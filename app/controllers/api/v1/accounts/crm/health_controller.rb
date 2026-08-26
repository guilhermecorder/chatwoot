# SAÚDE (HUB, segmento saude): o painel pessoal de treino, dieta e corpo.
# Fichas de treino, plano alimentar e metas ficam em agenda_config['health'];
# os registros do dia a dia na tabela hub_health_records. Área pessoal:
# 'health' não é concedível na Personalização, então só admin passa.
class Api::V1::Accounts::Crm::HealthController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:health) }

  WORKOUTS_LIMIT = 200
  DIETS_LIMIT = 200
  BODIES_LIMIT = 200

  def show
    render json: {
      config: health_cfg,
      workouts: records('workout', WORKOUTS_LIMIT),
      boxings: records('boxing', WORKOUTS_LIMIT),
      diets: records('diet', DIETS_LIMIT),
      bodies: records('body', BODIES_LIMIT)
    }
  end

  # POST create_record — body: { kind:, record_date:, data: {...} }.
  # Dieta e corpo têm no máximo 1 registro por dia (vira upsert);
  # treino pode repetir no mesmo dia (manhã/tarde).
  def create_record
    kind = params[:kind].to_s
    return render json: { error: 'Tipo inválido.' }, status: :unprocessable_entity unless HubHealthRecord::KINDS.include?(kind)

    date = parse_date(params[:record_date]) || Time.zone.today
    record =
      if %w[workout boxing].include?(kind)
        scope.new(kind: kind, record_date: date)
      else
        scope.of_kind(kind).find_or_initialize_by(record_date: date)
      end
    record.user_id = Current.user.id
    record.data = sanitized_data
    record.save!
    render json: record_json(record)
  end

  # record_date é opcional no update (corrigir a data de um treino já salvo)
  def update_record
    record = scope.find(params[:record_id])
    attrs = { data: sanitized_data }
    date = parse_date(params[:record_date])
    attrs[:record_date] = date if date
    record.update!(attrs)
    render json: record_json(record)
  end

  def delete_record
    scope.find(params[:record_id]).destroy!
    head :ok
  end

  # POST update_config — fichas de treino, plano alimentar e metas.
  def update_config
    cfg = crm_settings.agenda_config || {}
    cfg['health'] = sanitize_health_config(params[:config])
    crm_settings.update!(agenda_config: cfg)
    render json: { config: health_cfg }
  end

  private

  def scope
    HubHealthRecord.where(account: Current.account)
  end

  def records(kind, limit)
    scope.of_kind(kind).recent_first.limit(limit).map { |r| record_json(r) }
  end

  def record_json(record)
    { id: record.id, kind: record.kind, record_date: record.record_date.iso8601, data: record.data || {} }
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # payload JSON livre → permit! antes do to_h (lição do ambiente de páginas)
  def sanitized_data
    raw = params[:data]
    raw = raw.permit!.to_h if raw.is_a?(ActionController::Parameters)
    raw.is_a?(Hash) ? raw : {}
  end

  def sanitize_health_config(raw)
    raw = raw.permit!.to_h if raw.is_a?(ActionController::Parameters)
    return {} unless raw.is_a?(Hash)

    {
      'workout_plans' => Array(raw['workout_plans']).first(30).filter_map { |p| sanitize_plan(p) },
      'programs' => Array(raw['programs']).first(10).filter_map { |p| sanitize_program(p) },
      'boxing' => sanitize_boxing(raw['boxing']),
      'diet' => sanitize_diet(raw['diet'])
    }
  end

  # Boxe: biblioteca de sequências (combos numerados) pra praticar
  def sanitize_boxing(boxing)
    boxing = {} unless boxing.is_a?(Hash)
    {
      'sequences' => Array(boxing['sequences']).first(60).filter_map do |seq|
        next nil unless seq.is_a?(Hash)

        {
          'id' => seq['id'].presence || SecureRandom.hex(4),
          'name' => seq['name'].to_s.strip.first(60),
          'steps' => seq['steps'].to_s.strip.first(120),
          'desc' => seq['desc'].to_s.strip.first(200)
        }
      end
    }
  end

  # Programas estruturados (Warrior): prescrição hierárquica
  # PROGRAMA → CICLO → SESSÃO (A/B/C) → EXERCÍCIO → faixas de séries.
  # Área só de admin; sanitize estrutural com limites, sem mutilar conteúdo.
  def sanitize_program(prog)
    return nil unless prog.is_a?(Hash)

    {
      'id' => prog['id'].presence || SecureRandom.hex(4),
      'name' => prog['name'].to_s.strip.first(120),
      'start_date' => prog['start_date'].to_s.first(10),
      'active' => prog['active'] == true || prog['active'] == 'true',
      'note' => prog['note'].to_s.first(500),
      'cycles' => Array(prog['cycles']).first(12).filter_map { |c| sanitize_cycle(c) }
    }
  end

  def sanitize_cycle(cycle)
    return nil unless cycle.is_a?(Hash)

    {
      'id' => cycle['id'].presence || SecureRandom.hex(4),
      'name' => cycle['name'].to_s.strip.first(80),
      'focus' => cycle['focus'].to_s.first(120),
      'week_start' => cycle['week_start'].to_i,
      'week_end' => cycle['week_end'].to_i,
      'order' => cycle['order'].to_i,
      'sessions' => Array(cycle['sessions']).first(7).filter_map do |s|
        next nil unless s.is_a?(Hash)

        {
          'key' => s['key'].to_s.first(3),
          'weekday' => s['weekday'].to_s.first(20),
          'exercises' => Array(s['exercises']).first(20).filter_map { |e| sanitize_prescription(e) }
        }
      end
    }
  end

  def sanitize_prescription(ex)
    return nil unless ex.is_a?(Hash)

    {
      'name' => ex['name'].to_s.strip.first(120),
      'method' => ex['method'].to_s.first(20),
      'scheme' => ex['scheme'].to_s.first(60),
      'rest' => ex['rest'].to_s.first(40),
      'warmup' => ex['warmup'].to_s.first(120),
      'progression' => ex['progression'].to_s.first(200),
      'progression_type' => ex['progression_type'].to_s.first(30),
      'note' => ex['note'].to_s.first(200),
      'sets' => Array(ex['sets']).first(10).filter_map do |st|
        next nil unless st.is_a?(Hash)

        set = { 'min' => st['min'].to_i, 'max' => st['max'].to_i }
        set['kind'] = st['kind'].to_s.first(12) if st['kind'].present?
        set
      end
    }
  end

  def sanitize_plan(plan)
    return nil unless plan.is_a?(Hash)

    {
      'id' => plan['id'].presence || SecureRandom.hex(4),
      'name' => plan['name'].to_s.strip.first(80),
      'exercises' => Array(plan['exercises']).first(40).filter_map do |ex|
        next nil unless ex.is_a?(Hash)

        {
          'name' => ex['name'].to_s.strip.first(80),
          'sets' => ex['sets'].to_i.clamp(0, 20),
          'reps' => ex['reps'].to_s.strip.first(20),
          # aceita vírgula brasileira ("62,5")
          'load' => ex['load'].to_s.tr(',', '.').to_f
        }
      end
    }
  end

  def sanitize_diet(diet)
    diet = {} unless diet.is_a?(Hash)
    targets = diet['targets'].is_a?(Hash) ? diet['targets'] : {}
    {
      'notes' => diet['notes'].to_s.first(500),
      'targets' => {
        'kcal' => targets['kcal'].to_i.clamp(0, 20_000),
        'protein' => targets['protein'].to_i.clamp(0, 1000),
        'carbs' => targets['carbs'].to_i.clamp(0, 2000),
        'fat' => targets['fat'].to_i.clamp(0, 1000)
      },
      'meals' => Array(diet['meals']).first(12).filter_map do |meal|
        next nil unless meal.is_a?(Hash)

        {
          'id' => meal['id'].presence || SecureRandom.hex(4),
          'name' => meal['name'].to_s.strip.first(60),
          'time' => meal['time'].to_s.strip.first(5),
          'desc' => meal['desc'].to_s.strip.first(400),
          'kcal' => meal['kcal'].to_i.clamp(0, 10_000),
          'protein' => meal['protein'].to_i.clamp(0, 500),
          'carbs' => meal['carbs'].to_i.clamp(0, 1000),
          'fat' => meal['fat'].to_i.clamp(0, 500)
        }
      end
    }
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_or_create_by!(account: Current.account)
  end

  def health_cfg
    cfg = (crm_settings.agenda_config || {})['health']
    cfg.is_a?(Hash) ? cfg : {}
  end
end
