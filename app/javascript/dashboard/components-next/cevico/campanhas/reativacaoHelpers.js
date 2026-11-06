// 🎛️ item 382: ajudantes de texto do CONTROLE DO LOTE (próxima fatia, fila, lotes)
// — tudo em português simples, sem jargão.

export const FRENTE_LABEL = {
  padrao: 'padrão',
  lentes: 'Lentes',
  catarata: 'Catarata',
};

export const frenteLabel = key => FRENTE_LABEL[key] || key || '—';

// status de entrega da Meta → palavra + tom do kit
export const STATUS_META = {
  sent: { label: 'enviada', tone: 'cv-blue' },
  delivered: { label: 'entregue', tone: 'cv-green' },
  read: { label: 'lida', tone: 'cv-green' },
  failed: { label: 'falhou', tone: 'cv-red' },
};

export const statusMeta = key =>
  STATUS_META[key] || { label: key || '—', tone: 'cv-slate' };

// +5511999990000 → (11) 99999-0000; o que não for celular brasileiro fica como veio
export const fmtPhone = raw => {
  const digits = String(raw || '').replace(/\D/g, '');
  if (!digits) return '—';
  const local = digits.startsWith('55') && digits.length >= 12 ? digits.slice(2) : digits;
  if (local.length === 11) return `(${local.slice(0, 2)}) ${local.slice(2, 7)}-${local.slice(7)}`;
  if (local.length === 10) return `(${local.slice(0, 2)}) ${local.slice(2, 6)}-${local.slice(6)}`;
  return raw;
};

export const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;

export const people = n => plural(Number(n || 0), 'pessoa', 'pessoas');

// '2026-11-06' → '06/11'
export const fmtDay = ymd => {
  const [, m, d] = String(ymd || '').split('-');
  return d && m ? `${d}/${m}` : ymd || '';
};

// 'sexta-feira' → 'sexta'
export const shortWeekday = w => String(w || '').split('-')[0];

export const fmtTime = iso => {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleTimeString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    hour: '2-digit',
    minute: '2-digit',
  });
};

export const fmtWhen = iso => {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
