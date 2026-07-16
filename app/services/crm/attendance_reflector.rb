# Reflexo da Agenda no CRM: compareceu / faltou / cirurgia indicada movem o
# card do paciente para as colunas configuradas em agenda_config
# .attendance_stages (modal "Janelas dos médicos" da Agenda), disparando as
# automações da coluna de destino. Usado pela conferência do dia (tasks) e
# pela conduta do médico (anotação clínica — Central do Paciente, Fase 2).
class Crm::AttendanceReflector
  def self.call(account:, task:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    cfg = CrmSetting.find_by(account: account)&.agenda_config || {}
    stages_cfg = cfg['attendance_stages'] || {}

    target_id =
      if task.task_type == 'cirurgia'
        # trilho de cirurgias: realizada / não veio têm colunas próprias
        { 'attended' => stages_cfg['surgery_done_stage_id'],
          'missed' => stages_cfg['surgery_missed_stage_id'] }[task.attendance]
      elsif task.surgery_indication == 'indicated'
        stages_cfg['indicated_stage_id']
      elsif task.attendance == 'missed'
        stages_cfg['missed_stage_id']
      elsif task.attendance == 'attended'
        stages_cfg['attended_stage_id']
      end
    return if target_id.blank?

    contact = task.contact || Task.match_contact(account, task.phone)
    return if contact.blank?

    card = Crm::Contact.joins(:pipeline)
                       .where(crm_pipelines: { account_id: account.id }, contact_id: contact.id)
                       .order('crm_pipelines.position').first
    return if card.blank?

    new_stage = Crm::Stage.joins(:pipeline)
                          .where(crm_pipelines: { account_id: account.id })
                          .find_by(id: target_id)
    return if new_stage.blank? || new_stage.id == card.stage_id

    previous_stage = card.stage
    card.update!(stage_id: new_stage.id, pipeline_id: new_stage.pipeline_id)
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: new_stage,
                                    previous_stage: previous_stage, event_type: 'card_entered').call
    CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous_stage,
                                    previous_stage: previous_stage, event_type: 'card_left').call
  rescue StandardError => e
    Rails.logger.error "[Crm::AttendanceReflector] task #{task.id}: #{e.message}"
  end
end
