<script setup>
// CENTRAL DE TESTES A/B: todos os testes num lugar só — quem está no ar,
// o placar de cada variação e o líder. Hoje testa PÁGINAS (headline/
// subtítulo/botão no mesmo endereço); formulários e campanhas entram nas
// próximas rodadas, no mesmo padrão.
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const route = useRoute();
const router = useRouter();
const isLoading = ref(true);
const pages = ref([]);

const load = async () => {
  try {
    const { data } = await CrmAPI.getPagesDashboard();
    pages.value = data.pages || [];
  } catch {
    useAlert('Não consegui carregar os testes.');
  } finally {
    isLoading.value = false;
  }
};

const rowsFor = page => {
  const results = page.ab_results || {};
  const variants = page.ab_variants || [];
  return Object.keys(results).map(key => {
    const t = results[key];
    const clicks = (t.cta || 0) + (t.next || 0);
    return {
      key,
      name: key === 'a' ? 'Original' : variants.find(v => v.key === key)?.name || `Variação ${key.toUpperCase()}`,
      active: key === 'a' || !!variants.find(v => v.key === key)?.active,
      views: t.view || 0,
      clicks,
      rate: t.view ? Math.round((clicks / t.view) * 100) : null,
    };
  });
};
const leaderOf = page => {
  const rows = rowsFor(page).filter(r => r.rate !== null && r.views >= 10);
  if (rows.length < 2) return null;
  return [...rows].sort((a, b) => b.rate - a.rate)[0];
};

const running = computed(() => pages.value.filter(p => p.ab_running));
const paused = computed(() => pages.value.filter(p => !p.ab_running && (p.ab_variants || []).length));
const candidates = computed(() => pages.value.filter(p => !(p.ab_variants || []).length && p.status === 'published'));

const openEditor = () => router.push(frontendURL(`accounts/${route.params.accountId}/pages`));
const fmtPct = v => (v === null || v === undefined ? '—' : `${v}%`);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-4xl mx-auto w-full p-4 sm:p-8">
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
          <span class="i-lucide-flask-conical text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Testes A/B</h1>
          <p class="text-xs text-n-slate-10">todos os testes num lugar só — o placar decide, não o achismo · páginas hoje; formulários e campanhas em breve</p>
        </div>
      </div>

      <SkeletonScreen v-if="isLoading" variant="list" />

      <template v-else>
        <!-- no ar -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2">
            <span class="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" /> No ar agora ({{ running.length }})
          </h2>
          <div v-if="!running.length" class="text-xs text-n-slate-9">Nenhum teste rodando — escolha uma página aqui embaixo e crie a primeira variação.</div>
          <div v-for="p in running" :key="p.id" class="rounded-xl border border-n-weak bg-n-solid-1 p-3 mb-2">
            <div class="flex items-center gap-2 flex-wrap mb-2">
              <span class="text-base">{{ p.emoji || '👁️' }}</span>
              <p class="text-xs font-bold text-n-slate-12 flex-1 min-w-[140px] truncate">{{ p.title }}</p>
              <button class="text-[11px] text-n-slate-10 hover:text-n-brand underline decoration-dotted" @click="openEditor">
                editar variações
              </button>
            </div>
            <div
              v-for="r in rowsFor(p)"
              :key="r.key"
              class="flex items-center gap-2 flex-wrap rounded-lg px-2.5 py-1.5 mb-1 text-[11px]"
              :class="leaderOf(p)?.key === r.key ? 'bg-emerald-500/10' : 'bg-n-alpha-1'"
            >
              <b class="uppercase w-4 text-n-slate-12">{{ r.key }}</b>
              <span class="text-n-slate-11 flex-1 min-w-[100px] truncate">{{ r.name }}</span>
              <span v-if="!r.active" class="text-[10px] px-1.5 rounded bg-n-alpha-2 text-n-slate-10">pausada</span>
              <span class="text-n-slate-10">{{ r.views }} visitas</span>
              <span class="text-n-slate-10">{{ r.clicks }} cliques</span>
              <b :style="{ color: r.rate >= 10 ? '#047857' : '#64748B' }">{{ fmtPct(r.rate) }}</b>
              <span v-if="leaderOf(p)?.key === r.key" class="text-[10px] font-bold px-1.5 py-0.5 rounded-full" style="background: rgba(16,185,129,0.15); color: #047857">liderando</span>
            </div>
          </div>
        </div>

        <!-- pausados -->
        <div v-if="paused.length" class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-2">Com variações pausadas ({{ paused.length }})</h2>
          <div v-for="p in paused" :key="p.id" class="flex items-center gap-2 flex-wrap rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 mb-1.5">
            <span class="text-sm">{{ p.emoji || '👁️' }}</span>
            <p class="text-xs font-semibold text-n-slate-12 flex-1 min-w-[140px] truncate">{{ p.title }}</p>
            <span class="text-[11px] text-n-slate-10">{{ (p.ab_variants || []).length }} variação(ões) prontas</span>
            <button class="text-[11px] text-n-slate-10 hover:text-n-brand underline decoration-dotted" @click="openEditor">ativar no editor</button>
          </div>
        </div>

        <!-- candidatas -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1">Páginas publicadas sem teste ({{ candidates.length }})</h2>
          <p class="text-[11px] text-n-slate-10 mb-3">as com mais visitas rendem o teste mais rápido — crie a variação no editor da página</p>
          <div v-for="p in [...candidates].sort((a, b) => b.views_count - a.views_count)" :key="p.id" class="flex items-center gap-2 flex-wrap rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 mb-1.5">
            <span class="text-sm">{{ p.emoji || '👁️' }}</span>
            <p class="text-xs font-semibold text-n-slate-12 flex-1 min-w-[140px] truncate">{{ p.title }}</p>
            <span class="text-[11px] text-n-slate-10">{{ p.views_count }} visitas</span>
            <button
              class="px-2.5 h-7 rounded-lg text-[11px] font-bold text-white"
              style="background: linear-gradient(135deg, #B8860B, #D4A017)"
              @click="openEditor"
            >
              Criar variação
            </button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
