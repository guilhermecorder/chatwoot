<script setup>
// DASHBOARD GOOGLE (Ads + GA4): as conversões que o sistema ENVIA pro
// Google (eventos das colunas do CRM: consulta realizada, cirurgia
// realizada…) — quanto mais conversões reais, mais inteligente o Google
// Ads fica. Investimento/cliques entram quando o developer token do Ads
// for conectado (mesmo caminho do painel Meta).
import { ref, computed, onMounted } from 'vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const route = useRoute();
const router = useRouter();
const isLoading = ref(true);
const data = ref(null);

const load = async () => {
  try {
    const { data: payload } = await CrmAPI.getGoogleDashboard();
    data.value = payload;
  } catch {
    data.value = { configured: false, series: [], totals_by_event: {}, automations: [] };
  } finally {
    isLoading.value = false;
  }
};

const maxDay = computed(() => Math.max(1, ...(data.value?.series || []).map(d => d.total)));
const total30 = computed(() => (data.value?.series || []).reduce((s, d) => s + d.total, 0));
const barTitle = d => {
  const date = new Date(`${d.date}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  const parts = Object.entries(d.by_event || {}).map(([e, n]) => `${e}: ${n}`).join(' · ');
  return `${date}: ${d.total} conversão(ões)${parts ? ` — ${parts}` : ''}`;
};
const goIntegrations = () => router.push(frontendURL(`accounts/${route.params.accountId}/crm-integrations`));

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-4xl mx-auto w-full p-4 sm:p-8">
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #1E40AF, #34A853)">
          <span class="i-lucide-chart-column text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Google (Ads + GA4)</h1>
          <p class="text-xs text-n-slate-10">as conversões reais que o sistema envia pro Google — combustível da inteligência dos anúncios</p>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- estado da integração -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-5">
          <div class="rounded-xl px-4 py-3 border" :class="data.configured ? 'border-emerald-500/40 bg-emerald-500/5' : 'border-amber-500/40 bg-amber-500/5'">
            <p class="text-[11px] font-medium text-n-slate-10">GA4 (Measurement Protocol)</p>
            <p class="text-sm font-bold" :style="{ color: data.configured ? '#047857' : '#B45309' }">
              {{ data.configured ? `Conectado (${data.measurement_id})` : 'Aguardando conexão' }}
            </p>
            <button v-if="!data.configured" class="text-[11px] underline decoration-dotted text-n-slate-10 hover:text-n-brand mt-1" @click="goIntegrations">
              conectar em Integrações → Google
            </button>
          </div>
          <DashKpi
            compact
            label="Conversões enviadas (30 dias)"
            :value="total30"
            from="#1E40AF"
            to="#3B82F6"
          />
          <div class="rounded-xl px-4 py-3 border border-n-weak bg-n-solid-1">
            <p class="text-[11px] font-medium text-n-slate-10">Google Ads (investimento/cliques)</p>
            <p class="text-sm font-bold" :style="{ color: data.ads_token_set ? '#047857' : '#64748B' }">
              {{ data.ads_token_set ? 'Token conectado' : 'Entra com o developer token' }}
            </p>
          </div>
        </div>

        <!-- série diária -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-3">Conversões enviadas por dia — últimos 30 dias</h2>
          <div class="flex items-end gap-[3px] h-24 rounded-lg bg-n-alpha-1 px-2 pt-2">
            <div
              v-for="d in data.series"
              :key="d.date"
              class="flex-1 rounded-t-sm"
              :style="{
                height: `${Math.max((d.total / maxDay) * 100, d.total ? 8 : 1)}%`,
                background: d.total ? 'linear-gradient(180deg, #34A853, #1E40AF)' : 'rgba(148,163,184,0.25)',
              }"
              :title="barTitle(d)"
            />
          </div>
          <div v-if="Object.keys(data.totals_by_event || {}).length" class="flex items-center gap-2 flex-wrap mt-3">
            <span
              v-for="(n, event) in data.totals_by_event"
              :key="event"
              class="text-[11px] px-2 py-0.5 rounded-full border border-n-weak bg-n-solid-1 text-n-slate-11"
            >
              {{ event }} · <b>{{ n }}</b>
            </span>
          </div>
          <p v-else class="text-xs text-n-slate-9 mt-2">nenhuma conversão enviada ainda — plugue a ação "Conversão do Google" nas colunas (consulta realizada, cirurgia realizada…).</p>
        </div>

        <!-- onde está plugado -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-2">Colunas que enviam conversão</h2>
          <template v-if="data.automations?.length">
            <div v-for="(a, ai) in data.automations" :key="ai" class="flex items-center gap-2 text-xs text-n-slate-11 mb-1">
              <span class="i-lucide-columns-3 text-sm text-n-slate-9" />
              <b class="text-n-slate-12">{{ a.stage || 'coluna' }}</b>
              <span class="i-lucide-arrow-right text-xs text-n-slate-9" />
              <span>{{ a.event || 'evento' }}</span>
            </div>
          </template>
          <p v-else class="text-xs text-n-slate-9">
            Nenhuma coluna plugada — no CRM, adicione a automação "Conversão do Google" nas colunas-chave (Consulta Realizada, Cirurgia Realizada…).
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
