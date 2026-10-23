<script setup>
// 👓 SUA ÓTICA — VENDA (O.S.), fase 1 (22/10/2026). A tela principal da loja:
// cliente (contato do sistema, achado ou criado), receita (OD/OE), produtos
// (armação, lentes, serviço), resumo bruto/desconto/líquido, pagamento,
// previsão de entrega → Gravar. Gravar abre a O.S. e leva o card do cliente
// para "Pedido fechado" no funil; depois: Segundo par, Pedir ao laboratório
// e Enviar resumo pelo WhatsApp. Embaixo, as vendas recentes (lista | cards).
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { parseMoneyBR } from 'dashboard/helper/cevicoMoney';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CrmAPI from 'dashboard/api/crm';
import ContactAPI from 'dashboard/api/contacts';
import {
  fmtMoney,
  moneyInput,
  fmtDate,
  todayISO,
  daysFromNow,
  STATUS_META,
  KIND_META,
  METHOD_META,
  LAB_META,
  INPUT,
  LABEL,
  VERDE,
  AZUL,
  ROXO,
  VERMELHO,
  AMBAR,
  OURO,
  orderLate,
} from './oticaFormat';

const store = useStore();
const { canEdit } = useCevicoAccess();
const editable = computed(() => canEdit('otica.vendas'));

const pal = useCevicoPalette({
  scope: 'otica:venda',
  blocks: [
    { id: 'hoje', label: 'Hoje', icon: 'i-lucide-gauge' },
    { id: 'venda', label: 'Nova venda', icon: 'i-lucide-receipt-text' },
    { id: 'recentes', label: 'Vendas recentes', icon: 'i-lucide-history' },
  ],
});
const pageStyle = computed(() => pal.cvVars.value);

// ── dados da tela ──
const isLoading = ref(true);
const loadError = ref('');
const data = ref(null);
const statuses = computed(() => data.value?.statuses || {});
const paymentMethods = computed(() => data.value?.payment_methods || {});
const kinds = computed(() => data.value?.kinds || {});
const summary = computed(() => data.value?.summary || {});
const orders = computed(() => data.value?.orders || []);

const load = async () => {
  loadError.value = '';
  try {
    const { data: payload } = await CrmAPI.getOticaOrders();
    data.value = payload;
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Não consegui carregar as vendas.';
  } finally {
    isLoading.value = false;
  }
};

// vendedores = usuários da conta
const agents = computed(() => store.getters['agents/getAgents'] || []);
const currentUser = computed(() => store.getters.getCurrentUser);
const loadAgents = async () => {
  if (agents.value.length) return;
  try {
    await store.dispatch('agents/get');
  } catch {
    // sem a lista, o campo fica livre
  }
};

// fornecedores do tipo laboratório (para o pedido ao lab)
const suppliers = ref([]);
const labs = computed(() => suppliers.value.filter(s => s.kind === 'lab'));
const loadSuppliers = async () => {
  try {
    const { data: payload } = await CrmAPI.getOticaSuppliers();
    suppliers.value = payload.suppliers || [];
  } catch {
    suppliers.value = [];
  }
};

onMounted(() => {
  load();
  loadAgents();
  loadSuppliers();
});

// ── indicadores de hoje ──
const kpis = computed(() => [
  {
    key: 'abertas',
    label: 'Abertas',
    hint: 'vendas gravadas, ainda sem produção',
    icon: 'i-lucide-receipt-text',
    color: AZUL,
    value: String(summary.value.abertas ?? 0),
  },
  {
    key: 'em_producao',
    label: 'Em produção',
    hint: 'lentes no laboratório ou montagem',
    icon: 'i-lucide-factory',
    color: ROXO,
    value: String(summary.value.em_producao ?? 0),
  },
  {
    key: 'prontas',
    label: 'Prontas',
    hint: 'esperando o cliente retirar',
    icon: 'i-lucide-package-check',
    color: AMBAR,
    value: String(summary.value.prontas ?? 0),
  },
  {
    key: 'atrasadas',
    label: 'Atrasadas',
    hint: 'previsão de entrega já passou',
    icon: 'i-lucide-alarm-clock',
    color: (summary.value.atrasadas ?? 0) > 0 ? VERMELHO : VERDE,
    value: String(summary.value.atrasadas ?? 0),
  },
  {
    key: 'vendido_mes',
    label: 'Vendido no mês',
    hint: 'líquido das vendas gravadas',
    icon: 'i-lucide-coins',
    color: VERDE,
    value: fmtMoney(summary.value.vendido_mes),
  },
  {
    key: 'ticket_mes',
    label: 'Ticket médio',
    hint: 'por venda no mês',
    icon: 'i-lucide-gem',
    color: OURO,
    value: fmtMoney(summary.value.ticket_mes),
  },
]);

// ── o formulário da O.S. ──
const blankEye = () => ({
  sphere: '',
  cylinder: '',
  axis: '',
  addition: '',
  dnp: '',
  height: '',
});
const blankPrescription = () => ({
  doctor_name: '',
  prescribed_on: '',
  valid_until: '',
  notes: '',
  photo_url: '',
  od: blankEye(),
  oe: blankEye(),
});
const blankItem = (product = null) => ({
  product_id: product?.id ?? null,
  kind: product?.kind ?? 'armacao',
  description: product?.name ?? '',
  quantity: 1,
  unit_price: moneyInput(product?.price ?? ''),
  discount: '',
});
const blankPayment = () => ({
  method: 'pix',
  installments: 1,
  amount: '',
  notes: '',
});
const blankForm = () => ({
  id: null,
  status: null,
  contactMode: 'buscar', // buscar | novo
  contact: null, // { id, name, phone_number }
  newContact: { name: '', phone_number: '' },
  seller_id: currentUser.value?.id ?? null,
  doctor_name: '',
  sold_on: todayISO(),
  due_on: daysFromNow(7),
  discount: '',
  notes: '',
  second_pair_of_id: null,
  withPrescription: true,
  prescription: blankPrescription(),
  items: [blankItem()],
  payments: [blankPayment()],
});

const form = ref(blankForm());
const saving = ref(false);
const saved = ref(null); // a O.S. gravada (depois do Gravar / ao abrir uma)
const formOpen = ref(true);

const resetForm = () => {
  form.value = blankForm();
  saved.value = null;
  contactQuery.value = '';
  contactResults.value = [];
  productQuery.value = '';
  productResults.value = [];
};

// totais ao vivo
const num = v => (parseMoneyBR(v) ?? Number(v)) || 0;
const itemTotal = it =>
  Math.max(0, Number(it.quantity || 0) * num(it.unit_price) - num(it.discount));
