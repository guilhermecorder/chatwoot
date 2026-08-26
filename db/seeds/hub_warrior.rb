# Seed do WARRIOR SHREDDING no HUB (segmento saude) — importado da
# planilha Warrior_Shredding_24_Semanas_Ciclos_Separados.xlsx do Guilherme
# (25/08/2026) + especificação funcional dele.
#
# Grava em agenda_config['health'] da conta HUB:
#   - programs: Warrior 24 semanas (3 ciclos × A/B/C) + Rotina Bônus
#   - diet: metas do cutting (12 kcal/lb, 93 kg) + refeições do método
#
# PRESCRIÇÃO ≠ EXECUÇÃO: isto aqui é só a prescrição; cada treino feito
# vira um hub_health_record imutável (kind=workout).
#
# Rodar: bundle exec rails runner db/seeds/hub_warrior.rb

# faixas(6,8, 6,8, 6,8) → 3 séries com min/max
def faixas(*nums)
  nums.each_slice(2).map { |mn, mx| { 'min' => mn, 'max' => mx } }
end

# séries exatas (Independent Set Loading / barra fixa "6 / 6")
def exatas(*reps)
  reps.map { |r| { 'min' => r, 'max' => r } }
end

# rest-pause: 1 ativação + 3 mini-séries (mesma carga, pausas de ~10-20 s)
def rest_pause_sets(amin, amax, mmin, mmax)
  [{ 'min' => amin, 'max' => amax, 'kind' => 'ativacao' }] +
    Array.new(3) { { 'min' => mmin, 'max' => mmax, 'kind' => 'mini' } }
end

# pirâmide padrão: mesma carga, reps fixas decrescentes
def pyramid_sets(*reps)
  reps.map { |r| { 'min' => r, 'max' => r, 'kind' => 'piramide' } }
end

def ex(name, method, scheme, sets, rest: nil, warmup: nil, prog: nil, ptype: nil, note: nil)
  {
    'name' => name, 'method' => method, 'scheme' => scheme, 'sets' => sets,
    'rest' => rest, 'warmup' => warmup, 'progression' => prog,
    'progression_type' => ptype, 'note' => note
  }.compact
end

RP_PADRAO = '12–15 + 4–6 + 4–6 + 4–6'.freeze

