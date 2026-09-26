// 🧩 item 248 (26/09): MODELOS PRONTOS do Meu Painel — indicadores da CEVICO
// já montados em grade simétrica (cards grandes 2×2 + pequenos), com as cores
// das nossas paletas e o julgamento pela média histórica ligado.
//
// Cada card é um indicador FIXO do painel ({ fixed: 'new_leads' }) ou um card
// do "+" ({ kpi: { … } }). Na fórmula, `{stage:regex}` vira a chave da coluna
// do CRM cujo nome bate (ex.: {stage:or[cç]amento} → stage_42), resolvida na
// hora de aplicar — funciona em qualquer conta. Card que não resolve é pulado.
//
// color: [paleta, degrau] → family[degrau] da paleta (cevicoPalettes.js)
import { PALETTE_BY_KEY } from 'dashboard/helper/cevicoPalettes';

const gradOf = ([key, step = 1]) => PALETTE_BY_KEY[key]?.family?.[step] || null;

export const PANEL_PRESETS = [
  {
    key: 'agendamento_funil',
    panels: ['agendamento'],
    label: 'Funil do lead',
    emoji: '🧭',
    desc: 'Do lead ao agendamento: chegada, orçamento, agendamento e as taxas — com comparecimento e faturamento.',
    tiles: [
      { fixed: 'new_leads', size: 'lg', color: ['bondi', 1] },
      { kpi: { id: 'orc', label: 'Entrou em Envio de Orçamento', expr: '{stage:or[cç]amento}', format: 'number', icon: 'i-lucide-receipt' }, color: ['blueberry', 1] },
      { kpi: { id: 'agend', label: 'Entrou em Agendamento', expr: 'appointments_created', format: 'number', icon: 'i-lucide-calendar-check' }, color: ['grape', 1] },
      { kpi: { id: 'tx_orc', label: 'Taxa de orçamento', expr: '{stage:or[cç]amento} / new_leads * 100', format: 'percent', icon: 'i-lucide-receipt', note: 'Entraram em Envio de Orçamento ÷ novos contatos do período.' }, color: ['lime', 1] },
      { fixed: 'booking_rate_30', color: ['tangerine', 1] },
      { fixed: 'appointments_booked', color: ['kiwi', 1] },
      { kpi: { id: 'comp', label: 'Comparecimento', expr: 'appointments_attended / (appointments_attended + appointments_missed) * 100', format: 'percent', icon: 'i-lucide-user-check', note: 'Presenças ÷ (presenças + faltas) nas consultas do período.' }, color: ['cereja', 1] },
      { kpi: { id: 'fat', label: 'Faturamento fechado', expr: 'revenue', format: 'currency', icon: 'i-lucide-banknote' }, size: 'lg', color: ['laranja', 1] },
      { kpi: { id: 'indic', label: 'Indicações de cirurgia', expr: 'indications', format: 'number', icon: 'i-lucide-target' }, color: ['uva', 1] },
      { kpi: { id: 'conf', label: 'Confirmadas (SIM)', expr: 'appointments_confirmed', format: 'number', icon: 'i-lucide-check-check' }, color: ['mirtilo', 1] },
    ],
  },
  {
    key: 'agendamento_enxuto',
    panels: ['agendamento'],
    label: 'Enxuto',
    emoji: '✨',
    desc: 'Só o essencial do dia: leads, agendamentos, marcadas e a taxa oficial — um card grande e três pequenos.',
    tiles: [
      { fixed: 'new_leads', size: 'lg', color: ['blueberry', 1] },
      { kpi: { id: 'agend', label: 'Entrou em Agendamento', expr: 'appointments_created', format: 'number', icon: 'i-lucide-calendar-check' }, color: ['grape', 1] },
      { fixed: 'appointments_booked', color: ['kiwi', 1] },
      { fixed: 'booking_rate_30', color: ['tangerine', 1] },
      { spacer: true },
    ],
  },
  {
    key: 'gestor_visao',
    panels: ['gestor'],
    label: 'Visão do gestor',
    emoji: '📈',
    desc: 'Chegada, conversão, comparecimento, cirurgias e dinheiro — dois cards grandes e o funil nos pequenos.',
    tiles: [
      { fixed: 'new_leads', size: 'lg', color: ['bondi', 1] },
      { kpi: { id: 'agend', label: 'Entrou em Agendamento', expr: 'appointments_created', format: 'number', icon: 'i-lucide-calendar-check' }, color: ['grape', 1] },
      { kpi: { id: 'comp', label: 'Comparecimento', expr: 'appointments_attended / (appointments_attended + appointments_missed) * 100', format: 'percent', icon: 'i-lucide-user-check' }, color: ['cereja', 1] },
      { kpi: { id: 'indic', label: 'Indicações de cirurgia', expr: 'indications', format: 'number', icon: 'i-lucide-target' }, color: ['uva', 1] },
      { kpi: { id: 'cir', label: 'Cirurgias realizadas', expr: 'surgeries_done', format: 'number', icon: 'i-lucide-heart-pulse' }, color: ['strawberry', 1] },
      { kpi: { id: 'fat', label: 'Faturamento fechado', expr: 'revenue', format: 'currency', icon: 'i-lucide-banknote' }, size: 'lg', color: ['laranja', 1] },
      { kpi: { id: 'tx_cir', label: 'Indicação → cirurgia', expr: 'surgeries_booked / indications * 100', format: 'percent', icon: 'i-lucide-handshake' }, color: ['lime', 1] },
      { kpi: { id: 'marc', label: 'Marcadas na Agenda', expr: 'appointments_booked', format: 'number', icon: 'i-lucide-calendar-check' }, color: ['kiwi', 1] },
    ],
  },
];
export const PRESET_BY_KEY = Object.fromEntries(PANEL_PRESETS.map(p => [p.key, p]));

