// Dados e helpers da agenda — usados pela Agenda e pelos indicadores do
// Meu Painel. Profissionais, janelas, unidades e modalidades vêm do
// SEGMENTO (window.SEGMENTO ← config/segmentos/<id>.yml, sistema coringa);
// os valores chumbados abaixo são o preset clínica, usado como fallback
// quando não há pacote (testes, contexto sem layout).
import { SEGMENTO } from './segmento';

const FALLBACK_DOCTORS = [
  { name: 'Dr. Gustavo Bittar', short: 'Gustavo', color: '#0F5FA6' },
  { name: 'Dr. Henrique Gemelli', short: 'Henrique', color: '#B8860B' },
  { name: 'Dra. Roberta Negri', short: 'Roberta', color: '#7C3AED' },
];

// os "médicos" do segmento (na clínica, os 3 de sempre)
export const DOCTORS = Array.isArray(SEGMENTO.profissionais) && SEGMENTO.profissionais.length
  ? SEGMENTO.profissionais.map(p => ({
      name: p.nome,
      short: p.apelido || p.nome,
      color: p.cor || '#64748B',
    }))
  : FALLBACK_DOCTORS;

// unidades do segmento (keys gravadas nas tasks; label/cor p/ exibição)
const FALLBACK_UNITS = [
  { key: 'tatuape', nome: 'Tatuapé', cor: '#2563EB' },
  { key: 'paulista', nome: 'Av. Paulista', cor: '#EA580C' },
];
export const UNITS_LIST = Array.isArray(SEGMENTO.unidades) && SEGMENTO.unidades.length
  ? SEGMENTO.unidades
  : FALLBACK_UNITS;
export const UNIT_LABELS = Object.fromEntries(UNITS_LIST.map(u => [u.key, u.nome]));
export const unitLabel = key => UNIT_LABELS[key] || key || '';
export const DEFAULT_UNIT = UNITS_LIST[0]?.key || '';

// dow: 0=Dom … 6=Sáb; end é exclusivo (último bloco = end - block).
// Mapa padrão — editável em Agenda → "Janelas dos médicos".
const FALLBACK_WINDOWS = [
  { dow: 1, unit: 'paulista', doctor: 'Dr. Gustavo Bittar',   turno: 'Manhã', start: '08:30', end: '10:00', block: 15 },
  { dow: 2, unit: 'paulista', doctor: 'Dr. Henrique Gemelli', turno: 'Manhã', start: '08:00', end: '11:30', block: 15 },
  { dow: 2, unit: 'paulista', doctor: 'Dra. Roberta Negri',   turno: 'Tarde', start: '14:30', end: '16:30', block: 15 },
  { dow: 3, unit: 'paulista', doctor: 'Dr. Henrique Gemelli', turno: 'Tarde', start: '13:00', end: '17:00', block: 15 },
  { dow: 3, unit: 'tatuape',  doctor: 'Dr. Gustavo Bittar',   turno: 'Manhã', start: '08:30', end: '11:00', block: 10 },
  { dow: 4, unit: 'paulista', doctor: 'Dr. Gustavo Bittar',   turno: 'Manhã', start: '08:30', end: '11:00', block: 15 },
  { dow: 5, unit: 'tatuape',  doctor: 'Dra. Roberta Negri',   turno: 'Manhã', start: '10:30', end: '13:00', block: 10 },
];
export const DEFAULT_WINDOWS = Array.isArray(SEGMENTO.janelas_padrao)
  ? SEGMENTO.janelas_padrao.map(w => ({
      ...w,
      dow: Number(w.dow),
      block: Number(w.block) || 15,
    }))
  : FALLBACK_WINDOWS;

// ── Personalização por conta (Configurações → Personalização) ──
// resolução: conta (settings.segment) > segmento (window.SEGMENTO) >
// preset clínica. Sem nada salvo, comportamento idêntico ao de sempre.
export const resolveDoctors = settings => {
  const saved = settings?.segment?.professionals;
  return Array.isArray(saved) && saved.some(p => p.nome)
    ? saved
        .filter(p => p.nome)
        .map(p => ({ name: p.nome, short: p.apelido || p.nome, color: p.cor || '#64748B' }))
    : DOCTORS;
};

export const resolveUnits = settings => {
  const saved = settings?.segment?.units;
  return Array.isArray(saved) && saved.some(u => u.key) ? saved.filter(u => u.key) : UNITS_LIST;
};

export const resolveUnitLabels = settings =>
  Object.fromEntries(resolveUnits(settings).map(u => [u.key, u.nome || u.key]));

// listas editáveis (problemas, procedimentos) — conta > segmento > fallback
export const resolveSegmentList = (settings, key, fallback) => {
  const saved = settings?.segment?.[key];
  return Array.isArray(saved) && saved.length ? saved : fallback;
};

// metas ({vendas_mes: 100}) — conta > segmento > fallback
export const resolveGoal = (settings, key, fallback) => {
  const v = Number(settings?.segment?.metas?.[key]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
};

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

// modalidades de atendimento — alimentam a ocupação por tipo
// (keys fixas — gravadas nas tasks; labels/cores do segmento)
const FALLBACK_MODALITIES = [
  { key: 'avaliacao', label: 'Avaliação', color: '#0F5FA6' },
  { key: 'retorno', label: 'Retorno', color: '#D4A017' },
  { key: 'exames', label: 'Exames', color: '#7C3AED' },
];
export const MODALITIES = Array.isArray(SEGMENTO.modalidades) && SEGMENTO.modalidades.length
  ? SEGMENTO.modalidades.map(m => ({
      key: m.key,
      label: m.label,
      color: m.cor || '#64748B',
    }))
  : FALLBACK_MODALITIES;

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
