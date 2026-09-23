// Dados e helpers da agenda da CEVICO — usados pela Agenda, pelo painel de
// Agendamentos e pelos indicadores do Meu Painel.

export const DOCTORS = [
  { name: 'Dr. Gustavo Bittar', short: 'Gustavo', color: '#0F5FA6' },
  { name: 'Dr. Henrique Gemelli', short: 'Henrique', color: '#B8860B' },
  { name: 'Dra. Roberta Negri', short: 'Roberta', color: '#7C3AED' },
];

// ── 📅 item 210 (23/09): os 4 TIPOS da agenda — cada um com a sua cor ──
// Consultas (avaliação/retorno), Teleconsultas (online), Exames e Cirurgias.
// No banco: cirurgia = task_type 'cirurgia'; os outros três são task_type
// 'consulta' e se separam pela modality ('teleconsulta' | 'exames' | resto).
// Assim o Atendente de Agendamento, o Secretário, a conferência do dia e o
// CRM continuam enxergando tudo como consulta — só a Agenda e os
// Agendamentos mostram cada tipo no seu trilho e na sua cor.
export const ONLINE_UNIT = 'online';
export const KINDS = [
  {
    key: 'consultas',
    label: 'Consultas',
    noun: 'consulta',
    plural: 'consultas',
    article: 'a',
    icon: 'i-lucide-stethoscope',
    color: '#2563EB',
    deep: '#1E40AF',
    grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)',
    grad2: 'linear-gradient(135deg, #2563EB, #60A5FA)',
    grad3: 'linear-gradient(135deg, #3B82F6, #93C5FD)',
    hero: 'linear-gradient(135deg, #152C61 0%, #1D4ED8 55%, #60A5FA 100%)',
    hint: 'avaliação e retorno nas unidades',
  },
  {
    key: 'teleconsultas',
    label: 'Teleconsultas',
    noun: 'teleconsulta',
    plural: 'teleconsultas',
    article: 'a',
    icon: 'i-lucide-video',
    color: '#7C3AED',
    deep: '#5B21B6',
    grad: 'linear-gradient(135deg, #6D28D9, #A78BFA)',
    grad2: 'linear-gradient(135deg, #7C3AED, #C4B5FD)',
    grad3: 'linear-gradient(135deg, #8B5CF6, #DDD6FE)',
    hero: 'linear-gradient(135deg, #3B0764 0%, #6D28D9 55%, #A78BFA 100%)',
    hint: 'consulta por vídeo, sem unidade',
  },
  {
    key: 'exames',
    label: 'Exames',
    noun: 'exame',
    plural: 'exames',
    article: 'o',
    icon: 'i-lucide-scan-eye',
    color: '#0D9488',
    deep: '#0F766E',
    grad: 'linear-gradient(135deg, #0F766E, #2DD4BF)',
    grad2: 'linear-gradient(135deg, #14B8A6, #5EEAD4)',
    grad3: 'linear-gradient(135deg, #2DD4BF, #99F6E4)',
    hero: 'linear-gradient(135deg, #134E4A 0%, #0F766E 55%, #2DD4BF 100%)',
    hint: 'pentacam, OCT, topografia… nas unidades',
  },
  {
    key: 'cirurgias',
    label: 'Cirurgias',
    noun: 'cirurgia',
    plural: 'cirurgias',
    article: 'a',
    icon: 'i-lucide-slice',
    color: '#0284C7',
    deep: '#075985',
    grad: 'linear-gradient(135deg, #0369A1, #38BDF8)',
    grad2: 'linear-gradient(135deg, #0EA5E9, #7DD3FC)',
    grad3: 'linear-gradient(135deg, #38BDF8, #BAE6FD)',
    hero: 'linear-gradient(135deg, #0C4A6E 0%, #0284C7 55%, #7DD3FC 100%)',
    hint: 'sala cirúrgica das clínicas parceiras',
  },
];
export const KIND_BY_KEY = Object.fromEntries(KINDS.map(k => [k.key, k]));
export const kindFor = key => KIND_BY_KEY[key] || KINDS[0];

