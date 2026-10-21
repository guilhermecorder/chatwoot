# 🧹 item 345 (14/10): LIMPEZA DO "AGENDAMENTO FALSO". Entre 13/10 (Rodada 5
# da auditoria, #17: toda etiqueta do sistema passou a disparar automação) e a
# tarde de 14/10, a automação "Ag. Consulta – Google" estava SEM filtro de
# etiqueta: cada etiqueta de robô (refrativa, att_encerrado…) jogava o lead de
# Envio de Orçamento para Agendamento de Consulta — 86 disparos, taxa de
# agendamento em 81,5%, conversões falsas no Google e vídeo "Como será a
# consulta?" para quem nem marcou.
#
# Para cada disparo da automação no período, acha a ENTRADA que ele causou na
# coluna de agendamento e decide:
#   real   o paciente marcou consulta de verdade perto dali (de 2 dias antes até
#          30 min depois da entrada) → fica como está
#   falsa  sem consulta → a entrada sai dos indicadores (event_type
#          'automacao_errada'; continua no histórico do paciente). Se o card
#          AINDA está parado ali por causa dela (nada aconteceu depois) e o
#          paciente não tem consulta futura, ele VOLTA para a coluna de onde a
#          automação o tirou — quieto: sem automação, sem Agenda, sem mensagem;
#          a volta também não conta como "Entrou em…" ('corrigido').
#
# Só lê até aplicar: Crm::FalseBookingCleanup.plan(...) é a simulação;
# apply!(plan) grava. Rake: cevico:agendamento_falso (DRY=1 → DRY=0).
module Crm::FalseBookingCleanup
  WRONG = 'automacao_errada'.freeze
  FIXED = 'corrigido'.freeze
  MATCH_WINDOW = 20.seconds # disparo da automação × entrada que ele gravou
  CONSULT_BEFORE = 2.days
  CONSULT_AFTER = 30.minutes
  CONVERSION_ACTIONS = %w[google_ads_conversion meta_ads_event].freeze

  Row = Struct.new(:fire, :card, :log, :consult, :back, keyword_init: true) do
    def real?
      consult.present?
    end
  end

  module_function

  def target_stage(automation)
    automation.stage.pipeline.stages.find_by(id: automation.action_config&.dig('target_stage_id'))
  end

  def plan(automation, since)
    target = target_stage(automation)
    return [] if target.nil?

    rows = Crm::AutomationLog.where(automation_id: automation.id, status: 'fired').where('created_at >= ?', since)
                             .order(:id).filter_map { |fire| row_for(fire, target) }
    rows.uniq { |row| row.log.id }
  end

  def row_for(fire, target)
    card = Crm::Contact.find_by(contact_id: fire.contact_id, pipeline_id: target.pipeline_id)
    return nil unless card

    at = fire.fired_at || fire.created_at
    log = card.stage_logs.where(stage_id: target.id, event_type: Crm::StageLogBulk::ENTERED,
                                entered_at: (at - MATCH_WINDOW)..(at + MATCH_WINDOW)).order(:entered_at).first
    return nil unless log

    consult = consult_near(card, log.entered_at)
    Row.new(fire: fire, card: card, log: log, consult: consult, back: !consult && still_parked?(card, log, target))
  end

  # consulta marcada de verdade perto da entrada (a que justificaria o card ali)
  def consult_near(card, entered_at)
    card.pipeline.account.tasks.where(contact_id: card.contact_id, task_type: 'consulta', canceled_at: nil)
        .where(created_at: (entered_at - CONSULT_BEFORE)..(entered_at + CONSULT_AFTER)).order(:created_at).first
  end

  # o card ainda está na coluna por causa DESTA entrada e o paciente não tem
  # consulta futura (se tiver, alguém marcou depois — o card fica)
  def still_parked?(card, log, target)
    return false unless card.stage_id == target.id
    return false if card.stage_logs.exists?(['entered_at > ?', log.entered_at])

    !card.pipeline.account.tasks.where(contact_id: card.contact_id, task_type: 'consulta', canceled_at: nil)
         .exists?(['due_at > ?', Time.current])
  end

  # conversões (Google/Meta) que saíram junto com as entradas falsas
  def conversions_for(rows) # rubocop:disable Metrics/AbcSize
    falsas = rows.reject(&:real?)
    return [] if falsas.empty?

    automations = Crm::Automation.where(stage_id: falsas.first.log.stage_id, action_type: CONVERSION_ACTIONS).to_a
    falsas.flat_map do |row|
      Crm::AutomationLog.where(automation_id: automations.map(&:id), contact_id: row.card.contact_id, status: 'fired')
                        .where(created_at: (row.log.entered_at - 1.minute)..(row.log.entered_at + 10.minutes))
                        .map { |log| [automations.detect { |a| a.id == log.automation_id }, log, row] }
    end
  end

  # grava: entradas falsas fora dos indicadores + volta dos cards parados
  def apply!(automation, rows)
    back_to = automation.stage
    moved = 0
    rows.reject(&:real?).each do |row|
      row.log.update_column(:event_type, WRONG) # rubocop:disable Rails/SkipsModelValidations
      next unless row.back

      Crm::CardRouter.bypass('carga') { row.card.update!(stage_id: back_to.id) }
      row.card.stage_logs.where(stage_id: back_to.id).order(:id).last&.update_column(:event_type, FIXED) # rubocop:disable Rails/SkipsModelValidations
      moved += 1
    end
    { marked: rows.count { |row| !row.real? }, moved: moved }
  end
end
