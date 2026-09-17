# Empurra os eventos cevico_call.* para todo mundo da conta (stream
# account_<id>); o frontend filtra por ring_user_ids / usuário atual.
module Crm::Calls::Broadcaster
  module_function

  def push(account, event, data)
    ActionCableBroadcastJob.perform_later(["account_#{account.id}"], event, data.merge(account_id: account.id))
  end
end
