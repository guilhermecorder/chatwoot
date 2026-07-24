<script setup>
// 📈 RESULTADOS DE TRÁFEGO das Páginas (plano 100+ páginas com ads):
// de onde veio cada visita (Google Ads, Google orgânico/SEO, Meta, funil,
// direto) e o que ela virou — clique no WhatsApp, lead na caixa (via
// Protocolo), consulta agendada, cirurgia fechada e receita.
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const rows = ref([]);
const sources = ref({});
const protocol = ref({ minted: 0, matched: 0 });

// período: pílulas 7/30/90 dias (padrão 30)
const PERIODS = [
  { days: 7, label: '7 dias' },
  { days: 30, label: '30 dias' },
  { days: 90, label: '90 dias' },
];
const periodDays = ref(30);

// filtro de origem ('' = todas) — visual por pílulas coloridas
const SOURCE_META = {
  google_ads: { icon: '🎯', color: '#1A73E8' },
  google_organico: { icon: '🔍', color: '#188038' },
  meta_ads: { icon: '📣', color: '#7C3AED' },
  social: { icon: '📱', color: '#E1306C' },
  outros_ads: { icon: '💸', color: '#B45309' },
  funil: { icon: '🌪', color: '#0F5FA6' },
  busca: { icon: '🧭', color: '#0891B2' },
  direto: { icon: '🚪', color: '#64748B' },
};
const sourceFilter = ref('');

const load = async () => {
  isLoading.value = true;
  try {
    const since = new Date(Date.now() - periodDays.value * 86400000)
      .toISOString()
      .slice(0, 10);
    const { data } = await CrmAPI.getPagesReport({ since });
    rows.value = data.rows || [];
    sources.value = data.sources || {};
    protocol.value = data.protocol || { minted: 0, matched: 0 };
  } catch {
    useAlert('Não consegui carregar os resultados.');
  } finally {
    isLoading.value = false;
  }
};
const setPeriod = days => {
  periodDays.value = days;
  load();
};

// linha da página respeitando o filtro de origem
const rowFor = page => {
  if (!sourceFilter.value) return page;
  return page.sources[sourceFilter.value] || null;
};
const visibleRows = computed(() =>
  rows.value
    .map(p => ({ page: p, data: rowFor(p) }))
    .filter(r => r.data && (r.data.views || r.data.leads || r.data.cta))
);

// totais do recorte (todas as páginas, origem filtrada)
const totals = computed(() => {
  const sum = { views: 0, cta: 0, leads: 0, booked: 0, conversions: 0, revenue: 0 };
  visibleRows.value.forEach(({ data }) => {
    Object.keys(sum).forEach(k => {
      sum[k] += data[k] || 0;
    });
  });
  return sum;
});

// participação de cada origem no total de visitas (pro donut de pílulas)
const sourceTotals = computed(() => {
  const acc = {};
  rows.value.forEach(p => {
    Object.entries(p.sources || {}).forEach(([src, d]) => {
      acc[src] = acc[src] || { views: 0, leads: 0 };
      acc[src].views += d.views || 0;
      acc[src].leads += d.leads || 0;
    });
  });
  return acc;
});

