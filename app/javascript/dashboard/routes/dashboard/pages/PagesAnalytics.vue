<script setup>
// ANÁLISE DE PÁGINAS (PÁGINAS PRO, só admin): estatísticas completas por
// página (série diária, quanto da página leram, origem do funil, teste
// A/B) + o MONTADOR DE FUNIS — o "link build" da CEVICO: ligar páginas
// (página → página → WhatsApp) vendo a conversão de cada elo.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const pages = ref([]);
const funnels = ref([]);
const selectedId = ref(null);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getPagesDashboard();
    pages.value = data.pages || [];
    funnels.value = data.funnels || [];
    if (!selectedId.value && pages.value.length) {
      const best = [...pages.value].sort((a, b) => b.views_count - a.views_count)[0];
      selectedId.value = best.id;
    }
  } catch {
    useAlert('Não consegui carregar a análise.');
  } finally {
    isLoading.value = false;
  }
};

const selected = computed(() => pages.value.find(p => p.id === selectedId.value) || null);
const publishedPages = computed(() => pages.value.filter(p => p.status === 'published'));

// série diária: barras SVG simples (30 dias)
const maxSeries = computed(() => {
  if (!selected.value) return 1;
  return Math.max(1, ...selected.value.series.map(d => d.view));
});
const barLabel = d => {
  const date = new Date(`${d.date}T12:00:00`);
  return `${date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })}: ${d.view} visitas · ${d.cta} WhatsApp · ${d.next} funil`;
};

// quanto da página leram (25/50/75/100)
const SCROLL_BUCKETS = ['25', '50', '75', '100'];
const scrollTotal = computed(() =>
  SCROLL_BUCKETS.reduce((sum, b) => sum + (selected.value?.scroll?.[b] || 0), 0)
);
const scrollPct = bucket => {
  if (!scrollTotal.value) return 0;
  return Math.round(((selected.value?.scroll?.[bucket] || 0) / scrollTotal.value) * 100);
};

// resultados do teste A/B da página selecionada
const abRows = computed(() => {
  if (!selected.value) return [];
  const results = selected.value.ab_results || {};
  const variants = selected.value.ab_variants || [];
  return Object.keys(results).map(key => {
    const t = results[key];
    const clicks = (t.cta || 0) + (t.next || 0);
    return {
      key,
      name: key === 'a' ? 'Original' : variants.find(v => v.key === key)?.name || `Variação ${key.toUpperCase()}`,
      active: key === 'a' || variants.find(v => v.key === key)?.active,
      views: t.view || 0,
      clicks,
      rate: t.view ? Math.round((clicks / t.view) * 100) : null,
    };
  });
});
const abHasData = computed(() => abRows.value.some(r => r.views > 0 && r.key !== 'a'));
const abBest = computed(() => {
  const rows = abRows.value.filter(r => r.rate !== null && r.views >= 10);
  if (rows.length < 2) return null;
  return [...rows].sort((a, b) => b.rate - a.rate)[0];
});

// ── Montador de funis: reapontar o próximo passo direto daqui ──
const savingLink = ref(0);
const setNext = async (page, nextId) => {
  savingLink.value = page.id;
  try {
    await CrmAPI.updatePage(page.id, { next_page_id: nextId || null });
    await load();
    useAlert(nextId ? 'Funil atualizado! O botão da página já aponta pro novo destino.' : 'Elo removido — o botão volta pro WhatsApp.');
  } catch {
    useAlert('Não consegui atualizar o funil.');
  } finally {
    savingLink.value = 0;
  }
};
const linkCandidates = page => pages.value.filter(p => p.id !== page.id);

// páginas soltas (sem funil): candidatas a virar cabeça de um novo caminho
const loosePages = computed(() => {
  const inFunnel = new Set();
  funnels.value.forEach(f => f.steps.forEach(s => inFunnel.add(s.id)));
  return publishedPages.value.filter(p => !inFunnel.has(p.id));
});

