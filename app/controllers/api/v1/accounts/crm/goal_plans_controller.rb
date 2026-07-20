# PAINEL DE METAS: histórico dos indicadores + o plano de cada período
# (alvos, orientações, notas de ajuste por pessoa, marcos). Só ADMIN cria/
# edita o plano; o time inteiro VÊ (transparência da meta) e acompanha o
# progresso no Meu Painel. Rotinas e Ferramentas importantes moram aqui.
#
# MULTI-PERÍODO (item 58): ambientes de meta do DIA, da SEMANA, do FIM DE
# SEMANA, do MÊS (oficial dos selos/dashboards), do TRIMESTRE e do ANO —
# cada um com seu histórico. Também entram as metas de INDICADORES (%):
# agendamento, comparecimento e conversão p/ cirurgia, derivadas dos
# mesmos números (nunca digitadas à mão).
class Api::V1::Accounts::Crm::GoalPlansController < Api::V1::Accounts::BaseController
  before_action :check_admin, except: [:show]

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    start = normalize_start(parse_date(params[:month]) || TZ.now.to_date)
    render json: show_payload(start)
  end

  def upsert # rubocop:disable Metrics/AbcSize
    date = parse_date(params[:month])
    return render json: { error: 'Período inválido.' }, status: :unprocessable_entity if date.nil?

    plan = scoped_plans.find_or_initialize_by(month: normalize_start(date))
    plan.targets = params.permit(targets: {})[:targets].to_h.transform_values(&:to_f) if params.key?(:targets)
    plan.guidance = params[:guidance].to_s[0, 4000] if params.key?(:guidance)
    plan.milestones = sanitize_milestones if params.key?(:milestones)
    plan.indicator_meta = sanitize_indicator_meta if params.key?(:indicator_meta)
    plan.save!
    render json: plan_json(plan)
  end

  # nota de ajuste de processo (por pessoa do time)
  def add_note # rubocop:disable Metrics/AbcSize
    start = normalize_start(parse_date(params[:month]) || TZ.now.to_date)
    plan = scoped_plans.find_or_create_by!(month: start)
    text = params[:text].to_s.strip[0, 1000]
    return render json: { error: 'Escreva a nota.' }, status: :unprocessable_entity if text.blank?

    notes = Array(plan.process_notes)
    notes << { 'id' => SecureRandom.hex(4), 'user_id' => params[:about_user_id].presence&.to_i,
               'name' => about_name, 'text' => text,
               'author' => Current.user.available_name, 'at' => Time.current.iso8601 }
    plan.update!(process_notes: notes.last(100))
    render json: plan_json(plan)
  end

  def delete_note
    date = parse_date(params[:month])
    plan = scoped_plans.find_by!(month: date && normalize_start(date))
    plan.update!(process_notes: Array(plan.process_notes).reject { |n| n['id'] == params[:note_id] })
    render json: plan_json(plan)
  end

  # rotinas do time + ferramentas importantes (aparecem no Meu Painel)
  def update_routines # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = agenda_cfg
    cfg['team_routines'] = Array(params[:routines]).first(20).map { |r| r.to_s[0, 200] }.reject(&:blank?) if params.key?(:routines)
    if params.key?(:tools)
      cfg['important_tools'] = Array(params[:tools]).first(20).filter_map do |t|
        next if t[:label].blank?

        { 'label' => t[:label].to_s[0, 80], 'url' => t[:url].to_s[0, 500] }
      end
    end
    crm_settings.update!(agenda_config: cfg)
    render json: { routines: cfg['team_routines'] || [], tools: cfg['important_tools'] || [] }
  end

  private

  def account
    Current.account
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_or_create_by!(account: account)
  end

  def agenda_cfg
    @agenda_cfg ||= crm_settings.agenda_config || {}
  end

  def check_admin
    render json: { error: 'Só administradores editam as metas.' }, status: :forbidden unless Current.account_user.administrator?
  end

  # ── período selecionado (day/week/weekend/month/quarter/year) ──
  def period
    @period ||= CevicoGoalPlan::PERIOD_TYPES.include?(params[:period].to_s) ? params[:period].to_s : 'month'
  end

  def period_math
    @period_math ||= Crm::GoalPeriodHistoryService.new(account, period)
  end

  def scoped_plans
    account.cevico_goal_plans.where(period_type: period)
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def normalize_start(date)
    period_math.normalize_start(date)
  end

  def show_payload(start)
    {
      period: period,
      month: start.iso8601,
      indicators: CevicoGoalPlan::ALL_INDICATORS,
      rate_keys: CevicoGoalPlan::RATE_INDICATORS.keys,
      plan: plan_json(find_plan(start)),
      plans_index: scoped_plans.order(month: :desc).limit(24).pluck(:month),
      history: period_math.history(scoped_plans),
      routines: agenda_cfg['team_routines'] || [],
      tools: agenda_cfg['important_tools'] || [],
      closing_script_set: agenda_cfg['closing_script'].present?
    }
  end

  def find_plan(start)
    scoped_plans.find_by(month: start)
  end

  def about_name
    uid = params[:about_user_id].presence&.to_i
    return 'Processo geral' if uid.blank?

    account.users.find_by(id: uid)&.available_name || 'Processo geral'
  end

  def sanitize_milestones # rubocop:disable Metrics/CyclomaticComplexity
    Array(params[:milestones]).first(30).filter_map do |m|
      next if m[:title].blank?

      { 'id' => m[:id].presence || SecureRandom.hex(4), 'title' => m[:title].to_s[0, 200],
        'due_on' => m[:due_on].presence, 'done' => m[:done] == true || m[:done] == 'true',
        'done_at' => m[:done] == true || m[:done] == 'true' ? (m[:done_at].presence || Time.current.iso8601) : nil }
    end
  end

  def plan_json(plan)
    return nil if plan.nil?

    {
      id: plan.id,
      period: plan.period_type,
      month: plan.month.iso8601,
      targets: plan.targets || {},
      guidance: plan.guidance,
      process_notes: plan.process_notes || [],
      milestones: plan.milestones || [],
      indicator_meta: plan.indicator_meta || {}
    }
  end

  # responsável + "o que é preciso para alcançar" por indicador
  def sanitize_indicator_meta
    raw = params.permit(indicator_meta: {})[:indicator_meta].to_h
    sanitized = raw.slice(*CevicoGoalPlan::ALL_INDICATORS.keys.map(&:to_s)).to_h do |key, meta|
      meta = meta.is_a?(Hash) ? meta : {}
      [key, {
        'owner_id' => meta['owner_id'].presence&.to_i,
        'how' => meta['how'].to_s[0, 1000].presence
      }.compact]
    end
    sanitized.reject { |_k, v| v.empty? }
  end
end
