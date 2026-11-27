# 🙋 27/11/2026 (LIFE, Guilherme: "quando a IA pede gente, a gente precisa entender o porquê"): para cada pedido de
# atendimento humano, o motivo que a IA deixou na nota da tarefa, a última fala do cliente antes do pedido, a coluna
# do cartão e se o cliente foi o último a escrever. Usado por Crm::TeamResponse.
class Crm::TeamResponse::RequestReasons
  LOOKBACK = 7.days
  NOTE_WINDOW = 3.minutes

  def initialize(account, conversation_ids, since, until_at)
    @account = account
    @cids = conversation_ids
    @since = since
    @until = until_at
  end

  def at(cid, time) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    motivo = notes[cid]&.select { |t, _m| (t - time).abs <= NOTE_WINDOW }&.min_by { |t, _m| (t - time).abs }&.last
    said = client_lines[cid]&.reverse&.find { |t, _c| t <= time }&.last
    key, label = Crm::TeamResponse.topic_for(motivo, said)
    { motivo: motivo, cliente_disse: said.to_s.squish.first(220).presence, topic: key, topic_label: label }
  end

  # coluna do cartão e se o cliente foi o último a escrever (está esperando a gente)
  def card(cid)
    conv = conversations[cid]
    stage = conv && stages[conv.contact_id]
    last = last_public[cid]
    { display_id: conv&.display_id, name: conv&.contact&.name, etapa: stage,
      cliente_esperando: last.present? && last.to_s == 'incoming' }
  end

  private

  def notes
    @notes ||= Message.where(account_id: @account.id, conversation_id: @cids, message_type: :activity)
                      .where(created_at: (@since - LOOKBACK)..@until).where('content LIKE ?', '%a tarefa #%')
                      .pluck(:conversation_id, :created_at, :content)
                      .filter_map { |cid, at, content| (m = content.to_s.match(Crm::TeamResponse::TASK_NOTE)) && [cid, at, m[1].squish] }
                      .group_by(&:first).transform_values { |list| list.map { |_c, at, motivo| [at, motivo] } }
  end

  def client_lines
    @client_lines ||= Message.where(account_id: @account.id, conversation_id: @cids, message_type: :incoming, private: false)
                             .where(created_at: (@since - LOOKBACK)..@until).where.not(content: [nil, ''])
                             .order(:created_at).pluck(:conversation_id, :created_at, :content)
                             .group_by(&:first).transform_values { |list| list.map { |_c, at, content| [at, content] } }
  end

  def conversations
    @conversations ||= Conversation.where(id: @cids).includes(:contact).index_by(&:id)
  end

  def stages
    @stages ||= Crm::Contact.joins(:stage).where(contact_id: conversations.values.filter_map(&:contact_id))
                            .order(:updated_at).pluck(:contact_id, 'crm_stages.name').to_h
  end

  # tipo da última mensagem pública de cada conversa (incoming = cliente esperando)
  def last_public
    @last_public ||= Message.where(conversation_id: @cids, private: false, message_type: %i[incoming outgoing])
                            .select('DISTINCT ON (conversation_id) conversation_id, message_type')
                            .reorder(:conversation_id, created_at: :desc)
                            .to_h { |m| [m.conversation_id, m.message_type] }
  end
end
