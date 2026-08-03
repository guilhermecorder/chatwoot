# O "universo de leads" oficial do sistema: contatos NOVOS do período que
# chegaram pelas caixas de captação (portas de entrada). É a régua única
# usada pelo Meu Painel e pelo Dashboard CRM — os números batem entre telas.
#
# Quais caixas são de captação: o admin marca no Dashboard CRM (Resultados
# por caixa → Informar investimento; agenda_config.capture_inbox_ids). Sem
# configuração, vale o padrão histórico: caixas com "google"/"instagram" no
# nome. Conta sem caixa de captação nenhuma = todos os novos.
module Crm::LeadsUniverse
  module_function

  def scope(account, since, until_at)
    base = account.contacts.where(created_at: since..until_at)
    inbox_ids = capture_inbox_ids(account)
    return base if inbox_ids.empty?

    base.joins(:conversations).where(conversations: { inbox_id: inbox_ids }).distinct
  end

  # ids das portas de entrada: configuração do admin > heurística por nome
  def capture_inbox_ids(account)
    all_ids = account.inboxes.pluck(:id)
    configured = Array(CrmSetting.find_by(account: account)&.agenda_config&.dig('capture_inbox_ids'))
                 .map(&:to_i) & all_ids
    return configured if configured.any?

    account.inboxes
           .where('name ILIKE :g OR name ILIKE :i', g: '%google%', i: '%instagram%')
           .pluck(:id)
  end
end
