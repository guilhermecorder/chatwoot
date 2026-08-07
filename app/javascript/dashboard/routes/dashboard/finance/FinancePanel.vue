<script setup>
// GESTÃO FINANCEIRA (só admin): o caixa da CEVICO num lugar só —
// lançamentos de receitas, tributos, custos (serviços, comissões,
// distribuição de lucros, serviços médicos, sala cirúrgica) e
// investimentos (produto/estoque e equipamentos). Dashboard com os
// indicadores do período (presets + PERSONALIZADO com datas livres),
// histórico de 12 meses em LINHA (mesma linguagem dos outros painéis)
// e comparação de dois meses lado a lado.
import { ref, computed, onMounted, watch } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import StockTab from './StockTab.vue';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  Chart as ChartJS,
  Tooltip, Legend,
  CategoryScale, LinearScale,
  PointElement, LineElement, Filler,
  ArcElement,
} from 'chart.js';
import { Line, Doughnut } from 'vue-chartjs';

ChartJS.register(
  Tooltip, Legend,
  CategoryScale, LinearScale,
  PointElement, LineElement, Filler,
  ArcElement,
);

// paleta oficial
const VERDE = '#059669';
const VERMELHO = '#DC2626';
const AMBAR = '#D97706';
const OURO = '#D4A017';
const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';
// VERDE é a cor principal dos gráficos (item 68): a família de verdes
// lidera e as demais cores só apoiam quando há muitas categorias
const PALETTE = ['#059669', '#0F766E', '#84CC16', '#34D399', OURO, AZUL, ROXO, '#22D3EE', '#EA580C', '#F472B6', '#A78BFA', '#94A3B8'];

// identidade visual por tipo de lançamento
const KIND_META = {
  receita: { color: VERDE, icon: 'i-lucide-trending-up' },
  tributo: { color: AMBAR, icon: 'i-lucide-landmark' },
  custo: { color: VERMELHO, icon: 'i-lucide-trending-down' },
  investimento_produto: { color: AZUL, icon: 'i-lucide-package' },
  investimento_equipamento: { color: ROXO, icon: 'i-lucide-microscope' },
};

const isLoading = ref(true);
const data = ref(null);

// ── abas ──
const tab = ref('overview'); // overview | entries | compare
const TABS = [
  { key: 'overview', label: 'Visão geral', icon: 'i-lucide-chart-line' },
  { key: 'entries', label: 'Lançamentos', icon: 'i-lucide-list-plus' },
  { key: 'stock', label: 'Estoque', icon: 'i-lucide-package' },
  { key: 'compare', label: 'Comparar meses', icon: 'i-lucide-columns-2' },
];

// ── período: régua PADRÃO CEVICO (06/08) — default 'month' ──
const period = ref({ preset: 'month', from: '', to: '' });

const load = async () => {
  isLoading.value = true;
  try {
    const params = {
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
    };
    const { data: payload } = await CrmAPI.getFinance(params);
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar o financeiro.');
  } finally {
    isLoading.value = false;
  }
};

watch(period, load, { deep: true });
onMounted(load);

