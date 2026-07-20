<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const period = ref(30);
const data = ref(null);
const isLoading = ref(false);
const hasError = ref(false);

const PERIODS = [
  { value: 7, label: '7 dias' },
  { value: 30, label: '30 dias' },
  { value: 90, label: '90 dias' },
  { value: 180, label: '6 meses' },
];

// período PERSONALIZADO (item 84): De/Até direto na linha de períodos
const isCustom = ref(false);
const customFrom = ref('');
const customTo = ref('');

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const params = isCustom.value && customFrom.value
      ? { from: customFrom.value, to: customTo.value || undefined }
      : { period: period.value };
    const { data: response } = await CrmAPI.getTrafficReport(params);
    data.value = response;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(period, () => {
  isCustom.value = false;
  load();
});
watch([customFrom, customTo], () => {
  if (isCustom.value && customFrom.value) load();
});

const formatCurrency = v =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

const formatNumber = v => Number(v || 0).toLocaleString('pt-BR');

const formatDuration = seconds => {
  if (!seconds || seconds <= 0) return '—';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  const mins = Math.round(seconds / 60);
  if (mins < 60) return `${mins}min`;
  const h = Math.floor(mins / 60);
  return `${h}h ${mins % 60}min`;
};

// ── Funil: ads (alcance, cliques) + conversas + etapas do CRM ─────────
const funnelRows = computed(() => {
  if (!data.value) return [];
  const rows = [];
  const ads = data.value.ads ?? {};

  if (ads.configured && !ads.error) {
    rows.push({ key: 'reach', name: 'Alcance', count: ads.reach, color: '#0F5FA6', source: 'Meta Ads' });
    rows.push({ key: 'clicks', name: 'Cliques no link', count: ads.link_clicks, color: '#2781F6', source: 'Meta Ads' });
  }

  rows.push({
    key: 'conversations',
    name: 'Conversas iniciadas',
    count: data.value.conversations_started,
    color: '#12A594',
    source: 'WhatsApp',
  });

  (data.value.funnel_stages ?? []).forEach(stage => {
    rows.push({
      key: `stage-${stage.stage_id}`,
      name: stage.name,
      count: stage.count,
      color: stage.color || '#6B7280',
      source: 'CRM',
    });
  });

  const max = Math.max(...rows.map(r => r.count), 1);
  return rows.map((row, index) => {
    const previous = index > 0 ? rows[index - 1].count : null;
    const rate = previous ? (row.count / previous) * 100 : null;
    return {
      ...row,
      width: Math.max((row.count / max) * 100, 4),
      rate: rate ? rate.toFixed(1) : null,
      gain: rate !== null && rate >= 100, // ganho (entrou mais do que a etapa anterior)
    };
  });
});

