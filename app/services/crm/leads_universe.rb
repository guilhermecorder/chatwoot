# O "universo de leads" oficial do sistema: contatos NOVOS do período que
# chegaram pelas caixas de captação (Google/Instagram). É a régua única usada
# pelo Meu Painel e pelo Dashboard CRM — os números batem entre as telas.
# Conta sem caixas com esses nomes (ex.: ambiente local) = todos os novos.
module Crm::LeadsUniverse
  module_function

  def scope(account, since, until_at)
    base = account.contacts.where(created_at: since..until_at)
    inbox_ids = account.inboxes
                       .where('name ILIKE :g OR name ILIKE :i', g: '%google%', i: '%instagram%')
                       .pluck(:id)
    return base if inbox_ids.empty?

    base.joins(:conversations).where(conversations: { inbox_id: inbox_ids }).distinct
  end
end
