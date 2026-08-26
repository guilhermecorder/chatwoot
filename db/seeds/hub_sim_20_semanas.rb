# SIMULAÇÃO DE 20 SEMANAS DO WARRIOR (HUB) — dados FICTÍCIOS pra ele
# visualizar dashboards cheios e a projeção do objetivo.
#
# Ponto de partida = as medidas REAIS do Guilherme (26/08/2026, protocolo
# relaxado). A simulação conta a história como se as 20 semanas tivessem
# acabado ESTA semana: começa nos números dele 20 semanas atrás e chega
# ao objetivo hoje. Método fiel ao material: cutting 12 sem → growth
# phase 4 sem (peso estável, força subindo) → cutting 4 sem.
#
#   SIM=apply  bundle exec rails runner db/seeds/hub_sim_20_semanas.rb
#     → APAGA os registros de saúde, recua o start_date do programa e
#       popula ~20 semanas (treinos, boxe, pesos/medidas, dieta).
#   SIM=clean  bundle exec rails runner db/seeds/hub_sim_20_semanas.rb
#     → remove TUDO da simulação (_sim=true), volta o start_date pra
#       segunda-feira da semana atual e recria a linha de base real.
#
# Tudo que a simulação cria carrega data['_sim'] = true.

BASELINE = {
  'weight' => 92.4, 'waist_navel' => 104.0, 'waist_narrow' => 96.0,
  'hips' => 108.0, 'chest' => 109.0, 'arm_r' => 41.5, 'arm_l' => 42.5,
  'thigh_r' => 59.5, 'thigh_l' => 58.0, 'neck' => 40.0, 'shoulders' => 129.0
}.freeze

# objetivo após 20 semanas (ritmo do método: ~0,5-0,7% do peso/semana nos
# cuts, músculo preservado pela progressão de força)
GOAL = {
  'weight' => 81.5, 'waist_navel' => 92.0, 'waist_narrow' => 87.0,
  'hips' => 101.5, 'chest' => 105.0, 'arm_r' => 40.8, 'arm_l' => 41.6,
  'thigh_r' => 57.5, 'thigh_l' => 56.2, 'neck' => 37.8, 'shoulders' => 126.5
}.freeze

account = Account.find_by(name: 'HUB')
settings = CrmSetting.find_or_create_by!(account: account)
cfg = settings.agenda_config || {}
health = cfg['health'] || {}
prog = (health['programs'] || []).find { |p| p['id'] == 'warrior24' }

if ENV['SIM'] == 'clean'
  removed = HubHealthRecord.where(account: account).where("data->>'_sim' = 'true'").delete_all
  monday = Date.today - ((Date.today.cwday - 1) % 7)
  prog['start_date'] = monday.to_s if prog
  cfg['health'] = health
  settings.update!(agenda_config: cfg)
  HubHealthRecord.create!(
    account: account, user_id: 2, kind: 'body', record_date: Date.today,
    data: BASELINE.merge('notes' => 'Linha de base real — protocolo relaxado')
  )
  puts "SIMULAÇÃO REMOVIDA (#{removed} registros). start_date=#{monday}. Linha de base real recriada (92,4 kg)."
  exit
end

# ═══ APPLY ══════════════════════════════════════════════════════════
rng = Random.new(42)
today = Date.today
start_monday = Date.parse('2026-08-24') - (20 * 7) # semana 1 há 20 semanas
raise 'programa warrior24 não encontrado — rode antes o hub_warrior.rb' unless prog

HubHealthRecord.where(account: account).delete_all
prog['start_date'] = start_monday.to_s
cfg['health'] = health
settings.update!(agenda_config: cfg)

round05 = ->(x) { (x * 2).round / 2.0 }

