# Retroativo: varre as mensagens antigas que chegaram com "referral"
# (clique em anúncio CTWA) e carimba a atribuição nos contatos/conversas
# que ainda não têm. Roda uma vez após ativar a atribuição — mensagens
# novas já são carimbadas na chegada pelo webhook.
class Crm::AdAttributionBackfillJob < ApplicationJob
  queue_as :low

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return unless account

    stamped = 0
    scope(account).find_each(batch_size: 500) do |message|
      referral = message.content_attributes['referral']
      next if referral.blank?

      Crm::AdAttributionService.new(
        contact: message.sender.is_a?(Contact) ? message.sender : message.conversation&.contact,
        conversation: message.conversation,
        referral: referral,
        captured_at: message.created_at
      ).call
      stamped += 1
    end

    Rails.logger.info "[Crm::AdAttributionBackfill] account=#{account_id} messages=#{stamped}"
  end

  # mensagens de entrada com referral, da mais antiga pra mais nova
  # (primeiro toque: o anúncio mais antigo do contato é o que fica)
  def self.referral_messages(account)
    account.messages
           .where(message_type: :incoming)
           .where("content_attributes -> 'referral' IS NOT NULL")
  end

  private

  def scope(account)
    self.class.referral_messages(account).order(:created_at)
  end
end
