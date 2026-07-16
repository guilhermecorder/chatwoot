// Dados e helpers da agenda de avaliação da CEVICO — usados pela Agenda e
// pelos indicadores do Meu Painel.

export const DOCTORS = [
  { name: 'Dr. Gustavo Bittar', short: 'Gustavo', color: '#0F5FA6' },
  { name: 'Dr. Henrique Gemelli', short: 'Henrique', color: '#B8860B' },
  { name: 'Dra. Roberta Negri', short: 'Roberta', color: '#7C3AED' },
];

// dow: 0=Dom … 6=Sáb; end é exclusivo (último bloco = end - block).
// Mapa padrão — editável em Agenda → "Janelas dos médicos".
export const DEFAULT_WINDOWS = [
  { dow: 1, unit: 'paulista', doctor: 'Dr. Gustavo Bittar',   turno: 'Manhã', start: '08:30', end: '10:00', block: 15 },
  { dow: 2, unit: 'paulista', doctor: 'Dr. Henrique Gemelli', turno: 'Manhã', start: '08:00', end: '11:30', block: 15 },
  { dow: 2, unit: 'paulista', doctor: 'Dra. Roberta Negri',   turno: 'Tarde', start: '14:30', end: '16:30', block: 15 },
  { dow: 3, unit: 'paulista', doctor: 'Dr. Henrique Gemelli', turno: 'Tarde', start: '13:00', end: '17:00', block: 15 },
  { dow: 3, unit: 'tatuape',  doctor: 'Dr. Gustavo Bittar',   turno: 'Manhã', start: '08:30', end: '11:00', block: 10 },
  { dow: 4, unit: 'paulista', doctor: 'Dr. Gustavo Bittar',   turno: 'Manhã', start: '08:30', end: '11:00', block: 15 },
  { dow: 5, unit: 'tatuape',  doctor: 'Dra. Roberta Negri',   turno: 'Manhã', start: '10:30', end: '13:00', block: 10 },
];

// janelas salvas nas settings (ou o padrão)
export const resolveWindows = settings => {
  const saved = settings?.agenda_windows;
  return Array.isArray(saved) && saved.length
    ? saved.map(w => ({ ...w, dow: Number(w.dow), block: Number(w.block) }))
    : DEFAULT_WINDOWS;
};

export const resolveBlocked = settings =>
  Array.isArray(settings?.agenda_blocked) ? settings.agenda_blocked : [];

// janelas da SALA CIRÚRGICA (trilho de cirurgias) — unit recebe a key do
// local para reusar slotsFor/scanAgenda/blockKey sem mudança
export const resolveSurgeryWindows = settings =>
  Array.isArray(settings?.surgery_windows)
    ? settings.surgery_windows.map(w => ({
        ...w,
        dow: Number(w.dow),
        block: Number(w.block) || 60,
        unit: w.location,
      }))
    : [];

export const resolveBlockedDays = settings =>
  Array.isArray(settings?.agenda_blocked_days) ? settings.agenda_blocked_days : [];

// blocos ('08:30', '08:45'…) de uma janela
export const slotsFor = win => {
  const [sh, sm] = win.start.split(':').map(Number);
  const [eh, em] = win.end.split(':').map(Number);
  const slots = [];
  for (let t = sh * 60 + sm; t < eh * 60 + em; t += win.block) {
    slots.push(`${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`);
  }
  return slots;
};

export const dateKey = d => {
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

export const blockKey = (dateStr, time, unit) => `${dateStr}|${time}|${unit}`;

// modalidades de consulta — alimentam a ocupação por tipo
export const MODALITIES = [
  { key: 'avaliacao', label: 'Avaliação', color: '#0F5FA6' },
  { key: 'retorno', label: 'Retorno', color: '#D4A017' },
  { key: 'exames', label: 'Exames', color: '#7C3AED' },
];

// varre um intervalo de dias e devolve estatísticas + primeiras vagas livres:
// tasks = consultas (com due_at); blockedSet = Set de blockKey.
// byModality: blocos ocupados POR TIPO de consulta (avaliação/retorno/exames)
export const scanAgenda = ({ windows, tasks, blockedSet, blockedDays = new Set(), from, days, freeLimit = 3, futureOnly = false, pastOnly = false }) => {
  const occupied = new Set();
  const modalityByKey = new Map();
  tasks.forEach(t => {
    if (!t.due_at) return;
    const d = new Date(t.due_at);
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    const mod = t.modality || 'avaliacao'; // consulta sem tipo = avaliação
    const withUnit = blockKey(dateKey(d), hm, t.unit || '');
    const noUnit = `${dateKey(d)}|${hm}|`; // sem unidade também ocupa
    occupied.add(withUnit);
    occupied.add(noUnit);
    if (!modalityByKey.has(withUnit)) modalityByKey.set(withUnit, mod);
    if (!modalityByKey.has(noUnit)) modalityByKey.set(noUnit, mod);
  });

  const now = new Date();
  let total = 0;
  let filled = 0;
  const byModality = {};
  const freeSlots = [];

  for (let i = 0; i < days; i += 1) {
    const day = new Date(from);
    day.setDate(day.getDate() + i);
    const dow = day.getDay();
    if (dow === 0 || dow === 6) continue; // fim de semana bloqueado
    if (blockedDays.has(dateKey(day))) continue; // dia fechado inteiro

    windows
      .filter(w => w.dow === dow)
      .forEach(win => {
        slotsFor(win).forEach(slot => {
          const key = blockKey(dateKey(day), slot, win.unit);
          if (blockedSet.has(key)) return; // fechado com cadeado — fora da conta

          const slotDate = new Date(`${dateKey(day)}T${slot}`);
          if (futureOnly && slotDate <= now) return;
          if (pastOnly && slotDate > now) return;

          total += 1;
          const noUnitKey = blockKey(dateKey(day), slot, '');
          const isTaken = occupied.has(key) || occupied.has(noUnitKey);
          if (isTaken) {
            filled += 1;
            const mod = modalityByKey.get(key) || modalityByKey.get(noUnitKey) || 'avaliacao';
            byModality[mod] = (byModality[mod] || 0) + 1;
          } else if (freeSlots.length < freeLimit && slotDate > now) {
            freeSlots.push({ day: new Date(day), slot, win });
          }
        });
      });
  }

  return { total, filled, freeSlots, byModality, pct: total ? Math.round((filled / total) * 100) : 0 };
};
