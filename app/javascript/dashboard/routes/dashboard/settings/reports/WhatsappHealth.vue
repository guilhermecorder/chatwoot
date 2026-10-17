<script setup>
// 🚦 SAÚDE DO WHATSAPP (16/10/2026). A Meta NÃO informa quem bloqueou a
// clínica — esta tela junta o que dá para saber com precisão, em 4 blocos:
//   1. Seus números  → nota da Meta agora + quando mudou, limite de envios,
//                      entregues/lidas na semana, erros da Meta por dia
//   2. Modelos       → situação e nota de cada modelo, envios e entrega
//   3. Quem não quer mais receber → CERTO (pediu / Meta avisou) × SUSPEITA
//                      (bloqueio provável / frase), com o MOTIVO de cada um,
//                      e as chavinhas do que os robôs fazem com essas pessoas
//   4. O que veio antes do silêncio → por quem mandou e por modelo
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CrmAPI from 'dashboard/api/crm';

const route = useRoute();
const { canEdit } = useCevicoAccess();
const editable = computed(() => canEdit('relatorios.whatsapp_saude'));

const pal = useCevicoPalette({
  scope: 'report:whatsapp',
  blocks: [
    { id: 'numeros', label: 'Seus números', icon: 'i-lucide-smartphone' },
    { id: 'modelos', label: 'Modelos', icon: 'i-lucide-file-text' },
    { id: 'pessoas', label: 'Quem não quer receber', icon: 'i-lucide-user-x' },
    { id: 'silencio', label: 'Antes do silêncio', icon: 'i-lucide-route' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

const data = ref(null);
const isLoading = ref(true);
const isRefreshing = ref(false);
const lastRefresh = ref(null);

const load = async ({ quiet = false } = {}) => {
  if (quiet) isRefreshing.value = true;
  else isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getWhatsappHealth();
    data.value = payload;
    lastRefresh.value = new Date();
  } catch {
    useAlert('Não consegui carregar a saúde do WhatsApp.');
  } finally {
    isLoading.value = false;
    isRefreshing.value = false;
  }
};
onMounted(load);

// ── miúdos de formato ─────────────────────────────────────────────────────
const fmtNum = n => Number(n || 0).toLocaleString('pt-BR');
const fmtPct = n =>
  n === null || n === undefined ? '—' : `${String(n).replace('.', ',')}%`;
const fmtWhen = iso => {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
const conversationLink = id =>
  id ? `/app/accounts/${route.params.accountId}/conversations/${id}` : null;

// verde/amarelo/vermelho têm SIGNIFICADO (nota da Meta): chips semânticos do kit
const QUALITY = {
  GREEN: { label: 'Alta', cls: 'cv-green', dot: '#22C55E' },
  YELLOW: { label: 'Média', cls: 'cv-amber', dot: '#F59E0B' },
  RED: { label: 'Baixa', cls: 'cv-red', dot: '#EF4444' },
  UNKNOWN: { label: 'sem leitura', cls: 'cv-slate', dot: '#9CA3AF' },
};
const quality = q => QUALITY[(q || '').toUpperCase()] ?? QUALITY.UNKNOWN;
const TIERS = {
  TIER_50: '50 pessoas/24h',
  TIER_250: '250 pessoas/24h',
  TIER_1K: '1.000 pessoas/24h',
  TIER_2K: '2.000 pessoas/24h',
  TIER_10K: '10.000 pessoas/24h',
  TIER_100K: '100.000 pessoas/24h',
  TIER_UNLIMITED: 'Ilimitado',
};
const tier = t => TIERS[t] ?? t ?? '—';
const TEMPLATE_STATUS = {
  APPROVED: { label: 'Aprovado', cls: 'cv-green' },
  PAUSED: { label: 'Pausado pela Meta', cls: 'cv-red' },
  DISABLED: { label: 'Desativado', cls: 'cv-red' },
  REJECTED: { label: 'Recusado', cls: 'cv-red' },
  PENDING: { label: 'Em análise', cls: 'cv-amber' },
  IN_APPEAL: { label: 'Em recurso', cls: 'cv-amber' },
  LIMIT_EXCEEDED: { label: 'Limite excedido', cls: 'cv-amber' },
};
const tplStatus = s =>
  TEMPLATE_STATUS[s] ?? { label: s || '—', cls: 'cv-slate' };
const CATEGORY = {
  MARKETING: 'Marketing',
  UTILITY: 'Utilidade',
  AUTHENTICATION: 'Autenticação',
};

// ══ 1. SEUS NÚMEROS ══════════════════════════════════════════════════════
const numbers = computed(() => data.value?.numbers ?? []);
const legend = computed(() =>
  Object.fromEntries((data.value?.errors_legend ?? []).map(e => [e.code, e]))
);
const GRAVE = ['131048', '131049', '131050'];
const graveTotal = n =>
  GRAVE.reduce((sum, c) => sum + (n.errors?.totals?.[c] || 0), 0);
const errorList = n =>
  Object.entries(n.errors?.totals ?? {})
    .map(([code, count]) => ({
      code,
      count,
      label: legend.value[code]?.label ?? 'Outros erros',
      hint: legend.value[code]?.hint ?? '',
      grave: GRAVE.includes(code),
    }))
    .sort((a, b) => Number(b.grave) - Number(a.grave) || b.count - a.count);
const dayMax = n =>
  Math.max(
    1,
    ...(n.errors?.days ?? []).map(d =>
      Object.values(d.codes).reduce((s, v) => s + v, 0)
    )
  );
const dayBars = n =>
  (n.errors?.days ?? []).map(d => {
    const total = Object.values(d.codes).reduce((s, v) => s + v, 0);
    const grave = GRAVE.reduce((s, c) => s + (d.codes[c] || 0), 0);
    return { day: d.day, total, grave, codes: d.codes };
  });
const dayTitle = bar => {
  const parts = Object.entries(bar.codes).map(
    ([c, v]) => `${legend.value[c]?.label ?? c}: ${v}`
  );
  const [y, m, d] = bar.day.split('-');
  return `${d}/${m}/${y} — ${parts.length ? parts.join(' · ') : 'sem erros'}`;
};
const historyRows = n => [...(n.history ?? [])].reverse().slice(0, 6);
const showLegend = ref(false);

// ══ 2. MODELOS ═══════════════════════════════════════════════════════════
const tplInbox = ref('all');
const tplView = ref('list');
const tplOnlyProblems = ref(false);
const templateRows = computed(() =>
  (data.value?.templates ?? [])
    .filter(g => tplInbox.value === 'all' || g.inbox_id === tplInbox.value)
    .flatMap(g => g.list.map(t => ({ ...t, inbox: g.inbox })))
    .filter(
      t =>
        !tplOnlyProblems.value ||
        ['PAUSED', 'DISABLED', 'REJECTED'].includes(t.status) ||
        ['RED', 'YELLOW'].includes(t.quality)
    )
);
const templateProblems = computed(
  () =>
    (data.value?.templates ?? [])
      .flatMap(g => g.list)
      .filter(
        t =>
          ['PAUSED', 'DISABLED'].includes(t.status) ||
          ['RED', 'YELLOW'].includes(t.quality)
      ).length
);

// ══ 3. QUEM NÃO QUER MAIS RECEBER ════════════════════════════════════════
const signals = computed(() =>
  Object.fromEntries((data.value?.signals ?? []).map(s => [s.key, s]))
);
const counts = computed(() => data.value?.people?.counts ?? {});
const peopleTab = ref('certo');
const peopleKey = ref('all');
const peopleView = ref('list');
const peopleSearch = ref('');
const tabKeys = tab =>
  Object.values(signals.value)
    .filter(s => s.certeza === tab)
    .map(s => s.key);
const tabCount = tab =>
  tabKeys(tab).reduce((sum, k) => sum + (counts.value[k] || 0), 0);
const setTab = tab => {
  peopleTab.value = tab;
  peopleKey.value = 'all';
};
const peopleRows = computed(() => {
  const keys =
    peopleKey.value === 'all' ? tabKeys(peopleTab.value) : [peopleKey.value];
  const q = peopleSearch.value.trim().toLowerCase();
  return (data.value?.people?.list ?? []).filter(
    p =>
      keys.includes(p.key) &&
      (!q ||
        (p.name || '').toLowerCase().includes(q) ||
        (p.phone || '').includes(q))
  );
});
const sig = key => signals.value[key] ?? { titulo: key, color: '#64748b' };
const lastDelivered = p => p.evidence?.ultima_entregue;
const busyRow = ref(null);
const rowKey = p => `${p.contact_id}:${p.key}`;
const unmark = async p => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `Tirar a marcação "${sig(p.key).titulo}" de ${p.name || 'este paciente'}? A varredura não volta a marcar pelo mesmo sinal.`
    )
  )
    return;
  busyRow.value = rowKey(p);
  try {
    await CrmAPI.unmarkWhatsappSignal(p.contact_id, p.key);
    useAlert('Marcação tirada.');
    await load({ quiet: true });
  } catch {
    useAlert('Não consegui tirar a marcação.');
  } finally {
    busyRow.value = null;
  }
};
const confirmStop = async p => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `Confirmar que ${p.name || 'este paciente'} não quer mais receber? Vira "Pediu para parar" (nao_perturbe) e nenhum robô manda mais nada.`
    )
  )
    return;
  busyRow.value = rowKey(p);
  try {
    await CrmAPI.confirmWhatsappSignal(p.contact_id, p.key);
    useAlert('Confirmado: agora está em "Pediu para parar".');
    await load({ quiet: true });
  } catch {
    useAlert('Não consegui confirmar.');
  } finally {
    busyRow.value = null;
  }
};

