# Tratamento de dados: aplica uma etiqueta em todas as conversas (de todo o
# período ou de um intervalo) cujo conteúdo das mensagens contém um texto.
# Ex: etiqueta "orcamento-refrativa" em toda conversa que contém "3900".
class Crm::RetroLabelJob < ApplicationJob
  queue_as :low

  def perform(account_id, term, label_title, options = {})
    account = Account.find_by(id: account_id)
    return if account.blank? || term.blank? || label_title.blank?

    label_title = label_title.to_s.strip.downcase
    account.labels.find_or_create_by!(title: label_title)
    apply_to_contact = options['apply_to_contact'] != false

    conversation_ids = matching_conversation_ids(account, term, options)
    processed = 0

    conversation_ids.each_slice(100) do |batch|
      account.conversations.where(id: batch).includes(:contact).each do |conversation|
        conversation.add_labels([label_title]) unless conversation.label_list.include?(label_title)

        if apply_to_contact && conversation.contact && !conversation.contact.label_list.include?(label_title)
          conversation.contact.add_labels([label_title])
        end

        processed += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::RetroLabelJob] conversa #{conversation.id}: #{e.message}"
      end
    end

    Rails.logger.info "[Crm::RetroLabelJob] '#{term}' → '#{label_title}': #{processed} conversas etiquetadas"
  end

  def self.matching_scope(account, term, options = {})
    # reorder(nil) remove a ordenação padrão do Message, que quebra o DISTINCT
    scope = Message.reorder(nil)
                   .where(account_id: account.id)
                   .where('messages.content ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    scope = scope.where('messages.created_at >= ?', Date.parse(options['period_from']).beginning_of_day) if options['period_from'].present?
    scope = scope.where('messages.created_at <= ?', Date.parse(options['period_to']).end_of_day) if options['period_to'].present?
    scope
  end

  private

  def matching_conversation_ids(account, term, options)
    self.class.matching_scope(account, term, options).distinct.pluck(:conversation_id).compact
  end
end
