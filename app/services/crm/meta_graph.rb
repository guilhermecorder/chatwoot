# Cliente mínimo da Graph/Marketing API da Meta para a conta de anúncios
# configurada em CRM → Integrações → Meta Ads (meta_ads_config). Pagina por
# `paging.next` e devolve erros da Meta com a mensagem deles.
# CEVICO_META_SIMULATE=1 desvia tudo para o Crm::MetaSimulator (teste local).
class Crm::MetaGraph
  BASE_URI = 'https://graph.facebook.com'.freeze
  Error = Class.new(StandardError)

  def initialize(account:)
    @account = account
  end

  def configured?
    access_token.present? && ad_account_id.present?
  end

  # simulação: variável de ambiente OU token literal "simulate" na conta
  # (permite testar a tela no servidor local sem reiniciar contêiner)
  def simulate?
    ENV['CEVICO_META_SIMULATE'] == '1' || access_token == 'simulate'
  end

  def ad_account_id
    config['ad_account_id'].to_s.delete_prefix('act_')
  end

  # Percorre as páginas de uma edge da conta de anúncios (ex.: 'ads',
  # 'insights') e devolve todas as linhas de `data`.
  def fetch_all(edge, query, max_pages: 10)
    return Crm::MetaSimulator.new(account: @account).fetch_all(edge, query) if simulate?

    rows = []
    url = "#{BASE_URI}/#{api_version}/act_#{ad_account_id}/#{edge}"
    params = query.merge(access_token: access_token)

    max_pages.times do
      response = HTTParty.get(url, query: params, timeout: 30)
      raise Error, "#{edge}: #{extract_error(response)}" unless response.success?

      parsed = response.parsed_response
      rows.concat(Array(parsed['data']))
      next_url = parsed.dig('paging', 'next')
      break if next_url.blank?

      url = next_url
      params = nil # a URL "next" já carrega todos os parâmetros
    end

    rows
  end

  # Busca objetos pelo id — o caminho para anúncios APAGADOS na Meta, que
  # somem de /ads mas continuam legíveis por id. Até 50 ids por chamada;
  # se um lote falhar, tenta um a um e pula o que não existir mais.
  def fetch_objects(ids, fields)
    list = Array(ids).map(&:to_s).uniq
    return Crm::MetaSimulator.new(account: @account).fetch_objects(list, fields) if simulate?

    list.each_slice(50).with_object({}) do |slice, found|
      batch = get_objects(ids: slice.join(','), fields: fields) || one_by_one(slice, fields)
      batch.each { |id, obj| found[id.to_s] = obj if valid_object?(obj) }
    end
  end

  private

  # lote recusado (um id inexistente derruba o lote): tenta um a um
  def one_by_one(ids, fields)
    ids.index_with { |id| get_objects(ids: id, fields: fields)&.dig(id) }
  end

  def valid_object?(obj)
    obj.is_a?(Hash) && obj['id'].present?
  end

  def get_objects(query)
    response = HTTParty.get("#{BASE_URI}/#{api_version}/", query: query.merge(access_token: access_token), timeout: 30)
    response.success? ? response.parsed_response : nil
  rescue StandardError
    nil
  end

  def config
    @config ||= CrmSetting.find_by(account: @account)&.meta_ads_config || {}
  end

  def access_token
    config['access_token']
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  # mensagem + explicação que a Meta manda junto (error_user_msg) + códigos:
  # "Invalid parameter" sozinho não diz qual parâmetro
  def extract_error(response)
    err = response.parsed_response['error'] || {}
    parts = [err['message'], err['error_user_title'], err['error_user_msg']].compact.uniq
    codes = [err['code'], err['error_subcode']].compact.join('/')
    text = parts.join(' — ')
    text = "HTTP #{response.code}" if text.blank?
    codes.present? ? "#{text} (código #{codes})" : text
  rescue StandardError
    "HTTP #{response.code}"
  end
end
