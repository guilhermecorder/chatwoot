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
