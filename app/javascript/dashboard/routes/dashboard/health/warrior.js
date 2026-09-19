// Motor de progressão do Warrior Shredding (HUB · segmento saude).
//
// PRESCRIÇÃO ≠ EXECUÇÃO: a prescrição mora em agenda_config['health']
// ['programs'] (PROGRAMA → CICLO → SESSÃO A/B/C → EXERCÍCIO → faixas);
// cada treino feito é um hub_health_record imutável (kind=workout).
// O dado central é a comparação HOJE × ÚLTIMA SESSÃO do mesmo treino.

export const METHOD_LABELS = {
  rpt: 'RPT',
  rest_pause: 'Rest-Pause',
  pyramid: 'Pirâmide',
  sets: 'Séries',
};

export const METHOD_HINTS = {
  rpt: 'Pirâmide reversa: 1ª série é a mais pesada; reduza ~10% a cada série.',
  rest_pause: 'Ativação + 3 mini-séries com a MESMA carga e ~10–20 s de pausa.',
  pyramid: 'Mesma carga nas 4 séries (12/10/8/6); descanso de 30–60 s.',
  sets: 'Séries tradicionais.',
};

export const SET_LABELS = (method, index) => {
  if (method === 'rest_pause') return index === 0 ? 'Ativação' : `Mini ${index}`;
  return `${index + 1}ª série`;
};

const num = v => Number(String(v ?? '').replace(',', '.')) || 0;

export const activeProgram = programs =>
  (programs || []).find(p => p.active) || (programs || [])[0] || null;

// semana corrente do programa (1..N) a partir do start_date; null = sem data
export const weekOf = (program, todayISO) => {
  if (!program?.start_date) return null;
  const start = new Date(`${program.start_date}T00:00:00`);
  const today = new Date(`${todayISO}T00:00:00`);
  const diff = Math.floor((today - start) / 86400000);
  if (Number.isNaN(diff) || diff < 0) return 1;
  return Math.floor(diff / 7) + 1;
};

export const cycleForWeek = (program, week) => {
  const cycles = program?.cycles || [];
  if (!cycles.length) return null;
  if (!week) return cycles[0];
  return (
    cycles.find(c => week >= c.week_start && week <= c.week_end) ||
    cycles[cycles.length - 1]
  );
};

// próximo treino sugerido: o que vem depois do último registrado (A→B→C→A)
export const suggestedSessionKey = (workouts, program, cycle) => {
  const keys = (cycle?.sessions || []).map(s => s.key);
  if (!keys.length) return null;
  const last = (workouts || []).find(w => w.data?.program_id === program?.id);
  if (!last?.data?.session_key) return keys[0];
  const idx = keys.indexOf(last.data.session_key);
  return keys[(idx + 1) % keys.length];
};

// último registro do MESMO treino (ex.: último "Treino A" deste programa)
export const lastSessionRecord = (workouts, programId, sessionKey) =>
  (workouts || []).find(
    w => w.data?.program_id === programId && w.data?.session_key === sessionKey
  ) || null;

export const lastExerciseSets = (record, name) => {
  const ex = (record?.data?.exercises || []).find(e => e.name === name);
  return ex?.sets?.length ? ex.sets : null;
};

// séries de hoje: já vêm PREENCHIDAS com a última execução (pedido
// 26/08: "as últimas cargas como referência, pra eu já salvar") — é só
// ajustar o que mudou e concluir; cada série mantém a última execução
// em `prev` (chip ao lado) e a faixa da prescrição em `range`
export const buildTodaySets = (prescription, lastSets) => {
  const ranges = prescription.sets || [];
  const rangeOf = r => {
    if (!r) return '';
    if (r.min && r.max) return `${r.min}–${r.max}`;
    return String(r.min || r.max || '');
  };
  if (lastSets?.length) {
    return lastSets.map((s, i) => ({
      load: s.load ?? '',
      reps: s.reps ?? '',
      prev: { load: s.load, reps: s.reps },
      range: rangeOf(ranges[i]),
      kind: s.kind || ranges[i]?.kind || '',
    }));
  }
  return ranges.map(s => ({
    load: '',
    reps: '',
    prev: null,
    range: rangeOf(s),
    kind: s.kind || '',
  }));
};

// veredito do exercício: HOJE × última sessão, série a série.
// carga maior (ou mesma carga com mais reps) pontua; o inverso desconta.
export const exerciseVerdict = (todaySets, lastSets) => {
  if (!lastSets?.length) return 'first';
  const pairs = Math.min(todaySets.length, lastSets.length);
  let net = 0;
  for (let i = 0; i < pairs; i += 1) {
    const t = { load: num(todaySets[i].load), reps: num(todaySets[i].reps) };
    const l = { load: num(lastSets[i].load), reps: num(lastSets[i].reps) };
    if (t.load > l.load) net += 1;
    else if (t.load < l.load) net -= 1;
    else if (t.reps > l.reps) net += 1;
    else if (t.reps < l.reps) net -= 1;
  }
  if (todaySets.length > lastSets.length) net += 1;
  if (net > 0) return 'progress';
  if (net < 0) return 'regress';
  return 'tie';
};

// meta de hoje, calculada da última execução contra a prescrição
export const targetHint = (prescription, lastSets) => {
  const ranges = prescription.sets || [];
  if (!lastSets?.length) {
    return 'Primeira sessão — encontre as cargas de trabalho dentro das faixas.';
  }
  const method = prescription.method;
  const ptype = prescription.progression_type;

  if (ptype === 'rest_reduction' || method === 'pyramid') {
    return 'Mesma carga nas 4 séries. Reduza o descanso rumo a 30 s; fechou tudo com 30 s? Suba a carga e volte a 60 s.';
  }
  if (ptype === 'independent_set') {
    return 'Independent set loading: suba +2,3 kg primeiro na 3ª e na 2ª série; a 1ª por último (uma série por vez se pesar).';
  }
  if (ptype === 'add_each_session') {
    return prescription.progression || 'Adicione ~1,1 kg por treino se cumprir as repetições.';
  }

  // faixas (RPT / séries / rest-pause): topo de TODAS as faixas → subir carga
  const pairs = Math.min(lastSets.length, ranges.length);
  let firstBelow = -1;
  let allTop = pairs > 0;
  for (let i = 0; i < pairs; i += 1) {
    const max = ranges[i].max || 0;
    if (max && num(lastSets[i].reps) < max) {
      allTop = false;
      if (firstBelow === -1) firstBelow = i;
    }
  }
  if (allTop) {
    return '🎯 Meta atingida — topo de todas as faixas! Suba a carga (+~2,3 kg) na próxima.';
  }
  if (firstBelow >= 0) {
    const alvo = num(lastSets[firstBelow].reps) + 1;
    const carga = lastSets[firstBelow].load;
    const rotulo = SET_LABELS(method, firstBelow).toLowerCase();
    return `Supere a última: ${alvo} reps na ${rotulo} com ${String(carga).replace('.', ',')} kg.`;
  }
  return 'Supere a última sessão mantendo boa execução.';
};

