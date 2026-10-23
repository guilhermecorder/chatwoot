<script setup>
// 👓 SUA ÓTICA — PRODUTOS E ESTOQUE, fase 1 (22/10/2026). O catálogo da loja
// em grade (grife · linha · modelo · cor · tamanho), com saldo, custo, preço
// de tabela e promoção; importação do CSV exportado do SavWin; e os
// fornecedores e laboratórios (o laboratório é um fornecedor do tipo "lab").
// Saldo por produto (uma loja); desde a fase 2 toda mudança de saldo vira
// movimentação (tela Estoque).
import { ref, computed, onMounted } from 'vue';
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
  moneyInput,
  fmtDate,
  isPast,
  KIND_META,
  INPUT,
  LABEL,
  VERDE,
  AZUL,
  ROXO,
  VERMELHO,
  AMBAR,
  CINZA,
} from './oticaFormat';

const { canEdit } = useCevicoAccess();
const editable = computed(() => canEdit('otica.produtos'));

const pal = useCevicoPalette({
  scope: 'otica:produtos',
  blocks: [
    { id: 'resumo', label: 'Resumo', icon: 'i-lucide-gauge' },
    { id: 'produtos', label: 'Produtos', icon: 'i-lucide-glasses' },
    { id: 'importar', label: 'Importar do SavWin', icon: 'i-lucide-file-up' },
    { id: 'fornecedores', label: 'Fornecedores', icon: 'i-lucide-truck' },
  ],
});
const pageStyle = computed(() => pal.cvVars.value);

// ── dados ──
const isLoading = ref(true);
const loadError = ref('');
const data = ref(null);
const kinds = computed(() => data.value?.kinds || {});
const lensTypes = computed(() => data.value?.lens_types || {});
const supplierKinds = computed(() => data.value?.supplier_kinds || {});
const summary = computed(() => data.value?.summary || {});
const products = computed(() => data.value?.products || []);
const suppliers = computed(() => data.value?.suppliers || []);

const load = async () => {
  loadError.value = '';
  try {
    const { data: payload } = await CrmAPI.getOticaProducts({ active: 'all' });
    data.value = payload;
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Não consegui carregar os produtos.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const num = v => (parseMoneyBR(v) ?? Number(v)) || 0;

// ── resumo ──
const kpis = computed(() => [
  {
    key: 'count',
    label: 'Produtos',
    hint: `${summary.value.active ?? 0} ativo(s) no catálogo`,
    icon: 'i-lucide-glasses',
    color: AZUL,
    value: String(summary.value.count ?? 0),
  },
  {
    key: 'units',
    label: 'Peças em estoque',
    hint: 'soma dos saldos',
    icon: 'i-lucide-boxes',
    color: ROXO,
    value: String(summary.value.units ?? 0),
  },
  {
    key: 'total_cost',
    label: 'Custo em estoque',
    hint: 'dinheiro parado hoje',
    icon: 'i-lucide-coins',
    color: VERDE,
    value: fmtMoney(summary.value.total_cost),
  },
  {
    key: 'low_stock',
    label: 'Estoque baixo',
    hint: 'no mínimo ou abaixo',
    icon: 'i-lucide-alert-triangle',
    color: (summary.value.low_stock ?? 0) > 0 ? VERMELHO : VERDE,
    value: String(summary.value.low_stock ?? 0),
  },
]);

// ── filtros e visualização ──
const view = ref('list');
const kindFilter = ref('todos');
const activeFilter = ref('ativos'); // ativos | inativos | todos
const search = ref('');
const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return products.value.filter(p => {
    if (kindFilter.value !== 'todos' && p.kind !== kindFilter.value)
      return false;
    if (activeFilter.value === 'ativos' && !p.active) return false;
    if (activeFilter.value === 'inativos' && p.active) return false;
    if (!q) return true;
    const hay = `${p.name} ${p.brand || ''} ${p.line || ''} ${p.model || ''} ${
      p.color || ''
    } ${p.size || ''} ${p.sku || ''} ${p.barcode || ''}`.toLowerCase();
    return hay.includes(q);
  });
});
const gradeLine = p =>
  [p.brand, p.line, p.model, p.color, p.size].filter(Boolean).join(' · ');
