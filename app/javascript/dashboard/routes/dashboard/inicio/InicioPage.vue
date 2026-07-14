<script setup>
// Meu Painel (tela inicial) — visível para admin E atendentes.
// Boas-vindas, avisos do Radar, indicadores por período (hoje/ontem/semana/
// mês/mês passado) e a saúde da agenda — com atalhos para agir rápido.
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, resolveWindows, resolveBlocked, resolveBlockedDays, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';

const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');
const crmSettings = useMapGetter('crm/getSettings');

const isLoading = ref(true);
const data = ref(null);

// ── Período ─────────────────────────────────────────────────
const PERIODS = [
  { key: 'today', label: 'Hoje' },
  { key: 'yesterday', label: 'Ontem' },
  { key: 'week', label: 'Essa semana' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
];
const selectedPeriod = ref('today');

const fetchData = async () => {
  try {
    const { data: payload } = await CrmAPI.getHome({ preset: selectedPeriod.value });
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
        class="rounded-3xl p-6 sm:p-9 text-white shadow-lg mb-6 relative overflow-hidden"
        style="background: linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)"
      >
        <div class="relative z-10">
          <p class="text-sm font-medium text-white/70 mb-1">{{ todayLabel }}</p>
          <h1 class="text-2xl sm:text-4xl font-bold leading-tight">{{ greeting }}, {{ firstName }}! 👋</h1>
          <p class="text-sm text-white/80 mt-2">Boas-vindas ao CEVICO S.I — aqui está o seu resumo.</p>
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
                {{ radarAlerts.length }} paciente(s) quente(s) sem atendimento
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

        <!-- Seletor de período -->
        <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto mb-4">
          <button
            v-for="p in PERIODS"
            :key="p.key"
            class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
            :class="selectedPeriod === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="selectedPeriod === p.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="setPeriod(p.key)"
          >
            {{ p.label }}
          </button>
        </div>

        <!-- Indicadores do período -->
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4">
          <div class="rounded-2xl p-4 sm:p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #0F5FA6, #0B4A82)">
            <div class="flex items-center gap-1.5 mb-1 text-white/80"><span class="i-lucide-message-circle text-sm" /><p class="text-xs font-medium">Novas conversas</p></div>
            <p class="text-3xl font-bold">{{ data.new_conversations ?? 0 }}</p>
          </div>
          <div class="rounded-2xl p-4 sm:p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
            <div class="flex items-center gap-1.5 mb-1 text-white/80"><span class="i-lucide-calendar-check text-sm" /><p class="text-xs font-medium">Consultas agendadas</p></div>
            <p class="text-3xl font-bold">{{ data.appointments_created ?? 0 }}</p>
          </div>
          <div class="rounded-2xl p-4 sm:p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
            <div class="flex items-center gap-1.5 mb-1 text-white/80"><span class="i-lucide-percent text-sm" /><p class="text-xs font-medium">Taxa de agendamento</p></div>
            <p class="text-3xl font-bold">{{ data.booking_conversion ?? 0 }}%</p>
            <span class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-white/20">{{ conversionVerdict.label }}</span>
          </div>
          <div class="rounded-2xl p-4 sm:p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #65A30D, #84CC16)">
            <div class="flex items-center gap-1.5 mb-1 text-white/80"><span class="i-lucide-heart-pulse text-sm" /><p class="text-xs font-medium">Cirurgias fechadas</p></div>
            <p class="text-3xl font-bold">{{ data.surgeries_closed ?? '—' }}</p>
            <p class="text-[10px] text-white/70">{{ data.surgeries_closed === null ? 'conecte a planilha em Integrações' : 'pela planilha (Sheets)' }}</p>
          </div>
        </div>

        <!-- Linha 2: movimentações -->
        <div class="grid grid-cols-3 gap-4 mb-6">
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl px-4 py-3">
            <p class="text-[11px] text-n-slate-10 flex items-center gap-1"><span class="i-lucide-calendar-sync text-xs" /> Reagendadas</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ data.rescheduled ?? 0 }}</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl px-4 py-3">
            <p class="text-[11px] text-n-slate-10 flex items-center gap-1"><span class="i-lucide-calendar-x text-xs" /> Canceladas</p>
            <p class="text-2xl font-bold" :class="(data.canceled ?? 0) > 0 ? 'text-red-500' : 'text-n-slate-12'">{{ data.canceled ?? 0 }}</p>
          </div>
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl px-4 py-3">
            <p class="text-[11px] text-n-slate-10 flex items-center gap-1"><span class="i-lucide-stethoscope text-xs" /> Indicações de cirurgia</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ data.surgery_indications ?? 0 }}</p>
          </div>
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
            <button class="text-xs font-medium text-n-brand hover:underline" @click="go('agenda_board')">Ver agenda →</button>
          </div>

          <!-- Medidores (barras mais grossas) -->
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-5 mb-5">
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
          </div>

          <!-- % de agendamento (30d) + vagas -->
          <div class="flex flex-col sm:flex-row gap-4">
            <div class="flex-1 rounded-xl border border-n-weak bg-n-solid-2 px-4 py-3">
              <div class="flex items-center justify-between">
                <span class="text-xs text-n-slate-11">% de agendamento <span class="text-n-slate-9">(30 dias)</span></span>
                <span v-if="bookingRate30 !== null" class="font-bold text-xl" :style="{ color: booking30Verdict.color }">{{ bookingRate30 }}%</span>
                <span v-else class="text-n-slate-9 text-xs">sem dados</span>
              </div>
              <div v-if="booking30Verdict" class="flex items-center justify-between mt-1 flex-wrap gap-1">
                <span class="text-[10px] text-n-slate-9">{{ data.appointments_30d || 0 }} consultas ÷ {{ data.new_contacts_30d || 0 }} novos contatos</span>
                <span class="text-[10px] px-2 py-0.5 rounded-full font-semibold text-white" :style="{ background: booking30Verdict.color }">{{ booking30Verdict.label }}</span>
              </div>
              <p class="text-[9px] text-n-slate-9 mt-1">Referência: 15% muito bom · 10% bom · 5% fraco</p>
            </div>
            <div class="flex-1">
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Vagas livres mais próximas</p>
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
    </div>
  </div>
</template>