// META SÉRIE A SÉRIE (pedido 30/08): sugestão de carga×reps pra CADA
// série de hoje, seguindo o fundamento do método — vira os chips
// tocáveis do cartão de vidro. Regras:
//   faixas (RPT/séries/rest-pause): topo de TODAS → +2,3 kg e reps no
//     piso da faixa; senão mesma carga buscando +1 rep até o teto
//     (minis do rest-pause acompanham a carga da ativação);
//   independent_set: cada série que bateu o teto sobe +2,3 sozinha;
//   rest_reduction/pirâmide: mesma carga, reps do esquema (foco é o
//     descanso 60→30 s);
//   add_each_session: +1,1 kg em todas;
//   sem prescrição (extra/ficha): mesma carga da última, +1 rep.
const INC = 2.3;
// alvo cai na grade de 0,5 kg — é o passo da roleta e das anilhas reais
const round1 = n => Math.round(n * 2) / 2;

export const setTargets = (prescription, lastSets) => {
  const ranges = prescription.sets || [];
  const method = prescription.method;
  const ptype = prescription.progression_type;

  // sem histórico: mostra as faixas como alvo (sem carga pra copiar)
  if (!lastSets?.length) {
    if (!ranges.length) return [];
    return ranges.map((r, i) => ({
      label: SET_LABELS(method, i),
      load: null,
      reps: r.min && r.max ? `${r.min}–${r.max}` : String(r.min || r.max || ''),
    }));
  }

  // exercício sem prescrição (extra/ficha): última execução + 1 rep
  if (!ranges.length) {
    return lastSets.map((s, i) => ({
      label: SET_LABELS(method, i),
      load: num(s.load),
      reps: num(s.reps) + 1,
    }));
  }

  const pairs = Math.min(lastSets.length, ranges.length);

  if (ptype === 'add_each_session') {
    return lastSets.map((s, i) => ({
      label: SET_LABELS(method, i),
      load: round1(num(s.load) + 1.1),
      reps: num(s.reps) || ranges[i]?.max || ranges[i]?.min || '',
    }));
  }

  if (ptype === 'rest_reduction' || method === 'pyramid') {
    const load = num(lastSets[0]?.load);
    return ranges.map((r, i) => ({
      label: SET_LABELS(method, i),
      load,
      reps: r.max || r.min || num(lastSets[i]?.reps) || '',
    }));
  }

  if (ptype === 'independent_set') {
    return ranges.map((r, i) => {
      const last = lastSets[i];
      if (!last) return { label: SET_LABELS(method, i), load: null, reps: `${r.min}–${r.max}` };
      const hitTop = r.max && num(last.reps) >= r.max;
      return {
        label: SET_LABELS(method, i),
        load: hitTop ? round1(num(last.load) + INC) : num(last.load),
        reps: hitTop ? r.min || 1 : Math.min(num(last.reps) + 1, r.max || 99),
      };
    });
  }

  // faixas (RPT / séries / rest-pause)
  let allTop = pairs > 0;
  for (let i = 0; i < pairs; i += 1) {
    if (ranges[i].max && num(lastSets[i].reps) < ranges[i].max) allTop = false;
  }
  const activationLoad = num(lastSets[0]?.load);
  return ranges.map((r, i) => {
    const last = lastSets[i];
    const isMini = method === 'rest_pause' && i > 0;
    if (!last && !isMini) {
      return { label: SET_LABELS(method, i), load: null, reps: `${r.min}–${r.max}` };
    }
    if (allTop) {
      // subiu a carga: minis do rest-pause seguem a ativação
      const base = isMini ? activationLoad : num(last?.load);
      return { label: SET_LABELS(method, i), load: round1(base + INC), reps: r.min || 1 };
    }
    const load = last ? num(last.load) : activationLoad;
    const reps = r.max
      ? Math.min((num(last?.reps) || r.min || 0) + 1, r.max)
      : (num(last?.reps) || 0) + 1;
    return { label: SET_LABELS(method, i), load, reps };
  });
};

export const sessionSummary = exercises => {
  const counts = { progress: 0, tie: 0, regress: 0, first: 0 };
  exercises.forEach(ex => {
    if (ex.skipped) return;
    counts[ex.verdict || 'first'] = (counts[ex.verdict || 'first'] || 0) + 1;
  });
  return counts;
};

export const summaryPhrase = (counts, total) => {
  if (counts.first === total) return 'Primeira sessão registrada — base criada. 🏁';
  const done = total - counts.first;
  if (counts.progress === done && done > 0) {
    return `Você progrediu em TODOS os ${done} exercícios comparáveis. 🔥`;
  }
  return `Você progrediu em ${counts.progress} de ${done} exercícios em relação ao último treino.`;
};

export const fmtSets = sets =>
  (sets || [])
    .map(s => `${String(s.load ?? '').replace('.', ',')}×${s.reps}`)
    .join(' · ');

// ═══ CHAVINHA DE EQUIPAMENTO com N opções (rodada 16) ════════════════
// Pedido 10/09: "quando for supino inclinado, quero (barra | halteres |
// máquina)". A prescrição pode trazer a lista (variants) — sem lista, as
// opções saem do NOME do exercício por estas regras. A variação BASE é a
// que está no nome (ex.: "com barra" → barra); registros antigos sem tag
// contam como a base. Cada variação guarda as próprias cargas.
const EQUIP_RULES = [
  { match: /supino|desenvolvimento|remada alta/i, options: ['barra', 'halteres', 'máquina'] },
  { match: /rosca martelo/i, options: ['halteres', 'corda'] },
  { match: /rosca/i, options: ['halteres', 'barra', 'cabo'] },
  { match: /crucifixo/i, options: ['halteres', 'máquina', 'cabo'] },
  { match: /elevação lateral|elevacao lateral/i, options: ['halteres', 'cabo', 'máquina'] },
  { match: /remada/i, options: ['polia', 'barra', 'halteres', 'máquina'] },
  { match: /tríceps|triceps/i, options: ['corda', 'barra', 'halteres'] },
  { match: /agachamento|afundo/i, options: ['halteres', 'barra', 'smith'] },
  { match: /terra|stiff|rdl/i, options: ['barra', 'halteres'] },
  { match: /hip thrust|pélvica|pelvica/i, options: ['barra', 'máquina'] },
  { match: /panturrilha/i, options: ['máquina', 'halteres', 'smith'] },
  { match: /face pull|pulldown|puxada/i, options: ['polia', 'máquina'] },
];
// equipamento citado no nome ("Tríceps na polia com corda" → corda)
const TAG_IN_NAME = [
  [/corda/i, 'corda'],
  [/com barra|na barra|barra reta|barra w/i, 'barra'],
  [/halter/i, 'halteres'],
  [/máquina|maquina|cadeira/i, 'máquina'],
  [/smith/i, 'smith'],
  [/polia|cabo/i, 'polia'],
];
const lower = s => String(s || '').trim().toLowerCase();
const uniqTags = list => {
  const seen = new Set();
  return list
    .map(s => String(s || '').trim())
    .filter(s => s && !seen.has(s.toLowerCase()) && seen.add(s.toLowerCase()));
};

// → { base, options } — options.length >= 2 = tem chavinha
export const equipmentOf = presc => {
  const name = presc?.name || '';
  const explicit = uniqTags([presc?.tag, presc?.alt_tag, ...(presc?.variants || [])]);
  if (explicit.length >= 2) return { base: explicit[0], options: explicit };
  const rule = EQUIP_RULES.find(r => r.match.test(name));
  if (!rule) return { base: explicit[0] || '', options: explicit };
  if (explicit.length === 1) {
    return { base: explicit[0], options: uniqTags([explicit[0], ...rule.options]) };
  }
  const inName = (TAG_IN_NAME.find(([re]) => re.test(name)) || [])[1];
  const base = inName && rule.options.some(o => lower(o) === inName) ? inName : rule.options[0];
  return { base, options: uniqTags([base, ...rule.options]) };
};

