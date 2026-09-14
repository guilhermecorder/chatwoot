<script setup>
// ANÚNCIOS (META) — repaginado no padrão CEVICO (item 87): qual anúncio
// trouxe cada lead e qual gerou cirurgia. Investimento por anúncio
// (Marketing API) × leads atribuídos (CTWA) × conversões do CRM.
// A CONVERSÃO é dita POR EXTENSO (frase montada das colunas escolhidas)
// para nunca restar dúvida do que o painel está contando.
import { ref, computed, onMounted, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import { useAlert } from 'dashboard/composables';
import { Bar, Doughnut } from 'vue-chartjs';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  ArcElement,
  Tooltip,
  Legend,
} from 'chart.js';

ChartJS.register(CategoryScale, LinearScale, BarElement, ArcElement, Tooltip, Legend);

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
    { id: 'investimento', label: 'Investimento × retorno', icon: 'i-lucide-chart-bar' },
    { id: 'fatia', label: 'Onde está o investimento', icon: 'i-lucide-chart-pie' },
    { id: 'leads', label: 'Leads e conversões', icon: 'i-lucide-users' },
    { id: 'tabela', label: 'Anúncio por anúncio', icon: 'i-lucide-list-ordered' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';
const VERDE = '#059669';
const OURO = '#D4A017';
const AMBAR = '#D97706';
const CIANO = '#0E7490';

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

// ── Gráficos (padrão dos outros dashboards: Chart.js, cores CEVICO) ──
const shortName = n => ((n || '').length > 26 ? `${(n || '').slice(0, 25)}…` : n || '');

// Investimento × Receita por anúncio: barras deitadas (nome legível);
// anúncio bom = barra dourada maior que a do investimento (cor do bloco)
const investChart = computed(() => {
  const top = [...rows.value]
    .filter(r => r.spend > 0 || r.revenue > 0)
    .sort((a, b) => (b.spend || 0) - (a.spend || 0))
    .slice(0, 8);
  if (!top.length) return null;
  const barBase = { borderRadius: 6, borderSkipped: false, maxBarThickness: 16 };
  const investColor = hexFromGrad(blockFamily('investimento')[1]) || AZUL;
  return {
    data: {
      labels: top.map(r => shortName(r.ad_name)),
      datasets: [
        { label: 'Investimento', data: top.map(r => r.spend || 0), backgroundColor: investColor + 'E6', ...barBase },
        { label: 'Receita (CRM)', data: top.map(r => r.revenue || 0), backgroundColor: OURO + 'E6', ...barBase },
      ],
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 400 },
      plugins: {
        legend: { position: 'bottom', labels: { boxWidth: 12, padding: 12, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${formatMoneyShort(ctx.raw)}` } },
      },
      scales: {
        x: { ticks: { callback: v => formatMoneyShort(v), maxTicksLimit: 6 }, grid: { color: 'rgba(120,140,180,0.12)' } },
        y: { grid: { display: false }, ticks: { font: { size: 10 } } },
      },
    },
  };
});

// Leads × Conversões por anúncio (funil de cada anúncio, lado a lado)
const leadsChart = computed(() => {
  const top = [...rows.value]
    .filter(r => (r.leads || 0) > 0)
    .sort((a, b) => (b.leads || 0) - (a.leads || 0))
    .slice(0, 8);
  if (!top.length) return null;
  const barBase = { borderRadius: 8, borderSkipped: false, maxBarThickness: 26 };
  const leadsColor = hexFromGrad(blockFamily('leads')[1]) || ROXO;
  return {
    data: {
      labels: top.map(r => shortName(r.ad_name)),
      datasets: [
        { label: 'Leads', data: top.map(r => r.leads || 0), backgroundColor: leadsColor + 'E6', ...barBase },
        { label: 'Conversões', data: top.map(r => r.conversions || 0), backgroundColor: VERDE + 'E6', ...barBase },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 400 },
      plugins: {
        legend: { position: 'bottom', labels: { boxWidth: 12, padding: 12, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${formatNumber(ctx.raw)}` } },
      },
      scales: {
        y: { beginAtZero: true, ticks: { precision: 0, maxTicksLimit: 6 }, grid: { color: 'rgba(120,140,180,0.12)' } },
        x: { grid: { display: false }, ticks: { font: { size: 10 }, maxRotation: 30 } },
      },
    },
  };
});

