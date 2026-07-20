<script setup>
// 🌪 MONTADOR DE FUNIS (item 60, aba própria em Conteúdos): o caminho
// completo da captação — as FONTES (tráfego pago, orgânico, médicos
// parceiros, indicação…) alimentando cada funil de páginas até o WhatsApp.
// O admin escolhe as fontes de cada funil e liga páginas soltas em cadeia.
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CrmAPI from 'dashboard/api/crm';

const { isAdmin } = useAdmin();
const isLoading = ref(true);
const pages = ref([]);
const funnels = ref([]);
const funnelSources = ref({}); // { headPageId: [sourceKey, ...] }
const catalog = ref([]);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getPagesDashboard();
    pages.value = data.pages || [];
    funnels.value = data.funnels || [];
    funnelSources.value = data.funnel_sources || {};
    catalog.value = data.source_catalog || [];
  } catch {
    useAlert('Não consegui carregar o Montador de Funis.');
  } finally {
    isLoading.value = false;
  }
};

const sourceOf = key => catalog.value.find(s => s.key === key) || null;
const headOf = funnel => funnel.steps[0];
const sourcesFor = funnel => (funnelSources.value[String(headOf(funnel)?.id)] || []).map(sourceOf).filter(Boolean);
const availableSourcesFor = funnel => {
  const used = funnelSources.value[String(headOf(funnel)?.id)] || [];
  return catalog.value.filter(s => !used.includes(s.key));
};

const saving = ref(false);
const persist = async (extra = {}) => {
  saving.value = true;
  try {
    const { data } = await CrmAPI.saveFunnelSources({ funnel_sources: funnelSources.value, ...extra });
    funnelSources.value = data.funnel_sources || {};
    catalog.value = data.source_catalog || catalog.value;
  } catch {
    useAlert('Não consegui salvar as fontes.');
  } finally {
    saving.value = false;
  }
};

const addSource = (funnel, key) => {
  const id = String(headOf(funnel)?.id);
  funnelSources.value = { ...funnelSources.value, [id]: [...(funnelSources.value[id] || []), key] };
  persist();
};
const removeSource = (funnel, key) => {
  const id = String(headOf(funnel)?.id);
  funnelSources.value = { ...funnelSources.value, [id]: (funnelSources.value[id] || []).filter(k => k !== key) };
  persist();
};

// criar fonte nova no catálogo (médico parceiro específico, evento…)
const newSourceLabel = ref('');
const addCatalogSource = () => {
  if (!newSourceLabel.value.trim()) return;
  persist({ source_catalog: [...catalog.value, { label: newSourceLabel.value.trim(), emoji: '📥' }] });
  newSourceLabel.value = '';
};

// ── ligar páginas em cadeia (o elo do funil) ──
const savingLink = ref(0);
const setNext = async (page, nextId) => {
  savingLink.value = page.id;
  try {
    await CrmAPI.updatePage(page.id, { next_page_id: nextId || null });
    await load();
    useAlert(nextId ? 'Elo criado! O botão da página já aponta pro novo destino.' : 'Elo removido — o botão volta pro WhatsApp.');
  } catch {
    useAlert('Não consegui atualizar o funil.');
  } finally {
    savingLink.value = 0;
  }
};
const linkCandidates = page => pages.value.filter(p => p.id !== page.id);
const loosePages = computed(() => {
  const inFunnel = new Set();
  funnels.value.forEach(f => f.steps.forEach(s => inFunnel.add(s.id)));
  return pages.value.filter(p => p.status === 'published' && !inFunnel.has(p.id));
});