// nome sem o equipamento no fim (a chavinha passa a dizer o equipamento):
// "Supino inclinado com barra" → "Supino inclinado"
const EQUIP_SUFFIX = /\s+(com|na|no|em)\s+(a\s+|o\s+)?(barra|halteres?|máquina|maquina|corda|polia|cabo|smith)\s*$/i;
export const nameWithoutEquipment = name => {
  let out = String(name || '').trim();
  for (let i = 0; i < 3 && EQUIP_SUFFIX.test(out); i += 1) out = out.replace(EQUIP_SUFFIX, '').trim();
  return out || name;
};

// ═══ EXERCÍCIO EXTRA já com a TÉCNICA (rodada 16) ═══════════════════
// Pedido 10/09: ao adicionar um extra, escolher a técnica e o exercício
// nascer pré-configurado (séries/faixas/descanso) — o motor calcula
// meta e alvos por série como faz com a prescrição do programa.
const faixas = (...nums) => {
  const out = [];
  for (let i = 0; i < nums.length; i += 2) out.push({ min: nums[i], max: nums[i + 1] });
  return out;
};
export const EXTRA_METHODS = [
  {
    key: 'sets',
    label: 'Séries',
    desc: '3 × 8–12 · mesma carga · 60–90 s',
    presc: { method: 'sets', scheme: '3 × 8–12', rest: '60–90 s', progression_type: 'top_of_ranges', sets: faixas(8, 12, 8, 12, 8, 12) },
  },
  {
    key: 'rpt',
    label: 'RPT',
    desc: '6–8 / 8–10 / 10–12 · −10% por série · 2–3 min',
    presc: { method: 'rpt', scheme: '6–8 / 8–10 / 10–12', rest: '2–3 min', progression_type: 'top_of_ranges', sets: faixas(6, 8, 8, 10, 10, 12) },
  },
  {
    key: 'rest_pause',
    label: 'Rest-Pause',
    desc: 'ativação 12–15 + 3 minis 4–6 · 10–20 s',
    presc: {
      method: 'rest_pause',
      scheme: '12–15 + 4–6 + 4–6 + 4–6',
      rest: '10–20 s',
      progression_type: 'top_of_ranges',
      sets: [
        { min: 12, max: 15, kind: 'ativacao' },
        { min: 4, max: 6, kind: 'mini' },
        { min: 4, max: 6, kind: 'mini' },
        { min: 4, max: 6, kind: 'mini' },
      ],
    },
  },
  {
    key: 'pyramid',
    label: 'Pirâmide',
    desc: '12 / 10 / 8 / 6 · mesma carga · 30–60 s',
    presc: {
      method: 'pyramid',
      scheme: '12 / 10 / 8 / 6',
      rest: '30–60 s',
      progression_type: 'rest_reduction',
      sets: [12, 10, 8, 6].map(r => ({ min: r, max: r, kind: 'piramide' })),
    },
  },
];
export const extraMethod = key => EXTRA_METHODS.find(m => m.key === key) || EXTRA_METHODS[0];

// ═══ PESO COMUM entre variações (rodada 21) ═════════════════════════
// Pedido 18/09: "se eu fiz 30 kg no halter de cada lado e na máquina 70,
// encontrar um peso comum, assim como na barra". Cada variação tem um
// FATOR que leva a carga registrada pro "peso comum" (escala da barra):
//   halteres ×2 (cada lado → total) · barra/smith/polia ×1 ·
//   máquina = calibrada pelo histórico (força estimada na máquina vs nas
//   outras variações) ou fixada na prescrição (equiv: { 'máquina': 0.85 }).
export const DEFAULT_EQUIV = { halteres: 2, halter: 2, halteres_par: 2 };
const normEq = t => String(t || '').trim().toLowerCase();
export const fixedFactor = (presc, tag) => {
  const t = normEq(tag);
  const fromPresc = presc?.equiv?.[t];
  if (Number(fromPresc) > 0) return Number(fromPresc);
  return DEFAULT_EQUIV[t] ?? null;
};
// aprende o fator das variações sem fator fixo comparando a MELHOR força
// estimada (e-1RM) da execução mais recente de cada variação com a da
// variação de referência (base). execs = [{ tag, e1, date }] (mais novo
// primeiro). Devolve { tag: fator }.
export const learnEquiv = (presc, base, execs) => {
  const out = {};
  const tags = [...new Set((execs || []).map(x => normEq(x.tag) || normEq(base)))];
  const baseTag = normEq(base);
  const baseF = fixedFactor(presc, baseTag) ?? 1;
  out[baseTag] = baseF;
  const latest = tag => (execs || []).find(x => (normEq(x.tag) || baseTag) === tag);
  const refExec = latest(baseTag);
  tags.forEach(tag => {
    if (tag === baseTag) return;
    const fixed = fixedFactor(presc, tag);
    if (fixed) {
      out[tag] = fixed;
      return;
    }
    const mine = latest(tag);
    // sem referência: assume escala da barra (×1)
    if (!refExec || !mine || !mine.e1) {
      out[tag] = 1;
      return;
    }
    out[tag] = Math.round(((refExec.e1 * baseF) / mine.e1) * 1000) / 1000;
  });
  return out;
};
// fator de uma variação: o aprendido/fixado no mapa; se ela ainda não
// apareceu no histórico, o fixo da prescrição ou o padrão (halteres ×2)
export const factorOf = (equiv, tag, base, presc = null) => {
  const t = normEq(tag) || normEq(base);
  return equiv?.[t] ?? fixedFactor(presc, t) ?? 1;
};
// carga de uma variação → outra (ex.: halteres 30 → máquina ≈ 70)
export const convertLoad = (load, fromF, toF) => {
  if (!toF) return load;
  return Math.round(((load * fromF) / toF) * 2) / 2;
};

// ═══ PROGRAMAS PESSOAIS (rodada 25 — "crie seu próprio treino") ═════
// O Warrior continua sendo a prescrição compartilhada do config. Um
// programa PESSOAL é um hub_health_record kind=program (por pessoa):
// divisão A/B/C… com dia da semana, nº de semanas, OBJETIVO (parâmetro
// de sucesso/fracasso) e nome — normalizado aqui pro MESMO formato do
// programa do config, então sessão, planilha, painel e análises servem
// igual. A execução continua em registros kind=workout com program_id.
export const GOALS = [
  {
    key: 'constancia',
    icon: '🗓',
    ico: 'i-lucide-calendar-check',
    label: 'Constância',
    short: 'aparecer toda semana',
    desc: 'Sucesso = fazer os treinos planejados. Mede: treinos feitos ÷ planejados (meta 80%+).',
  },
  {
    key: 'forca',
    icon: '💪',
    ico: 'i-lucide-dumbbell',
    label: 'Força',
    short: 'cargas subindo',
    desc: 'Sucesso = ficar mais forte. Mede: força estimada total (1RM) hoje × no início do programa.',
  },
  {
    key: 'emagrecimento',
    icon: '🔥',
    ico: 'i-lucide-flame',
    label: 'Emagrecimento',
    short: 'peso e cintura caindo',
    desc: 'Sucesso = peso e cintura menores. Mede: peso e cintura (umbigo) hoje × no início.',
  },
  {
    key: 'hipertrofia',
    icon: '📐',
    ico: 'i-lucide-ruler',
    label: 'Hipertrofia',
    short: 'centímetros nos músculos',
    desc: 'Sucesso = músculos maiores. Mede: soma de peito, ombros, braços, antebraços, coxas e panturrilhas hoje × no início.',
  },
];
export const goalOf = key => GOALS.find(g => g.key === key) || GOALS[0];
export const LETTERS = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
export const WEEKDAYS = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];

