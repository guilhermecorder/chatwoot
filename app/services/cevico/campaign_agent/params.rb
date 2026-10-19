# ⚙️ PARÂMETROS do Agente de Campanhas (item 352). Decisões dele (18/10):
#   • a régua é o NOSSO histórico (média de 7/30/90/180/360 dias), nunca
#     número de mercado — "jogamos nosso próprio jogo";
#   • estrela-guia = custo por AGENDAMENTO de consulta; dá para trocar por
#     custo por CIRURGIA para testes (`goal`);
#   • verba ≈ R$ 15 mil por canal/mês (`budget`);
#   • autonomia por enquanto = analisa → sugere → ALGUÉM aprova → aplica →
#     aprende (`autonomy` = suggest; `execute_api` liga a mão na Meta).
# Mora em crm_settings.meta_ads_config['campaign_agent'] (sem tabela).
module Cevico::CampaignAgent::Params
  module_function

  KEY = 'campaign_agent'.freeze
  GOALS = %w[booked surgery].freeze
  AUTONOMIES = %w[suggest auto].freeze
  WINDOWS = [7, 30, 90, 180, 360].freeze

  DEFAULTS = {
    'enabled' => true,
    'goal' => 'booked',
    'budget' => { 'meta' => 15_000.0, 'google' => 15_000.0 },
    'autonomy' => 'suggest',
    'execute_api' => false,
    'window_days' => 7,        # a janela que o agente julga (os últimos N dias fechados)
    'baseline_days' => 30,     # "nossa média" contra a qual a janela é comparada
    'min' => { 'spend' => 150.0, 'impressions' => 1000, 'clicks' => 30, 'leads' => 5, 'goal_events' => 3 },
    'worse_pct' => 30,         # pior que a nossa média em 30 % = atenção
    'better_pct' => 30,        # melhor em 30 % = campeã (sobe verba)
    'budget_step_pct' => 20,   # passo de verba, para cima ou para baixo
    'daily_cap' => 0.0,        # teto por conjunto/campanha por dia (0 = sem teto)
    'learning_days' => 7,      # dias para medir o antes × depois
    'respect_days' => 7,       # não mexer no mesmo item de novo antes disso (fase de aprendizado)
    'weekend' => false,        # true = não sugerir mudança no fim de semana
    'brief_ai' => false        # resumo diário escrito pela IA (haiku), além dos números
  }.freeze

  LABELS = {
    'booked' => 'custo por agendamento de consulta',
    'surgery' => 'custo por cirurgia'
  }.freeze

  def config(account)
    (CrmSetting.find_by(account: account)&.meta_ads_config || {})[KEY] || {}
  end

  def for(account)
    merge(config(account))
  end

  def merge(raw)
    cfg = sanitize(raw)
    DEFAULTS.deep_merge(cfg)
  end

  # devolve só o que é válido — o resto cai no padrão
  def sanitize(raw) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    h = h.deep_stringify_keys
    out = {}
    out['enabled'] = h['enabled'] == true || h['enabled'].to_s == 'true' if h.key?('enabled')
    out['goal'] = h['goal'].to_s if GOALS.include?(h['goal'].to_s)
    out['autonomy'] = h['autonomy'].to_s if AUTONOMIES.include?(h['autonomy'].to_s)
    out['execute_api'] = h['execute_api'] == true || h['execute_api'].to_s == 'true' if h.key?('execute_api')
    out['weekend'] = h['weekend'] == true || h['weekend'].to_s == 'true' if h.key?('weekend')
    out['brief_ai'] = h['brief_ai'] == true || h['brief_ai'].to_s == 'true' if h.key?('brief_ai')
    budget = (h['budget'] || {}).to_h
    out['budget'] = %w[meta google].index_with { |c| number(budget[c], 0, 1_000_000) }.compact if budget.present?
    min = (h['min'] || {}).to_h
    if min.present?
      out['min'] = {
        'spend' => number(min['spend'], 0, 100_000), 'impressions' => int(min['impressions'], 0, 1_000_000),
        'clicks' => int(min['clicks'], 0, 100_000), 'leads' => int(min['leads'], 0, 10_000),
        'goal_events' => int(min['goal_events'], 0, 10_000)
      }.compact
    end
    out['window_days'] = int(h['window_days'], 3, 30)
    out['baseline_days'] = h['baseline_days'].to_i if WINDOWS.include?(h['baseline_days'].to_i)
    out['worse_pct'] = int(h['worse_pct'], 10, 200)
    out['better_pct'] = int(h['better_pct'], 10, 90)
    out['budget_step_pct'] = int(h['budget_step_pct'], 5, 100)
    out['daily_cap'] = number(h['daily_cap'], 0, 100_000)
    out['learning_days'] = int(h['learning_days'], 3, 30)
    out['respect_days'] = int(h['respect_days'], 1, 30)
    out.compact
  end

  def save!(account, raw)
    settings = CrmSetting.find_or_create_by!(account: account)
    clean = sanitize(raw)
    Cevico::SettingMerge.merge!(settings, :meta_ads_config) { |cfg| cfg.merge(KEY => (cfg[KEY] || {}).merge(clean)) }
    self.for(account)
  end

  def goal_label(params)
    LABELS[params['goal']] || LABELS['booked']
  end

  def number(value, min, max)
    return nil unless value.to_s.strip.match?(/\A-?\d+([.,]\d+)?\z/)

    v = value.to_s.tr(',', '.').to_f
    v.clamp(min, max).round(2)
  end

  def int(value, min, max)
    return nil unless value.to_s.strip.match?(/\A-?\d+\z/)

    value.to_i.clamp(min, max)
  end
end