# ═══ PROGRAMA PRINCIPAL — 24 SEMANAS ═══════════════════════════════
ciclo1 = {
  'id' => 'c1', 'name' => 'Treino 1', 'focus' => 'Fase 1 — Base',
  'week_start' => 1, 'week_end' => 8, 'order' => 1,
  'sessions' => [
    { 'key' => 'A', 'weekday' => 'Segunda', 'exercises' => [
      ex('Supino inclinado com barra', 'rpt', '5–6 / 6–7 / 7–8', faixas(5, 6, 6, 7, 7, 8),
         rest: '3 min', warmup: '6 leve / 4 médio / 2 mais pesado',
         prog: '−10% por série; 6/7/8 → +~2,3 kg', ptype: 'top_of_ranges'),
      ex('Supino reto com halteres', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12),
         rest: 'alguns min', warmup: 'Já aquecido',
         prog: '−~10%; 10/12 → +~2,3 kg por halter', ptype: 'top_of_ranges'),
      ex('Rosca inclinada com halteres', 'rpt', '6–8 / 6–8 / 6–8', faixas(6, 8, 6, 8, 6, 8),
         rest: 'alguns min', warmup: '1×8 leve',
         prog: 'Reduz ~2,3 kg/halter; 8/8/8 → subir', ptype: 'top_of_ranges'),
      ex('Rosca martelo na corda', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12),
         rest: '~2 min', prog: '−~10%; 10/12 → subir', ptype: 'top_of_ranges'),
      ex('Crucifixo inverso inclinado', 'rest_pause', RP_PADRAO, rest_pause_sets(12, 15, 4, 6),
         rest: '10 s', prog: '15 + 6/6/6 → subir', ptype: 'top_of_ranges'),
    ] },
    { 'key' => 'B', 'weekday' => 'Quarta', 'exercises' => [
      ex('Agachamento búlgaro', 'rpt', '6–8 / 6–8 / 6–8', faixas(6, 8, 6, 8, 6, 8),
         rest: 'alguns min', warmup: 'Peso corporal×8/perna; leve×6/perna',
         prog: 'Reduz ~4,5 kg/halter; 8/8/8 → subir', ptype: 'top_of_ranges'),
      ex('Levantamento terra romeno (RDL/Stiff)', 'rpt', '6–8 / 6–8 / 6–8', faixas(6, 8, 6, 8, 6, 8),
         rest: 'alguns min', warmup: '1–2×6–8',
         prog: '−10% por série; 8/8/8 → subir', ptype: 'top_of_ranges'),
      ex('Cadeira extensora', 'rpt', '10–12 / 10–12 / 10–12', faixas(10, 12, 10, 12, 10, 12),
         rest: 'alguns min', warmup: 'Pode entrar direto',
         prog: '−10%; 12/12/12 → subir', ptype: 'top_of_ranges'),
      ex('Elevação de joelhos suspenso com peso', 'sets', '3 × 8–15', faixas(8, 15, 8, 15, 8, 15),
         rest: 'confortável', warmup: 'Sem peso se necessário',
         prog: '3×15 → adicionar carga', ptype: 'top_of_ranges'),
    ] },
    { 'key' => 'C', 'weekday' => 'Sexta', 'exercises' => [
      ex('Desenvolvimento militar em pé com barra', 'rpt', '6–8 / 6–8 / 8–10', faixas(6, 8, 6, 8, 8, 10),
         rest: '3 min', warmup: '5 leve / 3 mais pesado',
         prog: '−10%; topo das faixas → +~2,3 kg', ptype: 'top_of_ranges'),
      ex('Barra fixa supinada com peso', 'rpt', '6 / 6', exatas(6, 6),
         rest: '3 min', warmup: 'Peso corporal×5; metade sobrecarga×3',
         prog: '2ª série −~9 kg; +~1,1 kg/treino se cumprir', ptype: 'add_each_session'),
      ex('Remada baixa sentada na polia', 'rpt', '8–12 / 8–12', faixas(8, 12, 8, 12),
         rest: 'alguns min', warmup: 'Já aquecido',
         prog: '−10%; 12/12 → subir', ptype: 'top_of_ranges'),
      ex('Tríceps na polia com corda', 'rpt', '8–10 / 10–12 / 10–12', faixas(8, 10, 10, 12, 10, 12),
         rest: '2 min', warmup: 'Já aquecido',
         prog: '−10%; 10/12/12 → subir', ptype: 'top_of_ranges'),
      ex('Elevação lateral', 'rest_pause', RP_PADRAO, rest_pause_sets(12, 15, 4, 6),
         rest: '10 s', prog: '15 + 6/6/6 → subir', ptype: 'top_of_ranges'),
    ] },
  ]
}

# fases 2/3: a planilha traz método+faixas; descanso/regra seguem o padrão
# RPT do documento (2–4 min, −10% por série, topo das faixas → subir carga)
REST_RPT = '2–4 min'.freeze
PROG_RPT = 'Topo das faixas → subir carga (−10% por série)'.freeze

