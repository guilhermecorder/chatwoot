<script setup>
// ANÚNCIOS (META) — repaginado no padrão CEVICO (item 87): qual anúncio
// trouxe cada lead e qual gerou cirurgia. Investimento por anúncio
// (Marketing API) × leads atribuídos (CTWA) × conversões do CRM.
// A CONVERSÃO é dita POR EXTENSO (frase montada das colunas escolhidas)
// para nunca restar dúvida do que o painel está contando.
// 14/09: gráficos do kit (HBars/ShareBar) no lugar do chart.js — mais leves,
// mesma linguagem visual dos outros painéis — e a tabela SEM rolagem lateral:
// impressões/cliques foram para a linha de baixo do anúncio, e no celular
// cada anúncio vira um cartão.
import { ref, computed, onMounted, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useAlert } from 'dashboard/composables';

// régua padrão CEVICO (06/08): Hoje | Ontem | 7 dias | Este mês | Este ano | Personalizado
const period = ref({ preset: 'month', from: '', to: '' });
const data = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
const isBackfilling = ref(false);
const isSavingStages = ref(false);
const showStagePicker = ref(false);
const draftStageIds = ref([]);

// 🍎 formato novo (rodada 163): kit "iMac G3 + vidro" com a paleta desta
// página (o admin escolhe pelo chip do banner; cada bloco pode ter a sua)
const pal = useCevicoPalette({
  scope: 'report:meta',
  blocks: [
    { id: 'kpis', label: 'Números do período', icon: 'i-lucide-gauge' },
    { id: 'formulas', label: 'Como se calcula', icon: 'i-lucide-info' },
    {
      id: 'investimento',
      label: 'Investimento × retorno',
      icon: 'i-lucide-chart-bar',
    },
    {
      id: 'fatia',
      label: 'Onde está o investimento',
      icon: 'i-lucide-chart-pie',
    },
    { id: 'leads', label: 'Leads e conversões', icon: 'i-lucide-users' },
    {
      id: 'tabela',
      label: 'Anúncio por anúncio',
      icon: 'i-lucide-list-ordered',
    },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

// verde = conversão/receita em toda a CEVICO; ouro = dinheiro que voltou
const VERDE = '#059669';
const OURO = '#D4A017';

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const p = period.value;
    const { data: response } = await CrmAPI.getAdsReport({
      preset: p.preset,
      ...(p.preset === 'custom' ? { from: p.from, to: p.to } : {}),
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
watch(period, load, { deep: true });

const rows = computed(() => data.value?.rows ?? []);

const totals = computed(() => {
  const sum = key =>
    rows.value.reduce((acc, r) => acc + (Number(r[key]) || 0), 0);
  const spend = sum('spend');
  const leads = sum('leads');
  const conversions = sum('conversions');
  const revenue = sum('revenue');
  return {
    spend,
    leads,
    conversions,
    revenue,
    impressions: sum('impressions'),
    clicks: sum('link_clicks'),
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
// 56.573 → "56,6 mil" (cabe na coluna sem rolagem)
const formatCompact = v => {
  const n = Number(v || 0);
  if (n >= 1000)
    return `${(n / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil`;
  return formatNumber(n);
};

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

// ── Gráficos do kit (HBars/ShareBar) ──
// Investimento × Receita por anúncio (mesma unidade → mesma escala)
const investRows = computed(() =>
  [...rows.value]
    .filter(r => r.spend > 0 || r.revenue > 0)
    .sort((a, b) => (b.spend || 0) - (a.spend || 0))
    .slice(0, 8)
    .map(r => ({
      key: r.ad_id,
      label: r.ad_name,
      sub: r.campaign_name,
      values: [r.spend || 0, r.revenue || 0],
      hint: r.roas ? `ROAS ${r.roas.toFixed(2)}×` : 'sem receita atribuída',
    }))
);
// Leads × Conversões por anúncio (funil de cada anúncio, lado a lado)
const leadRows = computed(() =>
  [...rows.value]
    .filter(r => (r.leads || 0) > 0)
    .sort((a, b) => (b.leads || 0) - (a.leads || 0))
    .slice(0, 8)
    .map(r => ({
      key: r.ad_id,
      label: r.ad_name,
      sub: r.cpl ? `CPL ${formatCurrency(r.cpl)}` : '',
      values: [r.leads || 0, r.conversions || 0],
    }))
);
// Onde está o investimento (fatia de cada anúncio no total gasto)
const spendSlices = computed(() =>
  rows.value
    .filter(r => (r.spend || 0) > 0)
    .map(r => ({ label: r.ad_name, value: r.spend }))
);

// como cada número nasce — por extenso, no padrão do kit (nunca restar dúvida)
const FORMULAS = [
  {
    label: 'Leads',
    text: 'contatos que chegaram clicando no anúncio (dado da Meta na 1ª mensagem)',
  },
  {
    label: 'Conversões',
    text: 'o card do lead passou pela(s) coluna(s) escolhida(s) na faixa verde acima',
  },
  { label: 'CPL', text: 'investimento ÷ leads' },
  { label: 'CAC', text: 'investimento ÷ conversões' },
  {
    label: 'Receita (CRM)',
    text: 'soma do valor em R$ dos cards dos leads que converteram',
  },
  {
    label: 'ROAS',
    text: 'receita ÷ investimento (quanto voltou de cada R$ 1)',
  },
];

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
  if (!names.length)
    return 'Nenhuma coluna de conversão escolhida — clique em "alterar" e escolha (ex.: Cirurgia Agendada).';
  const cols = names.map(n => `“${n}”`).join(' ou ');
  return `Conversão deste painel = o card do lead PASSAR pela coluna ${cols} — vale para leads que CHEGARAM pelo anúncio no período, mesmo que a cirurgia feche depois.`;
});

// as 7 colunas numéricas da tabela (a mesma lista desenha o cabeçalho, a
// linha do desktop e o cartão do celular — sem rolagem lateral)
const COLS = [
  {
    key: 'spend',
    label: 'Investimento',
    fmt: r => (r.spend ? formatMoneyShort(r.spend) : '—'),
  },
  {
    key: 'leads',
    label: 'Leads',
    fmt: r => formatNumber(r.leads),
    strong: true,
    tint: true,
  },
  { key: 'cpl', label: 'CPL', fmt: r => (r.cpl ? formatCurrency(r.cpl) : '—') },
  {
    key: 'conversions',
    label: 'Conversões',
    fmt: r => formatNumber(r.conversions),
    strong: true,
    green: true,
  },
  { key: 'cac', label: 'CAC', fmt: r => (r.cac ? formatCurrency(r.cac) : '—') },
  {
    key: 'revenue',
    label: 'Receita',
    fmt: r => (r.revenue ? formatMoneyShort(r.revenue) : '—'),
  },
  { key: 'roas', label: 'ROAS', roas: true },
];
const TABLE_GRID = 'minmax(0, 2.2fr) repeat(7, minmax(0, 1fr))';
</script>

<template>
  <div
    class="cv-page flex flex-col h-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-6">
      <!-- banner de vidro na paleta da página (rodada 163) -->
      <CevicoHero
        :pal="pal"
        title="Anúncios (Meta)"
        subtitle="Qual anúncio trouxe cada lead — e qual virou cirurgia. Investimento, custo por lead e retorno real."
        icon="i-lucide-megaphone"
      />

      <!-- Período (régua padrão CEVICO) -->
      <PeriodRuler v-model="period" glass class="mb-6" />

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <div
        v-else-if="hasError"
        class="text-center py-16 text-sm text-n-slate-10"
      >
        Não foi possível carregar o relatório. Tente novamente.
      </div>

      <template v-else-if="data">
        <!-- Meta não configurada (âmbar = atenção) -->
        <div
          v-if="!data.configured"
          class="cv-block cv-strip cv-amber flex items-start gap-3 px-4 py-3.5 mb-4 text-sm text-n-slate-11"
        >
          <span class="cv-icon cv-icon-sm mt-0.5"><span class="i-lucide-plug-zap text-xs"/></span>
          <div class="flex-1 min-w-0">
            <p class="font-medium text-n-slate-12 mb-1">
              Conecte a conta de anúncios da Meta
            </p>
            <p>
              Preencha o <b>token de acesso</b> e o
              <b>ID da conta de anúncios</b> em Configurações → Integrações →
              Meta. Os leads atribuídos por anúncio (abaixo) funcionam mesmo sem
              isso — só o investimento/impressões dependem da conexão.
            </p>
          </div>
        </div>

        <!-- Erro da API da Meta (vermelho = problema) -->
        <div
          v-else-if="data.error"
          class="cv-block cv-strip cv-red flex items-start gap-3 px-4 py-3.5 mb-4 text-sm text-n-slate-11"
        >
          <span class="cv-icon cv-icon-sm mt-0.5"><span class="i-lucide-triangle-alert text-xs"/></span>
          <div class="flex-1 min-w-0">
            <p class="font-medium text-n-slate-12 mb-1">
              A Meta respondeu com erro
            </p>
            <p class="break-words">{{ data.error }}</p>
          </div>
        </div>

        <!-- Backfill pendente -->
        <div
          v-if="data.needs_backfill"
          class="cv-block cv-strip px-4 py-3.5 mb-4 flex items-center gap-3 flex-wrap"
        >
          <span class="cv-icon cv-icon-sm"><span class="i-lucide-history text-xs"/></span>
          <div class="flex-1 min-w-[240px] text-sm text-n-slate-11">
            <p class="font-medium text-n-slate-12">
              Há mensagens antigas com dados de anúncio
            </p>
            <p class="text-xs">
              Processe o histórico uma vez para carimbar a origem nos contatos
              antigos.
            </p>
          </div>
          <button
            class="cv-btn cv-btn-sm"
            :disabled="isBackfilling"
            @click="runBackfill"
          >
            <span
              v-if="isBackfilling"
              class="i-lucide-loader-2 animate-spin text-xs"
            />
            <span v-else class="i-lucide-history text-xs" />
            Processar histórico
          </button>
        </div>

        <!-- A CONVERSÃO POR EXTENSO (clareza total do que o painel conta).
             Continua VERDE de propósito: é "a faixa verde" citada nas fórmulas -->
        <div class="cv-block cv-strip cv-green p-4 mb-6">
          <div class="flex items-start gap-2.5 flex-wrap">
            <span class="cv-icon cv-icon-sm mt-0.5"><span class="i-lucide-target text-xs"/></span>
            <p
              class="flex-1 min-w-[240px] text-xs text-n-slate-11 leading-relaxed"
            >
              <b class="text-n-slate-12">{{ conversionSentence }}</b>
            </p>
            <button
              class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
              @click="showStagePicker = !showStagePicker"
            >
              <span
                :class="showStagePicker ? 'i-lucide-x' : 'i-lucide-pencil'"
                class="text-xs"
              />
              {{ showStagePicker ? 'fechar' : 'alterar' }}
            </button>
          </div>

          <div
            v-if="showStagePicker"
            class="mt-3 pt-3"
            style="border-top: 1px solid rgb(var(--cv-rgb) / 0.2)"
          >
            <p class="text-xs font-medium text-n-slate-12 mb-2">
              Colunas do CRM que contam como conversão (escolha as de venda
              fechada — indicação ainda não é venda):
            </p>
            <div class="flex flex-wrap gap-2 mb-3">
              <button
                v-for="stage in data.stages"
                :key="stage.id"
                class="cv-btn cv-btn-sm"
                :class="draftStageIds.includes(stage.id) ? '' : 'cv-btn-ghost'"
                @click="toggleDraftStage(stage.id)"
              >
                <span
                  v-if="draftStageIds.includes(stage.id)"
                  class="i-lucide-check text-xs"
                />
                {{ stage.name }}
              </button>
            </div>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="isSavingStages"
              @click="saveStages"
            >
              <span
                v-if="isSavingStages"
                class="i-lucide-loader-2 animate-spin text-xs"
              />
              Salvar
            </button>
          </div>
        </div>

        <!-- 📊 Números do período: 4 vidros coloridos (o que saiu, quem chegou,
             quem fechou, o que voltou) + a linha de custo + ROAS + campeão -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('kpis')">
          <div class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-gauge text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Números do período
            </h2>
            <span class="text-[11px] text-n-slate-9 ml-auto">
              {{ formatCompact(totals.impressions) }} impressões ·
              {{ formatCompact(totals.clicks) }} cliques
            </span>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
            <DashKpi
              compact
              glass
              label="Investimento"
              :value="formatMoneyShort(totals.spend)"
              sub="o que saiu (Meta)"
              :grad="blockFamily('kpis')[0]"
            />
            <DashKpi
              compact
              glass
              label="Leads por anúncio"
              :value="totals.leads"
              sub="quem chegou clicando"
              :grad="blockFamily('kpis')[1]"
            />
            <DashKpi
              compact
              glass
              label="Conversões"
              :value="totals.conversions"
              sub="passaram pela coluna escolhida"
              :grad="blockFamily('kpis')[2]"
            />
            <DashKpi
              compact
              glass
              label="Receita (CRM)"
              :value="formatMoneyShort(totals.revenue)"
              sub="valor dos cards que converteram"
              :grad="blockFamily('kpis')[3]"
            />
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <div class="cv-sub px-4 py-3">
              <p class="text-[11px] font-medium text-n-slate-10">
                CPL — custo por lead
              </p>
              <p class="text-xl font-bold text-n-slate-12">
                {{ totals.cpl ? formatCurrency(totals.cpl) : '—' }}
              </p>
            </div>
            <div class="cv-sub px-4 py-3">
              <p class="text-[11px] font-medium text-n-slate-10">
                CAC — custo por venda
              </p>
              <p class="text-xl font-bold text-n-slate-12">
                {{ totals.cac ? formatCurrency(totals.cac) : '—' }}
              </p>
            </div>
            <div class="cv-sub px-4 py-3 flex items-center gap-3">
              <span
                class="cv-icon"
                :style="{ background: roasTone(totals.roas).color }"
              >
                <span class="i-lucide-trending-up text-base" />
              </span>
              <div class="min-w-0">
                <p class="text-[11px] font-medium text-n-slate-10">
                  ROAS — retorno
                </p>
                <p
                  class="text-xl font-bold"
                  :style="{ color: roasTone(totals.roas).color }"
                >
                  {{ totals.roas ? totals.roas.toFixed(2) + '×' : '—' }}
                </p>
                <p class="text-[10px] text-n-slate-9 truncate">
                  {{
                    totals.roas
                      ? `cada R$ 1 virou R$ ${totals.roas.toFixed(2)}`
                      : 'sem receita atribuída'
                  }}
                </p>
              </div>
            </div>
            <div
              v-if="champion"
              class="cv-sub cv-sub-on px-4 py-3 flex items-center gap-3"
            >
              <span class="text-2xl flex-shrink-0">🏆</span>
              <div class="min-w-0">
                <p class="text-[11px] font-medium text-n-slate-10">
                  Campeão do período
                </p>
                <p
                  class="text-sm font-bold text-n-slate-12 truncate"
                  :title="champion.ad_name"
                >
                  {{ champion.ad_name }}
                </p>
                <p class="text-[10px] text-n-slate-9 truncate">
                  {{ formatNumber(champion.leads) }} lead(s) ·
                  {{ formatNumber(champion.conversions) }} conversão(ões)
                  <template v-if="champion.revenue">
                    · {{ formatMoneyShort(champion.revenue) }}
                  </template>
                </p>
              </div>
            </div>
          </div>
        </div>

        <!-- Como cada número é calculado — por extenso, sem mistério -->
        <div
          class="cv-block cv-strip px-4 py-3 mb-6"
          :style="blockVars('formulas')"
        >
          <div class="flex items-center gap-2 mb-2">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-info text-xs"/></span>
            <p class="text-[11px] font-bold text-n-slate-11">
              Como cada número é calculado
            </p>
          </div>
          <div
            class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-x-6 gap-y-1"
          >
            <p
              v-for="f in FORMULAS"
              :key="f.label"
              class="text-[11px] text-n-slate-10"
            >
              <span class="font-bold text-n-slate-11">{{ f.label }}</span> =
              {{ f.text }}
            </p>
          </div>
        </div>

        <!-- Gráficos: o impacto de cada anúncio, visual (kit, sem lib) -->
        <div
          v-if="investRows.length || spendSlices.length"
          class="grid grid-cols-1 xl:grid-cols-5 gap-4 mb-4"
        >
          <div
            v-if="investRows.length"
            class="xl:col-span-3 cv-block p-5 sm:p-6"
            :style="blockVars('investimento')"
          >
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"><span class="i-lucide-chart-bar text-base"/></span>
              <h3 class="text-sm font-bold text-n-slate-12">
                Investimento × retorno por anúncio
              </h3>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-4">
              anúncio saudável = a barra dourada (o que voltou) passa a barra do
              investimento (o que saiu)
            </p>
            <HBars
              :rows="investRows"
              :series="[
                {
                  label: 'Investimento',
                  color: blockFamily('investimento')[1],
                  format: formatMoneyShort,
                },
                {
                  label: 'Receita (CRM)',
                  color: OURO,
                  format: formatMoneyShort,
                },
              ]"
              :label-width="12"
            />
          </div>
          <div
            v-if="spendSlices.length"
            class="xl:col-span-2 cv-block p-5 sm:p-6"
            :style="blockVars('fatia')"
          >
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"><span class="i-lucide-chart-pie text-base"/></span>
              <h3 class="text-sm font-bold text-n-slate-12">
                Onde está o investimento
              </h3>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-4">
              fatia de cada anúncio no total gasto ·
              {{ formatMoneyShort(totals.spend) }}
            </p>
            <ShareBar
              :items="spendSlices"
              :family="blockFamily('fatia')"
              :format="formatMoneyShort"
              :height="18"
            />
          </div>
        </div>
        <div
          v-if="leadRows.length"
          class="cv-block p-5 sm:p-6 mb-6"
          :style="blockVars('leads')"
        >
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-users text-base"/></span>
            <h3 class="text-sm font-bold text-n-slate-12">
              Leads e conversões por anúncio
            </h3>
          </div>
          <p class="text-[11px] text-n-slate-10 mb-4">
            quantos chegaram por cada anúncio (cor do bloco) — e quantos desses
            viraram conversão (verde)
          </p>
          <HBars
            :rows="leadRows"
            :series="[
              {
                label: 'Leads',
                color: blockFamily('leads')[1],
                format: formatNumber,
              },
              { label: 'Conversões', color: VERDE, format: formatNumber },
            ]"
            :label-width="12"
          />
        </div>

        <!-- Tabela por anúncio — sem rolagem lateral: 8 colunas que cabem na
             tela; impressões/cliques na linha de baixo; celular = cartões -->
        <div class="cv-block mb-6" :style="blockVars('tabela')">
          <div
            class="px-5 py-4 flex items-center gap-2 flex-wrap"
            style="border-bottom: 1px solid rgb(var(--cv-rgb) / 0.18)"
          >
            <span class="cv-icon"><span class="i-lucide-list-ordered text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Anúncio por anúncio
            </h2>
            <span class="text-[11px] text-n-slate-9 ml-auto">
              {{ formatNumber(data.unattributed_leads) }} contato(s) novo(s) no
              período sem anúncio identificado
            </span>
          </div>

          <div
            v-if="!rows.length"
            class="px-3 py-10 text-center text-xs text-n-slate-10"
          >
            <p class="text-3xl mb-2">📣</p>
            Nenhum anúncio no período — sem investimento na Meta e sem leads
            atribuídos. Se o tráfego já roda há tempo, use "Processar
            histórico".
          </div>

          <template v-else>
            <!-- cabeçalho (só no desktop) -->
            <div
              class="hidden xl:grid px-5 py-2 text-[10px] uppercase tracking-wide text-n-slate-9 font-bold"
              :style="{
                gridTemplateColumns: TABLE_GRID,
                borderBottom: '1px solid rgb(var(--cv-rgb) / 0.18)',
              }"
            >
              <span>Anúncio</span>
              <span v-for="c in COLS" :key="c.key" class="text-right">{{
                c.label
              }}</span>
            </div>

            <div
              v-for="(row, ri) in rows"
              :key="row.ad_id"
              class="px-5 py-3 xl:py-2.5 hover:bg-n-alpha-1 xl:grid xl:items-center xl:gap-x-3"
              :style="{
                gridTemplateColumns: TABLE_GRID,
                borderBottom:
                  ri === rows.length - 1
                    ? ''
                    : '1px solid rgb(var(--cv-rgb) / 0.1)',
              }"
            >
              <!-- anúncio + campanha + impressões/cliques -->
              <div class="min-w-0 flex items-start gap-1.5">
                <span
                  v-if="medalFor(ri) && (row.conversions || row.leads)"
                  class="flex-shrink-0 text-sm leading-5"
                  >{{ medalFor(ri) }}</span>
                <div class="min-w-0">
                  <a
                    v-if="row.source_url"
                    :href="row.source_url"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="text-sm font-medium text-n-slate-12 hover:text-n-brand hover:underline block truncate"
                    :title="row.ad_name"
                    >{{ row.ad_name }}</a>
                  <p
                    v-else
                    class="text-sm font-medium text-n-slate-12 truncate"
                    :title="row.ad_name"
                  >
                    {{ row.ad_name }}
                  </p>
                  <p class="text-[11px] text-n-slate-10 truncate">
                    <template v-if="row.campaign_name">
                      {{ row.campaign_name
                      }}<template v-if="row.adset_name">
                        · {{ row.adset_name }}
                      </template>
                      ·
                    </template>
                    <span class="tabular-nums">{{
                        row.impressions ? formatCompact(row.impressions) : '—'
                      }}
                      impressões ·
                      {{
                        row.link_clicks ? formatCompact(row.link_clicks) : '—'
                      }}
                      cliques</span>
                  </p>
                </div>
              </div>

              <!-- números: coluna no desktop, chips com rótulo no celular -->
              <template v-for="c in COLS" :key="c.key">
                <div
                  class="hidden xl:block text-right text-[13px] tabular-nums whitespace-nowrap"
                >
                  <span
                    v-if="c.roas && row.roas"
                    class="inline-block text-[10px] font-bold px-2 py-0.5 rounded-full"
                    :style="{
                      background: roasTone(row.roas).bg,
                      color: roasTone(row.roas).color,
                    }"
                    >{{ row.roas.toFixed(2) }}×</span>
                  <span v-else-if="c.roas" class="text-n-slate-9">—</span>
                  <span
                    v-else
                    :class="c.strong ? 'font-bold' : ''"
                    :style="
                      c.tint && row.leads
                        ? { color: 'var(--cv)' }
                        : c.green && row.conversions
                          ? { color: VERDE }
                          : {}
                    "
                    >{{ c.fmt(row) }}</span>
                </div>
              </template>
              <div class="xl:hidden flex flex-wrap gap-1.5 mt-2">
                <span
                  v-for="c in COLS"
                  :key="'m' + c.key"
                  class="cv-stat py-1 px-2 text-[11px] tabular-nums"
                >
                  <span class="text-n-slate-9">{{ c.label }}</span>
                  <b class="ml-1 text-n-slate-12">
                    <template v-if="c.roas">{{
                      row.roas ? row.roas.toFixed(2) + '×' : '—'
                    }}</template>
                    <template v-else>{{ c.fmt(row) }}</template>
                  </b>
                </span>
              </div>
            </div>
          </template>
        </div>

        <p class="text-[11px] text-n-slate-9 mt-3 mb-6">
          Leads = contatos que chegaram clicando no anúncio (dado oficial da
          Meta na primeira mensagem). Conversões e receita vêm dos cards do CRM.
          Anúncios sem investimento no período mas com leads também aparecem na
          lista.
        </p>
      </template>
    </div>
  </div>
</template>