// Medidas do corpo (rodada 24 incluiu antebraços e panturrilhas).
// down = cair é vitória (cintura, quadril, pescoço, peso)
export const MEASURE_DEFS = [
  { key: 'weight', label: 'Peso', unit: 'kg', down: true, icon: '⚖️', ico: 'i-lucide-scale' },
  { key: 'waist_navel', label: 'Cintura (umbigo)', unit: 'cm', down: true, icon: '📐', ico: 'i-lucide-ruler' },
  { key: 'waist_narrow', label: 'Cintura estreita', unit: 'cm', down: true, icon: '📐', ico: 'i-lucide-ruler' },
  { key: 'hips', label: 'Quadril', unit: 'cm', down: true, icon: '🍑', ico: 'i-lucide-circle' },
  { key: 'chest', label: 'Peito/tórax', unit: 'cm', down: false, icon: '🫁', ico: 'i-lucide-heart' },
  { key: 'arm_r', label: 'Braço D', unit: 'cm', down: false, icon: '💪', ico: 'i-lucide-dumbbell' },
  { key: 'arm_l', label: 'Braço E', unit: 'cm', down: false, icon: '💪', ico: 'i-lucide-dumbbell' },
  { key: 'thigh_r', label: 'Coxa D', unit: 'cm', down: false, icon: '🦵', ico: 'i-lucide-footprints' },
  { key: 'thigh_l', label: 'Coxa E', unit: 'cm', down: false, icon: '🦵', ico: 'i-lucide-footprints' },
  { key: 'forearm_r', label: 'Antebraço D', unit: 'cm', down: false, icon: '🦾', ico: 'i-lucide-hand' },
  { key: 'forearm_l', label: 'Antebraço E', unit: 'cm', down: false, icon: '🦾', ico: 'i-lucide-hand' },
  { key: 'calf_r', label: 'Panturrilha D', unit: 'cm', down: false, icon: '🦿', ico: 'i-lucide-footprints' },
  { key: 'calf_l', label: 'Panturrilha E', unit: 'cm', down: false, icon: '🦿', ico: 'i-lucide-footprints' },
  { key: 'neck', label: 'Pescoço', unit: 'cm', down: true, icon: '🧣', ico: 'i-lucide-circle-dot' },
  { key: 'shoulders', label: 'Ombros (escapular)', unit: 'cm', down: false, icon: '🏔', ico: 'i-lucide-mountain' },
];
const MUSCLE_KEYS = MEASURE_DEFS.filter(m => !m.down && m.key !== 'weight').map(m => m.key);

const e1rmOf = (load, reps) => (reps > 0 ? load * (1 + reps / 30) : load);
const fmt1 = v => String(Math.round(v * 10) / 10).replace('.', ',');
const signed1 = v => `${v > 0 ? '+' : v < 0 ? '−' : ''}${fmt1(Math.abs(v))}`;

export const customProgramId = rec => `custom_${rec.id}`;
export const programWeeks = program => {
  const cycles = program?.cycles || [];
  return cycles.length ? Math.max(...cycles.map(c => c.week_end || 0)) : 0;
};

// registro kind=program → formato de programa (1 ciclo com N semanas)
export const customToProgram = rec => {
  const d = rec?.data || {};
  const id = customProgramId(rec);
  const goal = goalOf(d.goal);
  const weeks = Number(d.weeks) || 12;
  return {
    id,
    record_id: rec.id,
    custom: true,
    name: d.name || 'Meu treino',
    start_date: d.start_date || rec.record_date,
    active: true,
    note: d.note || '',
    goal: goal.key,
    status: d.status || 'active',
    weekdays: d.weekdays || [],
    cycles: [
      {
        id: `${id}_c1`,
        name: d.name || 'Meu treino',
        focus: `${goal.icon} ${goal.label}`,
        week_start: 1,
        week_end: weeks,
        order: 1,
        sessions: (d.sessions || []).map(s => ({
          key: s.key,
          label: s.label || '',
          weekday: s.weekday || '',
          exercises: s.exercises || [],
        })),
      },
    ],
  };
};

// quais programas a pessoa vê: Warrior (config) ou o PESSOAL ativo
export const resolvePrograms = (config, profile, programRecords) => {
  const recs = programRecords || [];
  if (profile?.program_mode === 'custom') {
    const rec =
      recs.find(r => Number(r.id) === Number(profile.active_program_id) && r.data?.status !== 'archived') ||
      recs.find(r => r.data?.status === 'active');
    return rec ? [customToProgram(rec)] : [];
  }
  return config?.programs || [];
};
export const mainProgramOf = programs =>
  (programs || []).find(p => p.id === 'warrior24') ||
  (programs || []).find(p => p.custom) ||
  activeProgram(programs);

// séries da prescrição a partir de método + nº de séries + faixa
export const buildPrescriptionSets = (method, count, min, max) => {
  const n = Math.max(1, Math.min(10, Number(count) || 3));
  const lo = Math.max(1, Number(min) || 8);
  const hi = Math.max(lo, Number(max) || lo);
  if (method === 'rest_pause') {
    return [
      { min: lo, max: hi, kind: 'ativacao' },
      { min: 4, max: 6, kind: 'mini' },
      { min: 4, max: 6, kind: 'mini' },
      { min: 4, max: 6, kind: 'mini' },
    ];
  }
  if (method === 'pyramid') return [12, 10, 8, 6].map(r => ({ min: r, max: r, kind: 'piramide' }));
  return Array.from({ length: n }, () => ({ min: lo, max: hi }));
};
export const schemeText = (method, sets) => {
  if (method === 'rest_pause') return `${sets[0].min}–${sets[0].max} + 4–6 + 4–6 + 4–6`;
  if (method === 'pyramid') return '12 / 10 / 8 / 6';
  const rng = sets[0] ? (sets[0].min === sets[0].max ? `${sets[0].min}` : `${sets[0].min}–${sets[0].max}`) : '';
  return `${sets.length} × ${rng}`;
};

// IMPORTAR TREINO COLADO: uma linha por exercício — "Supino reto 3x8-12",
// "Agachamento 4 × 6–8", "Rosca direta - 3x10". Cabeçalhos "Treino A",
// "B:", "Dia 2 — Pernas" abrem um novo bloco. Sem faixa = 3 × 8–12.
export const parseImportText = text => {
  const groups = [];
  let current = { key: null, label: '', exercises: [] };
  const HEADER = /^(?:treino|dia|workout|day)?\s*([a-g]|\d)\s*[:\-–—.)]?\s*(.*)$/i;
  const LINE = /^(.+?)\s*[-–—:]?\s*(\d{1,2})\s*(?:x|×|séries?\s*(?:de)?)\s*(\d{1,3})(?:\s*(?:-|–|—|a|à)\s*(\d{1,3}))?\s*(?:reps?|repetições)?\s*$/i;
  String(text || '')
    .split(/\r?\n/)
    .map(l => l.replace(/^[\s•\-–*\d.)]+(?=[A-Za-zÀ-ú])/, '').trim())
    .filter(Boolean)
    .forEach(line => {
      const h = line.match(HEADER);
      const isHeader = h && (/^(treino|dia|workout|day)/i.test(line) || /^[a-g]\s*[:\-–—]/i.test(line));
      if (isHeader) {
        if (current.exercises.length || current.key) groups.push(current);
        const k = h[1].toUpperCase();
        current = { key: /\d/.test(k) ? LETTERS[Number(k) - 1] || null : k, label: (h[2] || '').trim(), exercises: [] };
        return;
      }
      const m = line.match(LINE);
      if (m) {
        const min = Number(m[3]);
        const max = m[4] ? Number(m[4]) : min;
        current.exercises.push({ name: m[1].trim(), count: Number(m[2]), min, max });
      } else {
        current.exercises.push({ name: line, count: 3, min: 8, max: 12 });
      }
    });
  if (current.exercises.length || current.key) groups.push(current);
  return groups;
};

