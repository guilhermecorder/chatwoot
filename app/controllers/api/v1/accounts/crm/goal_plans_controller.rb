# PAINEL DE METAS: histórico mensal dos indicadores + o plano de cada mês
# (alvos, orientações, notas de ajuste por pessoa, marcos). Só ADMIN cria/
# edita o plano; o time inteiro VÊ (transparência da meta) e acompanha o
# progresso no Meu Painel. Rotinas e Ferramentas importantes moram aqui.
class Api::V1::Accounts::Crm::GoalPlansController < Api::V1::Accounts::BaseController
  before_action :check_admin, except: [:show]

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HISTORY_MONTHS = 12

  def show
    month = parse_month(params[:month]) || TZ.now.to_date.beginning_of_month
    render json: {
      month: month.iso8601,
      indicators: CevicoGoalPlan::INDICATORS,
      plan: plan_json(find_plan(month)),
      plans_index: account.cevico_goal_plans.order(month: :desc).limit(24).pluck(:month),
      history: monthly_history,
      routines: agenda_cfg['team_routines'] || [],
      tools: agenda_cfg['important_tools'] || [],
      closing_script_set: agenda_cfg['closing_script'].present?
    }
  end

  def upsert # rubocop:disable Metrics/AbcSize
    month = parse_month(params[:month])
    return render json: { error: 'Mês inválido.' }, status: :unprocessable_entity if month.nil?

    plan = account.cevico_goal_plans.find_or_initialize_by(month: month)
    plan.targets = params.permit(targets: {})[:targets].to_h.transform_values(&:to_f) if params.key?(:targets)
    plan.guidance = params[:guidance].to_s[0, 4000] if params.key?(:guidance)
    plan.milestones = sanitize_milestones if params.key?(:milestones)
    plan.save!
    render json: plan_json(plan)
  end

  # nota de ajuste de processo (por pessoa do time)
  def add_note # rubocop:disable Metrics/AbcSize
    plan = account.cevico_goal_plans.find_or_create_by!(month: parse_month(params[:month]) || TZ.now.to_date.beginning_of_month)
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
    plan = account.cevico_goal_plans.find_by!(month: parse_month(params[:month]))
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

  def parse_month(value)
    Date.parse(value.to_s).beginning_of_month
  rescue ArgumentError, TypeError
    nil
  end

  def find_plan(month)
    account.cevico_goal_plans.find_by(month: month)
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
      month: plan.month.iso8601,
      targets: plan.targets || {},
      guidance: plan.guidance,
      process_notes: plan.process_notes || [],
      milestones: plan.milestones || []
    }
  end

  # ── histórico mensal dos indicadores (últimos 12 meses) ──
  def monthly_history # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    from = (TZ.now.to_date.beginning_of_month - (HISTORY_MONTHS - 1).months).beginning_of_day

    leads = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: account.id })
                        .where('crm_contacts.created_at >= ?', from)
                        .group(Arel.sql("date_trunc('month', crm_contacts.created_at)")).count
    consultas = account.tasks.where(task_type: 'consulta').where('created_at >= ?', from)
                       .group(Arel.sql("date_trunc('month', created_at)")).count
    attended = account.tasks.where(task_type: 'consulta', attendance: 'attended').where('due_at >= ?', from)
                      .group(Arel.sql("date_trunc('month', due_at)")).count
    surg_booked = account.tasks.where(task_type: 'cirurgia').where('created_at >= ?', from)
                         .group(Arel.sql("date_trunc('month', created_at)")).count
    surg_done = account.tasks.where(task_type: 'cirurgia', attendance: 'attended').where('due_at >= ?', from)
                       .group(Arel.sql("date_trunc('month', due_at)")).count
    revenue = Crm::StageLog.joins(crm_contact: :pipeline)
                           .where(crm_pipelines: { account_id: account.id }, event_type: 'entered')
                           .where('stage_name ILIKE ?', '%cirurgia realizada%')
                           .where('entered_at >= ?', from)
                           .group(Arel.sql("date_trunc('month', entered_at)"))
                           .sum('crm_contacts.value')

    plans = account.cevico_goal_plans.where(month: from.to_date..).index_by { |p| p.month.iso8601 }

    (0...HISTORY_MONTHS).map do |i|
      month = (from.to_date + i.months).beginning_of_month
      key = ->(h) { h.find { |k, _v| k.to_date.beginning_of_month == month }&.last || 0 }
      {
        month: month.iso8601,
        values: {
          'new_leads' => key.call(leads),
          'appointments_booked' => key.call(consultas),
          'consultations_attended' => key.call(attended),
          'surgeries_booked' => key.call(surg_booked),
          'surgeries_done' => key.call(surg_done),
          'revenue_closed' => key.call(revenue).to_f.round
        },
        targets: plans[month.iso8601]&.targets || {}
      }
    end
  end
end