// o que os robôs fazem (chavinhas)
const rules = computed(() => data.value?.rules ?? { robots: {} });
const savingRules = ref(false);
const ROBOT_KEYS = [
  'certo_sem_marketing',
  'suspeita_bloqueio',
  'suspeita_nao_quer',
];
const toggleRobot = async key => {
  if (!editable.value || savingRules.value) return;
  const next = !rules.value.robots[key];
  savingRules.value = true;
  try {
    const { data: res } = await CrmAPI.saveWhatsappHealthSettings({
      robos: { [key]: next },
    });
    data.value = {
      ...data.value,
      rules: { ...data.value.rules, robots: res.rules.robos },
    };
    useAlert(
      next
        ? 'Ligado: os robôs param para essas pessoas.'
        : 'Desligado: os robôs voltam a mandar.'
    );
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    savingRules.value = false;
  }
};
const scanForm = ref(null);
const editScan = () => {
  scanForm.value = { horas: rules.value.hours, presas: rules.value.stuck };
};
const saveScan = async () => {
  savingRules.value = true;
  try {
    const { data: res } = await CrmAPI.saveWhatsappHealthSettings(
      scanForm.value
    );
    data.value = {
      ...data.value,
      rules: {
        ...data.value.rules,
        hours: res.rules.horas,
        stuck: res.rules.presas,
      },
    };
    scanForm.value = null;
    useAlert('Regra salva — vale na próxima conferência.');
  } catch {
    useAlert('Não consegui salvar.');
  } finally {
    savingRules.value = false;
  }
};
const scanning = ref(false);
const scanNow = async () => {
  scanning.value = true;
  try {
    await CrmAPI.scanWhatsappHealth();
    useAlert('Conferindo agora — atualize a tela em 1 minuto.');
  } catch {
    useAlert('Não consegui pedir a conferência.');
  } finally {
    scanning.value = false;
  }
};

