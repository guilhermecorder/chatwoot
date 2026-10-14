# 🧭 MIGRAÇÃO ENTRE AMBIENTES (item 341, 13/10). Pedido do Guilherme:
# "precisamos de algum comando para passar todo mundo que conversa na caixa de
# entrada oftalmofácil para o CRM de lá".
#
# Olha cada paciente com alguma evidência de outro ambiente (conversa na caixa
# 12, etiqueta of_, atributo parceiro, agendamento/card de parceiro, carimbo)
# que tem card num funil que NÃO é do ambiente dele, e separa em:
#   MOVER    está ancorado no parceiro → o card sai da CEVICO e vai para o
#            funil do parceiro, na coluna equivalente
#   MANTER   regra B: falou com a CEVICO antes (ou a Agenda marcou "CEVICO")
#   REVISAR  ancorado no parceiro, mas com sinal da casa que pede olho humano
#            (cirurgia da CATARATA_SP no hub, ou só o carimbo diz parceiro)
#
# Mover (por paciente, numa transação, sem automação e sem reflexo na Agenda):
# cria/anda o card no funil do parceiro (o mais adiantado fica), copia as
# datas, a entrada inicial do card novo NÃO conta como "hoje" (vira carga em
# massa, com a data original), o histórico de colunas do card antigo passa
# para o card novo carimbado como parceiro, o card da CEVICO sai do funil com
# rastro (remove_from_pipeline!), o paciente e os agendamentos dele (menos os
# marcados "CEVICO" na Agenda) ganham o carimbo do parceiro.
class Crm::EnvironmentMigration
  Row = Struct.new(:contact, :env_id, :bucket, :reason, :moves, keyword_init: true)
  BUCKETS = %w[MOVER MANTER REVISAR].freeze

  def initialize(account, contact_ids: nil, limit: nil)
    @account = account
    @contact_ids = contact_ids.presence
    @limit = limit.to_i.positive? ? limit.to_i : nil
  end

  # uma linha por paciente com card fora do ambiente dele (ou mantido na CEVICO pela regra B)
  def rows # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    @rows ||= begin
      ids = @contact_ids ? Array(@contact_ids).map(&:to_i) : Crm::Environments.partner_evidence_ids(@account)
      anchors = Crm::Environments.anchored_partner_map(@account, ids)
      own = Crm::Environments.own_id(@account)
      cards = Crm::Contact.where(contact_id: ids, pipeline_id: @account.crm_pipelines.select(:id))
                          .includes(:stage, :pipeline, :contact).order(:contact_id, :id).group_by(&:contact_id)
      list = cards.filter_map do |cid, list_cards|
        env = anchors[cid]
        outside = list_cards.reject { |c| env_of(c.pipeline_id) == (env || own) }
        next if outside.empty? && env

        if env.nil?
          own_cards = list_cards.select { |c| env_of(c.pipeline_id) == own }
          next if own_cards.empty?

          next Row.new(contact: list_cards.first.contact, env_id: own, bucket: 'MANTER', reason: keep_reason(cid),
                       moves: own_cards.map { |c| [c, nil] })
        end
        build_row(list_cards.first.contact, env, outside)
      end
      @limit ? list.first(@limit) : list
    end
  end

  def summary
    BUCKETS.index_with { |bucket| rows.count { |r| r.bucket == bucket } }
  end

  # DRY: uma linha por paciente
  def describe(row)
    contact = row.contact
    phone = contact.phone_number.to_s.gsub(/\D/, '')[-4..] || '----'
    moves = row.moves.map do |card, target|
      from = "#{card.pipeline.name} / #{card.stage.name}"
      target ? "#{from} → #{target.pipeline.name} / #{target.name}" : "#{from} (fica)"
    end
    format('%<id>-8s %<name>-28s …%<phone>s  %<bucket>-8s %<reason>s  ·  %<moves>s',
           id: contact.id, name: contact.name.to_s[0, 28], phone: phone, bucket: row.bucket, reason: row.reason,
           moves: moves.join(' | '))
  end

  # DRY=0: aplica só os MOVER; devolve quantos pacientes foram movidos
  def run!
    Crm::PartnerFunnel.ensure_stages!(@account)
    moved = rows.select { |r| r.bucket == 'MOVER' }.count { |row| move!(row) }
    Crm::PartnerGuard.forget!(@account)
    self.class.clear_kpi_caches!(@account)
    moved
  end

  def move!(row) # rubocop:disable Metrics/AbcSize
    Crm::CardRouter.bypass('carga') do
      Crm::Stamp.with(via: 'carga', source: row.env_id) do
        ActiveRecord::Base.transaction do
          row.moves.map(&:first).each do |card|
            move_card!(card, Crm::CardRouter.target_stage(@account, row.env_id, card.stage), row.env_id)
          end
          ::Contact.where(id: row.contact.id).update_all(cevico_source_id: row.env_id) # rubocop:disable Rails/SkipsModelValidations
          @account.tasks.where(contact_id: row.contact.id).where("tasks.origin IS NULL OR tasks.origin <> 'cevico'")
                  .update_all(cevico_source_id: row.env_id) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
    true
  rescue StandardError => e
    Rails.logger.error "[ambientes] paciente #{row.contact.id}: #{e.class}: #{e.message}"
    warn "ERRO paciente #{row.contact.id}: #{e.class}: #{e.message}"
    false
  end

  def self.clear_kpi_caches!(account)
    ["cevico:home:#{account.id}:*", "cevico:overview/#{account.id}/*", "cevico:overview:#{account.id}*",
     "cevico:kpibag:#{account.id}:*", "cevico:funnel:#{account.id}:*", 'cevico:crm:with_conversations:*'].each do |pattern|
      Rails.cache.delete_matched(pattern)
    rescue NotImplementedError, StandardError => e
      Rails.logger.warn "[ambientes] cache #{pattern}: #{e.message}"
    end
  end

  private

  def env_of(pipeline_id)
    Crm::Environments.environment_id_for_pipeline(@account, pipeline_id)
  end

  def build_row(contact, env, outside)
    moves = outside.map { |card| [card, Crm::CardRouter.target_stage(@account, env, card.stage, create: false)] }
    review = review_reason(contact, env)
    bucket = review ? 'REVISAR' : 'MOVER'
    bucket = 'REVISAR' if moves.any? { |_card, target| target.nil? }
    Row.new(contact: contact, env_id: env, bucket: bucket, reason: review || evidence(contact), moves: moves)
  end

  def move_card!(card, target, env_id) # rubocop:disable Metrics/AbcSize
    moved_at = card.stage_moved_at || card.created_at
    partner = Crm::Contact.find_by(contact_id: card.contact_id, pipeline_id: target.pipeline_id)
    if partner.nil?
      partner = Crm::Contact.create!(contact_id: card.contact_id, pipeline_id: target.pipeline_id, stage_id: target.id,
                                     origin: card.origin.presence || 'oftalmofacil', value: card.value, assignee_id: card.assignee_id,
                                     procedure_of_interest: card.procedure_of_interest, notes: card.notes)
      partner.update_columns(created_at: card.created_at, stage_moved_at: moved_at) # rubocop:disable Rails/SkipsModelValidations
      quiet_last_log!(partner, moved_at)
    elsif partner.stage&.position.to_i < target.position.to_i
      partner.update!(stage_id: target.id)
      partner.update_columns(stage_moved_at: moved_at) # rubocop:disable Rails/SkipsModelValidations
      quiet_last_log!(partner, moved_at)
    end

    now = Time.current
    card.stage_logs.where(left_at: nil).find_each { |log| log.close!(now) }
    Crm::StageLog.where(crm_contact_id: card.id)
                 .update_all(crm_contact_id: partner.id, cevico_source_id: env_id, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    card.reload.remove_from_pipeline!
  end

  # a entrada que o card novo/andado acabou de ganhar não é "entrou hoje":
  # vira carga em massa com a data original
  def quiet_last_log!(partner, moved_at)
    log = partner.stage_logs.order(:id).last
    log&.update_columns(entered_at: moved_at, event_type: Crm::StageLogBulk::BULK) # rubocop:disable Rails/SkipsModelValidations
  end

  # por que fica na CEVICO (regra B)
  def keep_reason(contact_id)
    return 'Agenda marcou o agendamento como CEVICO' if @account.tasks.exists?(contact_id: contact_id, origin: 'cevico')

    first = Crm::Environments.own_evidence_times(@account, [contact_id]).filter_map { |times| times[contact_id] }.min
    "regra B: falou com a CEVICO antes#{first ? " (#{first.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')})" : ''}"
  end

  # sinais da casa que pedem olho humano antes de mover
  def review_reason(contact, env)
    own_name = Crm::PartnerGuard.own_provider_name(@account)
    if own_name.present? &&
       Crm::OftalmofacilSurgery.where(account_id: @account.id, contact_id: contact.id).exists?(['LOWER(provider_name) LIKE ?', "%#{own_name}%"])
      return "tem cirurgia da #{own_name.upcase} no hub"
    end
    return 'só o carimbo diz que é de outro ambiente' if evidence_list(contact, env) == ['carimbo']

    nil
  end

  def evidence(contact)
    evidence_list(contact, nil).join(', ').presence || 'evidência de parceiro'
  end

  def evidence_list(contact, _env) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    list = []
    inboxes = Crm::Environments.partner_inbox_ids(@account)
    first = inboxes.any? && @account.conversations.where(contact_id: contact.id, inbox_id: inboxes).order(:created_at).first
    list << "conversou pela caixa «#{first.inbox&.name}» em #{first.created_at.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')}" if first
    list << 'etiqueta of_' if contact.label_list.any? { |l| l.to_s.start_with?(Crm::PartnerGuard::LABEL_PREFIX) }
    list << 'atributo parceiro' if (contact.additional_attributes || {})['parceiro'].present?
    pipelines = Crm::Environments.partner_pipeline_ids(@account)
    list << 'card no funil do parceiro' if pipelines.any? && Crm::Contact.exists?(contact_id: contact.id, pipeline_id: pipelines)
    list << 'agendamento de parceiro' if Crm::Environments.partner_task_scope(@account, [contact.id]).exists?
    list << 'carimbo' if list.empty? && contact.cevico_source_id.present? && contact.cevico_source_id != Crm::Environments.own_id(@account)
    list
  end
end
