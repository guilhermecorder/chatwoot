# Varredura de valores (R$) pelo orçamento das conversas, card a card.
# 🔒 R2 da auditoria (#0): é CARGA EM LOTE, então grava com update_column
# (sem callbacks) — igual ao ExternalSurgeryJob — para não disparar o gatilho
# "valor adicionado" (evento de conversão, webhook, mensagem modelo) em massa.
# only_empty=false (sobrescrever valor já preenchido) só chega aqui vindo de
# admin (o controller força true para os demais).
class Crm::BulkDetectValuesJob < ApplicationJob
  queue_as :low

  def perform(pipeline_id, only_empty = true)
    pipeline = Crm::Pipeline.find(pipeline_id)
    account = pipeline.account
    scope = pipeline.crm_contacts.includes(:contact)
    scope = scope.where(value: [nil, 0]) if only_empty
    # No modo sobrescrever (só admin), card cujo paciente tem valor de FECHAMENTO
    # registrado pelo Espaço do Médico não é trocado por um "R$ x" achado na
    # conversa: o fechamento é o valor real, o orçamento é só uma proposta.
    closed_contact_ids = only_empty ? [] : contact_ids_with_closing(account)

    updated = 0
    scope.find_each do |crm_contact|
      value = new_value_for(crm_contact, account, closed_contact_ids)
      next if value.nil?

      crm_contact.update_column(:value, value) # rubocop:disable Rails/SkipsModelValidations
      updated += 1
    end
    Rails.logger.info("[CEVICO detect_values] pipeline #{pipeline_id}: #{updated} cards atualizados")
  end

  private

  # o valor novo do card, ou nil quando não há o que gravar
  def new_value_for(crm_contact, account, closed_contact_ids)
    return nil if crm_contact.contact.blank?
    return nil if crm_contact.value.to_f.positive? && closed_contact_ids.include?(crm_contact.contact_id)

    value = Crm::BudgetValueExtractor.new(account: account, contact: crm_contact.contact).max_value
    return nil if value.blank?
    return nil if crm_contact.value.to_d == value.to_d # já está com esse valor

    value
  end

  # pacientes com valor de fechamento (indicated_value > 0) em alguma anotação clínica
  def contact_ids_with_closing(account)
    Crm::ClinicalNote.where(account_id: account.id)
                     .pluck(:contact_id, :fields)
                     .select { |_id, fields| fields.to_h['indicated_value'].to_f.positive? }
                     .map(&:first).uniq
  end
end
