<script setup>
// DASHBOARD DOS AGENTES DE IA (item 85, só admin): um card por agente —
// quem está ligado, o que cada um faz, quantas vezes trabalhou no
// período, custo, última atividade e o ritmo diário (14 dias).
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const data = ref(null);
// régua de período PADRÃO CEVICO (06/08) — default 'last7' (antes: 7 dias)
const period = ref({ preset: 'last7', from: '', to: '' });

const load = async () => {
  isLoading.value = true;
  try {
    const params = {
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
    };
    const { data: payload } = await CrmAPI.getAiDashboard(params);
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar o painel dos agentes.');
  } finally {
    isLoading.value = false;
  }
};
watch(period, load, { deep: true });
onMounted(load);

const totals = computed(() => data.value?.totals || {});
const agents = computed(() => data.value?.agents || []);

const MODEL_LABEL = {
  'claude-opus-4-8': 'Opus',
  'claude-sonnet-5': 'Sonnet',
  'claude-haiku-4-5': 'Haiku',
};

const fmtCost = v => {
  const n = Number(v || 0);
  if (n === 0) return 'US$ 0';
  if (n < 0.01) return '< US$ 0,01';
  return `US$ ${n.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}`;
};

// "há 2h", "há 3d" — atividade recente sem precisar ler data
const ago = iso => {
  if (!iso) return 'nunca rodou';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'agora mesmo';
  if (mins < 60) return `há ${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `há ${hours}h`;
  return `há ${Math.floor(hours / 24)}d`;
};

const sparkMax = agent => Math.max(...(agent.daily || [1]), 1);
</script>

<template>
  <div class="max-w-4xl">
    <!-- período — régua padrão CEVICO -->
    <div class="mb-4">
      <PeriodRuler v-model="period" />
    </div>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- totais do período -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-5">
        <div class="rounded-2xl border border-n-weak bg-n-card p-4">
          <p class="text-[11px] font-bold text-n-slate-11 mb-1">Trabalhos no período</p>
          <p class="text-2xl font-bold tabular-nums" style="color: #DB2777">{{ totals.calls || 0 }}</p>
          <p class="text-[10px] text-n-slate-9 mt-0.5">chamadas de IA</p>
        </div>
        <div class="rounded-2xl border border-n-weak bg-n-card p-4">
          <p class="text-[11px] font-bold text-n-slate-11 mb-1">Custo do período</p>
          <p class="text-2xl font-bold tabular-nums" style="color: #B8860B">{{ fmtCost(totals.cost_usd) }}</p>
          <p class="text-[10px] text-n-slate-9 mt-0.5">estimado (tokens)</p>
        </div>
        <div class="rounded-2xl border border-n-weak bg-n-card p-4">
          <p class="text-[11px] font-bold text-n-slate-11 mb-1">Agentes ligados</p>
          <p class="text-2xl font-bold tabular-nums" style="color: #059669">{{ totals.active_agents || 0 }}<span class="text-sm text-n-slate-9"> / {{ agents.length }}</span></p>
          <p class="text-[10px] text-n-slate-9 mt-0.5">interruptor definitivo</p>
        </div>
        <div class="rounded-2xl border border-n-weak bg-n-card p-4">
          <p class="text-[11px] font-bold text-n-slate-11 mb-1">Mais ativo</p>
          <p class="text-sm font-bold leading-tight mt-1.5" style="color: #7C3AED">{{ totals.top_agent || '—' }}</p>
          <p class="text-[10px] text-n-slate-9 mt-0.5">no período</p>
        </div>
      </div>

      <!-- um card por agente -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-6">
        <div
          v-for="agent in agents"
          :key="agent.key"
          class="rounded-2xl border border-n-weak bg-n-card p-4"
          :class="agent.enabled ? '' : 'opacity-60'"
        >
          <div class="flex items-center gap-2.5 mb-1.5">
            <span class="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0" :style="{ background: agent.color }">
              <span :class="agent.icon" class="text-white text-base" />
            </span>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-bold text-n-slate-12 leading-tight flex items-center gap-1.5">
                {{ agent.name }}
                <span
                  v-if="agent.responder"
                  class="text-[8px] font-black uppercase px-1.5 py-0.5 rounded-full"
                  style="background: rgba(219, 39, 119, 0.12); color: #DB2777"
                  title="Este agente FALA com o paciente"
                >fala c/ paciente</span>
              </p>
              <p class="text-[10px] text-n-slate-9 leading-snug">{{ agent.what }}</p>
            </div>
            <span
              class="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
              :style="agent.enabled
                ? { background: 'rgba(5, 150, 105, 0.12)', color: '#059669' }
                : { background: 'rgba(100, 116, 139, 0.14)', color: '#64748B' }"
            >
              <span class="w-1.5 h-1.5 rounded-full" :style="{ background: agent.enabled ? '#059669' : '#94A3B8' }" />
              {{ agent.enabled ? 'ligado' : 'desligado' }}
            </span>
          </div>

          <div class="flex items-end gap-4 mt-2.5">
            <div>
              <p class="text-lg font-bold tabular-nums leading-none" :style="{ color: agent.color }">{{ agent.calls }}</p>
              <p class="text-[9px] text-n-slate-9 mt-0.5">trabalhos</p>
            </div>
            <div>
              <p class="text-xs font-bold tabular-nums text-n-slate-11 leading-none mt-1">{{ fmtCost(agent.cost_usd) }}</p>
              <p class="text-[9px] text-n-slate-9 mt-0.5">custo</p>
            </div>
            <div class="flex-1" />
            <!-- ritmo diário (14 dias) -->
            <div class="flex items-end gap-px h-7" :title="`ritmo diário (14 dias): ${(agent.daily || []).join(', ')}`">
              <div
                v-for="(count, di) in agent.daily.length ? agent.daily : Array(14).fill(0)"
                :key="di"
                class="rounded-sm"
                style="width: 5px"
                :style="{
                  height: `${count ? Math.max((count / sparkMax(agent)) * 100, 18) : 6}%`,
                  background: count ? agent.color : 'rgba(120, 140, 180, 0.2)',
                }"
              />
            </div>
          </div>

          <div class="flex items-center gap-2 mt-2 pt-2 border-t border-n-weak">
            <span class="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-n-alpha-1 text-n-slate-11">
              {{ MODEL_LABEL[agent.model] || agent.model }}
            </span>
            <span class="text-[10px] text-n-slate-9 ml-auto">
              <span class="i-lucide-clock text-[9px]" />
              última atividade: <b class="text-n-slate-11">{{ ago(agent.last_call_at) }}</b>
            </span>
          </div>
        </div>
      </div>

      <p class="text-[11px] text-n-slate-9 mb-6">
        💡 Custo estimado pelos tokens de cada chamada. Para ligar/desligar um agente ou editar o prompt,
        use a aba <b>Agentes de IA</b> aqui do lado.
        <template v-if="data.extras?.mentor_feedbacks_30d">
          · Mentor escreveu <b>{{ data.extras.mentor_feedbacks_30d }}</b> feedback(s) nos últimos 30 dias.
        </template>
      </p>
    </template>
  </div>
</template>