const fmtPct = v => (v === null || v === undefined ? '—' : `${v}%`);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4AF37)">
          <span class="i-lucide-tornado text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Montador de Funis</h1>
          <p class="text-xs text-n-slate-10">da FONTE ao WhatsApp: tráfego, médicos parceiros e indicações alimentando cada funil de páginas</p>
        </div>
      </div>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <template v-else>
        <!-- catálogo de fontes (admin adiciona novas) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-4 mb-5">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">Fontes de captação disponíveis</p>
          <div class="flex items-center gap-1.5 flex-wrap">
            <span
              v-for="s in catalog"
              :key="s.key"
              class="text-[11px] px-2.5 py-1 rounded-full border border-n-weak text-n-slate-11"
            >
              {{ s.emoji }} {{ s.label }}
            </span>
            <template v-if="isAdmin">
              <input
                v-model="newSourceLabel"
                type="text"
                placeholder="Nova fonte (ex: Dr. parceiro X)…"
                class="h-7 rounded-full border border-dashed border-n-weak bg-n-solid-1 px-3 text-[11px] text-n-slate-12"
                style="width: 14rem; margin-bottom: 0"
                @keyup.enter="addCatalogSource"
              />
              <button
                class="w-7 h-7 rounded-full text-white flex items-center justify-center disabled:opacity-50"
                style="background: linear-gradient(135deg, #B8860B, #D4AF37)"
                :disabled="saving || !newSourceLabel.trim()"
                @click="addCatalogSource"
              >
                <span class="i-lucide-plus text-xs" />
              </button>
            </template>
          </div>
        </div>

        <!-- cada funil: FONTES → páginas → WhatsApp -->
        <div v-if="!funnels.length" class="rounded-2xl border border-dashed border-n-weak px-4 py-8 text-center text-sm text-n-slate-9 mb-5">
          Nenhum funil montado ainda — ligue uma página solta aqui embaixo pra criar o primeiro caminho.
        </div>

        <div v-for="f in funnels" :key="f.key" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5 overflow-x-auto">
          <div class="flex items-stretch gap-0 min-w-max">
            <!-- FONTES que alimentam este funil -->
            <div class="w-56 flex-shrink-0 rounded-2xl border-2 border-dashed p-3" style="border-color: rgba(184, 134, 11, 0.4); background: rgba(184, 134, 11, 0.04)">
              <p class="text-[10px] font-bold uppercase tracking-wide mb-1.5" style="color: #92600A">📥 Fontes de captação</p>
              <div class="space-y-1">
                <div
                  v-for="s in sourcesFor(f)"
                  :key="s.key"
                  class="flex items-center gap-1.5 text-[11px] text-n-slate-11 rounded-lg bg-n-solid-1 border border-n-weak px-2 py-1"
                >
                  <span>{{ s.emoji }}</span>
                  <span class="flex-1 truncate">{{ s.label }}</span>
                  <button v-if="isAdmin" class="i-lucide-x text-[10px] text-n-slate-9 hover:text-red-500" @click="removeSource(f, s.key)" />
                </div>
                <p v-if="!sourcesFor(f).length" class="text-[10px] text-n-slate-9">nenhuma fonte marcada ainda.</p>
              </div>
              <select
                v-if="isAdmin && availableSourcesFor(f).length"
                class="mt-2 w-full h-7 rounded-lg border border-n-weak bg-n-solid-1 px-1.5 text-[10px] text-n-slate-11"
                style="margin-bottom: 0"
                :disabled="saving"
                @change="addSource(f, $event.target.value); $event.target.value = ''"
              >
                <option value="">+ adicionar fonte…</option>
                <option v-for="s in availableSourcesFor(f)" :key="s.key" :value="s.key">{{ s.emoji }} {{ s.label }}</option>
              </select>
            </div>
            <div class="flex items-center px-2 flex-shrink-0">
              <span class="i-lucide-arrow-right text-xl" style="color: #B8860B" />
            </div>

            <!-- trilha do funil -->
            <template v-for="(step, si) in f.steps" :key="step.id">
              <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3 w-56 flex-shrink-0">
                <div class="flex items-center gap-1.5 mb-1">
                  <span class="text-sm">{{ step.emoji || '👁️' }}</span>
                  <p class="text-xs font-bold text-n-slate-12 truncate flex-1">{{ step.title }}</p>
                </div>
                <p class="text-[10px] text-n-slate-9 truncate mb-1.5">/{{ step.slug }}</p>
                <p class="text-[11px] text-n-slate-11">
                  {{ step.views }} visitas
                  <template v-if="step.views_from_previous !== null"> · <b>{{ step.views_from_previous }}</b> do elo anterior</template>
                </p>
                <p class="text-[11px] text-n-slate-10 mt-0.5">
                  💬 {{ step.cta_clicks }} WhatsApp <b :style="{ color: step.cta_rate >= 10 ? '#047857' : '#64748B' }">({{ fmtPct(step.cta_rate) }})</b>
                </p>
                <select
                  v-if="isAdmin"
                  class="mt-2 w-full h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[10px] text-n-slate-11"
                  style="margin-bottom: 0"
                  :disabled="savingLink === step.id"
                  :value="step.next_page_id || ''"
                  @change="setNext(step, $event.target.value)"
                >
                  <option value="">➡ termina no WhatsApp</option>
                  <option v-for="c in linkCandidates(step)" :key="c.id" :value="c.id">➡ {{ c.title }}</option>
                </select>
              </div>
              <div v-if="si < f.steps.length - 1" class="flex flex-col items-center justify-center px-1.5 flex-shrink-0">
                <span class="text-[10px] font-bold" :style="{ color: step.next_rate >= 10 ? '#047857' : '#94A3B8' }">{{ step.next_clicks }} seguiram</span>
                <span class="i-lucide-arrow-right text-lg" :style="{ color: step.next_rate >= 10 ? '#047857' : '#94A3B8' }" />
                <span class="text-[10px]" :style="{ color: step.next_rate >= 10 ? '#047857' : '#94A3B8' }">{{ fmtPct(step.next_rate) }}</span>
              </div>
            </template>
            <div class="flex items-center pl-1.5 flex-shrink-0">
              <span class="rounded-xl border border-dashed border-n-weak px-3 py-2 text-[11px] text-n-slate-10">💬 WhatsApp</span>
            </div>
          </div>
        </div>

        <!-- páginas soltas: início de um novo caminho -->
        <div v-if="loosePages.length" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5">
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">Páginas publicadas fora de funil</p>
          <div class="space-y-1.5">
            <div v-for="p in loosePages" :key="p.id" class="flex items-center gap-2 flex-wrap rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2">
              <span class="text-sm">{{ p.emoji || '👁️' }}</span>
              <span class="text-xs font-semibold text-n-slate-12 flex-1 min-w-[140px] truncate">{{ p.title }}</span>
              <span class="text-[11px] text-n-slate-10">{{ p.views_count }} visitas</span>
              <select
                v-if="isAdmin"
                class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[10px] text-n-slate-11"
                style="width: 13rem; margin-bottom: 0"
                :disabled="savingLink === p.id"
                :value="p.next_page_id || ''"
                @change="setNext(p, $event.target.value)"
              >
                <option value="">➡ termina no WhatsApp</option>
                <option v-for="c in linkCandidates(p)" :key="c.id" :value="c.id">➡ {{ c.title }}</option>
              </select>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