const cpl = computed(() => {
  const ads = data.value?.ads;
  const conversations = data.value?.conversations_started;
  if (!ads?.configured || ads.error || !conversations) return null;
  return ads.spend / conversations;
});
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto p-8 bg-n-surface-1">
    <!-- Header -->
    <div class="flex items-center gap-4 mb-8 flex-wrap">
      <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #22D3EE)">
        <span class="i-lucide-filter text-white text-lg" />
      </span>
      <div>
        <h1 class="text-lg font-bold text-n-slate-12">Funil de Tráfego</h1>
        <p class="text-xs text-n-slate-10 mt-0.5">
          Do anúncio à cirurgia: Meta Ads → WhatsApp → jornada no CRM
        </p>
      </div>
      <div class="flex-1" />
      <div class="flex items-center gap-1.5 bg-n-solid-2 border border-n-weak rounded-xl p-1 flex-wrap">
        <button
          v-for="p in PERIODS"
          :key="p.value"
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="!isCustom && period === p.value ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="period = p.value"
        >{{ p.label }}</button>
        <button
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="isCustom ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="isCustom = true"
        >Personalizado</button>
        <template v-if="isCustom">
          <input
            v-model="customFrom"
            type="date"
            class="h-[30px] text-xs border border-n-weak rounded-full px-2.5 bg-n-solid-1 text-n-slate-12"
            style="width: 8.2rem"
            title="De"
          />
          <span class="text-[10px] text-n-slate-9">até</span>
          <input
            v-model="customTo"
            type="date"
            class="h-[30px] text-xs border border-n-weak rounded-full px-2.5 bg-n-solid-1 text-n-slate-12"
            style="width: 8.2rem"
            title="Até (vazio = hoje)"
          />
        </template>
      </div>
    </div>

    <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

    <div v-else-if="hasError" class="text-center py-16 text-sm text-n-slate-10">
      Erro ao carregar o relatório. Tente novamente.
    </div>

    <template v-else-if="data">
      <!-- Aviso de configuração dos anúncios -->
      <div
        v-if="!data.ads?.configured"
        class="mb-5 text-xs text-amber-700 bg-amber-500/10 border border-amber-500/30 rounded-2xl p-5 max-w-3xl"
      >
        <p class="font-semibold mb-1">Meta Ads não conectado ao funil</p>
        <p>
          Para ver investimento, alcance e cliques: abra o <b>CRM → Integrações → Meta Ads</b> e
          preencha o <b>token de acesso</b> e o <b>ID da conta de anúncios</b> (começa com act_).
          As etapas do WhatsApp e do CRM abaixo já funcionam sem isso.
        </p>
      </div>
      <div
        v-else-if="data.ads?.error"
        class="mb-5 text-xs text-red-600 bg-red-500/10 border border-red-500/30 rounded-2xl p-5 max-w-3xl"
      >
        <p class="font-semibold mb-1">Erro ao consultar o Meta Ads</p>
        <p>{{ data.ads.error }}</p>
      </div>

      <!-- KPIs de investimento -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 max-w-4xl mb-6">
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <p class="text-xs text-n-slate-10">Investimento</p>
          <p class="text-xl font-bold text-n-slate-12">
            {{ data.ads?.configured && !data.ads?.error ? formatCurrency(data.ads.spend) : '—' }}
          </p>
          <p class="text-xs text-n-slate-9 mt-0.5">Meta Ads no período</p>
        </div>
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <p class="text-xs text-n-slate-10">Alcance</p>
          <p class="text-xl font-bold text-n-slate-12">
            {{ data.ads?.configured && !data.ads?.error ? formatNumber(data.ads.reach) : '—' }}
          </p>
          <p class="text-xs text-n-slate-9 mt-0.5">pessoas alcançadas</p>
        </div>
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <p class="text-xs text-n-slate-10">Conversas iniciadas</p>
          <p class="text-xl font-bold text-n-brand">{{ formatNumber(data.conversations_started) }}</p>
          <p class="text-xs text-n-slate-9 mt-0.5">no período</p>
        </div>
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <p class="text-xs text-n-slate-10">Custo por conversa</p>
          <p class="text-xl font-bold text-n-gold">{{ cpl ? formatCurrency(cpl) : '—' }}</p>
          <p class="text-xs text-n-slate-9 mt-0.5">investimento ÷ conversas</p>
        </div>
      </div>

      <!-- Funil SIMÉTRICO (item 84): barras centralizadas como um funil de
           verdade, preenchimento suave com brilho (estilo barra do
           formulário) e queda × ganho bem diferentes -->
      <div class="bg-n-solid-2 border border-n-weak rounded-xl p-5 max-w-4xl mb-6">
        <p class="text-xs font-semibold text-n-slate-11 mb-6">Funil completo</p>
        <div class="space-y-1.5">
          <div v-for="row in funnelRows" :key="row.key" class="flex items-center gap-3">
            <div class="w-44 text-right flex-shrink-0">
              <p class="text-xs text-n-slate-12 font-medium truncate">{{ row.name }}</p>
              <p class="text-[10px] text-n-slate-9">{{ row.source }}</p>
            </div>
            <div class="flex-1 flex justify-center min-w-0">
              <div
                class="cevico-funnel-bar"
                :style="{
                  width: row.width + '%',
                  background: `linear-gradient(90deg, ${row.color}77 0%, ${row.color}F2 50%, ${row.color}77 100%)`,
                }"
              >
                <span class="text-xs font-bold text-white" style="text-shadow: 0 1px 2px rgba(15, 23, 42, 0.45)">
                  {{ formatNumber(row.count) }}
                </span>
              </div>
            </div>
            <div class="w-20 flex-shrink-0">
              <span
                v-if="row.rate"
                class="inline-flex items-center gap-0.5 text-[10px] font-semibold rounded-full px-1.5 py-0.5"
                :class="row.gain
                  ? 'bg-emerald-500/12 text-emerald-600'
                  : 'bg-n-alpha-1 text-n-slate-10'"
              >
                <span :class="row.gain ? 'i-lucide-trending-up' : 'i-lucide-trending-down'" class="text-[10px]" />
                {{ row.rate }}%
              </span>
            </div>
          </div>
        </div>
        <p class="text-xs text-n-slate-9 mt-4">
          A porcentagem compara com a etapa anterior — <span class="text-emerald-600 font-medium">verde ↑</span> é ganho,
          cinza ↓ é a queda natural do funil. As etapas do CRM refletem os cards atuais em cada coluna.
        </p>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 max-w-4xl">
        <!-- Etiquetas -->
        <div class="bg-n-solid-2 border border-n-weak rounded-xl p-5">
          <p class="text-xs font-semibold text-n-slate-11 mb-3 flex items-center gap-1.5">
            <span class="i-lucide-tags text-n-brand" /> Contatos por etiqueta
          </p>
          <div v-if="!data.labels?.length" class="text-xs text-n-slate-9 py-4">
            Nenhuma etiqueta aplicada ainda.
          </div>
          <div v-else class="space-y-1.5 max-h-80 overflow-y-auto">
            <div
              v-for="l in data.labels"
              :key="l.label"
              class="flex items-center justify-between px-3 py-1.5 rounded-lg bg-n-alpha-1"
            >
              <span class="text-xs text-n-slate-12 flex items-center gap-2 min-w-0">
                <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: l.color || '#6B7280' }" />
                <span class="truncate">{{ l.label }}</span>
              </span>
              <span class="text-xs font-bold text-n-slate-12 flex-shrink-0 ml-2">{{ l.count }}</span>
            </div>
          </div>
        </div>

        <!-- Agentes -->
        <div class="bg-n-solid-2 border border-n-weak rounded-xl p-5">
          <p class="text-xs font-semibold text-n-slate-11 mb-3 flex items-center gap-1.5">
            <span class="i-lucide-headset text-n-brand" /> Desempenho por agente
          </p>
          <div v-if="!data.agents?.rows?.length" class="text-xs text-n-slate-9 py-4">
            Sem dados de agentes no período.
          </div>
          <template v-else>
            <div class="grid grid-cols-3 text-[10px] text-n-slate-9 px-3 pb-1.5">
              <span>Agente</span>
              <span class="text-center">1ª resposta (média)</span>
              <span class="text-right">Conversas abertas</span>
            </div>
            <div class="space-y-1.5 max-h-72 overflow-y-auto">
              <div
                v-for="agent in data.agents.rows"
                :key="agent.id"
                class="grid grid-cols-3 items-center px-3 py-2 rounded-lg bg-n-alpha-1"
              >
                <span class="text-xs text-n-slate-12 truncate">{{ agent.name }}</span>
                <span class="text-xs text-center font-medium" :class="agent.avg_first_response_seconds > 3600 ? 'text-red-500' : 'text-n-slate-12'">
                  {{ formatDuration(agent.avg_first_response_seconds) }}
                </span>
                <span class="text-xs text-right font-bold" :class="agent.open_conversations > 0 ? 'text-n-brand' : 'text-n-slate-10'">
                  {{ agent.open_conversations }}
                </span>
              </div>
            </div>
            <p v-if="data.agents.unassigned_open > 0" class="text-xs text-amber-600 mt-3 flex items-center gap-1">
              <span class="i-lucide-alert-triangle" />
              {{ data.agents.unassigned_open }} conversa(s) aberta(s) sem agente atribuído
            </p>
          </template>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
/* barra do funil: cheia, arredondada, com relevo e varredura de brilho
   (mesma linguagem da barra de progresso do formulário) */
.cevico-funnel-bar {
  position: relative;
  overflow: hidden;
  height: 30px;
  min-width: 3rem;
  border-radius: 9999px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: width 0.6s cubic-bezier(0.22, 1, 0.36, 1);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.35),
    inset 0 -2px 5px rgba(15, 23, 42, 0.18);
}
.cevico-funnel-bar::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    100deg,
    transparent 35%,
    rgba(255, 255, 255, 0.32) 50%,
    transparent 65%
  );
  transform: translateX(-100%);
  animation: cevico-funnel-sheen 2.6s ease-in-out infinite;
}
@keyframes cevico-funnel-sheen {
  to {
    transform: translateX(100%);
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-funnel-bar::after {
    animation: none;
  }
}
</style>
