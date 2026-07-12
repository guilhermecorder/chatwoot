class Crm::LabelRemoveJob < ApplicationJob
  queue_as :low

  def perform(account_id, label, stage_id = nil)
    account = Account.find(account_id)
    result = Crm::LabelRemoveService.new(account: account, label: label, stage_id: stage_id).apply!
    Rails.logger.info("[CEVICO label_remove] conta #{account_id}: '#{label}' removida de #{result[:contacts]} " \
                      "contatos (stage=#{stage_id || 'todas'})")
  end
end
