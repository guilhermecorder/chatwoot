<script setup>
// Meu Painel (tela inicial) — visível para admin E atendentes.
// Boas-vindas, avisos do Radar, indicadores por período (régua padrão:
// hoje/ontem/últimos 7/mês/ano/personalizado) e a saúde da agenda —
// com atalhos para agir rápido.
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import SkeletonPiece from 'dashboard/components-next/cevico/SkeletonPiece.vue';
import EmojiFx from 'dashboard/components-next/cevico/EmojiFx.vue';
import TileAura from 'dashboard/components-next/radar/TileAura.vue';
import PatientSpaceIcon from 'dashboard/routes/dashboard/patient/PatientSpaceIcon.vue';
import ConversationChatModal from 'dashboard/routes/dashboard/crm/components/ConversationChatModal.vue';
import CustomPanelGrid from 'dashboard/components-next/cevico/CustomPanelGrid.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import AgendaDashboardCore from 'dashboard/components-next/cevico/AgendaDashboardCore.vue';
import CrmAPI from 'dashboard/api/crm';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import { paletteByKey } from 'dashboard/helper/cevicoBuilderCatalog';
import {
  DOCTORS, resolveWindows, resolveBlocked, resolveBlockedDays,
  resolveSurgeryWindows, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';

const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');
const crmSettings = useMapGetter('crm/getSettings');
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const data = ref(null);

// ── Período ─────────────────────────────────────────────────
// Régua PADRÃO dos dashboards (PeriodRuler): Hoje/Ontem/Últimos 7 dias/
// Este mês/Este ano + Personalizado (De/Até). O v-model traz sempre
// { preset, from, to } — nos presets o backend resolve as datas sozinho.
const pad2 = n => String(n).padStart(2, '0');
const hojeStr = (() => {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
})();
const period = ref({ preset: 'today', from: hojeStr, to: hojeStr });

// ── Painéis por pessoa: mesmo layout, indicadores e cores da função ──
const BASE_PANELS = [
  {
    key: 'agendamento', label: 'Agendamento', who: '',
    icon: 'i-lucide-calendar-check', desc: 'do lead ao agendamento',
    grad: 'linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)',
  },
  {
    key: 'conducao', label: 'Condução', who: '',
    icon: 'i-lucide-route', desc: 'do agendamento à indicação',
    grad: 'linear-gradient(135deg, #0F766E 0%, #2DD4BF 100%)',
  },
  {
    key: 'cirurgia', label: 'Cirurgias', who: '',
    icon: 'i-lucide-heart-pulse', desc: 'fechamento e pós-operatório',
    grad: 'linear-gradient(135deg, #9D174D 0%, #F472B6 100%)',
  },
  {
    key: 'medico', label: 'Médicos', who: '',
    icon: 'i-lucide-stethoscope', desc: 'a agenda de cada médico',
    grad: 'linear-gradient(135deg, #0369A1 0%, #38BDF8 100%)',
  },
  {
    key: 'gestor', label: 'Gestor', who: '',
    icon: 'i-lucide-line-chart', desc: 'indicadores-chave do processo inteiro',
    grad: 'linear-gradient(135deg, #111827 0%, #475569 60%, #94A3B8 100%)',
  },
];

// RESPONSÁVEL por painel (Configurações → Painéis): o 1º nome aparece na
// pílula — "Cirurgias · Elizangela". Sem responsável = só o tema.
const panelOwners = computed(() => crmSettings.value?.panel_owners || {});
const ownerFirstName = key =>
  (panelOwners.value[key]?.name || '').split(' ')[0] || '';

// painéis do CONSTRUTOR salvos pela conta viram pílulas junto dos fixos
// (key 'custom:<id>' — o backend do home já entende esse formato)
const allPanels = computed(() => [
  ...BASE_PANELS.map(p => ({ ...p, who: ownerFirstName(p.key) || p.who })),
  ...(crmSettings.value?.custom_panels || []).map(p => ({
    key: `custom:${p.id}`,
    label: p.name,
    who: '',
    icon: 'i-lucide-magnet',
    desc: 'painel do Construtor',
    grad: paletteByKey(p.palette).grads[0],
    custom: true,
    panelDef: p,
  })),
]);

// painel ATRIBUÍDO pelo admin: o agente fica travado nele
const assignedPanel = computed(() => {
  if (isAdmin.value) return null;
  const map = crmSettings.value?.panel_assignments || {};
  return map[String(currentUser.value?.id)] || null;
});
const visiblePanels = computed(() => {
  if (!assignedPanel.value) return allPanels.value;
  const only = allPanels.value.filter(p => p.key === assignedPanel.value);
  // atribuição órfã (painel custom excluído) libera todos de novo
  return only.length ? only : allPanels.value;
});

// ── Admin: quem vê qual painel (engrenagem ao lado das pílulas) ──
const showAssignModal = ref(false);
const assignDraft = ref({});
const isSavingAssign = ref(false);
const openAssignModal = () => {
  assignDraft.value = { ...(crmSettings.value?.panel_assignments || {}) };
  if (!teamAgents.value.length) store.dispatch('agents/get');
  showAssignModal.value = true;
};
const saveAssignments = async () => {
  if (isSavingAssign.value) return;
  isSavingAssign.value = true;
  try {
    const clean = Object.fromEntries(
      Object.entries(assignDraft.value).filter(([, v]) => v)
    );
    await CrmAPI.updatePanelAssignments(clean);
    await store.dispatch('crm/fetchSettings');
    showAssignModal.value = false;
  } finally {
    isSavingAssign.value = false;
  }
};
// escolha manual NESTE aparelho manda; sem ela, o painel PRINCIPAL da
// conta (settings.main_panel) assume quando as configurações chegarem
const storedPanel = localStorage.getItem('cevico_meu_painel');
const selectedPanel = ref(storedPanel || 'agendamento');
watch(assignedPanel, key => {
  if (key && selectedPanel.value !== key && allPanels.value.some(p => p.key === key)) {
    selectedPanel.value = key;
    fetchData();
  }
});
const selectedDoctor = ref(localStorage.getItem('cevico_meu_painel_medico') || '');
const currentPanel = computed(
  () => allPanels.value.find(p => p.key === selectedPanel.value) || BASE_PANELS[0]
);

// settings chegaram: (1) aplica o painel principal UMA vez — só se a
// pessoa nunca escolheu manualmente; (2) painel custom excluído cai
// para o padrão de fábrica
let mainPanelApplied = false;
watch(crmSettings, settings => {
  if (!settings || !Object.keys(settings).length) return;
  if (!mainPanelApplied) {
    mainPanelApplied = true;
    const main = settings.main_panel;
    if (
      !storedPanel && !assignedPanel.value && main &&
      main !== selectedPanel.value && allPanels.value.some(p => p.key === main)
    ) {
      selectedPanel.value = main;
      fetchData();
    }
  }
  if (
    selectedPanel.value.startsWith('custom:') &&
    !allPanels.value.some(p => p.key === selectedPanel.value)
  ) {
    selectedPanel.value = 'agendamento';
    fetchData();
  }
});

const fetchData = async () => {
  try {
    const { preset, from, to } = period.value;
    const { data: payload } = await CrmAPI.getHome({
      preset,
      panel: selectedPanel.value,
      doctor: selectedPanel.value === 'medico' ? selectedDoctor.value || undefined : undefined,
      // só o Personalizado manda De/Até; nos presets o backend resolve
      ...(preset === 'custom' ? { from, to } : {}),
    });
    data.value = payload;
  } catch {
    data.value = data.value || {};
  } finally {
    isLoading.value = false;
  }
};

// régua nova: qualquer mudança (preset ou De/Até) recarrega o painel
watch(period, fetchData);

const setPanel = key => {
  selectedPanel.value = key;
  localStorage.setItem('cevico_meu_painel', key); // cada pessoa fica no seu painel
  fetchData();
};

const setDoctor = name => {
  selectedDoctor.value = name;
  localStorage.setItem('cevico_meu_painel_medico', name);
  fetchData();
};

// indicadores de cada painel (mesmo formato de tiles, cores próprias)
const pd = computed(() => data.value?.panel_data || {});
const panelTiles = computed(() => {
  // painel do Construtor tem grade própria (CustomPanelGrid) — sem tiles fixas
  if (currentPanel.value.custom) return [];
  const d = pd.value;
  if (selectedPanel.value === 'conducao') {
    return [
      { label: 'Consultas no período', icon: 'i-lucide-calendar-days', value: d.consultations ?? 0, gk: 'consultations', sub: 'agenda das unidades', grad: 'linear-gradient(135deg, #0F766E, #115E59)' },
      { label: 'Compareceram', icon: 'i-lucide-user-check', value: d.attended ?? 0, gk: 'attended', sub: 'conferência do dia (Agenda)', grad: 'linear-gradient(135deg, #14B8A6, #0D9488)' },
      { label: 'Comparecimento', icon: 'i-lucide-percent', value: `${d.show_rate ?? 0}%`, gk: 'show_rate', pct: true, sub: `${d.missed ?? 0} falta(s) no período`, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
      { label: 'Indicações de cirurgia', icon: 'i-lucide-stethoscope', value: d.indications ?? 0, gk: 'indications', sub: 'saíram da consulta indicados', grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
    ];
  }
  if (selectedPanel.value === 'cirurgia') {
    return [
      { label: 'Indicações de cirurgia', icon: 'i-lucide-stethoscope', value: d.indications ?? 0, gk: 'indications', sub: 'pacientes indicados no período', grad: 'linear-gradient(135deg, #9D174D, #BE185D)' },
      { label: 'Cirurgias agendadas', icon: 'i-lucide-calendar-plus', value: d.surgeries_booked ?? 0, gk: 'surgeries_booked', sub: 'fechadas no período', grad: 'linear-gradient(135deg, #BE185D, #EC4899)' },
      { label: 'Taxa de fechamento', icon: 'i-lucide-percent', value: `${d.closing_rate ?? 0}%`, gk: 'closing_rate', pct: true, sub: 'agendadas ÷ indicações', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
      { label: 'Cirurgias realizadas', icon: 'i-lucide-heart-pulse', value: d.surgeries_done ?? 0, gk: 'surgeries_done', sub: `${d.surgeries_missed ?? 0} não vieram`, grad: 'linear-gradient(135deg, #65A30D, #84CC16)' },
    ];
  }
  if (selectedPanel.value === 'medico') {
    return [
      { label: 'Consultas no período', icon: 'i-lucide-calendar-days', value: d.consultations ?? 0, gk: 'consultations', sub: `${d.missed ?? 0} falta(s) · ${d.show_rate ?? 0}% comparecimento`, grad: 'linear-gradient(135deg, #0369A1, #075985)' },
      { label: 'Com indicação de cirurgia', icon: 'i-lucide-stethoscope', value: d.indications ?? 0, gk: 'indications', sub: `${d.indication_rate ?? 0}% de quem compareceu`, grad: 'linear-gradient(135deg, #0EA5E9, #38BDF8)' },
      { label: 'Sem indicação', icon: 'i-lucide-user-minus', value: d.no_indication ?? 0, sub: `${d.no_indication_rate ?? 0}% de quem compareceu`, grad: 'linear-gradient(135deg, #64748B, #94A3B8)' },
      { label: 'Conversão em cirurgia', icon: 'i-lucide-percent', value: `${d.conversion_rate ?? 0}%`, gk: 'conversion_rate', pct: true, sub: `${d.conversions ?? 0} viraram cirurgia · NPS ${d.nps_avg ?? '—'}`, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
    ];
  }
  if (selectedPanel.value === 'gestor') {
    return [
      { label: 'Novos contatos (leads)', icon: 'i-lucide-user-plus', value: d.new_leads ?? 0, gk: 'new_leads', sub: leadsInboxSub.value, sub2: leadsInboxConversion.value, grad: 'linear-gradient(135deg, #0F5FA6, #0B4A82)' },
      { label: 'Taxa de agendamento', icon: 'i-lucide-percent', value: `${d.booking_conversion ?? 0}%`, gk: 'booking_conversion', pct: true, sub: `${d.appointments_created ?? 0} dos ${d.new_leads ?? 0} leads do período`, sub2: 'avançaram até "Agendamento" no CRM', grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
      { label: 'Comparecimento', icon: 'i-lucide-user-check', value: `${d.show_rate ?? 0}%`, gk: 'show_rate', pct: true, sub: `${d.indications ?? 0} indicação(ões) de cirurgia`, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
      { label: 'Fechamento de cirurgias', icon: 'i-lucide-heart-pulse', value: `${d.closing_rate ?? 0}%`, gk: 'closing_rate', pct: true, sub: `${d.surgeries_booked ?? 0} agendada(s) · ${d.surgeries_done ?? 0} realizada(s)`, grad: 'linear-gradient(135deg, #065F46, #10B981)' },
    ];
  }
  // agendamento (padrão)
  return [
    { label: 'Novos contatos (leads)', icon: 'i-lucide-user-plus', value: d.new_leads ?? 0, gk: 'new_leads', sub: leadsInboxSub.value, sub2: leadsInboxConversion.value, grad: 'linear-gradient(135deg, #0F5FA6, #0B4A82)' },
    { label: 'Consultas agendadas', icon: 'i-lucide-calendar-check', value: d.appointments_booked ?? 0, gk: 'appointments_booked', sub: 'registradas no período', sub2: `⚡ ${d.appointments_same_day ?? 0} chegaram e agendaram`, sub3: decisionSub.value, grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
    { label: 'Agendamentos hoje', icon: 'i-lucide-calendar-plus', value: d.booked_today ?? 0, chip: bookingDayVerdict.value, sub: cohortLine('today', 'chegaram hoje'), sub2: cohortLine('yesterday', 'chegaram ontem'), grad: bookingDayVerdict.value.grad },
    { label: 'Cirurgias fechadas', icon: 'i-lucide-heart-pulse', value: d.surgeries_closed ?? 0, gk: 'surgeries_closed', sub: 'coluna Cirurgia Agendada (CRM)', grad: 'linear-gradient(135deg, #65A30D, #84CC16)' },
  ];
});

// ── CARDS VIVOS: metas, recordes e cores por desempenho ──
// Meta é MENSAL (config do admin na mira 🎯); o backend manda o fator do
// período. Status: 🔴 <40% do esperado · 🟠 40-70% · cores do painel
// 70-100% · 🟢 meta batida · 🏆 recorde = aura de átomos orbitando.
const goalsInfo = computed(() => data.value?.goals || { targets: {}, factor: 1, records: {} });

// 🎯 METAS OFICIAIS (Painel de Metas) como FALLBACK dos alvos da mira —
// a régua de cores (abaixo/dentro/acima da meta) vale em TODOS os painéis
// (Agendamento, Condução, Cirurgias, Médicos, Gestor), mesmo sem mira própria
// configurada. Pedido 18/07 (item 79).
const officialGoals = useCevicoGoals();
onMounted(() => officialGoals.load());
const OFFICIAL_GK = {
  new_leads: 'new_leads',
  appointments_booked: 'appointments_booked',
  consultations: 'appointments_booked',
  attended: 'consultations_attended',
  surgeries_booked: 'surgeries_booked',
  surgeries_done: 'surgeries_done',
  surgeries_closed: 'surgeries_booked',
};
const officialTargetFor = gk => {
  const key = OFFICIAL_GK[gk];
  if (!key) return 0;
  return Number(officialGoals.infoFor(key)?.target || 0);
};

// paleta de "bom e mau resultado" POR PAINEL (o mau alerta, o meta celebra)
const STATUS_GRADS = {
  agendamento: { bad: 'linear-gradient(135deg, #7F1D1D, #B91C1C)', warn: 'linear-gradient(135deg, #92400E, #D97706)', meta: 'linear-gradient(135deg, #065F46, #10B981)' },
  conducao: { bad: 'linear-gradient(135deg, #7F1D1D, #B91C1C)', warn: 'linear-gradient(135deg, #92400E, #D97706)', meta: 'linear-gradient(135deg, #0F766E, #2DD4BF)' },
  cirurgia: { bad: 'linear-gradient(135deg, #831843, #4C0519)', warn: 'linear-gradient(135deg, #9A3412, #EA580C)', meta: 'linear-gradient(135deg, #047857, #34D399)' },
  medico: { bad: 'linear-gradient(135deg, #7F1D1D, #991B1B)', warn: 'linear-gradient(135deg, #A16207, #EAB308)', meta: 'linear-gradient(135deg, #065F46, #14B8A6)' },
  gestor: { bad: 'linear-gradient(135deg, #450A0A, #991B1B)', warn: 'linear-gradient(135deg, #78350F, #F59E0B)', meta: 'linear-gradient(135deg, #064E3B, #10B981)' },
};

const tileState = tile => {
  const g = goalsInfo.value;
  const value = parseFloat(String(tile.value)) || 0;
  // mira 🎯 do painel manda; sem ela, vale a meta OFICIAL do mês
  const target = Number(g.targets?.[tile.gk]) || officialTargetFor(tile.gk);
  const rec = g.records?.[tile.gk];
  let status = 'none';
  let ratio = null;
  let expected = null;
  if (tile.gk && target > 0) {
    expected = tile.pct ? target : target * (g.factor || 1);
    ratio = expected > 0 ? value / expected : null;
    if (ratio >= 1) status = 'meta';
    else if (ratio >= 0.7) status = 'ok';
    else if (ratio >= 0.4) status = 'warn';
    else status = 'bad';
  }
  // pedido 22/07: até MEIO-DIA as cores ficam neutras — de manhã o dia mal
  // começou e o "vermelho de ritmo" só assusta. Meta batida/recorde são
  // fatos (não julgamento de ritmo) e continuam aparecendo.
  if (['bad', 'warn'].includes(status) && new Date().getHours() < 12)
    status = 'neutral';
  return { status, ratio, expected, isRecord: !!rec?.is_record, best: rec?.best || 0 };
};

const tileVisual = tile => {
  const st = tileState(tile);
  const grads = STATUS_GRADS[selectedPanel.value] || STATUS_GRADS.agendamento;
  return {
    ...st,
    // sem status de meta mandando, um chip "Muito bom" pinta o card de
    // verde (pedido 22/07 — o dourado confundia com "neutro")
    grad: ['bad', 'warn', 'meta'].includes(st.status)
      ? grads[st.status]
      : tile.chip?.grad || tile.grad,
    aura: st.isRecord,
    auraIntensity: Math.max(0.5, Math.min(1.2, st.ratio ?? 0.7)),
    pulse: st.status === 'meta' || st.isRecord,
  };
};

// ── modal de METAS (admin, mira 🎯 ao lado das pílulas) ──
const showGoalsModal = ref(false);
const goalsDraft = ref({});
const isSavingGoals = ref(false);
const GOAL_FIELDS = {
  agendamento: [
    { gk: 'new_leads', label: 'Novos contatos no mês' },
    { gk: 'appointments_booked', label: 'Consultas agendadas no mês' },
    { gk: 'booking_conversion', label: 'Taxa de agendamento (%)', pct: true },
    { gk: 'surgeries_closed', label: 'Cirurgias fechadas no mês' },
  ],
  conducao: [
    { gk: 'consultations', label: 'Consultas no mês' },
    { gk: 'attended', label: 'Comparecimentos no mês' },
    { gk: 'show_rate', label: 'Comparecimento (%)', pct: true },
    { gk: 'indications', label: 'Indicações no mês' },
  ],
  cirurgia: [
    { gk: 'indications', label: 'Indicações no mês' },
    { gk: 'surgeries_booked', label: 'Cirurgias agendadas no mês' },
    { gk: 'closing_rate', label: 'Taxa de fechamento (%)', pct: true },
    { gk: 'surgeries_done', label: 'Cirurgias realizadas no mês' },
  ],
  medico: [
    { gk: 'consultations', label: 'Consultas no mês' },
    { gk: 'indications', label: 'Indicações no mês' },
    { gk: 'conversion_rate', label: 'Conversão em cirurgia (%)', pct: true },
  ],
  gestor: [
    { gk: 'new_leads', label: 'Novos contatos no mês' },
    { gk: 'booking_conversion', label: 'Taxa de agendamento (%)', pct: true },
    { gk: 'show_rate', label: 'Comparecimento (%)', pct: true },
    { gk: 'closing_rate', label: 'Fechamento de cirurgias (%)', pct: true },
  ],
};
const openGoalsModal = () => {
  const all = crmSettings.value?.panel_goals || {};
  goalsDraft.value = JSON.parse(JSON.stringify(all));
  if (!goalsDraft.value[selectedPanel.value]) goalsDraft.value[selectedPanel.value] = {};
  showGoalsModal.value = true;
};
const saveGoals = async () => {
  if (isSavingGoals.value) return;
  isSavingGoals.value = true;
  try {
    const clean = {};
    Object.entries(goalsDraft.value).forEach(([panel, goals]) => {
      const g = Object.fromEntries(Object.entries(goals || {}).filter(([, v]) => Number(v) > 0));
      if (Object.keys(g).length) clean[panel] = g;
    });
    await CrmAPI.updatePanelGoals(clean);
    await store.dispatch('crm/fetchSettings');
    showGoalsModal.value = false;
    fetchData();
  } finally {
    isSavingGoals.value = false;
  }
};

// ── GESTOR: "posso viajar?" — o indicador próprio de decisão ──
// agrega metas em vermelho, radar, sem resposta e pendências num
// semáforo único com os motivos prontos para agir
const gestorSignals = computed(() => {
  if (selectedPanel.value !== 'gestor' || !data.value) return [];
  const sigs = [];
  (panelTiles.value || []).forEach(tile => {
    const st = tileState(tile);
    if (st.status === 'bad') sigs.push({ level: 'red', icon: 'i-lucide-trending-down', text: `${tile.label}: muito abaixo da meta (${tile.value})` });
    else if (st.status === 'warn') sigs.push({ level: 'amber', icon: 'i-lucide-alert-triangle', text: `${tile.label}: abaixo do ritmo da meta (${tile.value})` });
  });
  const alerts = radarAlerts.value.length;
  if (alerts) sigs.push({ level: 'red', icon: 'i-lucide-radar', text: `${alerts} paciente(s) quente(s) sem atendimento (Radar)` });
  const waiting = data.value.unanswered ?? 0;
  if (waiting > 8) sigs.push({ level: 'amber', icon: 'i-lucide-message-circle', text: `${waiting} conversas abertas aguardando resposta` });
  const unconfirmed = data.value.panel_data?.unconfirmed ?? 0;
  if (unconfirmed > 0) sigs.push({ level: 'amber', icon: 'i-lucide-clipboard-alert', text: `${unconfirmed} consulta(s) sem conferência na Agenda` });
  const bugs = data.value.my_tasks?.count ?? 0;
  if (bugs > 0) sigs.push({ level: 'info', icon: 'i-lucide-list-todo', text: `${bugs} tarefa(s) esperando você no board` });
  return sigs;
});
const gestorVerdict = computed(() => {
  const sigs = gestorSignals.value;
  if (sigs.some(x => x.level === 'red')) {
    return { key: 'red', title: 'Ação imediata ⚠️', sub: 'Tem coisa precisando de você agora — os motivos estão aqui embaixo.', grad: 'linear-gradient(135deg, #7F1D1D, #DC2626)' };
  }
  if (sigs.some(x => x.level === 'amber')) {
    return { key: 'amber', title: 'Atenção hoje 🟠', sub: 'Nada crítico, mas vale um olho antes de desligar.', grad: 'linear-gradient(135deg, #92400E, #F59E0B)' };
  }
  return { key: 'green', title: 'Tudo bem — pode viajar ✈️', sub: 'Metas no ritmo, ninguém esperando, nada travado. A operação está rodando.', grad: 'linear-gradient(135deg, #065F46, #10B981)' };
});

// linha de destaque abaixo dos tiles — muda com o painel
const panelHighlight = computed(() => {
  const d = pd.value;
  if (selectedPanel.value === 'conducao') {
    return {
      icon: 'i-lucide-clipboard-alert', color: '#D97706', value: d.unconfirmed ?? 0,
      label: 'Consultas sem conferência',
      sub: 'já passaram e ninguém marcou Compareceu/Faltou — confira na Agenda',
    };
  }
  if (selectedPanel.value === 'cirurgia') {
    return {
      icon: 'i-lucide-hourglass', color: '#BE185D', value: d.awaiting_closing ?? 0,
      label: 'Indicados aguardando fechamento',
      sub: `indicações do período ainda sem cirurgia marcada · ${d.upcoming_surgeries ?? 0} cirurgia(s) futura(s) na agenda`,
    };
  }
  if (selectedPanel.value === 'medico') {
    return {
      icon: 'i-lucide-slice', color: '#0369A1', value: d.surgeries ?? 0,
      label: 'Cirurgias no período',
      sub: d.doctor ? `realizadas/agendadas por ${d.doctor}` : 'todos os médicos',
    };
  }
  if (selectedPanel.value === 'gestor') {
    const nps = d.nps || {};
    return {
      icon: 'i-lucide-smile', color: '#0D9488',
      value: nps.satisfaction === null || nps.satisfaction === undefined ? '—' : `${nps.satisfaction}%`,
      label: 'Satisfação (NPS)',
      sub: nps.total
        ? `${nps.promoters} promotores (9-10) · ${nps.passives} notas 7-8 · ${nps.detractors} detratores (1-4)`
        : 'sem respostas ainda — ative o agente de NPS nas Automações',
    };
  }
  return {
    icon: 'i-lucide-stethoscope', color: '#EA580C', value: d.surgery_indications ?? 0,
    label: 'Indicações de cirurgia',
    sub: 'leads do período que chegaram à coluna "Indicação de Cirurgia"',
  };
});

// ── Saudação ────────────────────────────────────────────────
const firstName = computed(() => {
  const name = currentUser.value?.available_name || currentUser.value?.name || '';
  return name.split(' ')[0];
});
const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
});
const todayLabel = computed(() => {
  const label = new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' });
  return label.charAt(0).toUpperCase() + label.slice(1);
});

// ── Tarefas esperando VOCÊ (aviso dourado) ──────────────────
const myTasks = computed(() => data.value?.my_tasks?.items || []);
const myTasksCount = computed(() => data.value?.my_tasks?.count || 0);
const TASK_PRIORITY_LABEL = { low: 'baixa', medium: 'média', high: 'ALTA', urgent: 'URGENTE' };
const goToTasks = () =>
  router.push({ name: 'tasks_board', params: { accountId: accountId.value } });
// atalho pro Dashboard da Agenda em TODOS os painéis (item 86 — equipe vê)
const goToAgendaDashboard = () =>
  router.push({ name: 'agenda_dashboard_reports', params: { accountId: accountId.value } });
const fmtTaskDue = iso =>
  iso ? new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : null;

// ── Radar de Oportunidades ──────────────────────────────────
// pausa manual pela atendente (fica registrado quem desligou e quando)
const radarStatus = ref(null);
const togglingRadar = ref(false);
const loadRadarStatus = async () => {
  try {
    const { data: ping } = await CrmAPI.radarPing();
    radarStatus.value = ping.radar;
  } catch {
    radarStatus.value = null;
  }
};
const toggleRadarManual = async () => {
  const turningOff = radarStatus.value?.enabled;
  // eslint-disable-next-line no-alert
  if (turningOff && !window.confirm('Desativar o Radar de Oportunidades? Fica registrado que foi você.')) return;
  togglingRadar.value = true;
  try {
    const { data: res } = await CrmAPI.toggleRadar();
    radarStatus.value = res.radar;
  } finally {
    togglingRadar.value = false;
  }
};
const radarLastActionLabel = computed(() => {
  const a = radarStatus.value?.last_action;
  if (!a) return '';
  const when = new Date(a.at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
  return `${a.action} por ${a.user} às ${when}`;
});

const radarAlerts = computed(() => data.value?.opportunity_alerts?.alerts || []);

// ── Radar em CARROSSEL pulsante (item 63 — 19/07): um card por vez com
// tudo; os de trás só espiam (nome + tempo). "Atender agora" = 3 ✅
// pipocam do toque, -1 na contagem, o próximo assume — até zerar.
const radarQueue = ref([]);
watch(radarAlerts, list => { radarQueue.value = [...(list || [])]; }, { immediate: true });
const radarFront = computed(() => radarQueue.value[0] || null);
const radarPeek = computed(() => radarQueue.value.slice(1, 4));
const radarFx = ref(null);
// balão da conversa DIRETO do card (o mesmo do CRM): a atendente resolve
// dali mesmo, sem precisar ir até Conversas
const radarChat = ref(null);
const openChatBalloon = alert => {
  radarChat.value = {
    contact_id: alert.contact_id,
    name: alert.contact_name,
    phone_number: alert.phone,
    labels: [],
    last_conversation_id: alert.conversation_id,
    last_conversation: {
      inbox_id: alert.inbox_id,
      inbox_name: alert.inbox_name,
      channel_type: alert.channel_type,
      status: alert.conversation_status || 'open',
    },
  };
};
// mexeu na conversa pelo balão = aviso atendido: -1 na fila e registra no
// servidor (a eficácia do Radar continua contando normalmente)
const onRadarChatReplied = () => {
  const convId = radarChat.value?.last_conversation_id;
  if (!convId || !radarQueue.value.some(a => a.conversation_id === convId)) return;
  radarQueue.value = radarQueue.value.filter(a => a.conversation_id !== convId);
  CrmAPI.radarAttend(convId).catch(() => {});
};
const onRadarChatResolved = ({ status }) => {
  if (status === 'resolved') onRadarChatReplied();
};
const attendNow = (alert, event) => {
  if (radarFx.value && event) {
    radarFx.value.burstAt(event.clientX, event.clientY, ['✅'], 3);
  }
  radarQueue.value = radarQueue.value.filter(a => a !== alert);
  // persiste o -1 no servidor (vale p/ todos; se o paciente continuar sem
  // resposta, a próxima auditoria do Radar recoloca o aviso sozinha)
  CrmAPI.radarAttend(alert.conversation_id).catch(() => {});
  // pequena pausa para o prêmio ser sentido antes de abrir o balão
  setTimeout(() => openChatBalloon(alert), 320);
};
const rotateRadar = () => {
  if (radarQueue.value.length < 2) return;
  const [first, ...rest] = radarQueue.value;
  radarQueue.value = [...rest, first];
};
const radarLastRun = computed(() => {
  const iso = data.value?.opportunity_alerts?.last_run_at;
  return iso ? new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : null;
});
// item 83 — eficácia: consultas agendadas DEPOIS do aviso atendido (30d)
const radarEfficacy = computed(() => data.value?.opportunity_alerts?.efficacy || null);
const waitingLabel = alert => {
  if (!alert.waiting_since) return '';
  const min = Math.round((Date.now() - new Date(alert.waiting_since).getTime()) / 60000);
  if (min < 60) return `${min} min sem resposta`;
  return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')} sem resposta`;
};
// atalhos no formato do card do CRM (iniciais + Espaço do Paciente)
const alertInitials = alert =>
  (alert.contact_name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase();
const openPatientSpace = alert =>
  router.push(`/app/accounts/${accountId.value}/patient/${alert.contact_id}`);

// ── 🎯 Metas / Rotinas / Ferramentas (Painel de Metas alimenta) ──
const goalsData = ref(null);
const loadGoalsStrip = async () => {
  try {
    const { data: payload } = await CrmAPI.getGoalPlans();
    goalsData.value = payload;
  } catch {
    goalsData.value = null;
  }
};
const goalTargets = computed(() => goalsData.value?.plan?.targets || {});
const goalCurrent = computed(() => {
  const h = (goalsData.value?.history || []).find(x => x.month === goalsData.value?.month);
  return h?.values || {};
});
// só indicadores COM meta definida (até 3, os de maior alvo)
const goalRows = computed(() =>
  Object.entries(goalTargets.value)
    .filter(([, v]) => Number(v) > 0)
    .slice(0, 4)
    .map(([key, target]) => {
      const current = goalCurrent.value[key] || 0;
      return {
        key,
        label: goalsData.value?.indicators?.[key] || key,
        current,
        target: Number(target),
        pct: Math.min(100, Math.round((current / Number(target)) * 100)),
      };
    })
);
const teamRoutines = computed(() => goalsData.value?.routines || []);
const importantTools = computed(() => goalsData.value?.tools || []);
const goToGoals = () => router.push(`/app/accounts/${accountId.value}/goals`);
const goToTools = () => router.push(`/app/accounts/${accountId.value}/tools`);
const openTool = tool => tool.url && window.open(tool.url, '_blank', 'noopener');
// abre a gaveta global de feedback de bugs (BugReportDrawer no Dashboard.vue)
const reportBug = () => window.dispatchEvent(new CustomEvent('cevico:report-bug'));

// ── Mentor do Time: feedback semanal individual ──
// Cada pessoa vê o seu; admin navega pelo time (pílulas com os nomes).
const weeklyFeedback = computed(() => data.value?.weekly_feedback || null);
const myFeedback = computed(() => weeklyFeedback.value?.mine || null);
const teamFeedbacks = computed(() => weeklyFeedback.value?.team || []);
const feedbackViewUserId = ref(null);
const visibleFeedback = computed(() => {
  if (feedbackViewUserId.value) {
    return teamFeedbacks.value.find(f => f.user_id === feedbackViewUserId.value) || myFeedback.value;
  }
  return myFeedback.value || teamFeedbacks.value[0] || null;
});
const fbWeekLabel = fb => {
  if (!fb?.week_start) return '';
  const d = new Date(`${fb.week_start}T12:00:00`);
  const end = new Date(d);
  end.setDate(d.getDate() + 6);
  const f = x => x.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  return `semana de ${f(d)} a ${f(end)}`;
};

// Meta de tempo de atendimento: agora mora no Dashboard dos Agentes
// (Relatórios) — pedido 20/08. O widget do Construtor continua valendo.

// ── Indicadores do período ──────────────────────────────────
// ── Início do funil detalhado (item 138) ──
// card 1: total + quebra por caixa de captação
const shortInboxName = n =>
  (n || '').replace(/caixa/i, '').replace(/\(teste\)/i, '').trim().split(' ')[0] || n;
const leadsInboxSub = computed(() => {
  const list = data.value?.leads_by_inbox || [];
  if (!list.length) return 'caixas Google + Instagram';
  return list.map(i => `${shortInboxName(i.name)} ${i.count}`).join(' · ');
});
// conversão POR CAIXA: dos que chegaram por ela, % que avançou a Agendamento
const leadsInboxConversion = computed(() => {
  const list = (data.value?.leads_by_inbox || []).filter(i => i.count > 0);
  if (!list.length) return '';
  return `agendaram: ${list.map(i => `${shortInboxName(i.name)} ${i.rate}%`).join(' · ')}`;
});
// card 2: tempo de DECISÃO (dias entre chegar e agendar)
const decisionSub = computed(() => {
  const t = data.value?.decision_time;
  if (!t) return '';
  return `🤔 decisão média ${String(t.avg_days).replace('.', ',')}d · ${t.same_day} no dia · ${t.next_day} em 1d · ${t.within_week} em 2-7d · ${t.later} em 8d+`;
});
// card 3: o DIA julgado contra a fatia diária da meta oficial do mês
const cohortLine = (key, label) => {
  const c = data.value?.booking_cohorts?.[key];
  if (!c) return '';
  return `${label}: ${c.booked} de ${c.leads} agendaram (${c.rate}%)`;
};
const bookingDayVerdict = computed(() => {
  const booked = data.value?.booked_today ?? 0;
  const target = officialGoals.goalFor('appointments_booked')?.target || 0;
  if (!target)
    return { label: 'defina a meta no Painel de Metas', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' };
  const now = new Date();
  const daily = target / new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  const ratio = daily > 0 ? booked / daily : 1;
  if (ratio >= 1) return { label: 'Muito bom 🚀', grad: 'linear-gradient(135deg, #065F46, #10B981)' };
  if (ratio >= 0.6) return { label: 'Bom 👍', grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)' };
  if (ratio >= 0.3) return { label: 'Regular', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' };
  return { label: 'Fraco', grad: 'linear-gradient(135deg, #B91C1C, #EF4444)' };
});

// ── 🎯 Meu desempenho (item 138): a pessoa + o Atendimento IA ──
const perf = computed(() => data.value?.my_performance || null);
const perfCols = computed(() => {
  if (!perf.value) return [];
  const cols = [{ key: 'me', title: 'Você', row: perf.value.me }];
  if (perf.value.ai) cols.push({ key: 'ai', title: '🤖 Atendimento IA', row: perf.value.ai });
  return cols.filter(c => c.row);
});
const perfFmtMin = m => {
  if (m === null || m === undefined) return '—';
  if (m >= 60) return `${Math.floor(m / 60)}h${String(Math.round(m % 60)).padStart(2, '0')}`;
  return `${String(m).replace('.', ',')}min`;
};
const perfBrl = v =>
  (v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
// você × você: setinha vs o período anterior (invert = menor é melhor)
const perfDelta = (curr, prevVal, invert = false) => {
  if (prevVal === null || prevVal === undefined || curr === null || curr === undefined) return null;
  if (curr === prevVal) return null;
  const up = curr > prevVal;
  const good = invert ? !up : up;
  return { arrow: up ? '▲' : '▼', color: good ? '#059669' : '#DC2626', prev: prevVal };
};
// item 139: cada pessoa tem SUAS métricas (o admin propõe em Configurações
// → Painéis); row.metrics traz as chaves escolhidas (ou o padrão)
const perfTilesFor = col => {
  const r = col.row;
  const prev = col.key === 'me' ? perf.value?.previous || {} : {};
  const goal = perf.value?.goal_minutes || 15;
  const clinic = perf.value?.clinic || {};
  const mk = key => {
    switch (key) {
      case 'touched':
        return { key, display: r.conversations_touched ?? 0, label: 'conversas em que atuou', delta: perfDelta(r.conversations_touched, prev.conversations_touched) };
      case 'assigned':
        return { key, display: r.conversations_assigned ?? 0, label: 'conversas atribuídas' };
      case 'messages':
        return { key, display: r.messages_sent ?? 0, label: 'mensagens enviadas', delta: perfDelta(r.messages_sent, prev.messages_sent) };
      case 'reply_commercial': {
        const v = r.commercial?.avg_minutes ?? null;
        return { key, display: perfFmtMin(v), label: `resposta média (08–17h) · ${r.commercial?.within_rate ?? 0}% na meta`, color: v === null ? '' : v <= goal ? '#059669' : '#DC2626', delta: perfDelta(v, prev.avg_reply_min, true) };
      }
      case 'first_response':
        return { key, display: perfFmtMin(r.avg_first_response_min), label: '1ª resposta (média)' };
      case 'resolved':
        return { key, display: r.conversations_resolved ?? 0, label: 'resolvidas', delta: perfDelta(r.conversations_resolved, prev.conversations_resolved) };
      case 'appointments':
        return { key, display: r.appointments_created ?? 0, label: 'consultas agendadas', delta: perfDelta(r.appointments_created, prev.appointments_created) };
      case 'surgeries_created':
        return { key, display: r.surgeries_created ?? 0, label: 'cirurgias agendadas' };
      case 'surgeries_closed':
        return { key, display: r.surgeries?.count ?? 0, label: `cirurgias fechadas · ${perfBrl(r.surgeries?.revenue)}` };
      case 'attendance':
        return { key, display: `${clinic.rate ?? 0}%`, label: `comparecimento (clínica) · ${clinic.attended ?? 0} vieram · ${clinic.missed ?? 0} faltaram`, color: (clinic.rate ?? 0) >= 80 ? '#059669' : (clinic.rate ?? 0) >= 60 ? '#D4A017' : '#DC2626' };
      case 'days_worked':
        return { key, display: r.workday?.days_active ?? 0, label: 'dias trabalhados' };
      default:
        return null;
    }
  };
  return (r.metrics || []).map(mk).filter(Boolean);
};

// ── Saúde da agenda (janelas × consultas, calculada aqui) ───
const consultaTasks = computed(() =>
  allTasks.value.filter(t => (t.task_type === 'consulta' || t.unit) && t.due_at && !t.canceled_at)
);
const scan = opts =>
  scanAgenda({
    windows: resolveWindows(crmSettings.value),
    tasks: consultaTasks.value,
    blockedSet: new Set(resolveBlocked(crmSettings.value).map(b => blockKey(b.date, b.time, b.unit))),
    blockedDays: new Set(resolveBlockedDays(crmSettings.value)),
    ...opts,
  });

// ── Saúde da Agenda de CIRURGIAS (janelas da sala cirúrgica) ──
const surgeryTasks = computed(() =>
  allTasks.value.filter(t => t.task_type === 'cirurgia' && t.due_at && !t.canceled_at)
);
const scanSurgery = opts =>
  scanAgenda({
    windows: resolveSurgeryWindows(crmSettings.value),
    tasks: surgeryTasks.value,
    blockedSet: new Set(),
    blockedDays: new Set(resolveBlockedDays(crmSettings.value)),
    ...opts,
  });
const surgFillNext7 = computed(() => scanSurgery({ from: new Date(), days: 7, futureOnly: true }));
const surgUsageLast7 = computed(() => {
  const from = new Date();
  from.setDate(from.getDate() - 7);
  return scanSurgery({ from, days: 7, pastOnly: true });
});
// bloco de cirurgias SEMPRE lado a lado com o de consultas (pedido
// 2026-07-15) — meta do mês e próxima cirurgia valem mesmo sem janelas
// da sala configuradas (as barras mostram "—" até configurar)
const showSurgeryHealth = computed(() => true);

// 🎯 META DO MÊS: 100 cirurgias — barra de progresso no retângulo
const SURGERY_GOAL = 100;
const surgeriesDoneMonth = computed(() => {
  const now = new Date();
  return surgeryTasks.value.filter(t => {
    const d = new Date(t.due_at);
    return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() &&
      (t.attendance === 'attended' || t.status === 'done');
  }).length;
});
const goalPct = computed(() =>
  Math.min(Math.round((surgeriesDoneMonth.value / SURGERY_GOAL) * 100), 100)
);
const nextSurgery = computed(() =>
  surgeryTasks.value
    .filter(t => new Date(t.due_at) > new Date() && !t.attendance)
    .sort((a, b) => new Date(a.due_at) - new Date(b.due_at))[0] || null
);

const nextFreeSlots = computed(() =>
  scan({ from: new Date(), days: 14, freeLimit: 4, futureOnly: true }).freeSlots
);
const fillNext7 = computed(() => scan({ from: new Date(), days: 7, futureOnly: true }));
const usageLast7 = computed(() => {
  const from = new Date();
  from.setDate(from.getDate() - 7);
  return scan({ from, days: 7, pastOnly: true });
});
const attendance = computed(() => {
  const now = Date.now();
  const cutoff = now - 30 * 24 * 3600 * 1000;
  const past = consultaTasks.value.filter(t => {
    const d = new Date(t.due_at).getTime();
    return d < now && d > cutoff;
  });
  if (!past.length) return null;
  return Math.round((past.filter(t => t.status === 'done').length / past.length) * 100);
});
// % de agendamento 30d (consultas ÷ novos contatos) com referência fixa
const bookingRate30 = computed(() => {
  const contacts = data.value?.new_contacts_30d || 0;
  if (!contacts) return null;
  return Math.round(((data.value?.appointments_30d || 0) / contacts) * 1000) / 10;
});
const booking30Verdict = computed(() => {
  const r = bookingRate30.value;
  if (r === null) return null;
  if (r >= 15) return { label: 'Muito bom 🚀', color: '#10B981' };
  if (r >= 10) return { label: 'Bom 👍', color: '#3B82F6' };
  if (r >= 5) return { label: 'Regular', color: '#D4A017' };
  return { label: 'Fraco — hora de agir', color: '#EF4444' };
});

const slotLabel = f =>
  `${f.day.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })} ${f.slot}`;
const slotDoctorShort = f => DOCTORS.find(d => d.name === f.win.doctor)?.short || '';
const slotColor = f => DOCTORS.find(d => d.name === f.win.doctor)?.color || '#64748B';

const nextAppointment = computed(() => (data.value?.next_appointments || [])[0] || null);
const apptTime = iso =>
  new Date(iso).toLocaleString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

// ── Atalhos ─────────────────────────────────────────────────
const shortcuts = [
  { label: 'CRM', icon: 'i-lucide-rocket', route: 'crm_board', color: '#0F5FA6' },
  { label: 'Conversas', icon: 'i-lucide-message-circle', route: 'home', color: '#7C3AED' },
  { label: 'Agenda', icon: 'i-lucide-calendar-days', route: 'agenda_board', color: '#EA580C' },
  { label: 'Tarefas', icon: 'i-lucide-list-checks', route: 'tasks_board', color: '#D4A017' },
];
const go = route => router.push({ name: route, params: { accountId: accountId.value } });

// mantém o painel VIVO: atualiza sozinho a cada 2 min e sempre que a
// pessoa volta para a aba (sem precisar recarregar a página)
let refreshTimer = null;
const refreshAll = () => {
  store.dispatch('tasks/fetch').catch(() => {});
  fetchData();
};
const onVisible = () => {
  if (document.visibilityState === 'visible') refreshAll();
};

// ── ✓ dar CHECK num aviso: a janelinha some da tela e só volta quando
// houver NOVIDADE (a assinatura muda: outra semana de feedback, outros
// pacientes no Radar, outras tarefas). Por pessoa, neste aparelho. ──
const dismissStorageKey = computed(() => `cevico_avisos_checados_${currentUser.value?.id || 0}`);
const dismissedAvisos = ref({});
const loadDismissedAvisos = () => {
  try {
    dismissedAvisos.value = JSON.parse(localStorage.getItem(dismissStorageKey.value) || '{}');
  } catch {
    dismissedAvisos.value = {};
  }
};
const checkAviso = signature => {
  if (!signature) return;
  const entries = Object.entries({ ...dismissedAvisos.value, [signature]: Date.now() })
    .sort((a, b) => b[1] - a[1])
    .slice(0, 40); // guarda só os últimos, não cresce pra sempre
  dismissedAvisos.value = Object.fromEntries(entries);
  localStorage.setItem(dismissStorageKey.value, JSON.stringify(dismissedAvisos.value));
};
const avisoChecado = signature => Boolean(dismissedAvisos.value[signature]);
// assinaturas de conteúdo de cada janelinha
const fbSignature = computed(() =>
  visibleFeedback.value ? `fb:${myFeedback.value?.week_start || visibleFeedback.value.week_start}` : ''
);
// item 88 v2 (pedido 20/07): números de WhatsApp MINI e discreto no
// painel do gestor, mostrando o STATUS DA CONTA na Meta (qualidade +
// limite de envio), não um "funcionando" genérico
const whatsappStatus = computed(() => data.value?.whatsapp_status || null);
const waProblem = computed(() =>
  (whatsappStatus.value || []).some(
    w => w.reauthorization_required || ['RED', 'FLAGGED'].includes(w.quality) || w.name_status === 'DECLINED'
  )
);
const WA_QUALITY = {
  GREEN: { dot: '#10B981', label: 'conta saudável' },
  YELLOW: { dot: '#F59E0B', label: 'qualidade em atenção' },
  RED: { dot: '#EF4444', label: 'qualidade baixa — risco de restrição' },
  FLAGGED: { dot: '#EF4444', label: 'conta sinalizada pela Meta' },
};
const waQuality = w =>
  WA_QUALITY[(w.quality || '').toUpperCase()] || { dot: '#94A3B8', label: 'status indisponível' };
const WA_TIERS = {
  TIER_50: '50/dia', TIER_250: '250/dia', TIER_1K: '1 mil/dia',
  TIER_10K: '10 mil/dia', TIER_100K: '100 mil/dia', TIER_UNLIMITED: 'sem limite',
};
const waTier = tier => WA_TIERS[tier] || null;

// ── 📊 Briefing do Gestor Autônomo (só admin — null para o time) ──
// O agente lê o funil todo dia contra a média de 12 semanas e deixa aqui
// o resumo do dia + os desvios encontrados (chips) + as tarefas abertas.
const managerBrief = computed(() => data.value?.manager_brief || null);
// até 4 frases — briefing é café, não relatório
const managerBriefText = computed(() => {
  const text = (managerBrief.value?.brief || '').trim();
  if (!text) return '';
  const sentences = text.match(/[^.!?]+[.!?]*/g) || [text];
  return sentences.slice(0, 4).join('').trim();
});
const managerFindings = computed(() => managerBrief.value?.findings || []);
// chip do desvio: "Taxa de comparecimento −38%"
const managerFindingLabel = f =>
  `${f.label || f.indicator} ${Number(f.deviation_pct) < 0 ? '−' : '+'}${Math.abs(Math.round(f.deviation_pct || 0))}%`;
const managerLastRunTime = computed(() => {
  const iso = managerBrief.value?.last_run_at;
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
});

const radarSignature = computed(
  () => `radar:${radarAlerts.value.map(a => a.conversation_id).sort((a, b) => a - b).join(',')}`
);
const tasksSignature = computed(
  () => `tasks:${myTasks.value.map(t => t.id).sort((a, b) => a - b).join(',')}`
);

onMounted(() => {
  loadDismissedAvisos();
  store.dispatch('crm/fetchSettings').catch(() => {});
  loadRadarStatus();
  loadGoalsStrip();
  refreshAll();
  refreshTimer = setInterval(refreshAll, 120000);
  document.addEventListener('visibilitychange', onVisible);
});

onUnmounted(() => {
  clearInterval(refreshTimer);
  document.removeEventListener('visibilitychange', onVisible);
});
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto p-4 sm:p-8">
      <!-- Boas-vindas -->
      <div
        class="rounded-3xl p-6 sm:p-9 text-white shadow-lg mb-6 relative overflow-hidden transition-all"
        :style="{ background: currentPanel.grad }"
      >
        <div class="relative z-10" style="color: #fff">
          <div class="flex items-start justify-between gap-2 mb-1">
            <p class="text-sm font-medium" style="color: rgba(255,255,255,0.75)">{{ todayLabel }}</p>
            <!-- 🐞 Reportar problema — padrão no painel de TODOS (pedido 17/07) -->
            <button
              class="flex items-center gap-1.5 px-2.5 h-7 rounded-lg text-[11px] font-semibold transition-colors flex-shrink-0"
              style="background: rgba(255,255,255,0.14); color: #fff; border: 1px solid rgba(255,255,255,0.25)"
              title="Algo não funcionou? Vira um card no board do Guilherme e você recebe o aviso quando resolver."
              @click="reportBug"
            >
              <span class="i-lucide-bug text-xs" />
              Reportar problema
            </button>
          </div>
          <h1 class="text-2xl sm:text-4xl font-bold leading-tight" style="color: #fff">{{ greeting }}, {{ firstName }}! 👋</h1>
          <p class="text-sm mt-2" style="color: rgba(255,255,255,0.85)">
            Boas-vindas ao CEVICO S.I —
            <b>Painel de {{ currentPanel.label }}</b><template v-if="currentPanel.who"> ({{ currentPanel.who }})</template>: {{ currentPanel.desc }}.
          </p>
        </div>
        <span class="i-lucide-eye absolute -right-6 -bottom-8 text-[160px] text-white/10" />
      </div>

      <!-- SKELETON Homem de Ferro (item 89): o painel se monta por partes -->
      <div v-if="isLoading" class="space-y-6">
        <SkeletonPiece variant="block" class="h-28" :order="0" />
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <SkeletonPiece variant="block" class="h-36" :order="1" />
          <SkeletonPiece variant="block" class="h-36" :order="2" />
          <SkeletonPiece variant="block" class="h-36" :order="3" />
        </div>
        <div class="flex items-center gap-2 flex-wrap">
          <SkeletonPiece v-for="i in 5" :key="`pp${i}`" variant="pill" :order="3 + i" />
        </div>
        <div class="flex items-center gap-2 flex-wrap">
          <SkeletonPiece v-for="i in 6" :key="`per${i}`" variant="pill" class="!h-7 !w-20" :order="8 + i" />
        </div>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <SkeletonPiece v-for="i in 4" :key="`t${i}`" variant="tile" class="!h-36" :order="14 + i" />
        </div>
        <SkeletonPiece variant="block" class="h-64" :order="19" />
      </div>

      <template v-else>
        <!-- 🎉 Seus reports de bug resolvidos (notificação p/ quem reportou) -->
        <div
          v-if="data?.bug_reports?.resolved?.length"
          class="rounded-2xl border-2 border-green-500/40 bg-green-500/5 overflow-hidden mb-6"
        >
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #059669, #34D399)" />
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-2 mb-2">
              <span class="text-xl">🎉</span>
              <h2 class="text-sm font-bold text-n-slate-12">
                {{ data.bug_reports.resolved.length === 1
                  ? 'Um problema que você reportou foi resolvido!'
                  : `${data.bug_reports.resolved.length} problemas que você reportou foram resolvidos!` }}
              </h2>
            </div>
            <div class="space-y-1.5">
              <p
                v-for="r in data.bug_reports.resolved"
                :key="r.id"
                class="text-xs text-n-slate-11 bg-n-solid-1 border border-green-500/25 rounded-lg px-3 py-2"
              >
                ✅ {{ r.title }}
                <span class="text-n-slate-9">— resolvido {{ new Date(r.completed_at).toLocaleDateString('pt-BR') }}. Obrigado por avisar! 💙</span>
              </p>
            </div>
          </div>
        </div>

        <!-- 💬 Números de WhatsApp (item 88 v2 — pedido 20/07): faixa MINI
             e discreta com o STATUS DA CONTA na Meta; fica vermelha só
             quando existe problema de verdade -->
        <div
          v-if="whatsappStatus"
          class="flex items-center gap-x-3 gap-y-1 flex-wrap mb-6 px-3 py-1.5 rounded-xl border text-[11px]"
          :class="waProblem ? 'border-red-500/40 bg-red-500/5' : 'border-n-weak bg-n-solid-2'"
          title="Status das contas de WhatsApp na Meta (atualiza a cada 10 min) — detalhes em Relatórios → Saúde do WhatsApp"
        >
          <span class="i-lucide-phone text-xs flex-shrink-0" :class="waProblem ? 'text-red-500' : 'text-n-slate-9'" />
          <span
            v-for="w in whatsappStatus"
            :key="w.id"
            class="inline-flex items-center gap-1.5 text-n-slate-11 min-w-0"
          >
            <span
              class="w-2 h-2 rounded-full flex-shrink-0"
              :style="{ background: w.reauthorization_required ? '#EF4444' : waQuality(w).dot }"
            />
            <b class="text-n-slate-12 truncate">{{ w.verified_name || w.name }}</b>
            <span v-if="w.reauthorization_required" class="text-red-500 font-bold whitespace-nowrap">precisa reautorizar</span>
            <template v-else>
              <span class="text-n-slate-9 whitespace-nowrap">{{ waQuality(w).label }}</span>
              <span v-if="waTier(w.limit_tier)" class="text-n-slate-9 whitespace-nowrap">· limite {{ waTier(w.limit_tier) }}</span>
              <span v-if="w.failed_24h" class="text-amber-600 whitespace-nowrap">· {{ w.failed_24h }} falha(s) 24h</span>
            </template>
          </span>
        </div>

        <!-- 📊 Briefing do Gestor Autônomo (só admin): o resumo do dia +
             os desvios do funil vs a média de 12 semanas. Sem briefing
             escrito, o card fica discreto e mostra só os desvios. -->
        <div
          v-if="managerBrief && (managerBriefText || managerFindings.length)"
          class="rounded-xl border border-n-weak bg-n-solid-2 overflow-hidden mb-6"
        >
          <div class="h-1 w-full" style="background: linear-gradient(90deg, #0F5FA6, #3B82F6)" />
          <div class="p-4">
            <div class="flex items-center gap-2 mb-2 flex-wrap">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #0F5FA6, #3B82F6)">
                <span class="i-lucide-gauge text-white text-sm" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">📊 Briefing do Gestor</h2>
              <span class="text-[11px] text-n-slate-9 ml-auto">funil de hoje vs a média de 12 semanas</span>
            </div>

            <p v-if="managerBriefText" class="text-sm text-n-slate-11 leading-relaxed mb-2">
              {{ managerBriefText }}
            </p>

            <div v-if="managerFindings.length" class="flex flex-wrap gap-1.5 mb-2">
              <span
                v-for="(f, fi) in managerFindings"
                :key="fi"
                class="text-[11px] font-medium px-2 py-0.5 rounded-full bg-red-500/10 text-red-600 dark:text-red-400 border border-red-500/25"
                :title="f.window ? `janela: ${f.window}` : ''"
              >
                {{ managerFindingLabel(f) }}
              </span>
            </div>

            <p class="text-[11px] text-n-slate-9">
              abriu {{ managerBrief.tasks_opened || 0 }} tarefa(s) hoje<template v-if="managerLastRunTime"> · {{ managerLastRunTime }}</template>
            </p>
          </div>
        </div>

        <!-- 💚 Avisos do Radar de Oportunidades — cartão BRANCO (contraste
             nos dois temas) + verde dopamine + botão que emana energia
             (pedido 17/07: convite, não bronca) -->
        <div
          v-if="radarQueue.length && !avisoChecado(radarSignature)"
          class="rounded-2xl overflow-hidden mb-6 bg-white shadow-lg"
          style="border: 2px solid rgba(16, 185, 129, 0.35)"
        >
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #059669, #4ADE80)" />
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-2 mb-3 flex-wrap">
              <span class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #059669, #4ADE80)">
                <span class="i-lucide-radar text-white text-base" />
              </span>
              <h2 class="text-sm font-bold" style="color: #0f172a">
                {{ radarQueue.length === 1
                  ? '1 paciente quente sem atendimento'
                  : `${radarQueue.length} pacientes quentes sem atendimento` }}
              </h2>
              <!-- 📈 eficácia (item 83): o Radar gerando consulta de verdade -->
              <span
                v-if="radarEfficacy"
                class="text-[10px] font-bold px-2 py-0.5 rounded-full"
                style="background: rgba(16, 185, 129, 0.12); color: #047857; border: 1px solid rgba(16, 185, 129, 0.3)"
                :title="`Dos ${radarEfficacy.attended_30d} avisos atendidos nos últimos 30 dias, ${radarEfficacy.converted_30d} paciente(s) agendaram consulta depois do aviso`"
              >
                📈 {{ radarEfficacy.converted_30d }} consulta(s) geradas · {{ radarEfficacy.rate }}%
              </span>
              <span v-if="radarLastRun" class="text-[11px] ml-auto" style="color: #94a3b8">auditoria às {{ radarLastRun }}</span>
              <button
                v-if="radarStatus && isAdmin"
                class="text-[11px] font-medium px-2.5 py-1 rounded-lg border disabled:opacity-50"
                style="border-color: #e2e8f0; color: #64748b"
                :title="radarLastActionLabel"
                :disabled="togglingRadar"
                @click="toggleRadarManual"
              >
                {{ radarStatus.enabled ? '⏸ Pausar radar' : '▶️ Reativar radar' }}
              </button>
              <button
                class="w-7 h-7 rounded-lg border flex items-center justify-center transition-colors flex-shrink-0"
                style="border-color: #e2e8f0; color: #059669"
                title="Dar check: esconder este aviso (volta quando o Radar tiver novidade)"
                @click="checkAviso(radarSignature)"
              >
                <span class="i-lucide-check text-sm" />
              </button>
            </div>
            <!-- CARROSSEL pulsante (item 63): a pilha espia atrás (nome +
                 tempo) e o card da frente mostra tudo — CRM, etiquetas,
                 contexto e o botão convidativo -->
            <div class="relative max-w-2xl mx-auto" :style="{ paddingTop: `${radarPeek.length * 14 + 2}px` }">
              <!-- pilha de trás -->
              <div
                v-for="(p, i) in radarPeek"
                :key="`peek-${p.conversation_id}`"
                class="absolute left-1/2 -translate-x-1/2 rounded-xl border flex items-center gap-2 px-3 h-8 cursor-pointer"
                :style="{
                  top: `${(radarPeek.length - 1 - i) * 14}px`,
                  width: `calc(100% - ${(i + 1) * 36}px)`,
                  zIndex: 3 - i,
                  background: '#fbfdfc',
                  borderColor: '#dbe7e1',
                  opacity: String(0.85 - i * 0.18),
                }"
                :title="`Trazer ${p.contact_name} para a frente`"
                @click="rotateRadar"
              >
                <span class="text-[11px] font-semibold truncate" style="color: #334155">{{ p.contact_name }}</span>
                <span class="text-[10px] ml-auto flex-shrink-0" style="color: #047857">{{ waitingLabel(p) }}</span>
              </div>

              <!-- card da FRENTE (pulsa como Tarefas 100%) -->
              <div
                v-if="radarFront"
                :key="`front-${radarFront.conversation_id}`"
                class="cevico-radar-front relative z-10 rounded-xl p-3 cursor-pointer flex flex-col gap-2 bg-white"
                @click="openChatBalloon(radarFront)"
              >
                <div class="flex items-center gap-2">
                  <div
                    class="w-7 h-7 rounded-full flex items-center justify-center text-white text-[10px] font-semibold flex-shrink-0"
                    style="background: linear-gradient(135deg, #059669, #4ADE80)"
                  >
                    {{ alertInitials(radarFront) }}
                  </div>
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-semibold truncate leading-tight" style="color: #0f172a">{{ radarFront.contact_name }}</p>
                    <p v-if="radarFront.phone" class="text-xs truncate" style="color: #64748b">{{ radarFront.phone }}</p>
                  </div>
                  <span
                    class="inline-flex items-center gap-1 text-[11px] font-semibold rounded-full px-2 py-0.5 flex-shrink-0"
                    style="background: rgba(16, 185, 129, 0.12); color: #047857; border: 1px solid rgba(16, 185, 129, 0.3)"
                  >
                    <span class="i-lucide-clock text-[11px]" />
                    {{ waitingLabel(radarFront) }}
                  </span>
                </div>
                <div v-if="radarFront.stage_name || radarFront.user_name" class="flex flex-wrap gap-1">
                  <span v-if="radarFront.stage_name" class="inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded" style="background: #eef2f7; color: #475569">
                    <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" style="background: #059669" />
                    {{ radarFront.stage_name }}
                  </span>
                  <span v-if="radarFront.user_name" class="text-xs px-1.5 py-0.5 rounded font-medium" style="background: rgba(212, 160, 23, 0.14); color: #92600a">📌 para {{ radarFront.user_name }}</span>
                </div>
                <div class="rounded-r-lg px-2 py-1.5" style="background: #f8fafc; border-left: 2px solid #10b981">
                  <p class="text-xs leading-snug" style="color: #475569">{{ radarFront.motivo }}</p>
                </div>
                <p class="text-xs" style="color: #475569">💡 <b style="color: #0f172a">O que fazer:</b> {{ radarFront.acao }}</p>
                <div class="flex items-center justify-between gap-1 mt-auto">
                  <div class="flex items-center gap-1">
                    <button
                      v-if="radarFront.contact_id"
                      class="flex items-center justify-center w-8 h-8 rounded-lg transition-transform hover:scale-110"
                      title="Espaço do Paciente"
                      @click.stop="openPatientSpace(radarFront)"
                    >
                      <PatientSpaceIcon :size="24" />
                    </button>
                    <button
                      class="flex items-center justify-center w-8 h-8 rounded-lg transition-transform hover:scale-110"
                      style="color: #2563EB; background: rgba(37, 99, 235, 0.1)"
                      title="Abrir conversa"
                      @click.stop="openChatBalloon(radarFront)"
                    >
                      <span class="i-lucide-message-circle-more text-lg" />
                    </button>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <button
                      v-if="radarQueue.length > 1"
                      class="text-[11px] font-medium px-2 py-1.5 rounded-lg border transition-colors"
                      style="border-color: #e2e8f0; color: #64748b"
                      title="Deixar para depois — vai para o fim da fila"
                      @click.stop="rotateRadar"
                    >
                      pular ↷
                    </button>
                    <button
                      class="cevico-energy-btn text-xs font-bold text-white px-3.5 py-1.5 rounded-lg"
                      @click.stop="attendNow(radarFront, $event)"
                    >
                      Atender agora →
                    </button>
                  </div>
                </div>
              </div>

              <p v-if="radarQueue.length > 4" class="text-center text-[11px] mt-1.5" style="color: #94a3b8">
                +{{ radarQueue.length - 4 }} na fila
              </p>
            </div>
          </div>
        </div>

        <!-- 📋 Tarefas esperando você (aviso DOURADO — coisa boa a fazer) -->
        <div
          v-if="myTasks.length && !avisoChecado(tasksSignature)"
          class="rounded-2xl border-2 overflow-hidden mb-6"
          style="border-color: rgba(212, 160, 23, 0.5); background: rgba(212, 160, 23, 0.05)"
        >
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #B8860B, #D4A017)" />
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-2 mb-3 flex-wrap">
              <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
                <span class="i-lucide-list-checks text-white text-base" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">
                {{ myTasksCount }} tarefa(s) esperando você
              </h2>
              <button
                class="ml-auto text-xs font-semibold text-white px-3 py-1.5 rounded-lg hover:opacity-90"
                style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                @click="goToTasks"
              >
                Abrir Tarefas →
              </button>
              <button
                class="w-7 h-7 rounded-lg border border-n-weak flex items-center justify-center transition-colors flex-shrink-0"
                style="color: #B8860B"
                title="Dar check: esconder este aviso (volta quando houver tarefa nova)"
                @click="checkAviso(tasksSignature)"
              >
                <span class="i-lucide-check text-sm" />
              </button>
            </div>
            <div class="space-y-1.5">
              <button
                v-for="task in myTasks"
                :key="task.id"
                class="w-full flex items-center gap-2 flex-wrap bg-n-solid-1 border rounded-xl px-3 py-2 text-left hover:shadow-sm transition-shadow"
                style="border-color: rgba(212, 160, 23, 0.3)"
                @click="goToTasks"
              >
                <span class="i-lucide-circle-dot text-sm" style="color: #B8860B" />
                <span class="text-sm font-medium text-n-slate-12 truncate">{{ task.title }}</span>
                <span
                  class="text-[10px] px-2 py-0.5 rounded-full font-semibold"
                  :class="['high', 'urgent'].includes(task.priority) ? 'bg-red-500/15 text-red-600' : 'bg-n-alpha-2 text-n-slate-11'"
                >
                  {{ TASK_PRIORITY_LABEL[task.priority] || task.priority }}
                </span>
                <span v-if="task.creator_name" class="text-[10px] text-n-slate-9">de {{ task.creator_name.split(' ')[0] }}</span>
                <span v-if="task.comments_count" class="text-[10px] text-n-slate-9">💬 {{ task.comments_count }}</span>
                <span v-if="task.due_at" class="text-[10px] text-n-slate-10 ml-auto">⏰ {{ fmtTaskDue(task.due_at) }}</span>
              </button>
            </div>
          </div>
        </div>

        <!-- 🧭 Mentor do Time: feedback da semana (individual; admin vê o time) -->
        <div
          v-if="visibleFeedback && !avisoChecado(fbSignature)"
          class="rounded-2xl overflow-hidden mb-6 bg-n-card outline outline-1 outline-n-container"
        >
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #C2410C, #FB923C)" />
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-2 mb-3 flex-wrap">
              <span class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #C2410C, #FB923C)">
                <span class="i-lucide-graduation-cap text-white text-base" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">
                {{ visibleFeedback.user_id === currentUser.id ? 'Seu feedback da semana' : `Feedback de ${visibleFeedback.user_name}` }}
              </h2>
              <span class="text-[11px] text-n-slate-9 ml-auto">{{ fbWeekLabel(visibleFeedback) }}</span>
              <button
                class="w-7 h-7 rounded-lg border border-n-weak flex items-center justify-center transition-colors flex-shrink-0"
                style="color: #C2410C"
                title="Dar check: li meu feedback, pode esconder (volta na próxima semana)"
                @click="checkAviso(fbSignature)"
              >
                <span class="i-lucide-check text-sm" />
              </button>
            </div>

            <!-- admin: navega pelo time -->
            <div v-if="isAdmin && teamFeedbacks.length > 1" class="flex items-center gap-1 flex-wrap mb-3">
              <button
                v-for="fb in teamFeedbacks"
                :key="fb.user_id"
                class="text-[11px] font-medium px-2.5 py-1 rounded-full transition-colors"
                :class="visibleFeedback.user_id === fb.user_id ? 'text-white' : 'text-n-slate-10 bg-n-alpha-1 hover:bg-n-alpha-2'"
                :style="visibleFeedback.user_id === fb.user_id ? { background: 'linear-gradient(135deg, #C2410C, #FB923C)' } : {}"
                @click="feedbackViewUserId = fb.user_id"
              >
                {{ fb.user_name.split(' ')[0] }}
              </button>
            </div>

            <p class="text-sm text-n-slate-11 leading-relaxed mb-3">{{ visibleFeedback.feedback.resumo }}</p>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5 mb-3">
              <div class="rounded-xl p-3" style="background: rgba(16, 185, 129, 0.08); border: 1px solid rgba(16, 185, 129, 0.25)">
                <p class="text-[10px] font-bold uppercase tracking-wide mb-1" style="color: #047857">Ponto forte</p>
                <p class="text-xs text-n-slate-11 leading-snug">{{ visibleFeedback.feedback.ponto_forte }}</p>
              </div>
              <div class="rounded-xl p-3" style="background: rgba(245, 158, 11, 0.08); border: 1px solid rgba(245, 158, 11, 0.3)">
                <p class="text-[10px] font-bold uppercase tracking-wide mb-1" style="color: #B45309">O ponto a corrigir</p>
                <p class="text-xs text-n-slate-11 leading-snug">{{ visibleFeedback.feedback.ponto_fraco }}</p>
              </div>
            </div>

            <div v-if="visibleFeedback.feedback.solucoes?.length" class="space-y-1.5 mb-3">
              <p class="text-[10px] font-bold uppercase tracking-wide text-n-slate-9">Soluções simples desta semana</p>
              <div
                v-for="(sol, si) in visibleFeedback.feedback.solucoes"
                :key="si"
                class="flex items-start gap-2 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2"
              >
                <span
                  class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold text-white flex-shrink-0 mt-0.5"
                  style="background: linear-gradient(135deg, #C2410C, #FB923C)"
                >
                  {{ si + 1 }}
                </span>
                <div class="min-w-0">
                  <p class="text-xs font-semibold text-n-slate-12">{{ sol.titulo }}</p>
                  <p class="text-xs text-n-slate-10 leading-snug">{{ sol.como_fazer }}</p>
                </div>
              </div>
            </div>

            <p v-if="visibleFeedback.feedback.incentivo" class="text-xs italic" style="color: #9A3412">
              {{ visibleFeedback.feedback.incentivo }}
            </p>
          </div>
        </div>


        <!-- Seletor de painel (cada pessoa no seu) -->
        <div class="flex items-center gap-2 flex-wrap mb-3">
          <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto">
            <button
              v-for="p in visiblePanels"
              :key="p.key"
              class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex items-center gap-1.5"
              :class="selectedPanel === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="selectedPanel === p.key ? { background: p.grad } : {}"
              @click="setPanel(p.key)"
            >
              <span :class="p.icon" class="text-sm" />
              {{ p.label }}<template v-if="p.who"> · {{ p.who }}</template>
            </button>
            <button
              v-if="isAdmin"
              class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 flex items-center justify-center"
              title="Definir qual painel cada pessoa vê"
              @click="openAssignModal"
            >
              <span class="i-lucide-settings-2 text-sm" />
            </button>
            <button
              v-if="isAdmin"
              class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1 flex items-center justify-center"
              title="Metas do painel (os cards mudam de cor contra a meta)"
              @click="openGoalsModal"
            >
              <span class="i-lucide-target text-sm" />
            </button>
            <!-- atalho pro Dashboard da Agenda em TODOS os painéis (item 86) -->
            <button
              class="h-8 px-3 rounded-lg text-xs font-semibold text-white flex items-center gap-1.5 hover:opacity-90 whitespace-nowrap"
              style="background: linear-gradient(135deg, #0369A1, #38BDF8)"
              title="Dashboard da Agenda — comparecimento, ocupação, cirurgias"
              @click="goToAgendaDashboard"
            >
              <span class="i-lucide-calendar-range text-sm" />
              Dashboard da Agenda
            </button>
          </div>
          <!-- pílulas de médico (só no painel Médicos) -->
          <div v-if="selectedPanel === 'medico'" class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto">
            <button
              class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
              :class="!selectedDoctor ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="!selectedDoctor ? { background: currentPanel.grad } : {}"
              @click="setDoctor('')"
            >
              Todos
            </button>
            <button
              v-for="doc in DOCTORS"
              :key="doc.name"
              class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
              :class="selectedDoctor === doc.name ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="selectedDoctor === doc.name ? { background: doc.color } : {}"
              @click="setDoctor(doc.name)"
            >
              {{ doc.short || doc.name }}
            </button>
          </div>
        </div>

        <!-- Régua de período PADRÃO (presets + Personalizado De/Até) -->
        <div class="mb-4 max-w-full">
          <PeriodRuler v-model="period" class="max-w-full" />
        </div>

        <!-- ✈️ GESTOR: o indicador de decisão — posso viajar ou é ação imediata? -->
        <div
          v-if="selectedPanel === 'gestor' && data"
          class="rounded-2xl text-white shadow-lg overflow-hidden mb-4"
          :style="{ background: gestorVerdict.grad }"
        >
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-3 flex-wrap">
              <div class="flex-1 min-w-[220px]">
                <p class="text-lg font-bold">{{ gestorVerdict.title }}</p>
                <p class="text-xs text-white/80 mt-0.5">{{ gestorVerdict.sub }}</p>
              </div>
              <span class="text-[10px] px-2.5 py-1 rounded-full bg-white/20 font-semibold">
                {{ gestorSignals.length ? `${gestorSignals.length} aviso(s)` : 'nenhum aviso' }}
              </span>
            </div>
            <!-- central de avisos: os motivos, prontos para agir -->
            <div v-if="gestorSignals.length" class="mt-3 space-y-1.5">
              <div
                v-for="(sig, si) in gestorSignals"
                :key="si"
                class="flex items-center gap-2 bg-black/15 rounded-lg px-3 py-1.5 text-xs"
              >
                <span :class="sig.icon" class="text-sm shrink-0" />
                <span class="flex-1">{{ sig.text }}</span>
                <span
                  class="w-2 h-2 rounded-full shrink-0"
                  :style="{ background: sig.level === 'red' ? '#FCA5A5' : sig.level === 'amber' ? '#FDE68A' : '#BAE6FD' }"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Painel do CONSTRUTOR (custom:<id>): a grade montada pelo gestor
             substitui as tiles fixas; o resto da página continua igual -->
        <CustomPanelGrid
          v-if="currentPanel.custom"
          :widgets="currentPanel.panelDef.widgets"
          :palette="currentPanel.panelDef.palette"
          :home="data"
          :goals="goalsData"
          class="mb-6"
        />

        <template v-else>
        <!-- Indicadores do período — mudam com o painel escolhido -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div
            v-for="tile in panelTiles"
            :key="tile.label"
            class="relative rounded-2xl p-4 sm:p-5 text-white shadow-lg transition-all duration-700"
            :class="[
              tileVisual(tile).pulse ? 'cevico-meta-pulse' : '',
              tileVisual(tile).isRecord ? 'ring-2 ring-amber-300/80' : '',
            ]"
            :style="{ background: tileVisual(tile).grad }"
          >
            <!-- 🏆 recorde: átomos orbitando o card em sentido horário -->
            <TileAura
              v-if="tileVisual(tile).aura"
              :intensity="tileVisual(tile).auraIntensity"
              gold
            />
            <div class="relative">
              <div class="flex items-center gap-1.5 mb-1 text-white/80">
                <span :class="tile.icon" class="text-sm" />
                <p class="text-xs font-medium flex-1 truncate">{{ tile.label }}</p>
                <span v-if="tileVisual(tile).isRecord" class="text-[9px] font-black px-1.5 py-0.5 rounded-full bg-amber-300 text-amber-900" title="Melhor resultado já registrado neste tipo de período">🏆 RECORDE</span>
                <span v-else-if="tileVisual(tile).status === 'meta'" class="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-white/25" title="Meta batida">✓ META</span>
                <span v-else-if="tileVisual(tile).status === 'bad'" class="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-black/25" title="Muito abaixo do ritmo da meta">⚠️</span>
              </div>
              <p class="text-3xl font-bold">{{ tile.value }}</p>
              <span v-if="tile.chip" class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-white/20">{{ tile.chip.label }}</span>
              <template v-if="tile.sub">
                <!-- linhas curtas propositais: nada de frase quebrando no meio -->
                <p class="text-[10px] text-white/70 truncate">{{ tile.sub }}</p>
                <p v-if="tile.sub2" class="text-[10px] text-white/80 truncate">{{ tile.sub2 }}</p>
                <p v-if="tile.sub3" class="text-[10px] text-white/80 truncate">{{ tile.sub3 }}</p>
              </template>
              <!-- medidor da meta (aparece quando o admin definiu meta) -->
              <div v-if="tileVisual(tile).ratio !== null" class="mt-2">
                <div class="h-1.5 rounded-full bg-black/20 overflow-hidden">
                  <div
                    class="h-full rounded-full bg-white/85 transition-all duration-700"
                    :style="{ width: Math.min(100, Math.round(tileVisual(tile).ratio * 100)) + '%' }"
                  />
                </div>
                <p class="text-[9px] text-white/70 mt-0.5">
                  {{ Math.round(tileVisual(tile).ratio * 100) }}% do ritmo da meta
                  <template v-if="!tile.pct"> · esperado {{ Math.ceil(tileVisual(tile).expected) }}</template>
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Linha de destaque do painel -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl px-4 py-3 mb-6 flex items-center gap-3">
          <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" :style="{ background: panelHighlight.color + '1F' }">
            <span :class="panelHighlight.icon" class="text-lg" :style="{ color: panelHighlight.color }" />
          </span>
          <div class="flex-1">
            <p class="text-xs font-medium text-n-slate-11">{{ panelHighlight.label }}</p>
            <p class="text-[10px] text-n-slate-9">{{ panelHighlight.sub }}</p>
          </div>
          <p class="text-2xl font-bold text-n-slate-12">{{ panelHighlight.value }}</p>
        </div>
        </template>

        <!-- 🎯 MEU DESEMPENHO (item 138): auto-avaliação — a pessoa e o
             Atendimento IA como referência; sem ranking de colegas (o
             ranking do time vive no Dashboard dos Agentes, do gestor) -->
        <div v-if="perfCols.length" class="bg-n-card outline outline-1 outline-n-container rounded-2xl p-5 sm:p-6 mb-6">
          <div class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-target text-white text-base" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">Meu desempenho</h2>
            <span class="text-[10px] px-2 py-0.5 rounded-full bg-n-alpha-1 text-n-slate-11">velocidades no horário comercial · 08h–17h</span>
            <span v-if="perf?.previous?.label" class="text-[10px] text-n-slate-9 ml-auto">setinhas comparam com {{ perf.previous.label }}</span>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <div
              v-for="col in perfCols"
              :key="col.key"
              class="rounded-2xl border p-4"
              :class="col.key === 'me' ? 'border-violet-400/40 bg-n-solid-1' : 'border-n-weak bg-n-alpha-1'"
            >
              <div class="flex items-center gap-2 mb-3">
                <p class="text-sm font-bold text-n-slate-12 flex-1">{{ col.title }}</p>
                <span class="text-[10px] text-n-slate-10">{{ col.row.messages_sent }} mensagens</span>
              </div>

              <div class="grid grid-cols-2 sm:grid-cols-3 gap-2 text-center">
                <div v-for="t in perfTilesFor(col)" :key="t.key" class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :class="t.color ? '' : 'text-n-slate-12'" :style="t.color ? { color: t.color } : {}">
                    {{ t.display }}
                    <span v-if="t.delta" class="text-[10px] font-bold" :title="'antes: ' + t.delta.prev" :style="{ color: t.delta.color }">{{ t.delta.arrow }}</span>
                  </p>
                  <p class="text-[10px] text-n-slate-10">{{ t.label }}</p>
                </div>
              </div>

              <!-- Radar + jornada -->
              <div class="flex items-center gap-x-4 gap-y-1 flex-wrap mt-3 text-xs text-n-slate-11">
                <span class="inline-flex items-center gap-1.5">
                  <span class="i-lucide-radar text-sm" style="color: #EA580C" />
                  {{ col.row.radar_responded }} aviso(s) do Radar
                  <template v-if="col.row.radar_avg_response_min !== null"> · respondeu em <b class="text-n-slate-12">{{ perfFmtMin(col.row.radar_avg_response_min) }}</b></template>
                </span>
                <span v-if="col.row.workday" class="inline-flex items-center gap-1.5">
                  <span class="i-lucide-sunrise text-sm" style="color: #D97706" />
                  1ª msg <b class="text-n-slate-12">{{ col.row.workday.avg_first_msg }}</b> · última <b class="text-n-slate-12">{{ col.row.workday.avg_last_msg }}</b>
                </span>
              </div>
              <div v-if="col.row.workday?.top_gaps?.length || col.row.off_hours?.count" class="flex items-center gap-1.5 flex-wrap mt-2">
                <span
                  v-for="(g, gi) in (col.row.workday?.top_gaps || []).slice(0, 2)"
                  :key="gi"
                  class="text-[10px] px-2 py-0.5 rounded-full bg-n-alpha-1 border border-n-weak text-n-slate-11"
                  title="Maior pausa entre uma mensagem e outra no período"
                >
                  pausa {{ g.day }} · {{ g.from }}→{{ g.to }} · <b>{{ perfFmtMin(g.minutes) }}</b>
                </span>
                <span
                  v-if="col.row.off_hours?.count"
                  class="text-[10px] px-2 py-0.5 rounded-full bg-indigo-500/10 text-indigo-500 font-medium"
                  :title="'Dias com mensagens fora de seg–sex 08h–17h: ' + (col.row.off_hours.days || []).join(' · ')"
                >
                  🌙 {{ col.row.off_hours.count }} dia(s) fora do horário<template v-if="col.row.off_hours.days?.length">: {{ col.row.off_hours.days.slice(0, 3).join(' · ') }}</template>
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- 📅 Dashboard da Agenda EMBUTIDO (pedido 20/08): o dashboard
             inteiro faz parte do Meu Painel em TODAS as predefinições,
             seguindo o período da régua; a Saúde da Agenda vem logo abaixo -->
        <div class="bg-n-card outline outline-1 outline-n-container rounded-2xl p-5 sm:p-6 mb-6">
          <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
            <div class="flex items-center gap-2">
              <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
                <span class="i-lucide-calendar-days text-white text-base" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">Dashboard da Agenda</h2>
              <span class="text-[10px] text-n-slate-9">segue o período escolhido acima</span>
            </div>
            <button
              class="px-3 h-8 rounded-lg text-xs font-medium border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1.5"
              title="Abrir o relatório completo em Relatórios"
              @click="goToAgendaDashboard"
            >
              <span class="i-lucide-expand text-sm" />
              Relatório completo
            </button>
          </div>
          <AgendaDashboardCore :period="period" />
        </div>

        <!-- Saúde da Agenda -->
        <div class="bg-n-card outline outline-1 outline-n-container rounded-2xl p-5 sm:p-6 mb-6">
          <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
            <div class="flex items-center gap-2">
              <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
                <span class="i-lucide-calendar-days text-white text-base" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">Saúde da Agenda</h2>
            </div>
            <!-- atalho pulsante para a Agenda (cor do ambiente) -->
            <button
              class="cevico-pulse-btn px-4 h-9 rounded-xl text-xs font-bold text-white flex items-center gap-1.5 shadow-md"
              style="background: linear-gradient(135deg, #5B21B6, #7C3AED)"
              @click="go('agenda_board')"
            >
              <span class="i-lucide-calendar-days text-sm" />
              Ir para agenda →
            </button>
          </div>

          <!-- DOIS retângulos simétricos: Consultas × Cirurgias -->
          <div class="grid grid-cols-1 gap-4" :class="showSurgeryHealth ? 'lg:grid-cols-2' : ''">
            <!-- 🩺 Agenda de CONSULTAS -->
            <div class="rounded-xl border border-n-weak bg-n-solid-2 p-4 flex flex-col gap-4">
              <p class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
                <span class="i-lucide-stethoscope text-sm" style="color: #7C3AED" />
                Agenda de Consultas
              </p>
              <div>
                <div class="flex items-center justify-between text-xs mb-1.5">
                  <span class="text-n-slate-11">Agenda cheia <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                  <span class="font-bold text-base text-n-slate-12">{{ fillNext7.pct }}%</span>
                </div>
                <div class="h-3.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all" :style="{ width: Math.max(fillNext7.pct, 2) + '%', background: 'linear-gradient(90deg, #0F5FA6, #7C3AED)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">{{ fillNext7.filled }} de {{ fillNext7.total }} blocos</p>
              </div>
              <div>
                <div class="flex items-center justify-between text-xs mb-1.5">
                  <span class="text-n-slate-11">Aproveitamento <span class="text-n-slate-9">(últimos 7 dias)</span></span>
                  <span class="font-bold text-base text-n-slate-12">{{ usageLast7.pct }}%</span>
                </div>
                <div class="h-3.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all" :style="{ width: Math.max(usageLast7.pct, 2) + '%', background: 'linear-gradient(90deg, #B8860B, #D4A017)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">blocos que viraram consulta</p>
              </div>
              <div>
                <div class="flex items-center justify-between text-xs mb-1.5">
                  <span class="text-n-slate-11">Comparecimento <span class="text-n-slate-9">(30 dias)</span></span>
                  <span class="font-bold text-base text-n-slate-12">{{ attendance === null ? '—' : attendance + '%' }}</span>
                </div>
                <div class="h-3.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all" :style="{ width: Math.max(attendance || 0, 2) + '%', background: 'linear-gradient(90deg, #65A30D, #84CC16)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">consultas concluídas ÷ realizadas</p>
              </div>
              <!-- vagas livres, junto da agenda de consultas -->
              <div class="mt-auto pt-1 border-t border-n-weak">
                <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5 mt-2">Vagas livres mais próximas</p>
                <div v-if="nextFreeSlots.length" class="flex flex-wrap gap-1.5">
                  <button
                    v-for="(f, i) in nextFreeSlots"
                    :key="i"
                    class="flex items-center gap-1.5 text-[11px] font-medium px-2.5 py-1.5 rounded-lg border border-dashed hover:bg-n-alpha-1 transition-colors"
                    :style="{ borderColor: slotColor(f) + '70', color: slotColor(f) }"
                    @click="go('agenda_board')"
                  >
                    <span class="i-lucide-calendar-plus text-xs" />
                    {{ slotLabel(f) }} · {{ slotDoctorShort(f) }}
                  </button>
                </div>
                <p v-else class="text-xs text-n-slate-10">Sem vagas nos próximos 14 dias.</p>
                <p v-if="nextAppointment" class="text-[11px] text-n-slate-10 flex items-center gap-1.5 mt-2">
                  <span class="i-lucide-clock text-xs" />
                  Próxima consulta: <b class="text-n-slate-12">{{ nextAppointment.title }}</b> — {{ apptTime(nextAppointment.due_at) }}
                </p>
              </div>
            </div>

            <!-- 🔪 Agenda de CIRURGIAS (simétrica) -->
            <div v-if="showSurgeryHealth" class="rounded-xl border border-sky-400/30 bg-sky-400/5 p-4 flex flex-col gap-4">
              <p class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
                <span class="i-lucide-slice text-sm" style="color: #0284C7" />
                Agenda de Cirurgias
                <span class="text-[10px] font-normal text-n-slate-9">sala cirúrgica (IOP, Ocular Surgery...)</span>
              </p>
              <div>
                <div class="flex items-center justify-between text-xs mb-1.5">
                  <span class="text-n-slate-11">Sala cheia <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                  <span class="font-bold text-base text-n-slate-12">{{ surgFillNext7.total ? surgFillNext7.pct + '%' : '—' }}</span>
                </div>
                <div class="h-3.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all" :style="{ width: Math.max(surgFillNext7.pct, 2) + '%', background: 'linear-gradient(90deg, #0284C7, #7DD3FC)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">{{ surgFillNext7.total ? `${surgFillNext7.filled} de ${surgFillNext7.total} blocos` : 'sem janelas da sala nos próximos dias' }}</p>
              </div>
              <div>
                <div class="flex items-center justify-between text-xs mb-1.5">
                  <span class="text-n-slate-11">Aproveitamento <span class="text-n-slate-9">(últimos 7 dias)</span></span>
                  <span class="font-bold text-base text-n-slate-12">{{ surgUsageLast7.total ? surgUsageLast7.pct + '%' : '—' }}</span>
                </div>
                <div class="h-3.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all" :style="{ width: Math.max(surgUsageLast7.pct, 2) + '%', background: 'linear-gradient(90deg, #0369A1, #38BDF8)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">blocos da sala que viraram cirurgia</p>
              </div>
              <!-- 🎯 META: 100 cirurgias -->
              <div>
                <div class="flex items-center justify-between text-xs mb-1.5">
                  <span class="text-n-slate-11">🎯 Meta do mês <span class="text-n-slate-9">({{ SURGERY_GOAL }} cirurgias)</span></span>
                  <span class="font-bold text-base text-n-slate-12">{{ surgeriesDoneMonth }} de {{ SURGERY_GOAL }}</span>
                </div>
                <div class="h-3.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full transition-all" :style="{ width: Math.max(goalPct, 2) + '%', background: 'linear-gradient(90deg, #065F46, #10B981)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">{{ goalPct }}% da meta · cirurgias realizadas no mês</p>
              </div>
              <div class="mt-auto pt-1 border-t border-sky-400/20">
                <p v-if="nextSurgery" class="text-[11px] text-n-slate-10 flex items-center gap-1.5 mt-2">
                  <span class="i-lucide-clock text-xs" />
                  Próxima cirurgia: <b class="text-n-slate-12">{{ nextSurgery.title.replace(/^Consulta:\s*/i, '') }}</b> — {{ apptTime(nextSurgery.due_at) }}
                </p>
                <p v-else class="text-[11px] text-n-slate-10 mt-2">Nenhuma cirurgia futura na agenda.</p>
              </div>
            </div>
          </div>

          <!-- % de agendamento (linha compacta) -->
          <div class="mt-4 rounded-xl border border-n-weak bg-n-solid-2 px-4 py-3">
            <div class="flex items-center justify-between">
              <span class="text-xs text-n-slate-11">% de agendamento <span class="text-n-slate-9">(30 dias)</span></span>
              <span v-if="bookingRate30 !== null" class="font-bold text-xl" :style="{ color: booking30Verdict.color }">{{ bookingRate30 }}%</span>
              <span v-else class="text-n-slate-9 text-xs">sem dados</span>
            </div>
            <div v-if="booking30Verdict" class="flex items-center justify-between mt-1 flex-wrap gap-1">
              <span class="text-[10px] text-n-slate-9">{{ data.appointments_30d || 0 }} consultas ÷ {{ data.new_contacts_30d || 0 }} leads (Google+Instagram)</span>
              <span class="text-[10px] px-2 py-0.5 rounded-full font-semibold text-white" :style="{ background: booking30Verdict.color }">{{ booking30Verdict.label }}</span>
            </div>
            <p class="text-[9px] text-n-slate-9 mt-1">Referência: 15% muito bom · 10% bom · 5% fraco</p>
          </div>
        </div>

        <!-- 🎯 Metas · Rotinas · Ferramentas (alimentado pelo Painel de Metas) -->
        <div v-if="goalsData" class="grid grid-cols-1 md:grid-cols-3 gap-3 mb-6">
          <!-- METAS do mês -->
          <button
            class="rounded-2xl border border-n-weak bg-n-card outline-none p-4 text-left hover:border-violet-500/60 hover:shadow-md transition-all"
            @click="goToGoals"
          >
            <div class="flex items-center gap-2 mb-2">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
                <span class="i-lucide-target text-white text-sm" />
              </span>
              <p class="text-xs font-bold text-n-slate-12 flex-1">Metas do mês</p>
              <span class="i-lucide-chevron-right text-sm text-n-slate-9" />
            </div>
            <template v-if="goalRows.length">
              <div v-for="g in goalRows" :key="g.key" class="mb-1.5">
                <div class="flex items-center justify-between text-[10px] mb-0.5">
                  <span class="text-n-slate-10 truncate">{{ g.label }}</span>
                  <b class="text-n-slate-12">{{ g.current }}/{{ g.target }}</b>
                </div>
                <div class="h-1.5 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all duration-700"
                    :style="{ width: `${Math.max(g.pct, 2)}%`, background: g.pct >= 100 ? 'linear-gradient(90deg, #047857, #34D399)' : 'linear-gradient(90deg, #5B21B6, #7C3AED)' }"
                  />
                </div>
              </div>
            </template>
            <p v-else class="text-[11px] text-n-slate-9">
              {{ isAdmin ? 'Defina a meta do mês no Painel de Metas →' : 'A meta do mês aparece aqui quando o gestor definir.' }}
            </p>
          </button>

          <!-- ROTINAS -->
          <div class="rounded-2xl border border-n-weak bg-n-card p-4">
            <div class="flex items-center gap-2 mb-2">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F766E, #2DD4BF)">
                <span class="i-lucide-repeat text-white text-sm" />
              </span>
              <p class="text-xs font-bold text-n-slate-12">Rotinas</p>
            </div>
            <template v-if="teamRoutines.length">
              <p v-for="(r, ri) in teamRoutines.slice(0, 5)" :key="ri" class="text-[11px] text-n-slate-11 leading-relaxed flex items-start gap-1.5 mb-0.5">
                <span class="i-lucide-check-circle-2 text-[11px] mt-0.5 flex-shrink-0" style="color: #0D9488" />
                {{ r }}
              </p>
            </template>
            <p v-else class="text-[11px] text-n-slate-9">
              {{ isAdmin ? 'Cadastre as rotinas do time no Painel de Metas.' : 'As rotinas combinadas aparecem aqui.' }}
            </p>
          </div>

          <!-- FERRAMENTAS importantes -->
          <div class="rounded-2xl border border-n-weak bg-n-card p-4">
            <div class="flex items-center gap-2 mb-2">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #065F46, #34D399)">
                <span class="i-lucide-wrench text-white text-sm" />
              </span>
              <p class="text-xs font-bold text-n-slate-12">Ferramentas</p>
            </div>
            <button
              class="w-full flex items-center gap-1.5 text-[11px] font-semibold text-n-slate-12 rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 mb-1 hover:border-emerald-500/60 transition-colors"
              @click="goToTools"
            >
              <span class="i-lucide-swords text-[11px]" style="color: #047857" />
              Fechamento: script + mapa de objeções
              <span class="i-lucide-chevron-right text-[11px] ml-auto text-n-slate-9" />
            </button>
            <button
              v-for="(t, ti) in importantTools.slice(0, 4)"
              :key="ti"
              class="w-full flex items-center gap-1.5 text-[11px] text-n-slate-11 rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 mb-1 hover:border-emerald-500/60 transition-colors"
              @click="openTool(t)"
            >
              <span class="i-lucide-external-link text-[11px] text-n-slate-9" />
              <span class="truncate">{{ t.label }}</span>
            </button>
          </div>
        </div>

        <!-- Acesso rápido (compacto, largura toda) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
          <button
            v-for="s in shortcuts"
            :key="s.route"
            class="flex items-center gap-2.5 px-4 py-3 rounded-2xl border border-n-weak bg-n-solid-2 hover:border-n-brand/60 transition-colors text-left"
            @click="go(s.route)"
          >
            <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" :style="{ backgroundColor: s.color + '1A' }">
              <span :class="s.icon" class="text-lg" :style="{ color: s.color }" />
            </span>
            <span class="text-sm font-semibold text-n-slate-12">{{ s.label }}</span>
          </button>
        </div>

        <!-- Termômetro do momento -->
        <div class="flex flex-wrap gap-4 text-xs text-n-slate-10">
          <span class="flex items-center gap-1.5"><span class="i-lucide-inbox text-sm" /> {{ data.open_conversations ?? 0 }} conversas abertas agora</span>
          <span class="flex items-center gap-1.5" :class="(data.unanswered ?? 0) > 0 ? 'text-amber-500 font-medium' : ''">
            <span class="i-lucide-clock-alert text-sm" /> {{ data.unanswered ?? 0 }} aguardando resposta
          </span>
          <span class="flex items-center gap-1.5"><span class="i-lucide-calendar-check text-sm" /> {{ data.appointments_today ?? 0 }} consultas hoje</span>
        </div>
      </template>

      <!-- Admin: quem vê qual painel -->
      <div
        v-if="showAssignModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="showAssignModal = false"
      >
        <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md max-h-[85vh] flex flex-col overflow-hidden">
          <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #111827, #94A3B8)" />
          <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
            <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
              <span class="i-lucide-settings-2 text-n-brand" />
              Painel de cada pessoa
            </h2>
            <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showAssignModal = false" />
          </div>
          <div class="flex-1 overflow-y-auto p-5 space-y-2">
            <p class="text-xs text-n-slate-10 mb-2">
              A pessoa abre o Meu Painel já na versão da função dela (e só vê essa).
              "Livre" = pode alternar entre todos os painéis.
            </p>
            <div v-for="agent in teamAgents" :key="agent.id" class="flex items-center gap-2">
              <span class="text-sm text-n-slate-12 flex-1 truncate">{{ agent.name }}</span>
              <select
                v-model="assignDraft[String(agent.id)]"
                class="h-8 text-xs border border-n-weak rounded-lg px-2 bg-n-solid-2 text-n-slate-12"
              >
                <option value="">Livre (todos)</option>
                <!-- lista também os painéis do Construtor (custom:<id>) -->
                <option v-for="p in allPanels" :key="p.key" :value="p.key">
                  {{ p.label }}<template v-if="p.who"> · {{ p.who }}</template>
                </option>
              </select>
            </div>
          </div>
          <div class="px-5 py-4 border-t border-n-weak flex gap-2 flex-shrink-0">
            <button
              class="flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
              style="background: linear-gradient(135deg, #111827, #475569)"
              :disabled="isSavingAssign"
              @click="saveAssignments"
            >
              {{ isSavingAssign ? 'Salvando…' : 'Salvar' }}
            </button>
            <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showAssignModal = false">
              Cancelar
            </button>
          </div>
        </div>
      </div>

    <!-- 🎯 Modal de METAS por painel (admin) -->
    <div
      v-if="showGoalsModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      @click.self="showGoalsModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-xl w-full max-w-md p-5">
        <div class="flex items-center justify-between mb-1">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-target text-base" style="color: #d4af37" />
            Metas — {{ currentPanel.label }}
          </h3>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showGoalsModal = false" />
        </div>
        <p class="text-[11px] text-n-slate-10 mb-4">
          Metas MENSAIS (as taxas % são diretas). Os cards mudam de cor pelo ritmo:
          🔴 muito abaixo · 🟠 abaixo · cores normais no ritmo · 🟢 meta batida · 🏆 recorde com átomos.
        </p>
        <div class="space-y-3 mb-4">
          <label
            v-for="field in GOAL_FIELDS[selectedPanel] || []"
            :key="field.gk"
            class="flex items-center gap-3"
          >
            <span class="text-xs text-n-slate-11 flex-1">{{ field.label }}</span>
            <input
              v-model.number="goalsDraft[selectedPanel][field.gk]"
              type="number"
              min="0"
              :step="field.pct ? 0.5 : 1"
              class="w-24 h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12 text-right"
              placeholder="—"
            />
          </label>
        </div>
        <p class="text-[10px] text-n-slate-9 mb-3">Deixar vazio (ou 0) = sem meta para aquele card.</p>
        <div class="flex justify-end gap-2">
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showGoalsModal = false">Cancelar</button>
          <button
            class="px-4 rounded-lg py-2 text-sm font-semibold text-white disabled:opacity-60"
            :style="{ background: currentPanel.grad }"
            :disabled="isSavingGoals"
            @click="saveGoals"
          >
            {{ isSavingGoals ? 'Salvando…' : 'Salvar metas' }}
          </button>
        </div>
      </div>
    </div>
    </div>

    <!-- Balão da conversa direto do card do Radar (o mesmo do CRM) -->
    <ConversationChatModal
      v-if="radarChat"
      :contact="radarChat"
      @close="radarChat = null"
      @replied="onRadarChatReplied"
      @resolved="onRadarChatResolved"
    />

    <EmojiFx ref="radarFx" />
  </div>
</template>

<style scoped>
/* card da frente do Radar: pulso verde (como Tarefas 100%) */
.cevico-radar-front {
  border: 1px solid rgba(16, 185, 129, 0.45);
  animation: cevico-radar-pulse 2.2s ease-in-out infinite;
}
@keyframes cevico-radar-pulse {
  0%, 100% { box-shadow: 0 0 8px rgba(16, 185, 129, 0.3); }
  50% { box-shadow: 0 0 22px rgba(52, 211, 153, 0.65); }
}
/* meta batida / recorde: o card respira com brilho suave */
.cevico-meta-pulse {
  animation: cevicoMetaPulse 2.6s ease-in-out infinite;
}
@keyframes cevicoMetaPulse {
  0%, 100% { box-shadow: 0 10px 24px rgba(0, 0, 0, 0.2); }
  50% { box-shadow: 0 10px 24px rgba(0, 0, 0, 0.2), 0 0 26px 4px rgba(244, 222, 142, 0.45); }
}

/* botão de atalho pulsante (Ir para agenda) — respiração suave */
.cevico-pulse-btn {
  animation: cevico-pulse 2.2s ease-in-out infinite;
  transition: transform 0.15s ease;
}
.cevico-pulse-btn:hover {
  transform: scale(1.05);
  animation-play-state: paused;
}
@keyframes cevico-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(124, 58, 237, 0.45);
  }
  50% {
    box-shadow: 0 0 0 9px rgba(124, 58, 237, 0);
  }
}

/* "Atender agora" do Radar — botão que EMANA ENERGIA (pedido 17/07):
   respiração + anéis verdes saindo do botão + brilho varrendo por cima */
.cevico-energy-btn {
  position: relative;
  background: linear-gradient(135deg, #059669, #22c55e, #4ade80);
  background-size: 200% 200%;
  overflow: hidden;
  animation:
    cevico-energy-breathe 2s ease-in-out infinite,
    cevico-energy-rings 2s ease-out infinite,
    cevico-energy-grad 4s ease-in-out infinite;
  transition: transform 0.15s ease;
}
.cevico-energy-btn:hover {
  transform: scale(1.06);
}
.cevico-energy-btn::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    115deg,
    transparent 30%,
    rgba(255, 255, 255, 0.45) 50%,
    transparent 70%
  );
  transform: translateX(-120%);
  animation: cevico-energy-shine 2.6s ease-in-out infinite;
}
@keyframes cevico-energy-breathe {
  0%,
  100% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.035);
  }
}
@keyframes cevico-energy-rings {
  0% {
    box-shadow:
      0 0 0 0 rgba(34, 197, 94, 0.5),
      0 0 0 0 rgba(34, 197, 94, 0.3);
  }
  100% {
    box-shadow:
      0 0 0 10px rgba(34, 197, 94, 0),
      0 0 0 18px rgba(34, 197, 94, 0);
  }
}
@keyframes cevico-energy-grad {
  0%,
  100% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 50%;
  }
}
@keyframes cevico-energy-shine {
  0%,
  55% {
    transform: translateX(-120%);
  }
  85%,
  100% {
    transform: translateX(120%);
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-energy-btn,
  .cevico-energy-btn::after {
    animation: none;
  }
}
</style>