const norm = t =>
  String(t || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

// troca {stage:regex} pela chave da coluna no cesto; null se não achar
const resolveExpr = (expr, metrics) => {
  let ok = true;
  const out = String(expr).replace(/\{stage:([^}]+)\}/g, (_, pattern) => {
    const re = new RegExp(norm(pattern), 'i');
    const key = Object.keys(metrics || {}).find(
      k => k.startsWith('stage_') && re.test(norm(metrics[k].label))
    );
    if (!key) ok = false;
    return key || '';
  });
  return ok ? out : null;
};

// monta o que salvar: defs dos cards do "+" (ids `<painel>_p_<id>`) + layout
// (ordem, tamanhos, cores, espaços) — `fixedIds` = ids dos cards fixos que
// existem neste painel
export const buildPreset = (preset, { panel, metrics, fixedIds }) => {
  const defs = [];
  const order = [];
  const sizes = {};
  const colors = {};
  const spacers = [];
  preset.tiles.forEach((t, i) => {
    let id = null;
    if (t.spacer) {
      id = `gap:p${i}${preset.key.length}`;
      spacers.push(id);
    } else if (t.fixed) {
      if (!fixedIds.includes(t.fixed)) return;
      id = t.fixed;
    } else if (t.kpi) {
      const expr = resolveExpr(t.kpi.expr, metrics);
      if (!expr) return;
      const defId = `${panel}_p_${t.kpi.id}`;
      defs.push({ ...t.kpi, id: defId, expr, panel, color: gradOf(t.color || ['bondi', 1]) || '', icon_manual: true });
      id = `kpi:${defId}`;
    }
    if (!id) return;
    order.push(id);
    if (t.size === 'lg') sizes[id] = 'lg';
    if (t.color && !t.kpi) colors[id] = gradOf(t.color);
  });
  return { defs, layout: { order, sizes, colors, spacers, preset: preset.key, judge: true } };
};
