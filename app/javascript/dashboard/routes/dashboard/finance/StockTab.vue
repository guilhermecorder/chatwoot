<script setup>
// ESTOQUE (item 68): aba própria dentro do Financeiro. Dashboard com o
// dinheiro parado em estoque e o potencial de lucro, catálogo de itens
// (lentes, insumos, medicamentos) com alerta de estoque mínimo e os
// PEDIDOS — encomendas que nascem da indicação de cirurgia sem estoque,
// vinculadas ao card do paciente. Receber um pedido soma no estoque.
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CrmAPI from 'dashboard/api/crm';

const router = useRouter();

const VERDE = '#059669';
const VERDE_ESCURO = '#065F46';
const VERMELHO = '#DC2626';
const OURO = '#D4A017';
const AZUL = '#0F5FA6';

const CATEGORY_META = {
  lentes: { color: AZUL, icon: 'i-lucide-aperture' },
  insumos: { color: '#7C3AED', icon: 'i-lucide-syringe' },
  medicamentos: { color: '#0F766E', icon: 'i-lucide-pill' },
  outros: { color: '#64748B', icon: 'i-lucide-box' },
};
const STATUS_META = {
  pendente: { color: '#D97706', icon: 'i-lucide-clock' },
  encomendado: { color: AZUL, icon: 'i-lucide-truck' },
  recebido: { color: VERDE, icon: 'i-lucide-package-check' },
  cancelado: { color: '#64748B', icon: 'i-lucide-x' },
};

const isLoading = ref(true);
const data = ref(null);

const load = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getStock();
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar o estoque.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const fmtMoney = (v, cents = false) =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: cents ? 2 : 0,
    maximumFractionDigits: cents ? 2 : 0,
  })}`;
const fmtDate = iso => new Date(iso).toLocaleDateString('pt-BR');

// aceita "1.234,56" e "1234.56"
const parseAmount = raw => {
  let s = String(raw || '').replace(/[R$\s]/g, '');
  if (s.includes(',')) s = s.replace(/\./g, '').replace(',', '.');
  const n = parseFloat(s);
  return Number.isFinite(n) ? Math.round(n * 100) / 100 : 0;
};

const summary = computed(() => data.value?.summary || {});
const kpiCards = computed(() => [
  {
    key: 'units', label: 'Em estoque', icon: 'i-lucide-boxes', color: VERDE_ESCURO,
    value: `${summary.value.units || 0} un.`, hint: `${summary.value.items_count || 0} item(ns) no catálogo`,
  },
  {
    key: 'total_cost', label: 'Custo em estoque', icon: 'i-lucide-coins', color: AZUL,
    value: fmtMoney(summary.value.total_cost), hint: 'dinheiro parado hoje',
  },
  {
    key: 'potential_profit', label: 'Potencial de lucro', icon: 'i-lucide-gem', color: OURO,
    value: fmtMoney(summary.value.potential_profit), hint: 'se todo o estoque vender',
  },
  {
    key: 'open_orders', label: 'Pedidos abertos', icon: 'i-lucide-truck', color: (summary.value.open_orders || 0) > 0 ? '#D97706' : VERDE,
    value: String(summary.value.open_orders || 0), hint: 'pendentes + encomendados',
  },
]);

const lowStockItems = computed(() => (data.value?.items || []).filter(i => i.low));

// ── catálogo (criar / editar) ──
const blankItem = () => ({
  name: '', category: 'lentes', specification: '', quantity: 0,
  min_quantity: 0, unit_cost: '', sale_price: '', supplier: '', notes: '',
});
const itemForm = ref(blankItem());
const editingItemId = ref(null);
const savingItem = ref(false);
const showItemForm = ref(false);

const startNewItem = () => {
  editingItemId.value = null;
  itemForm.value = blankItem();
  showItemForm.value = true;
};
const startEditItem = item => {
  editingItemId.value = item.id;
  itemForm.value = {
    ...item,
    unit_cost: item.unit_cost.toLocaleString('pt-BR', { minimumFractionDigits: 2 }),
    sale_price: item.sale_price.toLocaleString('pt-BR', { minimumFractionDigits: 2 }),
  };
  showItemForm.value = true;
};
const cancelItem = () => {
  showItemForm.value = false;
  editingItemId.value = null;
  itemForm.value = blankItem();
};

const saveItem = async () => {
  if (!itemForm.value.name.trim()) {
    useAlert('Dê um nome ao item (ex: Lente Trifocal).');
    return;
  }
  savingItem.value = true;
  try {
    const payload = {
      ...itemForm.value,
      unit_cost: parseAmount(itemForm.value.unit_cost),
      sale_price: parseAmount(itemForm.value.sale_price),
    };
    if (editingItemId.value) await CrmAPI.updateStockItem(editingItemId.value, payload);
    else await CrmAPI.createStockItem(payload);
    useAlert(editingItemId.value ? 'Item atualizado. 📦' : 'Item adicionado ao estoque. 📦');
    cancelItem();
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o item.');
  } finally {
    savingItem.value = false;
  }
};

const removeItem = async item => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir "${item.name}" do catálogo de estoque?`)) return;
  try {
    await CrmAPI.deleteStockItem(item.id);
    await load();
  } catch {
    useAlert('Não consegui excluir.');
  }
};

