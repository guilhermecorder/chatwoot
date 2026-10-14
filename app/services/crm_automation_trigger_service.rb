# Chamado pelo CrmContactsController quando um card muda de coluna
# ou quando uma etiqueta é adicionada/removida
class CrmAutomationTriggerService
  # Aceita crm_contact (Crm::Contact) ou contact (Contact legado)
  # label: etiqueta específica (para eventos label_added/label_removed)
  def initialize(crm_contact: nil, contact: nil, new_stage:, previous_stage: nil, event_type: 'card_entered', label: nil)
    @crm_contact    = crm_contact
    @contact        = crm_contact&.contact || contact
    @new_stage      = new_stage
    @previous_stage = previous_stage
    @event_type     = event_type
    @label          = label
  end

  # 🏷️ Rodada 5 da auditoria (#17): a etiqueta do CONTATO mudou de verdade
  # (qualquer caminho: telas do CRM, tela Contatos do Chatwoot, API/N8N,
  # automação, etiqueta da conversa que sobe ao contato). Dispara "Etiqueta
  # adicionada/removida" na coluna atual de CADA card do contato. Chamado pelo
  # Contact depois de gravar (after_commit) — não depende mais do navegador.
  def self.label_change!(contact, added: [], removed: [])
    events = { 'label_added' => Array(added), 'label_removed' => Array(removed) }.reject { |_event, labels| labels.empty? }
    return if contact.blank? || events.empty?

    Crm::Contact.joins(:pipeline, :stage).includes(:stage)
                .where(crm_pipelines: { account_id: contact.account_id }, contact_id: contact.id)
                .find_each do |card|
      events.each do |event, labels|
        labels.each do |label|
          new(crm_contact: card, new_stage: card.stage, previous_stage: card.stage, event_type: event, label: label).call
        end
      end
    end
  end

  # Mesma etiqueta + mesma automação + mesmo contato dentro desta janela =
  # um disparo só (o servidor e a automação "aplicar etiqueta" avisam o mesmo
  # evento quase ao mesmo tempo). Efeito aceito: tirar a etiqueta e pôr de
  # volta em menos de 2 minutos NÃO dispara a segunda adição. Se o
  # enfileiramento falhar, a marca é devolvida (o evento não se perde).
  LABEL_DEDUP_TTL = 2.minutes

  def self.label_dedup_key(event_type, automation_id, contact_id, label)
    "CRM_LABEL_TRIGGER::#{event_type}::#{automation_id}::#{contact_id}::#{label.to_s.strip.downcase}"
  end

  def call
    return unless @contact
    # 🧭 item 341: card que a cerca do ambiente mandou para o funil do parceiro
    # não dispara as automações da coluna da CEVICO que o caminho pediu
    return if @event_type == 'card_entered' && @crm_contact && @new_stage && @crm_contact.pipeline_id != @new_stage.pipeline_id

    automations = @new_stage.automations.where(active: true, trigger_type: trigger_type_for_event)

    # Filtra por label_filter se a automação especificou uma etiqueta específica
    if @label.present?
      automations = automations.select do |a|
        filter = a.action_config&.dig('label_filter')
        filter.blank? || filter.strip.downcase == @label.strip.downcase
      end
    end

    automations = quiet_safe(automations)

    automations.each do |automation|
      next unless first_label_event?(automation)

      enqueue(automation)
    end
  end

  private

  def enqueue(automation)
    schedule_at = automation.delay_minutes.to_i.positive? ? automation.delay_minutes.minutes.from_now : Time.current
    job = schedule_at <= Time.current ? CrmAutomationFireJob : CrmAutomationFireJob.set(wait_until: schedule_at)
    job.perform_later(automation.id, @contact.id, extra_payload)
  rescue StandardError
    release_label_mark(automation)
    raise
  end

  def label_event?
    @event_type.in?(%w[label_added label_removed]) && @label.present?
  end

  # 🛑 Rodada 5 (#17): agora TODA etiqueta posta pelo sistema dispara
  # (nao_perturbe, perda_*, NPS, agendamento…), inclusive nas automações
  # "Qualquer etiqueta". Quem está em silêncio (Crm::OptOut: nao_perturbe ou
  # perda_*) só recebe as ações internas (etiqueta, mover, avisar a equipe…):
  # nada de mensagem modelo, formulário, n8n, webhook ou conversão de anúncio.
  # Lado mais seguro — decisão final do Guilherme.
  def quiet_safe(automations)
    return automations unless label_event?

    automations = automations.to_a
    return automations if automations.empty? || !quiet_contact?

    automations.select { |a| CrmAutomationFireJob::PARTNER_SAFE_ACTIONS.include?(a.action_type) }
  end

  def quiet_contact?
    titles = Crm::OptOut.quiet_titles(@contact.account).map(&:downcase)
    @contact.label_list.any? { |l| titles.include?(l.to_s.downcase) }
  end

  def release_label_mark(automation)
    return unless label_event?

    Redis::LockManager.new.unlock(self.class.label_dedup_key(@event_type, automation.id, @contact.id, @label))
  end

  # 🏷️ #17: eventos de etiqueta passam por uma marca no Redis (contato +
  # etiqueta + automação). Quem chegar depois dentro da janela não dispara de
  # novo. Colunas (entrou/saiu) seguem como sempre.
  def first_label_event?(automation)
    return true unless label_event?

    key = self.class.label_dedup_key(@event_type, automation.id, @contact.id, @label)
    Redis::LockManager.new.lock(key, LABEL_DEDUP_TTL)
  end

  def trigger_type_for_event
    case @event_type
    when 'card_entered' then 'card_entered'
    when 'card_left'    then 'card_left'
    when 'label_added'  then 'label_added'
    when 'label_removed' then 'label_removed'
    end
  end

  def extra_payload
    payload = {
      event_type:     @event_type,
      previous_stage: @previous_stage ? { id: @previous_stage.id, name: @previous_stage.name } : {}
    }
    payload[:label] = @label if @label.present?
    payload
  end
end
