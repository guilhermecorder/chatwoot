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
// 🔬 AGENDA DE EXAMES (23/09, pedido dele): os exames têm janela PRÓPRIA,
// separada dos médicos — padrão: segunda a sexta, 08h–17h, no IOP da Av.
// Paulista, blocos de 30 min. Editável em Agenda → trilho Exames → "Janela
// de exames" (agenda_config.exam_windows).
export const DEFAULT_EXAM_WINDOWS = [1, 2, 3, 4, 5].map(dow => ({
  dow,
  unit: 'paulista',
  start: '08:00',
  end: '17:00',
  block: 30,
}));
export const resolveExamWindows = settings =>
  Array.isArray(settings?.exam_windows) && settings.exam_windows.length
    ? settings.exam_windows.map(w => ({
        ...w,
        dow: Number(w.dow),
        block: Number(w.block) || 30,
        unit: w.unit || 'paulista',
        exam: true,
      }))
    : DEFAULT_EXAM_WINDOWS.map(w => ({ ...w, exam: true }));

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
  { key: 'pos_op', label: 'Pós-operatório', color: '#DB2777' }, // item 234
  { key: 'exames', label: 'Exames', color: '#0D9488' },
  { key: 'teleconsulta', label: 'Teleconsulta', color: '#7C3AED' },
];

// 🎨 item 234 (25/09, pedido dele: "cada coisa precisa ter a sua própria cor"
// + "agenda geral" com CAMADAS): os 6 TIPOS de agendamento. Cada tipo tem cor
// própria e vira uma camada que liga/desliga na Agenda; o balão veste a cor
// do TIPO (a unidade virou uma etiqueta pequena). `kind` = trilho antigo que
// o backend e o painel de Agendamentos ainda usam; `resource` = o que o tipo
// ocupa (janela do médico, janela de exames, sala cirúrgica ou nada/online).
const mkType = t => ({
  ...t,
  grad: `linear-gradient(135deg, ${t.deep}, ${t.color})`,
  grad2: `linear-gradient(135deg, ${t.color}, ${t.light})`,
  grad3: `linear-gradient(135deg, ${t.light}, ${t.pale})`,
  hero: `linear-gradient(135deg, ${t.dark} 0%, ${t.deep} 55%, ${t.light} 100%)`,
});
export const TYPES = [
  mkType({ key: 'avaliacao', label: 'Avaliação', noun: 'avaliação', plural: 'avaliações', article: 'a', icon: 'i-lucide-stethoscope',
    color: '#2563EB', deep: '#1E40AF', light: '#60A5FA', pale: '#BFDBFE', dark: '#172554', kind: 'consultas', modality: 'avaliacao',
    resource: 'doctor', hint: 'primeira consulta com o médico, nas unidades' }),
  mkType({ key: 'retorno', label: 'Retorno', noun: 'retorno', plural: 'retornos', article: 'o', icon: 'i-lucide-rotate-ccw',
    color: '#D4A017', deep: '#A16207', light: '#FACC15', pale: '#FEF08A', dark: '#713F12', kind: 'consultas', modality: 'retorno',
    resource: 'doctor', hint: 'volta ao médico depois de exames ou tratamento' }),
  mkType({ key: 'pos_op', label: 'Pós-operatório', noun: 'pós-operatório', plural: 'pós-operatórios', article: 'o', icon: 'i-lucide-heart-pulse',
    color: '#DB2777', deep: '#9D174D', light: '#F472B6', pale: '#FBCFE8', dark: '#500724', kind: 'consultas', modality: 'pos_op',
    resource: 'doctor', hint: 'revisão depois da cirurgia' }),
  mkType({ key: 'exames', label: 'Exame', noun: 'exame', plural: 'exames', article: 'o', icon: 'i-lucide-scan-eye',
    color: '#0D9488', deep: '#0F766E', light: '#2DD4BF', pale: '#99F6E4', dark: '#134E4A', kind: 'exames', modality: 'exames',
    resource: 'exam', hint: 'pentacam, OCT, topografia… na janela de exames' }),
  mkType({ key: 'teleconsulta', label: 'Teleconsulta', noun: 'teleconsulta', plural: 'teleconsultas', article: 'a', icon: 'i-lucide-video',
    color: '#7C3AED', deep: '#5B21B6', light: '#A78BFA', pale: '#DDD6FE', dark: '#3B0764', kind: 'teleconsultas', modality: 'teleconsulta',
    resource: 'online', hint: 'consulta por vídeo, sem unidade' }),
  mkType({ key: 'cirurgia', label: 'Cirurgia', noun: 'cirurgia', plural: 'cirurgias', article: 'a', icon: 'i-lucide-slice',
    color: '#EA580C', deep: '#9A3412', light: '#FB923C', pale: '#FED7AA', dark: '#431407', kind: 'cirurgias', modality: null,
    resource: 'surgery', hint: 'sala cirúrgica das clínicas parceiras' }),
];
export const TYPE_BY_KEY = Object.fromEntries(TYPES.map(t => [t.key, t]));
// a "Agenda geral" (todas as camadas ligadas) veste um tom neutro
export const GENERAL_TYPE = mkType({ key: 'geral', label: 'Agenda geral', noun: 'agendamento', plural: 'agendamentos', article: 'o',
  icon: 'i-lucide-layers', color: '#475569', deep: '#1E293B', light: '#94A3B8', pale: '#CBD5E1', dark: '#0F172A', kind: null,
  modality: null, resource: null, hint: 'todos os tipos juntos — ligue e desligue as camadas' });
export const typeOf = task => {
  if (!task) return 'avaliacao';
  if (task.task_type === 'cirurgia') return 'cirurgia';
  return TYPE_BY_KEY[task.modality] ? task.modality : 'avaliacao';
};
// ?kind=consultas (links antigos) → camadas
export const LEGACY_KIND_TO_TYPES = {
  consultas: ['avaliacao', 'retorno', 'pos_op'],
  teleconsultas: ['teleconsulta'],
  exames: ['exames'],
  cirurgias: ['cirurgia'],
};
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
