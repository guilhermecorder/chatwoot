class Crm::LabelReplaceJob < ApplicationJob
  queue_as :low

  def perform(account_id, from_label, to_label)
    account = Account.find(account_id)
    result = Crm::LabelReplaceService.new(
      account: account, from_label: from_label, to_label: to_label
    ).apply!
    Rails.logger.info("[CEVICO label_replace] conta #{account_id}: #{from_label} → #{to_label} " \
                      "(#{result[:contacts]} contatos, #{result[:conversations]} conversas)")
  end
end
