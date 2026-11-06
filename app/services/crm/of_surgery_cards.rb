# 🗂️ PONTA 3 (22/10): card em "Cirurgia Agendada" de cirurgia que NÃO vai
# acontecer ali. O hub nunca marca "realizada" e a cancelada só ganhava
# etiqueta — em 22/10, de 636 pacientes nessa coluna só 13 tinham cirurgia
# marcada daqui para a frente.
#
# Regra (só o funil da CEVICO e só quem está em "Cirurgia Agendada"; card em
# outra coluna nunca é mexido aqui). Exame/consulta do hub não conta:
#   futura             → tem cirurgia ativa de hoje em diante: fica (certo)
#   operou_com_prova   → passou e tem prova (Crm::SurgeryProof: pagamento ou
#                        Agenda) → "Cirurgia Realizada" (até 30 dias) ou
#                        "Pós Operatório" (mais antiga)
#   operou_sem_prova   → passou e nada prova: fica (o hub mostra "sem prova")
#   aguardando_vencido → só "aguardando pagamento" com a data passada: fica
#   cancelada          → todas canceladas ou faltou → "Não Fechou Ainda"
#   sem_item           → nenhuma cirurgia nossa no hub (a equipe pôs ali): fica
#
# settle!(catch_up: true) é a arrumação do passado (rake): a entrada na coluna
# nova fica com a data real e marcada como carga ('bulk'), fora dos
# indicadores. No dia a dia (sync) a entrada conta, com a data real, e só a
# cirurgia recente (2 dias) dispara as automações da coluna — como quando a
# equipe arrasta. Cancelada nunca dispara automação.
class Crm::OfSurgeryCards
  CLASSES = %w[futura operou_com_prova operou_sem_prova aguardando_vencido cancelada sem_item].freeze
  LABELS = {
    'futura' => 'tem cirurgia marcada daqui para a frente',
    'operou_com_prova' => 'já operou e tem prova (pagamento ou Agenda)',
    'operou_sem_prova' => 'a data passou, mas nada prova que operou',
    'aguardando_vencido' => 'só "aguardando pagamento" com a data passada',
    'cancelada' => 'cirurgia cancelada ou faltou',
    'sem_item' => 'sem cirurgia da CEVICO no hub'
  }.freeze
  FIRE_WINDOW_DAYS = 2
  TZ = 'America/Sao_Paulo'.freeze

  Row = Struct.new(:card, :klass, :target, :surgery, keyword_init: true)

  def initialize(account, pipeline:, own_provider:)
    @account = account
    @pipeline = pipeline
    @own = own_provider.to_s.strip.downcase
  end

  # cards em "Cirurgia Agendada" (todos, ou só destes contatos) com a classe e o destino
  def rows(contact_ids: nil) # rubocop:disable Metrics/CyclomaticComplexity
    return [] if booked_stage.nil? || @own.blank?

    cards = Crm::Contact.where(pipeline_id: @pipeline.id, stage_id: booked_stage.id)
    cards = cards.where(contact_id: contact_ids) if contact_ids
    cards = cards.to_a
    items = own_surgeries(cards.map(&:contact_id))
    proofs = Crm::SurgeryProof.new(@account).call(items.values.flatten.select(&:concluida?))
    cards.map { |card| classify(card, items[card.contact_id] || [], proofs) }
  end

  def self.tally(rows)
    CLASSES.index_with { |k| rows.count { |r| r.klass == k } }
  end

  # move quem tem destino; devolve as linhas movidas (ou que seriam, em dry)
  def settle!(contact_ids: nil, dry: false, catch_up: false, silent: false)
    moving = rows(contact_ids: contact_ids).select(&:target)
    return moving if dry

    moving.each do |row|
      move!(row, catch_up: catch_up, silent: silent)
    rescue StandardError => e
      Rails.logger.warn "[Crm::OfSurgeryCards] card #{row.card.id}: #{e.message}"
    end
  end

  private

  def classify(card, items, proofs) # rubocop:disable Metrics/CyclomaticComplexity
    today = Crm::OftalmofacilSurgery.today_sp
    active = items.select { |s| %w[agendada aguardando_pagamento].include?(s.status_kind) }
    done = items.select(&:concluida?).sort_by(&:surgery_date)
    klass = class_of(items, active, done, proofs, today)
    surgery = klass == 'operou_com_prova' ? done.reverse.find { |s| proofs[s.id] } : items.max_by { |s| s.surgery_date || Date.new(1900) }
    Row.new(card: card, klass: klass, target: target_for(klass, surgery, today), surgery: surgery)
  end

  def class_of(items, active, done, proofs, today) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'sem_item' if items.empty?
    return 'futura' if active.any? { |s| s.surgery_date.nil? || s.surgery_date >= today }
    return 'operou_com_prova' if done.any? { |s| proofs[s.id] }
    return 'operou_sem_prova' if done.any?
    return 'aguardando_vencido' if active.any?

    'cancelada'
  end

  def target_for(klass, surgery, today)
    case klass
    when 'operou_com_prova'
      surgery.surgery_date >= today - Crm::OftalmofacilSyncService::RECENT_DAYS ? realized_stage || postop_stage : postop_stage
    when 'cancelada' then not_closed_stage
    end
  end

  # só CIRURGIA da CEVICO (exame, consulta, retorno e pós-op do hub ficam de fora)
  def own_surgeries(contact_ids)
    Crm::OftalmofacilSurgery.where(account_id: @account.id, contact_id: contact_ids)
                            .where('LOWER(provider_name) LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(@own)}%")
                            .to_a.select(&:cirurgia?).group_by(&:contact_id)
  end

  def move!(row, catch_up:, silent:)
    card = row.card
    previous = card.stage
    at = entered_time(row)
    Crm::Stamp.with(via: 'sync') { card.update!(stage_id: row.target.id) }
    log = Crm::StageLog.where(crm_contact_id: card.id, stage_id: row.target.id).order(entered_at: :desc).first
    if at && at < Time.current
      log&.update_columns(entered_at: at) # rubocop:disable Rails/SkipsModelValidations
      card.update_column(:stage_moved_at, at) # rubocop:disable Rails/SkipsModelValidations
    end
    log&.update_columns(event_type: Crm::StageLogBulk::BULK) if catch_up # rubocop:disable Rails/SkipsModelValidations
    fire!(card, row, previous) unless silent || catch_up
  end

  # realizada = dia da cirurgia (meio-dia); cancelada = quando mudou lá
  def entered_time(row)
    return row.surgery&.local_time('12:00') if row.klass == 'operou_com_prova'

    row.surgery&.of_modified_at
  end

  def fire!(card, row, previous)
    return unless row.klass == 'operou_com_prova'
    return if row.surgery.surgery_date < Crm::OftalmofacilSurgery.today_sp - FIRE_WINDOW_DAYS

    CrmAutomationTriggerService.new(crm_contact: card, new_stage: row.target, previous_stage: previous,
                                    event_type: 'card_entered').call
  rescue StandardError => e
    Rails.logger.warn "[Crm::OfSurgeryCards] automações: #{e.message}"
  end

  def stages
    @stages ||= @pipeline.stages.order(:position).to_a
  end

  def stage_named(pattern)
    stages.find { |s| s.name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.match?(pattern) }
  end

  def booked_stage = @booked_stage ||= stage_named(/cirurgia agendada/)
  def realized_stage = @realized_stage ||= stage_named(/cirurgia realizada/)
  def postop_stage = @postop_stage ||= stage_named(/pos.?operat/)
  def not_closed_stage = @not_closed_stage ||= stage_named(/nao fechou/)
end
