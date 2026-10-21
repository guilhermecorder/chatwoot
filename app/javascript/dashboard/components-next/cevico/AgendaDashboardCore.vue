<script setup>
// MIOLO do Dashboard da Agenda: comparecimento, faltas, modalidades,
// médicos, unidades, cirurgias por clínica e ocupação. Reusado pela página
// de Relatórios E embutido no Meu Painel (item 136) — o período vem de fora.
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import CrmAPI from 'dashboard/api/crm';
import {
  DOCTORS, MODALITIES, resolveWindows, resolveBlocked, resolveBlockedDays,
  resolveSurgeryWindows, blockKey, scanAgenda,
} from 'dashboard/helper/cevicoAgenda';

// Recebe o período de FORA (Meu Painel ou página de Relatórios)
const props = defineProps({
  period: { type: Object, default: () => ({ preset: 'month', from: '', to: '' }) },
  // 🍎 formato novo (rodada 161, só no Meu Painel): glass = as caixas
  // viram sub-cartões de vidro do kit .cv-*; family = os 4 degradês do
  // dia para os KPIs coloridos. Relatórios continua com o visual próprio.
  glass: { type: Boolean, default: false },
  family: { type: Array, default: null },
  // 🍎 rodada 163 (página de Relatórios): o retorno do useCevicoPalette da
  // página. Quando vem, cada seção vira um bloco grande (cv-block) com a
  // paleta própria (pal.blockVars(id)) e os KPIs usam pal.blockFamily(id).
  // Sem ele (Meu Painel) nada muda: glass + family seguem valendo.
  pal: { type: Object, default: null },
});
// ids das seções (paleta por bloco): kpis · tipos · semana · medicos ·
// unidades · cirurgias · ocupacao
const kpiGrad = (i, blockId = 'kpis') => {
  const fam = props.pal ? props.pal.blockFamily(blockId) : props.family;
  return fam ? fam[i % fam.length] : '';
};
const secVars = blockId => (props.pal ? props.pal.blockVars(blockId) : null);
const card = computed(() => {
  if (props.pal) return 'cv-block p-5 sm:p-6';
  return props.glass ? 'cv-sub p-5' : 'bg-n-solid-2 border border-n-weak rounded-2xl p-5';
});
const iconWrap = computed(() => (props.pal ? 'cv-icon' : 'inline-flex items-center'));
const track = computed(() => (props.glass ? 'cv-track' : 'h-3 bg-n-alpha-1 rounded-full overflow-hidden'));
// com pal o ícone vai dentro do squircle .cv-icon (já branco): sem cor própria
const iconColor = c => {
  if (props.pal) return '';
  return props.glass ? 'var(--cv)' : c;
};
const barGrad = g => (props.glass ? 'var(--cv-grad-2)' : g);
const chip = computed(() => (props.glass ? 'cv-chip cv-chip-lg' : 'text-xs px-3 py-1.5 rounded-full bg-n-alpha-1 text-n-slate-11'));

const store = useStore();
const isLoading = ref(true);
const data = ref(null);

const fetchData = async () => {
  isLoading.value = true;
  try {
    const p = props.period || {};
    const { data: payload } = await CrmAPI.getAgendaDashboard({
      preset: p.preset,
      ...(p.preset === 'custom' ? { from: p.from, to: p.to } : {}),
    });
    data.value = payload;
  } catch {
    data.value = data.value || {};
  } finally {
    isLoading.value = false;
  }
};

