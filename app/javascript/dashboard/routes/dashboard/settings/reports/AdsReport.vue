<script setup>
// Relatório "qual anúncio gerou venda": investimento por anúncio (Marketing
// API) × leads atribuídos (CTWA) × conversões do CRM (etapa Cirurgia).
import { ref, computed, onMounted, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAlert } from 'dashboard/composables';

const period = ref(30);
const data = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
const isBackfilling = ref(false);
const isSavingStages = ref(false);
const showStagePicker = ref(false);
const draftStageIds = ref([]);

const PERIODS = [
  { value: 7, label: '7 dias' },
  { value: 30, label: '30 dias' },
  { value: 90, label: '90 dias' },
  { value: 180, label: '6 meses' },
];

const sinceDate = computed(() => {
  const d = new Date();
  d.setDate(d.getDate() - period.value);
  return d.toISOString().slice(0, 10);
});

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data: response } = await CrmAPI.getAdsReport({
      since: sinceDate.value,
    });
    data.value = response;
    draftStageIds.value = [...(response.conversion_stage_ids || [])];
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(period, load);

const rows = computed(() => data.value?.rows ?? []);

const totals = computed(() => {
  const sum = key => rows.value.reduce((acc, r) => acc + (Number(r[key]) || 0), 0);
  const spend = sum('spend');
  const leads = sum('leads');
  const conversions = sum('conversions');
  const revenue = sum('revenue');
  return {
    spend,
    leads,
    conversions,
    revenue,
    cpl: leads ? spend / leads : null,
    cac: conversions ? spend / conversions : null,
    roas: spend ? revenue / spend : null,
  };
});

const formatCurrency = v =>
  'R$ ' +
  Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

const formatNumber = v => Number(v || 0).toLocaleString('pt-BR');

const runBackfill = async () => {
  if (isBackfilling.value) return;
  isBackfilling.value = true;
  try {
    const { data: result } = await CrmAPI.backfillAdAttribution();
    useAlert(
      `Processando ${formatNumber(result.messages)} mensagens antigas com dados de anúncio. Recarregue em alguns minutos.`
    );
  } catch {
    useAlert('Erro ao iniciar o processamento do histórico.');
  } finally {
    isBackfilling.value = false;
  }
};

// ── Etapas que contam como conversão ─────────────────────────────────
const toggleDraftStage = id => {
  if (draftStageIds.value.includes(id)) {
    draftStageIds.value = draftStageIds.value.filter(s => s !== id);
  } else {
    draftStageIds.value = [...draftStageIds.value, id];
  }
};

const saveStages = async () => {
  isSavingStages.value = true;
  try {
    await CrmAPI.updateMetaAds({ conversion_stage_ids: draftStageIds.value });
    showStagePicker.value = false;
    await load();
  } catch {
    useAlert('Erro ao salvar as etapas de conversão.');
  } finally {
    isSavingStages.value = false;
  }
};

