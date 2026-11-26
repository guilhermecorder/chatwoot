// 🚪 item 420 — PORTAL DE TERCEIROS (agenda particular de um médico): as contas
// da tela, sem Vue nem store, para o spec conferir.
//
// Datas viajam como texto 'AAAA-MM-DD' e horários como 'HH:MM', SEMPRE no fuso
// de São Paulo (o da clínica), não no do computador de quem abre o portal. O
// servidor confere tudo de novo antes de gravar — aqui é só para desenhar.
export const SP_TZ = 'America/Sao_Paulo';
export const SP_OFFSET = '-03:00'; // São Paulo não tem horário de verão desde 2019

export const pad = n => String(n).padStart(2, '0');
export const toMin = hhmm => {
  const [h, m] = String(hhmm || '').split(':');
  return Number(h || 0) * 60 + Number(m || 0);
};
export const fromMin = min => `${pad(Math.floor(min / 60))}:${pad(min % 60)}`;

const partsFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: SP_TZ,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
});
// instante (ISO ou Date) → { date: 'AAAA-MM-DD', time: 'HH:MM' } em São Paulo
export const spParts = value => {
  const when = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(when.getTime())) return { date: '', time: '' };
  const p = Object.fromEntries(
    partsFmt.formatToParts(when).map(x => [x.type, x.value])
  );
  return {
    date: `${p.year}-${p.month}-${p.day}`,
    time: `${p.hour}:${p.minute}`,
  };
};
// dia + horário de São Paulo → o instante que vai para o servidor
export const dueAtFor = (date, time) => `${date}T${time}:00${SP_OFFSET}`;

const utcOf = date => {
  const [y, m, d] = String(date).split('-').map(Number);
  return new Date(Date.UTC(y, (m || 1) - 1, d || 1));
};
const isoOf = utc =>
  `${utc.getUTCFullYear()}-${pad(utc.getUTCMonth() + 1)}-${pad(utc.getUTCDate())}`;
export const dowOf = date => utcOf(date).getUTCDay();
export const addDays = (date, n) => {
  const utc = utcOf(date);
  utc.setUTCDate(utc.getUTCDate() + n);
  return isoOf(utc);
};
export const monthStart = date => `${String(date).slice(0, 7)}-01`;
export const addMonths = (date, n) => {
  const utc = utcOf(monthStart(date));
  utc.setUTCMonth(utc.getUTCMonth() + n);
  return isoOf(utc);
};
export const monthEnd = date => addDays(addMonths(date, 1), -1);
// as semanas do mês (domingo primeiro); null = casa vazia
export const monthGrid = date => {
  const first = monthStart(date);
  const last = monthEnd(date);
  const cells = Array(dowOf(first)).fill(null);
  for (let day = first; day <= last; day = addDays(day, 1)) cells.push(day);
  while (cells.length % 7) cells.push(null);
  const weeks = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
};