// ── formatação ──
const fmtMoney = (v, cents = false) =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: cents ? 2 : 0,
    maximumFractionDigits: cents ? 2 : 0,
  })}`;
const fmtCompact = v => {
  const n = Number(v || 0);
  if (Math.abs(n) >= 1000) return `R$ ${(n / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}k`;
  return `R$ ${n.toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`;
};
const fmtDate = iso => new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR');
const monthShort = iso =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' });
const monthLong = iso =>
  new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });

// aceita "1.234,56", "1234,56" e "1234.56"
const parseAmount = raw => {
  let s = String(raw || '').replace(/[R$\s]/g, '');
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
  const n = parseFloat(s);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
};

const periodLabel = computed(() => {
  const p = data.value?.period;
  if (!p) return '';
  return p.from === p.to ? fmtDate(p.from) : `${fmtDate(p.from)} → ${fmtDate(p.to)}`;
});

// ── KPIs da visão geral — DOPAMINE COLORS (pedido 19/07): cards em
// degradê pleno com fonte branca, mesma linguagem do Meu Painel ──
const summary = computed(() => data.value?.summary || {});
const GRADS = {
  verde: 'linear-gradient(135deg, #065F46, #10B981)',
  vermelho: 'linear-gradient(135deg, #B91C1C, #F87171)',
  ambar: 'linear-gradient(135deg, #B45309, #FBBF24)',
  ouro: 'linear-gradient(135deg, #B8860B, #D4A017)',
  azul: 'linear-gradient(135deg, #0F5FA6, #3B82F6)',
  roxo: 'linear-gradient(135deg, #5B21B6, #7C3AED)',
  teal: 'linear-gradient(135deg, #0F766E, #14B8A6)',
};
const kpiCards = computed(() => [
  { key: 'receita', label: 'Receita', value: summary.value.receita, grad: GRADS.verde, icon: 'i-lucide-trending-up' },
  { key: 'custo', label: 'Custos', value: summary.value.custo, grad: GRADS.vermelho, icon: 'i-lucide-trending-down' },
  { key: 'tributo', label: 'Tributos', value: summary.value.tributo, grad: GRADS.ambar, icon: 'i-lucide-landmark' },
  {
    key: 'lucro',
    label: 'Lucro do período',
    value: summary.value.lucro,
    grad: (summary.value.lucro || 0) >= 0 ? GRADS.ouro : GRADS.vermelho,
    icon: 'i-lucide-piggy-bank',
    badge: summary.value.margem != null ? `${summary.value.margem.toLocaleString('pt-BR')}% de margem` : null,
  },
]);
const investCards = computed(() => [
  { key: 'investimento_produto', label: 'Produto & Estoque', value: summary.value.investimento_produto, grad: GRADS.azul, icon: 'i-lucide-package', hint: 'investimento no período' },
  { key: 'investimento_equipamento', label: 'Equipamentos', value: summary.value.investimento_equipamento, grad: GRADS.roxo, icon: 'i-lucide-microscope', hint: 'investimento no período' },
  {
    key: 'caixa',
    label: 'Resultado do caixa',
    value: summary.value.caixa,
    grad: (summary.value.caixa || 0) >= 0 ? GRADS.teal : GRADS.vermelho,
    icon: 'i-lucide-wallet',
    hint: 'lucro − investimentos',
  },
]);

// ── gráfico de LINHA: histórico de 12 meses ──
const lineChart = computed(() => {
  const m = data.value?.monthly;
  if (!m?.length) return null;
  // hierarquia de peso (item 68: VERDE é a cor principal): Receita, verde
  // e preenchida, é a protagonista; Lucro ouro logo atrás; Tributos fica
  // fininha pra não competir com o ouro (cores vizinhas)
  const line = (label, key, color, { dashed = false, width = 2.5 } = {}) => ({
    label,
    data: m.map(x => x[key]),
    borderColor: color,
    backgroundColor: `${color}22`,
    pointBackgroundColor: color,
    pointRadius: width >= 3 ? 3 : 2,
    pointHoverRadius: 5,
    borderWidth: width,
    tension: 0.35,
    fill: key === 'receita',
    borderDash: dashed ? [6, 4] : [],
  });
  return {
    data: {
      labels: m.map(x => monthShort(x.month)),
      datasets: [
        line('Receita', 'receita', VERDE, { width: 3.5 }),
        line('Custos', 'custos', VERMELHO, { width: 2 }),
        line('Tributos', 'tributos', AMBAR, { width: 1.5 }),
        line('Lucro', 'lucro', OURO, { width: 2.5 }),
        line('Investimentos', 'investimentos', AZUL, { dashed: true, width: 2 }),
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 500, easing: 'easeOutQuart' },
      plugins: {
        legend: { display: true, position: 'bottom', labels: { boxWidth: 12, padding: 14, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${fmtMoney(ctx.raw, true)}` } },
      },
      scales: {
        y: { ticks: { callback: v => fmtCompact(v) }, grid: { color: 'rgba(120,140,180,0.12)' } },
        x: { grid: { display: false } },
      },
    },
  };
});