ciclo2 = {
  'id' => 'c2', 'name' => 'Treino 2', 'focus' => 'Fase 2 — Peitoral',
  'week_start' => 9, 'week_end' => 16, 'order' => 2,
  'sessions' => [
    { 'key' => 'A', 'weekday' => 'Segunda', 'exercises' => [
      ex('Supino inclinado com halteres', 'rpt', '6–8 / 8–10', faixas(6, 8, 8, 10), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Supino reto com barra', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Barra fixa supinada com peso', 'rpt', '6–8 / 6–8', faixas(6, 8, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Rosca inclinada com halteres', 'rpt', '6–8 / 6–8 / 6–8', faixas(6, 8, 6, 8, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Elevação lateral', 'rest_pause', RP_PADRAO, rest_pause_sets(12, 15, 4, 6), rest: '10 s', prog: '15 + 6/6/6 → subir', ptype: 'top_of_ranges'),
    ] },
    { 'key' => 'B', 'weekday' => 'Quarta', 'exercises' => [
      ex('Levantamento terra romeno (RDL/Stiff)', 'rpt', '6–8 / 6–8 / 6–8', faixas(6, 8, 6, 8, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Agachamento búlgaro', 'rpt', '6–8 / 6–8 / 8–10', faixas(6, 8, 6, 8, 8, 10), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Elevação pélvica / Hip Thrust', 'rpt', '8–10 / 10–12 / 12–15', faixas(8, 10, 10, 12, 12, 15), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Cadeira extensora', 'rpt', '10–12 / 10–12 / 10–12', faixas(10, 12, 10, 12, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
    ] },
    { 'key' => 'C', 'weekday' => 'Sexta', 'exercises' => [
      ex('Supino inclinado com halteres', 'rpt', '6–8 / 8–10', faixas(6, 8, 8, 10), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Paralelas com peso OU supino fechado', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Remada baixa na polia', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Tríceps na polia', 'rpt', '8–10 / 10–12 / 10–12', faixas(8, 10, 10, 12, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Crucifixo inverso inclinado', 'rest_pause', RP_PADRAO, rest_pause_sets(12, 15, 4, 6), rest: '10 s', prog: '15 + 6/6/6 → subir', ptype: 'top_of_ranges'),
    ] },
  ]
}

ciclo3 = {
  'id' => 'c3', 'name' => 'Treino 3', 'focus' => 'Fase 3 — Ombros',
  'week_start' => 17, 'week_end' => 24, 'order' => 3,
  'sessions' => [
    { 'key' => 'A', 'weekday' => 'Segunda', 'exercises' => [
      ex('Supino inclinado com barra', 'rpt', '6–8 / 8–10', faixas(6, 8, 8, 10), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Desenvolvimento militar em pé com barra', 'rpt', '6–8 / 8–10', faixas(6, 8, 8, 10), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Rosca inclinada com halteres', 'rpt', '6–8 / 6–8 / 6–8', faixas(6, 8, 6, 8, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Rosca martelo', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Elevação lateral', 'rest_pause', RP_PADRAO, rest_pause_sets(12, 15, 4, 6), rest: '10 s', prog: '15 + 6/6/6 → subir', ptype: 'top_of_ranges'),
    ] },
    { 'key' => 'B', 'weekday' => 'Quarta', 'exercises' => [
      ex('Agachamento frontal', 'rpt', '4–6 / 4–6 / 4–6', faixas(4, 6, 4, 6, 4, 6), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Levantamento terra romeno (RDL/Stiff)', 'rpt', '8–10 / 8–10 / 10–12', faixas(8, 10, 8, 10, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Afundo reverso', 'rpt', '6–8 / 6–8', faixas(6, 8, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Elevação de joelhos suspenso', 'sets', '3 × 8–15', faixas(8, 15, 8, 15, 8, 15), rest: 'confortável', prog: '3×15 → adicionar carga', ptype: 'top_of_ranges'),
    ] },
    { 'key' => 'C', 'weekday' => 'Sexta', 'exercises' => [
      ex('Desenvolvimento sentado com halteres', 'rpt', '4–6 / 4–6 / 6–8', faixas(4, 6, 4, 6, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Barra fixa pronada com peso', 'rpt', '6–8 / 6–8', faixas(6, 8, 6, 8), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Remada baixa na polia', 'rpt', '8–10 / 10–12', faixas(8, 10, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Tríceps na polia', 'rpt', '8–10 / 10–12 / 10–12', faixas(8, 10, 10, 12, 10, 12), rest: REST_RPT, prog: PROG_RPT, ptype: 'top_of_ranges'),
      ex('Crucifixo inverso inclinado', 'rest_pause', RP_PADRAO, rest_pause_sets(12, 15, 4, 6), rest: '10 s', prog: '15 + 6/6/6 → subir', ptype: 'top_of_ranges'),
    ] },
  ]
}

programa_principal = {
  'id' => 'warrior24',
  'name' => 'Warrior Shredding — 24 semanas',
  'start_date' => '2026-08-24', # semana 1 começou nesta segunda (log da planilha)
  'active' => true,
  'cycles' => [ciclo1, ciclo2, ciclo3]
}

# ═══ ROTINA BÔNUS — STRENGTH & FULLNESS (bloco alternativo de 8 sem) ═══
rotina_bonus = {
  'id' => 'warrior_bonus',
  'name' => 'Rotina Bônus — Strength & Fullness',
  'active' => false,
  'note' => 'Alternar: 8 semanas da rotina original → 8 semanas desta. Não substitui o programa principal.',
  'cycles' => [{
    'id' => 'bonus', 'name' => 'Rotina Bônus', 'focus' => 'Peitoral superior + ombros, mais volume',
    'week_start' => 1, 'week_end' => 8, 'order' => 1,
    'sessions' => [
      { 'key' => 'A', 'weekday' => 'Segunda', 'exercises' => [
        ex('Supino inclinado com barra', 'rpt', '5 / 6 / 8', exatas(5, 6, 8),
           rest: '2–4 min', prog: 'Independent set loading: subir 2ª e 3ª (+2,3 kg), depois a 1ª; se difícil, 3ª → 2ª → 1ª',
           ptype: 'independent_set', note: 'Reduzir ~10% a cada série; séries leves buscam +1–2 reps.'),
        ex('Crucifixo com halteres em inclinação baixa', 'pyramid', '12 / 10 / 8 / 6', pyramid_sets(12, 10, 8, 6),
           rest: '30–60 s', prog: 'Reduzir descanso até 30 s; depois subir carga e voltar a 60 s',
           ptype: 'rest_reduction', note: 'Mesma carga nas quatro séries.'),
        ex('Tríceps na corda', 'rpt', '6–8 / 8–10 / 10–12', faixas(6, 8, 8, 10, 10, 12),
           rest: '2–4 min', prog: 'Ao dominar o topo das faixas, subir carga', ptype: 'top_of_ranges'),
        ex('Remada alta com pegada aberta', 'rest_pause', '10–20 + 6–8 + 6–8 + 6–8', rest_pause_sets(10, 20, 6, 8),
           rest: 'pausas curtas', prog: 'Progredir quando dominar o esquema', ptype: 'top_of_ranges',
           note: 'Ênfase em fadiga/volume.'),
      ] },
      { 'key' => 'B', 'weekday' => 'Quarta', 'exercises' => [
        ex('Barra fixa com peso', 'rpt', '5 / 6 / 8', exatas(5, 6, 8),
           rest: '2–4 min', prog: 'Independent set loading: 3ª → 2ª → 1ª', ptype: 'independent_set',
           note: 'Reduzir ~10% a cada série.'),
        ex('Rosca inclinada com halteres', 'rpt', '4–6 / 6–8 / 6–8', faixas(4, 6, 6, 8, 6, 8),
           rest: '2–4 min', prog: 'Topo das faixas → subir carga', ptype: 'top_of_ranges'),
        ex('Rosca martelo na corda', 'pyramid', '12 / 10 / 8 / 6', pyramid_sets(12, 10, 8, 6),
           rest: '30–60 s', prog: 'Reduzir descanso até 30 s; depois subir carga', ptype: 'rest_reduction',
           note: 'Mesma carga nas quatro séries.'),
        ex('Crucifixo inverso curvado com halteres', 'pyramid', '12 / 10 / 8 / 6', pyramid_sets(12, 10, 8, 6),
           rest: '30–60 s', prog: 'Reduzir descanso até 30 s; depois subir carga', ptype: 'rest_reduction',
           note: 'Mesma carga nas quatro séries.'),
      ] },
      { 'key' => 'C', 'weekday' => 'Sexta', 'exercises' => [
        ex('Desenvolvimento sentado com halteres', 'rpt', '4–6 / 6–8 / 8–10', faixas(4, 6, 6, 8, 8, 10),
           rest: '2–4 min', prog: 'Topo das faixas → subir carga (+2,3 kg em todas)', ptype: 'top_of_ranges'),
        ex('Elevação lateral com halteres', 'rest_pause', '12–20 + 4–8 + 4–8 + 4–8', rest_pause_sets(12, 20, 4, 8),
           rest: 'pausas curtas', prog: 'Progredir quando dominar o esquema', ptype: 'top_of_ranges',
           note: 'Ênfase em ombros.'),
        ex('Agachamento búlgaro', 'rpt', '6–8 / 8–10 / 10–12', faixas(6, 8, 8, 10, 10, 12),
           rest: '2–4 min', prog: 'Topo das faixas → subir carga', ptype: 'top_of_ranges'),
        ex('Panturrilha sentada', 'pyramid', '12 / 10 / 8 / 6', pyramid_sets(12, 10, 8, 6),
           rest: '30–60 s', prog: 'Reduzir descanso até 30 s; depois subir carga', ptype: 'rest_reduction',
           note: 'Mesma carga nas quatro séries.'),
      ] },
    ]
  }]
}

# ═══ DIETA — lógica alimentar do material (peso 93 kg) ═════════════
# Cutting: 12 kcal/lb = 2.460 kcal · proteína 0,8 g/lb = 164 g ·
# macros ~27% P / 33% G / 40% C → ~90 g gordura / ~246 g carbo.
# A divisão por refeição abaixo segue a Massive Meal Option (almoço
# menor + jantar grande + lanche noturno) e é SUGESTÃO EDITÁVEL.
dieta = {
  'targets' => { 'kcal' => 2460, 'protein' => 164, 'carbs' => 246, 'fat' => 90 },
  'notes' => 'Warrior: jejum de 4–6 h após acordar (água/café preto) · refeed 1×/semana +600 kcal em carboidratos · após 2–3 meses de cutting: Growth Phase ~4 semanas a 15 kcal/lb (3.075 kcal).',
  'meals' => [
    { 'id' => 'm1', 'name' => 'Refeição 1 — quebra do jejum', 'time' => '13:00',
      'desc' => 'Após 4–6 h acordado. Almoço menor (Massive Meal Option).',
      'kcal' => 700, 'protein' => 50, 'carbs' => 60, 'fat' => 25 },
    { 'id' => 'm2', 'name' => 'Refeição 2 — jantar grande', 'time' => '19:00',
      'desc' => '4–6 h após a 1ª; a maior refeição do dia.',
      'kcal' => 1300, 'protein' => 85, 'carbs' => 140, 'fat' => 45 },
    { 'id' => 'm3', 'name' => 'Lanche noturno', 'time' => '22:00',
      'desc' => 'Se couber nas calorias do dia.',
      'kcal' => 460, 'protein' => 29, 'carbs' => 46, 'fat' => 20 },
  ]
}

# ═══ BOXE — sequências de partida (numeração clássica) ═════════════
# 1 jab · 2 direto · 3 hook esq · 4 hook dir · 5 uppercut esq · 6 uppercut dir
# Tudo editável na aba Boxe; treinos de boxe viram registros kind=boxing
# (duração, rounds, sequências praticadas).
boxe = {
  'sequences' => [
    { 'id' => 'b1', 'name' => 'Base 1-2', 'steps' => '1 · 2', 'desc' => 'Jab · direto' },
    { 'id' => 'b2', 'name' => 'Duplo jab', 'steps' => '1 · 1 · 2', 'desc' => 'Jab · jab · direto' },
    { 'id' => 'b3', 'name' => 'Clássica', 'steps' => '1 · 2 · 3', 'desc' => 'Jab · direto · hook esquerdo' },
    { 'id' => 'b4', 'name' => 'Quatro golpes', 'steps' => '1 · 2 · 3 · 2', 'desc' => 'Jab · direto · hook esq · direto' },
    { 'id' => 'b5', 'name' => 'Esquiva e resposta', 'steps' => '1 · 2 · esquiva · 2', 'desc' => 'Jab · direto · esquiva · direto' },
    { 'id' => 'b6', 'name' => 'Uppercut no meio', 'steps' => '1 · 6 · 3 · 2', 'desc' => 'Jab · uppercut dir · hook esq · direto' },
    { 'id' => 'b7', 'name' => 'Contra-ataque', 'steps' => '2 · 3 · 2', 'desc' => 'Direto · hook esq · direto' },
    { 'id' => 'b8', 'name' => 'Corpo e cabeça', 'steps' => '1 · 2 · 5 · 2', 'desc' => 'Jab · direto · uppercut esq no corpo · direto' },
  ]
}

# ═══ gravação ══════════════════════════════════════════════════════
account = Account.find_by(name: 'HUB') || Account.find(ENV.fetch('HUB_ACCOUNT_ID', 3).to_i)
settings = CrmSetting.find_or_create_by!(account: account)
cfg = settings.agenda_config || {}
health = cfg['health'].is_a?(Hash) ? cfg['health'] : {}

health['programs'] = [programa_principal, rotina_bonus]
health['diet'] = dieta
health['boxing'] = boxe unless health['boxing'].is_a?(Hash) && health['boxing']['sequences'].present?

cfg['health'] = health
settings.update!(agenda_config: cfg)

puts "Seed Warrior aplicado na conta #{account.id} (#{account.name}):"
puts "- programas: #{health['programs'].map { |p| p['name'] }.join(' | ')}"
puts "- sessões do principal: #{programa_principal['cycles'].sum { |c| c['sessions'].size }} fichas (3 ciclos × A/B/C)"
puts "- dieta: #{dieta['targets']['kcal']} kcal · P#{dieta['targets']['protein']} C#{dieta['targets']['carbs']} G#{dieta['targets']['fat']} · #{dieta['meals'].size} refeições"
