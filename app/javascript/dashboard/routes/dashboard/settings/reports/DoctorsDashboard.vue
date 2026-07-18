<script setup>
// Dashboard dos MÉDICOS (análise do gestor): quem mais converte consulta em
// cirurgia, indicações, comparecimento, NPS dos pacientes de cada médico e
// o volume de cirurgias por clínica parceira (IOP, Ocular Surgery...).
import { ref, computed, onMounted } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import CrmAPI from 'dashboard/api/crm';
import { DOCTORS } from 'dashboard/helper/cevicoAgenda';

const isLoading = ref(true);
const data = ref(null);

const PERIODS = [
  { key: 'week', label: 'Essa semana' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
  { key: 'year', label: 'Este ano' },
  { key: 'all', label: 'Desde o início' },
];
const selectedPeriod = ref('month');

const fetchData = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getDoctorsDashboard({ preset: selectedPeriod.value });
    data.value = payload;
  } catch {
    data.value = data.value || { doctors: [], surgeries_by_clinic: [] };
  } finally {
    isLoading.value = false;
  }
};

const setPeriod = key => {
  selectedPeriod.value = key;
  fetchData();
};

const doctorColor = name => DOCTORS.find(d => d.name === name)?.color || '#64748B';
const medal = i => ['🥇', '🥈', '🥉'][i] || `${i + 1}º`;
const fmtBRL = v =>
  Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

const npsColor = avg => {
  if (avg === null || avg === undefined) return '#94A3B8';
  if (avg >= 9) return '#059669';
  if (avg >= 7) return '#D4A017';
  return '#DC2626';
};

// resumo geral do período (soma dos médicos) c/ metas oficiais do mês
const goals = useCevicoGoals();
const totals = computed(() => {
  const rows = data.value?.doctors || [];
  const sum = key => rows.reduce((s, r) => s + Number(r[key] || 0), 0);
  return {
    consultations: sum('consultations'),
    conversions: sum('conversions'),
    surgeriesDone: sum('surgeries_done'),
    revenue: sum('revenue'),
  };
});