// Onde está o investimento (fatia de cada anúncio no total gasto)
const spendShareChart = computed(() => {
  const spenders = [...rows.value]
    .filter(r => (r.spend || 0) > 0)
    .sort((a, b) => (b.spend || 0) - (a.spend || 0));
  if (!spenders.length) return null;
  const top = spenders.slice(0, 5);
  const rest = spenders.slice(5).reduce((acc, r) => acc + (r.spend || 0), 0);
  const labels = top.map(r => shortName(r.ad_name)).concat(rest > 0 ? ['Outros anúncios'] : []);
  const values = top.map(r => r.spend || 0).concat(rest > 0 ? [rest] : []);
  const palette = [AZUL, ROXO, VERDE, OURO, AMBAR, CIANO];
  return {
    data: {
      labels,
      datasets: [{ data: values, backgroundColor: palette.slice(0, labels.length), borderWidth: 0, borderRadius: 6, spacing: 3 }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      cutout: '62%',
      animation: { duration: 400 },
      plugins: {
        legend: { position: 'bottom', labels: { boxWidth: 10, padding: 10, font: { size: 10 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.label}: ${formatMoneyShort(ctx.raw)}` } },
      },
    },
  };
});

// como cada número nasce — por extenso, no padrão do kit (nunca restar dúvida)
const FORMULAS = [
  { label: 'Leads', text: 'contatos que chegaram clicando no anúncio (dado da Meta na 1ª mensagem)' },
  { label: 'Conversões', text: 'o card do lead passou pela(s) coluna(s) escolhida(s) na faixa verde acima' },
  { label: 'CPL', text: 'investimento ÷ leads' },
  { label: 'CAC', text: 'investimento ÷ conversões' },
  { label: 'Receita (CRM)', text: 'soma do valor em R$ dos cards dos leads que converteram' },
  { label: 'ROAS', text: 'receita ÷ investimento (quanto voltou de cada R$ 1)' },
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
  if (!names.length) return 'Nenhuma coluna de conversão escolhida — clique em "alterar" e escolha (ex.: Cirurgia Agendada).';
  const cols = names.map(n => `“${n}”`).join(' ou ');
  return `Conversão deste painel = o card do lead PASSAR pela coluna ${cols} — vale para leads que CHEGARAM pelo anúncio no período, mesmo que a cirurgia feche depois.`;
});
</script>

<template>
  <div class="cv-page flex flex-col h-full overflow-y-auto bg-n-surface-1" :style="cvVars">
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

      <div v-else-if="hasError" class="text-center py-16 text-sm text-n-slate-10">
        Não foi possível carregar o relatório. Tente novamente.
      </div>

      <template v-else-if="data">
        <!-- Meta não configurada (âmbar = atenção) -->
        <div
          v-if="!data.configured"
          class="cv-block cv-strip cv-amber flex items-start gap-3 px-4 py-3.5 mb-4 text-sm text-n-slate-11"
        >
          <span class="cv-icon cv-icon-sm mt-0.5"><span class="i-lucide-plug-zap text-xs" /></span>
          <div class="flex-1 min-w-0">
            <p class="font-medium text-n-slate-12 mb-1">Conecte a conta de anúncios da Meta</p>
            <p>
              Preencha o <b>token de acesso</b> e o <b>ID da conta de anúncios</b> em
              Configurações → Integrações → Meta. Os leads atribuídos por anúncio (abaixo)
              funcionam mesmo sem isso — só o investimento/impressões dependem da conexão.
            </p>
          </div>
        </div>

        <!-- Erro da API da Meta (vermelho = problema) -->
        <div
          v-else-if="data.error"
          class="cv-block cv-strip cv-red flex items-start gap-3 px-4 py-3.5 mb-4 text-sm text-n-slate-11"
        >
          <span class="cv-icon cv-icon-sm mt-0.5"><span class="i-lucide-triangle-alert text-xs" /></span>
          <div class="flex-1 min-w-0">
            <p class="font-medium text-n-slate-12 mb-1">A Meta respondeu com erro</p>
            <p class="break-words">{{ data.error }}</p>
          </div>
        </div>

        <!-- Backfill pendente -->
        <div
          v-if="data.needs_backfill"
          class="cv-block cv-strip px-4 py-3.5 mb-4 flex items-center gap-3 flex-wrap"
        >
          <span class="cv-icon cv-icon-sm"><span class="i-lucide-history text-xs" /></span>
          <div class="flex-1 min-w-[240px] text-sm text-n-slate-11">
            <p class="font-medium text-n-slate-12">Há mensagens antigas com dados de anúncio</p>
            <p class="text-xs">Processe o histórico uma vez para carimbar a origem nos contatos antigos.</p>
          </div>
          <button
            class="cv-btn cv-btn-sm"
            :disabled="isBackfilling"
            @click="runBackfill"
          >
            <span v-if="isBackfilling" class="i-lucide-loader-2 animate-spin text-xs" />
            <span v-else class="i-lucide-history text-xs" />
            Processar histórico
          </button>
        </div>

        <!-- A CONVERSÃO POR EXTENSO (clareza total do que o painel conta).
             Continua VERDE de propósito: é "a faixa verde" citada nas fórmulas -->
        <div class="cv-block cv-strip cv-green p-4 mb-6">
          <div class="flex items-start gap-2.5 flex-wrap">
            <span class="cv-icon cv-icon-sm mt-0.5"><span class="i-lucide-target text-xs" /></span>
            <p class="flex-1 min-w-[240px] text-xs text-n-slate-11 leading-relaxed">
              <b class="text-n-slate-12">{{ conversionSentence }}</b>
            </p>
            <button
              class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
              @click="showStagePicker = !showStagePicker"
            >
              <span :class="showStagePicker ? 'i-lucide-x' : 'i-lucide-pencil'" class="text-xs" />
              {{ showStagePicker ? 'fechar' : 'alterar' }}
            </button>
          </div>

          <div v-if="showStagePicker" class="mt-3 pt-3" style="border-top: 1px solid rgb(var(--cv-rgb) / 0.2)">
            <p class="text-xs font-medium text-n-slate-12 mb-2">
              Colunas do CRM que contam como conversão (escolha as de venda fechada — indicação ainda não é venda):
            </p>
            <div class="flex flex-wrap gap-2 mb-3">
              <button
                v-for="stage in data.stages"
                :key="stage.id"
                class="cv-btn cv-btn-sm"
                :class="draftStageIds.includes(stage.id) ? '' : 'cv-btn-ghost'"
                @click="toggleDraftStage(stage.id)"
              >
                <span v-if="draftStageIds.includes(stage.id)" class="i-lucide-check text-xs" />
                {{ stage.name }}
              </button>
            </div>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="isSavingStages"
              @click="saveStages"
            >
              <span v-if="isSavingStages" class="i-lucide-loader-2 animate-spin text-xs" />
              Salvar
            </button>
          </div>
        </div>

        <!-- 📊 Números do período: KPIs dopamine + ROAS + campeão -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('kpis')">
          <div class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-gauge text-base" /></span>
            <h2 class="text-sm font-bold text-n-slate-12">Números do período</h2>
          </div>

          <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mb-3">
            <div v-for="(card, ci) in kpiCards" :key="card.key" class="cv-sub p-3.5">
              <div class="flex items-center gap-2 mb-1.5">
                <span class="cv-icon cv-icon-sm" :style="{ background: blockFamily('kpis')[ci % 4] }">
                  <span :class="card.icon" class="text-xs" />
                </span>
                <p class="text-[10px] font-bold text-n-slate-11 leading-tight">{{ card.label }}</p>
              </div>
              <p class="text-lg font-bold tabular-nums text-n-slate-12">{{ card.value }}</p>
            </div>
          </div>

          <!-- ROAS + campeão do período -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div class="cv-sub p-4 flex items-center gap-3">
              <span class="cv-icon" :style="{ background: roasTone(totals.roas).color }">
                <span class="i-lucide-trending-up text-base" />
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
            <div v-if="champion" class="cv-sub cv-sub-on p-4 flex items-center gap-3">
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
        </div>

        <!-- Como cada número é calculado — por extenso, sem mistério -->
        <div class="cv-block cv-strip px-4 py-3 mb-6" :style="blockVars('formulas')">
          <div class="flex items-center gap-2 mb-2">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-info text-xs" /></span>
            <p class="text-[11px] font-bold text-n-slate-11">Como cada número é calculado</p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-x-6 gap-y-1">
            <p v-for="f in FORMULAS" :key="f.label" class="text-[11px] text-n-slate-10">
              <span class="font-bold text-n-slate-11">{{ f.label }}</span> = {{ f.text }}
            </p>
          </div>
        </div>

        <!-- Gráficos: o impacto de cada anúncio, visual -->
        <div v-if="investChart || spendShareChart" class="grid grid-cols-1 xl:grid-cols-3 gap-4 mb-6">
          <div v-if="investChart" class="xl:col-span-2 cv-block p-5 sm:p-6" :style="blockVars('investimento')">
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"><span class="i-lucide-chart-bar text-base" /></span>
              <h3 class="text-sm font-bold text-n-slate-12">Investimento × retorno por anúncio</h3>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">anúncio saudável = barra dourada (o que voltou) maior que a barra do investimento (o que saiu)</p>
            <div class="h-72">
              <Bar :data="investChart.data" :options="investChart.options" />
            </div>
          </div>
          <div v-if="spendShareChart" class="cv-block p-5 sm:p-6" :style="blockVars('fatia')">
            <div class="flex items-center gap-2 mb-1 flex-wrap">
              <span class="cv-icon"><span class="i-lucide-chart-pie text-base" /></span>
              <h3 class="text-sm font-bold text-n-slate-12">Onde está o investimento</h3>
            </div>
            <p class="text-[11px] text-n-slate-10 mb-3">fatia de cada anúncio no total gasto do período</p>
            <div class="h-72">
              <Doughnut :data="spendShareChart.data" :options="spendShareChart.options" />
            </div>
          </div>
        </div>
        <div v-if="leadsChart" class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('leads')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-users text-base" /></span>
            <h3 class="text-sm font-bold text-n-slate-12">Leads e conversões por anúncio</h3>
          </div>
          <p class="text-[11px] text-n-slate-10 mb-3">quantos chegaram por cada anúncio (barra na cor do bloco) — e quantos desses viraram conversão (verde)</p>
          <div class="h-64">
            <Bar :data="leadsChart.data" :options="leadsChart.options" />
          </div>
        </div>

        <!-- Tabela por anúncio -->
        <div class="cv-block mb-6" :style="blockVars('tabela')">
          <div class="px-5 py-4 flex items-center gap-2 flex-wrap" style="border-bottom: 1px solid rgb(var(--cv-rgb) / 0.18)">
            <span class="cv-icon"><span class="i-lucide-list-ordered text-base" /></span>
            <h2 class="text-sm font-bold text-n-slate-12">Anúncio por anúncio</h2>
            <span class="text-[11px] text-n-slate-9 ml-auto">
              {{ formatNumber(data.unattributed_leads) }} contato(s) novo(s) no período sem anúncio identificado
            </span>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-sm min-w-[900px]">
              <thead>
                <tr class="text-left text-[10px] uppercase tracking-wide text-n-slate-9" style="border-bottom: 1px solid rgb(var(--cv-rgb) / 0.18)">
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
                  class="last:border-0 hover:bg-n-alpha-1"
                  style="border-bottom: 1px solid rgb(var(--cv-rgb) / 0.1)"
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
                  <td class="px-3 py-2.5 text-right tabular-nums font-bold" :style="{ color: row.leads ? 'var(--cv)' : undefined }">
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