const gross = computed(() =>
  form.value.items.reduce((acc, it) => acc + itemTotal(it), 0)
);
const discount = computed(() => num(form.value.discount));
const net = computed(() => Math.max(0, gross.value - discount.value));
const paid = computed(() =>
  form.value.payments.reduce((acc, p) => acc + num(p.amount), 0)
);
const balance = computed(() => net.value - paid.value);

// ── cliente: busca no cadastro ou cliente novo ──
const contactQuery = ref('');
const contactResults = ref([]);
const searchingContacts = ref(false);
let contactTimer = null;
watch(contactQuery, q => {
  clearTimeout(contactTimer);
  if (!q || q.trim().length < 2) {
    contactResults.value = [];
    return;
  }
  contactTimer = setTimeout(async () => {
    searchingContacts.value = true;
    try {
      const { data: payload } = await ContactAPI.search(q.trim(), 1, 'name');
      contactResults.value = (payload?.payload || []).slice(0, 8);
    } catch {
      contactResults.value = [];
    } finally {
      searchingContacts.value = false;
    }
  }, 300);
});
const pickContact = c => {
  form.value.contact = { id: c.id, name: c.name, phone_number: c.phone_number };
  contactQuery.value = '';
  contactResults.value = [];
};
const clearContact = () => {
  form.value.contact = null;
};

// ── produtos: busca por grife, modelo ou código ──
const productQuery = ref('');
const productResults = ref([]);
const searchingProducts = ref(false);
let productTimer = null;
watch(productQuery, q => {
  clearTimeout(productTimer);
  if (!q || q.trim().length < 2) {
    productResults.value = [];
    return;
  }
  productTimer = setTimeout(async () => {
    searchingProducts.value = true;
    try {
      const { data: payload } = await CrmAPI.getOticaProducts({
        q: q.trim(),
        active: 1,
      });
      productResults.value = (payload?.products || []).slice(0, 8);
    } catch {
      productResults.value = [];
    } finally {
      searchingProducts.value = false;
    }
  }, 300);
});
const addProduct = p => {
  // o primeiro item vazio é substituído, não somado
  const first = form.value.items[0];
  if (
    form.value.items.length === 1 &&
    !first.product_id &&
    !first.description
  ) {
    form.value.items.splice(0, 1, blankItem(p));
  } else {
    form.value.items.push(blankItem(p));
  }
  productQuery.value = '';
  productResults.value = [];
};
const addFreeItem = () => form.value.items.push(blankItem());
const removeItem = idx => {
  form.value.items.splice(idx, 1);
  if (!form.value.items.length) form.value.items.push(blankItem());
};

const addPayment = () => {
  const p = blankPayment();
  if (balance.value > 0) p.amount = moneyInput(balance.value);
  form.value.payments.push(p);
};
const removePayment = idx => form.value.payments.splice(idx, 1);
const fillPaymentWithBalance = p => {
  p.amount = moneyInput(Math.max(0, net.value - (paid.value - num(p.amount))));
};

// ── gravar ──
const eyePayload = e => ({
  sphere: e.sphere === '' ? null : e.sphere,
  cylinder: e.cylinder === '' ? null : e.cylinder,
  axis: e.axis === '' ? null : e.axis,
  addition: e.addition === '' ? null : e.addition,
  dnp: e.dnp === '' ? null : e.dnp,
  height: e.height === '' ? null : e.height,
});
const buildPayload = status => {
  const f = form.value;
  const payload = {
    seller_id: f.seller_id || null,
    doctor_name: f.doctor_name || f.prescription.doctor_name || '',
    sold_on: f.sold_on || null,
    due_on: f.due_on || null,
    discount: num(f.discount),
    notes: f.notes || '',
    status,
    second_pair_of_id: f.second_pair_of_id || null,
    items: f.items
      .filter(it => it.description || it.product_id)
      .map(it => ({
        product_id: it.product_id || null,
        kind: it.kind,
        description: it.description,
        quantity: Number(it.quantity || 1),
        unit_price: num(it.unit_price),
        discount: num(it.discount),
      })),
    payments: f.payments
      .filter(p => num(p.amount) > 0)
      .map(p => ({
        method: p.method,
        installments: Number(p.installments || 1),
        amount: num(p.amount),
        notes: p.notes || '',
      })),
  };
  if (f.contactMode === 'novo') {
    payload.contact = {
      name: f.newContact.name.trim(),
      phone_number: f.newContact.phone_number.trim(),
    };
  } else if (f.contact) {
    payload.contact_id = f.contact.id;
  }
  if (f.withPrescription) {
    payload.prescription = {
      doctor_name: f.prescription.doctor_name || f.doctor_name || '',
      prescribed_on: f.prescription.prescribed_on || null,
      valid_until: f.prescription.valid_until || null,
      notes: f.prescription.notes || '',
      photo_url: f.prescription.photo_url || '',
      od: eyePayload(f.prescription.od),
      oe: eyePayload(f.prescription.oe),
    };
  }
  return payload;
};

const validate = () => {
  const f = form.value;
  if (f.contactMode === 'novo') {
    if (!f.newContact.name.trim()) return 'Dê o nome do cliente.';
    if (!f.newContact.phone_number.trim())
      return 'Informe o celular do cliente (com DDD).';
  } else if (!f.contact) {
    return 'Escolha o cliente (busque pelo nome ou celular) ou marque "cliente novo".';
  }
  const items = f.items.filter(it => it.description || it.product_id);
  if (!items.length) return 'Adicione pelo menos um produto ou serviço.';
  return null;
};

const save = async status => {
  const problem = validate();
  if (problem) {
    useAlert(problem);
    return;
  }
  saving.value = true;
  try {
    const payload = buildPayload(status);
    const res = form.value.id
      ? await CrmAPI.updateOticaOrder(form.value.id, payload)
      : await CrmAPI.createOticaOrder(payload);
    const order = res.data?.order || res.data;
    saved.value = order;
    loadIntoForm(order);
    useAlert(
      status === 'orcamento'
        ? `Orçamento nº ${order.number} guardado.`
        : `Venda nº ${order.number} gravada. O cliente foi para "Pedido fechado" no funil.`
    );
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui gravar a venda.');
  } finally {
    saving.value = false;
  }
};

