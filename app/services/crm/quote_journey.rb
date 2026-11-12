# 🧭 JORNADA DO ORÇAMENTO (12/11/2026 · LIFE, pedido do Guilherme): "gosto de ver a conversão de uma
# etapa para outra, os indicadores de cada etapa e de cada fonte de tráfego… de uma forma mais
# simplificada, com menos texto e mais objetividade."
#
# Como conta (uma régua só, explicável):
#   · pega quem CHEGOU no período (os leads novos do Meu Painel — Crm::LeadsUniverse);
#   · para cada pessoa, vê até onde ela já andou na jornada, com o que o sistema registrou:
#       pedido   = o cartão entrou na coluna "Solicitação da Conta"
#       conta    = conta anotada no resumo do cliente, tarefa "Orçamento: conta recebida" ou cartão
#                  na coluna "Orçamento a fazer"
#       gerado   = orçamento criado no Gerador (Crm::Quote) ou cartão em "Orçamento pronto"
#       enviado  = orçamento marcado como enviado, etiqueta `orcamento-enviado` ou cartão em
#                  "Orçamento Enviado"
#       fechado  = cartão em "Contrato Assinado"
#   · quem chegou a uma etapa conta também nas anteriores (o funil nunca "cresce" no meio);
#   · conversão = desta etapa para a seguinte; mais dois saltos (lead → enviado, lead → fechado);
#   · fonte = a etiqueta de origem da conversa (anúncio, formulário, site, direto; Crm::WhatsappOrigin).
#
# As colunas são achadas pelo NOME no funil principal (com os nomes antigos também). Coluna que
# não existe na conta só deixa aquele sinal de fora — os outros continuam valendo.
class Crm::QuoteJourney
  PERIODS = [7, 30, 90].freeze
  DEFAULT_DAYS = 30
  STEPS = [
    { key: 'leads', label: 'Chegaram', short: 'Chegaram' },
    { key: 'pedido', label: 'Conta pedida', short: 'Pedida' },
    { key: 'conta', label: 'Conta recebida', short: 'Recebida' },
    { key: 'gerado', label: 'Orçamento gerado', short: 'Gerado' },
    { key: 'enviado', label: 'Orçamento enviado', short: 'Enviado' },
    { key: 'fechado', label: 'Fechado', short: 'Fechado' }
  ].freeze
  STAGE_NAMES = {
    'pedido' => /\Asolicitacao da conta\z/,
    'conta' => /\A(orcamento a fazer|recebimento da conta)\z/,
    'gerado' => /\A(orcamento pronto|orcamento gerado)\z/,
    'enviado' => /\Aorcamento enviado\z/,
    'fechado' => /\Acontrato assinado\z/
  }.freeze
  JUMPS = [%w[leads enviado], %w[leads fechado]].freeze
  SOURCES = Crm::WhatsappOrigin::LABELS.invert.freeze # 'origem-anuncio' => 'anuncio'
  SOURCE_LABELS = { 'anuncio' => 'Anúncio', 'formulario' => 'Formulário', 'site' => 'Site', 'direto' => 'Direto',
                    'sem_origem' => 'Sem origem' }.freeze
  BILL_TASK = 'Orçamento: conta recebida'.freeze

  def self.days(value)
    PERIODS.include?(value.to_i) ? value.to_i : DEFAULT_DAYS
  end

  def initialize(account, days: DEFAULT_DAYS, now: Time.current)
    @account = account
    @days = self.class.days(days)
    @now = now
    @since = now - @days.days
  end

  def call
    reach = lead_ids.index_with { |id| reached_index(id) }
    { days: @days, periods: PERIODS, since: @since, until: @now,
      steps: steps_json(reach.values), jumps: jumps_json(reach.values), sources: sources_json(reach) }
  end

  private

  # quem chegou no período: a mesma régua de "leads novos" do Meu Painel
  def lead_ids
    @lead_ids ||= Crm::LeadsUniverse.scope(@account, @since, @now).pluck(:id).uniq
  end

  # índice da etapa mais adiantada que a pessoa alcançou (0 = só chegou)
  def reached_index(contact_id)
    STEPS.each_index.reverse_each.find { |i| i.zero? || signals[STEPS[i][:key]].include?(contact_id) }
  end

  # por etapa, quem tem o sinal dela: { 'pedido' => Set[contact_id, …], … }
  def signals
    @signals ||= {
      'pedido' => in_stage('pedido'),
      'conta' => in_stage('conta') | with_bill_noted | with_bill_task,
      'gerado' => in_stage('gerado') | quotes(sent: false),
      'enviado' => in_stage('enviado') | quotes(sent: true) | with_sent_label,
      'fechado' => in_stage('fechado')
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
      conversations = @account.conversations.where(contact_id: lead_ids).order(:id).pluck(:id, :contact_id)
      labels = contact_ids_tagged('Conversation', SOURCES.keys, conversations.map(&:first))
      conversations.each_with_object({}) do |(conversation_id, contact_id), out|
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
      { key: key, label: label, counts: totals, lead_to_sent: pct(totals[4], totals[0]), lead_to_closed: pct(totals[5], totals[0]) }
    end
  end
end
