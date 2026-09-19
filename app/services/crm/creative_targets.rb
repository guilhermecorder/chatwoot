# Parâmetros de "bom / atenção / ruim" da Central de Criativos (item 172).
# Dois modos (meta_ads_config['creative_targets']['mode']):
#   manual → números fixos (padrões dos benchmarks publicados para vídeo na
#            Meta: parada ≥ 35 %, retenção ≥ 50 %, CTR ≥ 1,5 %…), editáveis;
#   auto   → o NOSSO histórico manda: bom = nossa melhor semana + passo de
#            superação (3 % por padrão), ruim = abaixo da nossa mediana
#            semanal. Cada recorde batido sobe a meta sozinho.
module Crm::CreativeTargets
  module_function

  DEFAULTS = {
    'hook_rate' => { 'bad' => 0.25, 'good' => 0.35, 'lower_is_better' => false },
    'hold_rate' => { 'bad' => 0.30, 'good' => 0.50, 'lower_is_better' => false },
    'link_ctr' => { 'bad' => 0.007, 'good' => 0.015, 'lower_is_better' => false },
    'conv_rate' => { 'bad' => 0.25, 'good' => 0.45, 'lower_is_better' => false },
    'cost_conversation' => { 'bad' => 25.0, 'good' => 10.0, 'lower_is_better' => true }
  }.freeze
  LABELS = {
    'hook_rate' => 'Taxa de parada (gancho)', 'hold_rate' => 'Retenção (corpo)', 'link_ctr' => 'CTR de link (CTA)',
    'conv_rate' => 'Conversa por clique', 'cost_conversation' => 'Custo por conversa'
  }.freeze
  BANDS = %w[ruim atencao bom].freeze
  MODES = %w[manual auto].freeze
  DEFAULT_STEP = 0.03

  def config(account)
    (CrmSetting.find_by(account: account)&.meta_ads_config || {})['creative_targets'] || {}
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def for(account)
    cfg = config(account)
    mode = MODES.include?(cfg['mode'].to_s) ? cfg['mode'].to_s : 'manual'
    step = step_from(cfg['step'])
    manual = DEFAULTS.to_h { |key, base| [key, base.merge(sanitize_one(cfg[key])).merge('source' => 'manual')] }
    return manual.merge('mode' => mode, 'step' => step) if mode == 'manual'

    records = Crm::CreativeRecords.new(account: account).call[:records]
    auto = manual.to_h do |key, base|
      rec = records[key] || {}
      best = rec[:best_week] || rec[:best_day]
      median = rec[:median_week]
      next [key, base.merge('source' => 'manual', 'fallback' => true)] if best.nil? || median.nil?

      lower = base['lower_is_better']
      good = lower ? best[:value] * (1 - step) : best[:value] * (1 + step)
      bad = lower ? [median, good * 1.25].max : [median, good * 0.8].min
      [key, base.merge('good' => good.round(4), 'bad' => bad.round(4), 'source' => 'auto',
                       'record' => best[:value], 'record_at' => best[:at], 'median' => median)]
    end
    auto.merge('mode' => mode, 'step' => step)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # bom / atencao / ruim (nil quando não há valor)
  def band(key, value, targets) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if value.nil?

    t = targets[key] || DEFAULTS[key]
    return nil unless t

    if t['lower_is_better']
      return 'bom' if value <= t['good']
      return 'ruim' if value > t['bad']
    else
      return 'bom' if value >= t['good']
      return 'ruim' if value < t['bad']
    end
    'atencao'
  end

  def step_from(raw)
    value = raw.to_f
    value.positive? ? value.clamp(0.0, 0.5) : DEFAULT_STEP
  end

  def sanitize(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    out = DEFAULTS.keys.index_with { |key| sanitize_one(h[key]) }.compact_blank
    out['mode'] = h['mode'].to_s if MODES.include?(h['mode'].to_s)
    out['step'] = step_from(h['step']) if h.key?('step')
    out
  end

  def sanitize_one(entry)
    return {} unless entry.is_a?(Hash) || entry.respond_to?(:to_h)

    e = entry.to_h
    out = {}
    %w[bad good].each do |k|
      v = e[k] || e[k.to_sym]
      out[k] = v.to_f if v.present? && v.to_f.positive?
    end
    out
  end
end
