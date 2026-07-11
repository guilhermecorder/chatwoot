class Crm::ContactUnificationJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find(account_id)
    result = Crm::ContactUnificationService.new(account: account).apply!
    Rails.logger.info("[CEVICO unify] conta #{account_id}: #{result[:merged]} mesclados, #{result[:failed]} falhas")
  end
end
