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

  # lens (item 328): a lente da fonte escolhida no Meu Painel. Sem lente vale a
  # régua de sempre (da casa, com a cerca dos parceiros tirando os pacientes deles).
  def scope(account, since, until_at, lens: nil)
    return lens_scope(account, since, until_at, lens) if lens

    base = account.contacts.where(created_at: since..until_at)
    # 🚧 item 231 (cerca dos parceiros): paciente de parceiro do hub e caixa
    # dos parceiros nunca contam como lead da CEVICO
    partner_ids = Crm::PartnerGuard.excluded_contact_ids(account)
    base = base.where.not(id: partner_ids) if partner_ids.any?
    inbox_ids = capture_inbox_ids(account) - Crm::PartnerGuard.partner_inbox_ids(account)
    return base if inbox_ids.empty?

    base.joins(:conversations).where(conversations: { inbox_id: inbox_ids }).distinct
  end

  # 🔎 item 328: o universo pela LENTE.
  #   casa         = pacientes novos da casa que chegaram pelas caixas de captação
  #   outra fonte  = pacientes novos daquela fonte (chegam pelo hub ou pela
  #                  caixa dela — não há "caixa de captação" para exigir)
  #   tudo         = a soma das duas coisas
  def lens_scope(account, since, until_at, lens)
    base = account.contacts.where(created_at: since..until_at)
    return own_lens_scope(account, base, lens) if lens.own?
    return lens.contacts(base) unless lens.all?

    house = Crm::SourceLens.for(account, Crm::Source::OWN_KEY)
    base.where('contacts.id IN (:own) OR contacts.id NOT IN (:house)',
               own: own_lens_scope(account, base, house).select(:id), house: house.contacts(base).select(:id))
  end

  def own_lens_scope(account, base, lens)
    base = lens.contacts(base)
    inbox_ids = capture_inbox_ids(account) - lens.foreign_inbox_ids
    return base if inbox_ids.empty?

    base.where(id: Conversation.where(account_id: account.id, inbox_id: inbox_ids).select(:contact_id))
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