// abrir uma O.S. existente no formulário
const eyeForm = e => ({
  sphere: e?.sphere ?? '',
  cylinder: e?.cylinder ?? '',
  axis: e?.axis ?? '',
  addition: e?.addition ?? '',
  dnp: e?.dnp ?? '',
  height: e?.height ?? '',
});
const loadIntoForm = order => {
  const p = order.prescription;
  form.value = {
    id: order.id,
    status: order.status,
    contactMode: 'buscar',
    contact: order.contact
      ? {
          id: order.contact.id,
          name: order.contact.name,
          phone_number: order.contact.phone_number,
        }
      : null,
    newContact: { name: '', phone_number: '' },
    seller_id: order.seller?.id ?? null,
    doctor_name: order.doctor_name || '',
    sold_on: order.sold_on || todayISO(),
    due_on: order.due_on || '',
    discount: moneyInput(order.discount),
    notes: order.notes || '',
    second_pair_of_id: order.second_pair_of_id || null,
    withPrescription: Boolean(p),
    prescription: p
      ? {
          doctor_name: p.doctor_name || '',
          prescribed_on: p.prescribed_on || '',
          valid_until: p.valid_until || '',
          notes: p.notes || '',
          photo_url: p.photo_url || '',
          od: eyeForm(p.od),
          oe: eyeForm(p.oe),
        }
      : blankPrescription(),
    items: (order.items || []).map(it => ({
      id: it.id,
      product_id: it.product_id,
      kind: it.kind,
      description: it.description,
      quantity: it.quantity,
      unit_price: moneyInput(it.unit_price),
      discount: moneyInput(it.discount || 0),
      lab_order: it.lab_order || null,
    })),
    payments: (order.payments || []).map(pm => ({
      id: pm.id,
      method: pm.method,
      installments: pm.installments,
      amount: moneyInput(pm.amount),
      notes: pm.notes || '',
    })),
  };
  if (!form.value.items.length) form.value.items.push(blankItem());
  if (!form.value.payments.length) form.value.payments.push(blankPayment());
  saved.value = order;
  formOpen.value = true;
};

const openOrder = async order => {
  try {
    const { data: payload } = await CrmAPI.getOticaOrder(order.id);
    loadIntoForm(payload.order || payload);
    document
      .getElementById('otica-venda-form')
      ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui abrir a venda.');
  }
};

// a O.S. gravada pode ser editada? (depois de entregue/cancelada, só leitura)
const lockedStatuses = ['entregue', 'cancelada', 'devolvida'];
const formLocked = computed(
  () =>
    !editable.value ||
    (saved.value && lockedStatuses.includes(saved.value.status))
);

