class Api::V1::Accounts::Conversations::DirectUploadsController < ActiveStorage::DirectUploadsController
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include AccessTokenAuthHelper
  include EnsureCurrentAccountHelper

  skip_before_action :verify_authenticity_token, if: :authenticate_by_access_token?

  around_action :handle_with_exception
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :current_account
  # 🚪 CEVICO item 420: este controller não herda do BaseController da conta
  # (é do ActiveStorage), então a trava do terceiro é repetida aqui
  before_action :cevico_third_party_guard
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :conversation

  def create
    return if @conversation.nil? || @current_account.nil?

    super
  end

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end

  def cevico_third_party_guard
    user = current_user || @resource
    return unless user.is_a?(User) && Cevico::ThirdParty.third_party?(Current.account, user, account_user: Current.account_user)

    render json: { error: 'Este acesso é restrito ao seu portal.', third_party: true }, status: :forbidden
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_id])
  end
end