// ── OBJETIVO: quanto o programa já entregou (parâmetro de sucesso) ──
const bodyAt = (bodies, iso, key) => {
  // última medição ATÉ a data; sem nenhuma, a primeira depois dela
  const asc = [...(bodies || [])]
    .filter(b => Number(b.data?.[key]) > 0)
    .sort((a, b) => (a.record_date > b.record_date ? 1 : -1));
  const before = asc.filter(b => b.record_date <= iso);
  const pick = before.at(-1) || asc[0];
  return pick ? Number(pick.data[key]) : null;
};
const latestBody = (bodies, key) => {
  const withV = (bodies || []).filter(b => Number(b.data?.[key]) > 0).sort((a, b) => (a.record_date < b.record_date ? 1 : -1));
  return withV[0] ? Number(withV[0].data[key]) : null;
};

export const goalProgress = ({ program, workouts, bodies, todayISO }) => {
  if (!program) return null;
  const goal = goalOf(program.goal);
  const weeks = programWeeks(program) || 1;
  const week = Math.min(weekOf(program, todayISO) || 1, weeks);
  const sessions = program.cycles?.[0]?.sessions || [];
  const perWeek = Math.max(1, sessions.length);
  const recs = (workouts || []).filter(
    w => w.data?.program_id === program.id && (w.data?.exercises || []).some(e => e.sets?.length)
  );
  const base = { key: goal.key, icon: goal.icon, ico: goal.ico, label: goal.label, week, weeks };
  if (goal.key === 'constancia') {
    const planned = week * perWeek;
    const done = recs.length;
    const pct = planned ? Math.min(1, done / planned) : 0;
    return {
      ...base,
      value: `${done} de ${planned}`,
      detail: `treinos feitos · ${Math.round(pct * 100)}%`,
      pct,
      ok: pct >= 0.8,
      none: !done,
    };
  }
  if (goal.key === 'forca') {
    const first = {};
    const last = {};
    [...recs]
      .sort((a, b) => (a.record_date > b.record_date ? 1 : -1))
      .forEach(w =>
        (w.data?.exercises || []).forEach(e => {
          if (!e.sets?.length) return;
          const e1 = Math.max(...e.sets.map(s => e1rmOf(Number(s.load) || 0, Number(s.reps) || 0)));
          if (!e1) return;
          if (!first[e.name]) first[e.name] = e1;
          last[e.name] = e1;
        })
      );
    const names = Object.keys(last);
    const sumF = names.reduce((a, n) => a + first[n], 0);
    const sumL = names.reduce((a, n) => a + last[n], 0);
    const pct = sumF ? (sumL - sumF) / sumF : 0;
    return {
      ...base,
      value: names.length ? `${signed1(pct * 100)}%` : '—',
      detail: names.length ? `força estimada · ${Math.round(sumL)} kg (início ${Math.round(sumF)} kg)` : 'registre os treinos pra medir',
      pct: Math.max(0, Math.min(1, pct * 5)),
      ok: pct > 0,
      none: !names.length,
    };
  }
  if (goal.key === 'emagrecimento') {
    const w0 = bodyAt(bodies, program.start_date, 'weight');
    const w1 = latestBody(bodies, 'weight');
    const c0 = bodyAt(bodies, program.start_date, 'waist_navel');
    const c1 = latestBody(bodies, 'waist_navel');
    const dw = w0 !== null && w1 !== null ? w1 - w0 : null;
    const dc = c0 !== null && c1 !== null ? c1 - c0 : null;
    const parts = [];
    if (dc !== null) parts.push(`cintura ${signed1(dc)} cm`);
    return {
      ...base,
      value: dw !== null ? `${signed1(dw)} kg` : '—',
      detail: dw !== null ? `peso desde o início${parts.length ? ` · ${parts.join(' · ')}` : ''}` : 'registre o peso na aba Corpo',
      pct: dw !== null ? Math.max(0, Math.min(1, -dw / 5)) : 0,
      ok: dw !== null && dw < 0,
      none: dw === null,
    };
  }
  // hipertrofia: soma dos músculos (só chaves presentes nas duas pontas)
  let s0 = 0;
  let s1 = 0;
  let n = 0;
  MUSCLE_KEYS.forEach(k => {
    const a = bodyAt(bodies, program.start_date, k);
    const b = latestBody(bodies, k);
    if (a === null || b === null) return;
    s0 += a;
    s1 += b;
    n += 1;
  });
  const d = n ? s1 - s0 : null;
  return {
    ...base,
    value: d !== null ? `${signed1(d)} cm` : '—',
    detail: d !== null ? `nos músculos (${n} medidas) desde o início` : 'registre as medidas na aba Corpo',
    pct: d !== null ? Math.max(0, Math.min(1, d / 6)) : 0,
    ok: d !== null && d > 0,
    none: d === null,
  };
};

// ═══ CELEBRAÇÕES (rodada 25): "anime os relatórios onde houve progresso"
// — toda semana ao fechar o último treino planejado, e a cada medição.
export const mondayOf = iso => {
  const d = new Date(`${iso}T00:00:00`);
  const dow = (d.getDay() + 6) % 7;
  d.setDate(d.getDate() - dow);
  return d.toISOString().slice(0, 10);
};
const shiftISO = (iso, days) => {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
};
const WEEK_PRAISES = [
  'Quem aparece toda semana é imbatível. 👑',
  'Consistência é o que constrói. Orgulho! 🔥',
  'Mais uma semana no bolso. O corpo agradece, o futuro também. 💪',
  'Isso não é sorte — é disciplina. ⚡',
];

