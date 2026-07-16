<script setup>
// Dashboard dos AGENTES (análise do gestor): desempenho de cada pessoa do
// time — conversas, tempo de 1ª resposta, resoluções, consultas agendadas
// e a responsividade aos avisos do Radar de Oportunidades. Serve de base
// para orientações, feedbacks e treinamentos.
import { ref, onMounted } from 'vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

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
    const { data: payload } = await CrmAPI.getAgentsDashboard({ preset: selectedPeriod.value });
    data.value = payload;
  } catch {
    data.value = data.value || { agents: [], radar: {} };
  } finally {
    isLoading.value = false;
  }
};

const setPeriod = key => {
  selectedPeriod.value = key;
  fetchData();
};

const medal = i => ['🥇', '🥈', '🥉'][i] || `${i + 1}º`;

// cores: rápido = verde, ok = dourado, lento = vermelho
const speedColor = min => {
  if (min === null || min === undefined) return '#94A3B8';
  if (min <= 5) return '#059669';
  if (min <= 20) return '#D4A017';
  return '#DC2626';
};
const rateColor = pct => {
  if (pct >= 80) return '#059669';
  if (pct >= 50) return '#D4A017';
  return '#DC2626';
};
const fmtMin = min => {
  if (min === null || min === undefined) return '—';
  if (min < 60) return `${min}min`;
  return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')}`;
};

onMounted(fetchData);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #7C3AED, #A78BFA)">
          <span class="i-lucide-users text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard dos Agentes</h1>
          <p class="text-xs text-n-slate-10">desempenho de cada pessoa do time · base para feedbacks e treinamentos</p>
        </div>
      </div>

      <!-- Período -->
      <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto mb-6">
        <button
          v-for="p in PERIODS"
          :key="p.key"
          class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
          :class="selectedPeriod === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="selectedPeriod === p.key ? { background: 'linear-gradient(135deg, #7C3AED, #A78BFA)' } : {}"
          @click="setPeriod(p.key)"
        >
          {{ p.label }}
        </button>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- 📡 Responsividade ao Radar (visão geral) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-radar text-base" style="color: #EA580C" />
            Resposta aos avisos do Radar de Oportunidades
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">
            de cada aviso que o Radar acendeu, a 1ª mensagem enviada ao paciente DEPOIS do aviso conta como a resposta
          </p>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #EA580C, #FB923C)">
              <p class="text-[11px] font-medium text-white/80">Avisos no período</p>
              <p class="text-2xl font-bold leading-tight">{{ data.radar?.total_alerts ?? 0 }}</p>
            </div>
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #0F5FA6, #38BDF8)">
              <p class="text-[11px] font-medium text-white/80">Respondidos</p>
              <p class="text-2xl font-bold leading-tight">{{ data.radar?.responded ?? 0 }}</p>
            </div>
            <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
              <p class="text-[11px] font-medium text-n-slate-10">Taxa de resposta</p>
              <p class="text-2xl font-bold leading-tight" :style="{ color: rateColor(data.radar?.response_rate ?? 0) }">
                {{ data.radar?.response_rate ?? 0 }}%
              </p>
            </div>
            <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
              <p class="text-[11px] font-medium text-n-slate-10">Tempo médio p/ responder</p>
              <p class="text-2xl font-bold leading-tight" :style="{ color: speedColor(data.radar?.avg_response_min) }">
                {{ fmtMin(data.radar?.avg_response_min) }}
              </p>
            </div>
          </div>

          <!-- por painel de destino -->
          <div v-if="data.radar?.by_target?.length" class="space-y-2">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">Por painel de destino do aviso</p>
            <div
              v-for="t in data.radar.by_target"
              :key="t.user_id ?? 'geral'"
              class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs flex-wrap"
            >
              <span class="font-medium text-n-slate-12 flex-1 min-w-[120px]">📌 {{ t.user_name || 'Todos os painéis' }}</span>
              <span class="text-n-slate-10">{{ t.responded }} de {{ t.total }} respondidos</span>
              <span class="font-bold" :style="{ color: rateColor(t.response_rate) }">{{ t.response_rate }}%</span>
              <span class="text-n-slate-10">tempo médio <b :style="{ color: speedColor(t.avg_response_min) }">{{ fmtMin(t.avg_response_min) }}</b></span>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">Nenhum aviso do Radar no período — ligue o Radar e configure as vigias em Automações → Agentes de IA.</p>
        </div>

        <!-- 👥 Métricas por pessoa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-user-round-check text-base" style="color: #7C3AED" />
            Desempenho por pessoa
          </h2>
          <p class="text-xs text-n-slate-10 mb-5">
            ordenado por volume de mensagens enviadas · "Radar" = avisos em que a pessoa foi quem respondeu ao paciente
          </p>

          <div v-if="!data.agents?.length" class="text-center py-10 text-n-slate-10 text-sm">
            Nenhuma atividade da equipe no período.
          </div>

          <div v-else class="space-y-3">
            <div
              v-for="(row, i) in data.agents"
              :key="row.id"
              class="rounded-2xl border-2 border-violet-400/30 bg-n-solid-1 p-4"
            >
              <div class="flex items-center gap-2 flex-wrap mb-3">
                <span class="text-lg">{{ medal(i) }}</span>
                <p class="text-sm font-bold text-n-slate-12 flex-1 truncate">{{ row.name }}</p>
                <span
                  class="text-xs font-bold text-white px-3 py-1 rounded-full"
                  style="background: linear-gradient(135deg, #7C3AED, #A78BFA)"
                >
                  {{ row.messages_sent }} mensagens
                </span>
              </div>
              <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 text-center">
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.conversations_assigned }}</p>
                  <p class="text-[10px] text-n-slate-10">conversas atribuídas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: speedColor(row.avg_first_response_min) }">
                    {{ fmtMin(row.avg_first_response_min) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">1ª resposta (média)</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.conversations_resolved }}</p>
                  <p class="text-[10px] text-n-slate-10">resolvidas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.appointments_created }}</p>
                  <p class="text-[10px] text-n-slate-10">consultas agendadas</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold text-n-slate-12">{{ row.radar_responded }}</p>
                  <p class="text-[10px] text-n-slate-10">avisos do Radar respondidos</p>
                </div>
                <div class="rounded-xl bg-n-alpha-1 px-2 py-2">
                  <p class="text-base font-bold" :style="{ color: speedColor(row.radar_avg_response_min) }">
                    {{ fmtMin(row.radar_avg_response_min) }}
                  </p>
                  <p class="text-[10px] text-n-slate-10">tempo até responder o Radar</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
