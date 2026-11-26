# 🚪 PORTAL DE TERCEIROS (item 420, 26/11): a ÚNICA porta que um terceiro abre.
# Hoje serve o tipo 'agenda_medico' (a agenda particular de um médico, vista e
# marcada pela secretária dele). As regras do que ela vê e do que pode marcar
# moram em Crm::ThirdPartyAgenda; quem é terceiro, em Cevico::ThirdParty.
#
#   GET   crm/portal/me                → quem sou eu neste portal (ou "acesso encerrado")
#   GET   crm/portal?from&to           → a agenda do período + indicadores
#   POST  crm/portal/appointments      → marcar
#   PATCH crm/portal/appointments/:id  → editar, remarcar, confirmar, cancelar, presença
#
# O administrador pode ABRIR o portal de um terceiro para conferir como ele
# vê (`?as=<user_id>`), só leitura: quem marca é sempre o próprio terceiro.
class Api::V1::Accounts::Crm::PortalController < Api::V1::Accounts::BaseController
  before_action :require_portal!, except: [:me]
  before_action :forbid_preview_writes!, only: %i[create update]
  after_action :stamp_last_seen, only: [:show]

  def me
    render json: {
      third_party: portal_third&.public_json,
      preview: admin_preview?,
      user: { id: Current.user.id, name: Current.user.name },
      account: { id: Current.account.id, name: Cevico::Company.for(Current.account).name }
    }
  end

  def show
    render json: agenda.payload(from: params[:from], to: params[:to]).merge(preview: admin_preview?)
  end

  def create
    task = agenda.create!(appointment_params)
    render json: agenda.appointment_json(task), status: :created
  rescue Crm::ThirdPartyAgenda::Refused => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    task = agenda.find(params[:id])
    return render json: { error: 'Consulta não encontrada.' }, status: :not_found if task.nil?

    agenda.update!(task, appointment_params)
    render json: agenda.appointment_json(task.reload)
  rescue Crm::ThirdPartyAgenda::Refused => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def agenda
    @agenda ||= Crm::ThirdPartyAgenda.new(Current.account, portal_third, Current.user)
  end

  # o terceiro desta requisição: a própria pessoa — ou, para o administrador,
  # o terceiro que ele pediu para conferir (`as`)
  def portal_third
    return @portal_third if defined?(@portal_third)

    @portal_third = cevico_access.third_party || preview_third
  end

  def admin_preview?
    cevico_access.third_party.nil? && preview_third.present?
  end

  def preview_third
    return nil unless Current.account_user&.administrator? && params[:as].present?

    @preview_third ||= Cevico::ThirdParty.all(Current.account).find { |t| t.user_id == params[:as].to_i }
  end

  def require_portal!
    third = portal_third
    return if third&.active? && third.kind == 'agenda_medico'

    message = third ? 'Este acesso foi encerrado. Fale com a clínica.' : 'Esta área é só para acessos de terceiros.'
    render json: { error: message, closed: third.present? }, status: :forbidden
  end

  def forbid_preview_writes!
    return unless admin_preview?

    render json: { error: 'Você está só conferindo este portal. Quem marca é a própria pessoa.' }, status: :forbidden
  end

  def appointment_params
    params.permit(:name, :phone, :description, :due_at, :unit, :confirmed, :canceled, :attendance).to_h.symbolize_keys
  end

  # "último acesso" para o administrador ver na tela de Acessos (no máximo
  # uma gravação a cada 15 minutos)
  def stamp_last_seen
    third = cevico_access.third_party
    return if third.nil?

    last = third.raw['last_seen_at'].to_s
    return if last.present? && last > 15.minutes.ago.iso8601

    Cevico::ThirdParty.touch!(Current.account, Current.user.id)
  rescue StandardError => e
    Rails.logger.error "[portal#stamp_last_seen] #{e.class}: #{e.message}"
  end
end
