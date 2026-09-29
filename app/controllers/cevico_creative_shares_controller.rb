# 🔗 Página PÚBLICA, só de leitura, com a análise de UM criativo (item 287).
# Abre sem login por um link com token assinado (Crm::CreativeShareLink):
# o token diz a conta, o anúncio, o período e até quando vale. Mostra só o
# que Crm::CreativeSharePayload libera — dados do ANÚNCIO, nunca de paciente.
# Token adulterado, vencido ou de anúncio que não existe mais → "link vencido".
class CevicoCreativeSharesController < ActionController::Base # rubocop:disable Rails/ApplicationController
  include Cevico::PublicSecurity

  layout false
  CACHE_TTL = 10.minutes

  before_action :no_index

  def show
    @link = Crm::CreativeShareLink.verify(params[:token])
    @payload = @link && payload_for(@link)
    return expired if @payload.nil?

    @expires_label = @link[:expires_at].in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y')
    respond_to do |format|
      format.html { render :show }
      format.json { render json: @payload.merge(expires_at: @link[:expires_at].iso8601) }
    end
  end

  private

  def no_index
    response.headers['X-Robots-Tag'] = 'noindex, nofollow, noarchive'
    response.headers['Referrer-Policy'] = 'no-referrer'
    response.headers['Cache-Control'] = 'private, no-store'
  end

  def expired
    respond_to do |format|
      format.html { render :expired, status: :gone }
      format.json { render json: { error: 'link vencido' }, status: :gone }
    end
  end

  # a análise é a mesma da tela interna; fica 10 min em cache por link
  def payload_for(link)
    account = Account.find_by(id: link[:account_id])
    return nil unless account

    Rails.cache.fetch("crm:creative_share:#{Digest::SHA256.hexdigest(params[:token].to_s)}", expires_in: CACHE_TTL) do
      detail = Crm::CreativeAnalyticsService.new(account: account, since_date: link[:since_date], until_date: link[:until_date])
                                            .detail(link[:ad_id])
      Crm::CreativeSharePayload.new(detail, since_date: link[:since_date], until_date: link[:until_date], finance: link[:finance])
                               .call.as_json
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