// Semana fechada? Devolve os indicadores animáveis ou null.
export const workoutCelebration = ({ program, workouts, dateISO, sessionsPerWeek }) => {
  if (!program) return null;
  const monday = mondayOf(dateISO);
  const sunday = shiftISO(monday, 6);
  const inWeek = w => w.record_date >= monday && w.record_date <= sunday;
  const week = (workouts || []).filter(w => inWeek(w) && w.data?.program_id === program.id);
  const goal = Math.max(1, Number(sessionsPerWeek) || 1);
  if (week.length < goal) return null;

  // sequência de semanas completas (contando pra trás, esta inclusa)
  let streak = 0;
  let cursor = monday;
  for (let i = 0; i < 104; i += 1) {
    const end = shiftISO(cursor, 6);
    const n = (workouts || []).filter(
      w => w.record_date >= cursor && w.record_date <= end && w.data?.program_id === program.id
    ).length;
    if (n < goal) break;
    streak += 1;
    cursor = shiftISO(cursor, -7);
  }

  // veredito de cada exercício da semana × execução anterior
  const counts = { progress: 0, tie: 0, regress: 0 };
  const gains = [];
  let e1Now = 0;
  let e1Prev = 0;
  week.forEach(w => {
    const prev = (workouts || []).find(
      o =>
        o.id !== w.id &&
        o.data?.program_id === w.data?.program_id &&
        o.data?.session_key === w.data?.session_key &&
        (o.record_date < w.record_date || (o.record_date === w.record_date && o.id < w.id))
    );
    (w.data?.exercises || []).forEach(ex => {
      if (!ex.sets?.length) return;
      const last = (prev?.data?.exercises || []).find(e => e.name === ex.name);
      if (!last?.sets?.length) return;
      const v = ex.verdict || exerciseVerdict(ex.sets, last.sets);
      if (counts[v] !== undefined) counts[v] += 1;
      const topNow = Math.max(...ex.sets.map(s => Number(s.load) || 0));
      const topLast = Math.max(...last.sets.map(s => Number(s.load) || 0));
      const bestNow = Math.max(...ex.sets.map(s => e1rmOf(Number(s.load) || 0, Number(s.reps) || 0)));
      const bestLast = Math.max(...last.sets.map(s => e1rmOf(Number(s.load) || 0, Number(s.reps) || 0)));
      e1Now += bestNow;
      e1Prev += bestLast;
      if (v === 'progress') {
        const dl = topNow - topLast;
        const dr = (Number(ex.sets[0]?.reps) || 0) - (Number(last.sets[0]?.reps) || 0);
        gains.push({
          name: ex.name,
          text: dl > 0 ? `${signed1(dl)} kg` : dr > 0 ? `+${dr} reps` : '▲',
          delta: dl > 0 ? dl : 0,
        });
      }
    });
  });
  const items = [
    { icon: '🗓', ico: 'i-lucide-calendar-check', label: 'Treinos da semana', big: week.length, suffix: ` / ${goal}`, pct: 1, sub: 'todos os planejados feitos' },
  ];
  if (streak > 1) items.push({ icon: '🔥', ico: 'i-lucide-flame', label: 'Semanas seguidas completas', big: streak, pct: Math.min(1, streak / 8), sub: 'sequência viva' });
  if (counts.progress) {
    items.push({
      icon: '▲',
      ico: 'i-lucide-trending-up',
      label: 'Exercícios que subiram',
      big: counts.progress,
      pct: counts.progress / Math.max(1, counts.progress + counts.tie + counts.regress),
      sub: `${counts.tie} mantidos · ${counts.regress} caíram`,
    });
  }
  if (e1Prev > 0 && e1Now > e1Prev) {
    const pct = ((e1Now - e1Prev) / e1Prev) * 100;
    items.push({ icon: '⚡', ico: 'i-lucide-zap', label: 'Força estimada vs última vez', value: `${signed1(pct)}%`, pct: Math.min(1, pct / 10), sub: `${Math.round(e1Now)} kg somados` });
  }
  gains
    .sort((a, b) => b.delta - a.delta)
    .slice(0, 4)
    .forEach(g => items.push({ icon: '🏋️', ico: 'i-lucide-dumbbell', label: g.name, value: g.text, pct: 0.7, small: true }));
  const weekNo = weekOf(program, dateISO);
  return {
    kind: 'week',
    key: `week_${program.id}_${monday}`,
    emoji: '🏆',
    ico: 'i-lucide-trophy',
    title: weekNo ? `Semana ${weekNo} fechada!` : 'Semana fechada!',
    subtitle: WEEK_PRAISES[(weekNo || 0) % WEEK_PRAISES.length],
    items,
  };
};

// Medição registrada: o que andou na direção certa vs a anterior
export const bodyCelebration = ({ bodies, record }) => {
  if (!record) return null;
  const others = (bodies || []).filter(b => b.id !== record.id);
  const prev = others
    .filter(b => b.record_date <= record.record_date)
    .sort((a, b) => (a.record_date < b.record_date ? 1 : -1))[0];
  const first = [...others, record].sort((a, b) => (a.record_date > b.record_date ? 1 : -1))[0];
  const items = [];
  const held = [];
  let cmGood = 0;
  MEASURE_DEFS.forEach(m => {
    const now = Number(record.data?.[m.key]);
    if (!(now > 0)) return;
    const before = prev ? Number(prev.data?.[m.key]) : 0;
    if (!(before > 0)) return;
    const d = Math.round((now - before) * 10) / 10;
    const good = m.down ? d < 0 : d > 0;
    const start = Number(first?.data?.[m.key]) > 0 ? Math.round((now - Number(first.data[m.key])) * 10) / 10 : null;
    if (good) {
      if (m.unit === 'cm') cmGood += Math.abs(d);
      items.push({
        icon: m.icon,
        ico: m.ico,
        label: m.label,
        value: `${signed1(d)} ${m.unit}`,
        pct: Math.min(1, Math.abs(d) / (m.unit === 'kg' ? 1.5 : 2)),
        sub: start !== null && first?.id !== prev?.id ? `desde o início: ${signed1(start)} ${m.unit}` : 'vs medição anterior',
      });
    } else if (d === 0) {
      held.push(m.label);
    }
  });
  items.sort((a, b) => b.pct - a.pct);
  if (cmGood > 0 && items.length > 1) {
    items.unshift({ icon: '📐', ico: 'i-lucide-ruler', label: 'Centímetros na direção certa', value: `${fmt1(cmGood)} cm`, pct: Math.min(1, cmGood / 4), sub: 'somando as medidas que andaram' });
  }
  if (!prev) {
    return {
      kind: 'body',
      key: `body_${record.id}`,
      emoji: '📏',
      ico: 'i-lucide-flag',
      title: 'Ponto de partida guardado!',
      subtitle: 'Primeira medição registrada. Daqui em diante, cada centímetro conta — e aparece aqui.',
      items: MEASURE_DEFS.filter(m => Number(record.data?.[m.key]) > 0)
        .slice(0, 6)
        .map(m => ({ icon: m.icon, ico: m.ico, label: m.label, value: `${fmt1(Number(record.data[m.key]))} ${m.unit}`, pct: 0.5, small: true })),
    };
  }
  return {
    kind: 'body',
    key: `body_${record.id}`,
    emoji: items.length ? '🎉' : '📏',
    ico: items.length ? 'i-lucide-party-popper' : 'i-lucide-ruler',
    title: items.length ? `${items.filter(i => !i.small && i.label !== 'Centímetros na direção certa').length || items.length} indicadores na direção certa!` : 'Medição registrada!',
    subtitle: items.length
      ? 'Olha o que mudou desde a última medição. A transformação está acontecendo.'
      : held.length
        ? `Nada regrediu: ${held.slice(0, 3).join(', ')} se mantiveram. Constância na medição é o que revela a transformação.`
        : 'Medir sempre do mesmo jeito é o que mostra a transformação de verdade. Segue o jogo!',
    items,
  };
};

// ═══ RODADA 26: CARDIO · BOXE (etiquetas, professor, plano de luta) · ROTINA ═══

