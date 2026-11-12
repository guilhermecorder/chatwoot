# 🌡️ TEMPERATURA DAS TAREFAS (11/11/2026 · LIFE, pedido do Guilherme): no Meu Painel cada tarefa
# de quem vende mostra QUEM é o cliente, a etapa do funil, o valor do orçamento e uma TEMPERATURA,
# para a pessoa saber qual pegar primeiro. A regra é uma soma de pontos (0 a 10) só com o que o
# sistema já sabe — nada inventado:
#
#   1. O cliente falou há pouco?   até 24 h +3 · até 3 dias +2 · até 7 dias +1
#   2. Ele está esperando resposta? a última mensagem da conversa é dele       +1
#   3. Onde está no funil?          +1 por etapa que já avançou, até            +3
#   4. E o prazo da tarefa?         atrasou +3 · vence nas próximas 24 h        +2
#
#   7 a 10 = quente · 4 a 6 = morna · 0 a 3 = fria
#   Empate: primeiro o maior valor de orçamento, depois o prazo mais antigo.
#
# O texto que aparece na tela ("falou há 3 horas") é montado no front
# (helper/taskPriority.js); aqui ficam só os pontos e os dados crus.
class Crm::TaskPriority
  HOT = 7
  WARM = 4
  MAX_STAGE_POINTS = 3

  # a regra, sem banco: devolve { level:, points:, parts: [{ key:, points: }] }
  def self.score(now:, due_at: nil, last_client_at: nil, waiting: false, stage_step: nil)
    parts = [
      { key: 'fala', points: talk_points(now, last_client_at) },
      { key: 'espera', points: waiting ? 1 : 0 },
      { key: 'etapa', points: stage_step.to_i.clamp(0, MAX_STAGE_POINTS) },
      { key: 'prazo', points: due_points(now, due_at) }
    ].select { |p| p[:points].positive? }
    points = parts.sum { |p| p[:points] }
    { level: level_for(points), points: points, parts: parts }
  end

  def self.level_for(points)
    return 'quente' if points >= HOT

    points >= WARM ? 'morna' : 'fria'
  end

  def self.talk_points(now, last_client_at)
    return 0 if last_client_at.nil?

    age = now - last_client_at
    return 3 if age <= 24.hours
    return 2 if age <= 3.days

    age <= 7.days ? 1 : 0
  end

  def self.due_points(now, due_at)
    return 0 if due_at.nil?
    return 3 if due_at < now

    due_at - now <= 24.hours ? 2 : 0
  end

  def initialize(account, tasks, now: Time.current)
    @account = account
    @tasks = tasks.to_a
    @now = now
    @contact_ids = @tasks.filter_map(&:contact_id).uniq
  end

  # { task_id => { contact:, card:, last_client_at:, last_reply_at:, client_waiting:, heat: } }
  def call
    @tasks.to_h { |task| [task.id, row(task)] }
  end

  # ordem de prioridade: mais pontos → maior valor → prazo mais antigo → mais nova
  def self.sort(items)
    items.sort_by do |i|
      [-i.dig(:heat, :points).to_i, -i.dig(:card, :value).to_f, i[:due_at] ? i[:due_at].to_f : Float::INFINITY, -i[:id]]
    end
  end

  private

  def row(task)
    card = card_for(task)
    last_in = last_client_at[task.contact_id]
    last_out = last_reply_at[task.contact_id]
    waiting = last_in.present? && (last_out.nil? || last_in > last_out)
    {
      contact: contact_json(task),
      card: card_json(card),
      last_client_at: last_in,
      last_reply_at: last_out,
      client_waiting: waiting,
      summary: summary_lines(task),
      heat: self.class.score(now: @now, due_at: task.due_at, last_client_at: last_in, waiting: waiting,
                             stage_step: card && stage_step(card))
    }
  end

  # 📝 resumo escrito do cliente (Crm::ClientSummary): só o que já foi anotado
  def summary_lines(task)
    contact = contacts[task.contact_id]
    @summary_fields ||= Crm::ClientSummary.fields(@account)
    contact ? Crm::ClientSummary.lines(contact, fields: @summary_fields) : []
  end

  def contact_json(task)
    contact = contacts[task.contact_id]
    contact && { id: contact.id, name: contact.name, phone: contact.phone_number }
  end

  def card_json(card)
    return nil if card.nil?

    stage = stages[card.stage_id]
    { id: card.id, pipeline_id: card.pipeline_id, value: card.value&.to_f,
      stage: stage && { id: stage.id, name: stage.name, color: stage.color, step: stage_step(card) } }
  end

  # o cartão da tarefa: o que a etapa marcou no compromisso; sem marca, o que se mexeu por último
  def card_for(task)
    list = cards[task.contact_id] || []
    marked = Array(task.comments).filter_map { |c| c.is_a?(Hash) && c.dig('etapa', 'card_id') }.last
    list.find { |c| c.id == marked.to_i } || list.first
  end

  # quantas etapas o cartão já andou no funil dele (0 = primeira coluna)
  def stage_step(card)
    (stage_order[card.pipeline_id] || []).index(card.stage_id) || 0
  end

  def contacts
    @contacts ||= @account.contacts.where(id: @contact_ids).index_by(&:id)
  end

  def cards
    @cards ||= Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, contact_id: @contact_ids)
                           .order(Arel.sql('crm_contacts.stage_moved_at DESC NULLS LAST, crm_contacts.id DESC'))
                           .group_by(&:contact_id)
  end

  def stages
    @stages ||= Crm::Stage.where(pipeline_id: pipeline_ids).index_by(&:id)
  end

  def stage_order
    @stage_order ||= stages.values.group_by(&:pipeline_id).transform_values { |list| list.sort_by { |s| [s.position, s.id] }.map(&:id) }
  end

  def pipeline_ids
    cards.values.flatten.map(&:pipeline_id).uniq
  end

  # última mensagem que o CLIENTE mandou, por contato
  def last_client_at
    @last_client_at ||= last_message_by_contact(Message.message_types[:incoming])
  end

  # última mensagem que a EMPRESA mandou (pessoa ou atendente de IA), por contato.
  # Avisos automáticos do sistema (tipo "template"/"activity") não contam como resposta.
  def last_reply_at
    @last_reply_at ||= last_message_by_contact(Message.message_types[:outgoing])
  end

  def last_message_by_contact(types)
    return {} if @contact_ids.empty?

    Message.unscope(:order).joins(:conversation)
           .where(account_id: @account.id, message_type: types, private: false)
           .where(conversations: { contact_id: @contact_ids })
           .group('conversations.contact_id').maximum('messages.created_at')
  end
end
