# Importação retroativa dos leads que JÁ estão no Meta: varre todos os
# formulários instantâneos da página e ingere lead a lead (a Meta guarda os
# leads por 90 dias — o que existe lá é o que dá para trazer). Idempotente:
# leads já ingeridos contam como duplicados e não entram de novo.
# O resultado fica em meta_ads_config['last_lead_import'] para o card mostrar.
class Crm::MetaLeadImportJob < ApplicationJob
  queue_as :low

  # since (08/11, busca a cada 5 min do Crm::MetaLeadPollJob): só os leads
  # criados depois desse instante (Unix), e o resultado não vai para o card
  def perform(account_id, since = nil)
    account = Account.find_by(id: account_id)
    return if account.blank?

    @since = since
    service = Crm::MetaLeadIngestService.new(account: account)
    return write_result(account, 'status' => 'error', 'error' => 'Página/token não configurados.') unless service.configured?

    stats = { 'forms' => 0, 'imported' => 0, 'duplicates' => 0, 'errors' => 0 }
    each_page(service, "#{service.page_id}/leadgen_forms", fields: 'id,name,status', limit: 50) do |form|
      stats['forms'] += 1
      each_page(service, "#{form['id']}/leads", lead_query) do |lead|
        result = service.ingest(lead['id'], prefetched: lead.merge('form_id' => form['id']))
        key = { imported: 'imported', duplicate: 'duplicates' }[result] || 'errors'
        stats[key] += 1
      end
    end

    write_result(account, stats.merge('status' => 'ok'))
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaLeadImport] conta #{account_id}: #{e.message}"
    write_result(account, 'status' => 'error', 'error' => e.message)
  end

  private

  def lead_query
    query = { fields: Crm::MetaLeadIngestService::LEAD_FIELDS, limit: 100 }
    return query if @since.blank?

    query.merge(filtering: [{ field: 'time_created', operator: 'GREATER_THAN', value: @since.to_i }].to_json)
  end

  def each_page(service, path, query)
    response = service.get_api(path, query)
    loop do
      raise "Meta: #{extract_error(response)}" unless response.success?

      body = response.parsed_response
      Array(body['data']).each { |item| yield item }

      next_url = body.dig('paging', 'next')
      break if next_url.blank?

      response = service.get_url(next_url)
    end
  end

  def extract_error(response)
    response.parsed_response.dig('error', 'message') || "HTTP #{response.code}"
  rescue StandardError
    "HTTP #{response.code}"
  end

  def write_result(account, result)
    key = @since.present? ? 'last_lead_poll' : 'last_lead_import'
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    cfg = settings.meta_ads_config || {}
    cfg[key] = result.merge('finished_at' => Time.current.iso8601)
    settings.update!(meta_ads_config: cfg)
  end
end
