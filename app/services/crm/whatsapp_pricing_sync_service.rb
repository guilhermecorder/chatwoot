# 💸 item 303 (30/09): puxa da Meta a FATURA do WhatsApp (pricing_analytics):
# por dia × número × categoria × tipo de cobrança, volume e custo na moeda da
# conta (WABA). Uma chamada por WABA (várias caixas podem dividir a mesma).
# Cron diário + botão "Atualizar da Meta" na tela Gasto do WhatsApp.
class Crm::WhatsappPricingSyncService
  BASE_URI = 'https://graph.facebook.com'.freeze
  CHUNK_DAYS = 90 # a Meta limita o intervalo por chamada
  MAX_DAYS = 450

  def initialize(account:, days: 35)
    @account = account
    @days = days.to_i.clamp(1, MAX_DAYS)
  end

  def call # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    wabas = channels_by_waba
    return { ok: false, error: 'Nenhuma caixa do WhatsApp oficial (Cloud API) com conta e chave configuradas.' } if wabas.empty?

    rows = 0
    errors = []
    to = Time.zone.now.end_of_day
    from = (to - (@days - 1).days).beginning_of_day
    wabas.each do |waba_id, channel|
      token = channel.provider_config['api_key']
      currency = fetch_currency(waba_id, token)
      chunk_from = from
      while chunk_from <= to
        chunk_to = [chunk_from + (CHUNK_DAYS - 1).days, to].min
        points = fetch_points(waba_id, token, chunk_from, chunk_to)
        if points.is_a?(String)
          errors << "#{waba_id}: #{points}"
          break
        end
        rows += store_points(waba_id, currency, points)
        chunk_from = chunk_to + 1.second
      end
    end
    Rails.logger.info "[CEVICO gasto whatsapp] conta=#{@account.id} wabas=#{wabas.size} linhas=#{rows} erros=#{errors.inspect}"
    { ok: errors.empty?, wabas: wabas.size, rows: rows, from: from.to_date.iso8601, to: to.to_date.iso8601,
      error: errors.presence&.join(' · ') }
  end

  private

  def channels_by_waba
    @account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).filter_map(&:channel)
            .select { |c| c.provider == 'whatsapp_cloud' && cloud_credentials?(c) }
            .index_by { |c| c.provider_config['business_account_id'].to_s }
  end

  def cloud_credentials?(channel)
    channel.provider_config['business_account_id'].present? && channel.provider_config['api_key'].present?
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def fetch_currency(waba_id, token)
    response = HTTParty.get("#{BASE_URI}/#{api_version}/#{waba_id}", query: { fields: 'currency' },
                                                                     headers: { 'Authorization' => "Bearer #{token}" }, timeout: 20)
    response.success? ? response.parsed_response['currency'].to_s.presence || 'USD' : 'USD'
  rescue StandardError
    'USD'
  end

  # devolve a lista de pontos ou uma String com o erro
  def fetch_points(waba_id, token, from, to)
    fields = "pricing_analytics.start(#{from.to_i}).end(#{to.to_i}).granularity(DAILY)" \
             '.dimensions(PRICING_CATEGORY,PRICING_TYPE,PHONE)'
    response = HTTParty.get("#{BASE_URI}/#{api_version}/#{waba_id}", query: { fields: fields },
                                                                     headers: { 'Authorization' => "Bearer #{token}" }, timeout: 30)
    body = response.parsed_response
    return (body.is_a?(Hash) ? body.dig('error', 'message') : nil) || "HTTP #{response.code}" unless response.success?

    Array(body.dig('pricing_analytics', 'data')).flat_map { |d| Array(d['data_points']) }
  rescue StandardError => e
    e.message
  end

  def store_points(waba_id, currency, points)
    rows = merge_duplicates(points.map { |p| row_from(p, waba_id, currency) })
    return 0 if rows.empty?

    # upsert_all: sobrescreve o dia quando a Meta fecha os números (sem validações — o modelo é só dados)
    Crm::WhatsappCharge.upsert_all(rows, unique_by: :idx_crm_wa_charges_unique) # rubocop:disable Rails/SkipsModelValidations
    rows.size
  end

  def row_from(point, waba_id, currency)
    day = Time.zone.at(point['start'].to_i).in_time_zone('America/Sao_Paulo').to_date
    { account_id: @account.id, waba_id: waba_id, phone_number: point['phone_number'].to_s.delete('^0-9'), day: day,
      category: point['pricing_category'].to_s.downcase, pricing_type: point['pricing_type'].to_s.downcase,
      volume: point['volume'].to_i, cost: point['cost'].to_f.round(4), currency: currency }
  end

  # mesmo dia/número/categoria/tipo repetido no lote (fuso): fica a soma
  def merge_duplicates(rows)
    rows.group_by { |r| r.values_at(:phone_number, :day, :category, :pricing_type) }.map do |_, group|
      group.first.merge(volume: group.sum { |r| r[:volume] }, cost: group.sum { |r| r[:cost] }.round(4))
    end
  end
end
