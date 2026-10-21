<script setup>
// 📊 Métricas da empresa (27/09): três fontes, lado a lado —
//   · Financeiro: receitas/custos lançados no sistema (mês atual)
//   · Oftalmofácil: faturamento e CIRURGIAS realizadas da CEVICO no hub
//     (parceiros ficam fora), vem do servidor junto com o quadro
//   · Estimativa: números que você digita (com a data), para planejar
// "Vendas" virou "Cirurgias". Custo mensal e ponto de equilíbrio usam o
// Financeiro ou a sua estimativa.
import { ref, computed, inject, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';
import { fmtDay, nowIso } from '../useBusinessBoard';

const biz = inject('biz');
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const finance = ref(null);
const loading = ref(true);
onMounted(async () => {
  try {
    const { data } = await CrmAPI.getFinance({ preset: 'month' });
    finance.value = data;
  } catch {
    finance.value = null;
  } finally {
    loading.value = false;
  }
});

const SOURCES = [
  { key: 'oftalmofacil', label: 'Oftalmofácil', icon: 'i-lucide-database' },
  { key: 'financeiro', label: 'Financeiro', icon: 'i-lucide-wallet' },
  { key: 'estimativa', label: 'Estimativa', icon: 'i-lucide-pencil-ruler' },
];
const est = computed(() => biz.board.value.estimates);
const source = computed({
  get: () => est.value.source || 'oftalmofacil',
  set: v => {
    est.value.source = v;
  },
});
const of = computed(() => biz.metrics?.value?.oftalmofacil || null);
const fin = computed(() => {
  const s = finance.value?.summary;
  if (!s) return null;
  return {
    faturamento: s.receita || 0,
    custo: (s.custo || 0) + (s.tributo || 0),
    lucro: s.lucro || 0,
    margem: s.margem,
    vendas: (finance.value.entries || []).filter(e => e.kind === 'receita')
      .length,
  };
});
const num = v =>
  Number(
    String(v ?? '')
      .replace(/\./g, '')
      .replace(',', '.')
  ) || 0;
const money = v =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}`;

// o que aparece, pela fonte escolhida
const m = computed(() => {
  const custo = num(est.value.custo) || fin.value?.custo || 0;
  if (source.value === 'estimativa') {
    const faturamento = num(est.value.faturamento);
    const cirurgias = num(est.value.cirurgias);
    return {
      faturamento,
      cirurgias,
      custo,
      ticket: cirurgias ? faturamento / cirurgias : 0,
      lucro: faturamento - custo,
      margem: faturamento
        ? Math.round(((faturamento - custo) / faturamento) * 100)
        : null,
      label: `estimativa${est.value.updated_at ? ` de ${fmtDay(est.value.updated_at)}` : ''}`,
    };
  }
  if (source.value === 'oftalmofacil') {
    if (!of.value) return null;
    const { faturamento, cirurgias, ticket } = of.value;
    return {
      faturamento,
      cirurgias,
      custo,
      ticket,
      lucro: faturamento - custo,
      margem: faturamento
        ? Math.round(((faturamento - custo) / faturamento) * 100)
        : null,
      label: `Oftalmofácil · ${of.value.month_label}`,
      extra: of.value,
    };
  }
  if (!fin.value) return null;
  return {
    faturamento: fin.value.faturamento,
    cirurgias: fin.value.vendas,
    custo: fin.value.custo,
    ticket: fin.value.vendas ? fin.value.faturamento / fin.value.vendas : 0,
    lucro: fin.value.lucro,
    margem: fin.value.margem,
    label: 'Financeiro · este mês',
  };
});
const pct = computed(() =>
  m.value?.custo
    ? Math.min(100, Math.round((m.value.faturamento / m.value.custo) * 100))
    : 0
);
const phrase = computed(() => {
  if (!m.value) return '';
  if (!m.value.faturamento && !m.value.custo) {
    return source.value === 'financeiro'
      ? 'O Financeiro ainda não tem lançamentos neste mês — registre receitas e custos, ou use o Oftalmofácil / uma estimativa.'
      : 'Sem números ainda nesta fonte para este mês.';
  }
  const gap = m.value.faturamento - m.value.custo;
  if (!m.value.custo)
    return `Entraram ${money(m.value.faturamento)}. Preencha o custo mensal (Financeiro ou estimativa) para ver o ponto de equilíbrio.`;
  return gap >= 0
    ? `Entraram ${money(m.value.faturamento)} com custo de ${money(m.value.custo)}: o mês já passou o ponto de equilíbrio em ${money(gap)}.`
    : `Entraram ${money(m.value.faturamento)} com custo de ${money(m.value.custo)}: faltam ${money(-gap)} para empatar o mês.`;
});
const tiles = computed(() => {
  if (!m.value) return [];
  return [
    {
      label: 'Faturamento',
      value: money(m.value.faturamento),
      sub:
        source.value === 'oftalmofacil'
          ? 'cirurgias realizadas no mês'
          : 'receitas do mês',
      color: '#C8962E',
    },
    {
      label: 'Cirurgias',
      value: m.value.cirurgias,
      sub:
        source.value === 'oftalmofacil'
          ? `${m.value.extra?.agendadas || 0} ainda agendadas no mês`
          : 'no mês',
      color: '#0A84FF',
    },
    {
      label: 'Ticket médio',
      value: money(m.value.ticket),
      sub: 'faturamento ÷ cirurgias',
      color: '#BF5AF2',
    },
    {
      label: 'Custo mensal',
      value: money(m.value.custo),
      sub: num(est.value.custo)
        ? 'estimativa'
        : 'custos + tributos (Financeiro)',
      color: '#FF375F',
    },
    {
      label: 'Lucro',
      value: money(m.value.lucro),
      sub:
        m.value.margem !== null && m.value.margem !== undefined
          ? `margem de ${m.value.margem}%`
          : 'sem margem ainda',
      color: '#30A46C',
    },
  ];
});
const showEst = ref(false);
const touchEst = () => {
  est.value.updated_at = nowIso();
};
const openFinance = () =>
  router.push({
    name: 'cevico_finance',
    params: { accountId: accountId.value },
  });
</script>

<template>
  <div class="biz-fill">
    <div class="biz-toolbar mb-2" data-no-drag>
      <button
        v-for="s in SOURCES"
        :key="s.key"
        class="biz-chip"
        :class="{ 'biz-chip-on': source === s.key }"
        @click="source = s.key"
      >
        <span :class="s.icon" /> {{ s.label }}
      </button>
      <button
        class="biz-chip ml-auto"
        :class="{ 'biz-chip-on': showEst }"
        @click="showEst = !showEst"
      >
        <span class="i-lucide-pencil" /> Estimativas
      </button>
    </div>
    <div v-if="showEst" class="biz-focus mb-2" data-no-drag>
      <p class="biz-label">
        Suas estimativas para o mês (ficam guardadas com a data)
      </p>
      <div class="biz-auto biz-auto-xs">
        <label class="biz-hint"
          >Faturamento (R$)<input
            v-model="est.faturamento"
            class="biz-add"
            placeholder="ex.: 180.000"
            @input="touchEst"
        /></label>
        <label class="biz-hint"
          >Cirurgias<input
            v-model="est.cirurgias"
            class="biz-add"
            placeholder="ex.: 40"
            @input="touchEst"
        /></label>
        <label class="biz-hint"
          >Custo mensal (R$)<input
            v-model="est.custo"
            class="biz-add"
            placeholder="usado em todas as fontes"
            @input="touchEst"
        /></label>
      </div>
      <p class="biz-hint mt-1">
        O custo mensal estimado vale para as três fontes até o Financeiro ter
        lançamentos.
      </p>
    </div>

    <div v-if="loading && source === 'financeiro'" class="biz-auto biz-auto-xs">
      <div v-for="i in 5" :key="i" class="biz-skel" />
    </div>
    <template v-else-if="m">
      <p class="biz-hint mb-1">{{ m.label }}</p>
      <p
        class="biz-phrase"
        :class="
          m.faturamento >= m.custo && m.custo
            ? 'biz-phrase-ok'
            : 'biz-phrase-warn'
        "
      >
        {{ phrase }}
      </p>
      <div class="biz-auto biz-auto-xs">
        <div
          v-for="t in tiles"
          :key="t.label"
          class="biz-kpi"
          :style="{ '--kpi': t.color }"
        >
          <p class="biz-kpi-label">{{ t.label }}</p>
          <p class="biz-kpi-value">{{ t.value }}</p>
          <p class="biz-hint">{{ t.sub }}</p>
        </div>
        <div class="biz-kpi" style="--kpi: #30a46c">
          <p class="biz-kpi-label">Ponto de equilíbrio</p>
          <p class="biz-kpi-value">{{ money(m.custo) }}</p>
          <div class="biz-track mt-1">
            <div
              class="biz-fillbar"
              :style="{
                width: `${pct}%`,
                background: pct >= 100 ? '#30A46C' : '#C8962E',
              }"
            />
          </div>
          <p class="biz-hint">
            {{
              !m.custo
                ? 'sem custo informado'
                : pct >= 100
                  ? 'mês pago — lucrando'
                  : `${pct}% do caminho`
            }}
          </p>
        </div>
      </div>
      <button
        v-if="source === 'financeiro'"
        class="biz-link mt-2"
        data-no-drag
        @click="openFinance"
      >
        abrir Financeiro <span class="i-lucide-arrow-right" />
      </button>
    </template>
    <p v-else class="biz-empty">
      {{
        source === 'oftalmofacil'
          ? 'O Oftalmofácil ainda não está ligado nesta conta (Integrações → Oftalmofácil).'
          : 'Não consegui ler o Financeiro agora.'
      }}
    </p>
  </div>
</template>
