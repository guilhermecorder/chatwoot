<script setup>
// 🗺️ MAPA DE FLUXOS (item 170): um fluxograma por agente/automação, gerado
// no servidor a partir do código real (Crm::FlowMap) e desenhado com Mermaid.
// Esquerda = lista agrupada (ligado/desligado, última execução, contadores);
// direita = cabeçalho + diagrama + rodapé. ?flow=<chave> na URL seleciona.
// O estado do fluxo aberto atualiza sozinho a cada 60 s (GET crm/flows/:key).
import {
  ref,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  defineAsyncComponent,
} from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoPalettePicker from 'dashboard/components-next/cevico/CevicoPalettePicker.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';

// o diagrama traz o Mermaid junto — só entra quando esta aba abre
const FlowDiagram = defineAsyncComponent(
  () => import('dashboard/components-next/cevico/FlowDiagram.vue')
);

const store = useStore();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();

const flows = ref([]);
const groups = ref([]);
const selectedKey = ref('');
const isLoading = ref(true);
const isRefreshing = ref(false);
const listOpen = ref(false); // celular: a lista fica recolhida em cima do diagrama

// 🍎 paleta desta tela (o admin escolhe pelo chip de paleta)
const pal = useCevicoPalette({
  scope: 'report:fluxos',
  blocks: [
    { id: 'lista', label: 'Fluxos', icon: 'i-lucide-list' },
    { id: 'mapa', label: 'Fluxograma', icon: 'i-lucide-git-branch' },
  ],
});
const { cvVars, blockVars, openPalettePicker } = pal;

const TRIGGER_ICON = {
  cron: 'i-lucide-clock',
  event: 'i-lucide-zap',
  webhook: 'i-lucide-webhook',
  manual: 'i-lucide-mouse-pointer-click',
};
const TRIGGER_LABEL = {
  cron: 'agendado',
  event: 'por evento',
  webhook: 'webhook',
  manual: 'manual',
};
// legenda das formas/cores (mesmas classes do Flow#to_mermaid)
const LEGEND = [
  { label: 'gatilho', color: '#2563EB' },
  { label: 'decisão', color: '#D97706' },
  { label: 'ação', color: '#64748B' },
  { label: 'IA', color: '#7C3AED' },
  { label: 'repetição', color: '#0284C7' },
  { label: 'saída', color: '#16A34A' },
  { label: 'externo', color: '#DB2777' },
  { label: 'fim', color: '#475569' },
];

const selected = computed(
  () => flows.value.find(f => f.key === selectedKey.value) || null
);
const grouped = computed(() =>
  groups.value
    .map(title => ({
      title,
      flows: flows.value.filter(f => f.group === title),
    }))
    .filter(g => g.flows.length)
);
const onCount = computed(
  () => flows.value.filter(f => f.live?.enabled === true).length
);