# progressão de carga por exercício: [início, fim das 20 semanas]
LOADS = {
  'Supino inclinado com barra' => [60, 78],
  'Supino reto com halteres' => [26, 34],
  'Supino reto com barra' => [70, 85],
  'Supino inclinado com halteres' => [26, 34],
  'Rosca inclinada com halteres' => [14, 20],
  'Rosca martelo na corda' => [30, 40],
  'Rosca martelo' => [32, 40],
  'Crucifixo inverso inclinado' => [10, 16],
  'Agachamento búlgaro' => [20, 32],
  'Levantamento terra romeno (RDL/Stiff)' => [80, 125],
  'Cadeira extensora' => [45, 65],
  'Elevação de joelhos suspenso com peso' => [2, 8],
  'Elevação de joelhos suspenso' => [2, 8],
  'Desenvolvimento militar em pé com barra' => [40, 54],
  'Barra fixa supinada com peso' => [10, 24],
  'Barra fixa pronada com peso' => [8, 16],
  'Remada baixa sentada na polia' => [55, 75],
  'Remada baixa na polia' => [60, 78],
  'Tríceps na polia com corda' => [30, 42],
  'Tríceps na polia' => [32, 42],
  'Elevação lateral' => [10, 16],
  'Elevação pélvica / Hip Thrust' => [100, 140],
  'Paralelas com peso OU supino fechado' => [10, 25],
  'Agachamento frontal' => [55, 70],
  'Afundo reverso' => [18, 26],
  'Desenvolvimento sentado com halteres' => [24, 30]
}.freeze

# peso ao longo dos dias: cut 12 sem (−6,8) → growth 4 sem (+0,2) → cut 4 sem (−4,3)
weight_at = lambda do |day|
  wk = day / 7.0
  if wk <= 12
    92.4 - (6.8 * ((wk / 12)**0.95))
  elsif wk <= 16
    85.6 + (0.2 * ((wk - 12) / 4))
  else
    [85.8 - (4.3 * ((wk - 16) / 4)), 81.5].max
  end
end

mk = lambda do |kind, date, data|
  HubHealthRecord.create!(account: account, user_id: 2, kind: kind,
                          record_date: date, data: data.merge('_sim' => true))
end

counts = Hash.new(0)

# ── TREINOS (semanas 1..21; a 21 é a semana atual, parcial) ─────────
(1..21).each do |week|
  cycle = prog['cycles'].find { |c| week >= c['week_start'] && week <= c['week_end'] }
  next unless cycle

  frac = [(week - 1) / 19.0, 1.0].min
  cycle['sessions'].each do |sess|
    offset = { 'Segunda' => 0, 'Quarta' => 2, 'Sexta' => 4 }[sess['weekday']] || 0
    date = start_monday + ((week - 1) * 7) + offset
    next if date > today
    next if week > 1 && week < 21 && rng.rand < 0.08 # sessão perdida ocasional

    bad_day = rng.rand < 0.08
    exercises = sess['exercises'].map do |ex|
      base, fim = LOADS[ex['name']] || [20, 30]
      top = base + ((fim - base) * frac) + rng.rand(-1.0..1.0)
      top -= 2.5 if bad_day
      top = round05.call([top, base * 0.9].max)
      sets = (ex['sets'] || []).each_with_index.map do |faixa, i|
        weight =
          case ex['method']
          when 'rest_pause', 'pyramid' then top
          else round05.call(top * (0.9**i))
          end
        mn = faixa['min'].to_i
        mx = [faixa['max'].to_i, mn].max
        reps =
          if ex['method'] == 'pyramid'
            mn
          elsif bad_day
            mn
          else
            (mn + ((mx - mn) * [frac * 1.3 + rng.rand(-0.3..0.3), 1.0].min.clamp(0, 1))).round
          end
        set = { 'load' => weight, 'reps' => reps.clamp(mn, mx) }
        set['kind'] = faixa['kind'] if faixa['kind']
        set
      end
      { 'name' => ex['name'], 'method' => ex['method'], 'sets' => sets }
    end
    mk.call('workout', date, {
              'program_id' => 'warrior24', 'cycle_id' => cycle['id'],
              'session_key' => sess['key'], 'week' => week,
              'plan_name' => "Treino #{sess['key']} — #{cycle['name']}",
              'exercises' => exercises
            })
    counts['treinos'] += 1
  end