const fmtMoney = v =>
  Number(v || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const pct = (a, b) => (b ? `${Math.round((a / b) * 100)}%` : '—');

// campanhas da página (drill do clique) — ordena por leads/visitas
const expandedId = ref(null);
const rowKey = p => p.page_id ?? 'hub'; // hub = linha sem página
const campaignsOf = page =>
  Object.entries(page.campaigns || {}).sort(
    (a, b) => b[1].leads - a[1].leads || b[1].views - a[1].views
  );
const sourcesOf = page =>
  Object.entries(page.sources || {}).sort((a, b) => b[1].views - a[1].views);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full overflow-auto bg-n-background p-4 md:p-6">
    <!-- cabeçalho da família Páginas -->
    <div class="flex items-center gap-3 mb-1 flex-wrap">
      <span class="text-2xl">📈</span>
      <div>
        <h1 class="text-lg font-bold text-n-slate-12">Resultados de tráfego</h1>
        <p class="text-[12px] text-n-slate-10">
          De onde veio cada visita — e o que ela virou: clique, lead, consulta, cirurgia.
        </p>
      </div>
      <div class="flex-1" />
      <!-- pílulas de período -->
      <div class="flex items-center gap-1.5">
        <button
          v-for="p in PERIODS"
          :key="p.days"
          class="px-3 h-8 rounded-full border text-[11px] font-semibold transition-colors"
          :class="periodDays === p.days ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
          :style="periodDays === p.days ? { background: 'linear-gradient(135deg, #0F5FA6, #1E7FBF)' } : {}"
          @click="setPeriod(p.days)"
        >
          {{ p.label }}
        </button>
      </div>
    </div>

    <SkeletonScreen v-if="isLoading" />

    <template v-else>
      <!-- pílulas de ORIGEM (com participação) -->
      <div class="flex items-center gap-1.5 mt-3 mb-4 flex-wrap">
        <button
          class="px-3 h-8 rounded-full border text-[11px] font-semibold"
          :class="sourceFilter === '' ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
          :style="sourceFilter === '' ? { background: 'linear-gradient(135deg, #152C61, #0F5FA6)' } : {}"
          @click="sourceFilter = ''"
        >
          Todas as origens
        </button>
        <button
          v-for="(label, src) in sources"
          :key="src"
          class="px-3 h-8 rounded-full border text-[11px] font-semibold flex items-center gap-1.5"
          :class="sourceFilter === src ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
          :style="sourceFilter === src ? { background: SOURCE_META[src]?.color || '#64748B' } : {}"
          @click="sourceFilter = sourceFilter === src ? '' : src"
        >
          {{ SOURCE_META[src]?.icon }} {{ label }}
          <span
            v-if="sourceTotals[src]"
            class="px-1.5 rounded-full text-[10px] font-bold"
            :class="sourceFilter === src ? 'bg-white/25' : 'bg-n-alpha-2'"
          >
            {{ sourceTotals[src].views }}
          </span>
        </button>
      </div>

      <!-- KPIs do recorte -->
      <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3 mb-4">
        <DashKpi label="Visitas" :value="totals.views" from="#0F5FA6" to="#1E7FBF" compact />
        <DashKpi label="Cliques WhatsApp" :value="totals.cta" :sub="pct(totals.cta, totals.views) + ' das visitas'" from="#047857" to="#10B981" compact />
        <DashKpi label="Leads na caixa" :value="totals.leads" :sub="protocol.minted ? `${protocol.matched} de ${protocol.minted} protocolos casaram` : 'via Protocolo'" from="#B8860B" to="#D4AF37" compact />
        <DashKpi label="Agendaram consulta" :value="totals.booked" :sub="pct(totals.booked, totals.leads) + ' dos leads'" from="#0284C7" to="#38BDF8" compact />
        <DashKpi label="Cirurgias" :value="totals.conversions" :sub="pct(totals.conversions, totals.leads) + ' dos leads'" from="#7C3AED" to="#A78BFA" compact />
        <DashKpi label="Receita" :value="fmtMoney(totals.revenue)" from="#152C61" to="#0F5FA6" compact />
      </div>

      <!-- por página -->
      <div v-if="!visibleRows.length" class="rounded-xl border border-n-weak p-8 text-center text-[13px] text-n-slate-10">
        Nenhum movimento nesse recorte ainda. Assim que as páginas receberem visitas
        (anúncio, Google ou funil), os números aparecem aqui.
      </div>

      <div
        v-for="{ page, data } in visibleRows"
        :key="page.page_id ?? 'hub'"
        class="rounded-xl border border-n-weak bg-n-solid-1 mb-2 overflow-hidden"
      >
        <button
          class="w-full flex items-center gap-3 p-3 text-left hover:bg-n-alpha-1 transition-colors"
          @click="expandedId = expandedId === rowKey(page) ? null : rowKey(page)"
        >
          <span class="text-xl shrink-0">{{ page.emoji || '📄' }}</span>
          <div class="min-w-0">
            <p class="text-[13px] font-bold text-n-slate-12 truncate">{{ page.title }}</p>
            <p class="text-[11px] text-n-slate-10 truncate">{{ page.page_id ? `/${page.slug}` : 'raiz do domínio' }}</p>
          </div>
          <span
            v-if="page.status !== 'published'"
            class="px-2 h-5 inline-flex items-center rounded-full bg-n-alpha-2 text-[10px] font-bold text-n-slate-11 shrink-0"
          >
            rascunho
          </span>
          <div class="flex-1" />
          <div class="flex items-center gap-4 shrink-0 text-right">
            <div><p class="text-[14px] font-bold text-n-slate-12">{{ data.views }}</p><p class="text-[10px] text-n-slate-10">visitas</p></div>
            <div><p class="text-[14px] font-bold" style="color:#10B981">{{ data.cta }}</p><p class="text-[10px] text-n-slate-10">WhatsApp</p></div>
            <div><p class="text-[14px] font-bold" style="color:#D4AF37">{{ data.leads }}</p><p class="text-[10px] text-n-slate-10">leads</p></div>
            <div class="hidden md:block"><p class="text-[14px] font-bold" style="color:#38BDF8">{{ data.booked }}</p><p class="text-[10px] text-n-slate-10">agendaram</p></div>
            <div class="hidden md:block"><p class="text-[14px] font-bold" style="color:#7C3AED">{{ data.conversions }}</p><p class="text-[10px] text-n-slate-10">cirurgias</p></div>
            <div class="hidden lg:block min-w-[80px]"><p class="text-[14px] font-bold" style="color:#152C61">{{ fmtMoney(data.revenue) }}</p><p class="text-[10px] text-n-slate-10">receita</p></div>
          </div>
          <span :class="expandedId === rowKey(page) ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="text-n-slate-10 shrink-0" />
        </button>

        <!-- drill: origens e campanhas da página -->
        <div v-if="expandedId === rowKey(page)" class="border-t border-n-weak p-3 bg-n-solid-2">
          <p class="text-[11px] font-semibold text-n-slate-12 mb-1.5">Por origem</p>
          <div class="flex gap-1.5 flex-wrap mb-3">
            <span
              v-for="[src, d] in sourcesOf(page)"
              :key="src"
              class="px-2.5 h-7 inline-flex items-center gap-1.5 rounded-full text-[11px] font-semibold text-white"
              :style="{ background: SOURCE_META[src]?.color || '#64748B' }"
            >
              {{ SOURCE_META[src]?.icon }} {{ sources[src] || src }}:
              {{ d.views }} visitas · {{ d.cta }} cliques · {{ d.leads }} leads
              <template v-if="d.conversions"> · {{ d.conversions }} 🏆</template>
            </span>
          </div>
          <template v-if="campaignsOf(page).length">
            <p class="text-[11px] font-semibold text-n-slate-12 mb-1.5">Por campanha</p>
            <div class="flex gap-1.5 flex-wrap">
              <span
                v-for="[name, d] in campaignsOf(page)"
                :key="name"
                class="px-2.5 h-7 inline-flex items-center gap-1.5 rounded-full border border-n-weak text-[11px] font-medium text-n-slate-11"
              >
                🏷 {{ name }}: {{ d.views }} visitas · {{ d.leads }} leads
                <template v-if="d.revenue"> · {{ fmtMoney(d.revenue) }}</template>
              </span>
            </div>
          </template>
          <p v-else class="text-[10px] text-n-slate-9">
            Sem campanhas nomeadas ainda — use utm_campaign nos anúncios pra ver o quebra-a-quebra aqui.
          </p>
        </div>
      </div>

      <!-- rodapé honesto: como o número nasce -->
      <p class="text-[10px] text-n-slate-9 mt-3">
        Leads = pacientes que chegaram na caixa com o Protocolo da página (quem apaga o texto do
        WhatsApp não entra na conta — {{ protocol.matched }} de {{ protocol.minted }} casaram no período).
        Cirurgias e receita seguem a mesma régua do relatório de Anúncios.
      </p>
    </template>
  </div>
</template>
