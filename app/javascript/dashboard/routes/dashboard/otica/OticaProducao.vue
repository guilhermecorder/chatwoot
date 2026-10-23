<script setup>
// 👓 SUA ÓTICA — PRODUÇÃO E ENTREGAS, fase 1 (22/10/2026). O quadro do que
// está no laboratório, do que já está pronto e do que foi entregue nos
// últimos 30 dias. Atraso em vermelho (previsão passou e não entregou).
// "Chegou do laboratório" baixa o pedido; "Retirou" entrega a venda e leva
// o card para "Retirou o óculos" no funil de pós-venda (dispara a Jornada).
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  fmtMoney,
  fmtDate,
  fmtDateTime,
  isPast,
  todayISO,
  STATUS_META,
  LAB_META,
  INPUT,
  LABEL,
  VERDE,
  ROXO,
  VERMELHO,
  AMBAR,
  orderLate,
} from './oticaFormat';

const { canEdit } = useCevicoAccess();
const editable = computed(
  () => canEdit('otica.producao') || canEdit('otica.vendas')
);

const pal = useCevicoPalette({
  scope: 'otica:producao',
  blocks: [
    { id: 'resumo', label: 'Resumo', icon: 'i-lucide-gauge' },
    { id: 'quadro', label: 'Quadro', icon: 'i-lucide-kanban' },
  ],
});
const pageStyle = computed(() => pal.cvVars.value);

const isLoading = ref(true);
const loadError = ref('');
const data = ref(null);
const summary = computed(() => data.value?.summary || {});
const orders = computed(() => data.value?.orders || []);