export const WEEKDAYS = [
  'domingo',
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
];
export const MONTHS = [
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
export const monthLabel = date => {
  const [y, m] = String(date).split('-').map(Number);
  return `${MONTHS[(m || 1) - 1]} de ${y}`;
};
export const dayLabel = date => {
  const [, m, d] = String(date).split('-').map(Number);
  return `${WEEKDAYS[dowOf(date)]}, ${d} de ${MONTHS[(m || 1) - 1]}`;
};
export const shortDay = date => {
  const [, m, d] = String(date).split('-');
  return `${d}/${m}`;
};

// os horários de uma faixa liberada
export const slotsOfWindow = win => {
  const block = Number(win?.block) > 0 ? Number(win.block) : 15;
  const out = [];
  for (let t = toMin(win?.start); t < toMin(win?.end); t += block)
    out.push(fromMin(t));
  return out;
};
export const windowsOn = (windows, date) =>
  (windows || [])
    .filter(w => Number(w.dow) === dowOf(date))
    .sort((a, b) => toMin(a.start) - toMin(b.start));

// a clínica fechou este dia (inteiro, a unidade ou o médico)? devolve o motivo
export const closedReason = (closed, date, unit) => {
  const hit = (closed || []).find(
    c => c.all || (c.date === date && !c.time && (!c.unit || c.unit === unit))
  );
  if (!hit) return null;
  return hit.reason || 'A clínica fechou esse dia.';
};
// cadeado de UM horário
export const padlocked = (closed, date, time, unit) =>
  (closed || []).some(
    c => c.date === date && c.time === time && (!c.unit || c.unit === unit)
  );

// o que cada horário do dia É para quem está no portal:
//   mine     = consulta do portal (com nome, telefone e ações)
//   private  = particular do médico marcada pela CLÍNICA (só o nome)
//   busy     = paciente da clínica (sem nome)
//   locked   = a clínica travou o horário
//   past     = já passou
//   free     = dá para marcar
export const dayPlan = ({
  date,
  windows,
  appointments,
  clinic,
  closed,
  now,
}) => {
  const live = (appointments || []).filter(a => !a.canceled_at);
  const mineAt = {};
  live.forEach(a => {
    const p = spParts(a.due_at);
    if (p.date === date) (mineAt[p.time] ||= []).push(a);
  });
  const clinicAt = {};
  (clinic || []).forEach(c => {
    const p = spParts(c.due_at);
    if (p.date === date) (clinicAt[p.time] ||= []).push(c);
  });
  const used = new Set();
  const groups = windowsOn(windows, date).map(win => {
    const reason = closedReason(closed, date, win.unit);
    const slots = slotsOfWindow(win).map(time => {
      const mine = (mineAt[time] || [])[0];
      const other = (clinicAt[time] || [])[0];
      let state = 'free';
      if (mine) state = 'mine';
      else if (other) state = other.particular ? 'private' : 'busy';
      else if (reason || padlocked(closed, date, time, win.unit))
        state = 'locked';
      else if (
        now &&
        (date < now.date || (date === now.date && time <= now.time))
      )
        state = 'past';
      if (mine) used.add(mine.id);
      return {
        time,
        unit: win.unit,
        state,
        appointment: mine || null,
        clinic: other || null,
      };
    });
    return { win, unit: win.unit, reason, slots };
  });
  // consultas do portal neste dia que ficaram fora das faixas de hoje (a
  // faixa mudou depois, ou a equipe moveu pela Agenda) — nunca somem da tela
  const extras = live
    .filter(a => spParts(a.due_at).date === date && !used.has(a.id))
    .sort((a, b) => new Date(a.due_at) - new Date(b.due_at));
  const all = groups.flatMap(g => g.slots);
  return {
    date,
    groups,
    extras,
    free: all.filter(s => s.state === 'free').length,
    mine: all.filter(s => s.state === 'mine').length + extras.length,
    hasWindow: groups.length > 0,
    closed: groups.length > 0 && groups.every(g => g.reason),
  };
};

// situação de uma consulta do portal, em uma palavra
export const appointmentStatus = (a, now) => {
  if (a.canceled_at) return { key: 'canceled', label: 'cancelada' };
  if (a.attendance === 'attended')
    return { key: 'attended', label: 'compareceu' };
  if (a.attendance === 'missed') return { key: 'missed', label: 'faltou' };
  if (a.confirmed_at) return { key: 'confirmed', label: 'confirmada' };
  const p = spParts(a.due_at);
  const past =
    now && (p.date < now.date || (p.date === now.date && p.time <= now.time));
  return past
    ? { key: 'unmarked', label: 'sem presença marcada' }
    : { key: 'pending', label: 'a confirmar' };
};

// "(11) 98888-7777" a partir do que a pessoa digita
export const maskPhone = value => {
  const d = String(value || '')
    .replace(/\D/g, '')
    .slice(0, 13);
  const local = d.length > 11 && d.startsWith('55') ? d.slice(2) : d;
  if (local.length <= 2) return local;
  if (local.length <= 6) return `(${local.slice(0, 2)}) ${local.slice(2)}`;
  if (local.length <= 10)
    return `(${local.slice(0, 2)}) ${local.slice(2, 6)}-${local.slice(6)}`;
  return `(${local.slice(0, 2)}) ${local.slice(2, 7)}-${local.slice(7, 11)}`;
};

// resumo das faixas em texto: "terça, 13:00 às 14:00 · Av. Paulista"
export const windowsText = (windows, unitLabel = key => key) =>
  (windows || [])
    .slice()
    .sort((a, b) => a.dow - b.dow || toMin(a.start) - toMin(b.start))
    .map(
      w =>
        `${WEEKDAYS[Number(w.dow)]}, ${w.start} às ${w.end} · ${unitLabel(w.unit)}`
    );
