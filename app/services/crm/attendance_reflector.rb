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

    new_stage = Crm::Stage.joins(:pipeline)
                          .where(crm_pipelines: { account_id: account.id })
                          .find_by(id: target_id)
    move_contact_to_stage(account: account, contact: contact, new_stage: new_stage)
  rescue StandardError => e
    Rails.logger.error "[Crm::AttendanceReflector] task #{task.id}: #{e.message}"
  end

  # 👓 fase 1 da Sua Ótica (22/10): o MIOLO do reflexo, agora reaproveitável —
  # a O.S. da ótica usa o mesmo caminho (Otica::CrmBridge). Comportamento da
  # clínica idêntico: o card mais antigo do contato (funil principal primeiro)
  # vai para a coluna; coluna de OUTRO funil = move/cria o card DAQUELE funil
  # (nunca troca o pipeline_id, que estourava o índice único); dispara as
  # automações de entrada e saída. Devolve o card movido (nil = nada a fazer).
  # create_if_missing: a clínica NÃO cria card por aqui (quem não tem card em
  # funil nenhum segue sem — como sempre foi); a ótica cria, porque o cliente
  # que nasce na venda precisa entrar no funil de pós-venda.
  def self.move_contact_to_stage(account:, contact:, new_stage:, create_if_missing: false) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if contact.blank? || new_stage.blank?

    card = Crm::Contact.joins(:pipeline)
                       .where(crm_pipelines: { account_id: account.id }, contact_id: contact.id)
                       .order('crm_pipelines.position').first
    # 👓 sem card em funil nenhum (cliente que nasceu na venda): nasce no funil da coluna
    return nil if card.blank? && !create_if_missing

    if card.blank?
      card = Crm::Contact.create!(contact_id: contact.id, pipeline_id: new_stage.pipeline_id, stage_id: new_stage.id)
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: new_stage, previous_stage: nil, event_type: 'card_entered').call
      return card
    end
    return nil if new_stage.id == card.stage_id

    previous_stage = card.stage
    moved_card =
      if new_stage.pipeline_id == card.pipeline_id
        card.update!(stage_id: new_stage.id)
        card
      else
        other = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: new_stage.pipeline_id)
        return nil if other.persisted? && other.stage_id == new_stage.id

        other.stage_id = new_stage.id
        other.save!
        other
      end

    CrmAutomationTriggerService.new(crm_contact: moved_card, new_stage: new_stage,
                                    previous_stage: previous_stage, event_type: 'card_entered').call
    CrmAutomationTriggerService.new(crm_contact: moved_card, new_stage: previous_stage,
                                    previous_stage: previous_stage, event_type: 'card_left').call
    moved_card
  end
end
