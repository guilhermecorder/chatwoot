# 🩹 CONSULTA DE PÓS-OPERATÓRIO ⇄ coluna "Consulta Pós Op" (21/10, pedido do
# Guilherme: "quando as consultas de pós op forem agendadas na agenda, o lead
# vai para essa coluna — todas as consultas de pós op serão ali").
#
# Toda consulta do tipo pós-operatório (tasks.modality = 'pos_op') salva com
# data de hoje em diante — marcada pela equipe na Agenda, remarcada, ou gravada
# por um robô — leva o card do paciente para a coluna de consulta de pós-op,
# disparando as automações da coluna como se a equipe tivesse arrastado.
#
# Coluna: agenda_config.booking.pos_op_stage_id ou, sem isso, a primeira coluna
# do funil da CEVICO cujo nome tem "consulta" + "pós op" (sem acento, sem
# hífen). Sem a coluna, não faz nada.
# Fica de fora: paciente/consulta de parceiro (Oftalmofácil — regra de ouro: o
# funil deles não recebe automação da CEVICO) e o que vem do sync do hub
# (source 'oftalmofacil'), para uma carga não mover cards em massa.
# Nunca levanta exceção para quem chama: a consulta já está gravada.
class Crm::PosOpReflector
  MODALITY = 'pos_op'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  class << self
    # a consulta acabou de ser salva: é hora de levar o card?
    def relevant_change?(task)
      return false unless pos_op_task?(task)

      task.saved_change_to_id? || task.saved_change_to_modality? || task.saved_change_to_due_at? ||
        task.saved_change_to_canceled_at? || task.saved_change_to_contact_id? || task.saved_change_to_archived_at?
    end

    def pos_op_task?(task)
      task.present? && task.task_type == 'consulta' && task.modality == MODALITY &&
        task.canceled_at.nil? && task.archived_at.nil? && task.due_at.present? &&
        task.due_at >= TZ.now.beginning_of_day
    end

    def call(task)
      return nil unless pos_op_task?(task) && task.source != 'oftalmofacil'

      contact = own_contact(task)
      stage = contact && stage_for(task.account)
      stage && move_card(contact, stage)
    rescue StandardError => e
      Rails.logger.error "[Crm::PosOpReflector] consulta #{task&.id}: #{e.message}"
      nil
    end

    # a PRÓXIMA consulta do paciente é de pós-op? (o Crm::BookingSideEffects e
    # o Crm::ConfirmationReflector usam para não puxar o card para o
    # agendamento / confirmada — ele fica em "Consulta Pós Op")
    def next_is_pos_op?(account, contact)
      return false if account.blank? || contact.blank?

      nxt = account.tasks.where(contact_id: contact.id, task_type: 'consulta', canceled_at: nil, archived_at: nil)
                   .where(due_at: TZ.now.beginning_of_day..).order(:due_at).first
      nxt&.modality == MODALITY && stage_for(account).present?
    end

    # confirmar consulta de pós-op (paciente da CEVICO) não move o card: ele fica
    # em "Consulta Pós Op" — usado pelo Crm::ConfirmationReflector
    def keeps_card?(account, task, contact)
      task.modality == MODALITY && stage_for(account).present? &&
        !Crm::PartnerGuard.partner_task?(task) && !Crm::PartnerGuard.partner_contact?(contact)
    end

    def stage_for(account)
      stages = own_stages(account)
      configured = (CrmSetting.find_by(account: account)&.agenda_config || {}).dig('booking', 'pos_op_stage_id').presence&.to_i
      (configured && stages.find_by(id: configured)) ||
        stages.order('crm_pipelines.position, crm_stages.position').find { |s| pos_op_name?(s.name) }
    end

    def pos_op_name?(name)
      plain = name.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z]/, '')
      plain.include?('consulta') && plain.include?('posop')
    end

    private

    # paciente da CEVICO dono da consulta (parceiro = nil: o funil deles não recebe automação nossa)
    def own_contact(task)
      return nil if Crm::PartnerGuard.partner_task?(task)

      contact = task.contact || Task.match_contact(task.account, task.phone)
      contact unless contact.blank? || Crm::PartnerGuard.partner_contact?(contact)
    end

    # colunas dos funis da CEVICO (sem o funil do parceiro)
    def own_stages(account)
      stages = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id })
      partner = Crm::PartnerGuard.partner_pipeline_id(account)
      partner ? stages.where.not(pipeline_id: partner) : stages
    end

    def move_card(contact, stage)
      card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
      if card.nil?
        card = Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id)
        CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, event_type: 'card_entered').call
        return stage.name
      end
      return nil if card.stage_id == stage.id

      previous = card.stage
      card.update!(stage_id: stage.id)
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, previous_stage: previous, event_type: 'card_entered').call
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous, previous_stage: previous, event_type: 'card_left').call if previous
      stage.name
    end
  end
end