// a que tipo uma task pertence
export const kindOf = task => {
  if (!task) return 'consultas';
  if (task.task_type === 'cirurgia') return 'cirurgias';
  if (task.modality === 'teleconsulta') return 'teleconsultas';
  if (task.modality === 'exames') return 'exames';
  return 'consultas';
};

// variáveis --cv* do kit "iMac G3 + vidro" para um tipo (a Agenda inteira
// veste a cor do trilho ativo)
export const hexToRgbSpaced = hex => {
  const h = String(hex || '').replace('#', '');
  if (h.length !== 6) return '37 99 235';
  return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)).join(' ');
};
export const kindVars = kind => {
  const k = typeof kind === 'string' ? kindFor(kind) : kind || KINDS[0];
  return {
    '--cv': k.color,
    '--cv-rgb': hexToRgbSpaced(k.color),
    '--cv-deep': k.deep,
    '--cv-deep-rgb': hexToRgbSpaced(k.deep),
    '--cv-grad': k.grad,
    '--cv-grad-2': k.grad2,
    '--cv-grad-3': k.grad3,
    '--cv-hero': k.hero,
    '--cv-alt': k.color,
    '--cv-alt-rgb': hexToRgbSpaced(k.color),
    '--cv-alt-grad': k.grad,
    '--cv-alt-ink': '#ffffff',
  };
};

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

// médicos com a agenda FECHADA (item 76) — as janelas deles somem em
// TODO consumidor (agenda, ocupação, saúde do Meu Painel)
export const resolveClosedDoctors = settings =>
  Array.isArray(settings?.agenda_closed_doctors) ? settings.agenda_closed_doctors : [];

// janelas salvas nas settings (ou o padrão) — sem os médicos fechados
export const resolveWindows = settings => {
  const saved = settings?.agenda_windows;
  const list = Array.isArray(saved) && saved.length
    ? saved.map(w => ({ ...w, dow: Number(w.dow), block: Number(w.block) }))
    : DEFAULT_WINDOWS;
  const closed = resolveClosedDoctors(settings);
  return closed.length ? list.filter(w => !closed.includes(w.doctor)) : list;
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

// modalidades de consulta — alimentam a ocupação por tipo e o formulário.
// item 210: entra 'teleconsulta' (trilho próprio na Agenda, cor violeta).
export const MODALITIES = [
  { key: 'avaliacao', label: 'Avaliação', color: '#2563EB' },
  { key: 'retorno', label: 'Retorno', color: '#D4A017' },
  { key: 'exames', label: 'Exames', color: '#0D9488' },
  { key: 'teleconsulta', label: 'Teleconsulta', color: '#7C3AED' },
];
export const modalityFor = key =>
  MODALITIES.find(m => m.key === (key || 'avaliacao')) || MODALITIES[0];

// varre um intervalo de dias e devolve estatísticas + primeiras vagas livres:
// tasks = consultas (com due_at); blockedSet = Set de blockKey.
// byModality: blocos ocupados POR TIPO de consulta (avaliação/retorno/exames)
// 23/09: igual ao servidor (Crm::AgendaSlots) — uma consulta COM unidade só
// ocupa o bloco daquela unidade; sem unidade ocupa em todas. Teleconsultas
// (unidade 'online') não ocupam bloco físico nenhum.
export const scanAgenda = ({ windows, tasks, blockedSet, blockedDays = new Set(), from, days, freeLimit = 3, futureOnly = false, pastOnly = false }) => {
  const occupied = new Set();
  const modalityByKey = new Map();
  tasks.forEach(t => {
    if (!t.due_at) return;
    if (t.unit === ONLINE_UNIT) return;
    const d = new Date(t.due_at);
    const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
    const mod = t.modality || 'avaliacao'; // consulta sem tipo = avaliação
    const key = blockKey(dateKey(d), hm, t.unit || '');
    occupied.add(key);
    if (!modalityByKey.has(key)) modalityByKey.set(key, mod);
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