// "há 2h", "há 3d" — atividade recente sem precisar ler data
const ago = iso => {
  if (!iso) return 'sem registro';
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return 'agora mesmo';
  if (mins < 60) return `há ${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `há ${hours}h`;
  return `há ${Math.floor(hours / 24)}d`;
};
const triggerTitle = computed(
  () => `Gatilho (${TRIGGER_LABEL[selected.value?.trigger?.kind] || 'manual'}):`
);
const lastRunText = computed(
  () => `· última execução ${ago(selected.value?.live?.last_run_at)}`
);
const fmtCounter = v =>
  typeof v === 'number' ? v.toLocaleString('pt-BR') : String(v ?? '—');
const counterList = flow =>
  Object.entries(flow?.live?.counters || {}).map(([label, value]) => ({
    label,
    value: fmtCounter(value),
  }));

// estado em 3 cores: ligado / desligado / externo (sem interruptor nosso)
const stateOf = flow => {
  const enabled = flow?.live?.enabled;
  if (enabled === true)
    return {
      label: 'ligado',
      bg: 'rgba(5,150,105,0.12)',
      fg: '#059669',
      dot: '#059669',
    };
  if (enabled === false)
    return {
      label: 'desligado',
      bg: 'rgba(100,116,139,0.14)',
      fg: '#64748B',
      dot: '#94A3B8',
    };
  return {
    label: 'externo',
    bg: 'rgba(219,39,119,0.12)',
    fg: '#DB2777',
    dot: '#DB2777',
  };
};

const pickInitial = () => {
  const wanted = route.query.flow;
  if (wanted && flows.value.some(f => f.key === wanted)) {
    selectedKey.value = wanted;
    return;
  }
  if (!flows.value.some(f => f.key === selectedKey.value)) {
    selectedKey.value = flows.value[0]?.key || '';
  }
};

const load = async () => {
  isLoading.value = true;
  try {
    const data = await store.dispatch('crm/fetchFlows');
    flows.value = data.flows || [];
    groups.value = data.groups || [];
    pickInitial();
  } catch {
    useAlert('Não consegui carregar o mapa de fluxos.');
  } finally {
    isLoading.value = false;
  }
};

// só o fluxo aberto: leve o bastante para rodar a cada 60 s
const refreshSelected = async () => {
  if (!selectedKey.value || isRefreshing.value) return;
  isRefreshing.value = true;
  try {
    const data = await store.dispatch('crm/fetchFlow', selectedKey.value);
    const idx = flows.value.findIndex(f => f.key === data.key);
    if (idx >= 0) flows.value.splice(idx, 1, data);
  } catch {
    // silencioso: a próxima rodada tenta de novo
  } finally {
    isRefreshing.value = false;
  }
};

const select = key => {
  selectedKey.value = key;
  listOpen.value = false;
  if (route.query.flow !== key) {
    router.replace({ query: { ...route.query, tab: 'fluxos', flow: key } });
  }
};
// deep link (?flow=) trocado por fora — ex.: botão "Ver fluxo" no card do agente
watch(
  () => route.query.flow,
  key => {
    if (
      key &&
      key !== selectedKey.value &&
      flows.value.some(f => f.key === key)
    ) {
      selectedKey.value = key;
    }
  }
);

// "Abrir configuração": rota própria (Integrações, Campanhas…) ou a aba do
// hub indicada pelo fluxo (+ ?agent= para o hub descer até o card certo)
const openConfig = () => {
  const cfg = selected.value?.config || {};
  if (cfg.route) {
    router.push({ name: cfg.route, params: { accountId: accountId.value } });
    return;
  }
  const query = { tab: cfg.tab || 'agentes' };
  if (cfg.anchor) query.agent = cfg.anchor;
  router.replace({ query });
};

let timer = null;
onMounted(() => {
  load();
  timer = setInterval(refreshSelected, 60000);
});
onBeforeUnmount(() => clearInterval(timer));
</script>

<template>
  <div class="cv-page cv-overlay max-w-6xl" :style="cvVars">
    <!-- linha de cima: o que é esta tela + a paleta -->
    <div class="mb-3 flex items-center gap-2 flex-wrap">
      <p class="text-[11px] text-n-slate-9 flex-1 min-w-0">
        O caminho que cada agente e automação percorre — gatilho, decisões,
        ações e saídas — com o estado ao vivo desta conta.
        <template v-if="flows.length">
          · <b class="text-n-slate-11">{{ onCount }}</b> de
          {{ flows.length }} ligado(s)
        </template>
      </p>
      <button
        class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
        title="Paleta desta tela"
        @click="openPalettePicker('panel')"
      >
        <span class="i-lucide-palette text-xs" />
        Paleta
      </button>
    </div>
    <CevicoPalettePicker :pal="pal" title="Paleta de cores · Mapa de Fluxos" />

    <SkeletonScreen v-if="isLoading" variant="list" />

    <div
      v-else-if="flows.length"
      class="grid grid-cols-1 lg:grid-cols-[280px_minmax(0,1fr)] gap-4 items-start"
    >
      <!-- ══ coluna esquerda: lista agrupada ══ -->
      <div class="cv-block p-4" :style="blockVars('lista')">
        <!-- celular: recolhe a lista, mostra só o fluxo aberto -->
        <button
          class="lg:hidden w-full flex items-center gap-2 text-sm font-bold text-n-slate-12"
          @click="listOpen = !listOpen"
        >
          <span class="cv-icon"><span class="i-lucide-list text-base" /></span>
          <span class="flex-1 text-left truncate">{{
            selected?.name || 'Fluxos'
          }}</span>
          <span
            class="i-lucide-chevron-down text-n-slate-9 transition-transform"
            :class="listOpen ? 'rotate-180' : ''"
          />
        </button>
        <div class="hidden lg:flex items-center gap-2 mb-3">
          <span class="cv-icon"><span class="i-lucide-list text-base" /></span>
          <h2 class="text-sm font-bold text-n-slate-12">Fluxos</h2>
          <span class="text-[11px] text-n-slate-9 ml-auto">{{
            flows.length
          }}</span>
        </div>

        <div
          :class="listOpen ? 'block mt-3' : 'hidden lg:block'"
          class="space-y-4"
        >
          <div v-for="group in grouped" :key="group.title">
            <p
              class="text-[10px] font-bold text-n-slate-9 uppercase tracking-wide mb-1.5"
            >
              {{ group.title }}
            </p>
            <div class="space-y-1">
              <button
                v-for="flow in group.flows"
                :key="flow.key"
                class="w-full text-left cv-sub cv-sub-hover px-3 py-2 transition-colors"
                :class="flow.key === selectedKey ? 'cv-sub-on' : ''"
                @click="select(flow.key)"
              >
                <div class="flex items-center gap-2">
                  <span
                    class="w-6 h-6 rounded-lg flex items-center justify-center flex-shrink-0 text-white"
                    :style="{ background: flow.color || '#64748B' }"
                  >
                    <span :class="flow.icon" class="text-xs" />
                  </span>
                  <span
                    class="text-xs font-semibold text-n-slate-12 truncate flex-1 min-w-0"
                  >
                    {{ flow.name }}
                  </span>
                  <span
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :style="{ background: stateOf(flow).dot }"
                    :title="stateOf(flow).label"
                  />
                </div>
                <div class="flex items-center gap-1 mt-1 flex-wrap pl-8">
                  <span
                    class="text-[9px] font-bold px-1.5 py-0.5 rounded-full"
                    :style="{
                      background: stateOf(flow).bg,
                      color: stateOf(flow).fg,
                    }"
                  >
                    {{ stateOf(flow).label }}
                  </span>
                  <span class="text-[9px] text-n-slate-9">
                    {{ ago(flow.live?.last_run_at) }}
                  </span>
                  <span
                    v-for="c in counterList(flow).slice(0, 2)"
                    :key="c.label"
                    class="text-[9px] px-1.5 py-0.5 rounded-full bg-n-alpha-1 text-n-slate-11"
                    :title="c.label"
                  >
                    {{ c.value }} {{ c.label }}
                  </span>
                </div>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ área principal: cabeçalho + diagrama + rodapé ══ -->
      <div
        v-if="selected"
        class="cv-block p-5 sm:p-6 min-w-0"
        :style="blockVars('mapa')"
      >
        <!-- no celular o cabeçalho empilha: ícone + título numa linha, botões
             embaixo em largura cheia (senão o título quebra letra a letra) -->
        <div class="flex flex-col sm:flex-row sm:items-start gap-3 mb-3">
          <span
            class="w-11 h-11 rounded-xl hidden sm:flex items-center justify-center flex-shrink-0 shadow text-white"
            :style="{ background: selected.color || '#64748B' }"
          >
            <span :class="selected.icon" class="text-lg" />
          </span>
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <span
                class="w-7 h-7 rounded-lg flex sm:hidden items-center justify-center flex-shrink-0 text-white"
                :style="{ background: selected.color || '#64748B' }"
              >
                <span :class="selected.icon" class="text-sm" />
              </span>
              <h2 class="text-base font-bold text-n-slate-12 leading-tight">
                {{ selected.name }}
              </h2>
              <span
                class="flex items-center gap-1 text-[10px] font-bold px-2 py-0.5 rounded-full"
                :style="{
                  background: stateOf(selected).bg,
                  color: stateOf(selected).fg,
                }"
              >
                <span
                  class="w-1.5 h-1.5 rounded-full"
                  :style="{ background: stateOf(selected).dot }"
                />
                {{ stateOf(selected).label }}
              </span>
              <span class="text-[10px] text-n-slate-9">{{
                selected.group
              }}</span>
            </div>
            <p class="text-xs text-n-slate-10 mt-1">{{ selected.what }}</p>
            <p
              class="text-[11px] text-n-slate-11 mt-1.5 flex items-center gap-1.5 flex-wrap"
            >
              <span
                :class="TRIGGER_ICON[selected.trigger?.kind] || 'i-lucide-play'"
                class="text-xs"
                :style="{ color: selected.color }"
              />
              <b>{{ triggerTitle }}</b>
              {{ selected.trigger?.label }}
              <span class="text-n-slate-9">{{ lastRunText }}</span>
            </p>
          </div>
          <div class="flex items-center gap-1.5 flex-shrink-0 w-full sm:w-auto">
            <button
              class="cv-btn cv-btn-ghost cv-btn-sm"
              :disabled="isRefreshing"
              title="Atualizar o estado agora (também atualiza sozinho a cada minuto)"
              @click="refreshSelected"
            >
              <span
                :class="
                  isRefreshing
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="text-xs"
              />
            </button>
            <button
              class="cv-btn cv-btn-sm text-white flex-1 sm:flex-none justify-center"
              :style="{ background: selected.color || '#64748B' }"
              title="Abre a tela onde este agente/automação é configurado"
              @click="openConfig"
            >
              <span class="i-lucide-settings-2 text-xs" />
              Abrir configuração
            </button>
          </div>
        </div>

        <FlowDiagram
          :definition="selected.mermaid"
          :flow-key="selected.key"
          @node-click="openConfig"
        />

        <!-- rodapé: contadores, nota e legenda -->
        <div
          class="mt-3 pt-3 flex items-center gap-2 flex-wrap"
          style="border-top: 1px solid rgb(var(--cv-rgb) / 0.16)"
        >
          <span
            v-for="c in counterList(selected)"
            :key="c.label"
            class="cv-chip"
            :title="c.label"
          >
            <b class="text-n-slate-12 mr-1">{{ c.value }}</b>
            <span>{{ c.label }}</span>
          </span>
          <span
            v-if="!counterList(selected).length"
            class="text-[11px] text-n-slate-9"
          >
            sem contadores para este fluxo
          </span>
          <span
            v-if="selected.live?.note"
            class="text-[11px] text-n-slate-9 ml-auto flex items-center gap-1"
          >
            <span class="i-lucide-info text-[10px]" />
            {{ selected.live.note }}
          </span>
        </div>
        <div class="mt-2 flex items-center gap-x-3 gap-y-1 flex-wrap">
          <span
            v-for="l in LEGEND"
            :key="l.label"
            class="text-[10px] text-n-slate-9 flex items-center gap-1"
          >
            <span class="w-2 h-2 rounded-sm" :style="{ background: l.color }" />
            {{ l.label }}
          </span>
          <span class="text-[10px] text-n-slate-9 ml-auto">
            cinza tracejado = fluxo desligado · desenhado a partir do código
            real
          </span>
        </div>
      </div>
    </div>

    <p v-else class="text-sm text-n-slate-10">Nenhum fluxo cadastrado ainda.</p>
  </div>
</template>
