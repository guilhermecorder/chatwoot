# 🧹 item 278 (28/09): VARREDURA dos indicadores do "+" (custom_kpis) — "tem
# indicadores errados aqui… elimine o que está errado, corrija o necessário".
# Regras (a régua oficial do Guilherme, item 233/267):
#   taxa/conversão de agendamento = entrou na coluna Agendamento ÷ leads × 100
#   ticket médio                  = faturamento ÷ cirurgias realizadas (R$)
#   fechamento de cirurgias (taxa)= cirurgias marcadas após indicação ÷ indicações × 100
#   "Entrou em X"                 = stage_<id> da coluna X DESTA conta (pelo nome)
#   card em % que é só uma contagem → vira número
#   duplicado (mesmo painel + mesmo nome + mesma conta) → fica um
#   fórmula com variável que não existe → apagar (mostrava "—")
# DRY=1 só lista; DRY=0 aplica. Também chamado pela tela (futuro).
class Crm::KpiSweep
  OFFICIAL = {
    booking_rate: 'appointments_created / new_leads * 100',
    ticket: 'revenue / surgeries_done',
    closing_rate: 'surgeries_booked_indicated / indications * 100',
    attendance_rate: 'appointments_attended / (appointments_attended + appointments_missed) * 100'
  }.freeze

  Action = Struct.new(:kind, :id, :label, :before, :after, :why, keyword_init: true)

  def initialize(account)
    @account = account
    @setting = CrmSetting.find_by(account: account)
  end

  def plan # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    list = Array(@setting&.agenda_config&.dig('custom_kpis')).map { |k| k.to_h.stringify_keys }
    actions = []
    seen = {}
    kept = []
    list.each do |k| # rubocop:disable Metrics/BlockLength
      id = k['id'].to_s
      label = k['label'].to_s
      expr = k['expr'].to_s.strip
      panel = k['panel'].to_s
      fixed = k.dup
      why = []

      # 1) "Entrou em X" → a coluna X desta conta
      if (m = label.match(/\AEntrou em (.+)\z/i)) && (stage = stage_named(m[1]))
        if fixed['expr'] != "stage_#{stage.id}"
          fixed['expr'] = "stage_#{stage.id}"
          why << "coluna \"#{stage.name}\" é stage_#{stage.id}"
        end
        if fixed['format'] != 'number'
          fixed['format'] = 'number'
          why << 'entrada na coluna é contagem, não %'
        end
      end
      # 2) taxa / conversão de agendamento = regra oficial
      if label.match?(/taxa de agendamento|convers[ãa]o de agendamento/i) && fixed['expr'] != OFFICIAL[:booking_rate]
        fixed['expr'] = OFFICIAL[:booking_rate]
        fixed['format'] = 'percent'
        why << 'taxa de agendamento oficial = entrou na coluna ÷ leads'
      end
      # 3) ticket médio
      if label.match?(/ticket m[ée]dio/i) && fixed['expr'] != OFFICIAL[:ticket]
        fixed['expr'] = OFFICIAL[:ticket]
        fixed['format'] = 'currency'
        why << 'ticket médio = faturamento ÷ cirurgias realizadas'
      end
      # 4) fechamento (taxa) que era só contagem
      if label.match?(/fechamento/i) && plain_count?(fixed['expr'])
        fixed['expr'] = OFFICIAL[:closing_rate]
        fixed['format'] = 'percent'
        why << 'fechamento = cirurgias marcadas após indicação ÷ indicações'
      end
      # 5) comparecimento (taxa)
      if label.match?(/\Acomparecimento\z/i) && fixed['expr'] != OFFICIAL[:attendance_rate]
        fixed['expr'] = OFFICIAL[:attendance_rate]
        fixed['format'] = 'percent'
        why << 'comparecimento = presenças ÷ (presenças + faltas)'
      end
      # 6) % numa contagem simples
      if fixed['format'] == 'percent' && plain_count?(fixed['expr'])
        fixed['format'] = 'number'
        why << 'contagem simples não é %'
      end
      # 7) nome enganoso
      if label.match?(/consultas agendadas \(registradas\)/i)
        fixed['label'] = 'Consultas marcadas na Agenda (leads novos + base)'
        why << 'nome dizia "registradas"; são as marcadas na Agenda'
      end
      # 8) variável que não existe
      unknown = unknown_vars(fixed['expr'], list)
      if unknown.any?
        actions << Action.new(kind: :delete, id: id, label: label, before: expr, after: nil, why: "variável inexistente: #{unknown.join(', ')}")
        next
      end
      # 9) duplicado no mesmo painel (mesmo nome e mesma conta)
      key = [panel, fixed['label'].to_s.downcase.strip, fixed['expr'].to_s.gsub(/\s+/, '')]
      if seen[key]
        actions << Action.new(kind: :delete, id: id, label: label, before: expr, after: nil, why: "duplicado de #{seen[key]}")
        next
      end
      seen[key] = id
      if fixed != k
        renamed = fixed['label'] == label ? '' : " · nome → #{fixed['label']}"
        actions << Action.new(kind: :fix, id: id, label: label, before: "#{expr} (#{k['format']})",
                              after: "#{fixed['expr']} (#{fixed['format']})#{renamed}", why: why.join(' · '))
      end
      kept << fixed
    end
    { actions: actions, kept: kept, total: list.size }
  end

  def apply!
    result = plan
    return result if @setting.nil?

    cfg = @setting.agenda_config.dup
    cfg['custom_kpis'] = result[:kept]
    @setting.update!(agenda_config: cfg)
    result
  end

  private

  def stage_named(name)
    norm = ->(t) { I18n.transliterate(t.to_s).downcase.strip }
    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
              .order('crm_pipelines.position, crm_stages.position')
              .detect { |s| norm.call(s.name) == norm.call(name) }
  end

  def plain_count?(expr)
    expr.to_s.strip.match?(/\A[a-z_0-9]+\z/i)
  end

  def known_keys
    @known_keys ||= begin
      bag = Crm::KpiBagService.new(account: @account, since: 1.day.ago, until_at: Time.current).call
      metrics = bag[:metrics] || bag['metrics'] || {}
      metrics.keys.map(&:to_s)
    rescue StandardError
      []
    end
  end

  def unknown_vars(expr, list)
    ids = list.map { |k| k['id'].to_s }
    expr.to_s.scan(/[A-Za-z_][A-Za-z0-9_:]*/).uniq.reject do |tok|
      known_keys.include?(tok) || (tok.match?(/\Astage_\d+\z/) && stage_exists?(tok)) ||
        ids.any? { |i| tok.include?(i) }
    end
  end

  def stage_exists?(tok)
    Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).exists?(id: tok.delete_prefix('stage_').to_i)
  end
end
