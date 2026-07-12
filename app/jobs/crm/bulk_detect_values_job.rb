class Crm::BulkDetectValuesJob < ApplicationJob
  queue_as :low

  def perform(pipeline_id, only_empty = true)
    pipeline = Crm::Pipeline.find(pipeline_id)
    account = pipeline.account
    scope = pipeline.crm_contacts.includes(:contact)
    scope = scope.where(value: [nil, 0]) if only_empty

    updated = 0
    scope.find_each do |crm_contact|
      next if crm_contact.contact.blank?

      value = Crm::BudgetValueExtractor.new(account: account, contact: crm_contact.contact).max_value
      next if value.blank?

      crm_contact.update!(value: value)
      updated += 1
    end
    Rails.logger.info("[CEVICO detect_values] pipeline #{pipeline_id}: #{updated} cards atualizados")
  end
end