// CARDIO — pré-configurações: tipo + tempo (pedido dele 19/09)
export const CARDIO_TYPES = [
  { key: 'caminhada', icon: '🚶', ico: 'i-lucide-footprints', label: 'Caminhada' },
  { key: 'corrida', icon: '🏃', ico: 'i-lucide-activity', label: 'Corrida' },
  { key: 'bike', icon: '🚴', ico: 'i-lucide-bike', label: 'Bike' },
  { key: 'boxe', icon: '🥊', ico: 'i-lucide-swords', label: 'Boxe' },
  { key: 'eliptico', icon: '🌀', ico: 'i-lucide-orbit', label: 'Elíptico' },
  { key: 'natacao', icon: '🏊', ico: 'i-lucide-waves', label: 'Natação' },
  { key: 'corda', icon: '➰', ico: 'i-lucide-spline', label: 'Corda' },
  { key: 'escada', icon: '🪜', ico: 'i-lucide-arrow-up-down', label: 'Escada' },
  { key: 'remo', icon: '🚣', ico: 'i-lucide-anchor', label: 'Remo' },
  { key: 'futebol', icon: '⚽', ico: 'i-lucide-goal', label: 'Futebol' },
  { key: 'outro', icon: '✨', ico: 'i-lucide-sparkles', label: 'Outro' },
];
export const cardioType = key => CARDIO_TYPES.find(t => t.key === key) || CARDIO_TYPES.at(-1);
export const CARDIO_DURATIONS = [10, 15, 20, 30, 45, 60];
export const CARDIO_INTENSITIES = [
  { key: 'leve', label: 'Leve', hint: 'dá pra conversar' },
  { key: 'moderado', label: 'Moderado', hint: 'fala frases curtas' },
  { key: 'forte', label: 'Forte', hint: 'só monossílabos' },
];

// SEQUÊNCIAS DE BOXE — etiquetas "quando usar" (pedido dele 19/09)
export const SEQ_CATEGORIES = [
  { key: 'ataque', icon: '⚔️', ico: 'i-lucide-sword', label: 'Ataque', hint: 'quando você tem a iniciativa' },
  { key: 'contra', icon: '↩️', ico: 'i-lucide-undo-2', label: 'Contra-ataque', hint: 'logo depois de defender/esquivar' },
  { key: 'esquiva', icon: '🌀', ico: 'i-lucide-wind', label: 'Esquiva', hint: 'tirar a cabeça da linha' },
  { key: 'defesa', icon: '🛡', ico: 'i-lucide-shield', label: 'Defesa/bloqueio', hint: 'absorver e sair inteiro' },
  { key: 'movimentacao', icon: '👟', ico: 'i-lucide-footprints', label: 'Movimentação', hint: 'trocar de ângulo, sair da linha' },
  { key: 'aproximacao', icon: '➡️', ico: 'i-lucide-log-in', label: 'Aproximação', hint: 'fechar a distância com segurança' },
  { key: 'saida', icon: '⬅️', ico: 'i-lucide-log-out', label: 'Saída', hint: 'terminar a troca e sair' },
  { key: 'clinch', icon: '🤼', ico: 'i-lucide-link', label: 'Clinch', hint: 'curta distância, amarrar e trabalhar' },
];
export const seqCategory = key => SEQ_CATEGORIES.find(c => c.key === key) || null;

// Biblioteca pronta (entra no repertório quando ele tocar "Importar
// biblioteca"; não repete nomes que já existem)
// 1 jab · 2 direto · 3 hook esq · 4 hook dir · 5 upper esq · 6 upper dir
export const SEQ_LIBRARY = [
  // ataques
  { name: 'Jab duplo + direto', steps: '1 · 1 · 2', category: 'ataque', when: 'Abrir a guarda com o jab antes do direto', desc: 'Jab · jab · direto' },
  { name: 'Clássica', steps: '1 · 2 · 3', category: 'ataque', when: 'Adversário parado ou recuando reto', desc: 'Jab · direto · hook esquerdo' },
  { name: 'Corpo e cabeça', steps: '1 · 2 · 3b · 3', category: 'ataque', when: 'Guarda alta: baixa com o hook no corpo e sobe', desc: 'Jab · direto · hook esq no corpo · hook esq na cabeça' },
  { name: 'Direto-upper', steps: '2 · 5 · 2', category: 'ataque', when: 'Adversário encurvado ou vindo com a cabeça baixa', desc: 'Direto · upper esq · direto' },
  { name: 'Quatro golpes', steps: '1 · 2 · 3 · 2', category: 'ataque', when: 'Fechar a troca com potência', desc: 'Jab · direto · hook esq · direto' },
  // contra-ataques
  { name: 'Contra do jab', steps: 'slip D · 2', category: 'contra', when: 'Ele solta o jab: esquiva pra fora e direto', desc: 'Esquiva pra direita · direto' },
  { name: 'Contra de bloqueio', steps: 'bloqueio 3 · 3 · 2', category: 'contra', when: 'Ele vem de hook esquerdo: bloqueia e responde', desc: 'Bloqueio do hook · hook esq · direto' },
  { name: 'Pull e direto', steps: 'pull · 2 · 3', category: 'contra', when: 'Ele avança reto: recua o tronco e responde', desc: 'Recuo do tronco · direto · hook esq' },
  { name: 'Contra pelo corpo', steps: 'slip E · 2b · 3', category: 'contra', when: 'Ele solta o direto: esquiva pra dentro e ataca o corpo', desc: 'Esquiva pra esquerda · direto no corpo · hook esq' },
  // esquivas
  { name: 'Slip duplo', steps: 'slip E · slip D · 2', category: 'esquiva', when: 'Contra jab-direto: sai dos dois e responde', desc: 'Esquiva esq · esquiva dir · direto' },
  { name: 'Roll do hook', steps: 'roll · 3 · 2', category: 'esquiva', when: 'Ele solta hook: passa por baixo e responde', desc: 'Roll por baixo · hook esq · direto' },
  { name: 'Pull-counter', steps: 'pull · 2', category: 'esquiva', when: 'Ele estica o jab demais', desc: 'Recuo do tronco · direto' },
  // defesa
  { name: 'Guarda alta e saída', steps: 'guarda · passo D', category: 'defesa', when: 'Ele entra com rajada: absorve e sai pelo lado', desc: 'Guarda fechada · passo pra direita' },
  { name: 'Bloqueio do corpo', steps: 'cotovelo · 3', category: 'defesa', when: 'Ataque ao fígado/corpo', desc: 'Cotovelo cola na costela · responde de hook' },
  { name: 'Parry e direto', steps: 'parry · 2', category: 'defesa', when: 'Jab lento ou telegrafado', desc: 'Desvia o jab com a mão direita · direto' },
  // movimentação
  { name: 'Pivô de saída', steps: '1 · pivô E', category: 'movimentacao', when: 'Sair da linha depois de acertar', desc: 'Jab · pivô pra esquerda' },
  { name: 'Passo lateral e jab', steps: 'passo D · 1', category: 'movimentacao', when: 'Mudar de ângulo sem parar', desc: 'Passo pra direita · jab' },
  { name: 'Entra-sai', steps: '1 · 2 · sai', category: 'movimentacao', when: 'Marcar pontos e não ficar no alcance', desc: 'Jab · direto · dois passos pra trás' },
  // aproximação
  { name: 'Jab de entrada', steps: '1 · passo · 3', category: 'aproximacao', when: 'Fechar distância contra quem é mais alto', desc: 'Jab · passo à frente · hook esq' },
  { name: 'Finta e entrada', steps: 'finta 1 · 2 · 3', category: 'aproximacao', when: 'Adversário reage a fintas', desc: 'Finta de jab · direto · hook esq' },
  { name: 'Entrada por baixo', steps: 'slip E · 3b · 4', category: 'aproximacao', when: 'Entrar por dentro da guarda longa', desc: 'Esquiva esq · hook esq no corpo · hook dir' },
  // saída
  { name: 'Saída com upper', steps: '3 · 6 · sai', category: 'saida', when: 'Terminar a troca na curta distância', desc: 'Hook esq · upper dir · sai' },
  { name: 'Sai pelo lado', steps: '2 · passo E · 1', category: 'saida', when: 'Não sair reto pra trás', desc: 'Direto · passo pra esquerda · jab' },
  // clinch
  { name: 'Curta: upper e hook', steps: '5 · 3 · 6', category: 'clinch', when: 'Colado, sem espaço pra jab', desc: 'Upper esq · hook esq · upper dir' },
  { name: 'Sai do clinch', steps: 'gira · 2', category: 'clinch', when: 'Ele amarra: gira o corpo e solta ao sair', desc: 'Giro pra fora · direto' },
];

