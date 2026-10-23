<script setup>
// 👓 SUA ÓTICA — ESTOQUE, fase 2 (23/10/2026). O saldo de cada produto só
// muda por MOVIMENTAÇÃO: a venda gravada baixa, cancelar/devolver devolve,
// a compra (XML da NF-e ou manual) entra, o inventário ajusta. Aqui ficam
// a visão (custo parado, cobertura, encalhados), a entrada de mercadoria,
// a contagem de inventário e o histórico das movimentações.
import { ref, computed, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { parseMoneyBR } from 'dashboard/helper/cevicoMoney';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  fmtMoney,
  fmtDate,
  fmtDateTime,
  KIND_META,
  INPUT,
  LABEL,
  VERDE,
  AZUL,
  ROXO,
  VERMELHO,
  AMBAR,
  CINZA,
  OURO,
} from './oticaFormat';

const { canEdit } = useCevicoAccess();
const editable = computed(() => canEdit('otica.produtos'));

const pal = useCevicoPalette({
  scope: 'otica:estoque',
  blocks: [
    { id: 'visao', label: 'Visão', icon: 'i-lucide-gauge' },
    { id: 'entrada', label: 'Entrada de mercadoria', icon: 'i-lucide-truck' },
    { id: 'inventario', label: 'Inventário', icon: 'i-lucide-clipboard-check' },
    { id: 'movimentacoes', label: 'Movimentações', icon: 'i-lucide-history' },
  ],
});
const pageStyle = computed(() => pal.cvVars.value);

// produtos que têm saldo: lente de grau vem do laboratório, serviço não tem
const STOCK_KINDS = ['armacao', 'solar', 'lente_contato', 'outro'];
const MOVE_META = {
  entrada: { color: VERDE, icon: 'i-lucide-arrow-down-to-line' },
  saida: { color: VERMELHO, icon: 'i-lucide-arrow-up-from-line' },
  ajuste: { color: AMBAR, icon: 'i-lucide-sliders-horizontal' },
};
const PURCHASE_META = {
  rascunho: { color: AMBAR, icon: 'i-lucide-file-search' },
  recebida: { color: VERDE, icon: 'i-lucide-package-check' },
  cancelada: { color: CINZA, icon: 'i-lucide-x' },
};
const PERIODS = [
  { days: 30, label: '30 dias' },
  { days: 90, label: '90 dias' },
  { days: 180, label: '180 dias' },
];

const num = v => (parseMoneyBR(v) ?? Number(v)) || 0;
const errorOf = (e, fallback) => e?.response?.data?.error || fallback;

// busca de produto (igual à da Venda): um "motor" por campo que precisa
const makeSearch = (limit = 8) => {
  const query = ref('');
  const results = ref([]);
  const searching = ref(false);
  const picked = ref(null);
  let timer = null;
  watch(query, q => {
    clearTimeout(timer);
    if (!q || q.trim().length < 2) {
      results.value = [];
      return;
    }
    timer = setTimeout(async () => {
      searching.value = true;
      try {
        const { data: payload } = await CrmAPI.getOticaProducts({
          q: q.trim(),
          active: 1,
        });
        results.value = (payload?.products || []).slice(0, limit);
      } catch {
        results.value = [];
      } finally {
        searching.value = false;
      }
    }, 300);
  });
  const pick = p => {
    picked.value = p;
    query.value = '';
    results.value = [];
  };
  const clear = () => {
    picked.value = null;
    query.value = '';
    results.value = [];
  };
  return { query, results, searching, picked, pick, clear };
};

// ── visão ──
const isLoading = ref(true);
const loadError = ref('');
const data = ref(null);
const days = ref(90);
const kinds = computed(() => data.value?.kinds || {});
const moveKinds = computed(() => data.value?.move_kinds || {});
const moveOrigins = computed(() => data.value?.move_origins || {});
const summary = computed(() => data.value?.summary || {});
const rows = computed(() => data.value?.rows || []);

const load = async () => {
  loadError.value = '';
  try {
    const { data: payload } = await CrmAPI.getOticaStock({ days: days.value });
    data.value = payload;
    if (!movesLoaded.value) moves.value = payload?.recent_moves || [];
  } catch (e) {
    loadError.value = errorOf(e, 'Não consegui carregar o estoque.');
  } finally {
    isLoading.value = false;
  }
};
const setDays = d => {
  days.value = d;
  load();
};

const fmtMonths = v => {
  if (v === null || v === undefined) return 'sem venda';
  const n = Number(v);
  if (!Number.isFinite(n)) return 'sem venda';
  return `${n.toLocaleString('pt-BR', { maximumFractionDigits: 1 })} ${
    n === 1 ? 'mês' : 'meses'
  }`;
};

const kpis = computed(() => [
  {
    key: 'units',
    label: 'Peças em estoque',
    hint: `${summary.value.products ?? 0} produto(s) com saldo`,
    icon: 'i-lucide-boxes',
    color: ROXO,
    value: String(summary.value.units ?? 0),
  },
  {
    key: 'total_cost',
    label: 'Custo parado',
    hint: 'o que o estoque vale a custo',
    icon: 'i-lucide-coins',
    color: AZUL,
    value: fmtMoney(summary.value.total_cost),
  },
  {
    key: 'coverage',
    label: 'Cobertura média',
    hint: `pelo ritmo de venda dos últimos ${summary.value.in_days ?? days.value} dias`,
    icon: 'i-lucide-hourglass',
    color: OURO,
    value: fmtMonths(summary.value.coverage_months),
  },
  {
    key: 'low',
    label: 'Estoque baixo',
    hint: 'no mínimo ou abaixo',
    icon: 'i-lucide-alert-triangle',
    color: (summary.value.low_stock ?? 0) > 0 ? VERMELHO : VERDE,
    value: String(summary.value.low_stock ?? 0),
  },
  {
    key: 'stale',
    label: 'Encalhados',
    hint: `${fmtMoney(summary.value.stale_cost)} parados há 180+ dias sem venda`,
    icon: 'i-lucide-snowflake',
    color: (summary.value.stale_count ?? 0) > 0 ? VERMELHO : VERDE,
    value: String(summary.value.stale_count ?? 0),
  },
  {
    key: 'sold',
    label: 'Vendidos no período',
    hint: `${fmtMoney(summary.value.sold_cost)} a custo`,
    icon: 'i-lucide-shopping-bag',
    color: VERDE,
    value: String(summary.value.sold_units ?? 0),
  },
]);

const view = ref('list');
const kindFilter = ref('todos');
const search = ref('');
const onlyStale = ref(false);
const gradeLine = p =>
  [p.brand, p.model, p.color, p.size].filter(Boolean).join(' · ');
