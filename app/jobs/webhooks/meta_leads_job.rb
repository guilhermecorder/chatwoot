# Processa os eventos "leadgen" do webhook de Lead Ads: para cada lead novo,
# busca os dados na Graph API e ingere via Crm::MetaLeadIngestService
# (contato + respostas + atribuição + conversa opcional).
class Webhooks::MetaLeadsJob < ApplicationJob
  queue_as :default

  def perform(account_id, entries)
    account = Account.find_by(id: account_id)
    return if account.blank?

    service = Crm::MetaLeadIngestService.new(account: account)
    Array(entries).each do |entry|
      Array(entry.with_indifferent_access[:changes]).each do |change|
        next unless change[:field].to_s == 'leadgen'

        leadgen_id = change.dig(:value, :leadgen_id)
        service.ingest(leadgen_id.to_s) if leadgen_id.present?
      end
    end
  end
end