// PLANO DE LUTA — intenção de cada round
export const FIGHT_INTENTS = [
  { key: 'estudar', icon: '🔍', ico: 'i-lucide-search', label: 'Estudar', hint: 'ler o adversário, jab e distância' },
  { key: 'pressionar', icon: '🔥', ico: 'i-lucide-flame', label: 'Pressionar', hint: 'ritmo alto, cortar o ringue' },
  { key: 'contra_atacar', icon: '↩️', ico: 'i-lucide-undo-2', label: 'Contra-atacar', hint: 'esperar ele entrar e responder' },
  { key: 'distancia', icon: '📏', ico: 'i-lucide-ruler', label: 'Controlar distância', hint: 'jab e pés, sem trocar' },
  { key: 'corpo', icon: '🎯', ico: 'i-lucide-target', label: 'Trabalhar o corpo', hint: 'tirar o fôlego dele' },
  { key: 'definir', icon: '🏁', ico: 'i-lucide-flag', label: 'Definir', hint: 'ir pra cima e fechar' },
  { key: 'recuperar', icon: '🧘', ico: 'i-lucide-wind', label: 'Recuperar', hint: 'round econômico, respirar' },
  { key: 'ritmo', icon: '♻️', ico: 'i-lucide-repeat', label: 'Manter ritmo', hint: 'mesma pressão, sem risco' },
];
export const fightIntent = key => FIGHT_INTENTS.find(i => i.key === key) || null;
export const blankFightPlan = (rounds = 3) => ({
  name: '',
  athlete: '',
  opponent: '',
  rounds,
  round_sec: 180,
  rest_sec: 60,
  note: '',
  plan: Array.from({ length: rounds }, () => ({ intent: '', seqs: [], notes: '' })),
});
// plano → treino guiado: 1 bloco por round (descanso ANTES do próximo)
export const fightPlanToWorkout = (rec, seqNameOf) => {
  const d = rec?.data || rec || {};
  const rounds = Math.max(1, Number(d.rounds) || 1);
  return {
    id: `fp_${rec?.id || 'x'}`,
    name: `🥇 ${d.name || 'Plano de luta'}`,
    desc: [d.athlete, d.opponent].filter(Boolean).join(' × '),
    blocks: Array.from({ length: rounds }, (_, i) => {
      const r = (d.plan || [])[i] || {};
      const it = fightIntent(r.intent);
      return {
        type: 'round',
        title: `Round ${i + 1}${it ? ` · ${it.label}` : ''}`,
        minutes: 0,
        rounds: 1,
        round_sec: Number(d.round_sec) || 180,
        rest_sec: Number(d.rest_sec) || 60,
        rest_after: i < rounds - 1,
        seqs: r.seqs || [],
        desc: [it?.hint, r.notes].filter(Boolean).join(' · '),
      };
    }),
  };
};

// ROTINA — construtor de dias/semanas/meses/anos (pedido dele 19/09)
export const ROUTINE_CATS = [
  { key: 'saude', icon: '💪', ico: 'i-lucide-heart-pulse', label: 'Saúde', color: '#4169E1' },
  { key: 'negocios', icon: '💼', ico: 'i-lucide-briefcase', label: 'Negócios', color: '#27408B' },
  { key: 'familia', icon: '👨‍👩‍👧', ico: 'i-lucide-users', label: 'Família', color: '#FF8A00' },
  { key: 'mente', icon: '🧠', ico: 'i-lucide-brain', label: 'Mente/estudo', color: '#8FA9F5' },
  { key: 'espirito', icon: '🕊', ico: 'i-lucide-sun', label: 'Espírito', color: '#FFB25E' },
  { key: 'casa', icon: '🏠', ico: 'i-lucide-house', label: 'Casa/rotina', color: '#94A3B8' },
  { key: 'descanso', icon: '😴', ico: 'i-lucide-moon', label: 'Descanso', color: '#111C3F' },
];
export const routineCat = key => ROUTINE_CATS.find(c => c.key === key) || ROUTINE_CATS.at(-2);
export const LIFE_AREAS = ['saude', 'negocios', 'familia', 'mente', 'espirito'];
const rb = (start, end, title, cat, note = '') => ({ id: `${start}-${title}`.replace(/\W+/g, '_'), start, end, title, cat, note });
// rotina "campeã" de partida — editável
export const ROUTINE_PRESET_WEEKDAY = [
  rb('05:30', '06:00', 'Acordar · água · luz do sol', 'casa'),
  rb('06:00', '07:15', 'Treino', 'saude', 'programa ativo'),
  rb('07:15', '08:00', 'Café · banho', 'casa'),
  rb('08:00', '12:00', 'Trabalho — foco profundo', 'negocios', 'sem celular'),
  rb('12:00', '13:00', 'Almoço · caminhada', 'saude'),
  rb('13:00', '18:00', 'Trabalho — execução e reuniões', 'negocios'),
  rb('18:30', '19:30', 'Cardio / boxe', 'saude'),
  rb('19:30', '21:00', 'Jantar · família', 'familia'),
  rb('21:00', '21:45', 'Leitura · planejamento do dia seguinte', 'mente'),
  rb('22:00', '05:30', 'Dormir', 'descanso'),
];
export const ROUTINE_PRESET_WEEKEND = [
  rb('07:00', '07:30', 'Acordar sem pressa', 'casa'),
  rb('08:00', '09:30', 'Atividade ao ar livre', 'saude'),
  rb('10:00', '12:30', 'Família', 'familia'),
  rb('12:30', '14:00', 'Almoço', 'familia'),
  rb('15:00', '17:00', 'Projeto pessoal / estudo', 'mente'),
  rb('19:00', '21:00', 'Jantar · lazer', 'familia'),
  rb('21:30', '22:00', 'Revisão da semana', 'mente'),
  rb('22:00', '07:00', 'Dormir', 'descanso'),
];
export const timeToMin = t => {
  const [h, m] = String(t || '0:0').split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
};
// minutos por categoria num dia (bloco que atravessa a meia-noite conta até 24h)
export const dayMinutesByCat = blocks => {
  const acc = {};
  (blocks || []).forEach(b => {
    const s = timeToMin(b.start);
    let e = timeToMin(b.end);
    if (e <= s) e += 24 * 60;
    acc[b.cat] = (acc[b.cat] || 0) + (e - s);
  });
  return acc;
};
