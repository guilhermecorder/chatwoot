# Webhook de LEAD ADS do Meta (objeto "page", campo "leadgen"): cada resposta
# de formulário instantâneo chega aqui em tempo real. A rota carrega o
# account_id — a verificação usa o token gerado no card Meta Ads da conta.
# A assinatura (X-Hub-Signature-256) é exigida quando houver app secret
# configurado (campo do card ou FB_APP_SECRET global).
class Webhooks::MetaLeadsController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :events

  def events
    if params['object'].to_s.casecmp('page').zero?
      entries = params.to_unsafe_hash[:entry]
      ::Webhooks::MetaLeadsJob.perform_later(params[:account_id].to_i, entries) if entries.present?
      render json: :ok
    else
      Rails.logger.warn("Meta leads webhook: objeto inesperado #{params['object']}")
      head :unprocessable_entity
    end
  end

  private

  def account
    @account ||= Account.find_by(id: params[:account_id])
  end

  def meta_ads_config
    @meta_ads_config ||= (account && CrmSetting.find_by(account: account)&.meta_ads_config) || {}
  end

  def valid_token?(token)
    expected = meta_ads_config['leadgen_verify_token']
    expected.present? && token == expected
  end

  def meta_app_secrets
    [
      meta_ads_config['app_secret'],
      GlobalConfigService.load('FB_APP_SECRET', nil),
      GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
    ].compact_blank
  end

  def meta_signature_verification_required?
    meta_app_secrets.present?
  end
end