onMounted(() => {
  fetchData();
  goals.load();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #0369A1, #38BDF8)">
          <span class="i-lucide-stethoscope text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard dos Médicos</h1>
          <p class="text-xs text-n-slate-10">quem mais converte consulta em cirurgia · indicações · NPS · cirurgias por clínica</p>
        </div>
      </div>

      <!-- Período -->
      <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto mb-6">
        <button
          v-for="p in PERIODS"
          :key="p.key"
          class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
          :class="selectedPeriod === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="selectedPeriod === p.key ? { background: 'linear-gradient(135deg, #0369A1, #38BDF8)' } : {}"
          @click="setPeriod(p.key)"
        >
          {{ p.label }}
        </button>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- 📈 Resumo do período (c/ selos de recorde/meta do mês) -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          <DashKpi
            compact
            label="Consultas realizadas"
            :value="totals.consultations"
            from="#0369A1"
            to="#38BDF8"
            :state="goals.stateFor('consultations_attended')"
            :goal="goals.goalFor('consultations_attended')"
          />
          <DashKpi
            compact
            label="Viraram cirurgia"
            :value="totals.conversions"
            from="#5B21B6"
            to="#7C3AED"
          />
          <DashKpi
            compact
            label="Cirurgias realizadas"
            :value="totals.surgeriesDone"
            from="#059669"
            to="#34D399"
            :state="goals.stateFor('surgeries_done')"
            :goal="goals.goalFor('surgeries_done')"
          />
          <DashKpi
            compact
            label="Faturamento gerado"
            :value="Math.round(totals.revenue)"
            prefix="R$ "
            from="#065F46"
            to="#10B981"
            :state="goals.stateFor('revenue_closed')"
            :goal="goals.goalFor('revenue_closed')"
          />
        </div>

        <!-- 🏆 Ranking de conversão -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-trophy text-base" style="color: #D4A017" />
            Conversão de consulta em cirurgia — ranking
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">
            conversão = pacientes que o médico INDICOU e que têm cirurgia marcada (rastreado pelo telefone do contato)
          </p>

          <div v-if="!data.doctors?.length" class="text-center py-10 text-n-slate-10 text-sm">
            Nenhuma consulta com médico no período — os dados vêm da conferência do dia na Agenda.
          </div>

          <div v-else class="space-y-3">
            <div
              v-for="(row, i) in data.doctors"
              :key="row.doctor"
              class="rounded-2xl border-2 bg-n-solid-1 p-4"
              :style="{ borderColor: doctorColor(row.doctor) + '40' }"
            >
              <!-- nome nunca vira "Dr. …": quebra linha no celular em vez de truncar -->
              <div class="flex items-center gap-2 flex-wrap mb-3">
                <span class="text-lg">{{ medal(i) }}</span>
                <span class="w-2.5 h-2.5 rounded-full flex-shrink-0" :style="{ backgroundColor: doctorColor(row.doctor) }" />
                <p class="text-sm font-bold text-n-slate-12 flex-1 min-w-[140px] break-words">{{ row.doctor }}</p>
                <span
                  class="text-xs font-bold text-white px-3 py-1 rounded-full whitespace-nowrap"
                  :style="{ background: `linear-gradient(135deg, ${doctorColor(row.doctor)}, ${doctorColor(row.doctor)}99)` }"
                >
                  {{ row.conversion_rate }}% de conversão
                </span>
              </div>
              <div class="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3 text-center">
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.consultations }}</p>
                  <p class="text-[10px] text-n-slate-10">consultas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.show_rate }}%</p>
                  <p class="text-[10px] text-n-slate-10">comparecimento</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.indications }}</p>
                  <p class="text-[10px] text-n-slate-10">indicações ({{ row.indication_rate }}%)</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.conversions }}</p>
                  <p class="text-[10px] text-n-slate-10">viraram cirurgia</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.surgeries_done }}</p>
                  <p class="text-[10px] text-n-slate-10">cirurgias realizadas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: npsColor(row.nps_avg) }">
                    {{ row.nps_avg === null ? '—' : row.nps_avg }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">NPS médio ({{ row.nps_count }})</p>
                </div>
                <div class="rounded-xl px-2 py-2 text-white" style="background: linear-gradient(135deg, #065F46, #10B981)">
                  <p class="text-sm font-bold leading-tight">{{ fmtBRL(row.revenue) }}</p>
                  <p class="text-[10px] text-white/80">faturamento gerado</p>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 🏥 Cirurgias por clínica parceira -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-building-2 text-base" style="color: #0284C7" />
            Volume de cirurgias por clínica
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">IOP (geralmente PRK) · Ocular Surgery (geralmente Lasik) — no período selecionado</p>

          <div v-if="!data.surgeries_by_clinic?.length" class="text-center py-8 text-n-slate-10 text-sm">
            Nenhuma cirurgia agendada no período.
          </div>
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div
              v-for="c in data.surgeries_by_clinic"
              :key="c.key"
              class="rounded-2xl p-5 text-white shadow-lg"
              style="background: linear-gradient(135deg, #0284C7, #38BDF8)"
            >
              <p class="text-xs font-medium text-white/80 mb-1">{{ c.label }}</p>
              <p class="text-3xl font-bold">{{ c.count }}</p>
              <p class="text-[11px] text-white/70 mt-1">
                {{ c.done }} realizada(s)
                <template v-if="c.nps_avg !== null && c.nps_avg !== undefined">
                  · NPS {{ c.nps_avg }} ({{ c.nps_count }})
                </template>
              </p>
            </div>
          </div>
          <p class="text-[10px] text-n-slate-9 mt-4 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            A ocupação da sala cirúrgica (dia/semana/mês) fica na Agenda → trilho Cirurgias, seguindo as janelas configuradas.
          </p>
        </div>

        <!-- 🏢 Consultas por UNIDADE (Tatuapé / Av. Paulista) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-map-pin text-base" style="color: #EA580C" />
            Consultas por unidade
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">volume e taxa de comparecimento em cada unidade da clínica</p>

          <div v-if="!data.consultations_by_unit?.length" class="text-center py-6 text-n-slate-10 text-sm">
            Nenhuma consulta no período.
          </div>
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div
              v-for="u in data.consultations_by_unit"
              :key="u.key"
              class="rounded-2xl border border-n-weak bg-n-solid-1 p-4"
            >
              <div class="flex items-center gap-2 mb-2">
                <p class="text-sm font-bold text-n-slate-12 flex-1">{{ u.label }}</p>
                <span class="text-xl font-bold text-n-slate-12">{{ u.count }}</span>
                <span class="text-[10px] text-n-slate-9">consultas</span>
              </div>
              <div class="flex items-center justify-between text-xs mb-1">
                <span class="text-n-slate-11">Comparecimento</span>
                <span class="font-bold text-n-slate-12">{{ u.show_rate }}%</span>
              </div>
              <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                <div
                  class="h-full rounded-full"
                  :style="{ width: Math.max(u.show_rate, 3) + '%', background: 'linear-gradient(90deg, #059669, #34D399)' }"
                />
              </div>
              <p class="text-[10px] text-n-slate-9 mt-1">{{ u.attended }} compareceram · {{ u.missed }} faltaram</p>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
