# Tratamento de dados: "Cirurgias feitas FORA do sistema" — pacientes que
# operaram fora do CRM e nunca chegaram na coluna "Cirurgia Realizada".
# Recebe a lista já casada (contact_id → valor) e, para cada paciente:
#   - card já existe no funil da coluna-alvo → move via update! direto no
#     model (os callbacks registram o StageLog normal); NENHUMA automação é
#     chamada — mover cirurgia antiga não pode disparar automação de coluna
#     nem conversão de anúncio
#   - card não existe naquele funil → cria com origin 'cirurgia externa'
# Valor do card: preenche quando veio na lista e o card não tem valor (ou
# quando o admin mandou sobrescrever). Em card EXISTENTE o valor entra por
# update_column, sem callbacks — senão o gatilho "valor adicionado" do model
# dispararia automações para uma cirurgia do passado. Na criação pode ir
# junto: fire_value_automations é after_update, não roda no create.
# Etiqueta no contato: modo LEVE, direto em taggings (como o RetroLabelJob).
class Crm::ExternalSurgeryJob < ApplicationJob
  queue_as :low

  def perform(account_id, matched_pairs, stage_id, label_title, options = {})
    account = Account.find_by(id: account_id)
    return if account.blank?

    stage = Crm::Stage.joins(:pipeline)
                      .where(crm_pipelines: { account_id: account.id })
                      .find_by(id: stage_id)
    return if stage.blank?

    label_title = label_title.to_s.strip.downcase.presence
    account.labels.find_or_create_by!(title: label_title) if label_title

    set_value = options['set_value'] != false
    overwrite_value = options['overwrite_value'] == true
    processed = 0

    Array(matched_pairs).each_slice(200) do |batch|
      contacts = account.contacts.where(id: batch.map(&:first)).index_by(&:id)

      batch.each do |contact_id, value|
        contact = contacts[contact_id]
        next if contact.blank?

        place_in_stage(stage, contact, value, set_value, overwrite_value)
        fast_add_label(contact, label_title) if label_title
        processed += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::ExternalSurgeryJob] contato #{contact_id}: #{e.message}"
      end

      # respira entre lotes para não saturar a CPU em bases grandes
      sleep 0.05
    end

    Rails.logger.info "[Crm::ExternalSurgeryJob] #{processed} pacientes colocados em #{stage.name}"
  end

  private

  # cria o card na coluna-alvo, ou move se já existir no funil dela —
  # e preenche o valor respeitando "sem valor || sobrescrever"
  def place_in_stage(stage, contact, value, set_value, overwrite_value)
    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    new_value = value if set_value && value.to_f.positive?

    if card.persisted?
      card.update!(stage_id: stage.id) if card.stage_id != stage.id
      # sem callbacks: valor de cirurgia antiga não dispara "valor adicionado"
      card.update_column(:value, new_value) if new_value && (card.value.to_f <= 0 || overwrite_value)
    else
      card.origin = 'cirurgia externa'
      card.stage_id = stage.id
      card.value = new_value if new_value
      card.save!
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # etiqueta LEVE e sem duplicar: direto na tabela de taggings + cache
  # (sem webhook/automação/ActionCable por registro — igual ao RetroLabelJob)
  def fast_add_label(taggable, tag_name)
    return if taggable.blank?

    tag = ActsAsTaggableOn::Tag.find_or_create_by!(name: tag_name)
    ActsAsTaggableOn::Tagging.find_or_create_by!(
      tag_id: tag.id,
      taggable_type: taggable.class.name,
      taggable_id: taggable.id,
      context: 'labels'
    )

    return unless taggable.has_attribute?(:cached_label_list)

    list = (taggable.cached_label_list || '').split(',').map(&:strip).reject(&:blank?)
    return if list.include?(tag_name)

    taggable.update_column(:cached_label_list, (list + [tag_name]).join(', '))
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
