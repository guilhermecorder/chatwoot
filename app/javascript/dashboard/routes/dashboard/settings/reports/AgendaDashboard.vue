<script setup>
// Dashboard da AGENDA (análise do gestor): comparecimento, faltas,
// cancelamentos, reagendamentos, conferência pendente, mix por modalidade,
// médicos, unidades, dias da semana, cirurgias por clínica e ocupação.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, MODALITIES, resolveWindows, resolveBlocked, resolveBlockedDays,
  resolveSurgeryWindows, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';
import { termo } from 'dashboard/helper/segmento';

const store = useStore();
const isLoading = ref(true);
const data = ref(null);

const PERIODS = [
  { key: 'today', label: 'Hoje' },
  { key: 'week', label: 'Essa semana' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
  { key: 'year', label: 'Este ano' },
];
const selectedPeriod = ref('month');

const fetchData = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAgendaDashboard({ preset: selectedPeriod.value });
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

// ── Ocupação (mesma conta da Agenda/Meu Painel: janelas × blocos) ──
const allTasks = useMapGetter('tasks/getTasks');
const crmSettings = useMapGetter('crm/getSettings');

const consultTasks = computed(() =>
  (allTasks.value || []).filter(t => t.task_type === 'consulta' && t.due_at && !t.canceled_at)
);
const surgeryTasks = computed(() =>
  (allTasks.value || []).filter(t => t.task_type === 'cirurgia' && t.due_at && !t.canceled_at)
);
const scan = (tasks, windows, opts) =>
  scanAgenda({
    windows,
    tasks,
    blockedSet: new Set(resolveBlocked(crmSettings.value).map(b => blockKey(b.date, b.time, b.unit))),
    blockedDays: new Set(resolveBlockedDays(crmSettings.value)),
    freeLimit: 0,
    ...opts,
  });
const fillNext7 = computed(() =>
  scan(consultTasks.value, resolveWindows(crmSettings.value), { from: new Date(), days: 7, futureOnly: true })
);
const usageLast7 = computed(() => {
  const from = new Date();
  from.setDate(from.getDate() - 7);
  return scan(consultTasks.value, resolveWindows(crmSettings.value), { from, days: 7, pastOnly: true });
});
const surgFillNext7 = computed(() =>
  scan(surgeryTasks.value, resolveSurgeryWindows(crmSettings.value), { from: new Date(), days: 7, futureOnly: true })
);

const doctorColor = name => DOCTORS.find(d => d.name === name)?.color || '#64748B';
const modColor = key => MODALITIES.find(m => m.key === key)?.color || '#64748B';
const rateColor = pct => {
  if (pct >= 80) return '#059669';
  if (pct >= 60) return '#D4A017';
  return '#DC2626';
};
const maxWeekday = computed(() =>
  Math.max(1, ...(data.value?.by_weekday || []).map(w => w.count))
);

// metas oficiais do mês (Painel de Metas) → selos de recorde/meta nos KPIs
const goals = useCevicoGoals();

onMounted(() => {
  fetchData();
  goals.load();
  if (!(allTasks.value || []).length) store.dispatch('tasks/fetch').catch(() => {});
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
          <span class="i-lucide-calendar-days text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard da Agenda</h1>
          <p class="text-xs text-n-slate-10">comparecimento · modalidades · {{ termo('profissionais') }} · unidades · {{ termo('vendas') }} · ocupação</p>
        </div>
      </div>

      <!-- Período -->
      <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto mb-6">
        <button
          v-for="p in PERIODS"
          :key="p.key"
          class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
          :class="selectedPeriod === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="selectedPeriod === p.key ? { background: 'linear-gradient(135deg, #5B21B6, #7C3AED)' } : {}"
          @click="setPeriod(p.key)"
        >
          {{ p.label }}
        </button>
      </div>

      <div v-if="isLoading || !data" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- KPIs de consultas (padrão CEVICO c/ selos de recorde/meta) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          <DashKpi
            compact
            label="Consultas no período"
            :value="data.consultas?.total ?? 0"
            :sub="`${data.consultas?.canceled ?? 0} cancelada(s)`"
            from="#0F5FA6"
            to="#38BDF8"
            :state="goals.stateFor('appointments_booked')"
            :goal="goals.goalFor('appointments_booked')"
          />
          <DashKpi
            compact
            label="Comparecimento"
            :value="`${data.consultas?.show_rate ?? 0}%`"
            :sub="`${data.consultas?.attended ?? 0} vieram · ${data.consultas?.missed ?? 0} faltaram`"
            from="#059669"
            to="#34D399"
            :state="goals.stateFor('consultations_attended')"
            :goal="goals.goalFor('consultations_attended')"
          />
          <DashKpi
            compact
            label="Indicações de cirurgia"
            :value="data.consultas?.indications ?? 0"
            :sub="`${data.consultas?.indication_rate ?? 0}% de quem compareceu`"
            from="#B8860B"
            to="#D4A017"
          />
          <DashKpi
            compact
            label="Reagendadas / sem conferência"
            :value="`${data.consultas?.rescheduled ?? 0} / ${data.consultas?.unconfirmed ?? 0}`"
            sub="sem conferência = passou sem ✓/✗"
            :value-color="(data.consultas?.unconfirmed ?? 0) > 0 ? '#EF4444' : ''"
          />
        </div>

        <!-- Modalidades + dias da semana -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span class="i-lucide-tags text-base" style="color: #7C3AED" />
              Consultas por tipo
            </h2>
            <div v-if="!data.by_modality?.length" class="text-xs text-n-slate-10 py-4 text-center">Nenhuma consulta no período.</div>
            <div v-else class="space-y-3">
              <div v-for="m in data.by_modality" :key="m.key">
                <div class="flex items-center justify-between text-xs mb-1">
                  <span class="font-medium text-n-slate-12">{{ m.label }}</span>
                  <span class="text-n-slate-10">{{ m.count }} · {{ m.share }}% da agenda · comparecimento {{ m.show_rate }}%</span>
                </div>
                <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full" :style="{ width: Math.max(m.share, 3) + '%', background: modColor(m.key) }" />
                </div>
              </div>
            </div>
          </div>

          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span class="i-lucide-calendar-range text-base" style="color: #0F5FA6" />
              Volume por dia da semana
            </h2>
            <div class="flex items-end gap-2 h-32">
              <div v-for="w in data.by_weekday" :key="w.dow" class="flex-1 flex flex-col items-center gap-1">
                <span class="text-xs font-bold text-n-slate-12">{{ w.count }}</span>
                <div
                  class="w-full rounded-t-lg transition-all"
                  :style="{ height: Math.max((w.count / maxWeekday) * 100, 4) + '%', background: 'linear-gradient(180deg, #7C3AED, #0F5FA6)' }"
                />
                <span class="text-[10px] text-n-slate-10">{{ w.label.slice(0, 3) }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Médicos e unidades -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span class="i-lucide-stethoscope text-base" style="color: #0369A1" />
              Por médico
            </h2>
            <div v-if="!data.by_doctor?.length" class="text-xs text-n-slate-10 py-4 text-center">Nenhuma consulta com médico no período.</div>
            <div v-else class="space-y-2">
              <div
                v-for="d in data.by_doctor"
                :key="d.doctor"
                class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs flex-wrap"
              >
                <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: doctorColor(d.doctor) }" />
                <span class="font-medium text-n-slate-12 flex-1 min-w-[130px]">{{ d.doctor }}</span>
                <span class="text-n-slate-10">{{ d.count }} consulta(s)</span>
                <span class="font-bold" :style="{ color: rateColor(d.show_rate) }">{{ d.show_rate }}% presença</span>
                <span class="text-n-slate-10">🎯 {{ d.indications }} indicação(ões)</span>
              </div>
            </div>
          </div>

          <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span class="i-lucide-map-pin text-base" style="color: #EA580C" />
              Por unidade
            </h2>
            <div v-if="!data.by_unit?.length" class="text-xs text-n-slate-10 py-4 text-center">Nenhuma consulta no período.</div>
            <div v-else class="space-y-3">
              <div v-for="u in data.by_unit" :key="u.key">
                <div class="flex items-center justify-between text-xs mb-1">
                  <span class="font-medium text-n-slate-12">{{ u.label }}</span>
                  <span class="text-n-slate-10">{{ u.count }} · {{ u.attended }} vieram · {{ u.missed }} faltaram</span>
                </div>
                <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div class="h-full rounded-full" :style="{ width: Math.max(u.show_rate, 3) + '%', background: 'linear-gradient(90deg, #059669, #34D399)' }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-0.5">{{ u.show_rate }}% de comparecimento</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Cirurgias -->
        <div class="bg-n-solid-2 border border-sky-400/30 rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
            <span class="i-lucide-slice text-base" style="color: #0284C7" />
            Agenda de Cirurgias
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
            <DashKpi
              compact
              label="Agendadas"
              :value="data.cirurgias?.total ?? 0"
              from="#0284C7"
              to="#7DD3FC"
              :state="goals.stateFor('surgeries_booked')"
              :goal="goals.goalFor('surgeries_booked')"
            />
            <DashKpi
              compact
              label="Realizadas"
              :value="data.cirurgias?.done ?? 0"
              from="#059669"
              to="#34D399"
              :state="goals.stateFor('surgeries_done')"
              :goal="goals.goalFor('surgeries_done')"
            />
            <DashKpi
              compact
              label="Não veio"
              :value="data.cirurgias?.missed ?? 0"
              value-color="#EF4444"
            />
            <DashKpi
              compact
              label="⚠️ Veio e não fez"
              :value="data.cirurgias?.attended_not_done ?? 0"
              value-color="#F59E0B"
            />
          </div>
          <div v-if="data.cirurgias?.by_location?.length" class="flex flex-wrap gap-2">
            <span
              v-for="l in data.cirurgias.by_location"
              :key="l.key"
              class="text-xs px-3 py-1.5 rounded-full bg-n-alpha-1 text-n-slate-11"
            >
              {{ l.label }}: <b class="text-n-slate-12">{{ l.count }}</b>
            </span>
          </div>
        </div>

        <!-- Ocupação + próximos 7 dias -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-gauge text-base" style="color: #D4A017" />
            Ocupação e o que vem pela frente
          </h2>
          <p class="text-xs text-n-slate-10 mb-4">pelas janelas dos médicos e da sala cirúrgica (cadeados fora da conta) — independente do período acima</p>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
            <div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Agenda cheia <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                <span class="font-bold text-n-slate-12">{{ fillNext7.total ? fillNext7.pct + '%' : '—' }}</span>
              </div>
              <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: Math.max(fillNext7.pct, 3) + '%', background: 'linear-gradient(90deg, #0F5FA6, #7C3AED)' }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">{{ fillNext7.filled }} de {{ fillNext7.total }} blocos</p>
            </div>
            <div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Aproveitamento <span class="text-n-slate-9">(últimos 7 dias)</span></span>
                <span class="font-bold text-n-slate-12">{{ usageLast7.total ? usageLast7.pct + '%' : '—' }}</span>
              </div>
              <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: Math.max(usageLast7.pct, 3) + '%', background: 'linear-gradient(90deg, #B8860B, #D4A017)' }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">blocos que viraram consulta</p>
            </div>
            <div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Sala cirúrgica cheia <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                <span class="font-bold text-n-slate-12">{{ surgFillNext7.total ? surgFillNext7.pct + '%' : '—' }}</span>
              </div>
              <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: Math.max(surgFillNext7.pct, 3) + '%', background: 'linear-gradient(90deg, #0284C7, #7DD3FC)' }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">{{ surgFillNext7.total ? `${surgFillNext7.filled} de ${surgFillNext7.total} blocos` : 'sem janelas da sala' }}</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <span class="text-xs px-3 py-1.5 rounded-full bg-n-alpha-1 text-n-slate-11">
              📅 Próximos 7 dias: <b class="text-n-slate-12">{{ data.upcoming?.consultas_next7 ?? 0 }}</b> consulta(s) · <b class="text-n-slate-12">{{ data.upcoming?.cirurgias_next7 ?? 0 }}</b> cirurgia(s)
            </span>
            <span
              class="text-xs px-3 py-1.5 rounded-full"
              :class="(data.upcoming?.unconfirmed_past ?? 0) > 0 ? 'bg-red-500/10 text-red-500 font-medium' : 'bg-n-alpha-1 text-n-slate-11'"
            >
              ✅ Conferência pendente (30d): <b>{{ data.upcoming?.unconfirmed_past ?? 0 }}</b>
            </span>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