// donut com o mesmo aspecto "macio" dos outros painéis
const shinySlices = colors => ctx => {
  const base = colors[ctx.dataIndex % colors.length];
  const { chartArea, ctx: c } = ctx.chart;
  if (!chartArea) return base;
  const g = c.createLinearGradient(chartArea.left, chartArea.top, chartArea.left, chartArea.bottom);
  g.addColorStop(0, `${base}99`);
  g.addColorStop(1, base);
  return g;
};
const doughnutFor = rows => {
  if (!rows?.length) return null;
  return {
    data: {
      labels: rows.map(r => r.label),
      datasets: [{
        data: rows.map(r => r.total),
        backgroundColor: shinySlices(PALETTE),
        borderWidth: 0,
        borderRadius: 14,
        spacing: 3,
        hoverOffset: 6,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: true, position: 'bottom', labels: { padding: 12, boxWidth: 12, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.label}: ${fmtMoney(ctx.raw, true)}` } },
      },
      cutout: '66%',
      animation: { duration: 500, easing: 'easeOutQuart' },
    },
  };
};
const custosChart = computed(() => doughnutFor(data.value?.by_category?.custo));
const receitasChart = computed(() => doughnutFor(data.value?.by_category?.receita));

// ── lançamentos (criar / editar / excluir) ──
const todayIso = () => new Date().toISOString().slice(0, 10);
const blankForm = () => ({ entry_date: todayIso(), kind: 'receita', category: '', description: '', amount: '' });
const form = ref(blankForm());
const editingId = ref(null);
const savingEntry = ref(false);

const categoriesForKind = computed(() => data.value?.categories?.[form.value.kind] || {});
const onKindChange = () => {
  form.value.category = Object.keys(categoriesForKind.value)[0] || '';
};

const startEdit = entry => {
  editingId.value = entry.id;
  form.value = {
    entry_date: entry.entry_date,
    kind: entry.kind,
    category: entry.category || '',
    description: entry.description,
    amount: entry.amount.toLocaleString('pt-BR', { minimumFractionDigits: 2 }),
  };
};
const cancelEdit = () => {
  editingId.value = null;
  form.value = blankForm();
};

const saveEntry = async () => {
  const amount = parseAmount(form.value.amount);
  if (!amount) {
    useAlert('Informe o valor do lançamento.');
    return;
  }
  if (!form.value.description.trim()) {
    useAlert('Descreva o lançamento (ex: comissão da Gabriela, lente Galaxy…).');
    return;
  }
  savingEntry.value = true;
  try {
    const payload = { ...form.value, amount, description: form.value.description.trim() };
    if (editingId.value) await CrmAPI.updateFinanceEntry(editingId.value, payload);
    else await CrmAPI.createFinanceEntry(payload);
    useAlert(editingId.value ? 'Lançamento atualizado. 💰' : 'Lançamento registrado. 💰');
    cancelEdit();
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o lançamento.');
  } finally {
    savingEntry.value = false;
  }
};

const removeEntry = async entry => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir "${entry.description}" (${fmtMoney(entry.amount, true)})?`)) return;
  try {
    await CrmAPI.deleteFinanceEntry(entry.id);
    await load();
  } catch {
    useAlert('Não consegui excluir.');
  }
};

// ── comparar meses ──
const thisMonthInput = () => new Date().toISOString().slice(0, 7);
const lastMonthInput = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth() - 1, 15).toISOString().slice(0, 7);
};
const monthA = ref(lastMonthInput());
const monthB = ref(thisMonthInput());
const compareData = ref(null);
const comparing = ref(false);

const runCompare = async () => {
  if (!monthA.value || !monthB.value) return;
  comparing.value = true;
  try {
    const { data: payload } = await CrmAPI.compareFinanceMonths(`${monthA.value}-01`, `${monthB.value}-01`);
    compareData.value = payload;
  } catch {
    useAlert('Não consegui comparar os meses.');
  } finally {
    comparing.value = false;
  }
};

// linhas da comparação: label + A + B + direção "boa" do delta
const COMPARE_ROWS = [
  { key: 'receita', label: 'Receita', goodWhenUp: true },
  { key: 'custo', label: 'Custos', goodWhenUp: false },
  { key: 'tributo', label: 'Tributos', goodWhenUp: false },
  { key: 'investimentos', label: 'Investimentos', goodWhenUp: null },
  { key: 'lucro', label: 'Lucro', goodWhenUp: true },
  { key: 'caixa', label: 'Resultado do caixa', goodWhenUp: true },
];
const compareRows = computed(() => {
  if (!compareData.value) return [];
  const a = compareData.value.a.summary;
  const b = compareData.value.b.summary;
  return COMPARE_ROWS.map(row => {
    const va = a[row.key] || 0;
    const vb = b[row.key] || 0;
    const delta = vb - va;
    const pct = va ? (delta / Math.abs(va)) * 100 : null;
    let tone = 'neutral';
    if (row.goodWhenUp !== null && delta !== 0) {
      tone = delta > 0 === row.goodWhenUp ? 'good' : 'bad';
    }
    return { ...row, va, vb, delta, pct, tone };
  });
});