// ── segundo par ──
const secondPair = () => {
  const base = saved.value;
  if (!base) return;
  const f = blankForm();
  f.contact = base.contact
    ? {
        id: base.contact.id,
        name: base.contact.name,
        phone_number: base.contact.phone_number,
      }
    : null;
  f.seller_id = base.seller?.id ?? f.seller_id;
  f.doctor_name = base.doctor_name || '';
  f.second_pair_of_id = base.id;
  if (base.prescription) {
    const p = base.prescription;
    f.withPrescription = true;
    f.prescription = {
      doctor_name: p.doctor_name || '',
      prescribed_on: p.prescribed_on || '',
      valid_until: p.valid_until || '',
      notes: p.notes || '',
      photo_url: p.photo_url || '',
      od: eyeForm(p.od),
      oe: eyeForm(p.oe),
    };
  }
  form.value = f;
  saved.value = null;
  useAlert(
    `Segundo par de ${base.contact?.name || 'cliente'}: cliente e receita já preenchidos. Escolha os produtos e grave.`
  );
  document
    .getElementById('otica-venda-form')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

// ── pedir ao laboratório ──
const labModal = ref(false);
const labForm = ref({
  item_ids: [],
  supplier_id: null,
  expected_on: '',
  cost: '',
  notes: '',
});
const labItems = computed(() =>
  (saved.value?.items || []).filter(it => !it.lab_order)
);
const openLabModal = () => {
  const lensIds = labItems.value
    .filter(it => ['lente', 'lente_contato'].includes(it.kind))
    .map(it => it.id);
  const lab = labs.value[0];
  labForm.value = {
    item_ids: lensIds.length ? lensIds : labItems.value.map(it => it.id),
    supplier_id: lab?.id ?? null,
    expected_on: daysFromNow(lab?.lab_days || 7),
    cost: '',
    notes: '',
  };
  labModal.value = true;
};
const onLabSupplierChange = () => {
  const lab = labs.value.find(l => l.id === labForm.value.supplier_id);
  if (lab?.lab_days) labForm.value.expected_on = daysFromNow(lab.lab_days);
};
const toggleLabItem = id => {
  const list = labForm.value.item_ids;
  const i = list.indexOf(id);
  if (i >= 0) list.splice(i, 1);
  else list.push(id);
};
const sendingLab = ref(false);
const sendToLab = async () => {
  if (!labForm.value.item_ids.length) {
    useAlert('Marque pelo menos um item para o laboratório.');
    return;
  }
  sendingLab.value = true;
  try {
    const { data: payload } = await CrmAPI.createOticaLabOrders(saved.value.id, {
      item_ids: labForm.value.item_ids,
      supplier_id: labForm.value.supplier_id || null,
      expected_on: labForm.value.expected_on || null,
      cost: num(labForm.value.cost),
      notes: labForm.value.notes || '',
    });
    loadIntoForm(payload.order || payload);
    labModal.value = false;
    useAlert('Pedido ao laboratório registrado. A venda está em produção.');
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui registrar o pedido.');
  } finally {
    sendingLab.value = false;
  }
};

// ── resumo pelo WhatsApp ──
const sendingWa = ref(false);
const sendWhatsapp = async order => {
  sendingWa.value = true;
  try {
    const { data: payload } = await CrmAPI.getOticaOrderWhatsapp(order.id);
    if (payload.link) window.open(payload.link, '_blank', 'noopener');
    else useAlert('A venda não tem celular do cliente para enviar.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui montar o resumo.');
  } finally {
    sendingWa.value = false;
  }
};

// ── mudar status / excluir ──
const busyOrderId = ref(null);
const setStatus = async (order, status) => {
  if (busyOrderId.value) return;
  const payload = { status };
  if (status === 'entregue') payload.delivered_at = new Date().toISOString();
  if (
    ['cancelada', 'devolvida'].includes(status) &&
    // eslint-disable-next-line no-alert
    !window.confirm(
      `Marcar a venda nº ${order.number} como ${statuses.value[status]?.toLowerCase() || status}?`
    )
  )
    return;
  busyOrderId.value = order.id;
  try {
    const { data: payload2 } = await CrmAPI.setOticaOrderStatus(
      order.id,
      payload
    );
    const updated = payload2.order || payload2;
    if (saved.value?.id === order.id) loadIntoForm(updated);
    useAlert(`Venda nº ${order.number}: ${updated.status_label}.`);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui mudar o status.');
  } finally {
    busyOrderId.value = null;
  }
};
const removeOrder = async order => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir o orçamento nº ${order.number}?`)) return;
  try {
    await CrmAPI.deleteOticaOrder(order.id);
    if (saved.value?.id === order.id) resetForm();
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui excluir.');
  }
};

// próximos passos possíveis de cada O.S. (botões)
const nextSteps = order => {
  const steps = [];
  if (order.status === 'orcamento')
    steps.push({ status: 'aberta', label: 'Fechar venda', color: AZUL });
  if (order.status === 'aberta')
    steps.push({ status: 'em_producao', label: 'Em produção', color: ROXO });
  if (['aberta', 'em_producao'].includes(order.status))
    steps.push({ status: 'pronta', label: 'Pronta', color: AMBAR });
  if (['aberta', 'em_producao', 'pronta'].includes(order.status))
    steps.push({ status: 'entregue', label: 'Retirou', color: VERDE });
  if (order.status === 'entregue')
    steps.push({ status: 'devolvida', label: 'Devolvida', color: VERMELHO });
  return steps;
};

// ── vendas recentes ──
const view = ref('list');
const filter = ref('todas');
const search = ref('');
const filterOptions = computed(() => [
  { key: 'todas', label: 'Todas' },
  ...Object.entries(statuses.value).map(([key, label]) => ({ key, label })),
]);
const shown = computed(() => {
  const q = search.value.trim().toLowerCase();
  return orders.value.filter(o => {
    if (filter.value !== 'todas' && o.status !== filter.value) return false;
    if (!q) return true;
    const hay = `${o.number} ${o.contact?.name || ''} ${
      o.contact?.phone_number || ''
    } ${o.seller?.name || ''}`.toLowerCase();
    return hay.includes(q);
  });
});
const itemsLine = order =>
  (order.items || [])
    .map(it => `${it.quantity}× ${it.description}`)
    .join(' · ') || 'Sem itens';
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Venda"
        subtitle="A O.S. da loja: cliente, receita, produtos, pagamento e previsão de entrega. Gravar leva o cliente para o funil e deixa a venda pronta para o laboratório."
        icon="i-lucide-receipt-text"
        :palette="false"
      >
        <template #chips>
          <span class="cv-glass-chip">
            <span class="i-lucide-receipt-text text-xs" />
            {{ (summary.abertas ?? 0) + (summary.em_producao ?? 0) }} em
            andamento
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

        <!-- bloco 1 · hoje -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <h2 class="cv-ag-block-title">Hoje</h2>
          <span class="cv-ag-block-sub">
            como está a loja agora: o que está aberto, no laboratório, pronto e
            o que já vendeu no mês
          </span>
          <div
            class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3 mt-4"
          >
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

        <!-- bloco 2 · a venda -->
        <section id="otica-venda-form" class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-start gap-3 flex-wrap">
            <div class="min-w-0">
              <h2 class="cv-ag-block-title">
                <template v-if="saved">
                  Venda nº {{ saved.number }}
                  <span
                    class="inline-flex items-center gap-1 text-[11px] font-bold px-2 py-0.5 rounded-full align-middle ml-1"
                    :style="{
                      background: `${STATUS_META[saved.status]?.color}1A`,
                      color: STATUS_META[saved.status]?.color,
                    }"
                  >
                    <span :class="STATUS_META[saved.status]?.icon" />
                    {{ saved.status_label }}
                  </span>
                </template>
                <template v-else-if="form.second_pair_of_id">
                  Segundo par
                </template>
                <template v-else>Nova venda</template>
              </h2>
              <span class="cv-ag-block-sub">
                <template v-if="saved && saved.crm_card">
                  card em {{ saved.crm_card.stage_name }} ·
                  {{ saved.crm_card.pipeline_name }}
                </template>
                <template v-else-if="form.second_pair_of_id">
                  segundo óculos da venda nº
                  {{
                    orders.find(o => o.id === form.second_pair_of_id)?.number ||
                    form.second_pair_of_id
                  }}
                  · cliente e receita já vieram da primeira
                </template>
                <template v-else>
                  cliente → receita → produtos → pagamento → previsão → Gravar
                </template>
              </span>
            </div>
            <div class="ml-auto flex items-center gap-2 flex-wrap">
              <button
                v-if="saved || form.id"
                class="cv-btn cv-btn-ghost cv-btn-sm"
                @click="resetForm"
              >
                <span class="i-lucide-plus text-xs" /> Nova venda
              </button>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                @click="formOpen = !formOpen"
              >
                <span
                  :class="formOpen ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
                  class="text-xs"
                />
                {{ formOpen ? 'Recolher' : 'Abrir' }}
              </button>
            </div>
          </div>

          <!-- ações depois de gravar -->
          <div
            v-if="saved && editable"
            class="cv-sub p-3 mt-4 flex items-center gap-2 flex-wrap"
          >
            <span class="text-[11px] font-semibold text-n-slate-11 mr-1">
              Próximo passo:
            </span>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="lockedStatuses.includes(saved.status)"
              @click="secondPair"
            >
              <span class="i-lucide-copy-plus text-xs" /> Segundo par
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="
                !labItems.length ||
                !['aberta', 'em_producao'].includes(saved.status)
              "
              title="Registrar o pedido das lentes ao laboratório"
              @click="openLabModal"
            >
              <span class="i-lucide-factory text-xs" /> Pedir ao laboratório
            </button>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="sendingWa"
              @click="sendWhatsapp(saved)"
            >
              <span class="i-lucide-message-circle text-xs" /> Enviar resumo pelo
              WhatsApp
            </button>
            <span class="flex-1" />
            <button
              v-for="step in nextSteps(saved)"
              :key="step.status"
              class="h-7 px-2.5 rounded-lg text-[11px] font-bold text-white disabled:opacity-50"
              :style="{ background: step.color }"
              :disabled="busyOrderId === saved.id"
              @click="setStatus(saved, step.status)"
            >
              {{ step.label }}
            </button>
            <button
              v-if="!lockedStatuses.includes(saved.status)"
              class="cv-btn cv-btn-ghost cv-btn-sm cv-btn-danger"
              :disabled="busyOrderId === saved.id"
              @click="setStatus(saved, 'cancelada')"
            >
              Cancelar venda
            </button>
          </div>

          <div v-show="formOpen" class="ot-form mt-5 flex flex-col gap-6">
            <!-- cliente -->
            <div>
              <p class="ot-step"><span>1</span> Cliente</p>
              <div v-if="form.contact" class="cv-sub p-3 flex items-center gap-3">
                <span
                  class="w-9 h-9 rounded-xl grid place-items-center text-white flex-shrink-0"
                  :style="{ background: AZUL }"
                >
                  <span class="i-lucide-user-round text-sm" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-bold text-n-slate-12">
                    {{ form.contact.name || 'Sem nome' }}
                  </p>
                  <p class="text-[11px] text-n-slate-11">
                    {{ form.contact.phone_number || 'sem celular' }}
                  </p>
                </div>
                <button
                  v-if="!formLocked"
                  class="cv-btn cv-btn-ghost cv-btn-sm"
                  @click="clearContact"
                >
                  Trocar
                </button>
              </div>
              <template v-else>
                <div class="cv-seg mb-3">
                  <button
                    class="cv-seg-item"
                    :class="form.contactMode === 'buscar' ? 'cv-seg-on' : ''"
                    @click="form.contactMode = 'buscar'"
                  >
                    <span class="i-lucide-search text-sm" /> Buscar no cadastro
                  </button>
                  <button
                    class="cv-seg-item"
                    :class="form.contactMode === 'novo' ? 'cv-seg-on' : ''"
                    @click="form.contactMode = 'novo'"
                  >
                    <span class="i-lucide-user-round-plus text-sm" /> Cliente novo
                  </button>
                </div>
                <div v-if="form.contactMode === 'buscar'" class="relative">
                  <input
                    v-model="contactQuery"
                    type="text"
                    :class="INPUT"
                    placeholder="Nome ou celular do cliente"
                    :disabled="formLocked"
                  />
                  <div
                    v-if="contactResults.length"
                    class="absolute z-20 left-0 right-0 mt-1 rounded-xl border border-n-weak bg-n-card shadow-lg overflow-hidden"
                  >
                    <button
                      v-for="c in contactResults"
                      :key="c.id"
                      class="w-full text-left px-3 py-2 hover:bg-n-alpha-1 flex items-center gap-2"
                      @click="pickContact(c)"
                    >
                      <span class="i-lucide-user-round text-xs text-n-slate-10" />
                      <span class="text-xs font-semibold text-n-slate-12">
                        {{ c.name || 'Sem nome' }}
                      </span>
                      <span class="text-[11px] text-n-slate-10 ml-auto">
                        {{ c.phone_number || '' }}
                      </span>
                    </button>
                  </div>
                  <p
                    v-else-if="contactQuery.length >= 2 && !searchingContacts"
                    class="text-[11px] text-n-slate-10 mt-1"
                  >
                    Ninguém com esse nome ou celular. Marque "Cliente novo".
                  </p>
                </div>
                <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <label class="block">
                    <span :class="LABEL">Nome</span>
                    <input
                      v-model="form.newContact.name"
                      type="text"
                      :class="INPUT"
                      placeholder="Nome completo"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Celular (com DDD)</span>
                    <input
                      v-model="form.newContact.phone_number"
                      type="tel"
                      :class="INPUT"
                      placeholder="11 9 9999-9999"
                    />
                  </label>
                </div>
              </template>
              <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-3">
                <label class="block">
                  <span :class="LABEL">Vendedor</span>
                  <select
                    v-model="form.seller_id"
                    :class="INPUT"
                    :disabled="formLocked"
                  >
                    <option :value="null">—</option>
                    <option v-for="a in agents" :key="a.id" :value="a.id">
                      {{ a.name }}
                    </option>
                  </select>
                </label>
                <label class="block">
                  <span :class="LABEL">Data da venda</span>
                  <input
                    v-model="form.sold_on"
                    type="date"
                    :class="INPUT"
                    :disabled="formLocked"
                  />
                </label>
                <label class="block">
                  <span :class="LABEL">Previsão de entrega</span>
                  <input
                    v-model="form.due_on"
                    type="date"
                    :class="INPUT"
                    :disabled="formLocked"
                  />
                </label>
              </div>
            </div>

            <!-- receita -->
            <div>
              <div class="flex items-center gap-3 flex-wrap">
                <p class="ot-step mb-0"><span>2</span> Receita</p>
                <label class="flex items-center gap-1.5 text-[11px] text-n-slate-11 ml-auto">
                  <input
                    v-model="form.withPrescription"
                    type="checkbox"
                    :disabled="formLocked"
                  />
                  tem receita (grau)
                </label>
              </div>
              <div v-if="form.withPrescription" class="mt-2 flex flex-col gap-3">
                <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <label class="block">
                    <span :class="LABEL">Médico(a)</span>
                    <input
                      v-model="form.prescription.doctor_name"
                      type="text"
                      :class="INPUT"
                      placeholder="Dr(a). …"
                      :disabled="formLocked"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Data da receita</span>
                    <input
                      v-model="form.prescription.prescribed_on"
                      type="date"
                      :class="INPUT"
                      :disabled="formLocked"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Válida até</span>
                    <input
                      v-model="form.prescription.valid_until"
                      type="date"
                      :class="INPUT"
                      :disabled="formLocked"
                    />
                  </label>
                </div>
                <div class="overflow-x-auto">
                  <table class="ot-eyes w-full text-xs">
                    <thead>
                      <tr class="text-[10px] uppercase tracking-wide text-n-slate-10">
                        <th class="text-left py-1 pr-2">Olho</th>
                        <th>Esférico</th>
                        <th>Cilíndrico</th>
                        <th>Eixo</th>
                        <th>Adição</th>
                        <th>DNP</th>
                        <th>Altura</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="eye in [
                          { key: 'od', label: 'OD · direito' },
                          { key: 'oe', label: 'OE · esquerdo' },
                        ]"
                        :key="eye.key"
                      >
                        <td class="font-bold text-n-slate-12 whitespace-nowrap pr-2">
                          {{ eye.label }}
                        </td>
                        <td
                          v-for="f in ['sphere', 'cylinder', 'axis', 'addition', 'dnp', 'height']"
                          :key="f"
                          class="px-0.5"
                        >
                          <input
                            v-model="form.prescription[eye.key][f]"
                            type="text"
                            inputmode="decimal"
                            class="h-9 w-full min-w-[4.2rem] rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-center"
                            :placeholder="f === 'axis' ? '0–180' : '0,00'"
                            :disabled="formLocked"
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <label class="block">
                    <span :class="LABEL">Observação da receita</span>
                    <input
                      v-model="form.prescription.notes"
                      type="text"
                      :class="INPUT"
                      placeholder="Ex.: usa para perto e computador"
                      :disabled="formLocked"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Foto da receita (link)</span>
                    <input
                      v-model="form.prescription.photo_url"
                      type="url"
                      :class="INPUT"
                      placeholder="https://…"
                      :disabled="formLocked"
                    />
                  </label>
                </div>
              </div>
            </div>

            <!-- produtos -->
            <div>
              <p class="ot-step"><span>3</span> Produtos e serviços</p>
              <div v-if="!formLocked" class="relative mb-3">
                <input
                  v-model="productQuery"
                  type="text"
                  :class="INPUT"
                  placeholder="Buscar por grife, modelo ou código"
                />
                <div
                  v-if="productResults.length"
                  class="absolute z-20 left-0 right-0 mt-1 rounded-xl border border-n-weak bg-n-card shadow-lg overflow-hidden"
                >
                  <button
                    v-for="p in productResults"
                    :key="p.id"
                    class="w-full text-left px-3 py-2 hover:bg-n-alpha-1 flex items-center gap-2"
                    @click="addProduct(p)"
                  >
                    <span
                      :class="KIND_META[p.kind]?.icon"
                      class="text-xs"
                      :style="{ color: KIND_META[p.kind]?.color }"
                    />
                    <span class="text-xs font-semibold text-n-slate-12">
                      {{ p.name }}
                    </span>
                    <span class="text-[11px] text-n-slate-10">
                      {{ p.sku || '' }}
                      <template v-if="p.quantity !== undefined">
                        · {{ p.quantity }} un.
                      </template>
                    </span>
                    <span class="text-xs font-bold tabular-nums ml-auto whitespace-nowrap" :style="{ color: VERDE }">
                      {{ fmtMoney(p.price) }}
                    </span>
                  </button>
                </div>
                <p
                  v-else-if="productQuery.length >= 2 && !searchingProducts"
                  class="text-[11px] text-n-slate-10 mt-1"
                >
                  Nenhum produto com esse nome. Cadastre em Produtos e estoque ou
                  adicione um item livre.
                </p>
              </div>
              <div class="flex flex-col gap-2">
                <div
                  v-for="(it, idx) in form.items"
                  :key="idx"
                  class="cv-sub p-3 grid gap-2 items-end"
                  style="grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr))"
                >
                  <label class="block" style="grid-column: span 2">
                    <span :class="LABEL">Descrição</span>
                    <input
                      v-model="it.description"
                      type="text"
                      :class="INPUT"
                      placeholder="Armação, lente, serviço…"
                      :disabled="formLocked"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Tipo</span>
                    <select v-model="it.kind" :class="INPUT" :disabled="formLocked">
                      <option v-for="(label, k) in kinds" :key="k" :value="k">
                        {{ label }}
                      </option>
                    </select>
                  </label>
                  <label class="block">
                    <span :class="LABEL">Qtd</span>
                    <input
                      v-model.number="it.quantity"
                      type="number"
                      min="1"
                      :class="INPUT"
                      class="text-right"
                      :disabled="formLocked"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Preço unit. (R$)</span>
                    <input
                      v-model="it.unit_price"
                      type="text"
                      inputmode="decimal"
                      :class="INPUT"
                      class="text-right"
                      placeholder="0,00"
                      :disabled="formLocked"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Desconto (R$)</span>
                    <input
                      v-model="it.discount"
                      type="text"
                      inputmode="decimal"
                      :class="INPUT"
                      class="text-right"
                      placeholder="0,00"
                      :disabled="formLocked"
                    />
                  </label>
                  <div class="flex items-center justify-end gap-2">
                    <div class="text-right">
                      <p class="text-[10px] text-n-slate-9">total</p>
                      <b class="text-xs tabular-nums whitespace-nowrap" :style="{ color: VERDE }">
                        {{ fmtMoney(itemTotal(it)) }}
                      </b>
                    </div>
                    <span
                      v-if="it.lab_order"
                      class="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full"
                      :style="{
                        background: `${LAB_META[it.lab_order.status]?.color}1A`,
                        color: LAB_META[it.lab_order.status]?.color,
                      }"
                      :title="`Laboratório: ${it.lab_order.supplier_name || '—'} · previsto ${fmtDate(it.lab_order.expected_on)}`"
                    >
                      <span :class="LAB_META[it.lab_order.status]?.icon" />
                      {{ it.lab_order.status_label }}
                    </span>
                    <button
                      v-if="!formLocked"
                      class="w-7 h-7 rounded-lg hover:bg-red-500/10 grid place-items-center text-n-slate-10 hover:text-red-500"
                      title="Tirar item"
                      @click="removeItem(idx)"
                    >
                      <span class="i-lucide-trash-2 text-xs" />
                    </button>
                  </div>
                </div>
              </div>
              <button
                v-if="!formLocked"
                class="cv-btn cv-btn-ghost cv-btn-sm mt-2"
                @click="addFreeItem"
              >
                <span class="i-lucide-plus text-xs" /> Item livre (sem cadastro)
              </button>
            </div>

            <!-- resumo + pagamento -->
            <div class="grid grid-cols-1 lg:grid-cols-5 gap-4">
              <div class="cv-sub p-4 lg:col-span-2 flex flex-col gap-2">
                <p class="ot-step mb-1"><span>4</span> Resumo</p>
                <div class="flex items-center justify-between text-xs">
                  <span class="text-n-slate-11">Bruto</span>
                  <b class="tabular-nums text-n-slate-12">{{ fmtMoney(gross) }}</b>
                </div>
                <label class="flex items-center justify-between gap-3 text-xs">
                  <span class="text-n-slate-11">Desconto (R$)</span>
                  <input
                    v-model="form.discount"
                    type="text"
                    inputmode="decimal"
                    class="h-8 w-28 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 text-right"
                    placeholder="0,00"
                    :disabled="formLocked"
                  />
                </label>
                <div class="flex items-center justify-between text-sm border-t border-n-weak pt-2">
                  <span class="font-bold text-n-slate-12">Líquido</span>
                  <b class="text-lg tabular-nums whitespace-nowrap" :style="{ color: VERDE }">
                    {{ fmtMoney(net) }}
                  </b>
                </div>
                <div class="flex items-center justify-between text-xs">
                  <span class="text-n-slate-11">Pago</span>
                  <b class="tabular-nums text-n-slate-12">{{ fmtMoney(paid) }}</b>
                </div>
                <div class="flex items-center justify-between text-xs">
                  <span class="text-n-slate-11">Falta</span>
                  <b
                    class="tabular-nums"
                    :style="{ color: balance > 0.009 ? AMBAR : VERDE }"
                  >
                    {{ fmtMoney(Math.max(0, balance)) }}
                  </b>
                </div>
              </div>

              <div class="cv-sub p-4 lg:col-span-3 flex flex-col gap-2">
                <div class="flex items-center gap-2">
                  <p class="ot-step mb-0"><span>5</span> Pagamento</p>
                  <button
                    v-if="!formLocked"
                    class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
                    @click="addPayment"
                  >
                    <span class="i-lucide-plus text-xs" /> Outro meio
                  </button>
                </div>
                <div
                  v-for="(pm, idx) in form.payments"
                  :key="idx"
                  class="grid gap-2 items-end"
                  style="grid-template-columns: repeat(auto-fit, minmax(6.5rem, 1fr))"
                >
                  <label class="block">
                    <span :class="LABEL">Meio</span>
                    <select v-model="pm.method" :class="INPUT" :disabled="formLocked">
                      <option
                        v-for="(label, k) in paymentMethods"
                        :key="k"
                        :value="k"
                      >
                        {{ label }}
                      </option>
                    </select>
                  </label>
                  <label class="block">
                    <span :class="LABEL">Parcelas</span>
                    <input
                      v-model.number="pm.installments"
                      type="number"
                      min="1"
                      max="24"
                      :class="INPUT"
                      class="text-right"
                      :disabled="formLocked || !['credito', 'crediario', 'boleto'].includes(pm.method)"
                    />
                  </label>
                  <label class="block">
                    <span :class="LABEL">Valor (R$)</span>
                    <input
                      v-model="pm.amount"
                      type="text"
                      inputmode="decimal"
                      :class="INPUT"
                      class="text-right"
                      placeholder="0,00"
                      :disabled="formLocked"
                    />
                  </label>
                  <div class="flex items-center gap-1 pb-0.5">
                    <button
                      v-if="!formLocked"
                      class="cv-btn cv-btn-ghost cv-btn-sm"
                      title="Preencher com o que falta"
                      @click="fillPaymentWithBalance(pm)"
                    >
                      <span class="i-lucide-wand-sparkles text-xs" /> o que falta
                    </button>
                    <button
                      v-if="!formLocked && form.payments.length > 1"
                      class="w-7 h-7 rounded-lg hover:bg-red-500/10 grid place-items-center text-n-slate-10 hover:text-red-500"
                      title="Tirar"
                      @click="removePayment(idx)"
                    >
                      <span class="i-lucide-trash-2 text-xs" />
                    </button>
                  </div>
                </div>
                <p class="text-[10px] text-n-slate-9">
                  Parcelas detalhadas e conciliação do cartão chegam na fase do
                  Financeiro. Aqui fica o meio, o número de parcelas e o valor.
                </p>
              </div>
            </div>

            <!-- observação + gravar -->
            <div class="flex flex-col gap-3">
              <label class="block">
                <span :class="LABEL">Observação da venda</span>
                <textarea
                  v-model="form.notes"
                  rows="2"
                  class="mt-1 block w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-2 text-xs text-n-slate-12"
                  placeholder="Ex.: cliente pediu para avisar pelo WhatsApp quando chegar"
                  :disabled="formLocked"
                />
              </label>
              <div v-if="!formLocked" class="flex items-center gap-2 flex-wrap">
                <button
                  class="h-10 px-5 rounded-xl text-sm font-bold text-white disabled:opacity-60"
                  :style="{ background: 'linear-gradient(135deg, #065F46, #10B981)' }"
                  :disabled="saving"
                  @click="save(saved?.status && saved.status !== 'orcamento' ? saved.status : 'aberta')"
                >
                  <span class="i-lucide-check text-xs mr-1" />
                  {{
                    saving
                      ? 'Gravando…'
                      : saved && saved.status !== 'orcamento'
                        ? 'Salvar alterações'
                        : 'Gravar venda'
                  }}
                </button>
                <button
                  v-if="!saved || saved.status === 'orcamento'"
                  class="cv-btn"
                  :disabled="saving"
                  @click="save('orcamento')"
                >
                  <span class="i-lucide-file-pen-line text-xs" /> Guardar como
                  orçamento
                </button>
                <span class="text-[11px] text-n-slate-10">
                  Gravar = venda fechada: o cliente vai para "Pedido fechado" no
                  funil. Orçamento não mexe no funil.
                </span>
              </div>
              <p v-else-if="saved" class="text-[11px] text-n-slate-10">
                Venda {{ saved.status_label.toLowerCase() }}: só leitura.
              </p>
            </div>
          </div>
        </section>

        <!-- bloco 3 · vendas recentes -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-center gap-3 flex-wrap mb-4">
            <div>
              <h2 class="cv-ag-block-title">Vendas recentes</h2>
              <span class="cv-ag-block-sub">
                {{ shown.length }} venda(s) · abertas, em produção, prontas e as
                dos últimos 90 dias
              </span>
            </div>
            <div class="cv-seg ml-auto">
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
          </div>
          <div class="flex items-center gap-2 flex-wrap mb-4">
            <button
              v-for="f in filterOptions"
              :key="f.key"
              class="cv-tag cv-tag-btn"
              :class="filter === f.key ? 'cv-tag-solid' : 'cv-tag-ghost'"
              @click="filter = f.key"
            >
              {{ f.label }}
            </button>
            <input
              v-model="search"
              type="text"
              class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 ml-auto"
              style="min-width: 12rem; margin-bottom: 0"
              placeholder="Buscar por cliente, celular ou nº"
            />
          </div>

          <div v-if="!shown.length" class="cv-sub p-8 text-center text-n-slate-10">
            <span class="i-lucide-receipt-text text-3xl block mx-auto mb-2" />
            <p class="text-sm">Nenhuma venda aqui ainda.</p>
          </div>

          <div
            v-else
            :class="
              view === 'cards'
                ? 'grid grid-cols-1 md:grid-cols-2 gap-4'
                : 'flex flex-col gap-2'
            "
          >
            <article
              v-for="o in shown"
              :key="o.id"
              class="cv-sub p-4 flex flex-col gap-3 border-l-4"
              :class="busyOrderId === o.id ? 'opacity-50 pointer-events-none' : ''"
              :style="{
                borderLeftColor: orderLate(o) ? VERMELHO : STATUS_META[o.status]?.color,
              }"
            >
              <header class="flex items-start gap-2.5 flex-wrap">
                <span
                  class="w-8 h-8 rounded-lg grid place-items-center text-white flex-shrink-0"
                  :style="{ background: STATUS_META[o.status]?.color }"
                >
                  <span :class="STATUS_META[o.status]?.icon" class="text-xs" />
                </span>
                <div class="min-w-0 flex-1">
                  <button
                    class="text-left font-bold text-[14px] text-n-slate-12 hover:underline"
                    @click="openOrder(o)"
                  >
                    Nº {{ o.number }} · {{ o.contact?.name || 'Sem nome' }}
                    <span class="i-lucide-arrow-up-right text-xs" />
                  </button>
                  <p class="text-[12px] text-n-slate-11 mt-0.5">
                    {{ o.status_label }}
                    <template v-if="o.seller?.name"> · {{ o.seller.name }}</template>
                    · {{ fmtDate(o.sold_on) }}
                    <template v-if="o.due_on">
                      · entrega
                      <b :style="{ color: orderLate(o) ? VERMELHO : 'inherit' }">
                        {{ fmtDate(o.due_on) }}{{ orderLate(o) ? ' (atrasada)' : '' }}
                      </b>
                    </template>
                  </p>
                </div>
                <div class="text-right">
                  <b class="text-sm tabular-nums whitespace-nowrap" :style="{ color: VERDE }">
                    {{ fmtMoney(o.net) }}
                  </b>
                  <p
                    v-if="o.balance > 0.009"
                    class="text-[10px] whitespace-nowrap"
                    :style="{ color: AMBAR }"
                  >
                    falta {{ fmtMoney(o.balance) }}
                  </p>
                </div>
              </header>
              <p v-if="view === 'cards'" class="text-[12px] text-n-slate-11">
                {{ itemsLine(o) }}
              </p>
              <div
                v-if="view === 'cards' && o.payments?.length"
                class="flex items-center gap-1.5 flex-wrap"
              >
                <span
                  v-for="pm in o.payments"
                  :key="pm.id"
                  class="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full"
                  :style="{
                    background: `${METHOD_META[pm.method]?.color}1A`,
                    color: METHOD_META[pm.method]?.color,
                  }"
                >
                  <span :class="METHOD_META[pm.method]?.icon" />
                  {{ pm.method_label
                  }}{{ pm.installments > 1 ? ` ${pm.installments}×` : '' }}
                  · {{ fmtMoney(pm.amount) }}
                </span>
              </div>
              <div v-if="editable" class="flex items-center gap-2 flex-wrap">
                <button
                  v-for="step in nextSteps(o)"
                  :key="step.status"
                  class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white disabled:opacity-50"
                  :style="{ background: step.color }"
                  @click="setStatus(o, step.status)"
                >
                  {{ step.label }}
                </button>
                <button
                  class="cv-btn cv-btn-ghost cv-btn-sm"
                  :disabled="sendingWa"
                  @click="sendWhatsapp(o)"
                >
                  <span class="i-lucide-message-circle text-xs" /> WhatsApp
                </button>
                <button
                  v-if="['orcamento', 'cancelada'].includes(o.status)"
                  class="cv-btn cv-btn-ghost cv-btn-sm cv-btn-danger ml-auto"
                  @click="removeOrder(o)"
                >
                  <span class="i-lucide-trash-2 text-xs" /> Excluir
                </button>
              </div>
            </article>
          </div>
        </section>
      </template>
    </div>

    <!-- modal · pedir ao laboratório -->
    <div
      v-if="labModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-3"
      style="background: rgba(15, 23, 42, 0.45)"
      @click.self="labModal = false"
    >
      <div class="cv-modal ot-form w-full max-w-lg rounded-2xl bg-n-card border border-n-weak p-5 flex flex-col gap-4 max-h-[90vh] overflow-y-auto">
        <div class="flex items-start gap-3">
          <span
            class="w-9 h-9 rounded-xl grid place-items-center text-white flex-shrink-0"
            :style="{ background: ROXO }"
          >
            <span class="i-lucide-factory text-sm" />
          </span>
          <div class="min-w-0 flex-1">
            <h3 class="text-base font-extrabold text-n-slate-12">
              Pedir ao laboratório
            </h3>
            <p class="text-[12px] text-n-slate-11">
              Venda nº {{ saved?.number }} · marque o que vai para o laboratório
            </p>
          </div>
          <button
            class="w-8 h-8 rounded-lg hover:bg-n-alpha-2 grid place-items-center text-n-slate-10"
            @click="labModal = false"
          >
            <span class="i-lucide-x text-sm" />
          </button>
        </div>

        <div class="flex flex-col gap-1.5">
          <label
            v-for="it in labItems"
            :key="it.id"
            class="flex items-center gap-2 rounded-xl border border-n-weak px-3 py-2 cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              :checked="labForm.item_ids.includes(it.id)"
              @change="toggleLabItem(it.id)"
            />
            <span
              :class="KIND_META[it.kind]?.icon"
              class="text-xs"
              :style="{ color: KIND_META[it.kind]?.color }"
            />
            <span class="text-xs font-semibold text-n-slate-12 flex-1">
              {{ it.quantity }}× {{ it.description }}
            </span>
            <span class="text-[11px] text-n-slate-10">{{ it.kind_label }}</span>
          </label>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <label class="block sm:col-span-2">
            <span :class="LABEL">Laboratório</span>
            <select
              v-model="labForm.supplier_id"
              :class="INPUT"
              @change="onLabSupplierChange"
            >
              <option :value="null">— sem laboratório cadastrado —</option>
              <option v-for="l in labs" :key="l.id" :value="l.id">
                {{ l.name }}{{ l.lab_days ? ` · ${l.lab_days} dias` : '' }}
              </option>
            </select>
            <span v-if="!labs.length" class="text-[10px] text-n-slate-9">
              Cadastre os laboratórios em Produtos e estoque → Fornecedores.
            </span>
          </label>
          <label class="block">
            <span :class="LABEL">Previsto para</span>
            <input v-model="labForm.expected_on" type="date" :class="INPUT" />
          </label>
          <label class="block">
            <span :class="LABEL">Custo (R$)</span>
            <input
              v-model="labForm.cost"
              type="text"
              inputmode="decimal"
              :class="INPUT"
              class="text-right"
              placeholder="0,00"
            />
          </label>
          <label class="block sm:col-span-2">
            <span :class="LABEL">Observação para o laboratório</span>
            <input
              v-model="labForm.notes"
              type="text"
              :class="INPUT"
              placeholder="Ex.: antirreflexo, armação segue junto"
            />
          </label>
        </div>

        <div class="flex items-center gap-2 justify-end">
          <button class="cv-btn cv-btn-ghost" @click="labModal = false">
            Voltar
          </button>
          <button
            class="h-9 px-4 rounded-lg text-xs font-bold text-white disabled:opacity-60"
            :style="{ background: ROXO }"
            :disabled="sendingLab"
            @click="sendToLab"
          >
            {{ sendingLab ? 'Registrando…' : 'Registrar pedido' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ot-form input,
.ot-form select,
.ot-form textarea {
  margin-bottom: 0;
}
.ot-step {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  font-weight: 800;
  letter-spacing: -0.01em;
  color: var(--cv, #0f172a);
  margin-bottom: 10px;
}
.ot-step > span {
  width: 22px;
  height: 22px;
  border-radius: 8px;
  display: grid;
  place-items: center;
  font-size: 11px;
  font-weight: 800;
  color: #fff;
  background: var(--cv-grad, linear-gradient(135deg, #0f5fa6, #2563eb));
}
.ot-eyes th,
.ot-eyes td {
  padding: 3px 2px;
}
</style>
