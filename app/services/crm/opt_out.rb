# 🛑 Opt-out de mensagens ativas (varredura de conformidade 20/09 — WhatsApp
# Business Messaging Policy: honrar o pedido de parar). Quem tem a etiqueta
# `nao_perturbe` ou qualquer `perda_*` fica FORA de campanha em massa, régua
# e campanha de ligação — sem depender do operador lembrar de excluir. O
# detector de "PARE / SAIR / DESCADASTRAR" aplica a etiqueta sozinho.
#
# 🚦 Saúde do WhatsApp (16/10): PRECISÃO em dois níveis (Crm::StopSignals).
#   CERTO    = a mensagem INTEIRA é um pedido de parar ("PARE", "Sair",
#              "não quero mais receber mensagens, obrigado") → nao_perturbe.
#   SUSPEITA = o pedido aparece no meio de uma frase ("vou bloquear esse
#              número", "isso é spam", "me tira dessa lista aí") →
#              suspeita_nao_quer, para a equipe conferir.
# Antes bastava a mensagem COMEÇAR com a palavra: "Sair de casa às 8h?" e
# "Cancelar a consulta de amanhã" viravam nao_perturbe. "Cancelar" saiu da
# lista (é desmarcar consulta, não parar mensagens).
# As etiquetas da família Crm::StopSignals ligadas na chavinha "robôs param"
# também silenciam (quiet_titles).
module Crm::OptOut
  module_function

  LABEL = 'nao_perturbe'.freeze
  PREFIXES = %w[perda_].freeze

  POLITE = '(?:\s+(?:por\s+favor|pfv|pf|por\s+gentileza|obrigad[oa]s?|obg|grat[oa]|ok))*'.freeze
  MSG = '(?:mensagens?|mensagem|msgs?|nada|isso)'.freeze
  # pedido de parar = a mensagem INTEIRA (texto já sem acento/pontuação)
  CERTAIN = [
    'pare|parem|parar|stop|sair|descadastrar|descadastre|descadastra|remover|remova',
    "(?:pare|parem|para|parar)\\s+de\\s+(?:me\\s+)?(?:mandar|enviar)(?:\\s+#{MSG})?(?:\\s+(?:aqui|pra\\s+mim|para\\s+mim))?",
    "nao\\s+quero\\s+(?:mais\\s+)?receber(?:\\s+(?:mais\\s+)?#{MSG})?(?:\\s+(?:de\\s+voces|daqui|de\\s+vcs))?",
    "nao\\s+quero\\s+mais\\s+#{MSG}",
    "nao\\s+(?:me\\s+)?(?:mande|mandem|envie|enviem|manda)\\s+mais(?:\\s+#{MSG})?",
    '(?:me\\s+)?(?:tira|tire|tirem|remove|remova|removam|exclui|exclua|excluam)\\s+(?:da|dessa|desta)\\s+lista',
    '(?:quero\\s+)?sair\\s+(?:da|dessa|desta)\\s+lista',
    'descadastr\\w*(?:\\s+(?:meu\\s+)?numero)?'
  ].freeze
  CERTAIN_RE = /\A(?:#{CERTAIN.join('|')})#{POLITE}\z/

  # sinais no meio da frase (só SUSPEITA — a equipe confere)
  SUSPECT_RE = Regexp.union(
    /\b(?:pare|parem|para|parar)\s+de\s+(?:me\s+)?(?:mandar|enviar|ficar\s+mandando)\b/,
    /\bnao\s+(?:me\s+)?(?:mande|mandem|envie|enviem|manda)\s+mais\b/,
    /\bnao\s+quero\s+(?:mais\s+)?receber\b/,
    /\bchega\s+de\s+mensage/,
    /\b(?:tira|tire|tirem|remove|remova|exclua|exclui)\s+(?:meu\s+numero\s+)?(?:da|dessa|desta)\s+lista\b/,
    /\b(?:remover|remova|tirar|tira|tire|apagar|apague|exclua|excluir)\s+(?:o\s+)?meu\s+(?:numero|contato|telefone|cadastro)\b/,
    /\bvou\s+(?:te\s+|lhe\s+|voces\s+|vcs\s+)?(?:bloquear|denunciar)\b/,
    /\bbloquear\s+(?:esse|este|o)\s+numero\b/,
    /\bspam\b/,
    /\bnao\s+autorizei\b/,
    /\bquem\s+(?:te\s+|lhe\s+|lhes\s+)?(?:deu|passou)\s+(?:o\s+)?meu\s+(?:numero|contato)\b/,
    /\bonde\s+(?:voces\s+|vcs\s+)?(?:conseguiram|pegaram|arrumaram)\s+(?:o\s+)?meu\s+(?:numero|contato)\b/,
    /\bdescadastr/
  )
  # (fora de propósito: "número errado" — nas conversas reais é o PACIENTE
  # dizendo que ele digitou errado; "parar de usar óculos" é o objetivo da cirurgia)
  # "não quero mais" SOZINHO — pode ser "não quero mais a cirurgia": só
  # SUSPEITA ("não quero mais esperar, pode ser hoje?" não conta)
  SHORT_SUSPECT_RE = /\Anao\s+quero\s+mais(?:\s+(?:nada|saber|contato))?#{POLITE}\z/
  CERTAIN_LIMIT = 80
  SHORT_LIMIT = 40
  SUSPECT_LIMIT = 300

  # títulos de etiqueta que silenciam (fixa + prefixos + chavinhas dos sinais), na conta
  def quiet_titles(account)
    prefixed = account.labels.where(PREFIXES.map { |p| "title LIKE '#{p}%'" }.join(' OR ')).pluck(:title)
    ([LABEL] + prefixed + Crm::StopSignals.robot_stop_labels(account)).uniq
  end

  def excluded_contact_ids(account)
    titles = quiet_titles(account)
    account.contacts.tagged_with(titles, any: true).pluck(:id)
  end

  # texto sem acento, minúsculo, só letras/números/espaço
  def normalize(content)
    I18n.transliterate(content.to_s).downcase.gsub(/[^a-z0-9\s]/, ' ').squish
  end

  # :certo | :suspeita | nil
  def classify(content)
    text = normalize(content)
    return nil if text.blank?
    return :certo if text.length <= CERTAIN_LIMIT && CERTAIN_RE.match?(text)
    return :suspeita if text.length <= SHORT_LIMIT && SHORT_SUSPECT_RE.match?(text)
    return :suspeita if text.length <= SUSPECT_LIMIT && SUSPECT_RE.match?(text)

    nil
  end

  # compatibilidade: "é pedido de parar com certeza?"
  def opt_out_message?(content)
    classify(content) == :certo
  end

  # aplica a etiqueta e deixa nota na conversa (uma vez)
  def apply!(contact, conversation: nil, message: nil)
    return false if contact.label_list.include?(LABEL)

    contact.add_labels([LABEL])
    record_proof(contact, message) if message
    conversation&.messages&.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: '🛑 Paciente pediu para não receber mais mensagens ativas — etiqueta nao_perturbe aplicada automaticamente.'
    )
    true
  rescue StandardError => e
    Rails.logger.warn("[CEVICO opt-out] não consegui aplicar: #{e.message}")
    false
  end

  # o MOTIVO fica no contato para a tela Saúde do WhatsApp
  def record_proof(contact, message)
    proof = { 'texto' => message.content.to_s.squish.truncate(200), 'message_id' => message.id, 'inbox_id' => message.inbox_id,
              'conversa' => message.conversation&.display_id,
              'ultima_entregue' => Crm::StopSignals.last_delivered_summary(contact, before: message.created_at) }.compact
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      signals = (attrs[Crm::StopSignals::ATTR_KEY] || {}).to_h
      signals[LABEL] = proof.merge('at' => Time.current.iso8601)
      attrs.merge(Crm::StopSignals::ATTR_KEY => signals)
    end
  end

  # chamado pelo CrmListener em toda mensagem recebida
  def handle_incoming!(message, contact)
    return unless message&.incoming? && contact.present?

    case classify(message.content)
    when :certo
      apply!(contact, conversation: message.conversation, message: message)
    when :suspeita
      return if contact.label_list.include?(LABEL)

      Crm::StopSignals.mark!(contact, 'suspeita_nao_quer',
                             { 'texto' => message.content.to_s.squish.truncate(200), 'message_id' => message.id,
                               'inbox_id' => message.inbox_id, 'conversa' => message.conversation&.display_id,
                               'ultima_entregue' => Crm::StopSignals.last_delivered_summary(contact, before: message.created_at) },
                             conversation: message.conversation, since: message.created_at.iso8601)
    end
  end
end
