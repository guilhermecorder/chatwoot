# Tratamento de dados: movimenta cards do CRM em LOTE e/ou adiciona etiqueta,
# filtrando por coluna atual, valor no card, caixa de entrada e etiqueta.
# Ex.: "cards COM valor na coluna Novos Contatos → mover para Envio de Orçamento"
#      "contatos da caixa GOOGLE → etiqueta consulta_google"
#
# Modo LEVE, como o RetroLabelJob: etiqueta escrita direto em taggings (sem
# webhook/automação/ActionCable por registro) e nunca duplica etiqueta que o
# contato já tem (find_or_create_by). Mover card registra o StageLog normal.
class Crm::BatchUpdateJob < ApplicationJob
  queue_as :low

  def perform(account_id, filters = {}, actions = {})
    account = Account.find_by(id: account_id)
    return if account.blank?

    target_stage = resolve_stage(account, actions['target_stage_id'])
    label_title = actions['add_label'].to_s.strip.downcase.presence
    return if target_stage.blank? && label_title.blank?

    account.labels.find_or_create_by!(title: label_title) if label_title

    card_ids = self.class.matching_cards(account, filters).pluck(:id)
    processed = 0

    card_ids.each_slice(200) do |batch|
      Crm::Contact.where(id: batch).includes(:contact).each do |card|
        move_card(card, target_stage) if target_stage
        fast_add_label(card.contact, label_title) if label_title && card.contact

        processed += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::BatchUpdateJob] card #{card.id}: #{e.message}"
      end

      # respira entre lotes para não saturar a CPU em bases grandes
      sleep 0.05
    end

    Rails.logger.info "[Crm::BatchUpdateJob] #{processed} cards processados " \
                      "(filtros: #{filters.inspect} → mover=#{target_stage&.name} etiqueta=#{label_title})"
  end

  # Filtros aceitos (todos opcionais, combináveis):
  #   stage_id     — cards que estão HOJE nessa coluna
  #   value_filter — 'with' (valor > 0) | 'without' (sem valor)
  #   inbox_id     — contatos com conversa nessa caixa de entrada
  #   label        — contatos que TÊM essa etiqueta
  def self.matching_cards(account, filters)
    scope = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id })
    scope = scope.where(stage_id: filters['stage_id']) if filters['stage_id'].present?

    case filters['value_filter']
    when 'with'
      scope = scope.where('crm_contacts.value > 0')
    when 'without'
      scope = scope.where('crm_contacts.value IS NULL OR crm_contacts.value <= 0')
    end

    if filters['inbox_id'].present?
      with_inbox = Conversation.where(account_id: account.id, inbox_id: filters['inbox_id']).select(:contact_id)
      scope = scope.where(contact_id: with_inbox)
    end

    if filters['label'].present?
      tagged = ActsAsTaggableOn::Tagging.joins(:tag)
                                        .where(taggable_type: 'Contact', context: 'labels')
                                        .where(tags: { name: filters['label'].to_s.strip.downcase })
                                        .select(:taggable_id)
      scope = scope.where(contact_id: tagged)
    end

    scope
  end

  private

  def resolve_stage(account, stage_id)
    return nil if stage_id.blank?

    Crm::Stage.joins(:pipeline)
              .where(crm_pipelines: { account_id: account.id })
              .find_by(id: stage_id)
  end

  # move dentro do próprio funil; se o destino é de outro funil, cria/move
  # o card de lá (mesma regra do place_in_stage do Tratamento)
  def move_card(card, stage)
    if card.pipeline_id == stage.pipeline_id
      card.update!(stage_id: stage.id) if card.stage_id != stage.id
    else
      other = Crm::Contact.find_or_initialize_by(contact_id: card.contact_id, pipeline_id: stage.pipeline_id)
      return if other.persisted? && other.stage_id == stage.id

      other.stage_id = stage.id
      other.save!
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # etiqueta LEVE e sem duplicar: direto na tabela de taggings + cache
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