const lensLine = p =>
  [
    p.lens_type_label,
    p.lens_material,
    p.lens_treatment,
    p.lab_days ? `${p.lab_days} dias de laboratório` : '',
  ]
    .filter(Boolean)
    .join(' · ');
const isLens = kind => ['lente', 'lente_contato'].includes(kind);
const promoValid = p =>
  p.promo_price > 0 && (!p.promo_until || !isPast(p.promo_until));

// ── produto: criar / editar ──
const blankProduct = () => ({
  kind: 'armacao',
  name: '',
  brand: '',
  line: '',
  model: '',
  color: '',
  size: '',
  sku: '',
  barcode: '',
  ncm: '',
  cost: '',
  list_price: '',
  promo_price: '',
  promo_until: '',
  active: true,
  quantity: 0,
  min_quantity: 0,
  lens_type: 'visao_simples',
  lens_material: '',
  lens_treatment: '',
  lab_days: '',
  supplier_id: null,
  notes: '',
});
const productForm = ref(blankProduct());
const editingId = ref(null);
const showProductForm = ref(false);
const savingProduct = ref(false);

const startNewProduct = () => {
  editingId.value = null;
  productForm.value = blankProduct();
  showProductForm.value = true;
};
const startEditProduct = p => {
  editingId.value = p.id;
  productForm.value = {
    ...blankProduct(),
    ...p,
    cost: moneyInput(p.cost),
    list_price: moneyInput(p.list_price),
    promo_price: p.promo_price ? moneyInput(p.promo_price) : '',
    promo_until: p.promo_until || '',
    lens_type: p.lens_type || 'visao_simples',
    lab_days: p.lab_days ?? '',
    supplier_id: p.supplier_id ?? null,
  };
  showProductForm.value = true;
  document
    .getElementById('otica-produto-form')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};