// ══ 4. O QUE VEIO ANTES DO SILÊNCIO ══════════════════════════════════════
const silenceView = ref('origin');
const silence = computed(() => data.value?.silence ?? {});
const silenceRows = computed(() =>
  silenceView.value === 'origin'
    ? (silence.value.by_origin ?? [])
    : (silence.value.by_template ?? [])
);
const silenceMax = computed(() =>
  Math.max(
    1,
    ...silenceRows.value.map(r => (r.blocked_pct || 0) + (r.stopped_pct || 0))
  )
);
const worst = computed(() =>
  silenceRows.value.find(r => r.enough && (r.blocked || r.stopped))
);
</script>

<template>
  <div
    class="cv-page flex flex-col h-full overflow-y-auto p-6 bg-n-surface-1"
    :style="cvVars"
  >
    <CevicoHero
      :pal="pal"
      title="Saúde do WhatsApp"
      subtitle="nota dos números e modelos · quem não quer mais receber · o que veio antes do silêncio"
      icon="i-lucide-activity"
    >
      <template #actions>
        <span v-if="lastRefresh" class="cevico-hero-chip">
          <span class="i-lucide-clock text-xs" />
          atualizado às
          {{
            lastRefresh.toLocaleTimeString('pt-BR', {
              hour: '2-digit',
              minute: '2-digit',
            })
          }}
        </span>
        <button
          class="cevico-hero-btn disabled:opacity-50"
          :disabled="isRefreshing || isLoading"
          @click="load({ quiet: true })"
        >
          <span
            class="i-lucide-refresh-cw text-xs"
            :class="isRefreshing ? 'animate-spin' : ''"
          />
          Atualizar
        </button>
      </template>
    </CevicoHero>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ 1. SEUS NÚMEROS ══ -->
      <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('numeros')">
        <div class="flex items-center gap-3 mb-1 flex-wrap">
          <span class="cv-icon cv-icon-lg"
            ><span class="i-lucide-smartphone text-lg"
          /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Seus números
          </h2>
          <span class="cv-chip">{{ numbers.length }} caixa(s)</span>
        </div>
        <p class="text-xs text-n-slate-10 mb-6 max-w-3xl">
          A nota é a Meta que dá, pelas denúncias e bloqueios dos pacientes.
          Amarela ou vermelha = mande menos marketing por esse número até voltar
          ao verde. A linha do tempo começa em 16/10 (antes disso a Meta só
          informava a nota do momento).
        </p>

        <div v-if="!numbers.length" class="cv-sub p-6 text-sm text-n-slate-10">
          Nenhuma caixa de WhatsApp conectada.
        </div>

        <div v-else class="grid gap-6 wh-grid-340">
          <article
            v-for="n in numbers"
            :key="n.id"
            class="cv-sub p-5 sm:p-6 flex flex-col gap-5"
            :class="n.quality === 'RED' ? 'ring-2 ring-red-500/50' : ''"
          >
            <header class="flex flex-wrap items-start justify-between gap-3">
              <div class="min-w-0">
                <p class="text-base font-bold text-n-slate-12">{{ n.name }}</p>
                <p class="text-xs text-n-slate-10">{{ n.phone || '—' }}</p>
              </div>
              <span
                class="cv-chip flex-shrink-0"
                :class="quality(n.quality).cls"
              >
                <span
                  class="w-2 h-2 rounded-full"
                  :style="{ backgroundColor: quality(n.quality).dot }"
                />
                Nota {{ quality(n.quality).label }}
              </span>
            </header>

            <div class="grid gap-3 wh-grid-140">
              <DashKpi
                compact
                glass
                label="Entregues (7 dias)"
                :value="fmtPct(n.week.delivered_pct)"
                :sub="`${fmtNum(n.week.total)} enviadas`"
                :grad="blockFamily('numeros')[0]"
              />
              <DashKpi
                compact
                glass
                label="Lidas (7 dias)"
                :value="fmtPct(n.week.read_pct)"
                :sub="`${fmtNum(n.week.read)} lidas`"
                :grad="blockFamily('numeros')[1]"
              />
              <DashKpi
                compact
                glass
                label="Só “enviado” há +48h"
                :value="fmtNum(n.stuck_48h)"
                sub="nunca chegaram no celular"
                :grad="blockFamily('numeros')[2]"
              />
              <DashKpi
                compact
                glass
                label="Avisos graves (14 dias)"
                :value="fmtNum(graveTotal(n))"
                sub="spam · marketing segurado · parou"
                :grad="
                  graveTotal(n)
                    ? 'linear-gradient(135deg,#DC2626,#F97316)'
                    : blockFamily('numeros')[3]
                "
              />
            </div>

            <div class="space-y-1.5 text-xs">
              <div
                class="cv-row flex items-center justify-between gap-2 px-3 py-2"
              >
                <span class="text-n-slate-10">Limite de envios</span>
                <span class="text-n-slate-12 font-semibold">{{
                  tier(n.limit_tier)
                }}</span>
              </div>
              <div
                v-if="n.status"
                class="cv-row flex items-center justify-between gap-2 px-3 py-2"
              >
                <span class="text-n-slate-10">Situação do número</span>
                <span
                  class="font-semibold"
                  :class="
                    n.status === 'CONNECTED'
                      ? 'text-green-600'
                      : 'text-amber-600'
                  "
                >
                  {{ n.status === 'CONNECTED' ? 'Conectado' : n.status }}
                </span>
              </div>
            </div>

            <div>
              <p class="cv-label mb-2">Erros da Meta por dia (14 dias)</p>
              <div class="flex items-end gap-1 h-14">
                <div
                  v-for="bar in dayBars(n)"
                  :key="bar.day"
                  class="flex-1 flex flex-col justify-end h-full"
                  :title="dayTitle(bar)"
                >
                  <div
                    v-if="bar.total"
                    class="rounded-t w-full overflow-hidden flex flex-col justify-end wh-tint-35"
                    :style="{
                      height: `${Math.max(8, (bar.total / dayMax(n)) * 100)}%`,
                    }"
                  >
                    <div
                      v-if="bar.grave"
                      class="w-full bg-red-500"
                      :style="{ height: `${(bar.grave / bar.total) * 100}%` }"
                    />
                  </div>
                  <div v-else class="h-[3px] rounded w-full wh-tint-15" />
                </div>
              </div>
              <p class="text-[11px] text-n-slate-9 mt-1.5">
                <span
                  class="inline-block w-2 h-2 rounded-sm bg-red-500 align-middle mr-1"
                />graves
                <span
                  class="inline-block w-2 h-2 rounded-sm align-middle ml-3 mr-1 wh-tint-35"
                />outros
              </p>
              <ul v-if="errorList(n).length" class="mt-3 space-y-1">
                <li
                  v-for="e in errorList(n)"
                  :key="e.code"
                  class="flex items-baseline gap-2 text-xs"
                >
                  <span
                    class="font-bold tabular-nums whitespace-nowrap"
                    :class="e.grave ? 'text-red-600' : 'text-n-slate-12'"
                    >{{ fmtNum(e.count) }}</span
                  >
                  <span class="text-n-slate-11" :title="e.hint">{{
                    e.label
                  }}</span>
                  <span class="text-n-slate-9 text-[10px]">{{ e.code }}</span>
                </li>
              </ul>
              <p v-else class="text-xs text-n-slate-9 mt-3">
                nenhum erro da Meta nos últimos 14 dias
              </p>
            </div>

            <div>
              <p class="cv-label mb-2">Quando a nota mudou</p>
              <ul v-if="historyRows(n).length" class="space-y-1">
                <li
                  v-for="h in historyRows(n)"
                  :key="h.em"
                  class="flex items-center gap-2 text-xs"
                >
                  <span
                    class="w-2 h-2 rounded-full"
                    :style="{ backgroundColor: quality(h.q).dot }"
                  />
                  <span class="text-n-slate-12 font-semibold">{{
                    quality(h.q).label
                  }}</span>
                  <span class="text-n-slate-10">· {{ tier(h.tier) }}</span>
                  <span class="text-n-slate-9 ml-auto whitespace-nowrap">{{
                    fmtWhen(h.em)
                  }}</span>
                </li>
              </ul>
              <p v-else class="text-xs text-n-slate-9">
                primeira leitura na próxima hora cheia
              </p>
            </div>
          </article>
        </div>

        <button
          class="cv-btn cv-btn-sm cv-btn-ghost mt-6"
          @click="showLegend = !showLegend"
        >
          <span class="i-lucide-info text-xs" />
          {{ showLegend ? 'Esconder' : 'O que quer dizer cada erro da Meta' }}
        </button>
        <div v-if="showLegend" class="cv-sub p-5 mt-3 grid gap-3 wh-grid-280">
          <div v-for="e in data.errors_legend" :key="e.code" class="text-xs">
            <p
              class="font-bold"
              :class="e.grave ? 'text-red-600' : 'text-n-slate-12'"
            >
              {{ e.label }}
              <span class="text-n-slate-9 font-normal">· {{ e.code }}</span>
            </p>
            <p class="text-n-slate-10">{{ e.hint }}</p>
          </div>
        </div>
      </section>

      <!-- ══ 2. MODELOS ══ -->
      <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('modelos')">
        <div class="flex items-center gap-3 mb-1 flex-wrap">
          <span class="cv-icon cv-icon-lg"
            ><span class="i-lucide-file-text text-lg"
          /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Modelos
          </h2>
          <span v-if="templateProblems" class="cv-chip cv-red">
            {{ templateProblems }} com problema
          </span>
        </div>
        <p class="text-xs text-n-slate-10 mb-6 max-w-3xl">
          Cada modelo tem a própria nota. Modelo amarelo ou vermelho é o que
          mais gente bloqueia ou denuncia — a Meta pausa sozinha quando piora.
          Envios e entrega dos últimos 14 dias.
        </p>

        <div class="flex items-center gap-3 flex-wrap mb-5">
          <span class="cv-seg cv-seg-sm">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tplInbox === 'all' }"
              @click="tplInbox = 'all'"
            >
              Todas
            </button>
            <button
              v-for="n in numbers"
              :key="n.id"
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tplInbox === n.id }"
              @click="tplInbox = n.id"
            >
              {{ n.name }}
            </button>
          </span>
          <label
            class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer"
          >
            <button
              class="cv-switch"
              :class="tplOnlyProblems ? 'cv-switch-on' : ''"
              role="switch"
              :aria-checked="tplOnlyProblems"
              @click.prevent="tplOnlyProblems = !tplOnlyProblems"
            />
            só os com problema
          </label>
          <span class="cv-seg cv-seg-sm ml-auto">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tplView === 'list' }"
              @click="tplView = 'list'"
            >
              <span class="i-lucide-list cv-seg-icon" />Lista
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tplView === 'cards' }"
              @click="tplView = 'cards'"
            >
              <span class="i-lucide-layout-grid cv-seg-icon" />Cards
            </button>
          </span>
        </div>

        <p
          v-if="!templateRows.length"
          class="cv-sub p-5 text-xs text-n-slate-10"
        >
          nenhum modelo para mostrar
        </p>

        <div v-else-if="tplView === 'list'" class="cv-sub overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr
                class="text-left text-[10px] uppercase tracking-wide text-n-slate-9"
              >
                <th class="px-4 py-3">Modelo</th>
                <th class="px-3 py-3">Caixa</th>
                <th class="px-3 py-3">Tipo</th>
                <th class="px-3 py-3">Situação</th>
                <th class="px-3 py-3">Nota</th>
                <th class="px-3 py-3 text-right">Envios</th>
                <th class="px-3 py-3 text-right">Entregues</th>
                <th class="px-4 py-3 text-right">Lidas</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="t in templateRows"
                :key="`${t.inbox}-${t.name}-${t.language}`"
                class="border-t border-n-weak"
              >
                <td class="px-4 py-2.5 font-semibold text-n-slate-12">
                  {{ t.name }}
                  <span class="text-n-slate-9 font-normal">{{
                    t.language
                  }}</span>
                </td>
                <td class="px-3 py-2.5 text-n-slate-11">{{ t.inbox }}</td>
                <td class="px-3 py-2.5 text-n-slate-11">
                  {{ CATEGORY[t.category] ?? t.category ?? '—' }}
                </td>
                <td class="px-3 py-2.5">
                  <span class="cv-chip" :class="tplStatus(t.status).cls">{{
                    tplStatus(t.status).label
                  }}</span>
                </td>
                <td class="px-3 py-2.5">
                  <span class="inline-flex items-center gap-1.5">
                    <span
                      class="w-2 h-2 rounded-full"
                      :style="{ backgroundColor: quality(t.quality).dot }"
                    />{{ quality(t.quality).label }}
                  </span>
                </td>
                <td class="px-3 py-2.5 text-right tabular-nums">
                  {{ fmtNum(t.sends.total) }}
                </td>
                <td class="px-3 py-2.5 text-right tabular-nums">
                  {{ fmtPct(t.sends.delivered_pct) }}
                </td>
                <td class="px-4 py-2.5 text-right tabular-nums">
                  {{ fmtPct(t.sends.read_pct) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-else class="grid gap-4 wh-grid-260">
          <div
            v-for="t in templateRows"
            :key="`${t.inbox}-${t.name}-${t.language}`"
            class="cv-sub p-5 flex flex-col gap-3"
          >
            <div class="flex items-start justify-between gap-2">
              <p class="text-sm font-bold text-n-slate-12 break-all">
                {{ t.name }}
              </p>
              <span
                class="w-2.5 h-2.5 rounded-full mt-1 flex-shrink-0"
                :style="{ backgroundColor: quality(t.quality).dot }"
                :title="`Nota ${quality(t.quality).label}`"
              />
            </div>
            <p class="text-[11px] text-n-slate-10">
              {{ t.inbox }} · {{ CATEGORY[t.category] ?? t.category ?? '—' }} ·
              {{ t.language }}
            </p>
            <span class="cv-chip self-start" :class="tplStatus(t.status).cls">{{
              tplStatus(t.status).label
            }}</span>
            <p class="text-xs text-n-slate-11">
              <b class="text-n-slate-12">{{ fmtNum(t.sends.total) }}</b> envios
              ·
              <b class="text-n-slate-12">{{ fmtPct(t.sends.delivered_pct) }}</b>
              entregues ·
              <b class="text-n-slate-12">{{ fmtPct(t.sends.read_pct) }}</b>
              lidas
            </p>
          </div>
        </div>
      </section>

      <!-- ══ 3. QUEM NÃO QUER MAIS RECEBER ══ -->
      <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('pessoas')">
        <div class="flex items-center gap-3 mb-1 flex-wrap">
          <span class="cv-icon cv-icon-lg"
            ><span class="i-lucide-user-x text-lg"
          /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Quem não quer mais receber
          </h2>
        </div>
        <p class="text-xs text-n-slate-10 mb-6 max-w-3xl">
          A Meta <b>não informa quem bloqueou</b>. Separamos o que é
          <b>CERTO</b> (a pessoa escreveu pedindo, ou a Meta avisou que ela
          desligou o marketing) do que é <b>SUSPEITA</b> (sinal indireto —
          celular desligado dá o mesmo sinal). Cada pessoa mostra por que foi
          marcada.
        </p>

        <div class="flex items-center gap-3 flex-wrap mb-4">
          <span class="cv-seg">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': peopleTab === 'certo' }"
              @click="setTab('certo')"
            >
              <span class="i-lucide-badge-check cv-seg-icon" />Certo ·
              {{ fmtNum(tabCount('certo')) }}
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': peopleTab === 'suspeita' }"
              @click="setTab('suspeita')"
            >
              <span class="i-lucide-shield-question cv-seg-icon" />Suspeita ·
              {{ fmtNum(tabCount('suspeita')) }}
            </button>
          </span>
          <input
            v-model="peopleSearch"
            class="cv-input text-xs px-3 py-1.5 w-48"
            placeholder="buscar nome ou telefone"
          />
          <span class="cv-seg cv-seg-sm ml-auto">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': peopleView === 'list' }"
              @click="peopleView = 'list'"
            >
              <span class="i-lucide-list cv-seg-icon" />Lista
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': peopleView === 'cards' }"
              @click="peopleView = 'cards'"
            >
              <span class="i-lucide-layout-grid cv-seg-icon" />Cards
            </button>
          </span>
        </div>

        <div class="flex items-center gap-2 flex-wrap mb-5">
          <button
            class="cv-tag cv-tag-md cv-tag-btn"
            :class="peopleKey === 'all' ? 'cv-tag-solid' : ''"
            @click="peopleKey = 'all'"
          >
            todas
          </button>
          <button
            v-for="k in tabKeys(peopleTab)"
            :key="k"
            class="cv-tag cv-tag-md cv-tag-btn"
            :class="peopleKey === k ? 'cv-tag-solid' : ''"
            :style="{ '--lb': sig(k).color }"
            :title="sig(k).description"
            @click="peopleKey = k"
          >
            <span class="cv-tag-dot" />{{ sig(k).titulo }} ·
            {{ fmtNum(counts[k]) }}
            <span class="opacity-60 font-normal">({{ k }})</span>
          </button>
        </div>
        <p
          v-if="peopleKey !== 'all'"
          class="text-[11px] text-n-slate-10 mb-4 max-w-3xl"
        >
          {{ sig(peopleKey).description }}
        </p>

        <p v-if="!peopleRows.length" class="cv-sub p-5 text-xs text-n-slate-10">
          ninguém aqui por enquanto{{
            peopleTab === 'suspeita'
              ? ' — a conferência roda de hora em hora'
              : ''
          }}
        </p>

        <div v-else-if="peopleView === 'list'" class="cv-sub overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr
                class="text-left text-[10px] uppercase tracking-wide text-n-slate-9"
              >
                <th class="px-4 py-3">Paciente</th>
                <th class="px-3 py-3">Marcação</th>
                <th class="px-3 py-3">Por quê</th>
                <th class="px-3 py-3">Última nossa que chegou</th>
                <th class="px-3 py-3">Desde</th>
                <th class="px-4 py-3" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="p in peopleRows"
                :key="rowKey(p)"
                class="border-t border-n-weak align-top"
              >
                <td class="px-4 py-3">
                  <p class="font-semibold text-n-slate-12">
                    {{ p.name || 'Sem nome' }}
                  </p>
                  <p class="text-n-slate-9">{{ p.phone }}</p>
                </td>
                <td class="px-3 py-3">
                  <span
                    class="cv-tag"
                    :style="{ '--lb': sig(p.key).color }"
                    :title="sig(p.key).description"
                    ><span class="cv-tag-dot" />{{ sig(p.key).titulo }}</span
                  >
                  <p
                    class="text-[10px] text-n-slate-9 mt-1 uppercase tracking-wide"
                  >
                    {{ p.certeza }}
                  </p>
                  <span v-if="p.review" class="cv-chip cv-amber mt-1">
                    revisar
                  </span>
                </td>
                <td class="px-3 py-3 text-n-slate-11 min-w-[200px] max-w-sm">
                  {{ p.reason }}
                </td>
                <td class="px-3 py-3 text-n-slate-11 min-w-[200px] max-w-sm">
                  <template v-if="lastDelivered(p)">
                    <p class="font-semibold text-n-slate-12">
                      {{ lastDelivered(p).origem_label }}
                    </p>
                    <p>
                      {{ fmtWhen(lastDelivered(p).em) }} ·
                      {{ lastDelivered(p).caixa
                      }}<template v-if="lastDelivered(p).modelo">
                        · modelo {{ lastDelivered(p).modelo }}
                      </template>
                    </p>
                    <p class="text-n-slate-9 italic">
                      “{{ lastDelivered(p).texto }}”
                    </p>
                  </template>
                  <span v-else class="text-n-slate-9">—</span>
                </td>
                <td class="px-3 py-3 text-n-slate-11 whitespace-nowrap">
                  {{ fmtWhen(p.since || p.at) }}
                </td>
                <td class="px-4 py-3">
                  <div class="flex flex-col gap-1.5 items-end">
                    <a
                      v-if="conversationLink(p.conversation_id)"
                      :href="conversationLink(p.conversation_id)"
                      class="cv-btn cv-btn-sm cv-btn-ghost whitespace-nowrap"
                    >
                      <span class="i-lucide-message-circle text-xs" />conversa
                    </a>
                    <button
                      v-if="editable && p.certeza === 'suspeita'"
                      class="cv-btn cv-btn-sm whitespace-nowrap"
                      :disabled="busyRow === rowKey(p)"
                      @click="confirmStop(p)"
                    >
                      <span class="i-lucide-hand text-xs" />é pedido de parar
                    </button>
                    <button
                      v-if="editable"
                      class="cv-btn cv-btn-sm cv-btn-ghost whitespace-nowrap"
                      :disabled="busyRow === rowKey(p)"
                      @click="unmark(p)"
                    >
                      <span class="i-lucide-x text-xs" />não é isso
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-else class="grid gap-4 wh-grid-300">
          <article
            v-for="p in peopleRows"
            :key="rowKey(p)"
            class="cv-sub p-5 flex flex-col gap-3"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="text-sm font-bold text-n-slate-12">
                  {{ p.name || 'Sem nome' }}
                </p>
                <p class="text-[11px] text-n-slate-9">{{ p.phone }}</p>
              </div>
              <span
                class="cv-tag flex-shrink-0"
                :style="{ '--lb': sig(p.key).color }"
                :title="sig(p.key).description"
                ><span class="cv-tag-dot" />{{ sig(p.key).titulo }}</span
              >
            </div>
            <div class="text-xs">
              <p class="cv-label mb-1">Por quê · {{ p.certeza }}</p>
              <p class="text-n-slate-11">{{ p.reason }}</p>
              <span v-if="p.review" class="cv-chip cv-amber mt-2">revisar</span>
            </div>
            <div v-if="lastDelivered(p)" class="text-xs">
              <p class="cv-label mb-1">Última nossa que chegou</p>
              <p class="text-n-slate-12 font-semibold">
                {{ lastDelivered(p).origem_label }}
              </p>
              <p class="text-n-slate-10">
                {{ fmtWhen(lastDelivered(p).em) }} ·
                {{ lastDelivered(p).caixa }}
              </p>
              <p class="text-n-slate-9 italic">
                “{{ lastDelivered(p).texto }}”
              </p>
            </div>
            <div class="flex items-center gap-2 flex-wrap mt-auto">
              <a
                v-if="conversationLink(p.conversation_id)"
                :href="conversationLink(p.conversation_id)"
                class="cv-btn cv-btn-sm cv-btn-ghost"
              >
                <span class="i-lucide-message-circle text-xs" />conversa
              </a>
              <button
                v-if="editable && p.certeza === 'suspeita'"
                class="cv-btn cv-btn-sm"
                :disabled="busyRow === rowKey(p)"
                @click="confirmStop(p)"
              >
                é pedido de parar
              </button>
              <button
                v-if="editable"
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="busyRow === rowKey(p)"
                @click="unmark(p)"
              >
                não é isso
              </button>
            </div>
          </article>
        </div>

        <!-- o que os robôs fazem com essas pessoas -->
        <div class="cv-sub p-5 sm:p-6 mt-8">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon cv-icon-sm"
              ><span class="i-lucide-bot text-xs"
            /></span>
            <h3 class="text-base font-bold text-n-slate-12">
              O que os robôs fazem com essas pessoas
            </h3>
            <button
              v-if="editable"
              class="cv-btn cv-btn-sm cv-btn-ghost ml-auto"
              :disabled="scanning"
              @click="scanNow"
            >
              <span class="i-lucide-scan-search text-xs" />{{
                scanning ? 'pedindo…' : 'Conferir agora'
              }}
            </button>
          </div>
          <p class="text-[11px] text-n-slate-10 mb-5 max-w-3xl">
            Ligado = a pessoa sai do follow-up, das campanhas, da jornada, da
            pesquisa de satisfação, da Colheitadeira e do agente de ligação.
            <b>Confirmação e lembrete da consulta continuam sempre.</b>
          </p>
          <div class="grid gap-3 wh-grid-260">
            <div class="cv-row px-4 py-3 flex items-start gap-3">
              <button
                class="cv-switch cv-switch-on opacity-60 cursor-not-allowed"
                role="switch"
                aria-checked="true"
                disabled
              />
              <div class="text-xs">
                <p class="font-semibold text-n-slate-12">
                  Pediu para parar
                  <span class="text-n-slate-9 font-normal">· certo</span>
                </p>
                <p class="text-n-slate-10">sempre param (regra de 20/09)</p>
              </div>
            </div>
            <div
              v-for="k in ROBOT_KEYS"
              :key="k"
              class="cv-row px-4 py-3 flex items-start gap-3"
            >
              <button
                class="cv-switch"
                :class="rules.robots[k] ? 'cv-switch-on' : ''"
                role="switch"
                :aria-checked="!!rules.robots[k]"
                :disabled="!editable || savingRules"
                @click.prevent="toggleRobot(k)"
              />
              <div class="text-xs">
                <p class="font-semibold text-n-slate-12">
                  {{ sig(k).titulo }}
                  <span class="text-n-slate-9 font-normal"
                    >· {{ sig(k).certeza }}</span
                  >
                </p>
                <p class="text-n-slate-10">
                  {{
                    rules.robots[k]
                      ? 'os robôs param'
                      : 'os robôs continuam mandando'
                  }}
                </p>
              </div>
            </div>
          </div>
          <div
            class="mt-5 text-xs text-n-slate-11 flex items-center gap-2 flex-wrap"
          >
            <span>Regra da suspeita de bloqueio:</span>
            <template v-if="!scanForm">
              <b class="text-n-slate-12"
                >{{ rules.stuck }} mensagens seguidas só em “enviado” há mais de
                {{ rules.hours }}h</b
              >
              <span
                >, de quem já recebia antes, sem ter escrito depois, com o
                número entregando para os outros.</span
              >
              <button v-if="editable" class="underline" @click="editScan">
                mudar
              </button>
            </template>
            <template v-else>
              <input
                v-model.number="scanForm.presas"
                type="number"
                :min="rules.limits.stuck[0]"
                :max="rules.limits.stuck[1]"
                class="cv-input w-16 px-2 py-1"
              />
              mensagens há mais de
              <input
                v-model.number="scanForm.horas"
                type="number"
                :min="rules.limits.hours[0]"
                :max="rules.limits.hours[1]"
                class="cv-input w-20 px-2 py-1"
              />
              horas
              <button
                class="cv-btn cv-btn-sm"
                :disabled="savingRules"
                @click="saveScan"
              >
                salvar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                @click="scanForm = null"
              >
                cancelar
              </button>
            </template>
          </div>
        </div>
      </section>

      <!-- ══ 4. O QUE VEIO ANTES DO SILÊNCIO ══ -->
      <section class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('silencio')">
        <div class="flex items-center gap-3 mb-1 flex-wrap">
          <span class="cv-icon cv-icon-lg"
            ><span class="i-lucide-route text-lg"
          /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            O que veio antes do silêncio
          </h2>
          <span class="cv-seg cv-seg-sm ml-auto">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': silenceView === 'origin' }"
              @click="silenceView = 'origin'"
            >
              <span class="i-lucide-bot cv-seg-icon" />Por quem mandou
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': silenceView === 'template' }"
              @click="silenceView = 'template'"
            >
              <span class="i-lucide-file-text cv-seg-icon" />Por modelo
            </button>
          </span>
        </div>
        <p class="text-xs text-n-slate-10 mb-6 max-w-3xl">
          Para cada pessoa, olhamos a última mensagem nossa que CHEGOU antes de
          ela sumir ou pedir para parar (últimos
          {{ silence.window_days }} dias). Lembre: robô de follow-up vai para
          quem já está esfriando — parte desse silêncio é natural.
        </p>

        <div
          v-if="worst"
          class="cv-strip px-5 py-4 mb-5 text-sm text-n-slate-12"
        >
          De cada 100 pessoas que receberam por último <b>{{ worst.label }}</b
          >, <b>{{ fmtPct(worst.blocked_pct) }}</b> ficaram em silêncio
          (suspeita de bloqueio) e
          <b>{{ fmtPct(worst.stopped_pct) }}</b> pediram para parar.
        </div>

        <p
          v-if="!silenceRows.length"
          class="cv-sub p-5 text-xs text-n-slate-10"
        >
          ainda sem dados
        </p>
        <div v-else class="cv-sub overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr
                class="text-left text-[10px] uppercase tracking-wide text-n-slate-9"
              >
                <th class="px-4 py-3">
                  {{ silenceView === 'origin' ? 'Quem mandou' : 'Modelo' }}
                </th>
                <th class="px-3 py-3 text-right">Receberam</th>
                <th class="px-3 py-3 text-right">Suspeita de bloqueio</th>
                <th class="px-3 py-3 text-right">Pediram para parar</th>
                <th class="px-4 py-3 w-1/3" />
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="r in silenceRows"
                :key="r.key"
                class="border-t border-n-weak"
                :class="r.enough ? '' : 'opacity-50'"
              >
                <td class="px-4 py-2.5 font-semibold text-n-slate-12">
                  {{ r.label }}
                  <span v-if="!r.enough" class="text-n-slate-9 font-normal">
                    · poucos dados
                  </span>
                </td>
                <td class="px-3 py-2.5 text-right tabular-nums">
                  {{ fmtNum(r.received) }}
                </td>
                <td
                  class="px-3 py-2.5 text-right tabular-nums whitespace-nowrap"
                >
                  {{ fmtNum(r.blocked) }}
                  <span class="text-n-slate-9"
                    >({{ fmtPct(r.blocked_pct) }})</span
                  >
                </td>
                <td
                  class="px-3 py-2.5 text-right tabular-nums whitespace-nowrap"
                >
                  {{ fmtNum(r.stopped) }}
                  <span class="text-n-slate-9"
                    >({{ fmtPct(r.stopped_pct) }})</span
                  >
                </td>
                <td class="px-4 py-2.5">
                  <div class="cv-track cv-track-sm flex">
                    <div
                      class="h-full wh-amber"
                      :style="{
                        width: `${((r.blocked_pct || 0) / silenceMax) * 100}%`,
                      }"
                    />
                    <div
                      class="h-full wh-red"
                      :style="{
                        width: `${((r.stopped_pct || 0) / silenceMax) * 100}%`,
                      }"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p class="text-[11px] text-n-slate-9 mt-3">
          <span
            class="inline-block w-2 h-2 rounded-sm align-middle mr-1 wh-amber"
          />suspeita de bloqueio
          <span
            class="inline-block w-2 h-2 rounded-sm align-middle ml-3 mr-1 wh-red"
          />pediram para parar (certo + frase) · a contagem começa em 16/10
          (marcações antigas não guardaram o que veio antes)
        </p>
      </section>
    </template>
  </div>
</template>

<style scoped>
.wh-grid-140 { grid-template-columns: repeat(auto-fit, minmax(min(100%, 140px), 1fr)); }
.wh-grid-260 {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr));
}
.wh-grid-280 {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr));
}
.wh-grid-300 {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 300px), 1fr));
}
.wh-grid-340 {
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 340px), 1fr));
}
.wh-tint-15 {
  background: rgb(var(--cv-rgb) / 0.15);
}
.wh-tint-35 {
  background: rgb(var(--cv-rgb) / 0.35);
}
.wh-amber {
  background: #d97706;
}
.wh-red {
  background: #dc2626;
}
</style>