const conversionStageNames = computed(() => {
  const ids = data.value?.conversion_stage_ids || [];
  const stages = data.value?.stages || [];
  const names = stages.filter(s => ids.includes(s.id)).map(s => s.name);
  return names.length ? names.join(', ') : 'nenhuma etapa definida';
});
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto p-6 bg-n-surface-1">
    <!-- Header -->
    <div class="flex items-center gap-3 mb-6 flex-wrap">
      <div>
        <div class="flex items-center gap-3">
          <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #1D4ED8, #38BDF8)">
            <span class="i-lucide-megaphone text-white text-lg" />
          </span>
          <div>
            <h1 class="text-lg font-bold text-n-slate-12">Anúncios (Meta)</h1>
            <p class="text-xs text-n-slate-10 mt-0.5">
              Qual anúncio trouxe cada lead — e qual gerou cirurgia
            </p>
          </div>
        </div>
      </div>
      <div class="flex-1" />
      <div class="flex items-center gap-1.5 bg-n-solid-2 border border-n-weak rounded-xl p-1">
        <button
          v-for="p in PERIODS"
          :key="p.value"
          class="px-3 py-1.5 text-xs font-medium rounded-lg transition-colors"
          :class="period === p.value ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="period = p.value"
        >{{ p.label }}</button>
      </div>
    </div>

    <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

    <div v-else-if="hasError" class="text-center py-16 text-sm text-n-slate-10">
      Não foi possível carregar o relatório. Tente novamente.
    </div>

    <template v-else-if="data">
      <!-- Meta não configurada -->
      <div
        v-if="!data.configured"
        class="rounded-xl border border-amber-500/40 bg-amber-500/5 p-4 mb-4 text-sm text-n-slate-11"
      >
        <p class="font-medium text-n-slate-12 mb-1">Conecte a conta de anúncios da Meta</p>
        <p>
          Preencha o <b>token de acesso</b> e o <b>ID da conta de anúncios</b> em
          CRM → Integrações → Meta. Os leads atribuídos por anúncio (abaixo)
          funcionam mesmo sem isso — só o investimento/impressões dependem da conexão.
        </p>
      </div>

      <!-- Erro da API da Meta -->
      <div
        v-else-if="data.error"
        class="rounded-xl border border-red-500/40 bg-red-500/5 p-4 mb-4 text-sm text-n-slate-11"
      >
        <p class="font-medium text-n-slate-12 mb-1">A Meta respondeu com erro</p>
        <p class="break-words">{{ data.error }}</p>
      </div>

      <!-- Backfill pendente -->
      <div
        v-if="data.needs_backfill"
        class="rounded-xl border border-blue-500/40 bg-blue-500/5 p-4 mb-4 flex items-center gap-3 flex-wrap"
      >
        <div class="flex-1 min-w-[240px] text-sm text-n-slate-11">
          <p class="font-medium text-n-slate-12">Há mensagens antigas com dados de anúncio</p>
          <p class="text-xs">Processe o histórico uma vez para carimbar a origem nos contatos antigos.</p>
        </div>
        <button
          class="px-3 py-2 text-xs font-medium rounded-lg bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-50"
          :disabled="isBackfilling"
          @click="runBackfill"
        >
          <span v-if="isBackfilling" class="i-lucide-loader-2 animate-spin inline-block align-middle mr-1" />
          Processar histórico
        </button>
      </div>

      <!-- KPIs -->
      <div class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3 mb-6">
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">Investimento</p>
          <p class="text-lg font-semibold text-n-slate-12">{{ formatCurrency(totals.spend) }}</p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">Leads por anúncio</p>
          <p class="text-lg font-semibold text-n-slate-12">{{ formatNumber(totals.leads) }}</p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">CPL</p>
          <p class="text-lg font-semibold text-n-slate-12">{{ totals.cpl ? formatCurrency(totals.cpl) : '—' }}</p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">Conversões</p>
          <p class="text-lg font-semibold text-green-600">{{ formatNumber(totals.conversions) }}</p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">CAC</p>
          <p class="text-lg font-semibold text-n-slate-12">{{ totals.cac ? formatCurrency(totals.cac) : '—' }}</p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">Receita (CRM)</p>
          <p class="text-lg font-semibold text-n-slate-12">{{ formatCurrency(totals.revenue) }}</p>
        </div>
        <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-[11px] text-n-slate-10">ROAS</p>
          <p class="text-lg font-semibold text-n-slate-12">{{ totals.roas ? totals.roas.toFixed(2) + 'x' : '—' }}</p>
        </div>
      </div>

      <!-- Etapa de conversão -->
      <div class="flex items-center gap-2 mb-3 text-xs text-n-slate-10 flex-wrap">
        <span>
          Conversão = card que passou por: <b class="text-n-slate-12">{{ conversionStageNames }}</b>
        </span>
        <button
          class="text-n-brand hover:underline"
          @click="showStagePicker = !showStagePicker"
        >
          alterar
        </button>
        <span class="ml-auto">
          {{ formatNumber(data.unattributed_leads) }} contatos novos no período sem anúncio identificado
        </span>
      </div>

      <div
        v-if="showStagePicker"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-3 mb-4"
      >
        <p class="text-xs font-medium text-n-slate-12 mb-2">
          Etapas do CRM que contam como conversão:
        </p>
        <div class="flex flex-wrap gap-2 mb-3">
          <button
            v-for="stage in data.stages"
            :key="stage.id"
            class="px-2.5 py-1 text-xs rounded-lg border transition-colors"
            :class="draftStageIds.includes(stage.id)
              ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            @click="toggleDraftStage(stage.id)"
          >
            {{ stage.name }}
          </button>
        </div>
        <button
          class="px-3 py-1.5 text-xs font-medium rounded-lg bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-50"
          :disabled="isSavingStages"
          @click="saveStages"
        >
          <span v-if="isSavingStages" class="i-lucide-loader-2 animate-spin inline-block align-middle mr-1" />
          Salvar
        </button>
      </div>

      <!-- Tabela por anúncio -->
      <div class="rounded-xl border border-n-weak bg-n-solid-1 overflow-x-auto">
        <table class="w-full text-sm min-w-[900px]">
          <thead>
            <tr class="text-left text-[11px] text-n-slate-10 border-b border-n-weak">
              <th class="px-3 py-2.5 font-medium">Anúncio</th>
              <th class="px-3 py-2.5 font-medium text-right">Investimento</th>
              <th class="px-3 py-2.5 font-medium text-right">Impressões</th>
              <th class="px-3 py-2.5 font-medium text-right">Cliques</th>
              <th class="px-3 py-2.5 font-medium text-right">Leads</th>
              <th class="px-3 py-2.5 font-medium text-right">CPL</th>
              <th class="px-3 py-2.5 font-medium text-right">Conversões</th>
              <th class="px-3 py-2.5 font-medium text-right">CAC</th>
              <th class="px-3 py-2.5 font-medium text-right">Receita</th>
              <th class="px-3 py-2.5 font-medium text-right">ROAS</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!rows.length">
              <td colspan="10" class="px-3 py-8 text-center text-xs text-n-slate-10">
                Nenhum anúncio no período — sem investimento na Meta e sem leads
                atribuídos. Se o tráfego já roda há tempo, use "Processar histórico".
              </td>
            </tr>
            <tr
              v-for="row in rows"
              :key="row.ad_id"
              class="border-b border-n-weak/60 last:border-0 hover:bg-n-alpha-1"
            >
              <td class="px-3 py-2.5 max-w-[280px]">
                <a
                  v-if="row.source_url"
                  :href="row.source_url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="font-medium text-n-slate-12 hover:text-n-brand hover:underline block truncate"
                  :title="row.ad_name"
                >{{ row.ad_name }}</a>
                <p v-else class="font-medium text-n-slate-12 truncate" :title="row.ad_name">
                  {{ row.ad_name }}
                </p>
                <p v-if="row.campaign_name" class="text-[11px] text-n-slate-10 truncate">
                  {{ row.campaign_name }}<template v-if="row.adset_name"> · {{ row.adset_name }}</template>
                </p>
              </td>
              <td class="px-3 py-2.5 text-right">{{ row.spend ? formatCurrency(row.spend) : '—' }}</td>
              <td class="px-3 py-2.5 text-right">{{ row.impressions ? formatNumber(row.impressions) : '—' }}</td>
              <td class="px-3 py-2.5 text-right">{{ row.link_clicks ? formatNumber(row.link_clicks) : '—' }}</td>
              <td class="px-3 py-2.5 text-right font-medium">{{ formatNumber(row.leads) }}</td>
              <td class="px-3 py-2.5 text-right">{{ row.cpl ? formatCurrency(row.cpl) : '—' }}</td>
              <td class="px-3 py-2.5 text-right font-medium" :class="row.conversions ? 'text-green-600' : ''">
                {{ formatNumber(row.conversions) }}
              </td>
              <td class="px-3 py-2.5 text-right">{{ row.cac ? formatCurrency(row.cac) : '—' }}</td>
              <td class="px-3 py-2.5 text-right">{{ row.revenue ? formatCurrency(row.revenue) : '—' }}</td>
              <td class="px-3 py-2.5 text-right">{{ row.roas ? row.roas.toFixed(2) + 'x' : '—' }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="text-[11px] text-n-slate-9 mt-3">
        Leads = contatos que chegaram clicando no anúncio (dado oficial da Meta na
        primeira mensagem). Conversões e receita vêm dos cards do CRM. Anúncios sem
        investimento no período mas com leads também aparecem na lista.
      </p>
    </template>
  </div>
</template>
