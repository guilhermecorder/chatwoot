# 🛑 Opt-out de mensagens ativas (varredura de conformidade 20/09 — WhatsApp
# Business Messaging Policy: honrar o pedido de parar). Quem tem a etiqueta
# `nao_perturbe` ou qualquer `perda_*` fica FORA de campanha em massa, régua
# e campanha de ligação — sem depender do operador lembrar de excluir. O
# detector de "PARE / SAIR / DESCADASTRAR" aplica a etiqueta sozinho.
module Crm::OptOut
  module_function

  LABEL = 'nao_perturbe'.freeze
  PREFIXES = %w[perda_].freeze
  # palavras que o paciente manda para não receber mais mensagens ativas
  KEYWORDS = /\A\s*(pare|parar|sair|stop|cancelar|descadastrar|remover|
    n[aã]o\s+quero\s+(mais\s+)?(receber|mensagens?)|n[aã]o\s+me\s+(mande|envie)\s+mais)\b/ix

  # títulos de etiqueta que silenciam (fixa + prefixos), na conta
  def quiet_titles(account)
    prefixed = account.labels.where(PREFIXES.map { |p| "title LIKE '#{p}%'" }.join(' OR ')).pluck(:title)
    ([LABEL] + prefixed).uniq
  end

  def excluded_contact_ids(account)
    titles = quiet_titles(account)
    account.contacts.tagged_with(titles, any: true).pluck(:id)
  end

  def opt_out_message?(content)
    text = content.to_s.strip
    text.length <= 60 && KEYWORDS.match?(text)
  end

  # aplica a etiqueta e deixa nota na conversa (uma vez)
  def apply!(contact, conversation: nil)
    return false if contact.label_list.include?(LABEL)

    contact.add_labels([LABEL])
    conversation&.messages&.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: '🛑 Paciente pediu para não receber mais mensagens ativas — etiqueta nao_perturbe aplicada automaticamente.'
    )
    true
  rescue StandardError => e
    Rails.logger.warn("[CEVICO opt-out] não consegui aplicar: #{e.message}")
    false
  end
end
