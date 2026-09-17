# 🗺️ MAPA DE FLUXOS (item 170): descrição declarativa de um agente/automação
# (gatilho → decisões → ações → saídas) que vira um fluxograma Mermaid na
# aba "Fluxos" das Automações. Cada arquivo em flows/*.rb chama
# `Flow.define(:chave) do … end`; o `live` lê o estado ao vivo da conta
# (ligado/desligado, última execução, contadores) sem nunca derrubar a lista.
#
# Regra: os nós de decisão correspondem aos `if/return` REAIS do job —
# fonte em docs/MAPEAMENTO_FLUXOS_JOBS.md. Não inventar condições.
class Crm::FlowMap::Flow
  KINDS = %i[trigger decision action ai loop output external end].freeze
  TRIGGER_KINDS = %i[cron event webhook manual].freeze
  GROUPS = [
    'Atendimento ao paciente',
    'Vendas e fechamento',
    'Marketing e aquisição',
    'Gestão e evolução do time',
    'Infraestrutura'
  ].freeze

  # forma de cada tipo de nó no Mermaid (abre/fecha em volta do rótulo)
  SHAPES = {
    trigger: ['([', '])'],
    decision: ['{', '}'],
    action: ['[', ']'],
    ai: ['[[', ']]'],
    loop: ['[/', '/]'],
    output: ['[(', ')]'],
    external: ['>', ']'],
    end: ['((', '))']
  }.freeze

  # cores suaves que leem bem no claro e no escuro (texto sempre escuro
  # sobre fundo claro — o tema do Mermaid não precisa adivinhar).
  # Nomes com prefixo cv_ porque `end` é palavra reservada do Mermaid.
  CLASS_DEFS = {
    cv_trigger: 'fill:#DBEAFE,stroke:#2563EB,color:#1E3A8A',
    cv_decision: 'fill:#FEF3C7,stroke:#D97706,color:#78350F',
    cv_action: 'fill:#F1F5F9,stroke:#64748B,color:#0F172A',
    cv_ai: 'fill:#EDE9FE,stroke:#7C3AED,color:#4C1D95',
    cv_loop: 'fill:#E0F2FE,stroke:#0284C7,color:#0C4A6E',
    cv_output: 'fill:#DCFCE7,stroke:#16A34A,color:#14532D',
    cv_external: 'fill:#FCE7F3,stroke:#DB2777,color:#831843',
    cv_fim: 'fill:#E2E8F0,stroke:#475569,color:#1E293B',
    # desligado: tudo cinza e tracejado (definido por último para vencer)
    cv_off: 'fill:#F1F5F9,stroke:#CBD5E1,color:#94A3B8,stroke-dasharray:4 3'
  }.freeze

  Node = Struct.new(:id, :label, :kind, keyword_init: true)
  Edge = Struct.new(:from, :to, :label, keyword_init: true)

  attr_reader :key, :nodes, :edges

  def self.define(key, &)
    new(key).tap { |flow| flow.instance_eval(&) }
  end

  def initialize(key)
    @key = key.to_s
    @nodes = []
    @edges = []
    @jobs = []
    @config = {}
    @trigger = { kind: :manual, label: 'manual' }
    @live = nil
  end

  # ── DSL ─────────────────────────────────────────────────────────────
  def name(value = nil)
    value.nil? ? @name : (@name = value)
  end

  def group(value = nil)
    return @group if value.nil?
    raise ArgumentError, "grupo desconhecido: #{value}" unless GROUPS.include?(value)

    @group = value
  end

  def icon(value = nil)
    value.nil? ? @icon : (@icon = value)
  end

  def color(value = nil)
    value.nil? ? @color : (@color = value)
  end

  def what(value = nil)
    value.nil? ? @what : (@what = value)
  end

  # onde abrir ao clicar: { tab:, anchor: } (aba do hub) ou { route: } (rota nomeada)
  def config(**opts)
    opts.empty? ? @config : (@config = opts)
  end

  # o gatilho vira o primeiro nó (id :trigger) — cron | event | webhook | manual
  def trigger(kind = nil, label = nil)
    return @trigger if kind.nil?
    raise ArgumentError, "gatilho desconhecido: #{kind}" unless TRIGGER_KINDS.include?(kind)

    @trigger = { kind: kind, label: label.to_s }
    node(:trigger, label, kind: :trigger)
  end

  # classes de job (config/schedule.yml) que este fluxo cobre — a spec do
  # registro exige que todo job CEVICO agendado apareça em algum fluxo
  def jobs(*classes)
    classes.empty? ? @jobs : (@jobs = classes.map(&:to_s))
  end

  def node(id, label, kind: :action)
    raise ArgumentError, "tipo de nó desconhecido: #{kind}" unless KINDS.include?(kind)

    nid = normalize_id(id)
    raise ArgumentError, "nó repetido: #{id}" if @nodes.any? { |n| n.id == nid }

    @nodes << Node.new(id: nid, label: label.to_s, kind: kind)
  end

  def edge(from, to, label = nil)
    @edges << Edge.new(from: normalize_id(from), to: normalize_id(to), label: label&.to_s)
  end

  def live(&block)
    @live = block
  end

  # ── saída ───────────────────────────────────────────────────────────
  def validate!
    ids = @nodes.map(&:id)
    @edges.each do |e|
      raise ArgumentError, "fluxo #{@key}: aresta #{e.from} → #{e.to} aponta para nó inexistente" unless ids.include?(e.from) && ids.include?(e.to)
    end
    raise ArgumentError, "fluxo #{@key}: sem nome" if @name.blank?
    raise ArgumentError, "fluxo #{@key}: sem grupo" if @group.blank?

    self
  end

  # estado ao vivo — erro vira nota, nunca exceção
  def live_state(account)
    base = { enabled: nil, last_run_at: nil, counters: {}, note: nil }
    return base unless @live

    result = LiveContext.new(account).instance_exec(account, &@live) || {}
    base.merge(normalize_live(result))
  rescue StandardError => e
    Rails.logger.warn("[FlowMap] live #{@key}: #{e.class} #{e.message}")
    base.merge(note: "estado indisponível: #{e.message.to_s.truncate(120)}")
  end

  # flowchart TD com ids estáveis (<chave>_<nó>), rótulos entre aspas,
  # classDef por tipo e `class … off` quando o fluxo está desligado
  def to_mermaid(enabled: nil)
    lines = ['flowchart TD']
    @nodes.each { |n| lines << "  #{mermaid_id(n)}#{SHAPES[n.kind][0]}\"#{escape(n.label)}\"#{SHAPES[n.kind][1]}" }
    @edges.each { |e| lines << mermaid_edge(e) }
    lines.concat(class_lines(enabled))
    lines.join("\n")
  end

  def to_h(account)
    state = live_state(account)
    {
      key: @key, name: @name, group: @group, icon: @icon, color: @color, what: @what,
      trigger: @trigger.merge(jobs: @jobs),
      config: @config,
      mermaid: to_mermaid(enabled: state[:enabled]),
      nodes: @nodes.map { |n| { id: mermaid_id(n), label: n.label, kind: n.kind } },
      live: state
    }
  end

  private

  # `ligado?` → `ligado`; só letras/números/_ para o Mermaid não engasgar
  def normalize_id(id)
    id.to_s.downcase.gsub(/[^a-z0-9_]/, '')
  end

  def mermaid_id(node)
    "#{@key}_#{node.id}"
  end

  # aspas dentro do rótulo viram entidade (o Mermaid entende #quot;)
  def escape(label)
    label.to_s.gsub('"', '#quot;')
  end

  def mermaid_edge(edge)
    from = "#{@key}_#{edge.from}"
    to = "#{@key}_#{edge.to}"
    return "  #{from} --> #{to}" if edge.label.blank?

    "  #{from} -->|\"#{escape(edge.label)}\"| #{to}"
  end

  def class_lines(enabled)
    lines = CLASS_DEFS.map { |name, style| "  classDef #{name} #{style}" }
    @nodes.group_by(&:kind).each do |kind, nodes|
      lines << "  class #{nodes.map { |n| mermaid_id(n) }.join(',')} #{css_class(kind)}"
    end
    lines << "  class #{@nodes.map { |n| mermaid_id(n) }.join(',')} cv_off" if enabled == false
    lines
  end

  def css_class(kind)
    kind == :end ? 'cv_fim' : "cv_#{kind}"
  end

  def normalize_live(result)
    result = result.to_h.symbolize_keys
    {
      enabled: result[:enabled].nil? ? nil : result[:enabled] == true,
      last_run_at: iso(result[:last_run_at]),
      counters: (result[:counters] || {}).to_h.transform_keys(&:to_s),
      note: result[:note].presence
    }
  end

  def iso(value)
    return nil if value.blank?
    return value.iso8601 if value.respond_to?(:iso8601)

    Time.zone.parse(value.to_s)&.iso8601
  rescue ArgumentError
    nil
  end

  # helpers disponíveis dentro do bloco `live` — todos leem a conta do fluxo
  class LiveContext
    TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

    def initialize(account)
      @account = account
    end

    def setting(_account = nil)
      @setting ||= CrmSetting.find_by(account: @account)
    end

    def ai(_account = nil)
      setting&.ai_config || {}
    end

    def agenda(_account = nil)
      setting&.agenda_config || {}
    end

    def agent_enabled?(_account, key)
      ai.dig('agents', key.to_s, 'enabled') == true
    end

    def usage_last(_account, key)
      Crm::AiUsage.where(account_id: @account.id, agent_key: key.to_s).maximum(:created_at)
    end

    def usage_count(_account, key, since)
      Crm::AiUsage.where(account_id: @account.id, agent_key: key.to_s).where(created_at: since..).count
    end

    def today_range
      now = TZ.now
      now.all_day
    end

    # último 'at' de uma lista de eventos ({'at' => iso}) — sem ordem garantida
    def last_at(events)
      Array(events).filter_map { |e| e.is_a?(Hash) ? e['at'] : nil }.max
    end

    def count_today(events)
      today = TZ.now.to_date
      Array(events).count { |e| e.is_a?(Hash) && e['at'].present? && Time.zone.parse(e['at'].to_s)&.in_time_zone(TZ)&.to_date == today }
    end
  end
end