// quebra de custos lado a lado (categoria → A/B)
const compareCosts = computed(() => {
  if (!compareData.value) return [];
  const rowsA = compareData.value.a.by_category?.custo || [];
  const rowsB = compareData.value.b.by_category?.custo || [];
  const keys = [...new Set([...rowsA, ...rowsB].map(r => `${r.category}`))];
  return keys.map(k => {
    const ra = rowsA.find(r => `${r.category}` === k);
    const rb = rowsB.find(r => `${r.category}` === k);
    return {
      key: k,
      label: ra?.label || rb?.label || 'Sem categoria',
      va: ra?.total || 0,
      vb: rb?.total || 0,
    };
  }).sort((x, y) => y.vb + y.va - (x.vb + x.va));
});
</script>

<template>
  <div class="h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto p-4 sm:p-8">
      <!-- cabeçalho -->
      <div
        class="rounded-3xl p-6 sm:p-8 text-white shadow-lg mb-6 relative overflow-hidden"
        style="background: linear-gradient(135deg, #065f46, #10b981)"
      >
        <div class="relative z-10" style="color: #fff">
          <h1 class="text-2xl sm:text-3xl font-bold leading-tight" style="color: #fff">Gestão Financeira</h1>
          <p class="text-sm mt-1.5" style="color: rgba(255,255,255,0.85)">
            Receitas, tributos, custos e investimentos — a saúde do caixa da CEVICO, com histórico e comparação de meses.
          </p>
        </div>
        <span class="i-lucide-wallet absolute -right-5 -bottom-7 text-[140px] text-white/10" />
      </div>

      <!-- abas -->
      <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto mb-4">
        <button
          v-for="tb in TABS"
          :key="tb.key"
          class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex items-center gap-1.5"
          :class="tab === tb.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="tab === tb.key ? { background: 'linear-gradient(135deg, #065F46, #10B981)' } : {}"
          @click="tab = tb.key"
        >
          <span :class="tb.icon" class="text-sm" />
          {{ tb.label }}
        </button>
      </div>

      <!-- período (vale para Visão geral e Lançamentos) — régua padrão CEVICO -->
      <div v-if="tab !== 'compare' && tab !== 'stock'" class="mb-5">
        <PeriodRuler v-model="period" />
        <p v-if="data?.period" class="text-[11px] text-n-slate-9 mt-2">
          Analisando: <b class="text-n-slate-11">{{ periodLabel }}</b> · {{ summary.lancamentos || 0 }} lançamento(s)
        </p>
      </div>

      <!-- ════════ ESTOQUE (carrega os próprios dados) ════════ -->
      <StockTab v-if="tab === 'stock'" />

      <SkeletonScreen v-else-if="isLoading" variant="dashboard" />

      <template v-else-if="data">
        <!-- ════════ VISÃO GERAL ════════ -->
        <template v-if="tab === 'overview'">
          <!-- indicadores principais — dopamine: degradê pleno + fonte branca -->
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
            <div
              v-for="card in kpiCards"
              :key="card.key"
              class="relative rounded-2xl p-4 text-white shadow-md overflow-hidden"
              :style="{ background: card.grad }"
            >
              <span :class="card.icon" class="absolute -right-2 -bottom-3 text-[64px] text-white/15 pointer-events-none" />
              <p class="text-[11px] font-bold leading-tight relative" style="color: rgba(255,255,255,0.9)">{{ card.label }}</p>
              <p class="text-xl sm:text-2xl font-bold tabular-nums mt-1.5 relative" style="color: #fff">
                {{ fmtMoney(card.value) }}
              </p>
              <span
                v-if="card.badge"
                class="inline-block mt-1.5 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-black/20 relative"
                style="color: #fff"
              >
                {{ card.badge }}
              </span>
            </div>
          </div>

          <!-- investimentos + caixa — dopamine -->
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
            <div
              v-for="card in investCards"
              :key="card.key"
              class="relative rounded-2xl p-4 text-white shadow-md overflow-hidden"
              :style="{ background: card.grad }"
            >
              <span :class="card.icon" class="absolute -right-2 -bottom-3 text-[56px] text-white/15 pointer-events-none" />
              <p class="text-[11px] font-bold leading-tight relative" style="color: rgba(255,255,255,0.9)">{{ card.label }}</p>
              <p class="text-[10px] relative" style="color: rgba(255,255,255,0.65)">{{ card.hint }}</p>
              <p class="text-lg font-bold tabular-nums mt-1 relative" style="color: #fff">
                {{ fmtMoney(card.value) }}
              </p>
            </div>
          </div>

          <!-- histórico de 12 meses (linha) -->
          <div class="rounded-2xl border border-n-weak bg-n-card p-4 sm:p-5 mb-3">
            <div class="flex items-center gap-2 mb-3">
              <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #065F46, #10B981)">
                <span class="i-lucide-chart-line text-white text-sm" />
              </span>
              <h2 class="text-sm font-bold text-n-slate-12">Histórico de 12 meses</h2>
              <span class="text-[11px] text-n-slate-9 ml-auto">receita · custos · tributos · lucro · investimentos</span>
            </div>
            <div class="h-72">
              <Line v-if="lineChart" :data="lineChart.data" :options="lineChart.options" />
            </div>
          </div>

          <!-- categorias do período -->
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3 mb-6">
            <div class="rounded-2xl border border-n-weak bg-n-card p-4 sm:p-5">
              <h3 class="text-xs font-bold text-n-slate-12 mb-3 flex items-center gap-1.5">
                <span class="w-2 h-2 rounded-full" style="background: #DC2626" />
                Custos por categoria (no período)
              </h3>
              <div v-if="custosChart" class="h-56">
                <Doughnut :data="custosChart.data" :options="custosChart.options" />
              </div>
              <p v-else class="text-[11px] text-n-slate-9 py-8 text-center">Nenhum custo lançado no período.</p>
            </div>
            <div class="rounded-2xl border border-n-weak bg-n-card p-4 sm:p-5">
              <h3 class="text-xs font-bold text-n-slate-12 mb-3 flex items-center gap-1.5">
                <span class="w-2 h-2 rounded-full" style="background: #059669" />
                Receitas por categoria (no período)
              </h3>
              <div v-if="receitasChart" class="h-56">
                <Doughnut :data="receitasChart.data" :options="receitasChart.options" />
              </div>
              <p v-else class="text-[11px] text-n-slate-9 py-8 text-center">Nenhuma receita lançada no período.</p>
            </div>
          </div>
        </template>

        <!-- ════════ LANÇAMENTOS ════════ -->
        <template v-else-if="tab === 'entries'">
          <!-- formulário de lançamento -->
          <div class="rounded-2xl border border-n-weak bg-n-card p-4 sm:p-5 mb-4">
            <h2 class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2">
              <span class="i-lucide-plus-circle text-base" style="color: #0F766E" />
              {{ editingId ? 'Editar lançamento' : 'Novo lançamento' }}
            </h2>
            <div class="flex items-end gap-2.5 flex-wrap">
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Data</span>
                <input
                  v-model="form.entry_date"
                  type="date"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 10rem; margin-bottom: 0"
                />
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Tipo</span>
                <select
                  v-model="form.kind"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 11rem; margin-bottom: 0; border: 1px solid rgba(148, 163, 184, 0.35); background-color: transparent"
                  @change="onKindChange"
                >
                  <option v-for="(label, k) in data.kinds" :key="k" :value="k">{{ label }}</option>
                </select>
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Categoria</span>
                <select
                  v-model="form.category"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 12rem; margin-bottom: 0; border: 1px solid rgba(148, 163, 184, 0.35); background-color: transparent"
                >
                  <option value="">Sem categoria</option>
                  <option v-for="(label, c) in categoriesForKind" :key="c" :value="c">{{ label }}</option>
                </select>
              </label>
              <label class="block flex-1" style="min-width: 14rem">
                <span class="text-[11px] font-medium text-n-slate-11">Descrição</span>
                <input
                  v-model="form.description"
                  type="text"
                  placeholder="Ex: sala cirúrgica — mutirão de catarata"
                  class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="margin-bottom: 0"
                  @keyup.enter="saveEntry"
                />
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Valor (R$)</span>
                <input
                  v-model="form.amount"
                  type="text"
                  inputmode="decimal"
                  placeholder="1.500,00"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
                  style="width: 8rem; margin-bottom: 0"
                  @keyup.enter="saveEntry"
                />
              </label>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                style="background: linear-gradient(135deg, #065F46, #10B981)"
                :disabled="savingEntry"
                @click="saveEntry"
              >
                {{ savingEntry ? 'Salvando…' : editingId ? 'Salvar alterações' : 'Adicionar' }}
              </button>
              <button
                v-if="editingId"
                class="h-9 px-3 rounded-lg text-xs font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1"
                @click="cancelEdit"
              >
                Cancelar
              </button>
            </div>
          </div>

          <!-- lista do período -->
          <div class="rounded-2xl border border-n-weak bg-n-card overflow-hidden">
            <div class="px-4 sm:px-5 py-3 border-b border-n-weak flex items-center gap-2">
              <h2 class="text-sm font-bold text-n-slate-12">Lançamentos do período</h2>
              <span class="text-[11px] text-n-slate-9 ml-auto">{{ data.entries.length }} registro(s)</span>
            </div>
            <div v-if="!data.entries.length" class="py-12 text-center">
              <p class="text-3xl mb-2">💸</p>
              <p class="text-sm font-semibold text-n-slate-12 mb-1">Nenhum lançamento no período</p>
              <p class="text-xs text-n-slate-10">Registre a primeira receita ou custo no formulário acima.</p>
            </div>
            <div v-else class="divide-y divide-n-weak">
              <div
                v-for="entry in data.entries"
                :key="entry.id"
                class="px-4 sm:px-5 py-2.5 flex items-center gap-3 hover:bg-n-alpha-1 transition-colors"
              >
                <span class="text-[11px] text-n-slate-9 tabular-nums flex-shrink-0" style="width: 4.5rem">
                  {{ fmtDate(entry.entry_date).slice(0, 5) }}
                </span>
                <span
                  class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                  :style="{ background: `${KIND_META[entry.kind]?.color}1A`, color: KIND_META[entry.kind]?.color }"
                >
                  {{ entry.kind_label }}
                </span>
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-medium text-n-slate-12 truncate">{{ entry.description }}</p>
                  <p class="text-[10px] text-n-slate-9">{{ entry.category_label }}</p>
                </div>
                <b
                  class="text-xs tabular-nums flex-shrink-0"
                  :style="{ color: entry.kind === 'receita' ? '#059669' : '#DC2626' }"
                >
                  {{ entry.kind === 'receita' ? '+' : '−' }} {{ fmtMoney(entry.amount, true) }}
                </b>
                <button
                  class="w-7 h-7 rounded-lg hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-10 flex-shrink-0"
                  title="Editar"
                  @click="startEdit(entry)"
                >
                  <span class="i-lucide-pencil text-xs" />
                </button>
                <button
                  class="w-7 h-7 rounded-lg hover:bg-red-500/10 flex items-center justify-center text-n-slate-10 hover:text-red-500 flex-shrink-0"
                  title="Excluir"
                  @click="removeEntry(entry)"
                >
                  <span class="i-lucide-trash-2 text-xs" />
                </button>
              </div>
            </div>
          </div>
        </template>

        <!-- ════════ COMPARAR MESES ════════ -->
        <template v-else>
          <div class="rounded-2xl border border-n-weak bg-n-card p-4 sm:p-5 mb-4">
            <div class="flex items-end gap-2.5 flex-wrap">
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Mês A</span>
                <input
                  v-model="monthA"
                  type="month"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 11rem; margin-bottom: 0"
                />
              </label>
              <span class="i-lucide-arrow-right-left text-base text-n-slate-9 mb-2" />
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Mês B</span>
                <input
                  v-model="monthB"
                  type="month"
                  class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
                  style="width: 11rem; margin-bottom: 0"
                />
              </label>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                style="background: linear-gradient(135deg, #065F46, #10B981)"
                :disabled="comparing"
                @click="runCompare"
              >
                {{ comparing ? 'Comparando…' : 'Comparar' }}
              </button>
            </div>
          </div>

          <template v-if="compareData">
            <!-- indicadores lado a lado -->
            <div class="rounded-2xl border border-n-weak bg-n-card overflow-hidden mb-4">
              <div class="grid items-center px-4 sm:px-5 py-3 border-b border-n-weak text-[11px] font-bold text-n-slate-11" style="grid-template-columns: 1.4fr 1fr 1fr 0.9fr">
                <span>Indicador</span>
                <span class="text-right capitalize">{{ monthLong(compareData.a.month) }}</span>
                <span class="text-right capitalize">{{ monthLong(compareData.b.month) }}</span>
                <span class="text-right">Variação</span>
              </div>
              <div
                v-for="row in compareRows"
                :key="row.key"
                class="grid items-center px-4 sm:px-5 py-3 border-b border-n-weak last:border-0"
                style="grid-template-columns: 1.4fr 1fr 1fr 0.9fr"
              >
                <span class="text-xs font-semibold text-n-slate-12">{{ row.label }}</span>
                <span class="text-xs text-right tabular-nums text-n-slate-11">{{ fmtMoney(row.va) }}</span>
                <b class="text-xs text-right tabular-nums text-n-slate-12">{{ fmtMoney(row.vb) }}</b>
                <span class="text-right">
                  <span
                    class="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full tabular-nums"
                    :style="{
                      background: row.tone === 'good' ? '#05966915' : row.tone === 'bad' ? '#DC262615' : 'rgba(120,140,180,0.12)',
                      color: row.tone === 'good' ? '#059669' : row.tone === 'bad' ? '#DC2626' : '#64748B',
                    }"
                  >
                    <span
                      v-if="row.delta !== 0"
                      :class="row.delta > 0 ? 'i-lucide-arrow-up-right' : 'i-lucide-arrow-down-right'"
                      class="text-[10px]"
                    />
                    <template v-if="row.pct != null">{{ Math.abs(row.pct).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) }}%</template>
                    <template v-else-if="row.delta !== 0">{{ fmtCompact(Math.abs(row.delta)) }}</template>
                    <template v-else>=</template>
                  </span>
                </span>
              </div>
            </div>

            <!-- custos por categoria lado a lado -->
            <div v-if="compareCosts.length" class="rounded-2xl border border-n-weak bg-n-card overflow-hidden mb-6">
              <div class="px-4 sm:px-5 py-3 border-b border-n-weak">
                <h2 class="text-sm font-bold text-n-slate-12">Custos por categoria</h2>
              </div>
              <div
                v-for="row in compareCosts"
                :key="row.key"
                class="grid items-center px-4 sm:px-5 py-2.5 border-b border-n-weak last:border-0"
                style="grid-template-columns: 1.4fr 1fr 1fr 0.9fr"
              >
                <span class="text-xs text-n-slate-12">{{ row.label }}</span>
                <span class="text-xs text-right tabular-nums text-n-slate-11">{{ fmtMoney(row.va) }}</span>
                <b class="text-xs text-right tabular-nums text-n-slate-12">{{ fmtMoney(row.vb) }}</b>
                <span
                  class="text-[10px] text-right font-semibold tabular-nums"
                  :style="{ color: row.vb > row.va ? '#DC2626' : row.vb < row.va ? '#059669' : '#64748B' }"
                >
                  {{ row.vb === row.va ? '=' : (row.vb > row.va ? '+' : '−') + ' ' + fmtCompact(Math.abs(row.vb - row.va)) }}
                </span>
              </div>
            </div>
          </template>
          <div v-else class="rounded-2xl border border-n-weak bg-n-card py-12 text-center">
            <p class="text-3xl mb-2">⚖️</p>
            <p class="text-sm font-semibold text-n-slate-12 mb-1">Escolha os dois meses e clique em Comparar</p>
            <p class="text-xs text-n-slate-10">Os indicadores aparecem lado a lado, com a variação de cada um.</p>
          </div>
        </template>
      </template>
    </div>
  </div>
</template>
