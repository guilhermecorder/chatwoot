<script setup>
// Meu Painel (tela inicial) — visível para admin E atendentes.
// Boas-vindas, avisos do Radar, indicadores por período (hoje/ontem/semana/
// mês/mês passado) e a saúde da agenda — com atalhos para agir rápido.
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
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
const PERIODS = [
  { key: 'today', label: 'Hoje' },
  { key: 'yesterday', label: 'Ontem' },
  { key: 'week', label: 'Essa semana' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
  { key: 'year', label: 'Este ano' },
];
const selectedPeriod = ref('today');

// ── Painéis por pessoa: mesmo layout, indicadores e cores da função ──
const PANELS = [
  {
    key: 'agendamento', label: 'Agendamento', who: 'Vaneide',
    icon: 'i-lucide-calendar-check', desc: 'do lead ao agendamento',
    grad: 'linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)',
  },
  {
    key: 'conducao', label: 'Condução', who: 'Elisangela',
    icon: 'i-lucide-route', desc: 'do agendamento à indicação',
    grad: 'linear-gradient(135deg, #0F766E 0%, #2DD4BF 100%)',
  },
  {
    key: 'cirurgia', label: 'Cirurgias', who: 'Gabriela',
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

// painel ATRIBUÍDO pelo admin: o agente fica travado nele
const assignedPanel = computed(() => {
  if (isAdmin.value) return null;
  const map = crmSettings.value?.panel_assignments || {};
  return map[String(currentUser.value?.id)] || null;
});
const visiblePanels = computed(() =>
  assignedPanel.value ? PANELS.filter(p => p.key === assignedPanel.value) : PANELS
);

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
const selectedPanel = ref(localStorage.getItem('cevico_meu_painel') || 'agendamento');
watch(assignedPanel, key => {
  if (key && selectedPanel.value !== key) {
    selectedPanel.value = key;
    fetchData();
  }
});
const selectedDoctor = ref(localStorage.getItem('cevico_meu_painel_medico') || '');
const currentPanel = computed(() => PANELS.find(p => p.key === selectedPanel.value) || PANELS[0]);

const fetchData = async () => {
  try {
    const { data: payload } = await CrmAPI.getHome({
      preset: selectedPeriod.value,
      panel: selectedPanel.value,
      doctor: selectedPanel.value === 'medico' ? selectedDoctor.value || undefined : undefined,
    });
    data.value = payload;
  } catch {
    data.value = data.value || {};
  } finally {
    isLoading.value = false;
  }
};

const setPeriod = key => {
  selectedPeriod.value = key;
  fetchData();
};

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
  const d = pd.value;
  if (selectedPanel.value === 'conducao') {
    return [
      { label: 'Consultas no período', icon: 'i-lucide-calendar-days', value: d.consultations ?? 0, sub: 'agenda das unidades', grad: 'linear-gradient(135deg, #0F766E, #115E59)' },
      { label: 'Compareceram', icon: 'i-lucide-user-check', value: d.attended ?? 0, sub: 'conferência do dia (Agenda)', grad: 'linear-gradient(135deg, #14B8A6, #0D9488)' },
      { label: 'Comparecimento', icon: 'i-lucide-percent', value: `${d.show_rate ?? 0}%`, sub: `${d.missed ?? 0} falta(s) no período`, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
      { label: 'Indicações de cirurgia', icon: 'i-lucide-stethoscope', value: d.indications ?? 0, sub: 'saíram da consulta indicados', grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
    ];
  }
  if (selectedPanel.value === 'cirurgia') {
    return [
      { label: 'Indicações de cirurgia', icon: 'i-lucide-stethoscope', value: d.indications ?? 0, sub: 'pacientes indicados no período', grad: 'linear-gradient(135deg, #9D174D, #BE185D)' },
      { label: 'Cirurgias agendadas', icon: 'i-lucide-calendar-plus', value: d.surgeries_booked ?? 0, sub: 'fechadas no período', grad: 'linear-gradient(135deg, #BE185D, #EC4899)' },
      { label: 'Taxa de fechamento', icon: 'i-lucide-percent', value: `${d.closing_rate ?? 0}%`, sub: 'agendadas ÷ indicações', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
      { label: 'Cirurgias realizadas', icon: 'i-lucide-heart-pulse', value: d.surgeries_done ?? 0, sub: `${d.surgeries_missed ?? 0} não vieram`, grad: 'linear-gradient(135deg, #65A30D, #84CC16)' },
    ];
  }
  if (selectedPanel.value === 'medico') {
    return [
      { label: 'Consultas no período', icon: 'i-lucide-calendar-days', value: d.consultations ?? 0, sub: `${d.missed ?? 0} falta(s) · ${d.show_rate ?? 0}% comparecimento`, grad: 'linear-gradient(135deg, #0369A1, #075985)' },
      { label: 'Com indicação de cirurgia', icon: 'i-lucide-stethoscope', value: d.indications ?? 0, sub: `${d.indication_rate ?? 0}% de quem compareceu`, grad: 'linear-gradient(135deg, #0EA5E9, #38BDF8)' },
      { label: 'Sem indicação', icon: 'i-lucide-user-minus', value: d.no_indication ?? 0, sub: `${d.no_indication_rate ?? 0}% de quem compareceu`, grad: 'linear-gradient(135deg, #64748B, #94A3B8)' },
      { label: 'Conversão em cirurgia', icon: 'i-lucide-percent', value: `${d.conversion_rate ?? 0}%`, sub: `${d.conversions ?? 0} viraram cirurgia · NPS ${d.nps_avg ?? '—'}`, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
    ];
  }
  if (selectedPanel.value === 'gestor') {
    return [
      { label: 'Novos contatos (leads)', icon: 'i-lucide-user-plus', value: d.new_leads ?? 0, sub: 'caixas Google + Instagram', grad: 'linear-gradient(135deg, #0F5FA6, #0B4A82)' },
      { label: 'Taxa de agendamento', icon: 'i-lucide-percent', value: `${d.booking_conversion ?? 0}%`, sub: `${d.appointments_created ?? 0} consulta(s) agendada(s)`, grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
      { label: 'Comparecimento', icon: 'i-lucide-user-check', value: `${d.show_rate ?? 0}%`, sub: `${d.indications ?? 0} indicação(ões) de cirurgia`, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
      { label: 'Fechamento de cirurgias', icon: 'i-lucide-heart-pulse', value: `${d.closing_rate ?? 0}%`, sub: `${d.surgeries_booked ?? 0} agendada(s) · ${d.surgeries_done ?? 0} realizada(s)`, grad: 'linear-gradient(135deg, #065F46, #10B981)' },
    ];
  }
  // agendamento (padrão — Vaneide)
  return [
    { label: 'Novos contatos (leads)', icon: 'i-lucide-user-plus', value: d.new_leads ?? 0, sub: 'caixas Google + Instagram', grad: 'linear-gradient(135deg, #0F5FA6, #0B4A82)' },
    { label: 'Consultas agendadas', icon: 'i-lucide-calendar-check', value: d.appointments_booked ?? 0, sub: 'registradas no período', sub2: `⚡ ${d.appointments_same_day ?? 0} chegaram e agendaram`, grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
    { label: 'Taxa de agendamento', icon: 'i-lucide-percent', value: `${d.booking_conversion ?? 0}%`, chip: conversionVerdict.value, grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
    { label: 'Cirurgias fechadas', icon: 'i-lucide-heart-pulse', value: d.surgeries_closed ?? 0, sub: 'coluna Cirurgia Agendada (CRM)', grad: 'linear-gradient(135deg, #65A30D, #84CC16)' },
  ];
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
const fmtTaskDue = iso =>
  iso ? new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : null;

// ── Radar de Oportunidades ──────────────────────────────────
const radarAlerts = computed(() => data.value?.opportunity_alerts?.alerts || []);
const radarLastRun = computed(() => {
  const iso = data.value?.opportunity_alerts?.last_run_at;
  return iso ? new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : null;
});
const waitingLabel = alert => {
  if (!alert.waiting_since) return '';
  const min = Math.round((Date.now() - new Date(alert.waiting_since).getTime()) / 60000);
  if (min < 60) return `${min} min sem resposta`;
  return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')} sem resposta`;
};
const openConversation = alert =>
  router.push(`/app/accounts/${accountId.value}/conversations/${alert.conversation_id}`);

// ── Indicadores do período ──────────────────────────────────
const conversionVerdict = computed(() => {
  const r = data.value?.booking_conversion ?? 0;
  if (r >= 15) return { label: 'Muito bom 🚀', color: '#84CC16' };
  if (r >= 10) return { label: 'Bom 👍', color: '#3B82F6' };
  if (r >= 5) return { label: 'Regular', color: '#D4A017' };
  return { label: 'Fraco', color: '#EF4444' };
});

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
  if (r >= 15) return { label: 'Muito bom 🚀', color: '#84CC16' };
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

onMounted(() => {
  store.dispatch('crm/fetchSettings').catch(() => {});
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
          <p class="text-sm font-medium mb-1" style="color: rgba(255,255,255,0.75)">{{ todayLabel }}</p>
          <h1 class="text-2xl sm:text-4xl font-bold leading-tight" style="color: #fff">{{ greeting }}, {{ firstName }}! 👋</h1>
          <p class="text-sm mt-2" style="color: rgba(255,255,255,0.85)">
            Boas-vindas ao CEVICO S.I —
            <b>Painel de {{ currentPanel.label }}</b><template v-if="currentPanel.who"> ({{ currentPanel.who }})</template>: {{ currentPanel.desc }}.
          </p>
        </div>
        <span class="i-lucide-eye absolute -right-6 -bottom-8 text-[160px] text-white/10" />
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- 🚨 Avisos do Radar de Oportunidades -->
        <div
          v-if="radarAlerts.length"
          class="rounded-2xl border-2 border-red-500/40 bg-red-500/5 overflow-hidden mb-6"
        >
          <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #DC2626, #F59E0B)" />
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-2 mb-3 flex-wrap">
              <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #DC2626, #F59E0B)">
                <span class="i-lucide-radar text-white text-base" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">
                {{ radarAlerts.length === 1
                  ? '1 paciente quente sem atendimento'
                  : `${radarAlerts.length} pacientes quentes sem atendimento` }}
              </h2>
              <span v-if="radarLastRun" class="text-[11px] text-n-slate-9 ml-auto">auditoria às {{ radarLastRun }}</span>
            </div>
            <div class="space-y-2">
              <div
                v-for="alert in radarAlerts"
                :key="alert.conversation_id"
                class="bg-n-solid-1 border border-red-500/25 rounded-xl p-3"
              >
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="i-lucide-flame text-red-500" />
                  <p class="text-sm font-bold text-n-slate-12">{{ alert.contact_name }}</p>
                  <span v-if="alert.stage_name" class="text-[10px] px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11">{{ alert.stage_name }}</span>
                  <span class="text-[10px] px-2 py-0.5 rounded-full bg-red-500/15 text-red-600 font-semibold">⏱ {{ waitingLabel(alert) }}</span>
                  <span v-if="alert.user_name" class="text-[10px] px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-600 font-semibold">📌 para {{ alert.user_name }}</span>
                  <button
                    class="ml-auto text-xs font-semibold text-white px-3 py-1.5 rounded-lg hover:opacity-90"
                    style="background: linear-gradient(135deg, #DC2626, #F59E0B)"
                    @click="openConversation(alert)"
                  >
                    Atender agora →
                  </button>
                </div>
                <p class="text-xs text-n-slate-11 mt-1.5"><b class="text-n-slate-12">Motivo:</b> {{ alert.motivo }}</p>
                <p class="text-xs text-n-slate-11 mt-0.5"><b class="text-n-slate-12">O que fazer:</b> {{ alert.acao }}</p>
              </div>
            </div>
          </div>
        </div>

        <!-- 📋 Tarefas esperando você (aviso DOURADO — coisa boa a fazer) -->
        <div
          v-if="myTasks.length"
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

        <!-- Seletor de período -->
        <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto mb-4">
          <button
            v-for="p in PERIODS"
            :key="p.key"
            class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
            :class="selectedPeriod === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="selectedPeriod === p.key ? { background: currentPanel.grad } : {}"
            @click="setPeriod(p.key)"
          >
            {{ p.label }}
          </button>
        </div>

        <!-- Indicadores do período — mudam com o painel escolhido -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div
            v-for="tile in panelTiles"
            :key="tile.label"
            class="rounded-2xl p-4 sm:p-5 text-white shadow-lg"
            :style="{ background: tile.grad }"
          >
            <div class="flex items-center gap-1.5 mb-1 text-white/80"><span :class="tile.icon" class="text-sm" /><p class="text-xs font-medium">{{ tile.label }}</p></div>
            <p class="text-3xl font-bold">{{ tile.value }}</p>
            <span v-if="tile.chip" class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-white/20">{{ tile.chip.label }}</span>
            <template v-else-if="tile.sub">
              <!-- linhas curtas propositais: nada de frase quebrando no meio -->
              <p class="text-[10px] text-white/70 truncate">{{ tile.sub }}</p>
              <p v-if="tile.sub2" class="text-[10px] text-white/80 truncate">{{ tile.sub2 }}</p>
            </template>
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
                <option v-for="p in PANELS" :key="p.key" :value="p.key">
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
    </div>
  </div>
</template>

<style scoped>
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
</style>