end

# ── CORPO: peso 3×/semana + medidas completas a cada 4 semanas ──────
measure_days = [0, 28, 56, 84, 112, (today - start_monday).to_i]
(0..(today - start_monday).to_i).each do |day|
  date = start_monday + day
  next if date > today

  full = measure_days.include?(day)
  is_weight_day = [0, 2, 4].include?(date.cwday - 1) # seg/qua/sex
  next unless full || is_weight_day

  w = weight_at.call(day) + rng.rand(-0.35..0.35)
  data = { 'weight' => w.round(1) }
  if full
    loss_frac = [(92.4 - weight_at.call(day)) / (92.4 - 81.5), 0].max
    BASELINE.each do |k, v0|
      next if k == 'weight'

      data[k] = (v0 + ((GOAL[k] - v0) * loss_frac) + rng.rand(-0.3..0.3)).round(1)
    end
    data['notes'] = 'medição completa (protocolo relaxado)'
  end
  mk.call('body', date, data)
  counts['corpo'] += 1
end

# ── DIETA: dia a dia c/ aderência ~85%, refeed sáb, growth 13-16 ────
meals = (health.dig('diet', 'meals') || []).map { |m| m['id'] }
(0..(today - start_monday).to_i).each do |day|
  date = start_monday + day
  next if date > today
  next if rng.rand < 0.15 # dia sem registro

  wk = (day / 7) + 1
  roll = rng.rand
  done = if roll < 0.60 then meals
         elsif roll < 0.85 then meals.sample(2, random: rng)
         else meals.sample(1, random: rng)
         end
  at = {}
  base_times = { 'm1' => 13 * 60, 'm2' => 19 * 60, 'm3' => 22 * 60 }
  done.each do |id|
    min = (base_times[id] || 720) + rng.rand(-25..35)
    at[id] = format('%02d:%02d', min / 60, min % 60)
  end
  extras = []
  extras << { 'name' => 'Extra fora do plano', 'kcal' => rng.rand(150..450), 'protein' => rng.rand(5..25), 'carbs' => rng.rand(10..50), 'fat' => rng.rand(5..15) } if rng.rand < 0.18
  extras << { 'name' => 'Refeed — carboidratos', 'kcal' => 600, 'protein' => 10, 'carbs' => 150, 'fat' => 5 } if date.saturday?
  extras << { 'name' => 'Growth phase (manutenção)', 'kcal' => 600, 'protein' => 15, 'carbs' => 90, 'fat' => 15 } if wk.between?(13, 16)
  mk.call('diet', date, { 'meals_done' => done, 'meals_done_at' => at, 'extras' => extras })
  counts['dieta'] += 1
end

# ── BOXE: ter/qui, evoluindo 20→40 min ──────────────────────────────
seq_ids = (health.dig('boxing', 'sequences') || []).map { |s| s['id'] }
(0..20).each do |wk_i|
  [1, 3].each do |dow| # terça e quinta
    date = start_monday + (wk_i * 7) + dow
    next if date > today
    next if rng.rand < 0.2

    frac = wk_i / 20.0
    mk.call('boxing', date, {
              'duration_min' => (20 + (20 * frac) + rng.rand(-4..6)).round,
              'rounds' => (4 + (4 * frac)).round,
              'sequences' => seq_ids.sample(rng.rand(2..4), random: rng),
              'notes' => ''
            })
    counts['boxe'] += 1
  end
end

puts "SIMULAÇÃO APLICADA (start_date=#{start_monday}):"
counts.each { |k, v| puts "- #{k}: #{v} registros" }
puts "Peso: 92,4 → #{weight_at.call((today - start_monday).to_i).round(1)} kg · limpar depois com SIM=clean"
