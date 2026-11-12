# 🏷️ PROPOSTA ENVIADA AO CLIENTE (11/11/2026 · LIFE, pedido do Guilherme): "quando a pessoa recebeu
# o orçamento, é para ela ter uma etiqueta, uma etiqueta automática".
#
# É o PONTO DE ENCONTRO entre o gerador de proposta e o follow-up. Quem envia a proposta chama:
#
#   Crm::QuoteSent.call(contact, value: 24_800)     # value é opcional
#
# O que acontece: o contato ganha a etiqueta `orcamento-enviado`. A etiqueta dispara o resto,
# pelas automações da conta (LIFE/agente/followup_life_v3.rb):
#   etiqueta posta → o cartão vai para a coluna "Orçamento Enviado"
#                  → nasce o compromisso do responsável com a fila de lembretes (Crm::StageDeadline)
#                  → o robô de mensagens ao cliente começa a contar (ele só cutuca quem tem a etiqueta).
# Quem arrasta o cartão para a coluna na mão também ganha a etiqueta (automação "cartão entrou").
# Com `value`, o valor do orçamento fica no cartão (aparece no funil e nas tarefas).
class Crm::QuoteSent
  LABEL = 'orcamento-enviado'.freeze
  COLOR = '#EA580C'.freeze
  DESCRIPTION = 'Cliente que já recebeu o orçamento (posta sozinha quando a proposta é enviada)'.freeze

  def self.call(contact, value: nil)
    return false if contact.nil?

    ensure_label!(contact.account)
    store_value(contact, value)
    contact.add_labels([LABEL]) unless contact.label_list.include?(LABEL)
    true
  end

  def self.ensure_label!(account)
    account.labels.find_or_create_by!(title: LABEL) do |label|
      label.color = COLOR
      label.description = DESCRIPTION
      label.show_on_sidebar = true
    end
  end

  # o valor vai para o cartão mais recente do cliente (só quando vem um número de verdade)
  def self.store_value(contact, value)
    amount = value.to_f
    return unless amount.positive?

    card = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: contact.account_id }, contact_id: contact.id)
                       .order(Arel.sql('crm_contacts.stage_moved_at DESC NULLS LAST, crm_contacts.id DESC')).first
    card&.update!(value: amount)
  end
end
