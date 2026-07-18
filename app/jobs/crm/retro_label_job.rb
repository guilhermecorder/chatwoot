# Tratamento de dados: varre conversas cujo conteúdo das mensagens contém um
# texto (todo o período ou um intervalo) e, para cada uma, pode:
#   - aplicar uma etiqueta na conversa e no contato
#   - colocar/mover o card do contato numa coluna (stage) do CRM
# Ex: conversa contém "3900" → etiqueta "orcamento-refrativa" + coluna "Envio de Orçamento".
class Crm::RetroLabelJob < ApplicationJob
  queue_as :low

  def perform(account_id, term, label_title, options = {})
    account = Account.find_by(id: account_id)
    return if account.blank? || term.blank?

    label_title = label_title.to_s.strip.downcase.presence
    account.labels.find_or_create_by!(title: label_title) if label_title

    stage = resolve_stage(account, options)
    return if label_title.blank? && stage.blank?

    apply_to_contact = options['apply_to_contact'] != false
    conversation_ids = matching_conversation_ids(account, term, options)
    processed = 0

    conversation_ids.each_slice(200) do |batch|
      account.conversations.where(id: batch).includes(:contact).each do |conversation|
        if label_title
          fast_add_label(conversation, label_title)
          fast_add_label(conversation.contact, label_title) if apply_to_contact && conversation.contact
        end

        place_in_stage(stage, conversation.contact) if stage && conversation.contact

        processed += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::RetroLabelJob] conversa #{conversation.id}: #{e.message}"
      end

      # respira entre lotes para não saturar a CPU em bases grandes
      sleep 0.05
    end

    Rails.logger.info "[Crm::RetroLabelJob] '#{term}': #{processed} conversas processadas"
  end

  # Interpreta o campo de busca:
  #   - "entre aspas"  → frase exata, tratada como UMA peça (vírgula dentro ok)
  #   - sem aspas      → termos separados por vírgula/;/quebra de linha
  # Qualquer um dos termos casa a conversa (OR).
  def self.parse_terms(raw)
    terms = []
    rest = raw.to_s.gsub(/"([^"]+)"|'([^']+)'|“([^”]+)”/) do
      terms << (Regexp.last_match(1) || Regexp.last_match(2) || Regexp.last_match(3))
      ' '
    end
    terms += rest.split(/[,;\n]+/)
    terms.map(&:strip).reject(&:blank?)
  end

  # Busca ignorando acento e caixa.
  def self.matching_scope(account, term, options = {})
    terms = parse_terms(term)

    # reorder(nil) remove a ordenação padrão do Message, que quebra o DISTINCT
    scope = Message.reorder(nil).where(account_id: account.id)

    if terms.any?
      clauses = terms.map { 'unaccent(messages.content) ILIKE unaccent(?)' }
      values  = terms.map { |t| "%#{ActiveRecord::Base.sanitize_sql_like(t)}%" }
      scope = scope.where(clauses.join(' OR '), *values)
    end

    # datas inválidas não podem derrubar o job (o filtro só é ignorado)
    if (from = safe_date(options['period_from']))
      scope = scope.where('messages.created_at >= ?', from.beginning_of_day)
    end
    if (to = safe_date(options['period_to']))
      scope = scope.where('messages.created_at <= ?', to.end_of_day)
    end
    scope
  end

  def self.safe_date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end

  private

  def resolve_stage(account, options)
    return nil if options['target_stage_id'].blank?

    Crm::Stage.joins(:pipeline)
              .where(crm_pipelines: { account_id: account.id })
              .find_by(id: options['target_stage_id'])
  end

  # Etiquetagem retroativa LEVE: escreve direto na tabela de taggings e
  # atualiza o cache, sem disparar update! (que geraria webhook, automação,
  # evento de relatório e ActionCable para cada registro — o que saturava a
  # CPU ao processar milhares de leads). Para dados históricos isso é o certo.
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

  # cria o card na coluna, ou move se já existir (sem duplicar no pipeline)
  def place_in_stage(stage, contact)
    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    return if card.persisted? && card.stage_id == stage.id

    card.stage_id = stage.id
    card.save!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def matching_conversation_ids(account, term, options)
    self.class.matching_scope(account, term, options).distinct.pluck(:conversation_id).compact
  end
end
