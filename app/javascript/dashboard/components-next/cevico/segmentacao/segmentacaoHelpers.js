// 🧪 item 383: ajudantes da SEGMENTAÇÃO DA BASE (segmentos, mensagens A–E,
// ritmo e resultados) — tudo em português simples, sem jargão.
export { fmtPhone, fmtWhen, fmtTime, fmtDay, people, plural, frenteLabel } from '../campanhas/reativacaoHelpers';

export const NAME_VAR = '{{contact.name}}';

export const KIND = {
  teste: { label: 'Teste de mensagens', short: 'Teste', icon: 'i-lucide-flask-conical', tone: 'cv-blue' },
  escala: { label: 'Escala da vencedora', short: 'Escala', icon: 'i-lucide-rocket', tone: 'cv-green' },
};
export const kindMeta = key => KIND[key] || KIND.teste;

export const STATUS = {
  reservado: { label: 'Reservado', tone: 'cv-slate', icon: 'i-lucide-lock', hint: 'as pessoas estão separadas; nada saiu ainda' },
  enviando: { label: 'Enviando', tone: 'cv-green', icon: 'i-lucide-play', hint: 'o robô manda as levas no ritmo, dentro do horário' },
  pausado: { label: 'Pausado', tone: 'cv-amber', icon: 'i-lucide-pause', hint: 'parado; quem já recebeu fica registrado' },
  concluido: { label: 'Concluído', tone: 'cv-blue', icon: 'i-lucide-check', hint: 'todo mundo do segmento recebeu' },
};
export const statusMeta = key => STATUS[key] || STATUS.reservado;

// cada mensagem tem a sua cor (igual no cartão, na tabela e no gráfico)
export const VARIANT_COLORS = { A: '#2563EB', B: '#7C3AED', C: '#059669', D: '#D97706', E: '#DB2777' };
export const variantColor = key => VARIANT_COLORS[key] || '#64748B';

export const MEMBER_STATUS = {
  reservado: { label: 'reservada', tone: 'cv-slate' },
  enviado: { label: 'enviada', tone: 'cv-green' },
  falhou: { label: 'falhou', tone: 'cv-red' },
  pulado: { label: 'pulada', tone: 'cv-amber' },
};
export const memberStatus = key => MEMBER_STATUS[key] || { label: key || '—', tone: 'cv-slate' };

export const fmtInt = n => Number(n || 0).toLocaleString('pt-BR');
export const fmtPct = v => `${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
export const pct = (a, b) => (b > 0 ? Math.min(100, Math.round((a / b) * 100)) : 0);

// ── modelos da Meta ─────────────────────────────────────────────────────
export const templateBody = tpl => tpl?.components?.find(c => c.type === 'BODY')?.text || '';

export const tokensOf = text => {
  const out = [];
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(String(text || ''));
  while (m !== null) {
    if (!out.includes(m[1])) out.push(m[1]);
    m = re.exec(String(text || ''));
  }
  return out;
};

// monta uma mensagem (variante) a partir de um modelo aprovado — o {{1}} vira o nome
export const buildVariant = (tpl, label) => {
  const body = templateBody(tpl);
  const vars = {};
  tokensOf(body).forEach((token, i) => {
    vars[token] = i === 0 ? NAME_VAR : '';
  });
  return {
    label,
    template_params: {
      name: tpl.name,
      namespace: tpl.namespace ?? '',
      language: tpl.language,
      category: tpl.category,
      processed_params: { body: vars },
    },
    message_preview: body,
  };
};

export const variantTokens = v => tokensOf(v?.message_preview || '');
export const variantVar = (v, token) => v?.template_params?.processed_params?.body?.[token] ?? '';
export const setVariantVar = (v, token, value) => {
  if (!v?.template_params) return;
  v.template_params.processed_params = v.template_params.processed_params || {};
  v.template_params.processed_params.body = {
    ...(v.template_params.processed_params.body || {}),
    [token]: value,
  };
};
export const variantMissingVar = v =>
  Boolean(v?.template_params) && variantTokens(v).some(token => !String(variantVar(v, token)).trim());

// prévia: {{n}} vira o valor digitado; {{contact.name}} vira o chip "nome"
export const previewParts = v => {
  if (!v) return [];
  const text = String(v.message_preview || '').replace(/\{\{\s*(\d+)\s*\}\}/g, (full, token) => {
    const val = String(variantVar(v, token) || '');
    return val.trim() ? val : full;
  });
  return text
    .split(/(\{\{contact\.name\}\})/g)
    .filter(Boolean)
    .map((part, i) => ({ key: i, chip: part === NAME_VAR, text: part === NAME_VAR ? '{{nome}}' : part }));
};

// ── ritmo ───────────────────────────────────────────────────────────────
export const stepSize = pace => Math.max(1, Math.round((Number(pace?.per_hour || 0) * Number(pace?.step_minutes || 60)) / 60));

export const perDay = pace => {
  const hours = Math.max(Number(pace?.hour_to || 0) - Number(pace?.hour_from || 0), 1);
  const byWindow = Number(pace?.per_hour || 0) * hours;
  const cap = Number(pace?.daily_cap || 0);
  return cap > 0 ? Math.min(byWindow, cap) : byWindow;
};

// frase por extenso do ritmo ("150 por hora, de 60 em 60 min…")
export const paceSentence = pace => {
  if (!pace) return '';
  const bits = [
    `${fmtInt(pace.per_hour)} por hora`,
    `${fmtInt(stepSize(pace))} por leva, de ${pace.step_minutes} em ${pace.step_minutes} min`,
    `das ${pace.hour_from}h às ${pace.hour_to}h`,
    pace.weekdays_only ? 'só dias úteis' : 'todos os dias',
  ];
  if (Number(pace.daily_cap) > 0) bits.push(`teto ${fmtInt(pace.daily_cap)} por dia`);
  if (Number(pace.inbox_daily_cap) > 0) bits.push(`${fmtInt(pace.inbox_daily_cap)} por caixa/dia`);
  if (pace.route_by_origin) bits.push('pela caixa de origem');
  return bits.join(' · ');
};

// 'A' → 'Mensagem A'
export const variantLabel = (variants, key) =>
  (variants || []).find(v => v.key === key)?.label || `Mensagem ${key}`;
