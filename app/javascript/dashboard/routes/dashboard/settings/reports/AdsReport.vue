<script setup>
// ANÚNCIOS (META) — repaginado no padrão CEVICO (item 87): qual anúncio
// trouxe cada lead e qual gerou cirurgia. Investimento por anúncio
// (Marketing API) × leads atribuídos (CTWA) × conversões do CRM.
// A CONVERSÃO é dita POR EXTENSO (frase montada das colunas escolhidas)
// para nunca restar dúvida do que o painel está contando.
import { ref, computed, onMounted, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
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

const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';
const VERDE = '#059669';
const OURO = '#D4A017';
const AMBAR = '#D97706';
const CIANO = '#0E7490';

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
const formatMoneyShort = v =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 });

const formatNumber = v => Number(v || 0).toLocaleString('pt-BR');

// KPIs no padrão dopamine: medalhão colorido + valor grande
const kpiCards = computed(() => [
  { key: 'spend', label: 'Investimento', icon: 'i-lucide-wallet', color: AZUL, value: formatMoneyShort(totals.value.spend) },
  { key: 'leads', label: 'Leads por anúncio', icon: 'i-lucide-users', color: ROXO, value: formatNumber(totals.value.leads) },
  { key: 'cpl', label: 'CPL — custo por lead', icon: 'i-lucide-user-plus', color: CIANO, value: totals.value.cpl ? formatCurrency(totals.value.cpl) : '—' },
  { key: 'conversions', label: 'Conversões', icon: 'i-lucide-heart-pulse', color: VERDE, value: formatNumber(totals.value.conversions) },
  { key: 'cac', label: 'CAC — custo por venda', icon: 'i-lucide-target', color: AMBAR, value: totals.value.cac ? formatCurrency(totals.value.cac) : '—' },
  { key: 'revenue', label: 'Receita (CRM)', icon: 'i-lucide-gem', color: OURO, value: formatMoneyShort(totals.value.revenue) },
]);

// ROAS ganha cor pelo resultado: acima de 1× = verde (cada R$ virou mais R$)
const roasTone = v => {
  if (!v) return { color: '#64748B', bg: 'rgba(100,116,139,0.12)' };
  if (v >= 2) return { color: '#059669', bg: 'rgba(5,150,105,0.12)' };
  if (v >= 1) return { color: '#B8860B', bg: 'rgba(212,160,23,0.14)' };
  return { color: '#DC2626', bg: 'rgba(220,38,38,0.1)' };
};

// campeão do período: o anúncio que mais converteu (desempate: leads)
const champion = computed(() => {
  const best = rows.value[0];
  return best && (best.conversions > 0 || best.leads > 0) ? best : null;
});

const medalFor = index => ['🥇', '🥈', '🥉'][index] || null;

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

// ── Conversão POR EXTENSO (item 87: clareza total do que conta) ──────
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
  return stages.filter(s => ids.includes(s.id)).map(s => s.name);
});