watch(() => props.period, fetchData, { deep: true });

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
const weekdayTotal = computed(() =>
  (data.value?.by_weekday || []).reduce((sum, w) => sum + (w.count || 0), 0)
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
  <div>
      <div v-if="isLoading || !data" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- KPIs de consultas (padrão CEVICO c/ selos de recorde/meta) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6" :style="secVars('kpis')">
          <DashKpi
            compact
            label="Consultas no período"
            :value="data.consultas?.total ?? 0"
            :sub="`${data.consultas?.canceled ?? 0} cancelada(s)`"
            from="#0F5FA6"
            to="#38BDF8"
            :grad="kpiGrad(0)"
            :glass="glass"
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
            :grad="kpiGrad(1)"
            :glass="glass"
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
            :grad="kpiGrad(2)"
            :glass="glass"
          />
          <DashKpi
            compact
            label="Reagendadas / sem conferência"
            :value="`${data.consultas?.rescheduled ?? 0} / ${data.consultas?.unconfirmed ?? 0}`"
            sub="sem conferência = passou sem ✓/✗"
            :value-color="(data.consultas?.unconfirmed ?? 0) > 0 ? '#EF4444' : ''"
            :glass="glass"
          />
        </div>

        <!-- Modalidades + dias da semana -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          <div :class="card" :style="secVars('tipos')">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span :class="iconWrap"><span class="i-lucide-tags text-base" :style="{ color: iconColor('#7C3AED') }" /></span>
              Consultas por tipo
            </h2>
            <div v-if="!data.by_modality?.length" class="text-xs text-n-slate-10 py-4 text-center">Nenhuma consulta no período.</div>
            <div v-else class="space-y-3">
              <div v-for="m in data.by_modality" :key="m.key">
                <div class="flex items-center justify-between text-xs mb-1">
                  <span class="font-medium text-n-slate-12">{{ m.label }}</span>
                  <span class="text-n-slate-10">{{ m.count }} · {{ m.share }}% da agenda · comparecimento {{ m.show_rate }}%</span>
                </div>
                <div :class="track">
                  <div class="h-full rounded-full" :class="glass ? 'cv-fill' : ''" :style="{ width: Math.max(m.share, 3) + '%', background: modColor(m.key) }" />
                </div>
              </div>
            </div>
          </div>

          <div :class="card" :style="secVars('semana')">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span :class="iconWrap"><span class="i-lucide-calendar-range text-base" :style="{ color: iconColor('#0F5FA6') }" /></span>
              Volume por dia da semana
            </h2>
            <!-- barras com o dia mais cheio em destaque e a fatia da semana
                 no rótulo (varredura 12/09) -->
            <div class="flex items-end gap-2 h-32 border-b border-n-weak/70 pb-1">
              <div
                v-for="w in data.by_weekday"
                :key="w.dow"
                class="flex-1 flex flex-col items-center gap-1 h-full justify-end"
                :title="`${w.label}: ${w.count} consulta(s)`"
              >
                <span class="text-xs font-bold" :class="w.count === maxWeekday && w.count > 0 ? 'text-n-slate-12' : 'text-n-slate-10'">{{ w.count }}</span>
                <div
                  class="w-full max-w-[56px] rounded-t-lg transition-all"
                  :class="w.count === maxWeekday && w.count > 0 ? '' : 'opacity-70'"
                  :style="{ height: Math.max((w.count / maxWeekday) * 100, 3) + '%', background: glass ? 'linear-gradient(180deg, var(--cv), var(--cv-deep))' : 'linear-gradient(180deg, #8B5CF6, #0F5FA6)' }"
                />
              </div>
            </div>
            <div class="flex gap-2 mt-1">
              <span v-for="w in data.by_weekday" :key="'l' + w.dow" class="flex-1 text-center text-[10px] text-n-slate-10">
                {{ w.label.slice(0, 3) }}<template v-if="weekdayTotal"> · {{ Math.round((w.count / weekdayTotal) * 100) }}%</template>
              </span>
            </div>
          </div>
        </div>

        <!-- Médicos e unidades -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
          <div :class="card" :style="secVars('medicos')">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span :class="iconWrap"><span class="i-lucide-stethoscope text-base" :style="{ color: iconColor('#0369A1') }" /></span>
              Por médico
            </h2>
            <div v-if="!data.by_doctor?.length" class="text-xs text-n-slate-10 py-4 text-center">Nenhuma consulta com médico no período.</div>
            <div v-else class="space-y-2">
              <div
                v-for="d in data.by_doctor"
                :key="d.doctor"
                class="flex items-center gap-3 rounded-xl px-3 py-2 text-xs flex-wrap"
                :class="glass ? 'cv-row' : 'border border-n-weak bg-n-solid-1'"
              >
                <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: doctorColor(d.doctor) }" />
                <span class="font-medium text-n-slate-12 flex-1 min-w-[130px]">{{ d.doctor }}</span>
                <span class="text-n-slate-10">{{ d.count }} consulta(s)</span>
                <span class="font-bold" :style="{ color: rateColor(d.show_rate) }">{{ d.show_rate }}% presença</span>
                <span class="text-n-slate-10">🎯 {{ d.indications }} indicação(ões)</span>
              </div>
            </div>
          </div>

          <div :class="card" :style="secVars('unidades')">
            <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
              <span :class="iconWrap"><span class="i-lucide-map-pin text-base" :style="{ color: iconColor('#EA580C') }" /></span>
              Por unidade
            </h2>
            <div v-if="!data.by_unit?.length" class="text-xs text-n-slate-10 py-4 text-center">Nenhuma consulta no período.</div>
            <div v-else class="space-y-3">
              <div v-for="u in data.by_unit" :key="u.key">
                <div class="flex items-center justify-between text-xs mb-1">
                  <span class="font-medium text-n-slate-12">{{ u.label }}</span>
                  <span class="text-n-slate-10">{{ u.count }} · {{ u.attended }} vieram · {{ u.missed }} faltaram</span>
                </div>
                <div :class="track">
                  <div class="h-full rounded-full" :class="glass ? 'cv-fill' : ''" :style="{ width: Math.max(u.show_rate, 3) + '%', background: barGrad('linear-gradient(90deg, #059669, #34D399)') }" />
                </div>
                <p class="text-[10px] text-n-slate-9 mt-0.5">{{ u.show_rate }}% de comparecimento</p>
              </div>
            </div>
          </div>
        </div>

        <!-- Cirurgias -->
        <div :class="card" class="mb-6" :style="secVars('cirurgias')">
          <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
            <span :class="iconWrap"><span class="i-lucide-slice text-base" :style="{ color: iconColor('#0284C7') }" /></span>
            Agenda de Cirurgias
          </h2>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
            <DashKpi
              compact
              label="Agendadas"
              :value="data.cirurgias?.total ?? 0"
              from="#0284C7"
              to="#7DD3FC"
              :grad="kpiGrad(0, 'cirurgias')"
              :glass="glass"
              :state="goals.stateFor('surgeries_booked')"
              :goal="goals.goalFor('surgeries_booked')"
            />
            <DashKpi
              compact
              label="Realizadas"
              :value="data.cirurgias?.done ?? 0"
              from="#059669"
              to="#34D399"
              :grad="kpiGrad(1, 'cirurgias')"
              :glass="glass"
              :state="goals.stateFor('surgeries_done')"
              :goal="goals.goalFor('surgeries_done')"
            />
            <DashKpi
              compact
              label="Não veio"
              :value="data.cirurgias?.missed ?? 0"
              value-color="#EF4444"
              :glass="glass"
            />
            <DashKpi
              compact
              label="Veio e não fez"
              :value="data.cirurgias?.attended_not_done ?? 0"
              value-color="#F59E0B"
              :glass="glass"
            />
          </div>
          <div v-if="data.cirurgias?.by_location?.length" class="flex flex-wrap gap-2">
            <span
              v-for="l in data.cirurgias.by_location"
              :key="l.key"
              :class="chip"
            >
              {{ l.label }}: <b class="text-n-slate-12">{{ l.count }}</b>
            </span>
          </div>
        </div>

        <!-- Ocupação + próximos 7 dias -->
        <div :class="card" class="mb-6" :style="secVars('ocupacao')">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span :class="iconWrap"><span class="i-lucide-gauge text-base" :style="{ color: iconColor('#D4A017') }" /></span>
            Ocupação e o que vem pela frente
          </h2>
          <p class="text-xs text-n-slate-10 mb-4">pelas janelas dos médicos e da sala cirúrgica (cadeados fora da conta) — independente do período acima</p>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
            <div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Agenda cheia <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                <span class="font-bold text-n-slate-12">{{ fillNext7.total ? fillNext7.pct + '%' : '—' }}</span>
              </div>
              <div :class="track">
                <div class="h-full rounded-full" :class="glass ? 'cv-fill' : ''" :style="{ width: Math.max(fillNext7.pct, 3) + '%', background: barGrad('linear-gradient(90deg, #0F5FA6, #7C3AED)') }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">{{ fillNext7.filled }} de {{ fillNext7.total }} blocos</p>
            </div>
            <div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Aproveitamento <span class="text-n-slate-9">(últimos 7 dias)</span></span>
                <span class="font-bold text-n-slate-12">{{ usageLast7.total ? usageLast7.pct + '%' : '—' }}</span>
              </div>
              <div :class="track">
                <div class="h-full rounded-full" :class="glass ? 'cv-fill' : ''" :style="{ width: Math.max(usageLast7.pct, 3) + '%', background: barGrad('linear-gradient(90deg, #B8860B, #D4A017)') }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">blocos que viraram consulta</p>
            </div>
            <div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Sala cirúrgica cheia <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                <span class="font-bold text-n-slate-12">{{ surgFillNext7.total ? surgFillNext7.pct + '%' : '—' }}</span>
              </div>
              <div :class="track">
                <div class="h-full rounded-full" :class="glass ? 'cv-fill' : ''" :style="{ width: Math.max(surgFillNext7.pct, 3) + '%', background: barGrad('linear-gradient(90deg, #0284C7, #7DD3FC)') }" />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-0.5">{{ surgFillNext7.total ? `${surgFillNext7.filled} de ${surgFillNext7.total} blocos` : 'sem janelas da sala' }}</p>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <span :class="chip">
              Próximos 7 dias: <b class="text-n-slate-12">{{ data.upcoming?.consultas_next7 ?? 0 }}</b> consulta(s) · <b class="text-n-slate-12">{{ data.upcoming?.cirurgias_next7 ?? 0 }}</b> cirurgia(s)
            </span>
            <span
              :class="[chip, (data.upcoming?.unconfirmed_past ?? 0) > 0 ? (glass ? 'cv-red' : 'text-xs px-3 py-1.5 rounded-full bg-red-500/10 text-red-500 font-medium') : '']"
            >
              Conferência pendente (30d): <b>{{ data.upcoming?.unconfirmed_past ?? 0 }}</b>
            </span>
          </div>
        </div>
      </template>
  </div>
</template>
