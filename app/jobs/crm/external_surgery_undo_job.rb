# ↩️ DESFAZER a última importação de cirurgias (item 133): lê o recibo
# gravado pelo ExternalSurgeryJob e devolve tudo ao estado anterior —
#   - paciente CRIADO pela planilha → apagado (junto com o card);
#   - card CRIADO → apagado;
#   - card MOVIDO → volta pra coluna anterior, com o valor e o
#     stage_moved_at de antes; o registro de movimentação criado no import
#     é apagado (histórico antigo do card não é tocado);
#   - etiqueta aplicada no import → removida dos contatos afetados.
# O recibo é da ÚLTIMA importação apenas; desfeito, ele é limpo.
class Crm::ExternalSurgeryUndoJob < ApplicationJob
  queue_as :low

  def perform(account_id, receipt_id)
    account = Account.find_by(id: account_id)
    settings = CrmSetting.find_by(account: account)
    return if account.blank? || settings.blank?

    receipt = (settings.agenda_config || {})['surgery_import_undo']
    return if receipt.blank? || receipt['id'] != receipt_id

    label_tag = find_label_tag(receipt['label'])
    reverted = 0

    Array(receipt['entries']).each_slice(200) do |batch|
      batch.each do |entry|
        revert_entry(account, entry, label_tag)
        reverted += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::ExternalSurgeryUndoJob] entrada #{entry.inspect}: #{e.message}"
      end
      sleep 0.05
    end

    clear_receipt(settings, receipt_id)
    Rails.logger.info "[Crm::ExternalSurgeryUndoJob] #{reverted} mudanças desfeitas na conta #{account.id}"
  end

  private

  def revert_entry(account, entry, label_tag)
    card = Crm::Contact.find_by(id: entry['card_id'])

    if entry['created_contact_id']
      # paciente veio da planilha: some com card e contato
      card&.destroy
      account.contacts.find_by(id: entry['created_contact_id'])&.destroy
      return
    end

    remove_label(entry['contact_id'], label_tag) if label_tag
    return if card.blank?

    if entry['created_card']
      card.destroy
      return
    end

    # card já existia: apaga o log do import e restaura coluna/valor/data
    Crm::StageLog.where(id: entry['new_log_id']).delete_all if entry['new_log_id']
    restores = {}
    restores[:stage_id] = entry['prev_stage_id'] if entry['moved'] && entry['prev_stage_id']
    restores[:value] = entry['prev_value'] if entry.key?('prev_value')
    restores[:stage_moved_at] = entry['prev_stage_moved_at'] if entry['moved']
    card.update_columns(**restores) if restores.any? # rubocop:disable Rails/SkipsModelValidations
  end

  def find_label_tag(label_title)
    return nil if label_title.blank?

    ActsAsTaggableOn::Tag.find_by(name: label_title.to_s.strip.downcase)
  end

  # remoção LEVE da etiqueta (par do fast_add_label do import)
  def remove_label(contact_id, tag)
    return if contact_id.blank?

    ActsAsTaggableOn::Tagging.where(
      taggable_type: 'Contact', taggable_id: contact_id,
      context: 'labels', tag_id: tag.id
    ).delete_all
  end

  def clear_receipt(settings, receipt_id)
    settings.with_lock do
      cfg = (settings.reload.agenda_config || {}).deep_dup
      cfg.delete('surgery_import_undo') if cfg.dig('surgery_import_undo', 'id') == receipt_id
      settings.update_column(:agenda_config, cfg) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