const fmtPct = v => (v === null || v === undefined ? '—' : `${v}%`);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #1E7FBF)">
          <span class="i-lucide-chart-line text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Análise de Páginas</h1>
          <p class="text-xs text-n-slate-10">o que cada página está gerando · testes A/B · e o montador de funis (o "link build")</p>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- ── Visão geral: todas as páginas ── -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2">
            <span class="i-lucide-panels-top-left text-base" style="color: #0F5FA6" />
            Todas as páginas
            <span class="text-[11px] font-normal text-n-slate-9">clique numa linha para abrir a análise completa</span>
          </h2>
          <div class="space-y-1.5">
            <button
              v-for="p in pages"
              :key="p.id"
              class="w-full flex items-center gap-2 flex-wrap rounded-xl border px-3 py-2 text-left transition-all"
              :class="selectedId === p.id ? 'border-n-brand bg-n-brand/5' : 'border-n-weak bg-n-solid-1 hover:border-n-brand/50'"
              @click="selectedId = p.id"
            >
              <span class="text-base">{{ p.emoji || '👁️' }}</span>
              <span class="text-xs font-semibold text-n-slate-12 flex-1 min-w-[140px] truncate">{{ p.title }}</span>
              <span v-if="p.status !== 'published'" class="text-[10px] px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-10">não publicada</span>
              <span v-if="p.ab_running" class="text-[10px] px-1.5 py-0.5 rounded font-semibold" style="background: rgba(212,175,55,0.15); color: #92600A">teste A/B no ar</span>
              <span class="text-[11px] text-n-slate-10">{{ p.views_count }} visitas</span>
              <span class="text-[11px] text-n-slate-10">{{ p.cta_clicks_count + p.next_clicks_count }} cliques</span>
              <span class="text-[11px] font-bold" :style="{ color: p.click_rate >= 10 ? '#047857' : p.click_rate >= 5 ? '#B45309' : '#64748B' }">
                {{ fmtPct(p.click_rate) }}
              </span>
            </button>
          </div>
        </div>

        <!-- ── Análise da página escolhida ── -->
        <div v-if="selected" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-4 flex items-center gap-2">
            <span class="text-base">{{ selected.emoji || '👁️' }}</span>
            {{ selected.title }}
          </h2>

          <!-- série diária (30 dias) -->
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Visitas por dia — últimos 30 dias</p>
          <div class="flex items-end gap-[2px] h-24 mb-1 rounded-lg bg-n-alpha-1 px-2 pt-2">
            <div
              v-for="d in selected.series"
              :key="d.date"
              class="flex-1 rounded-t-sm transition-all hover:opacity-80"
              :style="{
                height: `${Math.max((d.view / maxSeries) * 100, d.view ? 6 : 1)}%`,
                background: d.view ? 'linear-gradient(180deg, #38BDF8, #0F5FA6)' : 'rgba(148,163,184,0.25)',
              }"
              :title="barLabel(d)"
            />
          </div>
          <p class="text-[10px] text-n-slate-9 mb-4">passe o mouse nas barras para ver o dia</p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <!-- quanto leram -->
            <div>
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Quanto da página leram</p>
              <template v-if="scrollTotal">
                <div v-for="b in SCROLL_BUCKETS" :key="b" class="flex items-center gap-2 mb-1">
                  <span class="text-[11px] text-n-slate-10 w-14">até {{ b }}%</span>
                  <div class="flex-1 h-2.5 bg-n-alpha-1 rounded-full overflow-hidden">
                    <div class="h-full rounded-full" :style="{ width: `${Math.max(scrollPct(b), 2)}%`, background: 'linear-gradient(90deg, #0F5FA6, #38BDF8)' }" />
                  </div>
                  <span class="text-[11px] font-semibold text-n-slate-11 w-10 text-right">{{ scrollPct(b) }}%</span>
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">onde cada visitante PAROU de rolar (novas visitas já contam)</p>
              </template>
              <p v-else class="text-[11px] text-n-slate-9">ainda sem dados de leitura — as próximas visitas já contam.</p>
            </div>

            <!-- origens do funil -->
            <div>
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">De onde os visitantes vieram (funil)</p>
              <template v-if="Object.keys(selected.origins || {}).length">
                <div v-for="(n, slug) in selected.origins" :key="slug" class="flex items-center gap-2 text-[11px] mb-1">
                  <span class="i-lucide-corner-down-right text-xs text-n-slate-9" />
                  <span class="text-n-slate-11 truncate flex-1">/{{ slug }}</span>
                  <b class="text-n-slate-12">{{ n }}</b>
                </div>
              </template>
              <p v-else class="text-[11px] text-n-slate-9">nenhuma visita veio de outra página ainda.</p>
            </div>
          </div>

          <!-- resultados do teste A/B -->
          <div v-if="selected.ab_variants?.length" class="mt-4 pt-4 border-t border-n-weak">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">Teste A/B</p>
            <div class="space-y-1.5">
              <div
                v-for="r in abRows"
                :key="r.key"
                class="flex items-center gap-2 flex-wrap rounded-xl border px-3 py-2"
                :class="abBest && abBest.key === r.key ? 'border-emerald-500/50 bg-emerald-500/5' : 'border-n-weak bg-n-solid-1'"
              >
                <span class="text-[11px] font-bold text-n-slate-12 uppercase w-4">{{ r.key }}</span>
                <span class="text-xs text-n-slate-11 flex-1 min-w-[120px] truncate">{{ r.name }}</span>
                <span v-if="!r.active" class="text-[10px] px-1.5 py-0.5 rounded bg-n-alpha-2 text-n-slate-10">pausada</span>
                <span class="text-[11px] text-n-slate-10">{{ r.views }} visitas</span>
                <span class="text-[11px] text-n-slate-10">{{ r.clicks }} cliques</span>
                <span class="text-[11px] font-bold" :style="{ color: r.rate >= 10 ? '#047857' : '#64748B' }">{{ fmtPct(r.rate) }}</span>
                <span v-if="abBest && abBest.key === r.key" class="text-[10px] font-bold px-2 py-0.5 rounded-full" style="background: rgba(16,185,129,0.14); color: #047857">
                  liderando
                </span>
              </div>
            </div>
            <p v-if="!abHasData" class="text-[10px] text-n-slate-9 mt-1.5">o teste começa a pontuar quando as variações receberem visitas.</p>
            <p v-else-if="!abBest" class="text-[10px] text-n-slate-9 mt-1.5">com 10+ visitas por variação o placar aponta quem está liderando.</p>
          </div>
        </div>

        <!-- ── 🔗 Montador de Funis (o "link build") ── -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1 flex items-center gap-2">
            <span class="i-lucide-git-branch text-base" style="color: #B8860B" />
            Montador de Funis
          </h2>
          <p class="text-xs text-n-slate-10 mb-4">
            o caminho do visitante: página → página → WhatsApp. Troque o destino de qualquer elo aqui — o botão da página passa a apontar pro novo destino na hora.
          </p>

          <div v-if="!funnels.length" class="rounded-xl border border-dashed border-n-weak px-4 py-5 text-center text-[12px] text-n-slate-9 mb-3">
            Nenhum funil montado ainda — escolha o destino de uma página solta aqui embaixo pra criar o primeiro caminho.
          </div>

          <!-- cada funil: trilha horizontal com a conversão de cada elo -->
          <div v-for="f in funnels" :key="f.key" class="mb-4 overflow-x-auto pb-2">
            <div class="flex items-stretch gap-0 min-w-max">
              <template v-for="(step, si) in f.steps" :key="step.id">
                <!-- nó -->
                <div class="rounded-xl border border-n-weak bg-n-solid-1 p-3 w-56 flex-shrink-0">
                  <div class="flex items-center gap-1.5 mb-1">
                    <span class="text-sm">{{ step.emoji || '👁️' }}</span>
                    <p class="text-xs font-bold text-n-slate-12 truncate flex-1">{{ step.title }}</p>
                  </div>
                  <p class="text-[10px] text-n-slate-9 truncate mb-1.5">/{{ step.slug }}</p>
                  <p class="text-[11px] text-n-slate-11">
                    {{ step.views }} visitas
                    <template v-if="step.views_from_previous !== null"> · <b>{{ step.views_from_previous }}</b> vindas do elo anterior</template>
                  </p>
                  <p class="text-[11px] text-n-slate-10 mt-0.5">
                    💬 {{ step.cta_clicks }} WhatsApp <b :style="{ color: step.cta_rate >= 10 ? '#047857' : '#64748B' }">({{ fmtPct(step.cta_rate) }})</b>
                  </p>
                  <!-- reapontar o elo -->
                  <select
                    class="mt-2 w-full h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[10px] text-n-slate-11"
                    :disabled="savingLink === step.id"
                    :value="step.next_page_id || ''"
                    @change="setNext(step, $event.target.value)"
                  >
                    <option value="">➡ termina no WhatsApp</option>
                    <option v-for="c in linkCandidates(step)" :key="c.id" :value="c.id">➡ {{ c.title }}</option>
                  </select>
                </div>
                <!-- seta com a conversão do elo -->
                <div v-if="si < f.steps.length - 1" class="flex flex-col items-center justify-center px-1.5 flex-shrink-0">
                  <span class="text-[10px] font-bold" :style="{ color: step.next_rate >= 10 ? '#047857' : '#94A3B8' }">
                    {{ step.next_clicks }} seguiram
                  </span>
                  <span class="i-lucide-arrow-right text-lg" :style="{ color: step.next_rate >= 10 ? '#047857' : '#94A3B8' }" />
                  <span class="text-[10px]" :style="{ color: step.next_rate >= 10 ? '#047857' : '#94A3B8' }">{{ fmtPct(step.next_rate) }}</span>
                </div>
              </template>
              <!-- fim da trilha -->
              <div class="flex items-center pl-1.5 flex-shrink-0">
                <span class="rounded-xl border border-dashed border-n-weak px-3 py-2 text-[11px] text-n-slate-10">💬 WhatsApp</span>
              </div>
            </div>
          </div>

          <!-- páginas soltas: criar novo caminho -->
          <div v-if="loosePages.length" class="pt-3 border-t border-n-weak">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-2">Páginas publicadas fora de funil</p>
            <div class="space-y-1.5">
              <div v-for="p in loosePages" :key="p.id" class="flex items-center gap-2 flex-wrap rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2">
                <span class="text-sm">{{ p.emoji || '👁️' }}</span>
                <span class="text-xs font-semibold text-n-slate-12 flex-1 min-w-[140px] truncate">{{ p.title }}</span>
                <span class="text-[11px] text-n-slate-10">{{ p.views_count }} visitas</span>
                <select
                  class="h-7 rounded-lg border border-n-weak bg-n-solid-2 px-1.5 text-[10px] text-n-slate-11"
                  style="width: 13rem"
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
        </div>
      </template>
    </div>
  </div>
</template>
