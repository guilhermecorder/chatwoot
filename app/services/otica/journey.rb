# 👓 JORNADA DA ÓTICA NO MEU PAINEL (22/11/2026, pedido do Guilherme): "aquela mesma ideia da LIFE, que aponta a
# jornada inteira da pessoa… traz aquela tecnologia para cá, atualiza para a jornada da ótica e enriqueça com a
# expansão de dashboards que nós já temos".
#
# A mesma régua da LIFE (Crm::QuoteJourney), com o caminho da ótica ("a foto abre, a loja fecha"):
#   NA CONVERSA  novos contatos → mandou a foto → recebeu a prova virtual → agendou → confirmou
#   NA LOJA      veio à loja → comprou → óculos pronto → retirou o óculos
#
# Como conta:
#   · pega quem CHEGOU no período (os leads novos do Meu Painel, Crm::LeadsUniverse);
#   · para cada pessoa, vê até onde ela já andou, com o que o sistema registrou:
#       foto      = selfie lida numa conversa dela (Crm::MediaReadingService, meta cevico_media tipo "selfie")
#       prova     = a prova virtual saiu para ela (mensagem com o carimbo do Otica::VirtualTryOn)
#       agendou   = horário na Agenda (visita, exame ou retirada) ou cartão em "Agendamento da visita"
#       confirmou = horário confirmado na Agenda ou cartão em "Visita confirmada"
#       veio      = presença marcada na Agenda ou cartão em "Visita realizada"
#       comprou   = O.S. vendida (Otica::Order) ou cartão em "Pedido fechado"
#       pronto    = O.S. pronta ou entregue, ou cartão em "Pronto para retirar"
#       retirou   = O.S. entregue, ou cartão em "Retirou o óculos" e nas colunas do pós-venda
#   · quem chegou a uma etapa conta também nas anteriores (o funil nunca "cresce" no meio);
#   · conversão = desta etapa para a seguinte; mais dois saltos (chegou → agendou, chegou → comprou);
#   · fonte = a etiqueta de origem da conversa (anúncio, formulário, site, direto; Crm::WhatsappOrigin);
#   · dinheiro = as O.S. vendidas de quem chegou no período (vendas, faturamento líquido, ticket médio);
#   · "quem está em cada etapa": as pessoas que pararam ali, para abrir a conversa com um clique.
#
# As colunas são achadas pelo NOME (em qualquer funil da conta). Coluna que não existe só deixa aquele sinal de
# fora; os outros continuam valendo.
class Otica::Journey # rubocop:disable Metrics/ClassLength
  STEPS = [
    { key: 'leads', label: 'Novos contatos', short: 'Novos', group: 'conversa' },
    { key: 'foto', label: 'Mandou a foto', short: 'Foto', group: 'conversa' },
    { key: 'prova', label: 'Recebeu a prova virtual', short: 'Prova', group: 'conversa' },
    { key: 'agendou', label: 'Agendou', short: 'Agendou', group: 'conversa' },
    { key: 'confirmou', label: 'Confirmou', short: 'Confirm.', group: 'conversa' },
    { key: 'veio', label: 'Veio à loja', short: 'Veio', group: 'loja' },
    { key: 'comprou', label: 'Comprou', short: 'Comprou', group: 'loja' },
    { key: 'pronto', label: 'Óculos pronto', short: 'Pronto', group: 'loja' },
    { key: 'retirou', label: 'Retirou o óculos', short: 'Retirou', group: 'loja' }
  ].freeze
  GROUPS = [{ key: 'conversa', label: 'Na conversa' }, { key: 'loja', label: 'Na loja' }].freeze
  STAGE_NAMES = {
    'agendou' => /\Aagendamento da visita/,
    'confirmou' => /\Avisita confirmada/,
    'veio' => /\Avisita realizada/,
    'comprou' => /\Apedido fechado/,
    'pronto' => /\Apronto para retirar/,
    'retirou' => /\A(retirou o oculos|1 semana|30 dias)/
  }.freeze
  MISSED_STAGE = /\Adesmarcou ou nao veio/
  PIX_STAGES = { 'pedido' => /\Apix do exame/, 'pago' => /\Aexame pago/ }.freeze
  PIX_PAID_LABEL = 'exame-pago'.freeze
  READY_STATUSES = %w[pronta entregue].freeze
  JUMPS = [%w[leads agendou], %w[leads comprou]].freeze
  SOURCES = Crm::WhatsappOrigin::LABELS.invert.freeze # 'origem-anuncio' => 'anuncio'
  SOURCE_LABELS = { 'anuncio' => 'Anúncio', 'formulario' => 'Formulário', 'site' => 'Site', 'direto' => 'Direto',
                    'sem_origem' => 'Sem origem' }.freeze
  PEOPLE_PER_STEP = 30

  def initialize(account, since:, until_at:)
    @account = account
    @since = since
    @until = until_at
  end

  def call
    reach = lead_ids.index_with { |id| reached_index(id) }
    { since: @since, until: @until, groups: GROUPS,
      steps: steps_json(reach), jumps: jumps_json(reach.values), sources: sources_json(reach),
      money: money_json(lead_ids), extras: extras_json }
  end

  # índice da etapa mais adiantada que a pessoa alcançou (0 = só chegou)
  def reached_index(contact_id)
    STEPS.each_index.reverse_each.find { |i| i.zero? || signals[STEPS[i][:key]].include?(contact_id) }
  end

  private

  def lead_ids
    @lead_ids ||= Crm::LeadsUniverse.scope(@account, @since, @until).pluck(:id).uniq
  end

  # por etapa, quem tem o sinal dela: { 'foto' => Set[contact_id, …], … }
  def signals # rubocop:disable Metrics/AbcSize
    @signals ||= {
      'foto' => with_selfie,
      'prova' => with_try_on,
      'agendou' => in_stage('agendou') | ids(bookings),
      'confirmou' => in_stage('confirmou') | ids(bookings.where.not(confirmed_at: nil)),
      'veio' => in_stage('veio') | ids(bookings.where(attendance: 'attended')),
      'comprou' => in_stage('comprou') | ids(orders),
      'pronto' => in_stage('pronto') | ids(orders.where(status: READY_STATUSES)) | ids(orders.where.not(ready_at: nil)),
      'retirou' => in_stage('retirou') | ids(orders.where(status: 'entregue')) | ids(orders.where.not(delivered_at: nil))
    }
  end

  def ids(relation)
    Set.new(relation.reorder(nil).distinct.pluck(:contact_id))
  end

  # ── sinais ──────────────────────────────────────────────────────────────
  def norm(text)
    I18n.transliterate(text.to_s).downcase.squish
  end

  def stages
    @stages ||= Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).to_a
  end

  def stage_ids_for(pattern)
    stages.select { |s| norm(s.name).match?(pattern) }.map(&:id)
  end

  # o cartão da pessoa entrou (ou está) numa coluna que casa com o nome
  def in_stage(key, pattern = STAGE_NAMES[key])
    ids = stage_ids_for(pattern)
    return Set.new if ids.empty? || lead_ids.empty?

    logged = Crm::StageLog.joins(:crm_contact).where(stage_id: ids, crm_contacts: { contact_id: lead_ids })
                          .distinct.pluck('crm_contacts.contact_id')
    now_there = Crm::Contact.where(stage_id: ids, contact_id: lead_ids).pluck(:contact_id)
    Set.new(logged + now_there)
  end

  def conversation_rows
    @conversation_rows ||= @account.conversations.where(contact_id: lead_ids).order(:id).pluck(:id, :contact_id)
  end

  def contact_of_conversation
    @contact_of_conversation ||= conversation_rows.to_h
  end

  def with_selfie
    ids = Attachment.joins(:message)
                    .where(account_id: @account.id, messages: { conversation_id: contact_of_conversation.keys, message_type: :incoming })
                    .where("attachments.meta -> 'cevico_media' ->> 'tipo' = 'selfie'")
                    .reorder(nil).distinct.pluck('messages.conversation_id')
    Set.new(ids.filter_map { |id| contact_of_conversation[id] })
  end

  def with_try_on
    ids = Message.where(account_id: @account.id, conversation_id: contact_of_conversation.keys, message_type: :outgoing)
                 .where('messages.additional_attributes ? :key', key: Otica::VirtualTryOn::STAMP_KEY)
                 .reorder(nil).distinct.pluck(:conversation_id)
    Set.new(ids.filter_map { |id| contact_of_conversation[id] })
  end

  def bookings
    @account.tasks.where(task_type: 'consulta', contact_id: lead_ids)
  end

  def orders
    @account.otica_orders.where(contact_id: lead_ids, status: Otica::StockReport::SOLD_STATUSES)
  end

  # ── saída ───────────────────────────────────────────────────────────────
  def counts(reached)
    STEPS.each_index.map { |i| reached.count { |r| r >= i } }
  end

  def pct(part, whole)
    whole.to_i.positive? ? (part * 100.0 / whole).round : nil
  end

  def steps_json(reach) # rubocop:disable Metrics/AbcSize
    totals = counts(reach.values)
    stopped = reach.group_by(&:last).transform_values { |rows| rows.map(&:first) }
    STEPS.each_with_index.map do |step, i|
      here = Array(stopped[i])
      { key: step[:key], label: step[:label], short: step[:short], group: step[:group], count: totals[i],
        of_leads: pct(totals[i], totals[0]), to_next: totals[i + 1] && pct(totals[i + 1], totals[i]),
        stopped: here.size, people: people_json(here) }
    end
  end

  # quem parou nesta etapa: os mais recentes primeiro, com a conversa para abrir
  def people_json(contact_ids)
    return [] if contact_ids.empty?

    last_conversation = conversation_rows.each_with_object({}) { |(conv, contact), out| out[contact] = conv }
    @account.contacts.where(id: contact_ids).order(created_at: :desc).limit(PEOPLE_PER_STEP)
            .pluck(:id, :name, :phone_number, :created_at).map do |id, name, phone, created_at|
      { id: id, name: name.presence || phone.presence || "Contato #{id}", arrived_at: created_at,
        conversation_id: last_conversation[id], source: SOURCE_LABELS[source_by_contact[id] || 'sem_origem'] }
    end
  end

  def jumps_json(reached)
    totals = counts(reached)
    index = STEPS.each_with_index.to_h { |step, i| [step[:key], i] }
    JUMPS.map do |from, to|
      { from: from, to: to, from_label: STEPS[index[from]][:label], to_label: STEPS[index[to]][:label],
        count: totals[index[to]], pct: pct(totals[index[to]], totals[index[from]]) }
    end
  end

  # fonte de cada pessoa: a etiqueta de origem das conversas dela
  def source_by_contact
    @source_by_contact ||= begin
      labels = tagged('Conversation', SOURCES.keys, conversation_rows.map(&:first))
      conversation_rows.each_with_object({}) do |(conversation_id, contact_id), out|
        label = Array(labels[conversation_id]).first
        out[contact_id] ||= SOURCES[label] if label
      end
    end
  end

  def tagged(type, names, ids)
    return {} if ids.empty?

    ActsAsTaggableOn::Tagging.joins(:tag).where(taggable_type: type, taggable_id: ids, context: 'labels', tags: { name: names })
                             .pluck(:taggable_id, 'tags.name').group_by(&:first).transform_values { |rows| rows.map(&:last) }
  end

  def sources_json(reach)
    groups = reach.group_by { |contact_id, _| source_by_contact[contact_id] || 'sem_origem' }
    booked = STEPS.index { |s| s[:key] == 'agendou' }
    bought = STEPS.index { |s| s[:key] == 'comprou' }
    SOURCE_LABELS.filter_map do |key, label|
      rows = Array(groups[key])
      next if rows.empty?

      totals = counts(rows.map(&:last))
      { key: key, label: label, counts: totals, lead_to_booked: pct(totals[booked], totals[0]),
        lead_to_bought: pct(totals[bought], totals[0]), revenue: money_json(rows.map(&:first))[:revenue] }
    end
  end

  # o dinheiro de quem chegou no período: as O.S. vendidas dessas pessoas (até hoje)
  def money_json(contact_ids)
    scope = @account.otica_orders.where(contact_id: contact_ids, status: Otica::StockReport::SOLD_STATUSES)
    sales, revenue = scope.pick(Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(net), 0)'))
    revenue = revenue.to_f.round(2)
    { sales: sales.to_i, revenue: revenue, ticket: sales.to_i.positive? ? (revenue / sales).round(2) : nil }
  end

  # o que acontece AO LADO da linha principal: quem desmarcou/faltou e o exame pago no PIX (se a conta usa)
  def extras_json
    missed = in_stage(nil, MISSED_STAGE) | ids(bookings.where(attendance: 'missed'))
    out = { missed: missed.size, exams: ids(bookings.where(modality: 'exame')).size }
    return out if stage_ids_for(PIX_STAGES['pedido']).empty?

    paid = in_stage(nil, PIX_STAGES['pago']) | labeled(PIX_PAID_LABEL)
    out.merge(pix_asked: (in_stage(nil, PIX_STAGES['pedido']) | paid).size, pix_paid: paid.size)
  end

  # a etiqueta no contato ou em alguma conversa dele
  def labeled(name)
    by_conversation = tagged('Conversation', [name], contact_of_conversation.keys).keys.filter_map { |id| contact_of_conversation[id] }
    Set.new(tagged('Contact', [name], lead_ids).keys + by_conversation)
  end
end
