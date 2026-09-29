# ✅ CONFIRMOU A CONSULTA ⇄ coluna "Consulta Confirmada" (item 300, 30/09).
# Pedido do Guilherme: "ele responde SIM para a mensagem de confirmação e entra
# na coluna consulta confirmada" — e a Agenda mostra o selo de confirmado.
#
# Dois sentidos, para o selo aparecer venha a confirmação de onde vier:
#   · call        — a consulta foi confirmada (SIM ao lembrete ou a equipe marcou
#                   na Agenda) → o card anda para "Consulta Confirmada".
#                   Paciente do Oftalmofácil: funil do Oftalmofácil, sem
#                   automação. Paciente da CEVICO: funil da CEVICO, disparando as
#                   automações da coluna como se a equipe tivesse arrastado.
#   · from_stage  — o card ENTROU na coluna "Consulta Confirmada" (equipe
#                   arrastou ou o N8N moveu) → a próxima consulta do paciente
#                   ganha o confirmado.
#
# Coluna da CEVICO: agenda_config.booking.confirmed_stage_id ou, sem isso, a
# coluna chamada "Consulta Confirmada". O card nunca volta para trás (quem já
# está em Consulta Realizada, Cirurgia… fica onde está) — só sai de "Não foi à
# consulta" porque remarcou. Nunca levanta exceção para quem chama.
class Crm::ConfirmationReflector
  STAGE_LIKE = 'consulta confirmada'.freeze
  WINDOW_DAYS = 8
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  class << self
    def call(account:, task:)
      contact = task.contact || Task.match_contact(account, task.phone)
      return nil if contact.blank?

      if Crm::PartnerGuard.partner_task?(task) || Crm::PartnerGuard.partner_contact?(contact)
        Crm::PartnerFunnel.place!(account, contact, :confirmed)
      else
        move_own_card(account, contact)
      end
    rescue StandardError => e
      Rails.logger.error "[Crm::ConfirmationReflector] consulta #{task&.id}: #{e.message}"
      nil
    end

    def confirmed_stage?(stage)
      return false if stage.blank?

      account = stage.pipeline&.account
      configured = configured_stage_id(account)
      return stage.id == configured if configured && stage.pipeline_id != Crm::PartnerGuard.partner_pipeline_id(account)

      normalize(stage.name).include?(STAGE_LIKE)
    end

    def from_stage(card)
      return nil unless confirmed_stage?(card.stage)

      contact = card.contact
      today = TZ.now.beginning_of_day
      task = contact.account.tasks
                    .where(contact_id: contact.id, task_type: 'consulta', canceled_at: nil, archived_at: nil, confirmed_at: nil)
                    .where(due_at: today..(today + WINDOW_DAYS.days))
                    .where(attendance: [nil, ''])
                    .order(:due_at).first
      task&.update!(confirmed_at: Time.current, declined_at: nil)
      task
    rescue StandardError => e
      Rails.logger.error "[Crm::ConfirmationReflector] card #{card&.id}: #{e.message}"
      nil
    end

    private

    def configured_stage_id(account)
      return nil if account.blank?

      (CrmSetting.find_by(account: account)&.agenda_config || {}).dig('booking', 'confirmed_stage_id').presence&.to_i
    end

    def own_stage(account)
      stages = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id })
      partner = Crm::PartnerGuard.partner_pipeline_id(account)
      stages = stages.where.not(pipeline_id: partner) if partner
      configured = configured_stage_id(account)
      (configured && stages.find_by(id: configured)) ||
        stages.where('crm_stages.name ILIKE ?', "%#{STAGE_LIKE}%").order('crm_pipelines.position, crm_stages.position').first
    end

    def move_own_card(account, contact)
      stage = own_stage(account)
      return nil if stage.nil?

      card = Crm::Contact.find_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
      if card.nil?
        card = Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id)
        CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, event_type: 'card_entered').call
        return stage.name
      end
      return nil if card.stage_id == stage.id || ahead?(account, card, stage)

      previous = card.stage
      card.update!(stage_id: stage.id)
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: stage, previous_stage: previous, event_type: 'card_entered').call
      CrmAutomationTriggerService.new(crm_contact: card, new_stage: previous, previous_stage: previous, event_type: 'card_left').call if previous
      stage.name
    end

    # já passou da confirmação (consulta realizada, cirurgia…)? "Não foi à
    # consulta" não conta: quem faltou e remarcou volta a confirmar
    def ahead?(account, card, stage)
      return false if card.stage.nil? || card.stage.position.to_i <= stage.position.to_i

      missed = (CrmSetting.find_by(account: account)&.agenda_config || {}).dig('attendance_stages', 'missed_stage_id').to_i
      card.stage_id != missed
    end

    def normalize(text)
      text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.squeeze(' ').strip
    end
  end
end