// a frase que elimina a dúvida — montada ao vivo das colunas escolhidas
const conversionSentence = computed(() => {
  const names = conversionStageNames.value;
  if (!names.length) return 'Nenhuma coluna de conversão escolhida — clique em "alterar" e escolha (ex.: Cirurgia Agendada).';
  const cols = names.map(n => `“${n}”`).join(' ou ');
  return `Conversão deste painel = o card do lead PASSAR pela coluna ${cols} — vale para leads que CHEGARAM pelo anúncio no período, mesmo que a cirurgia feche depois.`;
});
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-6">
      <!-- cabeçalho no padrão CEVICO -->
      <div
        class="rounded-3xl p-6 text-white shadow-lg mb-5 relative overflow-hidden"
        style="background: linear-gradient(135deg, #0d3a75, #1877f2)"
      >
        <div class="relative z-10 flex items-center gap-4 flex-wrap" style="color: #fff">
          <div class="flex-1 min-w-[220px]">
            <h1 class="text-2xl font-bold leading-tight" style="color: #fff">Anúncios (Meta)</h1>
            <p class="text-sm mt-1" style="color: rgba(255,255,255,0.85)">
              Qual anúncio trouxe cada lead — e qual virou cirurgia. Investimento, custo por lead e retorno real.
            </p>
          </div>
          <div class="flex items-center gap-1 bg-white/15 rounded-xl p-1 backdrop-blur-sm">
            <button
              v-for="p in PERIODS"
              :key="p.value"
              class="px-3 py-1.5 text-xs font-bold rounded-lg transition-colors"
              :class="period === p.value ? 'bg-white text-blue-900 shadow-sm' : 'text-white/85 hover:bg-white/10'"
              @click="period = p.value"
            >{{ p.label }}</button>
          </div>
        </div>
        <span class="i-lucide-megaphone absolute -right-4 -bottom-8 text-[130px] text-white/10" />
      </div>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <div v-else-if="hasError" class="text-center py-16 text-sm text-n-slate-10">
        Não foi possível carregar o relatório. Tente novamente.
      </div>

      <template v-else-if="data">
        <!-- Meta não configurada -->
        <div
          v-if="!data.configured"
          class="rounded-2xl border border-amber-500/40 bg-amber-500/5 p-4 mb-4 text-sm text-n-slate-11"
        >
          <p class="font-medium text-n-slate-12 mb-1">Conecte a conta de anúncios da Meta</p>
          <p>
            Preencha o <b>token de acesso</b> e o <b>ID da conta de anúncios</b> em
            Configurações → Integrações → Meta. Os leads atribuídos por anúncio (abaixo)
            funcionam mesmo sem isso — só o investimento/impressões dependem da conexão.
          </p>
        </div>

        <!-- Erro da API da Meta -->
        <div
          v-else-if="data.error"
          class="rounded-2xl border border-red-500/40 bg-red-500/5 p-4 mb-4 text-sm text-n-slate-11"
        >
          <p class="font-medium text-n-slate-12 mb-1">A Meta respondeu com erro</p>
          <p class="break-words">{{ data.error }}</p>
        </div>

        <!-- Backfill pendente -->
        <div
          v-if="data.needs_backfill"
          class="rounded-2xl border border-blue-500/40 bg-blue-500/5 p-4 mb-4 flex items-center gap-3 flex-wrap"
        >
          <div class="flex-1 min-w-[240px] text-sm text-n-slate-11">
            <p class="font-medium text-n-slate-12">Há mensagens antigas com dados de anúncio</p>
            <p class="text-xs">Processe o histórico uma vez para carimbar a origem nos contatos antigos.</p>
          </div>
          <button
            class="px-3 py-2 text-xs font-bold rounded-lg text-white disabled:opacity-50"
            style="background: linear-gradient(135deg, #0d3a75, #1877f2)"
            :disabled="isBackfilling"
            @click="runBackfill"
          >
            <span v-if="isBackfilling" class="i-lucide-loader-2 animate-spin inline-block align-middle mr-1" />
            Processar histórico
          </button>
        </div>

        <!-- A CONVERSÃO POR EXTENSO (clareza total do que o painel conta) -->
        <div
          class="rounded-2xl border p-4 mb-4"
          style="border-color: rgba(5, 150, 105, 0.35); background: rgba(5, 150, 105, 0.06)"
        >
          <div class="flex items-start gap-2.5 flex-wrap">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" style="background: #059669">
              <span class="i-lucide-target text-white text-sm" />
            </span>
            <p class="flex-1 min-w-[240px] text-xs text-n-slate-11 leading-relaxed">
              <b class="text-n-slate-12">{{ conversionSentence }}</b>
            </p>
            <button
              class="text-xs font-bold px-3 h-8 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex-shrink-0"
              @click="showStagePicker = !showStagePicker"
            >
              {{ showStagePicker ? 'fechar' : 'alterar' }}
            </button>
          </div>

          <div v-if="showStagePicker" class="mt-3 pt-3 border-t" style="border-color: rgba(5, 150, 105, 0.2)">
            <p class="text-xs font-medium text-n-slate-12 mb-2">
              Colunas do CRM que contam como conversão (escolha as de venda fechada — indicação ainda não é venda):
            </p>
            <div class="flex flex-wrap gap-2 mb-3">
              <button
                v-for="stage in data.stages"
                :key="stage.id"
                class="px-2.5 py-1 text-xs rounded-lg border transition-colors"
                :class="draftStageIds.includes(stage.id)
                  ? 'font-bold text-white border-transparent'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                :style="draftStageIds.includes(stage.id) ? { background: '#059669' } : {}"
                @click="toggleDraftStage(stage.id)"
              >
                {{ stage.name }}
              </button>
            </div>
            <button
              class="px-3 py-1.5 text-xs font-bold rounded-lg text-white disabled:opacity-50"
              style="background: #059669"
              :disabled="isSavingStages"
              @click="saveStages"
            >
              <span v-if="isSavingStages" class="i-lucide-loader-2 animate-spin inline-block align-middle mr-1" />
              Salvar
            </button>
          </div>
        </div>

        <!-- KPIs dopamine -->
        <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mb-3">
          <div v-for="card in kpiCards" :key="card.key" class="rounded-2xl border border-n-weak bg-n-card p-3.5">
            <div class="flex items-center gap-2 mb-1.5">
              <span class="w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0" :style="{ background: card.color }">
                <span :class="card.icon" class="text-white text-xs" />
              </span>
              <p class="text-[10px] font-bold text-n-slate-11 leading-tight">{{ card.label }}</p>
            </div>
            <p class="text-lg font-bold tabular-nums" :style="{ color: card.color }">{{ card.value }}</p>
          </div>
        </div>

        <!-- ROAS + campeão do período -->
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-5">
          <div class="rounded-2xl border border-n-weak bg-n-card p-4 flex items-center gap-3">
            <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" :style="{ background: roasTone(totals.roas).color }">
              <span class="i-lucide-trending-up text-white text-base" />
            </span>
            <div class="flex-1">
              <p class="text-[11px] font-bold text-n-slate-11">ROAS — retorno do investimento</p>
              <p class="text-xl font-bold tabular-nums" :style="{ color: roasTone(totals.roas).color }">
                {{ totals.roas ? totals.roas.toFixed(2) + '×' : '—' }}
              </p>
              <p class="text-[10px] text-n-slate-9">
                {{ totals.roas ? `cada R$ 1 investido virou R$ ${totals.roas.toFixed(2)} em cirurgias` : 'sem receita atribuída no período' }}
              </p>
            </div>
          </div>
          <div v-if="champion" class="rounded-2xl border border-n-weak bg-n-card p-4 flex items-center gap-3">
            <span class="text-3xl flex-shrink-0">🏆</span>
            <div class="min-w-0">
              <p class="text-[11px] font-bold text-n-slate-11">Campeão do período</p>
              <p class="text-sm font-bold text-n-slate-12 truncate" :title="champion.ad_name">{{ champion.ad_name }}</p>
              <p class="text-[10px] text-n-slate-9">
                {{ formatNumber(champion.leads) }} lead(s) · {{ formatNumber(champion.conversions) }} conversão(ões)
                <template v-if="champion.revenue"> · {{ formatMoneyShort(champion.revenue) }}</template>
              </p>
            </div>
          </div>
        </div>

        <!-- Tabela por anúncio -->
        <div class="rounded-2xl border border-n-weak bg-n-card overflow-hidden">
          <div class="px-4 py-3 border-b border-n-weak flex items-center gap-2 flex-wrap">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0d3a75, #1877f2)">
              <span class="i-lucide-list-ordered text-white text-sm" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">Anúncio por anúncio</h2>
            <span class="text-[11px] text-n-slate-9 ml-auto">
              {{ formatNumber(data.unattributed_leads) }} contato(s) novo(s) no período sem anúncio identificado
            </span>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm min-w-[900px]">
              <thead>
                <tr class="text-left text-[10px] uppercase tracking-wide text-n-slate-9 border-b border-n-weak">
                  <th class="px-3 py-2.5 font-bold">Anúncio</th>
                  <th class="px-3 py-2.5 font-bold text-right">Investimento</th>
                  <th class="px-3 py-2.5 font-bold text-right">Impressões</th>
                  <th class="px-3 py-2.5 font-bold text-right">Cliques</th>
                  <th class="px-3 py-2.5 font-bold text-right">Leads</th>
                  <th class="px-3 py-2.5 font-bold text-right">CPL</th>
                  <th class="px-3 py-2.5 font-bold text-right">Conversões</th>
                  <th class="px-3 py-2.5 font-bold text-right">CAC</th>
                  <th class="px-3 py-2.5 font-bold text-right">Receita</th>
                  <th class="px-3 py-2.5 font-bold text-right">ROAS</th>
                </tr>
              </thead>
              <tbody>
                <tr v-if="!rows.length">
                  <td colspan="10" class="px-3 py-10 text-center text-xs text-n-slate-10">
                    <p class="text-3xl mb-2">📣</p>
                    Nenhum anúncio no período — sem investimento na Meta e sem leads
                    atribuídos. Se o tráfego já roda há tempo, use "Processar histórico".
                  </td>
                </tr>
                <tr
                  v-for="(row, ri) in rows"
                  :key="row.ad_id"
                  class="border-b border-n-weak/60 last:border-0 hover:bg-n-alpha-1"
                >
                  <td class="px-3 py-2.5 max-w-[280px]">
                    <div class="flex items-center gap-1.5">
                      <span v-if="medalFor(ri) && (row.conversions || row.leads)" class="flex-shrink-0">{{ medalFor(ri) }}</span>
                      <div class="min-w-0">
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
                      </div>
                    </div>
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ row.spend ? formatCurrency(row.spend) : '—' }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ row.impressions ? formatNumber(row.impressions) : '—' }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ row.link_clicks ? formatNumber(row.link_clicks) : '—' }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums font-bold" :style="{ color: row.leads ? '#7C3AED' : undefined }">
                    {{ formatNumber(row.leads) }}
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ row.cpl ? formatCurrency(row.cpl) : '—' }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums font-bold" :style="{ color: row.conversions ? '#059669' : undefined }">
                    {{ formatNumber(row.conversions) }}
                  </td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ row.cac ? formatCurrency(row.cac) : '—' }}</td>
                  <td class="px-3 py-2.5 text-right tabular-nums">{{ row.revenue ? formatCurrency(row.revenue) : '—' }}</td>
                  <td class="px-3 py-2.5 text-right">
                    <span
                      v-if="row.roas"
                      class="inline-block text-[10px] font-bold px-2 py-0.5 rounded-full tabular-nums"
                      :style="{ background: roasTone(row.roas).bg, color: roasTone(row.roas).color }"
                    >
                      {{ row.roas.toFixed(2) }}×
                    </span>
                    <span v-else class="text-n-slate-9">—</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <p class="text-[11px] text-n-slate-9 mt-3 mb-6">
          Leads = contatos que chegaram clicando no anúncio (dado oficial da Meta na
          primeira mensagem). Conversões e receita vêm dos cards do CRM. Anúncios sem
          investimento no período mas com leads também aparecem na lista.
        </p>
      </template>
    </div>
  </div>
</template>
