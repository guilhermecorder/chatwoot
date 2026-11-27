class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  # 🔐 CEVICO (rodada 334): trava automática pelo catálogo de acessos
  # (só age nos controllers mapeados em Cevico::AccessCatalog::CONTROLLER_NODES)
  include Crm::AccessControl
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  around_action :switch_locale_using_account_locale
  # 👣 27/11 (LIFE): 1º e último acesso do dia de cada pessoa (Crm::PresenceTracker; grava no máximo a cada 5 min)
  after_action :cevico_mark_presence

  private

  def cevico_mark_presence
    Crm::PresenceTracker.touch!(Current.account, Current.user) if Current.user.is_a?(User)
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end
end
