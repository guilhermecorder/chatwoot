# 📣 item 345 (14/10): cada caixa do WhatsApp da clínica é uma conta do
# WhatsApp (WABA) DIFERENTE, e a Meta só aceita evento de MENSAGEM (lead que
# veio de anúncio click-to-WhatsApp) no conjunto de dados LIGADO àquela conta.
# Mandado para o conjunto do site, ela responde "Não há uma conta do WhatsApp
# Business vinculada a este conjunto de dados" (código 100, subcode 2804132).
#
# Aqui mora:
#   · achar (GET /{waba}/dataset) ou criar (POST /{waba}/dataset) o conjunto
#     de cada conta — guardado em meta_ads_config['waba_datasets'] (a tela de
#     Integrações mostra) e, se a Meta recusar, uma pausa de 1h no cache para
#     não bater na Meta a cada automação;
#   · a ordem dos tokens para mandar o evento: o da API de Conversões
#     ("sistema") primeiro; se a Meta recusar por PERMISSÃO, o da própria caixa
#     ("caixa") — e lembra por 12h qual funcionou em cada conta;
#   · a cerca dos parceiros: conta do WhatsApp de caixa do Oftalmofácil nunca
#     recebe evento da CEVICO.
# Tokens nunca vão para log nem para a resposta (só o rótulo sistema/caixa).
class Crm::MetaWabaDatasets
  TOKEN_TTL = 12.hours
  FAIL_TTL = 1.hour
  JSON_HEADERS = { 'Content-Type' => 'application/json' }.freeze
  NO_WABA_LINKED_SUBCODE = 2_804_132
  AUTH_MESSAGES = /does not have permission|unsupported (post|get) request|does not exist|missing permissions/i

  attr_reader :last_error

  class << self
    def graph_url
      MetaAdsConversionsService::GRAPH_API_URL
    end

    # POST /{conjunto}/events — devolve { ok:, parsed:, error:, auth_error: }
    def post_events(target_id, token, payload)
      response = HTTParty.post("#{graph_url}/#{target_id}/events",
                               query: { access_token: token }, body: payload.to_json, headers: JSON_HEADERS, timeout: 15)
      parsed = parse(response)
      return { ok: true, parsed: parsed } if response.success?

      { ok: false, parsed: parsed, error: error_text(parsed, response.code), auth_error: auth_error?(parsed['error']) }
    end

    # recusa por TOKEN/PERMISSÃO (vale tentar o outro token) × recusa do
    # evento em si (parâmetro inválido, conjunto sem WABA…)
    def auth_error?(error)
      return false unless error.is_a?(Hash)
      return false if error['error_subcode'].to_i == NO_WABA_LINKED_SUBCODE

      code = error['code'].to_i
      [10, 190].include?(code) || (200..299).cover?(code) || error['message'].to_s.match?(AUTH_MESSAGES)
    end

    # o "Invalid parameter" da Meta diz pouco: o error_user_msg explica
    def error_text(parsed, http_code)
      err = parsed.is_a?(Hash) ? parsed['error'] : nil
      return "HTTP #{http_code}" unless err.is_a?(Hash)

      text = [err['message'].presence, user_message(err)].compact.uniq.join(' — ')
      text += " (subcode #{err['error_subcode']})" if err['error_subcode'].present?
      text.presence || "HTTP #{http_code}"
    end

    def user_message(err)
      err['error_user_msg'].presence || err['error_user_title'].presence
    end

    def parse(response)
      parsed = response.parsed_response
      return parsed if parsed.is_a?(Hash)

      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end
  end

  def initialize(account, config = nil)
    @account = account
    @config = config || setting&.meta_ads_config || {}
  end

  # caixas do WhatsApp da CEVICO (sem as dos parceiros), uma por conta (WABA)
  def channels
    @channels ||= begin
      own = whatsapp_inboxes.reject { |inbox| partner_inbox_ids.include?(inbox.id) || waba_of(inbox).blank? }
      own.map { |inbox| { inbox: inbox, channel: inbox.channel, waba_id: waba_of(inbox) } }.uniq { |c| c[:waba_id] }
    end
  end

  def channel_for(waba)
    channels.find { |c| c[:waba_id] == waba.to_s }
  end

  # conta do WhatsApp usada por uma caixa dos parceiros (cerca do Oftalmofácil)
  def partner_waba?(waba)
    whatsapp_inboxes.any? { |inbox| partner_inbox_ids.include?(inbox.id) && waba_of(inbox) == waba.to_s }
  end

  # o que a tela mostra: caixa → conta → conjunto guardado
  def overview
    channels.map do |c|
      { inbox_id: c[:inbox].id, inbox_name: c[:inbox].name, waba_id: c[:waba_id], dataset_id: stored_datasets[c[:waba_id]] }
    end
  end

  # conjunto de dados da conta do WhatsApp; fresh: true (botão de teste)
  # ignora a pausa de 1h depois de uma recusa
  def dataset_id(waba, fresh: false)
    waba = waba.to_s
    return blocked('conta do WhatsApp não informada') if waba.blank?
    return blocked('conta do WhatsApp de caixa de parceiro — fica de fora') if partner_waba?(waba)

    stored = stored_datasets[waba]
    return stored if stored.present?
    return blocked(Rails.cache.read(fail_key(waba))) if !fresh && Rails.cache.read(fail_key(waba))

    resolve!(waba)
  end

  # manda o evento ao conjunto da conta: token preferido primeiro; se a Meta
  # recusar por permissão, tenta o outro uma vez
  def post_events(waba, dataset_id, payload)
    result = nil
    event_tokens(waba).each do |label, token|
      result = self.class.post_events(dataset_id, token, payload).merge(token: label)
      if result[:ok]
        Rails.cache.write(token_key(waba), label, expires_in: TOKEN_TTL)
        return result
      end
      break unless result[:auth_error]
    end
    result || { ok: false, error: 'Nenhum token disponível para esta conta do WhatsApp', auth_error: true }
  end

  private

  def setting
    @setting ||= CrmSetting.find_by(account: @account)
  end

  def whatsapp_inboxes
    @whatsapp_inboxes ||= @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id).to_a
  end

  def partner_inbox_ids
    @partner_inbox_ids ||= Crm::PartnerGuard.partner_inbox_ids(@account)
  end

  def waba_of(inbox)
    inbox.channel&.provider_config&.dig('business_account_id').to_s.presence
  end

  def inbox_token(waba)
    channel_for(waba)&.dig(:channel)&.provider_config&.dig('api_key').presence
  end

  def stored_datasets
    datasets = @config['waba_datasets']
    datasets.is_a?(Hash) ? datasets : {}
  end

  # para POSTAR eventos: o que funcionou da última vez; senão sistema → caixa
  def event_tokens(waba)
    preferred = Rails.cache.read(token_key(waba))
    tokens = [['sistema', @config['access_token'].presence], ['caixa', inbox_token(waba)]]
    tokens.select { |_, token| token }.uniq { |_, token| token }.sort_by { |label, _| label == preferred ? 0 : 1 }
  end

  # para ACHAR/CRIAR o conjunto: o token da caixa (o que funcionou em 14/10)
  # primeiro; o do sistema de reserva
  def lookup_tokens(waba)
    [inbox_token(waba), @config['access_token'].presence].compact.uniq
  end

  def resolve!(waba)
    @last_error = 'nenhum token para esta conta do WhatsApp'
    lookup_tokens(waba).each do |token|
      id = lookup(waba, token)
      next if id.blank?

      persist!(waba, id)
      Rails.cache.delete(fail_key(waba))
      return id
    end
    Rails.logger.warn "[MetaWabaDatasets] conta #{waba}: conjunto do WhatsApp não resolvido — #{@last_error}"
    Rails.cache.write(fail_key(waba), @last_error, expires_in: FAIL_TTL)
    nil
  end

  # GET devolve {"data":[{"id":…}]} (ou vazio); vazio → POST cria e devolve {"id":…}
  def lookup(waba, token)
    url = "#{self.class.graph_url}/#{waba}/dataset"
    response = HTTParty.get(url, query: { access_token: token }, timeout: 15)
    return failed(response) unless response.success?

    found = extract_id(self.class.parse(response))
    return found if found

    response = HTTParty.post(url, query: { access_token: token }, timeout: 15)
    response.success? ? extract_id(self.class.parse(response)) : failed(response)
  rescue StandardError => e
    @last_error = e.message.to_s.gsub(token.to_s, '[token]')
    nil
  end

  def extract_id(body)
    first = Array(body['data']).first
    id = first.is_a?(Hash) ? first['id'] : body['id']
    id.to_s.presence
  end

  def failed(response)
    @last_error = self.class.error_text(self.class.parse(response), response.code)
    nil
  end

  def blocked(reason)
    @last_error = reason
    nil
  end

  # grava junto do resto da config (com trava: a tela pode salvar ao mesmo tempo)
  def persist!(waba, id)
    return if setting.blank?

    setting.with_lock do
      cfg = (setting.meta_ads_config || {}).deep_dup
      cfg['waba_datasets'] = (cfg['waba_datasets'].is_a?(Hash) ? cfg['waba_datasets'] : {}).merge(waba => id)
      setting.update!(meta_ads_config: cfg)
      @config = @config.merge('waba_datasets' => cfg['waba_datasets'])
    end
  end

  def token_key(waba)
    "cevico:meta_waba_token:#{@account.id}:#{waba}"
  end

  def fail_key(waba)
    "cevico:meta_waba_dataset_fail:#{@account.id}:#{waba}"
  end
end
