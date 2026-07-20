<script setup>
// PLANEJAMENTO DE CONTEÚDOS (workflow de marketing): cada peça de conteúdo
// (reels, carrossel, post, anúncio, página, e-mail) anda pelo fluxo
// ideia → copy → produção → revisão → publicado. Time inteiro usa.
import { ref, computed, watch, onMounted, nextTick } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import draggable from 'vuedraggable';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import EmojiFx from 'dashboard/components-next/cevico/EmojiFx.vue';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const items = ref([]);

const STAGES = [
  { key: 'ideia', label: 'Ideias', icon: 'i-lucide-lightbulb', grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)' },
  { key: 'copy', label: 'Copy', icon: 'i-lucide-pen-line', grad: 'linear-gradient(135deg, #0F5FA6, #1E7FBF)' },
  { key: 'producao', label: 'Em produção', icon: 'i-lucide-clapperboard', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
  { key: 'revisao', label: 'Revisão', icon: 'i-lucide-eye', grad: 'linear-gradient(135deg, #9D174D, #F472B6)' },
  { key: 'publicado', label: 'Publicado', icon: 'i-lucide-check-check', grad: 'linear-gradient(135deg, #047857, #10B981)' },
];
const FORMATS = [
  { key: 'reels', label: 'Reels', color: '#DB2777' },
  { key: 'carrossel', label: 'Carrossel', color: '#7C3AED' },
  { key: 'post', label: 'Post', color: '#0F5FA6' },
  { key: 'anuncio', label: 'Anúncio', color: '#EA580C' },
  { key: 'pagina', label: 'Página', color: '#0D9488' },
  { key: 'email', label: 'E-mail', color: '#64748B' },
];
const formatOf = key => FORMATS.find(f => f.key === key) || FORMATS[2];

const byStage = computed(() => {
  const map = {};
  STAGES.forEach(s => {
    map[s.key] = items.value.filter(i => i.stage === s.key);
  });
  return map;
});

const load = async () => {
  try {
    const { data } = await CrmAPI.getContentItems();
    items.value = data.items || [];
  } catch {
    useAlert('Não consegui carregar o planejamento.');
  } finally {
    isLoading.value = false;
  }
};

// ── item 95: RENOVAR o ambiente — tudo PUBLICADO? 5 min depois os cards
// vão pra coluna oculta e o quadro nasce limpo pro próximo ciclo ──
const allPublished = computed(
  () => items.value.length > 0 && items.value.every(i => i.stage === 'publicado')
);
const RENEW_AFTER_MS = 5 * 60 * 1000;
let renewTimer = null;
const renewCountdown = ref(0);
let renewTicker = null;
const clearRenewTimers = () => {
  clearTimeout(renewTimer);
  clearInterval(renewTicker);
  renewTimer = null;
  renewTicker = null;
  renewCountdown.value = 0;
};
const renewNow = async () => {
  clearRenewTimers();
  try {
    await CrmAPI.archivePublishedContent();
    await load();
    useAlert('Quadro renovado — pronto pro próximo ciclo de conteúdos! ✨');
  } catch {
    useAlert('Não consegui renovar o quadro.');
  }
};
watch(allPublished, now => {
  if (!now) {
    clearRenewTimers();
    return;
  }
  renewCountdown.value = RENEW_AFTER_MS / 1000;
  renewTicker = setInterval(() => { renewCountdown.value = Math.max(0, renewCountdown.value - 1); }, 1000);
  renewTimer = setTimeout(renewNow, RENEW_AFTER_MS);
});
const renewLabel = computed(() => {
  const m = Math.floor(renewCountdown.value / 60);
  const s = String(renewCountdown.value % 60).padStart(2, '0');
  return `${m}:${s}`;
});

// ── criar rápido (input no topo de cada coluna) ──
const drafts = ref({});
const draftFor = stage => {
  if (!drafts.value[stage]) drafts.value[stage] = { title: '', format: 'post' };
  return drafts.value[stage];
};
const addItem = async stage => {
  const draft = draftFor(stage);
  if (!draft.title.trim()) return;
  try {
    const { data } = await CrmAPI.createContentItem({ title: draft.title.trim(), format: draft.format, stage });
    items.value.push(data);
    draft.title = '';
  } catch {
    useAlert('Não consegui criar.');
  }
};

// ── comemoração progressiva (rodada 2 — 18/07) ──
// copy = foco/ideias · produção = corações · publicado = explosão SAINDO
// DO CARD (1 emoji sorteado, estilo Tarefas) + a coluna se ENERGIZA:
// elétrons dão a volta em sentido horário e ela acende verde, pulsando.
const fx = ref(null);
const CELEBRATIONS = {
  copy: { emojis: ['💡', '🎯', '✍️'], count: 5 },
  producao: { emojis: ['❤️', '💖', '❤️‍🔥'], count: 10 },
};
const PUBLISH_EMOJIS = ['🥳', '👏', '⭐️', '🔥', '🥇', '🚀', '💚', '✅', '💎'];
// '' | 'charging' (volta dos elétrons) | 'lit' (pulsando) | 'fading' (esvai)
const publishedCharge = ref('');
// 1ª publicação da sessão = festa completa; as SEGUINTES = só pop de 3 ✅
let publishedCelebratedOnce = false;
let chargeLapTimer = null;
let chargeFadeTimer = null;
let chargeOffTimer = null;
const energizePublishedColumn = () => {
  clearTimeout(chargeLapTimer);
  clearTimeout(chargeFadeTimer);
  clearTimeout(chargeOffTimer);
  publishedCharge.value = '';
  requestAnimationFrame(() => {
    publishedCharge.value = 'charging';
  });
  chargeLapTimer = setTimeout(() => {
    publishedCharge.value = 'lit';
  }, 1100);
  chargeFadeTimer = setTimeout(() => {
    publishedCharge.value = 'fading'; // a intensidade some LENTAMENTE
  }, 5100);
  chargeOffTimer = setTimeout(() => {
    publishedCharge.value = '';
  }, 7400);
};
const cardCenter = id => {
  const el = document.querySelector(`[data-cid="${id}"]`);
  if (!el) return { x: window.innerWidth / 2, y: window.innerHeight / 2 };
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
};
const celebrate = async (item, event) => {
  if (!fx.value) return;
  if (item.stage === 'publicado') {
    await nextTick();
    const { x, y } = cardCenter(item.id);
    if (publishedCelebratedOnce) {
      // já teve a festa nesta sessão: só um "pop" de 3 checks verdes
      fx.value.burstAt(x, y, ['✅'], 3);
      return;
    }
    publishedCelebratedOnce = true;
    const emoji =
      PUBLISH_EMOJIS[Math.floor(Math.random() * PUBLISH_EMOJIS.length)];
    fx.value.burstAt(x, y, [emoji], 26);
    setTimeout(energizePublishedColumn, 150);
    return;
  }
  const c = CELEBRATIONS[item.stage];
  if (!c) return;
  if (event?.clientX) {
    fx.value.burstAt(event.clientX, event.clientY, c.emojis, c.count);
  } else {
    await nextTick();
    const { x, y } = cardCenter(item.id);
    fx.value.burstAt(x, y, c.emojis, c.count);
  }
};
const stageIndex = key => STAGES.findIndex(s => s.key === key);
const moveItem = async (item, dir, event) => {
  const idx = stageIndex(item.stage) + dir;
  if (idx < 0 || idx >= STAGES.length) return;
  const before = item.stage;
  item.stage = STAGES[idx].key;
  try {
    await CrmAPI.updateContentItem(item.id, { stage: item.stage });
    if (dir > 0) celebrate(item, event);
  } catch {
    item.stage = before;
    useAlert('Não consegui mover.');
  }
};

// ── arrasto entre colunas (mesmo movimento do card do CRM) ──
const onDrop = async (stageKey, list) => {
  const ids = new Set(list.map(i => i.id));
  const moved = list.find(i => i.stage !== stageKey);
  const fromIdx = moved ? stageIndex(moved.stage) : -1;
  list.forEach(i => {
    i.stage = stageKey;
  });
  // preserva a ordem deixada pelo arrasto nesta coluna
  items.value = [...items.value.filter(i => !ids.has(i.id)), ...list];
  if (!moved) return; // só reordenou dentro da própria coluna
  try {
    await CrmAPI.updateContentItem(moved.id, {
      stage: stageKey,
      position: list.findIndex(i => i.id === moved.id),
    });
    if (stageIndex(stageKey) > fromIdx) celebrate(moved);
  } catch {
    useAlert('Não consegui mover.');
    load();
  }
};

// ── detalhes (expande no clique) ──
const expanded = ref(null);
const saveItem = async item => {
  try {
    await CrmAPI.updateContentItem(item.id, {
      title: item.title, format: item.format, owner_id: item.owner_id || null,
      due_on: item.due_on || null, notes: item.notes,
    });
  } catch {
    useAlert('Não consegui salvar.');
  }
};
const deleteItem = async item => {
  if (!window.confirm(`Excluir "${item.title}"?`)) return;
  try {
    await CrmAPI.deleteContentItem(item.id);
    items.value = items.value.filter(i => i.id !== item.id);
  } catch {
    useAlert('Só administradores excluem conteúdos.');
  }
};

const agentName = id => {
  const a = teamAgents.value.find(u => u.id === Number(id));
  return a ? (a.available_name || a.name).split(' ')[0] : null;
};
const overdue = item => item.due_on && item.stage !== 'publicado' && new Date(`${item.due_on}T23:59:59`) < new Date();
const fmtDue = d => new Date(`${d}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });

onMounted(() => {
  if (!teamAgents.value.length) store.dispatch('agents/get');
  load();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-hidden bg-n-surface-1">
    <div class="p-4 sm:px-8 sm:pt-6 pb-2">
      <div class="flex items-center gap-3 flex-wrap">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #7C3AED, #DB2777)">
          <span class="i-lucide-kanban text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Planejamento de conteúdos</h1>
          <p class="text-xs text-n-slate-10">o fluxo das peças de marketing: ideia → copy → produção → revisão → publicado</p>
        </div>
        <!-- item 95: tudo publicado → o quadro se renova sozinho -->
        <div v-if="renewCountdown > 0" class="flex items-center gap-1.5">
          <span class="text-[10px] px-2 py-0.5 rounded-full font-bold" style="background: rgba(16, 185, 129, 0.14); color: #047857">
            🧹 quadro novo em {{ renewLabel }}
          </span>
          <button
            class="text-[10px] font-bold px-2 py-0.5 rounded-full text-white hover:opacity-90"
            style="background: linear-gradient(135deg, #047857, #10B981)"
            @click="renewNow"
          >
            Renovar agora
          </button>
        </div>
      </div>
    </div>

    <SkeletonScreen v-if="isLoading" variant="board" />

    <!-- board: colunas deslizáveis (desktop e mobile) -->
    <div v-else class="flex-1 overflow-x-auto overflow-y-hidden px-4 sm:px-8 pb-4">
      <div class="flex gap-3 h-full min-w-max">
        <div
          v-for="stage in STAGES"
          :key="stage.key"
          class="relative w-64 flex-shrink-0 flex flex-col rounded-2xl bg-n-solid-2 border border-n-weak overflow-hidden"
          :class="{
            'cevico-col-charging': stage.key === 'publicado' && publishedCharge === 'charging',
            'cevico-col-lit': stage.key === 'publicado' && publishedCharge === 'lit',
            'cevico-col-fading': stage.key === 'publicado' && publishedCharge === 'fading',
          }"
        >
          <div class="px-3 py-2 flex items-center gap-2 text-white" :style="{ background: stage.grad }">
            <span :class="stage.icon" class="text-sm" />
            <span class="text-xs font-bold flex-1">{{ stage.label }}</span>
            <span class="text-[10px] font-bold bg-white/20 rounded-full px-1.5 py-0.5">{{ byStage[stage.key].length }}</span>
          </div>

          <div class="p-2 flex-1 overflow-y-auto">
            <!-- criar rápido -->
            <div class="flex items-center gap-1 mb-2">
              <input
                v-model="draftFor(stage.key).title"
                type="text"
                placeholder="Nova peça…"
                class="flex-1 min-w-0 h-7 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12"
                @keyup.enter="addItem(stage.key)"
              />
              <button
                class="w-7 h-7 rounded-lg text-white flex items-center justify-center flex-shrink-0 disabled:opacity-40"
                :style="{ background: stage.grad }"
                :disabled="!draftFor(stage.key).title.trim()"
                @click="addItem(stage.key)"
              >
                <span class="i-lucide-plus text-xs" />
              </button>
            </div>

            <!-- cards — arrasto entre colunas no mesmo movimento do CRM -->
            <draggable
              :model-value="byStage[stage.key]"
              group="cevico-content"
              item-key="id"
              :animation="150"
              :empty-insert-threshold="80"
              ghost-class="opacity-40"
              class="min-h-[40px]"
              @update:model-value="list => onDrop(stage.key, list)"
            >
              <template #item="{ element: item }">
            <div
              :data-cid="item.id"
              class="rounded-xl border border-n-weak bg-n-solid-1 mb-1.5 overflow-hidden cursor-grab active:cursor-grabbing"
            >
              <div class="px-2.5 py-2 cursor-pointer hover:bg-n-alpha-1" @click="expanded = expanded === item.id ? null : item.id">
                <p class="text-xs font-semibold text-n-slate-12 leading-snug">{{ item.title }}</p>
                <div class="flex items-center gap-1.5 flex-wrap mt-1.5">
                  <span
                    class="text-[9px] font-bold px-1.5 py-0.5 rounded-full text-white"
                    :style="{ background: formatOf(item.format).color }"
                  >
                    {{ formatOf(item.format).label }}
                  </span>
                  <span v-if="item.owner_id && agentName(item.owner_id)" class="text-[10px] text-n-slate-10">{{ agentName(item.owner_id) }}</span>
                  <span
                    v-if="item.due_on"
                    class="inline-flex items-center gap-0.5 text-[10px] font-semibold ml-auto"
                    :style="{ color: overdue(item) ? '#DC2626' : '#94A3B8' }"
                  >
                    <span class="i-lucide-clock text-[10px]" /> {{ fmtDue(item.due_on) }}
                  </span>
                </div>
              </div>

              <!-- detalhes -->
              <div v-if="expanded === item.id" class="px-2.5 pb-2.5 pt-1 border-t border-n-weak space-y-1.5">
                <input v-model="item.title" type="text" class="w-full h-7 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12" @change="saveItem(item)" />
                <div class="flex items-center gap-1 flex-wrap">
                  <button
                    v-for="f in FORMATS"
                    :key="f.key"
                    class="text-[9px] font-bold px-1.5 py-0.5 rounded-full border transition-all"
                    :style="item.format === f.key
                      ? { background: f.color, color: '#fff', borderColor: f.color }
                      : { borderColor: '#CBD5E1', color: '#64748B' }"
                    @click="item.format = f.key; saveItem(item)"
                  >
                    {{ f.label }}
                  </button>
                </div>
                <div class="flex items-center gap-1.5">
                  <select v-model="item.owner_id" class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1 text-[10px] text-n-slate-12" style="width: 7.5rem" @change="saveItem(item)">
                    <option :value="null">Sem dono</option>
                    <option v-for="a in teamAgents" :key="a.id" :value="a.id">{{ a.available_name || a.name }}</option>
                  </select>
                  <input v-model="item.due_on" type="date" class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1 text-[10px] text-n-slate-12" style="width: 7rem" @change="saveItem(item)" />
                </div>
                <textarea
                  v-model="item.notes"
                  rows="2"
                  placeholder="Roteiro, referências, link do drive…"
                  class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1 text-[11px] text-n-slate-12 resize-y"
                  @change="saveItem(item)"
                />
                <div class="flex items-center gap-1">
                  <button
                    class="h-6 px-2 rounded-md border border-n-weak text-[10px] text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-30"
                    :disabled="stageIndex(item.stage) === 0"
                    @click="moveItem(item, -1, $event)"
                  >
                    ← voltar
                  </button>
                  <button
                    class="h-6 px-2 rounded-md border border-n-weak text-[10px] font-semibold text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-30"
                    :disabled="stageIndex(item.stage) === STAGES.length - 1"
                    @click="moveItem(item, 1, $event)"
                  >
                    avançar →
                  </button>
                  <button
                    v-if="isAdmin"
                    class="ml-auto w-6 h-6 rounded-md flex items-center justify-center text-red-500 hover:bg-red-500/10"
                    @click="deleteItem(item)"
                  >
                    <span class="i-lucide-trash-2 text-xs" />
                  </button>
                </div>
              </div>
            </div>
              </template>
            </draggable>

            <p v-if="!byStage[stage.key].length" class="text-[10px] text-n-slate-9 text-center py-3">
              nada aqui ainda
            </p>
          </div>
        </div>
      </div>
    </div>

    <EmojiFx ref="fx" />
  </div>
</template>

<style scoped>
/* volta dos ELÉTRONS na coluna Publicado (sentido horário, 1 volta) */
@property --cevico-lap {
  syntax: '<angle>';
  initial-value: 0deg;
  inherits: false;
}
.cevico-col-charging::before {
  content: '';
  position: absolute;
  inset: 0;
  border-radius: 1rem;
  padding: 2px;
  background: conic-gradient(
    from var(--cevico-lap),
    transparent 0deg 292deg,
    rgba(52, 211, 153, 0.25) 310deg,
    #34d399 338deg,
    #ecfdf5 356deg,
    transparent 360deg
  );
  -webkit-mask: linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0);
  -webkit-mask-composite: xor;
  mask-composite: exclude;
  pointer-events: none;
  z-index: 10;
  animation: cevico-col-lap 1.1s linear forwards;
}
@keyframes cevico-col-lap {
  to { --cevico-lap: 360deg; }
}

/* círculo completo → coluna acesa pulsando SÓ PRA FORA (box-shadow);
   a tela de dentro fica branca/intocada (pedido 19/07) */
.cevico-col-lit {
  border-color: #10b981 !important;
  animation: cevico-col-pulse 1.6s ease-in-out infinite;
}
@keyframes cevico-col-pulse {
  0%, 100% { box-shadow: 0 0 10px rgba(16, 185, 129, 0.35); }
  50% { box-shadow: 0 0 26px rgba(52, 211, 153, 0.75); }
}
/* fim da festa: a intensidade SOME LENTAMENTE (2.3s de decaimento) */
.cevico-col-fading {
  border-color: #10b981 !important;
  animation: cevico-col-fade 2.3s ease-out forwards;
}
@keyframes cevico-col-fade {
  0% { box-shadow: 0 0 18px rgba(52, 211, 153, 0.55); }
  100% { box-shadow: 0 0 0 rgba(52, 211, 153, 0); border-color: inherit; }
}
</style>
