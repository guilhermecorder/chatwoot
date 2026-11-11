// 📐 BASE DE COMPARAÇÃO do sistema (item 394, 11/11/2026 — pedido dele: "é bom
// a gente sempre poder ter uma base de comparação, por exemplo, comparar com a
// semana passada, o mês passado, um mês com o outro").
// UMA lista só, para toda tela que compara períodos:
//   Período anterior | Mês passado | Outro mês
// Quem usa: CompareRuler (a chavinha), o Meu Painel (Visão geral, jornada e
// painel clássico). O servidor entende as mesmas chaves em
// Crm::PeriodComparison (concern Crm::ResolvesPeriod#period_comparison).
export const COMPARE_MODES = [
  {
    key: 'previous',
    label: 'Período anterior',
    hint: 'O período do mesmo tamanho logo antes: hoje × ontem, 7 dias × 7 dias anteriores, mês fechado × mês fechado anterior.',
  },
  {
    key: 'month',
    label: 'Mês passado',
    hint: 'O mesmo trecho um mês antes: 1 a 11 deste mês × 1 a 11 do mês passado.',
  },
  {
    key: 'pick',
    label: 'Outro mês',
    hint: 'O mesmo trecho num mês que você escolhe.',
  },
];

export const COMPARE_DEFAULT = { mode: 'previous', month: '' };

const MESES = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];
const pad = n => String(n).padStart(2, '0');

// o que veio salvo (ui_settings) ou da URL → sempre um estado válido
export const normalizeCompare = value => {
  const mode = COMPARE_MODES.some(m => m.key === value?.mode)
    ? value.mode
    : 'previous';
  const month = /^\d{4}-\d{2}$/.test(value?.month || '') ? value.month : '';
  if (mode === 'pick' && !month) return { ...COMPARE_DEFAULT };
  return { mode, month: mode === 'pick' ? month : '' };
};

// parâmetros da API — SEMPRE manda `compare` (o servidor só troca a base
// quando a tela pede; aba antiga, sem o parâmetro, segue como antes)
export const compareParams = value => {
  const c = normalizeCompare(value);
  return {
    compare: c.mode,
    compare_month: c.mode === 'pick' ? c.month : undefined,
  };
};

// os últimos N meses fechados, do mais recente ao mais antigo:
// [{ value: '2026-10', label: 'outubro/26' }, …]
export const compareMonthOptions = (count = 12, now = new Date()) =>
  Array.from({ length: count }, (_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth() - (i + 1), 1);
    return {
      value: `${d.getFullYear()}-${pad(d.getMonth() + 1)}`,
      label: `${MESES[d.getMonth()]}/${String(d.getFullYear()).slice(2)}`,
    };
  });

const fmt = v =>
  Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 1 });

// VARIAÇÃO entre o número de agora e o da base de comparação.
//   pontos: true → os dois são taxas (%), a diferença sai em pontos
//   bomQuandoSobe: false → cair é bom (faltas, cancelamentos, custo)
// Devolve { estado: 'bom'|'atencao'|'neutro', seta: '▲'|'▼'|'', delta, pct, curto }
// `curto` = "+12%", "-3 pts", "igual", "novo" (antes era zero), "—" (sem base)
export const variation = (
  atual,
  anterior,
  { bomQuandoSobe = true, pontos = false } = {}
) => {
  const vazio = { estado: 'neutro', seta: '', delta: 0, pct: null };
  if (anterior === null || anterior === undefined)
    return { ...vazio, curto: '—' };
  const a = Number(atual) || 0;
  const b = Number(anterior) || 0;
  const delta = a - b;
  if (!a && !b) return { ...vazio, curto: 'igual' };
  const subiu = delta > 0;
  const estado = subiu === bomQuandoSobe ? 'bom' : 'atencao';
  const seta = subiu ? '▲' : '▼';
  if (pontos) {
    const pts = Math.round(delta * 10) / 10;
    if (!pts) return { ...vazio, curto: 'igual' };
    return {
      estado,
      seta,
      delta: pts,
      pct: null,
      curto: `${subiu ? '+' : ''}${fmt(pts)} pts`,
    };
  }
  if (!b) return { estado, seta, delta, pct: null, curto: 'novo' };
  const pct = Math.round((delta / b) * 100);
  if (!pct) return { ...vazio, delta, pct: 0, curto: 'igual' };
  return { estado, seta, delta, pct, curto: `${subiu ? '+' : ''}${pct}%` };
};

// frase da comparação no formato do CvIndicador ({ texto, estado, seta }):
//   "+12% vs ontem (34)" · "igual: setembro também teve 40" · "ontem: 0"
// rotulo = o nome da base ("ontem", "setembro", "mesmo período de outubro")
export const variationText = (
  atual,
  anterior,
  rotulo = 'período anterior',
  { bomQuandoSobe = true, pontos = false, format = fmt } = {}
) => {
  if (anterior === null || anterior === undefined) return null;
  const v = variation(atual, anterior, { bomQuandoSobe, pontos });
  const antes = format(anterior);
  if (v.curto === 'igual') {
    return Number(anterior)
      ? { texto: `igual: ${rotulo} também teve ${antes}`, estado: 'neutro' }
      : { texto: `sem movimento · ${rotulo}: ${antes}`, estado: 'neutro' };
  }
  if (v.curto === 'novo')
    return { texto: `${rotulo}: ${antes}`, estado: 'neutro' };
  // seta = o SENTIDO do número (▲ subiu, ▼ caiu); a cor vem do estado —
  // falta que caiu sai "▼" em verde
  return {
    texto: `${v.curto} vs ${rotulo} (${antes})`,
    estado: v.estado,
    seta: v.seta,
  };
};
