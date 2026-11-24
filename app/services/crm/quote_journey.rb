# 🧭 JORNADA DA VENDA (12/11/2026 · LIFE, pedido do Guilherme): "gosto de ver a conversão de uma
# etapa para outra, os indicadores de cada etapa e de cada fonte de tráfego… de uma forma mais
# simplificada, com menos texto e mais objetividade."
# ☀️ 16/11/2026 (pedido do Guilherme): "mudar a nomenclatura… para o mercado de energia solar". O fluxo é o dele:
# novo contato → sondagem → conta para o orçamento → orçamento gerado e enviado → pré-aprovação do crédito →
# proposta de fechamento → contrato fechado (daí instalação e pós-venda). E o período é a régua normal do sistema
# (hoje, ontem, 7 dias, semana passada…).
# 🧭 18/11/2026 (pedido do Guilherme): "corrigir o traqueamento… no meu painel ele não está registrando, enquanto na
# realidade a gente já conseguiu avançar pelo CPF". Depois do orçamento enviado o caminho é: é possível fazer o
# investimento? → forma de pagamento (cartão ou financiamento) → CPF e pré-aprovação do crédito (só no financiamento;
# cartão e à vista passam direto) → proposta de fechamento → contrato fechado → instalação realizada.
#
# Como conta (uma régua só, explicável):
#   · pega quem CHEGOU no período (os leads novos do Meu Painel — Crm::LeadsUniverse);
#   · para cada pessoa, vê até onde ela já andou na jornada, com o que o sistema registrou:
#       sondagem = alguma informação anotada no resumo do cliente, ou o cartão entrou em "Solicitação da Conta"
#       conta    = conta anotada no resumo do cliente, tarefa "Orçamento: conta recebida" ou cartão
#                  na coluna "Orçamento a fazer"
#       enviado  = orçamento marcado como enviado, etiqueta `orcamento-enviado` ou cartão em
#                  "Orçamento Enviado"
#       investimento = etiqueta `investimento-possivel` (o cliente disse SIM à pergunta de fechamento)
#       pagamento = forma de pagamento anotada na ficha (etiqueta `quer-fechar`) ou cartão numa coluna de vistoria
#       credito  = CPF anotado na ficha, etiqueta `credito-pre-aprovado`, ou forma de pagamento sem crédito
#                  (cartão, à vista), que não precisa de pré-aprovação
#       proposta = etiqueta `proposta-de-fechamento` ou cartão na coluna "Negociação"
#       fechado  = etiqueta `contrato-fechado` ou cartão em "Contrato Assinado", "Homologação" ou "Instalação"
#       instalado = etiqueta `instalacao-realizada` ou cartão no pós-venda
#   · as etiquetas valem no contato ou em alguma conversa dele; quem marca: o atendente de IA (ficha do cliente)
#     e a equipe, pelos botões "Etapa da venda" (Crm::SaleSteps);
#   · quem chegou a uma etapa conta também nas anteriores (o funil nunca "cresce" no meio);
#   · conversão = desta etapa para a seguinte; mais dois saltos (novo → orçamento, novo → contrato);
#   · fonte = a etiqueta de origem da conversa (anúncio, formulário, site, direto; Crm::WhatsappOrigin).
#
# As colunas são achadas pelo NOME no funil principal (com os nomes antigos também). Coluna que
# não existe na conta só deixa aquele sinal de fora — os outros continuam valendo.
class Crm::QuoteJourney # rubocop:disable Metrics/ClassLength
  STEPS = [
    { key: 'leads', label: 'Novos contatos', short: 'Novos' },
    { key: 'sondagem', label: 'Sondagem', short: 'Sondagem' },
    { key: 'conta', label: 'Conta para orçamento', short: 'Conta' },
    { key: 'enviado', label: 'Orçamento enviado', short: 'Orçam.' },
    { key: 'investimento', label: 'Investimento possível', short: 'Possível' },
    { key: 'pagamento', label: 'Forma de pagamento', short: 'Pagam.' },
    { key: 'credito', label: 'CPF e crédito', short: 'Crédito' },
    { key: 'proposta', label: 'Proposta de fechamento', short: 'Proposta' },
    { key: 'fechado', label: 'Contrato fechado', short: 'Contrato' },
    { key: 'instalado', label: 'Instalação realizada', short: 'Instalado' }
  ].freeze
  STAGE_NAMES = {
    'sondagem' => /\A(sondagem|solicitacao da conta)\z/,
    'conta' => /\A(orcamento a fazer|recebimento da conta)\z/,
    'enviado' => /\Aorcamento enviado\z/,
    'pagamento' => /vistoria|visita tecnica/,
    'credito' => /credito|pre.?aprovac/,
    'proposta' => /\A(negociacao|proposta.*)\z/,
    'fechado' => /\A(contrato (assinado|fechado)|homologacao|instalacao)\z/,
    'instalado' => /pos.?venda|instalacao realizada|instalado/
  }.freeze
  # etiquetas de cada etapa (no contato ou na conversa)
  STEP_LABELS = {
    'investimento' => %w[investimento-possivel],
    'pagamento' => %w[quer-fechar],
    'credito' => %w[credito-pre-aprovado credito-aprovado],
    'proposta' => %w[proposta-de-fechamento],
    'fechado' => %w[contrato-fechado],
    'instalado' => %w[instalacao-realizada]
  }.freeze
  # forma de pagamento que NÃO passa por pré-aprovação de crédito (cartão, à vista)
  NO_CREDIT_PAYMENT = /cart|vista|pix|dinheiro|boleto/i
  FINANCING = /financ/i
  JUMPS = [%w[leads enviado], %w[leads fechado]].freeze
  SOURCES = Crm::WhatsappOrigin::LABELS.invert.freeze # 'origem-anuncio' => 'anuncio'
  SOURCE_LABELS = { 'anuncio' => 'Anúncio', 'formulario' => 'Formulário', 'site' => 'Site', 'direto' => 'Direto',
                    'sem_origem' => 'Sem origem' }.freeze
  BILL_TASK = 'Orçamento: conta recebida'.freeze

  # since/until_at = o período escolhido na régua normal do sistema (Crm::ResolvesPeriod)
  # contact_ids = em vez do período, só estas pessoas (a etapa de UM cliente: Crm::SaleSteps)
  def initialize(account, since: nil, until_at: nil, contact_ids: nil)
    @account = account
    @since = since
    @until = until_at
    @lead_ids = Array(contact_ids).map(&:to_i).uniq if contact_ids
  end

  # series_since/series_until (24/11): a janela do mini gráfico de cada etapa — a do período ou, em "hoje" e "ontem",
  # os 7 dias que terminam nele
  def call(series_since: nil, series_until: nil)
    out = { since: @since, until: @until,
            steps: steps_json(reach.values), jumps: jumps_json(reach.values), sources: sources_json(reach) }
    out[:series] = series(series_since || @since, series_until || @until) if @since && @until
    out
  end

  # 📈 24/11 (Guilherme: "cada indicador com um mini gráfico de linha com o histórico… hoje e ontem, 7 dias; semana
  # passada, a semana; o mês, o mês; 90 dias, esse ano…"). Mesma régua dos cartões, por data de chegada: em cada dia
  # (semana ou mês) do gráfico, quantos dos que chegaram ali alcançaram a etapa.
  def series(from, to)
    journey = from == @since && to == @until ? self : self.class.new(@account, since: from, until_at: to)
    journey.series_json
  end

  def series_json
    gran = granularity
    starts = bucket_starts(gran)
    rows = reach_by_bucket(starts)
    { granularity: gran, labels: starts.map { |start| bucket_label(start, gran) },
      values: STEPS.each_with_index.to_h { |step, i| [step[:key], rows.map { |list| list.count { |r| r >= i } }] } }
  end

  # 👥 24/11 ("janelas expansíveis para mostrar quem foram os contatos, poder abrir a conversa"): quem chegou no período
  # e alcançou a etapa; 'parou' = esta é a etapa mais adiantada da pessoa
  def people(step_key, limit: 300)
    index = step_index(step_key.to_s)
    return [] if index.nil?

    ids = reach.select { |_, r| r >= index }.keys
    extras = { conversations: latest_conversations(ids), stages: current_stages(ids) }
    @account.contacts.where(id: ids).order(created_at: :desc).limit(limit).pluck(:id, :name, :phone_number, :created_at)
            .map { |row| person_json(row, index, extras) }
  end

  # índice da etapa mais adiantada que a pessoa alcançou (0 = só chegou)
  def reached_index(contact_id)
    STEPS.each_index.reverse_each.find { |i| i.zero? || signals[STEPS[i][:key]].include?(contact_id) }
  end

  protected

  def reach
    @reach ||= lead_ids.index_with { |id| reached_index(id) }
  end

  private

  TZ = Crm::ResolvesPeriod::PERIOD_TZ

  # [[alcances de quem chegou no 1º balde], …]
  def reach_by_bucket(starts)
    rows = starts.map { [] }
    @account.contacts.where(id: lead_ids).pluck(:id, :created_at).each do |id, at|
      index = starts.rindex { |start| at >= start }
      rows[index] << reach[id] if index
    end
    rows
  end

  def latest_conversations(ids)
    @account.conversations.where(contact_id: ids).order(:last_activity_at, :id).pluck(:contact_id, :display_id).to_h
  end

  def current_stages(ids)
    Crm::Contact.where(contact_id: ids).includes(:stage).to_h { |card| [card.contact_id, card.stage&.name] }
  end

  def person_json((id, name, phone, created_at), index, extras)
    { id: id, contact_id: id, name: name.presence || phone, phone: phone, when: created_at&.iso8601,
      origin: SOURCE_LABELS[source_by_contact[id] || 'sem_origem'], conversation_id: extras[:conversations][id],
      meta: extras[:stages][id], parou: reach[id] == index, etapa: STEPS[reach[id]][:label] }
  end

  # dia até 31 dias, semana até 120, mês acima disso
  def granularity
    days = ((@until - @since) / 1.day).ceil
    return 'day' if days <= 31

    days <= 120 ? 'week' : 'month'
  end

  def bucket_starts(gran)
    first = @since.in_time_zone(TZ)
    first = { 'day' => first.beginning_of_day, 'week' => first.beginning_of_week, 'month' => first.beginning_of_month }[gran]
    step = { 'day' => 1.day, 'week' => 1.week, 'month' => 1.month }[gran]
    starts = []
    cursor = first
    while cursor <= @until
      starts << cursor
      cursor += step
    end
    starts
  end

  MONTHS = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  def bucket_label(start, gran)
    gran == 'month' ? MONTHS[start.month - 1] : start.strftime('%d/%m')
  end

  # quem chegou no período: a mesma régua de "leads novos" do Meu Painel
  def lead_ids
    @lead_ids ||= Crm::LeadsUniverse.scope(@account, @since, @until).pluck(:id).uniq
  end

  # por etapa, quem tem o sinal dela: { 'sondagem' => Set[contact_id, …], … }
  def signals
    @signals ||= quote_signals.merge(closing_signals)
  end

  # até o orçamento enviado
  def quote_signals
    {
      'sondagem' => in_stage('sondagem') | with_summary_noted,
      'conta' => in_stage('conta') | with_bill_noted | with_bill_task,
      'enviado' => in_stage('enviado') | quotes(sent: true) | with_sent_label
    }
  end

  # do "é possível?" até a instalação
  def closing_signals
    {
      'investimento' => labeled('investimento'),
      'pagamento' => in_stage('pagamento') | labeled('pagamento') | with_payment_noted,
      'credito' => in_stage('credito') | labeled('credito') | with_cpf_noted | with_payment_without_credit,
      'proposta' => in_stage('proposta') | labeled('proposta'),
      'fechado' => in_stage('fechado') | labeled('fechado'),
      'instalado' => in_stage('instalado') | labeled('instalado')
    }
  end

  # ── sinais ──────────────────────────────────────────────────────────────
  def norm(text)
    I18n.transliterate(text.to_s).downcase.squish
  end

  def stage_ids
    @stage_ids ||= begin
      pipeline = Crm::Pipeline.where(account: @account).order(:position, :id).first
      stages = pipeline ? pipeline.stages.to_a : []
      STAGE_NAMES.transform_values { |pattern| stages.select { |s| norm(s.name).match?(pattern) }.map(&:id) }
    end
  end

  # o cartão da pessoa entrou (ou está) na coluna desta etapa
  def in_stage(key)
    ids = stage_ids[key]
    return Set.new if ids.empty? || lead_ids.empty?

    logged = Crm::StageLog.joins(:crm_contact).where(stage_id: ids, crm_contacts: { contact_id: lead_ids }).distinct.pluck('crm_contacts.contact_id')
    now_there = Crm::Contact.where(stage_id: ids, contact_id: lead_ids).pluck(:contact_id)
    Set.new(logged + now_there)
  end

  # a sondagem começou: já tem alguma resposta anotada no resumo do cliente (cidade, telhado, conta…)
  def with_summary_noted
    key = Crm::ClientSummary::ATTR_KEY
    Set.new(@account.contacts.where(id: lead_ids).where("jsonb_typeof(additional_attributes -> ?) = 'object'", key)
                    .where('additional_attributes -> ? <> ?::jsonb', key, '{}').pluck(:id))
  end

  def with_bill_noted
    key = Crm::ClientSummary::ATTR_KEY
    Set.new(@account.contacts.where(id: lead_ids).where("additional_attributes -> ? -> 'conta' ->> 'valor' <> ''", key).pluck(:id))
  end

  def with_bill_task
    Set.new(@account.tasks.where(contact_id: lead_ids).where('tasks.title LIKE ?', "%#{BILL_TASK}%").distinct.pluck(:contact_id))
  end

  def quotes(sent:)
    scope = Crm::Quote.where(account_id: @account.id, contact_id: lead_ids)
    scope = scope.where.not(sent_at: nil) if sent
    Set.new(scope.distinct.pluck(:contact_id))
  end

  # a etiqueta da etapa no contato ou em alguma conversa dele
  def labeled(key)
    names = STEP_LABELS[key]
    tagged = contact_ids_tagged('Conversation', names, conversation_rows.map(&:first))
    by_conversation = conversation_rows.select { |conversation_id, _| tagged.key?(conversation_id) }.map(&:last)
    Set.new(contact_ids_tagged('Contact', names).keys + by_conversation)
  end

  # { contact_id => 'cartão: 6x' } de quem tem o campo da ficha preenchido
  def ficha_values(field)
    @ficha_values ||= {}
    @ficha_values[field] ||= begin
      key = Crm::ClientSummary::ATTR_KEY
      @account.contacts.where(id: lead_ids).where("additional_attributes -> ? -> ? ->> 'valor' <> ''", key, field)
              .pluck(:id, :additional_attributes).to_h.transform_values { |attrs| attrs.dig(key, field, 'valor').to_s }
    end
  end

  def with_payment_noted
    Set.new(ficha_values('forma_pagamento').keys)
  end

  def with_cpf_noted
    Set.new(ficha_values('cpf').keys)
  end

  # cartão e à vista não passam por pré-aprovação: a etapa do crédito já está resolvida
  def with_payment_without_credit
    Set.new(ficha_values('forma_pagamento').select { |_, value| value.match?(NO_CREDIT_PAYMENT) && !value.match?(FINANCING) }.keys)
  end

  # [[conversation_id, contact_id], …] de quem chegou
  def conversation_rows
    @conversation_rows ||= @account.conversations.where(contact_id: lead_ids).order(:id).pluck(:id, :contact_id)
  end

  def with_sent_label
    Set.new(contact_ids_tagged('Contact', [Crm::QuoteSent::LABEL]).keys)
  end

  # { id => [etiquetas] } dos registros (contatos ou conversas) que têm alguma das etiquetas
  def contact_ids_tagged(type, names, ids = lead_ids)
    return {} if ids.empty?

    ActsAsTaggableOn::Tagging.joins(:tag).where(taggable_type: type, taggable_id: ids, context: 'labels', tags: { name: names })
                             .pluck(:taggable_id, 'tags.name').group_by(&:first).transform_values { |rows| rows.map(&:last) }
  end

  # ── saída ───────────────────────────────────────────────────────────────
  # quantos alcançaram cada etapa (quem foi além conta também)
  def counts(reached)
    STEPS.each_index.map { |i| reached.count { |r| r >= i } }
  end

  def step_index(key)
    STEPS.index { |step| step[:key] == key }
  end

  def pct(part, whole)
    whole.to_i.positive? ? (part * 100.0 / whole).round : nil
  end

  def steps_json(reached)
    totals = counts(reached)
    STEPS.each_with_index.map do |step, i|
      { key: step[:key], label: step[:label], short: step[:short], count: totals[i], of_leads: pct(totals[i], totals[0]),
        to_next: totals[i + 1] && pct(totals[i + 1], totals[i]) }
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
      labels = contact_ids_tagged('Conversation', SOURCES.keys, conversation_rows.map(&:first))
      conversation_rows.each_with_object({}) do |(conversation_id, contact_id), out|
        label = Array(labels[conversation_id]).first
        out[contact_id] ||= SOURCES[label] if label
      end
    end
  end

  def sources_json(reach)
    groups = reach.group_by { |contact_id, _| source_by_contact[contact_id] || 'sem_origem' }
    SOURCE_LABELS.filter_map do |key, label|
      reached = Array(groups[key]).map(&:last)
      next if reached.empty?

      totals = counts(reached)
      { key: key, label: label, counts: totals, lead_to_sent: pct(totals[step_index('enviado')], totals[0]),
        lead_to_closed: pct(totals[step_index('fechado')], totals[0]) }
    end
  end
end