const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return rows.value.filter(p => {
    if (kindFilter.value !== 'todos' && p.kind !== kindFilter.value)
      return false;
    if (onlyStale.value && !p.stale) return false;
    if (!q) return true;
    return `${p.name} ${gradeLine(p)} ${p.sku || ''}`
      .toLowerCase()
      .includes(q);
  });
});
const saldoStyle = p => {
  if (p.low) return { background: '#DC26261A', color: VERMELHO };
  if (!p.quantity)
    return { background: 'rgba(100,116,139,0.14)', color: CINZA };
  return { background: '#0596691A', color: VERDE };
};

// ── entrada de mercadoria: XML da NF-e ──
const xmlName = ref('');
const xmlText = ref('');
const previewing = ref(false);
const preview = ref(null); // { purchase, items }
const previewItems = ref([]); // itens com a escolha de cada um
const savingPurchase = ref(false);
const purchases = ref([]);
const purchasesLoaded = ref(false);
const purchaseBusyId = ref(null);

const onXmlFile = ev => {
  const file = ev.target.files?.[0];
  if (!file) return;
  xmlName.value = file.name;
  preview.value = null;
  previewItems.value = [];
  const reader = new FileReader();
  reader.onload = () => {
    xmlText.value = String(reader.result || '');
  };
  reader.readAsText(file, 'UTF-8');
};
const guessKind = description => {
  const t = String(description || '').toLowerCase();
  if (t.includes('contato')) return 'lente_contato';
  if (t.includes('sol')) return 'solar';
  if (t.includes('arma') || t.includes('ocul')) return 'armacao';
  return 'outro';
};
const previewXml = async () => {
  if (!xmlText.value.trim()) {
    useAlert('Escolha o arquivo .xml da nota.');
    return;
  }
  previewing.value = true;
  try {
    const { data: payload } = await CrmAPI.previewOticaPurchaseXml({
      xml: xmlText.value,
    });
    preview.value = payload;
    previewItems.value = (payload?.items || []).map(it => ({
      ...it,
      mode: it.product_id ? 'found' : 'create',
      create: {
        kind: guessKind(it.description),
        brand: '',
        model: it.code || '',
        color: '',
        size: '',
      },
    }));
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui ler o XML da nota.'));
  } finally {
    previewing.value = false;
  }
};
const previewTotal = computed(() =>
  previewItems.value.reduce(
    (acc, it) => acc + Number(it.quantity || 0) * Number(it.unit_cost || 0),
    0
  )
);
const matchedCount = computed(
  () => previewItems.value.filter(it => it.product_id).length
);
const loadPurchases = async () => {
  try {
    const { data: payload } = await CrmAPI.getOticaPurchases();
    purchases.value = payload?.purchases || [];
    purchasesLoaded.value = true;
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui carregar as compras.'));
  }
};
const savePurchase = async receive => {
  if (!previewItems.value.length) {
    useAlert('A nota não tem itens.');
    return;
  }
  savingPurchase.value = true;
  try {
    const p = preview.value?.purchase || {};
    const { data: payload } = await CrmAPI.createOticaPurchase({
      supplier_name: p.supplier_name,
      number: p.number,
      series: p.series,
      access_key: p.access_key,
      issued_on: p.issued_on,
      receive,
      items: previewItems.value.map(it => ({
        product_id: it.product_id || null,
        description: it.description,
        ean: it.ean,
        ncm: it.ncm,
        code: it.code,
        quantity: Number(it.quantity || 0),
        unit_cost: Number(it.unit_cost || 0),
        ...(!it.product_id && it.mode === 'create'
          ? { create_product: it.create }
          : {}),
      })),
    });
    const created = payload?.purchase || payload;
    useAlert(
      receive
        ? `Entrada feita: compra ${created?.number ? `nº ${created.number}` : ''} recebida no estoque.`
        : 'Compra guardada para conferir. Receba quando conferir as peças.'
    );
    preview.value = null;
    previewItems.value = [];
    xmlText.value = '';
    xmlName.value = '';
    await Promise.all([load(), loadPurchases(), refreshMoves()]);
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui gravar a compra.'));
  } finally {
    savingPurchase.value = false;
  }
};
const receivePurchase = async pu => {
  if (purchaseBusyId.value) return;
  purchaseBusyId.value = pu.id;
  try {
    await CrmAPI.receiveOticaPurchase(pu.id);
    useAlert('Compra recebida: as peças entraram no estoque.');
    await Promise.all([load(), loadPurchases(), refreshMoves()]);
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui receber a compra.'));
  } finally {
    purchaseBusyId.value = null;
  }
};
const deletePurchase = async pu => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir a compra ${pu.number ? `nº ${pu.number}` : ''} ainda não recebida?`))
    return;
  try {
    await CrmAPI.deleteOticaPurchase(pu.id);
    await loadPurchases();
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui excluir a compra.'));
  }
};

// ── entrada manual ──
const entrySearch = makeSearch();
const entryForm = ref({ quantity: 1, unit_cost: '', notes: '' });
const savingEntry = ref(false);
const saveEntry = async () => {
  const product = entrySearch.picked.value;
  if (!product) {
    useAlert('Escolha o produto que está entrando.');
    return;
  }
  if (Number(entryForm.value.quantity) <= 0) {
    useAlert('Quantidade precisa ser maior que zero.');
    return;
  }
  savingEntry.value = true;
  try {
    await CrmAPI.createOticaStockMove({
      product_id: product.id,
      kind: 'entrada',
      quantity: Number(entryForm.value.quantity),
      unit_cost: entryForm.value.unit_cost
        ? num(entryForm.value.unit_cost)
        : undefined,
      notes: entryForm.value.notes,
    });
    useAlert(`Entrada de ${entryForm.value.quantity} un. de ${product.name} gravada.`);
    entrySearch.clear();
    entryForm.value = { quantity: 1, unit_cost: '', notes: '' };
    await Promise.all([load(), refreshMoves()]);
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui gravar a entrada.'));
  } finally {
    savingEntry.value = false;
  }
};

// ── inventário ──
const inventoryRows = ref([]);
const inventoryStarted = ref(false);
const inventoryKind = ref('todos');
const inventorySearch = ref('');
const inventoryNotes = ref('');
const savingInventory = ref(false);
const inventoryResult = ref(null);
const startInventory = () => {
  const q = inventorySearch.value.trim().toLowerCase();
  inventoryRows.value = rows.value
    .filter(p => STOCK_KINDS.includes(p.kind))
    .filter(p => inventoryKind.value === 'todos' || p.kind === inventoryKind.value)
    .filter(p => !q || `${p.name} ${p.sku || ''}`.toLowerCase().includes(q))
    .map(p => ({
      product_id: p.id,
      name: p.name,
      sku: p.sku,
      kind: p.kind,
      quantity: p.quantity,
      counted: '',
    }));
  inventoryStarted.value = true;
  inventoryResult.value = null;
};
const cancelInventory = () => {
  inventoryStarted.value = false;
  inventoryRows.value = [];
};
const countedRows = computed(() =>
  inventoryRows.value.filter(r => r.counted !== '' && r.counted !== null)
);
const differingRows = computed(() =>
  countedRows.value.filter(r => Number(r.counted) !== Number(r.quantity))
);
const saveInventory = async () => {
  if (!countedRows.value.length) {
    useAlert('Preencha a contagem de pelo menos um produto.');
    return;
  }
  savingInventory.value = true;
  try {
    const { data: payload } = await CrmAPI.postOticaInventory({
      rows: countedRows.value.map(r => ({
        product_id: r.product_id,
        counted: Number(r.counted),
      })),
      notes: inventoryNotes.value,
    });
    inventoryResult.value = payload;
    useAlert(
      `Contagem gravada: ${payload?.adjusted ?? 0} ajustado(s), ${payload?.unchanged ?? 0} sem mudança.`
    );
    inventoryStarted.value = false;
    inventoryRows.value = [];
    inventoryNotes.value = '';
    await Promise.all([load(), refreshMoves()]);
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui gravar a contagem.'));
  } finally {
    savingInventory.value = false;
  }
};

// ── movimentações ──
const moves = ref([]);
const movesLoaded = ref(false);
const loadingMoves = ref(false);
const moveFilter = ref({ origin: 'todas', from: '', to: '' });
const moveSearch = makeSearch(6);
const loadMoves = async () => {
  loadingMoves.value = true;
  try {
    const params = {};
    if (moveFilter.value.origin !== 'todas') params.origin = moveFilter.value.origin;
    if (moveFilter.value.from) params.from = moveFilter.value.from;
    if (moveFilter.value.to) params.to = moveFilter.value.to;
    if (moveSearch.picked.value) params.product_id = moveSearch.picked.value.id;
    const { data: payload } = await CrmAPI.getOticaStockMoves(params);
    moves.value = payload?.moves || [];
    movesLoaded.value = true;
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui carregar as movimentações.'));
  } finally {
    loadingMoves.value = false;
  }
};
// depois de gravar algo: se a lista já foi filtrada, recarrega com o filtro;
// senão pega as recentes do GET stock (o load() já atualiza)
const refreshMoves = async () => {
  if (movesLoaded.value) await loadMoves();
};
const clearMoveFilter = () => {
  moveFilter.value = { origin: 'todas', from: '', to: '' };
  moveSearch.clear();
  loadMoves();
};
const deltaText = m => {
  const d = Number(m.delta ?? 0);
  if (d > 0) return `+${d}`;
  return String(d);
};

// ajuste manual (saldo novo)
const showAdjust = ref(false);
const adjustSearch = makeSearch();
const adjustForm = ref({ quantity: '', notes: '' });
const savingAdjust = ref(false);
const saveAdjust = async () => {
  const product = adjustSearch.picked.value;
  if (!product) {
    useAlert('Escolha o produto para ajustar.');
    return;
  }
  if (adjustForm.value.quantity === '' || Number(adjustForm.value.quantity) < 0) {
    useAlert('Informe o saldo novo (zero ou mais).');
    return;
  }
  if (!adjustForm.value.notes.trim()) {
    useAlert('Diga o motivo do ajuste: fica registrado na movimentação.');
    return;
  }
  savingAdjust.value = true;
  try {
    await CrmAPI.createOticaStockMove({
      product_id: product.id,
      kind: 'ajuste',
      quantity: Number(adjustForm.value.quantity),
      notes: adjustForm.value.notes,
    });
    useAlert(`Saldo de ${product.name} ajustado para ${adjustForm.value.quantity}.`);
    adjustSearch.clear();
    adjustForm.value = { quantity: '', notes: '' };
    showAdjust.value = false;
    await Promise.all([load(), refreshMoves()]);
  } catch (e) {
    useAlert(errorOf(e, 'Não consegui gravar o ajuste.'));
  } finally {
    savingAdjust.value = false;
  }
};

onMounted(async () => {
  await load();
  loadPurchases();
});
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Estoque"
        subtitle="O saldo só muda por movimentação: a venda baixa, a compra entra, o inventário ajusta. Veja o que está parado, dê entrada na mercadoria e conte o estoque."
        icon="i-lucide-warehouse"
        :palette="false"
      >
        <template #chips>
          <span class="cv-glass-chip">
            <span class="i-lucide-boxes text-xs" />
            {{ summary.units ?? 0 }} peça(s) em estoque
          </span>
          <span v-if="(summary.stale_count ?? 0) > 0" class="cv-glass-chip">
            <span class="i-lucide-snowflake text-xs" />
            {{ summary.stale_count }} encalhado(s)
          </span>
          <CevicoViewOnlyPill v-if="!editable" />
        </template>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <template v-else>
        <div
          v-if="loadError"
          class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3"
        >
          <p class="text-xs text-n-slate-11 flex-1">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="load">Tentar de novo</button>
        </div>

        <!-- bloco 1 · visão -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-start gap-3 flex-wrap">
            <div>
              <h2 class="cv-ag-block-title">Visão</h2>
              <span class="cv-ag-block-sub">
                quanto está parado, por quantos meses dá, e o que não gira
              </span>
            </div>
            <div class="ml-auto cv-seg">
              <button
                v-for="p in PERIODS"
                :key="p.days"
                class="cv-seg-item"
                :class="days === p.days ? 'cv-seg-on' : ''"
                @click="setDays(p.days)"
              >
                {{ p.label }}
              </button>
            </div>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-3 gap-3 mt-4">
            <div
              v-for="k in kpis"
              :key="k.key"
              class="cv-sub p-4 flex flex-col gap-1.5"
            >
              <span class="flex items-center gap-2">
                <span
                  class="w-7 h-7 rounded-lg grid place-items-center text-white flex-shrink-0"
                  :style="{ background: k.color }"
                >
                  <span :class="k.icon" class="text-xs" />
                </span>
                <span class="text-[11px] font-bold text-n-slate-11 leading-tight">
                  {{ k.label }}
                </span>
              </span>
              <span
                class="text-xl font-extrabold tabular-nums whitespace-nowrap"
                :style="{ color: k.color }"
              >
                {{ k.value }}
              </span>
              <span class="text-[10px] text-n-slate-9 leading-snug">
                {{ k.hint }}
              </span>
            </div>
          </div>

          <div class="cv-ag-divider" />

          <div class="flex items-center gap-2 flex-wrap mb-3">
            <div class="cv-seg">
              <button
                class="cv-seg-item"
                :class="view === 'list' ? 'cv-seg-on' : ''"
                @click="view = 'list'"
              >
                <span class="i-lucide-list text-sm" /> Lista
              </button>
              <button
                class="cv-seg-item"
                :class="view === 'cards' ? 'cv-seg-on' : ''"
                @click="view = 'cards'"
              >
                <span class="i-lucide-layout-grid text-sm" /> Cards
              </button>
            </div>
            <label class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer">
              <input v-model="onlyStale" type="checkbox" class="m-0" />
              só encalhados
            </label>
            <span class="text-[11px] text-n-slate-10 ml-auto">
              {{ shown.length }} produto(s)
            </span>
          </div>
          <div class="flex items-center gap-1.5 flex-wrap mb-3">
            <button
              class="cv-tag cv-tag-ghost text-[11px]"
              :class="kindFilter === 'todos' ? 'cv-tag-solid' : ''"
              @click="kindFilter = 'todos'"
            >
              Todos
            </button>
            <button
              v-for="(label, k) in kinds"
              :key="k"
              class="cv-tag cv-tag-ghost text-[11px]"
              :class="kindFilter === k ? 'cv-tag-solid' : ''"
              @click="kindFilter = k"
            >
              {{ label }}
            </button>
          </div>
          <input
            v-model="search"
            type="text"
            :class="INPUT"
            class="mb-3"
            placeholder="Grife, modelo, cor ou código"
          />

          <p v-if="!shown.length" class="text-xs text-n-slate-10 py-6 text-center">
            Nada aqui com esse filtro.
          </p>

          <!-- lista -->
          <div v-else-if="view === 'list'" class="flex flex-col gap-1.5">
            <div
              v-for="p in shown"
              :key="p.id"
              class="cv-sub px-3 py-2.5 flex items-center gap-3 flex-wrap"
            >
              <span
                class="w-8 h-8 rounded-lg grid place-items-center flex-shrink-0"
                :style="{ background: `${KIND_META[p.kind]?.color}1A` }"
              >
                <span
                  :class="KIND_META[p.kind]?.icon"
                  class="text-sm"
                  :style="{ color: KIND_META[p.kind]?.color }"
                />
              </span>
              <div class="min-w-0 flex-1" style="min-width: 10rem">
                <p class="text-xs font-semibold text-n-slate-12">
                  {{ p.name }}
                  <span
                    v-if="p.stale"
                    class="ml-1 text-[10px] font-bold px-1.5 py-0.5 rounded-full align-middle"
                    :style="{ background: '#DC26261A', color: VERMELHO }"
                  >
                    Encalhado
                  </span>
                </p>
                <p class="text-[10px] text-n-slate-9">
                  {{ p.kind_label }}
                  <template v-if="gradeLine(p)"> · {{ gradeLine(p) }}</template>
                  <template v-if="p.sku"> · cód. {{ p.sku }}</template>
                </p>
              </div>
              <span
                class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0 tabular-nums"
                :style="saldoStyle(p)"
                :title="p.low ? 'No mínimo ou abaixo — hora de repor' : 'Saldo'"
              >
                {{ p.quantity }} un.
              </span>
              <div class="text-right flex-shrink-0" style="width: 6.5rem">
                <p class="text-[10px] text-n-slate-9">custo</p>
                <b class="text-xs tabular-nums whitespace-nowrap" :style="{ color: AZUL }">
                  {{ fmtMoney(p.cost) }}
                </b>
              </div>
              <div class="text-right flex-shrink-0" style="width: 5rem">
                <p class="text-[10px] text-n-slate-9">vendidos</p>
                <b class="text-xs tabular-nums">{{ p.sold ?? 0 }}</b>
              </div>
              <div class="text-right flex-shrink-0" style="width: 6rem">
                <p class="text-[10px] text-n-slate-9">última venda</p>
                <b class="text-xs tabular-nums whitespace-nowrap">
                  {{ p.last_sale_on ? fmtDate(p.last_sale_on) : '—' }}
                </b>
              </div>
              <div class="text-right flex-shrink-0" style="width: 6.5rem">
                <p class="text-[10px] text-n-slate-9">cobertura</p>
                <b
                  class="text-xs tabular-nums whitespace-nowrap"
                  :style="{ color: p.stale ? VERMELHO : p.coverage_months === null ? CINZA : OURO }"
                >
                  {{ fmtMonths(p.coverage_months) }}
                </b>
              </div>
            </div>
          </div>

          <!-- cards -->
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <article
              v-for="p in shown"
              :key="p.id"
              class="cv-sub p-4 flex flex-col gap-2 border-l-4"
              :style="{ borderLeftColor: p.stale || p.low ? VERMELHO : KIND_META[p.kind]?.color }"
            >
              <header class="flex items-start gap-2">
                <span
                  class="w-8 h-8 rounded-lg grid place-items-center text-white flex-shrink-0"
                  :style="{ background: KIND_META[p.kind]?.color }"
                >
                  <span :class="KIND_META[p.kind]?.icon" class="text-xs" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="text-[13px] font-bold text-n-slate-12">{{ p.name }}</p>
                  <p class="text-[11px] text-n-slate-11">
                    {{ p.kind_label }}<template v-if="p.sku"> · cód. {{ p.sku }}</template>
                  </p>
                </div>
                <span
                  v-if="p.stale"
                  class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                  :style="{ background: '#DC26261A', color: VERMELHO }"
                >
                  Encalhado
                </span>
              </header>
              <p v-if="gradeLine(p)" class="text-[12px] text-n-slate-11">
                {{ gradeLine(p) }}
              </p>
              <div class="grid grid-cols-2 gap-2 mt-1">
                <div class="rounded-xl bg-n-alpha-1 p-2">
                  <p class="text-[10px] text-n-slate-9">saldo</p>
                  <b class="text-sm tabular-nums" :style="{ color: p.low ? VERMELHO : VERDE }">
                    {{ p.quantity }}
                  </b>
                </div>
                <div class="rounded-xl bg-n-alpha-1 p-2">
                  <p class="text-[10px] text-n-slate-9">custo</p>
                  <b class="text-xs tabular-nums whitespace-nowrap" :style="{ color: AZUL }">
                    {{ fmtMoney(p.cost) }}
                  </b>
                </div>
                <div class="rounded-xl bg-n-alpha-1 p-2">
                  <p class="text-[10px] text-n-slate-9">vendidos · última</p>
                  <b class="text-xs tabular-nums whitespace-nowrap">
                    {{ p.sold ?? 0 }} · {{ p.last_sale_on ? fmtDate(p.last_sale_on) : '—' }}
                  </b>
                </div>
                <div class="rounded-xl bg-n-alpha-1 p-2">
                  <p class="text-[10px] text-n-slate-9">cobertura</p>
                  <b
                    class="text-xs tabular-nums whitespace-nowrap"
                    :style="{ color: p.stale ? VERMELHO : p.coverage_months === null ? CINZA : OURO }"
                  >
                    {{ fmtMonths(p.coverage_months) }}
                  </b>
                </div>
              </div>
            </article>
          </div>
        </section>

        <!-- bloco 2 · entrada de mercadoria -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <h2 class="cv-ag-block-title">Entrada de mercadoria</h2>
          <span class="cv-ag-block-sub">
            o XML da nota do fornecedor casa os itens pelo código de barras ou
            código; o que não casar você cria na hora ou deixa só na compra
          </span>

          <div v-if="editable" class="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
            <!-- XML -->
            <div class="ot-form cv-sub p-4 flex flex-col gap-3">
              <p class="text-xs font-bold text-n-slate-12">
                <span class="i-lucide-file-code text-xs mr-1" :style="{ color: AZUL }" />
                Importar XML da NF-e
              </p>
              <label class="block">
                <span :class="LABEL">Arquivo .xml</span>
                <input
                  type="file"
                  accept=".xml,text/xml,application/xml"
                  class="mt-1 block w-full text-xs text-n-slate-12"
                  @change="onXmlFile"
                />
              </label>
              <p v-if="xmlName" class="text-[11px] text-n-slate-11">{{ xmlName }}</p>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60 w-fit"
                :style="{ background: AZUL }"
                :disabled="previewing || !xmlText"
                @click="previewXml"
              >
                <span class="i-lucide-scan-search text-xs mr-1" />
                {{ previewing ? 'Lendo…' : 'Ler a nota' }}
              </button>
            </div>

            <!-- manual -->
            <div class="ot-form cv-sub p-4 flex flex-col gap-3">
              <p class="text-xs font-bold text-n-slate-12">
                <span class="i-lucide-package-plus text-xs mr-1" :style="{ color: VERDE }" />
                Entrada manual
              </p>
              <div v-if="entrySearch.picked.value" class="rounded-xl bg-n-alpha-1 p-2.5 flex items-center gap-2">
                <span
                  :class="KIND_META[entrySearch.picked.value.kind]?.icon"
                  class="text-xs"
                  :style="{ color: KIND_META[entrySearch.picked.value.kind]?.color }"
                />
                <span class="text-xs font-semibold text-n-slate-12 flex-1 min-w-0">
                  {{ entrySearch.picked.value.name }}
                  <span class="font-normal text-n-slate-10">· saldo {{ entrySearch.picked.value.quantity }}</span>
                </span>
                <button class="text-n-slate-10 hover:text-n-slate-12" title="Trocar" @click="entrySearch.clear()">
                  <span class="i-lucide-x text-xs" />
                </button>
              </div>
              <div v-else class="relative">
                <input
                  v-model="entrySearch.query.value"
                  type="text"
                  :class="INPUT"
                  class="!mt-0"
                  placeholder="Buscar por grife, modelo ou código"
                />
                <div
                  v-if="entrySearch.results.value.length"
                  class="absolute z-20 left-0 right-0 mt-1 rounded-xl border border-n-weak bg-n-card shadow-lg overflow-hidden"
                >
                  <button
                    v-for="p in entrySearch.results.value"
                    :key="p.id"
                    class="w-full text-left px-3 py-2 hover:bg-n-alpha-1 flex items-center gap-2"
                    @click="entrySearch.pick(p)"
                  >
                    <span :class="KIND_META[p.kind]?.icon" class="text-xs" :style="{ color: KIND_META[p.kind]?.color }" />
                    <span class="text-xs font-semibold text-n-slate-12">{{ p.name }}</span>
                    <span class="text-[11px] text-n-slate-10">{{ p.sku || '' }} · {{ p.quantity }} un.</span>
                  </button>
                </div>
                <p
                  v-else-if="entrySearch.query.value.length >= 2 && !entrySearch.searching.value"
                  class="text-[11px] text-n-slate-10 mt-1"
                >
                  Nenhum produto com esse nome. Cadastre em Produtos e estoque.
                </p>
              </div>
              <div class="grid gap-2" style="grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr))">
                <label class="block">
                  <span :class="LABEL">Quantidade</span>
                  <input v-model.number="entryForm.quantity" type="number" min="1" :class="INPUT" class="text-right" />
                </label>
                <label class="block">
                  <span :class="LABEL">Custo unitário (R$)</span>
                  <input v-model="entryForm.unit_cost" type="text" inputmode="decimal" :class="INPUT" class="text-right" placeholder="opcional" />
                </label>
              </div>
              <label class="block">
                <span :class="LABEL">Observação</span>
                <input v-model="entryForm.notes" type="text" :class="INPUT" placeholder="Ex.: reposição da distribuidora" />
              </label>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60 w-fit"
                :style="{ background: VERDE }"
                :disabled="savingEntry"
                @click="saveEntry"
              >
                <span class="i-lucide-arrow-down-to-line text-xs mr-1" />
                {{ savingEntry ? 'Gravando…' : 'Dar entrada' }}
              </button>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10 mt-3">
            Só quem edita produtos dá entrada de mercadoria.
          </p>

          <!-- prévia da nota -->
          <div v-if="preview" class="ot-form cv-sub p-4 mt-4 flex flex-col gap-3">
            <div class="flex items-start gap-3 flex-wrap">
              <div class="min-w-0 flex-1">
                <p class="text-xs font-bold text-n-slate-12">
                  {{ preview.purchase?.supplier_name || 'Fornecedor sem nome' }}
                  <span v-if="preview.purchase?.supplier_cnpj" class="font-normal text-n-slate-10">
                    · CNPJ {{ preview.purchase.supplier_cnpj }}
                  </span>
                </p>
                <p class="text-[11px] text-n-slate-11">
                  NF {{ preview.purchase?.number || '—' }}
                  <template v-if="preview.purchase?.series"> série {{ preview.purchase.series }}</template>
                  · emitida em {{ fmtDate(preview.purchase?.issued_on) }}
                  · total da nota {{ fmtMoney(preview.purchase?.total) }}
                </p>
              </div>
              <span class="text-[11px] text-n-slate-11 whitespace-nowrap">
                <b :style="{ color: VERDE }">{{ matchedCount }}</b> casado(s) ·
                <b :style="{ color: AMBAR }">{{ previewItems.length - matchedCount }}</b> novo(s)
              </span>
            </div>
            <div class="flex flex-col gap-2">
              <div
                v-for="(it, idx) in previewItems"
                :key="idx"
                class="rounded-xl bg-n-alpha-1 p-3 flex flex-col gap-2 border-l-4"
                :style="{ borderLeftColor: it.product_id ? VERDE : AMBAR }"
              >
                <div class="flex items-start gap-2 flex-wrap">
                  <div class="min-w-0 flex-1" style="min-width: 10rem">
                    <p class="text-xs font-semibold text-n-slate-12">{{ it.description }}</p>
                    <p class="text-[10px] text-n-slate-9">
                      <template v-if="it.code">cód. {{ it.code }} · </template>
                      <template v-if="it.ean">EAN {{ it.ean }} · </template>
                      <template v-if="it.ncm">NCM {{ it.ncm }} · </template>
                      {{ it.quantity }} un. × {{ fmtMoney(it.unit_cost) }} = {{ fmtMoney(Number(it.quantity || 0) * Number(it.unit_cost || 0)) }}
                    </p>
                  </div>
                  <span
                    v-if="it.product_id"
                    class="text-[10px] font-bold px-2 py-0.5 rounded-full"
                    :style="{ background: '#0596691A', color: VERDE }"
                  >
                    <span class="i-lucide-check text-[10px] mr-0.5" />
                    {{ it.product_name || 'produto cadastrado' }}
                  </span>
                  <div v-else class="cv-seg">
                    <button
                      class="cv-seg-item"
                      :class="it.mode === 'create' ? 'cv-seg-on' : ''"
                      @click="it.mode = 'create'"
                    >
                      Criar produto
                    </button>
                    <button
                      class="cv-seg-item"
                      :class="it.mode === 'skip' ? 'cv-seg-on' : ''"
                      @click="it.mode = 'skip'"
                    >
                      Só na compra
                    </button>
                  </div>
                </div>
                <div
                  v-if="!it.product_id && it.mode === 'create'"
                  class="grid gap-2"
                  style="grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr))"
                >
                  <label class="block">
                    <span :class="LABEL">Tipo</span>
                    <select v-model="it.create.kind" :class="INPUT">
                      <option v-for="(label, k) in kinds" :key="k" :value="k">{{ label }}</option>
                    </select>
                  </label>
                  <label class="block">
                    <span :class="LABEL">Grife</span>
                    <input v-model="it.create.brand" type="text" :class="INPUT" />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Modelo</span>
                    <input v-model="it.create.model" type="text" :class="INPUT" />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Cor</span>
                    <input v-model="it.create.color" type="text" :class="INPUT" />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Tamanho</span>
                    <input v-model="it.create.size" type="text" :class="INPUT" />
                  </label>
                </div>
              </div>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-xs text-n-slate-11 mr-auto">
                Itens: <b class="tabular-nums">{{ fmtMoney(previewTotal) }}</b>
              </span>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-n-slate-12 border border-n-weak disabled:opacity-60"
                :disabled="savingPurchase"
                @click="savePurchase(false)"
              >
                Guardar para conferir
              </button>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                :style="{ background: VERDE }"
                :disabled="savingPurchase"
                @click="savePurchase(true)"
              >
                <span class="i-lucide-package-check text-xs mr-1" />
                {{ savingPurchase ? 'Gravando…' : 'Dar entrada' }}
              </button>
            </div>
          </div>

          <!-- compras -->
          <div class="mt-5">
            <p class="text-xs font-bold text-n-slate-12 mb-2">
              Compras
              <span class="font-normal text-n-slate-10">· {{ purchases.length }} nota(s)</span>
            </p>
            <p v-if="purchasesLoaded && !purchases.length" class="text-xs text-n-slate-10">
              Nenhuma compra ainda. A primeira entra pelo XML da nota ou pela entrada manual.
            </p>
            <div v-else class="flex flex-col gap-1.5">
              <div
                v-for="pu in purchases"
                :key="pu.id"
                class="cv-sub px-3 py-2.5 flex items-center gap-3 flex-wrap"
              >
                <span
                  class="w-8 h-8 rounded-lg grid place-items-center flex-shrink-0"
                  :style="{ background: `${PURCHASE_META[pu.status]?.color}1A` }"
                >
                  <span :class="PURCHASE_META[pu.status]?.icon" class="text-sm" :style="{ color: PURCHASE_META[pu.status]?.color }" />
                </span>
                <div class="min-w-0 flex-1" style="min-width: 10rem">
                  <p class="text-xs font-semibold text-n-slate-12">
                    {{ pu.supplier_name || 'Fornecedor' }}
                    <template v-if="pu.number"> · NF {{ pu.number }}</template>
                  </p>
                  <p class="text-[10px] text-n-slate-9">
                    {{ pu.items?.length ?? 0 }} item(ns)
                    <template v-if="pu.issued_on"> · emitida {{ fmtDate(pu.issued_on) }}</template>
                    <template v-if="pu.received_at"> · recebida {{ fmtDate(pu.received_at) }}</template>
                  </p>
                </div>
                <span
                  class="text-[10px] font-bold px-2 py-0.5 rounded-full"
                  :style="{ background: `${PURCHASE_META[pu.status]?.color}1A`, color: PURCHASE_META[pu.status]?.color }"
                >
                  {{ pu.status_label }}
                </span>
                <b class="text-xs tabular-nums whitespace-nowrap" :style="{ color: AZUL }">
                  {{ fmtMoney(pu.total) }}
                </b>
                <template v-if="editable && pu.status === 'rascunho'">
                  <button
                    class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white disabled:opacity-60"
                    :style="{ background: VERDE }"
                    :disabled="purchaseBusyId === pu.id"
                    @click="receivePurchase(pu)"
                  >
                    Receber
                  </button>
                  <button class="text-n-slate-10 hover:text-red-600" title="Excluir" @click="deletePurchase(pu)">
                    <span class="i-lucide-trash-2 text-xs" />
                  </button>
                </template>
              </div>
            </div>
          </div>
        </section>

        <!-- bloco 3 · inventário -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-start gap-3 flex-wrap">
            <div>
              <h2 class="cv-ag-block-title">Inventário</h2>
              <span class="cv-ag-block-sub">
                conte as peças da loja; o que diferir do sistema vira ajuste com
                origem "inventário"
              </span>
            </div>
            <div v-if="editable" class="ml-auto flex items-center gap-2 flex-wrap">
              <template v-if="!inventoryStarted">
                <select v-model="inventoryKind" :class="INPUT" class="!mt-0 !w-auto">
                  <option value="todos">Todos os tipos</option>
                  <option v-for="k in STOCK_KINDS" :key="k" :value="k">{{ kinds[k] }}</option>
                </select>
                <input
                  v-model="inventorySearch"
                  type="text"
                  :class="INPUT"
                  class="!mt-0"
                  style="width: 12rem"
                  placeholder="Grife, modelo ou código"
                />
                <button
                  class="h-9 px-4 rounded-lg text-xs font-bold text-white"
                  :style="{ background: ROXO }"
                  @click="startInventory"
                >
                  <span class="i-lucide-clipboard-check text-xs mr-1" />
                  Começar contagem
                </button>
              </template>
              <button
                v-else
                class="h-9 px-4 rounded-lg text-xs font-bold text-n-slate-12 border border-n-weak"
                @click="cancelInventory"
              >
                Cancelar contagem
              </button>
            </div>
          </div>

          <div v-if="inventoryStarted" class="ot-form mt-4 flex flex-col gap-3">
            <div class="flex items-center gap-3 flex-wrap text-xs text-n-slate-11">
              <span><b class="tabular-nums">{{ inventoryRows.length }}</b> produto(s) na contagem</span>
              <span>· <b class="tabular-nums">{{ countedRows.length }}</b> contado(s)</span>
              <span>
                · <b class="tabular-nums" :style="{ color: differingRows.length ? AMBAR : VERDE }">{{ differingRows.length }}</b>
                com diferença
              </span>
            </div>
            <p v-if="!inventoryRows.length" class="text-xs text-n-slate-10">
              Nenhum produto de estoque com esse filtro.
            </p>
            <div v-else class="flex flex-col gap-1.5">
              <div
                v-for="r in inventoryRows"
                :key="r.product_id"
                class="cv-sub px-3 py-2 flex items-center gap-3 flex-wrap"
                :style="r.counted !== '' && Number(r.counted) !== r.quantity ? { borderColor: AMBAR } : {}"
              >
                <span :class="KIND_META[r.kind]?.icon" class="text-sm flex-shrink-0" :style="{ color: KIND_META[r.kind]?.color }" />
                <div class="min-w-0 flex-1" style="min-width: 10rem">
                  <p class="text-xs font-semibold text-n-slate-12">{{ r.name }}</p>
                  <p v-if="r.sku" class="text-[10px] text-n-slate-9">cód. {{ r.sku }}</p>
                </div>
                <div class="text-right flex-shrink-0" style="width: 5.5rem">
                  <p class="text-[10px] text-n-slate-9">no sistema</p>
                  <b class="text-xs tabular-nums">{{ r.quantity }}</b>
                </div>
                <label class="block flex-shrink-0" style="width: 6rem">
                  <span :class="LABEL">contado</span>
                  <input v-model="r.counted" type="number" min="0" :class="INPUT" class="text-right" placeholder="—" />
                </label>
                <div class="text-right flex-shrink-0" style="width: 4.5rem">
                  <p class="text-[10px] text-n-slate-9">diferença</p>
                  <b
                    class="text-xs tabular-nums"
                    :style="{
                      color:
                        r.counted === '' ? CINZA : Number(r.counted) === r.quantity ? VERDE : AMBAR,
                    }"
                  >
                    <template v-if="r.counted === ''">—</template>
                    <template v-else>{{ Number(r.counted) - r.quantity > 0 ? '+' : '' }}{{ Number(r.counted) - r.quantity }}</template>
                  </b>
                </div>
              </div>
            </div>
            <div class="flex items-end gap-2 flex-wrap">
              <label class="block flex-1" style="min-width: 12rem">
                <span :class="LABEL">Observação da contagem</span>
                <input v-model="inventoryNotes" type="text" :class="INPUT" placeholder="Ex.: contagem de fim de mês" />
              </label>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                :style="{ background: ROXO }"
                :disabled="savingInventory || !countedRows.length"
                @click="saveInventory"
              >
                <span class="i-lucide-save text-xs mr-1" />
                {{ savingInventory ? 'Gravando…' : 'Gravar contagem' }}
              </button>
            </div>
          </div>
          <div v-else-if="inventoryResult" class="rounded-xl bg-n-alpha-1 p-3 mt-4 text-xs text-n-slate-12">
            Última contagem:
            <b :style="{ color: AMBAR }">{{ inventoryResult.adjusted ?? 0 }}</b> ajustado(s) ·
            <b :style="{ color: VERDE }">{{ inventoryResult.unchanged ?? 0 }}</b> sem mudança.
            Os ajustes estão nas movimentações.
          </div>
          <p v-else-if="!editable" class="text-xs text-n-slate-10 mt-3">
            Só quem edita produtos conta o inventário.
          </p>
        </section>

        <!-- bloco 4 · movimentações -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-start gap-3 flex-wrap">
            <div>
              <h2 class="cv-ag-block-title">Movimentações</h2>
              <span class="cv-ag-block-sub">
                cada mudança de saldo, com origem, referência e quem fez
                <template v-if="!movesLoaded"> · as {{ moves.length }} mais recentes</template>
              </span>
            </div>
            <button
              v-if="editable"
              class="ml-auto h-8 px-3 rounded-lg text-xs font-bold text-white"
              :style="{ background: AMBAR }"
              @click="showAdjust = !showAdjust"
            >
              {{ showAdjust ? 'Fechar' : 'Ajuste manual' }}
            </button>
          </div>

          <!-- ajuste manual -->
          <div v-if="showAdjust && editable" class="ot-form cv-sub p-4 mt-4 flex flex-col gap-3">
            <p class="text-xs font-bold text-n-slate-12">Ajuste manual de saldo</p>
            <div v-if="adjustSearch.picked.value" class="rounded-xl bg-n-alpha-1 p-2.5 flex items-center gap-2">
              <span :class="KIND_META[adjustSearch.picked.value.kind]?.icon" class="text-xs" :style="{ color: KIND_META[adjustSearch.picked.value.kind]?.color }" />
              <span class="text-xs font-semibold text-n-slate-12 flex-1 min-w-0">
                {{ adjustSearch.picked.value.name }}
                <span class="font-normal text-n-slate-10">· saldo hoje {{ adjustSearch.picked.value.quantity }}</span>
              </span>
              <button class="text-n-slate-10 hover:text-n-slate-12" title="Trocar" @click="adjustSearch.clear()">
                <span class="i-lucide-x text-xs" />
              </button>
            </div>
            <div v-else class="relative">
              <input
                v-model="adjustSearch.query.value"
                type="text"
                :class="INPUT"
                class="!mt-0"
                placeholder="Buscar por grife, modelo ou código"
              />
              <div
                v-if="adjustSearch.results.value.length"
                class="absolute z-20 left-0 right-0 mt-1 rounded-xl border border-n-weak bg-n-card shadow-lg overflow-hidden"
              >
                <button
                  v-for="p in adjustSearch.results.value"
                  :key="p.id"
                  class="w-full text-left px-3 py-2 hover:bg-n-alpha-1 flex items-center gap-2"
                  @click="adjustSearch.pick(p)"
                >
                  <span :class="KIND_META[p.kind]?.icon" class="text-xs" :style="{ color: KIND_META[p.kind]?.color }" />
                  <span class="text-xs font-semibold text-n-slate-12">{{ p.name }}</span>
                  <span class="text-[11px] text-n-slate-10">{{ p.sku || '' }} · {{ p.quantity }} un.</span>
                </button>
              </div>
            </div>
            <div class="grid gap-2 items-end" style="grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr))">
              <label class="block">
                <span :class="LABEL">Saldo novo</span>
                <input v-model.number="adjustForm.quantity" type="number" min="0" :class="INPUT" class="text-right" />
              </label>
              <label class="block" style="grid-column: span 2">
                <span :class="LABEL">Motivo</span>
                <input v-model="adjustForm.notes" type="text" :class="INPUT" placeholder="Ex.: peça quebrada, mostruário" />
              </label>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                :style="{ background: AMBAR }"
                :disabled="savingAdjust"
                @click="saveAdjust"
              >
                {{ savingAdjust ? 'Gravando…' : 'Gravar ajuste' }}
              </button>
            </div>
          </div>

          <!-- filtros -->
          <div class="ot-form flex items-end gap-2 flex-wrap mt-4 mb-3">
            <label class="block">
              <span :class="LABEL">Origem</span>
              <select v-model="moveFilter.origin" :class="INPUT" class="!w-auto">
                <option value="todas">Todas</option>
                <option v-for="(label, k) in moveOrigins" :key="k" :value="k">{{ label }}</option>
              </select>
            </label>
            <div class="block relative flex-1" style="min-width: 12rem">
              <span :class="LABEL">Produto</span>
              <div v-if="moveSearch.picked.value" class="mt-1 h-9 rounded-lg bg-n-alpha-1 px-2 flex items-center gap-2 text-xs">
                <span class="font-semibold text-n-slate-12 flex-1 min-w-0">{{ moveSearch.picked.value.name }}</span>
                <button class="text-n-slate-10 hover:text-n-slate-12" title="Limpar" @click="moveSearch.clear(); loadMoves()">
                  <span class="i-lucide-x text-xs" />
                </button>
              </div>
              <template v-else>
                <input v-model="moveSearch.query.value" type="text" :class="INPUT" placeholder="Todos os produtos" />
                <div
                  v-if="moveSearch.results.value.length"
                  class="absolute z-20 left-0 right-0 mt-1 rounded-xl border border-n-weak bg-n-card shadow-lg overflow-hidden"
                >
                  <button
                    v-for="p in moveSearch.results.value"
                    :key="p.id"
                    class="w-full text-left px-3 py-2 hover:bg-n-alpha-1 flex items-center gap-2"
                    @click="moveSearch.pick(p); loadMoves()"
                  >
                    <span :class="KIND_META[p.kind]?.icon" class="text-xs" :style="{ color: KIND_META[p.kind]?.color }" />
                    <span class="text-xs font-semibold text-n-slate-12">{{ p.name }}</span>
                  </button>
                </div>
              </template>
            </div>
            <label class="block">
              <span :class="LABEL">De</span>
              <input v-model="moveFilter.from" type="date" :class="INPUT" />
            </label>
            <label class="block">
              <span :class="LABEL">Até</span>
              <input v-model="moveFilter.to" type="date" :class="INPUT" />
            </label>
            <button
              class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
              :style="{ background: AZUL }"
              :disabled="loadingMoves"
              @click="loadMoves"
            >
              <span class="i-lucide-search text-xs mr-1" />
              {{ loadingMoves ? 'Buscando…' : 'Filtrar' }}
            </button>
            <button
              v-if="movesLoaded"
              class="h-9 px-3 rounded-lg text-xs font-bold text-n-slate-12 border border-n-weak"
              @click="clearMoveFilter"
            >
              Limpar
            </button>
          </div>

          <p v-if="!moves.length" class="text-xs text-n-slate-10 py-6 text-center">
            Nenhuma movimentação ainda. A primeira venda gravada, entrada ou contagem aparece aqui.
          </p>
          <div v-else class="flex flex-col gap-1.5">
            <div
              v-for="m in moves"
              :key="m.id"
              class="cv-sub px-3 py-2.5 flex items-center gap-3 flex-wrap"
            >
              <span
                class="w-8 h-8 rounded-lg grid place-items-center flex-shrink-0"
                :style="{ background: `${MOVE_META[m.kind]?.color}1A` }"
              >
                <span :class="MOVE_META[m.kind]?.icon" class="text-sm" :style="{ color: MOVE_META[m.kind]?.color }" />
              </span>
              <div class="min-w-0 flex-1" style="min-width: 10rem">
                <p class="text-xs font-semibold text-n-slate-12">{{ m.product_name }}</p>
                <p class="text-[10px] text-n-slate-9">
                  {{ fmtDateTime(m.created_at) }}
                  · {{ m.origin_label }}
                  <template v-if="m.reference"> · {{ m.reference }}</template>
                  <template v-if="m.user_name"> · {{ m.user_name }}</template>
                  <template v-if="m.notes"> · {{ m.notes }}</template>
                </p>
              </div>
              <span
                class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
                :style="{ background: `${MOVE_META[m.kind]?.color}1A`, color: MOVE_META[m.kind]?.color }"
              >
                {{ m.kind_label }}
              </span>
              <div class="text-right flex-shrink-0" style="width: 4.5rem">
                <p class="text-[10px] text-n-slate-9">qtd</p>
                <b class="text-sm tabular-nums" :style="{ color: MOVE_META[m.kind]?.color }">{{ deltaText(m) }}</b>
              </div>
              <div class="text-right flex-shrink-0" style="width: 5.5rem">
                <p class="text-[10px] text-n-slate-9">saldo depois</p>
                <b class="text-xs tabular-nums">{{ m.balance_after ?? '—' }}</b>
              </div>
              <div v-if="m.unit_cost" class="text-right flex-shrink-0" style="width: 6.5rem">
                <p class="text-[10px] text-n-slate-9">custo unit.</p>
                <b class="text-xs tabular-nums whitespace-nowrap" :style="{ color: AZUL }">{{ fmtMoney(m.unit_cost) }}</b>
              </div>
            </div>
          </div>
        </section>
      </template>
    </div>
  </div>
</template>

<style scoped>
.ot-form input,
.ot-form select,
.ot-form textarea {
  margin-bottom: 0;
}
</style>
