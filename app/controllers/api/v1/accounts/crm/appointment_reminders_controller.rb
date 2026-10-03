# 🖐️ ENVIO MANUAL do lembrete de confirmação (item 320): o botão "Enviar agora
# para quem falta" do card (o lembrete inteiro, fora da hora) e o "Enviar" /
# "Reenviar" de cada paciente da última rodada. Mesmo acesso de quem configura
# os lembretes. A regra mora no Crm::AppointmentReminderSendJob#run_manual.
class Api::V1::Accounts::Crm::AppointmentRemindersController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:settings) }

  # POST /crm/appointment_reminders/run { regua: 'd2', task_id: (opcional) }
  def run
    result = Crm::AppointmentReminderSendJob.new.run_manual(
      Current.account, params[:regua].to_s, task_id: params[:task_id].presence&.to_i
    )
    state = CrmSetting.find_by(account: Current.account)&.agenda_config&.dig(Crm::AppointmentReminderSendJob::STATE_KEY) || {}
    render json: result.merge(state: state), status: result[:ok] ? :ok : :unprocessable_entity
  end
end
