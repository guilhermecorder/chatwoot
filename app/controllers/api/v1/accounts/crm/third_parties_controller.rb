# 🚪 ACESSOS DE TERCEIROS — a parte do ADMINISTRADOR (item 420, 26/11).
# Criar, ajustar e encerrar o acesso de alguém de fora da equipe (ex.: a
# secretária particular de um médico). Conceder acesso nunca é delegável:
# tudo aqui é só administrador.
#
#   GET    crm/third_parties              → a lista + o que a tela precisa (médicos, unidades, faixas)
#   POST   crm/third_parties              → cria o login já marcado como terceiro (convite por e-mail)
#   PATCH  crm/third_parties/:user_id     → nome do acesso, médico, faixas liberadas, reabrir
#   DELETE crm/third_parties/:user_id     → ENCERRA o acesso (a pessoa não abre mais nada)
#   POST   crm/third_parties/:user_id/invite → reenvia o e-mail de convite
class Api::V1::Accounts::Crm::ThirdPartiesController < Api::V1::Accounts::BaseController
  before_action :require_administrator!
  before_action :third_user, only: %i[update destroy invite]

  EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  def index
    render json: admin_payload
  end

  def create # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    email = params[:email].to_s.strip.downcase
    name = params[:name].to_s.strip[0, 80]
    return refuse('Escreva o nome da pessoa.') if name.length < 2
    return refuse('Confira o e-mail.') unless email.match?(EMAIL)
    return refuse('Escolha o médico.') if params[:doctor].to_s.strip.blank?

    existing = User.from_email(email)
    if existing && Current.account.account_users.exists?(user_id: existing.id)
      return refuse('Esse e-mail já é de alguém da equipe. O terceiro precisa de um e-mail só dele.')
    end

    user = AgentBuilder.new(email: email, name: name, role: :agent, inviter: Current.user, account: Current.account).perform
    begin
      Cevico::ThirdParty.save!(Current.account, user.id, third_attrs.merge('active' => true), by: Current.user)
    rescue StandardError
      # sem a marcação a pessoa seria um atendente comum: desfaz o vínculo
      Current.account.account_users.find_by(user_id: user.id)&.destroy
      raise
    end
    render json: admin_payload, status: :created
  rescue AgentBuilder::LimitExceededError
    refuse('O limite de logins desta conta foi atingido.')
  end

  def update
    Cevico::ThirdParty.save!(Current.account, third_user.id, third_attrs, by: Current.user)
    third_user.update!(name: params[:name].to_s.strip[0, 80]) if params[:name].to_s.strip.length >= 2
    render json: admin_payload
  end

  # encerrar = continua marcado como terceiro (não vira atendente), mas o
  # portal fecha. As consultas que marcou continuam na Agenda, com o rastro.
  def destroy
    Cevico::ThirdParty.save!(Current.account, third_user.id, { 'active' => false }, by: Current.user)
    render json: admin_payload
  end

  def invite
    return refuse('Essa pessoa já criou a senha. Se esqueceu, ela usa "Esqueci a senha" na entrada.') if third_user.confirmed?

    third_user.send_confirmation_instructions
    render json: { ok: true }
  end

  private

  def refuse(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def third_user
    return @third_user if defined?(@third_user)

    uid = params[:id].to_i
    marked = Cevico::ThirdParty.user_ids(Current.account).include?(uid)
    @third_user = marked ? Current.account.users.find_by(id: uid) : nil
    render json: { error: 'Acesso não encontrado.' }, status: :not_found if @third_user.nil?
    @third_user
  end

  def third_attrs # rubocop:disable Metrics/AbcSize
    attrs = {}
    attrs['kind'] = params[:kind].to_s if params.key?(:kind)
    attrs['label'] = params[:label].to_s if params.key?(:label)
    attrs['doctor'] = params[:doctor].to_s if params.key?(:doctor)
    attrs['active'] = params[:active] if params.key?(:active)
    attrs['windows'] = Array(params[:windows]) if params.key?(:windows)
    attrs
  end

  def admin_payload # rubocop:disable Metrics/AbcSize
    company = Cevico::Company.for(Current.account)
    thirds = Cevico::ThirdParty.all(Current.account)
    users = Current.account.users.where(id: thirds.map(&:user_id)).index_by(&:id)
    admins = Current.account.account_users.where(role: :administrator).pluck(:user_id)
    {
      kinds: Cevico::ThirdParty::KINDS.map { |key, spec| { key: key, label: spec['label'], hint: spec['hint'] } },
      doctors: doctor_windows.keys,
      doctor_windows: doctor_windows,
      units: unit_options(company),
      list: thirds.filter_map { |third| third_json(third, users[third.user_id], admins) }
                  .sort_by { |row| [row[:active] ? 0 : 1, row[:name].to_s.downcase] }
    }
  end

  def third_json(third, user, admins) # rubocop:disable Metrics/AbcSize
    return nil if user.nil? # login apagado em Agentes: a marcação fica órfã e some da lista

    made = Current.account.tasks.external.where(creator_id: user.id)
    {
      user_id: user.id, name: user.name, email: user.email, confirmed: user.confirmed?,
      kind: third.kind, label: third.label, doctor: third.doctor, active: third.active?,
      windows: third.windows, created_at: third.raw['created_at'], last_seen_at: third.raw['last_seen_at'],
      # administrador nunca é barrado: se promoverem esta pessoa, a marcação deixa de valer
      ignored_admin: admins.include?(user.id),
      stats: { booked: made.count, upcoming: made.where(canceled_at: nil).where('due_at > ?', Time.current).count }
    }
  end

  # as faixas de cada médico na Agenda da clínica (para "copiar as faixas do médico")
  def doctor_windows
    @doctor_windows ||= Crm::AgendaSlots.windows(Current.account)
                                        .reject { |w| Crm::AgendaSlots.expired?(w) }
                                        .group_by { |w| w['doctor'].to_s }
                                        .reject { |doctor, _| doctor.blank? }
                                        .transform_values { |wins| wins.map { |w| w.slice('dow', 'start', 'end', 'unit', 'block') } }
  end

  def unit_options(company)
    list = company.units.reject { |u| u['key'] == 'online' }.map { |u| { key: u['key'], label: u['label'] } }
    return list if list.any?

    Crm::AgendaSlots::UNIT_LABELS.except('online').map { |key, label| { key: key, label: label } }
  end
end
