class Crm::CampaignRunJob < ApplicationJob
  queue_as :low

  # Meta aceita bem mais, mas 5 msg/s evita bloqueio por qualidade
  THROTTLE_SECONDS = 0.2
  # rodada longa não pode ser reenfileirada em paralelo; TTL generoso p/ campanhas grandes
  LOCK_TTL = 2.hours

  # 🚫 auditoria 10/2026 (#45): a Meta recusa a mensagem modelo DEPOIS de ela
  # ser gravada (modelo pausado, variável vazia, número inválido…) e a mensagem
  # fica `status: failed`. A campanha confere isso no fim da rodada e de novo
  # numa varredura 10 min depois (o aviso da Meta pode chegar por webhook):
  # o destinatário vira delivery_status 'failed' e os números da campanha
  # ('sent' × 'failed') passam a dizer a verdade. Não reenvia sozinho.
  SWEEP_DELAY = 10.minutes
  REFUSED_LIST_CAP = 50

  # mode 'sweep' = só a conferência das recusas (agendada pelo fim da rodada)
  def perform(campaign_id, mode = nil)
    campaign = Crm::Campaign.find_by(id: campaign_id)
    return if campaign.blank?
    return if mode != 'sweep' && !campaign.processing?

    # TRAVA: um restart do sidekiq (deploy) reenfileira este job. Sem a trava,
    # a 2ª instância recomeçava a campanha e reenviava pra base inteira.
    lock_manager = Redis::LockManager.new
    lock_key = "CRM_CAMPAIGN_RUN_LOCK::#{campaign.id}"
    return unless lock_manager.lock(lock_key, LOCK_TTL)

    begin
      mode == 'sweep' ? sweep_refused(campaign) : run_campaign(campaign)
    ensure
      lock_manager.unlock(lock_key)
    end
  end

  private

  def run_campaign(campaign)
    # quem JÁ recebeu nesta campanha (CampaignContact é a fonte da verdade) não
    # recebe de novo: retomada após deploy continua de onde parou, sem duplicar.
    already_sent = campaign.campaign_contacts.pluck(:contact_id).to_set
    contacts = campaign.resolve_audience
    stats = { 'total' => contacts.size, 'sent' => already_sent.size, 'skipped' => 0, 'failed' => 0 }
    campaign.update!(stats: stats, started_at: campaign.started_at || Time.current)

    deliver_all(campaign, contacts, stats, already_sent)

    settle_refused(campaign, stats)

    finish(campaign, stats)
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] campaign #{campaign.id} failed: #{e.message}"
    campaign.update(status: :failed, stats: (stats || {}).merge('error' => e.message), finished_at: Time.current)
  end

  def deliver_all(campaign, contacts, stats, already_sent)
    contacts.find_each do |contact|
      # ⏸ pausada/cancelada pela tela → para no próximo contato
      break if stopped_by_team?(campaign)

      process_contact(campaign, contact, stats, already_sent)
      persist_progress(campaign, stats)
      sleep THROTTLE_SECONDS
    end
  end

  # fim da rodada. ⏸ R3 da auditoria (#415): a equipe pausou no meio → guarda
  # o que já foi e NÃO marca como concluída (quem já recebeu fica registrado)
  def finish(campaign, stats)
    return campaign.update!(stats: stats) if stopped_by_team?(campaign)

    campaign.update!(status: :completed, stats: stats, finished_at: Time.current)
  end

  # a campanha deixou de estar "em envio" no banco (pausa pela tela)
  def stopped_by_team?(campaign)
    !Crm::Campaign.exists?(id: campaign.id, status: :processing)
  end

  def process_contact(campaign, contact, stats, already_sent)
    # já recebeu (esta rodada ou uma anterior interrompida) → nunca reenvia
    if already_sent.include?(contact.id)
      stats['skipped'] += 1
      return
    end

    conversation = Crm::SendTemplateService.new(source: campaign, contact: contact).perform
    if conversation.nil?
      stats['skipped'] += 1
      return
    end

    record_recipient(campaign, contact, conversation)
    already_sent << contact.id
    apply_label(campaign, contact)
    stats['sent'] += 1
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] contact #{contact.id}: #{e.message}"
    stats['failed'] += 1
  end

  def record_recipient(campaign, contact, conversation)
    Crm::CampaignContact.create!(
      campaign: campaign,
      contact: contact,
      conversation: conversation,
      sent_at: Time.current
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end

  def apply_label(campaign, contact)
    title = campaign.apply_label.to_s.strip.downcase
    return if title.blank?

    campaign.account.labels.find_or_create_by!(title: title)
    contact.label_list.add(title)
    contact.save!
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] label '#{title}' contact #{contact.id}: #{e.message}"
  end

  def persist_progress(campaign, stats)
    processed_count = stats['sent'] + stats['skipped'] + stats['failed']
    campaign.update_column(:stats, stats) if (processed_count % 10).zero?
  end

  # ── a Meta recusou (#45) ────────────────────────────────────────────────
  # fim da rodada: quem a Meta já recusou sai de 'sent'; 10 min depois confere de novo
  def settle_refused(campaign, stats)
    reconcile_refused(campaign, stats)
    self.class.set(wait: SWEEP_DELAY).perform_later(campaign.id, 'sweep')
  rescue StandardError => e
    # a varredura não agendada (Redis fora) não pode derrubar uma campanha que já saiu inteira
    Rails.logger.error "[Crm::CampaignRunJob] campaign #{campaign.id} varredura das recusas não agendada: #{e.message}"
  end

  # varredura agendada: relê os números gravados e confere de novo
  def sweep_refused(campaign)
    stats = (campaign.stats || {}).deep_dup
    return unless reconcile_refused(campaign, stats)

    campaign.update!(stats: stats)
  end

  # destinatários ainda 'sent' cuja mensagem modelo da campanha ficou failed:
  # viram 'failed' e saem de 'sent' nos números. Devolve true se mudou algo.
  def reconcile_refused(campaign, stats)
    rows = refused_rows(campaign)
    return false if rows.empty?

    Crm::CampaignContact.where(id: rows.map(&:first)).update_all(delivery_status: 'failed') # rubocop:disable Rails/SkipsModelValidations
    count_refused(stats, rows)
    drop_label(campaign, rows.map(&:last))
    true
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] campaign #{campaign.id} conferência das recusas: #{e.message}"
    false
  end

  # a etiqueta da campanha sai de quem a Meta recusou (revisão da Rodada 3):
  # ela quer dizer "recebeu" — audiências que excluem por etiqueta não podem
  # pular quem nunca recebeu
  def drop_label(campaign, contact_ids)
    title = campaign.apply_label.to_s.strip.downcase
    return if title.blank? || contact_ids.empty?

    campaign.account.contacts.where(id: contact_ids).find_each do |contact|
      contact.update!(label_list: contact.label_list - [title]) if contact.label_list.include?(title)
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::CampaignRunJob] campaign #{campaign.id} etiqueta dos recusados: #{e.message}"
  end

  def count_refused(stats, rows)
    errors = Crm::SendTemplateService.refused(rows.pluck(2))
    refused = rows.map { |_id, name, message_id, _contact_id| { 'name' => name, 'error' => errors[message_id] } }
    stats['sent'] = [stats['sent'].to_i - rows.size, 0].max
    stats['failed'] = stats['failed'].to_i + rows.size
    stats['meta_refused'] = (Array(stats['meta_refused']) + refused).first(REFUSED_LIST_CAP)
  end

  # [campaign_contact_id, nome, message_id, contact_id] — a mensagem da campanha é a
  # automática ('cevico_auto' = Campaign) gravada na conversa no instante do envio
  def refused_rows(campaign)
    Message.reorder(nil)
           .joins('INNER JOIN crm_campaign_contacts cc ON cc.conversation_id = messages.conversation_id')
           .joins('INNER JOIN contacts ON contacts.id = cc.contact_id')
           .where(cc: { campaign_id: campaign.id, delivery_status: 'sent' })
           .where(status: :failed, message_type: :outgoing)
           .where("messages.additional_attributes ->> 'cevico_auto' = ?", 'Campaign')
           # a mensagem é gravada no mesmo instante do sent_at (outra campanha na mesma conversa não conta)
           .where("messages.created_at BETWEEN cc.sent_at - interval '1 minute' AND cc.sent_at + interval '1 minute'")
           .distinct
           .pluck('cc.id', 'contacts.name', 'messages.id', 'cc.contact_id')
  end
end