const cancelProduct = () => {
  showProductForm.value = false;
  editingId.value = null;
  productForm.value = blankProduct();
};
const saveProduct = async () => {
  const f = productForm.value;
  if (!f.name.trim() && !f.brand.trim() && !f.model.trim()) {
    useAlert('Dê um nome ao produto, ou pelo menos grife e modelo.');
    return;
  }
  if (num(f.list_price) <= 0) {
    useAlert('Informe o preço de tabela (maior que zero).');
    return;
  }
  savingProduct.value = true;
  try {
    const payload = {
      kind: f.kind,
      name: f.name.trim(),
      brand: f.brand.trim(),
      line: f.line.trim(),
      model: f.model.trim(),
      color: f.color.trim(),
      size: f.size.trim(),
      sku: f.sku.trim(),
      barcode: f.barcode.trim(),
      ncm: f.ncm.trim(),
      cost: num(f.cost),
      list_price: num(f.list_price),
      promo_price: f.promo_price === '' ? null : num(f.promo_price),
      promo_until: f.promo_until || null,
      active: Boolean(f.active),
      quantity: Number(f.quantity || 0),
      min_quantity: Number(f.min_quantity || 0),
      supplier_id: f.supplier_id || null,
      notes: f.notes.trim(),
    };
    if (isLens(f.kind)) {
      payload.lens_type = f.lens_type;
      payload.lens_material = f.lens_material.trim();
      payload.lens_treatment = f.lens_treatment.trim();
      payload.lab_days = f.lab_days === '' ? null : Number(f.lab_days);
    }
    if (editingId.value)
      await CrmAPI.updateOticaProduct(editingId.value, payload);
    else await CrmAPI.createOticaProduct(payload);
    useAlert(editingId.value ? 'Produto atualizado.' : 'Produto cadastrado.');
    cancelProduct();
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o produto.');
  } finally {
    savingProduct.value = false;
  }
};
const toggleActive = async p => {
  try {
    await CrmAPI.updateOticaProduct(p.id, { active: !p.active });
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui alterar.');
  }
};
const removeProduct = async p => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir "${p.name}" do catálogo?`)) return;
  try {
    await CrmAPI.deleteOticaProduct(p.id);
    await load();
  } catch (e) {
    useAlert(
      e?.response?.data?.error ||
        'Não consegui excluir. Se o produto já foi vendido, desative em vez de excluir.'
    );
  }
};

// ── importar CSV do SavWin ──
const csvText = ref('');
const csvName = ref('');
const importing = ref(false);
const importResult = ref(null);
const onCsvFile = ev => {
  const file = ev.target.files?.[0];
  if (!file) return;
  csvName.value = file.name;
  importResult.value = null;
  const reader = new FileReader();
  reader.onload = () => {
    csvText.value = String(reader.result || '');
  };
  // o SavWin exporta em Windows; latin1 cobre os acentos do CSV dele
  reader.readAsText(file, 'ISO-8859-1');
};
const csvLines = computed(() =>
  csvText.value ? csvText.value.split(/\r?\n/).filter(l => l.trim()).length : 0
);
const importCsv = async () => {
  if (!csvText.value.trim()) {
    useAlert('Escolha o arquivo CSV exportado do SavWin.');
    return;
  }
  importing.value = true;
  try {
    const { data: payload } = await CrmAPI.importOticaProductsCsv({
      csv: csvText.value,
    });
    importResult.value = payload;
    useAlert(
      `Importação: ${payload.created ?? 0} novo(s), ${payload.updated ?? 0} atualizado(s), ${
        payload.skipped ?? 0
      } pulado(s).`
    );
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui importar o arquivo.');
  } finally {
    importing.value = false;
  }
};

// ── fornecedores e laboratórios ──
const blankSupplier = () => ({
  name: '',
  kind: 'lab',
  phone: '',
  email: '',
  lab_days: '',
  notes: '',
  active: true,
});
const supplierForm = ref(blankSupplier());
const editingSupplierId = ref(null);
const showSupplierForm = ref(false);
const savingSupplier = ref(false);
const startNewSupplier = () => {
  editingSupplierId.value = null;
  supplierForm.value = blankSupplier();
  showSupplierForm.value = true;
};
const startEditSupplier = s => {
  editingSupplierId.value = s.id;
  supplierForm.value = { ...blankSupplier(), ...s, lab_days: s.lab_days ?? '' };
  showSupplierForm.value = true;
};
const cancelSupplier = () => {
  showSupplierForm.value = false;
  editingSupplierId.value = null;
  supplierForm.value = blankSupplier();
};
const saveSupplier = async () => {
  const f = supplierForm.value;
  if (!f.name.trim()) {
    useAlert('Dê o nome do fornecedor ou laboratório.');
    return;
  }
  savingSupplier.value = true;
  try {
    const payload = {
      name: f.name.trim(),
      kind: f.kind,
      phone: f.phone.trim(),
      email: f.email.trim(),
      lab_days: f.lab_days === '' ? null : Number(f.lab_days),
      notes: f.notes.trim(),
      active: Boolean(f.active),
    };
    if (editingSupplierId.value)
      await CrmAPI.updateOticaSupplier(editingSupplierId.value, payload);
    else await CrmAPI.createOticaSupplier(payload);
    useAlert(editingSupplierId.value ? 'Fornecedor atualizado.' : 'Fornecedor cadastrado.');
    cancelSupplier();
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar.');
  } finally {
    savingSupplier.value = false;
  }
};
const removeSupplier = async s => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir "${s.name}"?`)) return;
  try {
    await CrmAPI.deleteOticaSupplier(s.id);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui excluir.');
  }
};
const supplierColor = kind => (kind === 'lab' ? ROXO : AZUL);
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Produtos e estoque"
        subtitle="O catálogo da loja em grade: grife, modelo, cor e tamanho, com saldo, custo e preço. Importe do SavWin e cadastre os laboratórios."
        icon="i-lucide-glasses"
        :palette="false"
      >
        <template #chips>
          <span class="cv-glass-chip">
            <span class="i-lucide-glasses text-xs" />
            {{ summary.active ?? 0 }} produto(s) ativo(s)
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

        <!-- bloco 1 · resumo -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <h2 class="cv-ag-block-title">Resumo</h2>
          <span class="cv-ag-block-sub">
            o que a loja tem hoje em peças e em dinheiro parado
          </span>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-4">
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
        </section>

        <!-- bloco 2 · produtos -->
        <section id="otica-produto-form" class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-center gap-3 flex-wrap mb-4">
            <div>
              <h2 class="cv-ag-block-title">Produtos</h2>
              <span class="cv-ag-block-sub">
                {{ shown.length }} produto(s) · saldo em vermelho = no mínimo ou
                abaixo
              </span>
            </div>
            <div class="ml-auto flex items-center gap-2 flex-wrap">
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
              <button
                v-if="editable"
                class="h-8 px-3 rounded-lg text-xs font-bold text-white"
                style="background: linear-gradient(135deg, #065f46, #10b981)"
                @click="showProductForm ? cancelProduct() : startNewProduct()"
              >
                {{ showProductForm ? 'Fechar' : '+ Novo produto' }}
              </button>
            </div>
          </div>

          <!-- formulário -->
          <div v-if="showProductForm" class="ot-form cv-sub p-4 mb-4">
            <p class="text-xs font-bold text-n-slate-12 mb-3">
              {{ editingId ? 'Editar produto' : 'Novo produto' }}
            </p>
            <div
              class="grid gap-3"
              style="grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr))"
            >
              <label class="block">
                <span :class="LABEL">Tipo</span>
                <select v-model="productForm.kind" :class="INPUT">
                  <option v-for="(label, k) in kinds" :key="k" :value="k">
                    {{ label }}
                  </option>
                </select>
              </label>
              <label class="block" style="grid-column: span 2">
                <span :class="LABEL">Nome (opcional: monta de grife + modelo)</span>
                <input
                  v-model="productForm.name"
                  type="text"
                  :class="INPUT"
                  placeholder="Ex.: Ray-Ban RB5154 preto 51"
                />
              </label>
              <label class="block">
                <span :class="LABEL">Grife</span>
                <input v-model="productForm.brand" type="text" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">Linha</span>
                <input v-model="productForm.line" type="text" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">Modelo</span>
                <input v-model="productForm.model" type="text" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">Cor</span>
                <input v-model="productForm.color" type="text" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">Tamanho</span>
                <input v-model="productForm.size" type="text" :class="INPUT" placeholder="Ex.: 52-18" />
              </label>
              <label class="block">
                <span :class="LABEL">Código (SavWin)</span>
                <input v-model="productForm.sku" type="text" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">Código de barras</span>
                <input v-model="productForm.barcode" type="text" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">NCM</span>
                <input v-model="productForm.ncm" type="text" :class="INPUT" placeholder="9003.11.00" />
              </label>
              <label class="block">
                <span :class="LABEL">Custo (R$)</span>
                <input
                  v-model="productForm.cost"
                  type="text"
                  inputmode="decimal"
                  :class="INPUT"
                  class="text-right"
                  placeholder="0,00"
                />
              </label>
              <label class="block">
                <span :class="LABEL">Preço de tabela (R$)</span>
                <input
                  v-model="productForm.list_price"
                  type="text"
                  inputmode="decimal"
                  :class="INPUT"
                  class="text-right"
                  placeholder="0,00"
                />
              </label>
              <label class="block">
                <span :class="LABEL">Preço promocional (R$)</span>
                <input
                  v-model="productForm.promo_price"
                  type="text"
                  inputmode="decimal"
                  :class="INPUT"
                  class="text-right"
                  placeholder="vazio = sem promoção"
                />
              </label>
              <label class="block">
                <span :class="LABEL">Promoção até</span>
                <input v-model="productForm.promo_until" type="date" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">Saldo (vira ajuste no estoque)</span>
                <input
                  v-model.number="productForm.quantity"
                  type="number"
                  min="0"
                  :class="INPUT"
                  class="text-right"
                />
              </label>
              <label class="block">
                <span :class="LABEL">Saldo mínimo</span>
                <input
                  v-model.number="productForm.min_quantity"
                  type="number"
                  min="0"
                  :class="INPUT"
                  class="text-right"
                />
              </label>
              <label class="block">
                <span :class="LABEL">Fornecedor</span>
                <select v-model="productForm.supplier_id" :class="INPUT">
                  <option :value="null">—</option>
                  <option v-for="s in suppliers" :key="s.id" :value="s.id">
                    {{ s.name }}
                  </option>
                </select>
              </label>
              <template v-if="isLens(productForm.kind)">
                <label class="block">
                  <span :class="LABEL">Tipo de lente</span>
                  <select v-model="productForm.lens_type" :class="INPUT">
                    <option v-for="(label, k) in lensTypes" :key="k" :value="k">
                      {{ label }}
                    </option>
                  </select>
                </label>
                <label class="block">
                  <span :class="LABEL">Material</span>
                  <input
                    v-model="productForm.lens_material"
                    type="text"
                    :class="INPUT"
                    placeholder="Ex.: resina 1.56, policarbonato"
                  />
                </label>
                <label class="block">
                  <span :class="LABEL">Tratamento</span>
                  <input
                    v-model="productForm.lens_treatment"
                    type="text"
                    :class="INPUT"
                    placeholder="Ex.: antirreflexo, filtro azul"
                  />
                </label>
                <label class="block">
                  <span :class="LABEL">Prazo do laboratório (dias)</span>
                  <input
                    v-model="productForm.lab_days"
                    type="number"
                    min="0"
                    :class="INPUT"
                    class="text-right"
                  />
                </label>
              </template>
              <label class="block" style="grid-column: 1 / -1">
                <span :class="LABEL">Observação</span>
                <input v-model="productForm.notes" type="text" :class="INPUT" />
              </label>
            </div>
            <div class="flex items-center gap-3 mt-3 flex-wrap">
              <label class="flex items-center gap-1.5 text-xs text-n-slate-11">
                <input v-model="productForm.active" type="checkbox" />
                ativo (aparece na venda e na busca)
              </label>
              <span class="flex-1" />
              <button class="cv-btn cv-btn-ghost" @click="cancelProduct">
                Cancelar
              </button>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                style="background: linear-gradient(135deg, #065f46, #10b981)"
                :disabled="savingProduct"
                @click="saveProduct"
              >
                {{
                  savingProduct
                    ? 'Salvando…'
                    : editingId
                      ? 'Salvar alterações'
                      : 'Cadastrar'
                }}
              </button>
            </div>
          </div>

          <!-- filtros -->
          <div class="flex items-center gap-2 flex-wrap mb-4">
            <button
              class="cv-tag cv-tag-btn"
              :class="kindFilter === 'todos' ? 'cv-tag-solid' : 'cv-tag-ghost'"
              @click="kindFilter = 'todos'"
            >
              Todos
            </button>
            <button
              v-for="(label, k) in kinds"
              :key="k"
              class="cv-tag cv-tag-btn"
              :class="kindFilter === k ? 'cv-tag-solid' : 'cv-tag-ghost'"
              @click="kindFilter = k"
            >
              <span :class="KIND_META[k]?.icon" class="text-[10px]" /> {{ label }}
            </button>
            <select
              v-model="activeFilter"
              class="h-8 rounded-lg px-2 text-xs text-n-slate-12"
              style="border: 1px solid rgba(148, 163, 184, 0.35); background-color: transparent; margin-bottom: 0"
            >
              <option value="ativos">Ativos</option>
              <option value="inativos">Inativos</option>
              <option value="todos">Ativos e inativos</option>
            </select>
            <input
              v-model="search"
              type="text"
              class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 ml-auto"
              style="min-width: 12rem; margin-bottom: 0"
              placeholder="Grife, modelo, cor ou código"
            />
          </div>

          <div v-if="!shown.length" class="cv-sub p-8 text-center text-n-slate-10">
            <span class="i-lucide-glasses text-3xl block mx-auto mb-2" />
            <p class="text-sm">Nenhum produto aqui. Cadastre ou importe do SavWin.</p>
          </div>

          <!-- lista -->
          <div v-else-if="view === 'list'" class="flex flex-col gap-1.5">
            <div
              v-for="p in shown"
              :key="p.id"
              class="cv-sub px-3 py-2.5 flex items-center gap-3 flex-wrap"
              :class="p.active ? '' : 'opacity-60'"
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
                  <span v-if="!p.active" class="font-normal text-n-slate-10">(inativo)</span>
                </p>
                <p class="text-[10px] text-n-slate-9">
                  {{ p.kind_label }}
                  <template v-if="gradeLine(p)"> · {{ gradeLine(p) }}</template>
                  <template v-if="p.sku"> · cód. {{ p.sku }}</template>
                  <template v-if="isLens(p.kind) && lensLine(p)"> · {{ lensLine(p) }}</template>
                </p>
              </div>
              <span
                class="text-[10px] font-bold px-2 py-0.5 rounded-full flex-shrink-0 tabular-nums"
                :style="
                  p.low
                    ? { background: '#DC26261A', color: VERMELHO }
                    : p.quantity === 0
                      ? { background: 'rgba(100,116,139,0.14)', color: CINZA }
                      : { background: '#0596691A', color: VERDE }
                "
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
              <div class="text-right flex-shrink-0" style="width: 7rem">
                <p class="text-[10px] text-n-slate-9">tabela</p>
                <b
                  class="text-xs tabular-nums whitespace-nowrap"
                  :class="promoValid(p) ? 'line-through text-n-slate-10 font-normal' : ''"
                >
                  {{ fmtMoney(p.list_price) }}
                </b>
              </div>
              <div class="text-right flex-shrink-0" style="width: 7.5rem">
                <p class="text-[10px] text-n-slate-9">
                  {{ promoValid(p) ? `promoção até ${fmtDate(p.promo_until)}` : 'preço hoje' }}
                </p>
                <b
                  class="text-xs tabular-nums whitespace-nowrap"
                  :style="{ color: promoValid(p) ? AMBAR : VERDE }"
                >
                  {{ fmtMoney(p.price) }}
                </b>
              </div>
              <template v-if="editable">
                <button
                  class="w-7 h-7 rounded-lg hover:bg-n-alpha-2 grid place-items-center text-n-slate-10 flex-shrink-0"
                  title="Editar"
                  @click="startEditProduct(p)"
                >
                  <span class="i-lucide-pencil text-xs" />
                </button>
                <button
                  class="w-7 h-7 rounded-lg hover:bg-n-alpha-2 grid place-items-center text-n-slate-10 flex-shrink-0"
                  :title="p.active ? 'Desativar' : 'Reativar'"
                  @click="toggleActive(p)"
                >
                  <span :class="p.active ? 'i-lucide-eye-off' : 'i-lucide-eye'" class="text-xs" />
                </button>
                <button
                  class="w-7 h-7 rounded-lg hover:bg-red-500/10 grid place-items-center text-n-slate-10 hover:text-red-500 flex-shrink-0"
                  title="Excluir"
                  @click="removeProduct(p)"
                >
                  <span class="i-lucide-trash-2 text-xs" />
                </button>
              </template>
            </div>
          </div>

          <!-- cards -->
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <article
              v-for="p in shown"
              :key="p.id"
              class="cv-sub p-4 flex flex-col gap-2 border-l-4"
              :class="p.active ? '' : 'opacity-60'"
              :style="{ borderLeftColor: p.low ? VERMELHO : KIND_META[p.kind]?.color }"
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
              </header>
              <p v-if="gradeLine(p)" class="text-[12px] text-n-slate-11">
                {{ gradeLine(p) }}
              </p>
              <p v-if="isLens(p.kind) && lensLine(p)" class="text-[12px] text-n-slate-11">
                {{ lensLine(p) }}
              </p>
              <div class="grid grid-cols-3 gap-2 mt-1">
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
                  <p class="text-[10px] text-n-slate-9">
                    {{ promoValid(p) ? 'promoção' : 'preço' }}
                  </p>
                  <b
                    class="text-xs tabular-nums whitespace-nowrap"
                    :style="{ color: promoValid(p) ? AMBAR : VERDE }"
                  >
                    {{ fmtMoney(p.price) }}
                  </b>
                </div>
              </div>
              <div v-if="editable" class="flex items-center gap-1 mt-1">
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="startEditProduct(p)">
                  <span class="i-lucide-pencil text-xs" /> Editar
                </button>
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="toggleActive(p)">
                  {{ p.active ? 'Desativar' : 'Reativar' }}
                </button>
                <button
                  class="w-7 h-7 rounded-lg hover:bg-red-500/10 grid place-items-center text-n-slate-10 hover:text-red-500 ml-auto"
                  title="Excluir"
                  @click="removeProduct(p)"
                >
                  <span class="i-lucide-trash-2 text-xs" />
                </button>
              </div>
            </article>
          </div>
        </section>

        <!-- bloco 3 · importar do SavWin -->
        <section v-if="editable" class="cv-ag-block p-5 sm:p-7 mb-8">
          <h2 class="cv-ag-block-title">Importar do SavWin</h2>
          <span class="cv-ag-block-sub">
            o arquivo CSV da grade "Exportar" dos produtos. O código do SavWin é
            a chave: produto já cadastrado é atualizado, novo é criado.
          </span>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 mt-4">
            <div class="ot-form cv-sub p-4 flex flex-col gap-3">
              <label class="block">
                <span :class="LABEL">Arquivo .csv</span>
                <input
                  type="file"
                  accept=".csv,text/csv"
                  class="mt-1 block w-full text-xs text-n-slate-12"
                  @change="onCsvFile"
                />
              </label>
              <p v-if="csvName" class="text-[11px] text-n-slate-11">
                {{ csvName }} · {{ csvLines }} linha(s), contando o cabeçalho
              </p>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60 w-fit"
                :style="{ background: AZUL }"
                :disabled="importing || !csvText"
                @click="importCsv"
              >
                <span class="i-lucide-file-up text-xs mr-1" />
                {{ importing ? 'Importando…' : 'Importar produtos' }}
              </button>
              <div v-if="importResult" class="rounded-xl bg-n-alpha-1 p-3 text-xs text-n-slate-12 flex flex-col gap-1">
                <p>
                  <b :style="{ color: VERDE }">{{ importResult.created ?? 0 }}</b> novo(s) ·
                  <b :style="{ color: AZUL }">{{ importResult.updated ?? 0 }}</b> atualizado(s) ·
                  <b :style="{ color: CINZA }">{{ importResult.skipped ?? 0 }}</b> pulado(s)
                </p>
                <ul v-if="importResult.errors?.length" class="text-[11px] mt-1 flex flex-col gap-0.5" :style="{ color: VERMELHO }">
                  <li v-for="(err, i) in importResult.errors.slice(0, 20)" :key="i">{{ err }}</li>
                  <li v-if="importResult.errors.length > 20">
                    … e mais {{ importResult.errors.length - 20 }}
                  </li>
                </ul>
              </div>
            </div>
            <div class="cv-sub p-4 text-xs text-n-slate-11 flex flex-col gap-2">
              <p class="font-bold text-n-slate-12">Colunas que o arquivo precisa ter</p>
              <p>
                Cabeçalho na primeira linha, separado por ponto e vírgula ou
                vírgula, sem distinção de maiúsculas ou acentos:
              </p>
              <p class="font-mono text-[11px] text-n-slate-12 rounded-lg bg-n-alpha-1 p-2">
                codigo; grife; modelo; cor; tamanho; custo; preco; saldo
              </p>
              <p>
                Opcionais: tipo (armacao, solar, lente, lente_contato, servico),
                linha, codigo_barras, ncm. Dinheiro pode vir como 1.234,56.
                Linha sem código é criada como produto novo; linha sem preço é
                pulada e aparece na lista de erros.
              </p>
              <p>
                O saldo do CSV vira um ajuste de estoque, registrado nas
                movimentações.
              </p>
            </div>
          </div>
        </section>

        <!-- bloco 4 · fornecedores e laboratórios -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-center gap-3 flex-wrap mb-4">
            <div>
              <h2 class="cv-ag-block-title">Fornecedores e laboratórios</h2>
              <span class="cv-ag-block-sub">
                o laboratório recebe o pedido das lentes; o prazo em dias vira a
                previsão na venda
              </span>
            </div>
            <button
              v-if="editable"
              class="ml-auto h-8 px-3 rounded-lg text-xs font-bold text-white"
              :style="{ background: ROXO }"
              @click="showSupplierForm ? cancelSupplier() : startNewSupplier()"
            >
              {{ showSupplierForm ? 'Fechar' : '+ Novo fornecedor' }}
            </button>
          </div>

          <div v-if="showSupplierForm" class="ot-form cv-sub p-4 mb-4">
            <div
              class="grid gap-3"
              style="grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr))"
            >
              <label class="block" style="grid-column: span 2">
                <span :class="LABEL">Nome</span>
                <input v-model="supplierForm.name" type="text" :class="INPUT" placeholder="Ex.: Laboratório HB" />
              </label>
              <label class="block">
                <span :class="LABEL">Tipo</span>
                <select v-model="supplierForm.kind" :class="INPUT">
                  <option v-for="(label, k) in supplierKinds" :key="k" :value="k">
                    {{ label }}
                  </option>
                </select>
              </label>
              <label class="block">
                <span :class="LABEL">Telefone / WhatsApp</span>
                <input v-model="supplierForm.phone" type="tel" :class="INPUT" />
              </label>
              <label class="block">
                <span :class="LABEL">E-mail</span>
                <input v-model="supplierForm.email" type="email" :class="INPUT" />
              </label>
              <label v-if="supplierForm.kind === 'lab'" class="block">
                <span :class="LABEL">Prazo padrão (dias)</span>
                <input
                  v-model="supplierForm.lab_days"
                  type="number"
                  min="0"
                  :class="INPUT"
                  class="text-right"
                />
              </label>
              <label class="block" style="grid-column: 1 / -1">
                <span :class="LABEL">Observação</span>
                <input
                  v-model="supplierForm.notes"
                  type="text"
                  :class="INPUT"
                  placeholder="Ex.: pedido pelo portal, retirada às terças"
                />
              </label>
            </div>
            <div class="flex items-center gap-3 mt-3">
              <label class="flex items-center gap-1.5 text-xs text-n-slate-11">
                <input v-model="supplierForm.active" type="checkbox" /> ativo
              </label>
              <span class="flex-1" />
              <button class="cv-btn cv-btn-ghost" @click="cancelSupplier">Cancelar</button>
              <button
                class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
                :style="{ background: ROXO }"
                :disabled="savingSupplier"
                @click="saveSupplier"
              >
                {{ savingSupplier ? 'Salvando…' : editingSupplierId ? 'Salvar alterações' : 'Cadastrar' }}
              </button>
            </div>
          </div>

          <div v-if="!suppliers.length" class="cv-sub p-8 text-center text-n-slate-10">
            <span class="i-lucide-truck text-3xl block mx-auto mb-2" />
            <p class="text-sm">
              Nenhum fornecedor ainda. Cadastre o laboratório das lentes para
              pedir direto da venda.
            </p>
          </div>
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <article
              v-for="s in suppliers"
              :key="s.id"
              class="cv-sub p-4 flex flex-col gap-2 border-l-4"
              :class="s.active ? '' : 'opacity-60'"
              :style="{ borderLeftColor: supplierColor(s.kind) }"
            >
              <header class="flex items-start gap-2">
                <span
                  class="w-8 h-8 rounded-lg grid place-items-center text-white flex-shrink-0"
                  :style="{ background: supplierColor(s.kind) }"
                >
                  <span :class="s.kind === 'lab' ? 'i-lucide-factory' : 'i-lucide-truck'" class="text-xs" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="text-[13px] font-bold text-n-slate-12">{{ s.name }}</p>
                  <p class="text-[11px] text-n-slate-11">
                    {{ s.kind_label || (s.kind === 'lab' ? 'Laboratório' : 'Fornecedor') }}
                    <template v-if="s.kind === 'lab' && s.lab_days"> · {{ s.lab_days }} dias</template>
                    <template v-if="!s.active"> · inativo</template>
                  </p>
                </div>
              </header>
              <p v-if="s.phone || s.email" class="text-[12px] text-n-slate-11">
                {{ [s.phone, s.email].filter(Boolean).join(' · ') }}
              </p>
              <p v-if="s.notes" class="text-[12px] text-n-slate-10">{{ s.notes }}</p>
              <div v-if="editable" class="flex items-center gap-1 mt-1">
                <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="startEditSupplier(s)">
                  <span class="i-lucide-pencil text-xs" /> Editar
                </button>
                <button
                  class="w-7 h-7 rounded-lg hover:bg-red-500/10 grid place-items-center text-n-slate-10 hover:text-red-500 ml-auto"
                  title="Excluir"
                  @click="removeSupplier(s)"
                >
                  <span class="i-lucide-trash-2 text-xs" />
                </button>
              </div>
            </article>
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