const load = async () => {
  loadError.value = '';
  try {
    const { data: payload } = await CrmAPI.getOticaOrders();
    data.value = payload;
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Não consegui carregar a produção.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

// ── resumo ──
const kpis = computed(() => [
  {
    key: 'em_producao',
    label: 'Em produção',
    hint: 'no laboratório ou em montagem',
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
    hint: 'previsão passou e não entregou',
    icon: 'i-lucide-alarm-clock',
    color: (summary.value.atrasadas ?? 0) > 0 ? VERMELHO : VERDE,
    value: String(summary.value.atrasadas ?? 0),
  },
  {
    key: 'entregues_mes',
    label: 'Entregues no mês',
    hint: 'óculos retirados',
    icon: 'i-lucide-smile',
    color: VERDE,
    value: String(summary.value.entregues_mes ?? 0),
  },
]);

// ── colunas do quadro ──
const thirtyDaysAgo = () => {
  const d = new Date();
  d.setDate(d.getDate() - 30);
  return d;
};
const COLUMNS = [
  {
    key: 'em_producao',
    label: 'Em produção',
    hint: 'lentes no laboratório, montagem',
    color: ROXO,
    icon: 'i-lucide-factory',
  },
  {
    key: 'pronta',
    label: 'Pronta',
    hint: 'avisar o cliente e entregar',
    color: AMBAR,
    icon: 'i-lucide-package-check',
  },
  {
    key: 'entregue',
    label: 'Entregue (30 dias)',
    hint: 'retiradas no último mês',
    color: VERDE,
    icon: 'i-lucide-smile',
  },
];
const byColumn = computed(() => {
  const limit = thirtyDaysAgo();
  const sortByDue = (a, b) => (a.due_on || '9999').localeCompare(b.due_on || '9999');
  return {
    em_producao: orders.value
      .filter(o => o.status === 'em_producao')
      .sort(sortByDue),
    pronta: orders.value.filter(o => o.status === 'pronta').sort(sortByDue),
    entregue: orders.value
      .filter(
        o =>
          o.status === 'entregue' &&
          (!o.delivered_at || new Date(o.delivered_at) >= limit)
      )
      .sort((a, b) => (b.delivered_at || '').localeCompare(a.delivered_at || '')),
  };
});

const view = ref('cards');
const search = ref('');
const match = o => {
  const q = search.value.trim().toLowerCase();
  if (!q) return true;
  return `${o.number} ${o.contact?.name || ''} ${o.contact?.phone_number || ''}`
    .toLowerCase()
    .includes(q);
};

const labLate = lab =>
  lab && !['recebido', 'cancelado'].includes(lab.status) && isPast(lab.expected_on);
const openLabs = o =>
  (o.lab_orders || []).filter(l => !['recebido', 'cancelado'].includes(l.status));
const itemsLine = o =>
  (o.items || []).map(it => `${it.quantity}× ${it.description}`).join(' · ') ||
  'Sem itens';

// ── ações ──
const busyId = ref(null);
const labArrived = async (order, lab) => {
  if (busyId.value) return;
  busyId.value = order.id;
  try {
    const { data: payload } = await CrmAPI.updateOticaLabOrder(lab.id, {
      status: 'recebido',
      received_at: new Date().toISOString(),
    });
    const updated = payload.order || payload;
    useAlert(
      updated.status === 'pronta'
        ? `Nº ${order.number}: tudo chegou, a venda está pronta.`
        : `Nº ${order.number}: pedido do laboratório recebido.`
    );
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui registrar a chegada.');
  } finally {
    busyId.value = null;
  }
};
const setStatus = async (order, status, extra = {}) => {
  if (busyId.value) return;
  busyId.value = order.id;
  try {
    const { data: payload } = await CrmAPI.setOticaOrderStatus(order.id, {
      status,
      ...extra,
    });
    const updated = payload.order || payload;
    useAlert(`Nº ${order.number}: ${updated.status_label}.`);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui mudar o status.');
  } finally {
    busyId.value = null;
  }
};

// retirou: pergunta a data (padrão hoje)
const deliverModal = ref(null); // a O.S.
const deliverDate = ref(todayISO());
const openDeliver = order => {
  deliverModal.value = order;
  deliverDate.value = todayISO();
};
const confirmDeliver = async () => {
  const order = deliverModal.value;
  deliverModal.value = null;
  await setStatus(order, 'entregue', {
    delivered_at: `${deliverDate.value}T12:00:00`,
  });
};

const sendingWa = ref(false);
const sendWhatsapp = async order => {
  sendingWa.value = true;
  try {
    const { data: payload } = await CrmAPI.getOticaOrderWhatsapp(order.id);
    if (payload.link) window.open(payload.link, '_blank', 'noopener');
    else useAlert('A venda não tem celular do cliente para avisar.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui montar a mensagem.');
  } finally {
    sendingWa.value = false;
  }
};
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-7xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Produção e entregas"
        subtitle="O que está no laboratório, o que já está pronto e o que foi entregue. Atraso fica em vermelho. Retirou leva o cliente para o pós-venda."
        icon="i-lucide-package-check"
        :palette="false"
      >
        <template #chips>
          <span class="cv-glass-chip">
            <span class="i-lucide-factory text-xs" />
            {{ byColumn.em_producao.length }} em produção
          </span>
          <span class="cv-glass-chip">
            <span class="i-lucide-package-check text-xs" />
            {{ byColumn.pronta.length }} pronta(s)
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
            quantos óculos estão em cada etapa e quantos atrasaram
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

        <!-- bloco 2 · quadro -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-center gap-3 flex-wrap mb-4">
            <div>
              <h2 class="cv-ag-block-title">Quadro</h2>
              <span class="cv-ag-block-sub">
                em produção · pronta · entregue — cada cartão é uma venda
              </span>
            </div>
            <input
              v-model="search"
              type="text"
              class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 ml-auto"
              style="min-width: 12rem; margin-bottom: 0"
              placeholder="Cliente, celular ou nº"
            />
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
          </div>

          <div
            :class="
              view === 'cards'
                ? 'grid grid-cols-1 lg:grid-cols-3 gap-4'
                : 'flex flex-col gap-6'
            "
          >
            <div
              v-for="col in COLUMNS"
              :key="col.key"
              class="flex flex-col gap-2"
            >
              <div class="flex items-center gap-2 pb-2 border-b-2" :style="{ borderColor: col.color }">
                <span
                  class="w-7 h-7 rounded-lg grid place-items-center text-white flex-shrink-0"
                  :style="{ background: col.color }"
                >
                  <span :class="col.icon" class="text-xs" />
                </span>
                <div class="min-w-0">
                  <p class="text-[13px] font-extrabold text-n-slate-12">
                    {{ col.label }}
                    <span class="text-n-slate-10 font-semibold">
                      · {{ byColumn[col.key].filter(match).length }}
                    </span>
                  </p>
                  <p class="text-[10px] text-n-slate-9">{{ col.hint }}</p>
                </div>
              </div>

              <div
                v-if="!byColumn[col.key].filter(match).length"
                class="cv-sub p-5 text-center text-n-slate-10 text-xs"
              >
                Nada aqui.
              </div>

              <article
                v-for="o in byColumn[col.key].filter(match)"
                :key="o.id"
                class="cv-sub p-3.5 flex flex-col gap-2.5 border-l-4"
                :class="busyId === o.id ? 'opacity-50 pointer-events-none' : ''"
                :style="{
                  borderLeftColor:
                    o.status !== 'entregue' && orderLate(o) ? VERMELHO : col.color,
                }"
              >
                <header class="flex items-start gap-2">
                  <div class="min-w-0 flex-1">
                    <p class="text-[13px] font-bold text-n-slate-12">
                      Nº {{ o.number }} · {{ o.contact?.name || 'Sem nome' }}
                    </p>
                    <p class="text-[11px] text-n-slate-11">
                      {{ o.contact?.phone_number || 'sem celular' }}
                      <template v-if="o.seller?.name"> · {{ o.seller.name }}</template>
                    </p>
                  </div>
                  <span
                    v-if="o.status !== 'entregue' && orderLate(o)"
                    class="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full text-white whitespace-nowrap"
                    :style="{ background: VERMELHO }"
                  >
                    <span class="i-lucide-alarm-clock" /> atrasada
                  </span>
                </header>

                <p class="text-[12px] text-n-slate-11">{{ itemsLine(o) }}</p>

                <div class="flex items-center gap-x-3 gap-y-1 flex-wrap text-[11px]">
                  <span v-if="o.status !== 'entregue'" class="text-n-slate-11">
                    previsão
                    <b :style="{ color: orderLate(o) ? VERMELHO : 'inherit' }">
                      {{ fmtDate(o.due_on) }}
                    </b>
                  </span>
                  <span v-else class="text-n-slate-11">
                    retirou <b>{{ fmtDateTime(o.delivered_at) }}</b>
                  </span>
                  <span class="text-n-slate-11">
                    líquido <b :style="{ color: VERDE }">{{ fmtMoney(o.net) }}</b>
                  </span>
                  <span v-if="o.balance > 0.009" :style="{ color: AMBAR }">
                    falta {{ fmtMoney(o.balance) }}
                  </span>
                </div>

                <!-- laboratório -->
                <div
                  v-for="lab in o.lab_orders || []"
                  :key="lab.id"
                  class="rounded-xl bg-n-alpha-1 p-2.5 flex items-center gap-2 flex-wrap"
                >
                  <span
                    class="inline-flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full"
                    :style="{
                      background: `${(labLate(lab) ? VERMELHO : LAB_META[lab.status]?.color)}1A`,
                      color: labLate(lab) ? VERMELHO : LAB_META[lab.status]?.color,
                    }"
                  >
                    <span :class="LAB_META[lab.status]?.icon" />
                    {{ lab.status_label }}
                  </span>
                  <!-- celular: a descrição ocupa a linha inteira (não espreme em coluna) -->
                  <span
                    class="text-[11px] text-n-slate-11 min-w-0 flex-1 basis-full sm:basis-auto"
                  >
                    {{ lab.item_description }}
                    <template v-if="lab.supplier_name"> · {{ lab.supplier_name }}</template>
                    <template v-if="lab.expected_on && lab.status !== 'recebido'">
                      · previsto
                      <b :style="{ color: labLate(lab) ? VERMELHO : 'inherit' }">
                        {{ fmtDate(lab.expected_on) }}
                      </b>
                    </template>
                    <template v-if="lab.status === 'recebido'">
                      · chegou {{ fmtDate(lab.received_at) }}
                    </template>
                  </span>
                  <button
                    v-if="editable && !['recebido', 'cancelado'].includes(lab.status)"
                    class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white"
                    :style="{ background: VERDE }"
                    @click="labArrived(o, lab)"
                  >
                    Chegou do laboratório
                  </button>
                </div>

                <!-- ações -->
                <div v-if="editable" class="flex items-center gap-1.5 flex-wrap">
                  <button
                    v-if="o.status === 'em_producao'"
                    class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white"
                    :style="{ background: AMBAR }"
                    :title="openLabs(o).length ? 'Ainda tem pedido no laboratório em aberto' : ''"
                    @click="setStatus(o, 'pronta')"
                  >
                    Marcar pronta
                  </button>
                  <button
                    v-if="['em_producao', 'pronta'].includes(o.status)"
                    class="h-7 px-2.5 rounded-lg text-[10px] font-bold text-white"
                    :style="{ background: VERDE }"
                    @click="openDeliver(o)"
                  >
                    Retirou
                  </button>
                  <button
                    class="cv-btn cv-btn-ghost cv-btn-sm"
                    :disabled="sendingWa"
                    @click="sendWhatsapp(o)"
                  >
                    <span class="i-lucide-message-circle text-xs" />
                    {{ o.status === 'pronta' ? 'Avisar pelo WhatsApp' : 'WhatsApp' }}
                  </button>
                  <span
                    v-if="o.crm_card"
                    class="text-[10px] text-n-slate-9 ml-auto"
                    :title="o.crm_card.pipeline_name"
                  >
                    <span :class="STATUS_META[o.status]?.icon" class="text-[10px]" />
                    {{ o.crm_card.stage_name }}
                  </span>
                </div>
              </article>
            </div>
          </div>
        </section>
      </template>
    </div>

    <!-- modal · retirou -->
    <div
      v-if="deliverModal"
      class="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-3"
      style="background: rgba(15, 23, 42, 0.45)"
      @click.self="deliverModal = null"
    >
      <div class="ot-form w-full max-w-sm rounded-2xl bg-n-card border border-n-weak p-5 flex flex-col gap-4">
        <div class="flex items-start gap-3">
          <span
            class="w-9 h-9 rounded-xl grid place-items-center text-white flex-shrink-0"
            :style="{ background: VERDE }"
          >
            <span class="i-lucide-smile text-sm" />
          </span>
          <div class="min-w-0 flex-1">
            <h3 class="text-base font-extrabold text-n-slate-12">
              O cliente retirou
            </h3>
            <p class="text-[12px] text-n-slate-11">
              Nº {{ deliverModal.number }} · {{ deliverModal.contact?.name }}.
              O card vai para "Retirou o óculos" e a Jornada começa a contar.
            </p>
          </div>
        </div>
        <label class="block">
          <span :class="LABEL">Data da retirada</span>
          <input v-model="deliverDate" type="date" :class="INPUT" />
        </label>
        <div class="flex items-center gap-2 justify-end">
          <button class="cv-btn cv-btn-ghost" @click="deliverModal = null">
            Voltar
          </button>
          <button
            class="h-9 px-4 rounded-lg text-xs font-bold text-white"
            :style="{ background: VERDE }"
            @click="confirmDeliver"
          >
            Confirmar retirada
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ot-form input,
.ot-form select {
  margin-bottom: 0;
}
</style>
