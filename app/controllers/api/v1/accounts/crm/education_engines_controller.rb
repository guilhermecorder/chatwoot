# 🎓 MOTOR DE EDUCAÇÃO (item 389) — Automações → Agentes de IA → Motor de
# educação. Ver = quem vê os agentes de IA; ligar, escolher a caixa piloto,
# editar os aprendizados e "ler ontem agora" = quem edita (catálogo de acessos).
# Aprovar/ignorar usa as rotas das orientações; voltar versão, as do histórico.
class Api::V1::Accounts::Crm::EducationEnginesController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  TZ = Crm::EducationEngine::TZ
  SHOW_DAYS = 21

  def show
    render json: payload
  end

  # PUT { enabled, pilot_inbox_ids, control_inbox_ids }
  def update
    Crm::EducationEngine.update_settings!(
      Current.account,
      enabled: params.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(params[:enabled]) : nil,
      pilot_inbox_ids: params.key?(:pilot_inbox_ids) ? Array(params[:pilot_inbox_ids]) : nil,
      control_inbox_ids: params.key?(:control_inbox_ids) ? Array(params[:control_inbox_ids]) : nil
    )
    render json: payload
  end

  # PUT { rules } — edição à mão dos aprendizados (foto antes)
  def rules
    Crm::ScriptVersion.snapshot!(Current.account, kind: 'motor', note: 'antes de editar os aprendizados na tela', by: Current.user)
    Crm::EducationEngine.write_rules!(Current.account, params[:rules].to_s)
    render json: payload
  end

  # POST { day? } — lê o dia (padrão: ontem) em segundo plano
  def run_now
    day = begin
      Date.iso8601(params[:day].to_s)
    rescue ArgumentError
      TZ.yesterday
    end
    day = TZ.yesterday if day > TZ.today
    Crm::EducationEngineJob.perform_later(Current.account.id, day.iso8601)
    render json: { queued: true, day: day.iso8601 }
  end

  private

  def payload # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    cfg = Crm::EducationEngine.settings(Current.account)
    guidances = Crm::AgentGuidance.where(account: Current.account, source: 'motor').includes(:created_by, :applied_by)
    why = cfg.dig('state', 'why') || {}
    {
      enabled: Crm::EducationEngine.enabled?(Current.account, cfg),
      pilot_inbox_ids: Crm::EducationEngine.pilot_inbox_ids(cfg),
      control_inbox_ids: Crm::EducationEngine.control_inbox_ids(cfg),
      rules: cfg['rules'].to_s,
      rules_updated_at: cfg['rules_updated_at'],
      last_run_at: cfg.dig('state', 'last_run_at'),
      has_api_key: (CrmSetting.find_by(account: Current.account)&.ai_config || {})['api_key'].present?,
      inboxes: Current.account.inboxes.where(channel_type: 'Channel::Whatsapp').order(:id).map { |i| { id: i.id, name: i.name } },
      days: recent_days(cfg),
      scoreboard: scoreboard(cfg, guidances),
      pending: guidances.where(status: 'pending').recent.limit(30).map { |g| with_why(g, why) },
      applied: guidances.where(status: 'applied').order(applied_at: :desc).limit(30).map { |g| with_why(g, why) },
      versions: Crm::ScriptVersion.where(account: Current.account, kind: 'motor').includes(:created_by).recent.limit(15).map(&:to_payload)
    }
  end

  def with_why(guidance, why)
    extra = why[guidance.id.to_s] || {}
    guidance.to_payload.merge(why: extra['why'], confidence: extra['confidence'])
  end

  def recent_days(cfg)
    (cfg.dig('state', 'days') || {}).sort_by { |date, _| date }.last(SHOW_DAYS).reverse.map { |date, row| row.merge('day' => date) }
  end

  # placar: caixa piloto × caixa de comparação, ANTES e DEPOIS do 1º
  # aprendizado aprovado, mais a série dia a dia
  def scoreboard(cfg, guidances) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    pilot = Crm::EducationEngine.pilot_inbox_ids(cfg).map(&:to_s)
    control = Crm::EducationEngine.control_inbox_ids(cfg).map(&:to_s)
    since = guidances.where(status: 'applied').minimum(:applied_at)&.in_time_zone(TZ)&.to_date&.iso8601
    totals = { 'pilot' => blank_totals, 'control' => blank_totals }
    daily = (cfg.dig('state', 'days') || {}).sort_by { |date, _| date }.map do |date, row|
      score = row['score'] || {}
      phase = since && date >= since ? 'after' : 'before'
      p = sum_inboxes(score, pilot)
      c = sum_inboxes(score, control)
      add!(totals['pilot'][phase], p)
      add!(totals['control'][phase], c)
      { day: date, phase: phase, pilot: p, control: c }
    end
    { since: since, totals: totals, daily: daily.last(30), alert: alert_for(totals) }
  end

  def blank_totals
    { 'before' => { 'n' => 0, 'booked' => 0 }, 'after' => { 'n' => 0, 'booked' => 0 } }
  end

  def sum_inboxes(score, ids)
    ids.each_with_object({ 'n' => 0, 'booked' => 0 }) do |id, acc|
      acc['n'] += score.dig(id, 'n').to_i
      acc['booked'] += score.dig(id, 'booked').to_i
    end
  end

  def add!(acc, part)
    acc['n'] += part['n']
    acc['booked'] += part['booked']
  end

  # depois dos aprendizados, com volume mínimo: a piloto agendando bem menos
  # que a comparação (5 pontos ou mais) vira aviso com a sugestão de voltar
  def alert_for(totals)
    pilot = totals['pilot']['after']
    control = totals['control']['after']
    return nil if pilot['n'] < 30 || control['n'] < 30

    gap = (rate(control) - rate(pilot)).round(1)
    return nil if gap < 5

    "Depois dos aprendizados, a caixa piloto agendou #{rate(pilot)}% × #{rate(control)}% da comparação. " \
      'Vale olhar os últimos aprovados e, se preciso, voltar para a versão anterior.'
  end

  def rate(part)
    part['n'].zero? ? 0.0 : (100.0 * part['booked'] / part['n']).round(1)
  end
end