// ── pedidos ──
const orderForm = ref({ item_name: '', specification: '', quantity: 1, reason: '' });
const savingOrder = ref(false);
const showOrderForm = ref(false);

const saveOrder = async () => {
  if (!orderForm.value.item_name.trim()) {
    useAlert('O que precisa ser encomendado?');
    return;
  }
  savingOrder.value = true;
  try {
    await CrmAPI.createStockOrder(orderForm.value);
    useAlert('Pedido criado. 🛒');
    orderForm.value = { item_name: '', specification: '', quantity: 1, reason: '' };
    showOrderForm.value = false;
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui criar o pedido.');
  } finally {
    savingOrder.value = false;
  }
};

// auditoria S1: trava de requisição em andamento — duplo clique no
// "Recebi ✓" não dispara duas somas
const updatingOrderId = ref(null);
const setOrderStatus = async (order, status) => {
  if (updatingOrderId.value) return;
  updatingOrderId.value = order.id;
  try {
    await CrmAPI.updateStockOrder(order.id, status);
    if (status === 'recebido') useAlert('Pedido recebido — quantidade somada no estoque. ✅');
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui atualizar o pedido.');
  } finally {
    updatingOrderId.value = null;
  }
};

const removeOrder = async order => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir o pedido de "${order.item_name}"?`)) return;
  try {
    await CrmAPI.deleteStockOrder(order.id);
    await load();
  } catch {
    useAlert('Não consegui excluir.');
  }
};

const openPatient = order => {
  if (!order.contact_id) return;
  const accountId = window.location.pathname.split('/')[3];
  router.push(frontendURL(`accounts/${accountId}/patient/${order.contact_id}`));
};
</script>

<template>
  <SkeletonScreen v-if="isLoading" variant="dashboard" />
  <template v-else-if="data">
    <!-- indicadores do estoque -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-3">
      <div v-for="card in kpiCards" :key="card.key" class="rounded-2xl border border-n-weak bg-n-card p-4">
        <div class="flex items-center gap-2 mb-2">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" :style="{ background: card.color }">
            <span :class="card.icon" class="text-white text-sm" />
          </span>
          <p class="text-[11px] font-bold text-n-slate-11 leading-tight">{{ card.label }}</p>
        </div>
        <p class="text-xl sm:text-2xl font-bold tabular-nums" :style="{ color: card.color }">{{ card.value }}</p>
        <p class="text-[10px] text-n-slate-9 mt-1">{{ card.hint }}</p>
      </div>
    </div>

    <!-- alerta de estoque mínimo -->
    <div
      v-if="lowStockItems.length"
      class="rounded-2xl border p-3.5 mb-4 flex items-start gap-2.5"
      style="border-color: rgba(217, 119, 6, 0.35); background: rgba(217, 119, 6, 0.08)"
    >
      <span class="i-lucide-alert-triangle text-base mt-0.5" style="color: #D97706" />
      <div class="min-w-0">
        <p class="text-xs font-bold text-n-slate-12">
          {{ lowStockItems.length }} item(ns) no estoque mínimo
        </p>
        <p class="text-[11px] text-n-slate-11 mt-0.5">
          {{ lowStockItems.map(i => `${i.name}${i.specification ? ` (${i.specification})` : ''} — ${i.quantity} un.`).join(' · ') }}
        </p>
      </div>
    </div>

    <!-- catálogo -->
    <div class="rounded-2xl border border-n-weak bg-n-card overflow-hidden mb-4">
      <div class="px-4 sm:px-5 py-3 border-b border-n-weak flex items-center gap-2">
        <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #065F46, #10B981)">
          <span class="i-lucide-package text-white text-sm" />
        </span>
        <h2 class="text-sm font-bold text-n-slate-12">Itens em estoque</h2>
        <button
          class="ml-auto h-8 px-3 rounded-lg text-xs font-bold text-white"
          style="background: linear-gradient(135deg, #065F46, #10B981)"
          @click="showItemForm ? cancelItem() : startNewItem()"
        >
          {{ showItemForm ? 'Fechar' : '+ Novo item' }}
        </button>
      </div>

      <!-- formulário do item -->
      <div v-if="showItemForm" class="px-4 sm:px-5 py-4 border-b border-n-weak bg-n-alpha-1">
        <div class="flex items-end gap-2.5 flex-wrap">
          <label class="block flex-1" style="min-width: 12rem">
            <span class="text-[11px] font-medium text-n-slate-11">Item</span>
            <input
              v-model="itemForm.name"
              type="text"
              placeholder="Ex: Lente Trifocal"
              class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Categoria</span>
            <select
              v-model="itemForm.category"
              class="mt-1 block h-9 rounded-lg px-2 text-xs text-n-slate-12"
              style="width: 10rem; margin-bottom: 0; border: 1px solid rgba(148, 163, 184, 0.35); background-color: transparent"
            >
              <option v-for="(label, k) in data.categories" :key="k" :value="k">{{ label }}</option>
            </select>
          </label>
          <label class="block flex-1" style="min-width: 12rem">
            <span class="text-[11px] font-medium text-n-slate-11">Configuração</span>
            <input
              v-model="itemForm.specification"
              type="text"
              placeholder="Ex: +21,5 D · marca Alcon"
              class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Qtd</span>
            <input
              v-model.number="itemForm.quantity"
              type="number"
              min="0"
              class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
              style="width: 5rem; margin-bottom: 0"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Qtd mínima</span>
            <input
              v-model.number="itemForm.min_quantity"
              type="number"
              min="0"
              class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
              style="width: 5.5rem; margin-bottom: 0"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Custo unit. (R$)</span>
            <input
              v-model="itemForm.unit_cost"
              type="text"
              inputmode="decimal"
              placeholder="3.500,00"
              class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
              style="width: 7.5rem; margin-bottom: 0"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Preço venda (R$)</span>
            <input
              v-model="itemForm.sale_price"
              type="text"
              inputmode="decimal"
              placeholder="8.490,00"
              class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
              style="width: 7.5rem; margin-bottom: 0"
            />
          </label>
          <label class="block flex-1" style="min-width: 10rem">
            <span class="text-[11px] font-medium text-n-slate-11">Fornecedor</span>
            <input
              v-model="itemForm.supplier"
              type="text"
              class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
          </label>
          <button
            class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
            style="background: linear-gradient(135deg, #065F46, #10B981)"
            :disabled="savingItem"
            @click="saveItem"
          >
            {{ savingItem ? 'Salvando…' : editingItemId ? 'Salvar alterações' : 'Adicionar' }}
          </button>
        </div>
      </div>

      <div v-if="!data.items.length" class="py-12 text-center">
        <p class="text-3xl mb-2">📦</p>
        <p class="text-sm font-semibold text-n-slate-12 mb-1">Estoque vazio</p>
        <p class="text-xs text-n-slate-10">Cadastre a primeira lente ou insumo no botão "+ Novo item".</p>
      </div>
      <div v-else class="divide-y divide-n-weak">
        <div
          v-for="item in data.items"
          :key="item.id"
          class="px-4 sm:px-5 py-2.5 flex items-center gap-3 hover:bg-n-alpha-1 transition-colors"
        >
          <span
            class="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0"
            :style="{ background: `${CATEGORY_META[item.category]?.color}1A` }"
          >
            <span :class="CATEGORY_META[item.category]?.icon" class="text-sm" :style="{ color: CATEGORY_META[item.category]?.color }" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="text-xs font-semibold text-n-slate-12 truncate">
              {{ item.name }}
              <span v-if="item.specification" class="font-normal text-n-slate-10">— {{ item.specification }}</span>
            </p>
            <p class="text-[10px] text-n-slate-9">
              {{ item.category_label }}<template v-if="item.supplier"> · {{ item.supplier }}</template>
            </p>
          </div>
          <!-- zerado sem mínimo definido = neutro (nem alerta, nem "ok") -->
          <span
            class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0 tabular-nums"
            :style="item.low
              ? { background: '#DC26261A', color: '#DC2626' }
              : item.quantity === 0
                ? { background: 'rgba(100,116,139,0.14)', color: '#64748B' }
                : { background: '#0596691A', color: '#059669' }"
            :title="item.low ? 'No estoque mínimo — hora de repor' : item.quantity === 0 ? 'Sem unidades' : 'Estoque ok'"
          >
            {{ item.quantity }} un.
          </span>
          <div class="text-right flex-shrink-0 hidden sm:block" style="width: 7rem">
            <p class="text-[10px] text-n-slate-9">custo total</p>
            <b class="text-xs tabular-nums" style="color: #0F5FA6">{{ fmtMoney(item.total_cost) }}</b>
          </div>
          <!-- sem preço de venda = item de consumo, não tem lucro pra medir -->
          <div class="text-right flex-shrink-0 hidden sm:block" style="width: 7.5rem">
            <p class="text-[10px] text-n-slate-9">lucro potencial</p>
            <b v-if="item.sale_price > 0" class="text-xs tabular-nums" style="color: #059669">{{ fmtMoney(item.potential_profit) }}</b>
            <span v-else class="text-xs text-n-slate-9">—</span>
          </div>
          <button
            class="w-7 h-7 rounded-lg hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-10 flex-shrink-0"
            title="Editar"
            @click="startEditItem(item)"
          >
            <span class="i-lucide-pencil text-xs" />
          </button>
          <button
            class="w-7 h-7 rounded-lg hover:bg-red-500/10 flex items-center justify-center text-n-slate-10 hover:text-red-500 flex-shrink-0"
            title="Excluir"
            @click="removeItem(item)"
          >
            <span class="i-lucide-trash-2 text-xs" />
          </button>
        </div>
      </div>
    </div>

    <!-- pedidos -->
    <div class="rounded-2xl border border-n-weak bg-n-card overflow-hidden mb-6">
      <div class="px-4 sm:px-5 py-3 border-b border-n-weak flex items-center gap-2">
        <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: #0F5FA6">
          <span class="i-lucide-truck text-white text-sm" />
        </span>
        <h2 class="text-sm font-bold text-n-slate-12">Pedidos</h2>
        <span class="text-[11px] text-n-slate-9">encomendas para repor ou atender uma indicação</span>
        <button
          class="ml-auto h-8 px-3 rounded-lg text-xs font-bold text-white"
          style="background: #0F5FA6"
          @click="showOrderForm = !showOrderForm"
        >
          {{ showOrderForm ? 'Fechar' : '+ Novo pedido' }}
        </button>
      </div>

      <div v-if="showOrderForm" class="px-4 sm:px-5 py-4 border-b border-n-weak bg-n-alpha-1">
        <div class="flex items-end gap-2.5 flex-wrap">
          <label class="block flex-1" style="min-width: 12rem">
            <span class="text-[11px] font-medium text-n-slate-11">Item</span>
            <input
              v-model="orderForm.item_name"
              type="text"
              placeholder="Ex: Lente Trifocal"
              class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
          </label>
          <label class="block flex-1" style="min-width: 10rem">
            <span class="text-[11px] font-medium text-n-slate-11">Configuração</span>
            <input
              v-model="orderForm.specification"
              type="text"
              class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
          </label>
          <label class="block">
            <span class="text-[11px] font-medium text-n-slate-11">Qtd</span>
            <input
              v-model.number="orderForm.quantity"
              type="number"
              min="1"
              class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
              style="width: 5rem; margin-bottom: 0"
            />
          </label>
          <label class="block flex-1" style="min-width: 14rem">
            <span class="text-[11px] font-medium text-n-slate-11">Motivo</span>
            <input
              v-model="orderForm.reason"
              type="text"
              placeholder="Ex: reposição do mês"
              class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
          </label>
          <button
            class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
            style="background: #0F5FA6"
            :disabled="savingOrder"
            @click="saveOrder"
          >
            {{ savingOrder ? 'Criando…' : 'Criar pedido' }}
          </button>
        </div>
      </div>

      <div v-if="!data.orders.length" class="py-10 text-center">
        <p class="text-3xl mb-2">🛒</p>
        <p class="text-sm font-semibold text-n-slate-12 mb-1">Nenhum pedido</p>
        <p class="text-xs text-n-slate-10">
          Pedidos nascem aqui ou direto da indicação de cirurgia sem estoque, já vinculados ao paciente.
        </p>
      </div>
      <div v-else class="divide-y divide-n-weak">
        <div
          v-for="order in data.orders"
          :key="order.id"
          class="px-4 sm:px-5 py-2.5 flex items-center gap-3 hover:bg-n-alpha-1 transition-colors"
        >
          <span
            class="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0"
            :style="{ background: `${STATUS_META[order.status]?.color}1A`, color: STATUS_META[order.status]?.color }"
          >
            <span :class="STATUS_META[order.status]?.icon" class="text-[10px]" />
            {{ order.status_label }}
          </span>
          <div class="min-w-0 flex-1">
            <p class="text-xs font-semibold text-n-slate-12 truncate">
              {{ order.quantity }}× {{ order.item_name }}
              <span v-if="order.specification" class="font-normal text-n-slate-10">— {{ order.specification }}</span>
            </p>
            <p class="text-[10px] text-n-slate-9 truncate">
              {{ fmtDate(order.created_at) }}<template v-if="order.reason"> · {{ order.reason }}</template>
            </p>
          </div>
          <button
            v-if="order.contact_name"
            class="text-[10px] font-semibold px-2 py-0.5 rounded-full flex-shrink-0 hover:opacity-80"
            style="background: #7C3AED1A; color: #7C3AED"
            title="Abrir o espaço do paciente"
            @click="openPatient(order)"
          >
            👤 {{ order.contact_name }}
          </button>
          <template v-if="order.status === 'pendente'">
            <button
              class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white flex-shrink-0 disabled:opacity-50"
              style="background: #0F5FA6"
              :disabled="updatingOrderId === order.id"
              @click="setOrderStatus(order, 'encomendado')"
            >
              Encomendei
            </button>
          </template>
          <template v-if="order.status === 'pendente' || order.status === 'encomendado'">
            <button
              class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white flex-shrink-0 disabled:opacity-50"
              style="background: #059669"
              title="Marca como recebido e soma no estoque"
              :disabled="updatingOrderId === order.id"
              @click="setOrderStatus(order, 'recebido')"
            >
              {{ updatingOrderId === order.id ? 'Salvando…' : 'Recebi ✓' }}
            </button>
            <button
              class="h-7 px-2.5 rounded-lg text-[10px] font-medium text-n-slate-11 border border-n-weak hover:bg-n-alpha-1 flex-shrink-0 disabled:opacity-50"
              :disabled="updatingOrderId === order.id"
              @click="setOrderStatus(order, 'cancelado')"
            >
              Cancelar
            </button>
          </template>
          <button
            v-else
            class="w-7 h-7 rounded-lg hover:bg-red-500/10 flex items-center justify-center text-n-slate-10 hover:text-red-500 flex-shrink-0"
            title="Excluir"
            @click="removeOrder(order)"
          >
            <span class="i-lucide-trash-2 text-xs" />
          </button>
        </div>
      </div>
    </div>
  </template>
</template>
