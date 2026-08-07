<script setup>
// DASHBOARD GOOGLE (Ads + GA4) — 06/08, repaginado:
//  • régua de período padrão (Hoje/Ontem/7 dias/Mês/Ano/Personalizado);
//  • PALAVRAS-CHAVE, termos de pesquisa e campanhas com cliques/custo/CPC
//    lidos do GA4 (conta de serviço — sem developer token do Ads);
//  • funil DO TERMO À CIRURGIA: leads carimbados nas páginas (utm_term)
//    cruzados com consultas agendadas/realizadas e cirurgias fechadas.
import { ref, computed, onMounted, watch } from 'vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const route = useRoute();
const router = useRouter();
const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'month', from: '', to: '' });

const load = async () => {
  isLoading.value = true;
  try {
    const params = { preset: period.value.preset };
    if (period.value.preset === 'custom') {
      params.from = period.value.from;
      params.to = period.value.to;
    }
    const { data: payload } = await CrmAPI.getGoogleDashboard(params);
    data.value = payload;
  } catch {
    data.value = { configured: false, series: [], totals_by_event: {}, automations: [] };
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(period, load, { deep: true });

const maxDay = computed(() => Math.max(1, ...(data.value?.series || []).map(d => d.total)));
const totalSent = computed(() => (data.value?.series || []).reduce((s, d) => s + d.total, 0));
const barTitle = d => {
  const date = new Date(`${d.date}T12:00:00`).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  const parts = Object.entries(d.by_event || {}).map(([e, n]) => `${e}: ${n}`).join(' · ');
  return `${date}: ${d.total} conversão(ões)${parts ? ` — ${parts}` : ''}`;
};
const goIntegrations = () => router.push(frontendURL(`accounts/${route.params.accountId}/crm-integrations`));

const fmtMoney = v =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');

// ── Tabelas do GA4: palavras-chave | termos de pesquisa | campanhas ──
const GOOGLE_TABS = [
  { key: 'keywords', label: 'Palavras-chave', hint: 'a palavra que você COMPROU no Google Ads' },
  { key: 'queries', label: 'Termos de pesquisa', hint: 'o que a pessoa DIGITOU no Google' },
  { key: 'campaigns', label: 'Campanhas', hint: 'cliques e custo por campanha' },
];
const googleTab = ref('keywords');

const googleData = computed(() => data.value?.google_data || null);
const googleRows = computed(() => googleData.value?.[googleTab.value]?.rows ?? []);
const googleTabError = computed(() => googleData.value?.[googleTab.value]?.error || googleData.value?.error);
const maxClicks = computed(() => Math.max(1, ...googleRows.value.map(r => r.clicks)));

const cpc = r => (r.clicks > 0 ? r.cost / r.clicks : 0);

// ── Funil do termo (banco) ───────────────────────────────────────────
const funnel = computed(() => data.value?.keyword_funnel || { total_leads: 0, with_term: 0, rows: [] });
const maxFunnelLeads = computed(() => Math.max(1, ...funnel.value.rows.map(r => r.leads)));
const termHintNeeded = computed(
  () => funnel.value.total_leads >= 5 && funnel.value.with_term / Math.max(funnel.value.total_leads, 1) < 0.3
);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #1E40AF, #34A853)">
          <span class="i-lucide-chart-column text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Google (Ads + GA4)</h1>
          <p class="text-xs text-n-slate-10">palavras que trazem paciente, conversões que ensinam o Google — tudo num lugar só</p>
        </div>
        <PeriodRuler v-model="period" />
      </div>

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- estado da integração -->
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-5">
          <div class="rounded-xl px-4 py-3 border" :class="data.configured ? 'border-emerald-500/40 bg-emerald-500/5' : 'border-amber-500/40 bg-amber-500/5'">
            <p class="text-[11px] font-medium text-n-slate-10">GA4 (Measurement Protocol)</p>
            <p class="text-sm font-bold" :style="{ color: data.configured ? '#047857' : '#B45309' }">
              {{ data.configured ? `Conectado (${data.measurement_id})` : 'Aguardando conexão' }}
            </p>
            <button v-if="!data.configured" class="text-[11px] underline decoration-dotted text-n-slate-10 hover:text-n-brand mt-1" @click="goIntegrations">
              conectar em Integrações → Google
            </button>
          </div>
          <DashKpi
            compact
            label="Conversões enviadas (período)"
            :value="totalSent"
            from="#1E40AF"
            to="#3B82F6"
          />
          <div class="rounded-xl px-4 py-3 border" :class="data.insights_configured ? 'border-emerald-500/40 bg-emerald-500/5' : 'border-n-weak bg-n-solid-1'">
            <p class="text-[11px] font-medium text-n-slate-10">Cliques e custo (GA4 → Google Ads)</p>
            <p class="text-sm font-bold" :style="{ color: data.insights_configured ? '#047857' : '#64748B' }">
              {{ data.insights_configured ? 'Conta de serviço conectada' : 'Entra com a conta de serviço' }}
            </p>
            <button v-if="!data.insights_configured" class="text-[11px] underline decoration-dotted text-n-slate-10 hover:text-n-brand mt-1" @click="goIntegrations">
              preencher em Integrações → Google (propriedade GA4 + JSON)
            </button>
          </div>
        </div>

        <!-- ═══ PALAVRAS-CHAVE / TERMOS / CAMPANHAS (GA4) ═══ -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <div class="flex items-center gap-3 flex-wrap mb-1">
            <h2 class="text-sm font-bold text-n-slate-12">O que traz clique (e custo) no Google</h2>
            <div class="flex items-center gap-1 bg-n-solid-1 border border-n-weak rounded-xl p-0.5">
              <button
                v-for="tab in GOOGLE_TABS"
                :key="tab.key"
                class="h-7 px-2.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap"
                :class="googleTab === tab.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                :style="googleTab === tab.key ? { background: 'linear-gradient(135deg, #1E40AF, #34A853)' } : {}"
                :title="tab.hint"
                @click="googleTab = tab.key"
              >
                {{ tab.label }}
              </button>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-3">
            {{ GOOGLE_TABS.find(t => t.key === googleTab)?.hint }} — dados do GA4 vinculado ao Google Ads
          </p>

          <div v-if="!googleData || googleData.configured === false" class="text-xs text-amber-700 bg-amber-500/10 border border-amber-500/30 rounded-xl p-4">
            <p class="font-semibold mb-1">Falta conectar a leitura do GA4</p>
            <p>
              Em <b>Integrações → Google</b>, preencha a <b>propriedade do GA4</b> e o
              <b>JSON da conta de serviço</b> (a mesma usada no investimento automático).
              Com isso esta tela mostra cliques, custo e CPC por palavra-chave — sem precisar do developer token.
            </p>
          </div>
          <div v-else-if="googleTabError" class="text-xs text-red-600 bg-red-500/10 border border-red-500/30 rounded-xl p-4">
            <p class="font-semibold mb-1">Erro ao consultar o Google</p>
            <p>{{ googleTabError }}</p>
          </div>
          <div v-else-if="!googleRows.length" class="text-xs text-n-slate-9 py-4">
            Nenhum dado do Google Ads no período — confira se a conta do Ads está vinculada à propriedade do GA4.
          </div>
          <template v-else>
            <div class="grid text-[10px] text-n-slate-9 px-3 pb-1.5" style="grid-template-columns: minmax(0,2.2fr) 1fr 1fr 1fr 1fr 1fr">
              <span>{{ googleTab === 'campaigns' ? 'Campanha' : 'Termo' }}</span>
              <span class="text-right">Cliques</span>
              <span class="text-right">Custo</span>
              <span class="text-right">CPC</span>
              <span class="text-right">Sessões</span>
              <span class="text-right" title="Eventos-chave registrados no GA4 (inclui as conversões que o sistema envia)">Conversões</span>
            </div>
            <div class="space-y-1 max-h-96 overflow-y-auto">
              <div
                v-for="r in googleRows"
                :key="r.term"
                class="relative grid items-center px-3 py-1.5 rounded-lg bg-n-alpha-1 overflow-hidden"
                style="grid-template-columns: minmax(0,2.2fr) 1fr 1fr 1fr 1fr 1fr"
              >
                <!-- barra de participação nos cliques (fundo) -->
                <div
                  class="absolute inset-y-0 left-0 rounded-lg"
                  :style="{ width: `${(r.clicks / maxClicks) * 100}%`, background: 'rgba(30, 64, 175, 0.10)' }"
                />
                <span class="relative text-xs text-n-slate-12 truncate pr-2" :title="r.term">{{ r.term }}</span>
                <span class="relative text-xs text-right font-bold text-n-slate-12">{{ fmtNum(r.clicks) }}</span>
                <span class="relative text-xs text-right text-n-slate-11">{{ fmtMoney(r.cost) }}</span>
                <span class="relative text-xs text-right text-n-slate-11">{{ r.clicks ? fmtMoney(cpc(r)) : '—' }}</span>
                <span class="relative text-xs text-right text-n-slate-11">{{ fmtNum(r.sessions) }}</span>
                <span class="relative text-xs text-right font-semibold" :class="r.key_events > 0 ? 'text-emerald-600' : 'text-n-slate-10'">
                  {{ fmtNum(r.key_events) }}
                </span>
              </div>
            </div>
          </template>
        </div>

        <!-- ═══ DO TERMO À CIRURGIA (dados do sistema) ═══ -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-1">Do termo à cirurgia — o que vira paciente de verdade</h2>
          <p class="text-[11px] text-n-slate-9 mb-3">
            leads do Google carimbados nas páginas (Protocolo) e a jornada deles no sistema:
            {{ fmtNum(funnel.total_leads) }} lead(s) no período
          </p>

          <div v-if="termHintNeeded" class="text-[11px] text-amber-700 bg-amber-500/10 border border-amber-500/30 rounded-xl p-3 mb-3">
            <b>Dica:</b> a maioria dos leads chegou sem o termo de pesquisa. No Google Ads, adicione
            <code class="font-mono">utm_term={'{'}keyword{'}'}</code> ao modelo de acompanhamento
            da campanha — daí cada lead chega com a palavra que o trouxe.
          </div>

          <div v-if="!funnel.rows.length" class="text-xs text-n-slate-9 py-4">
            Nenhum lead do Google carimbado no período — os carimbos nascem nas páginas do sistema
            (Protocolo no WhatsApp) e nas campanhas com rastreamento.
          </div>
          <template v-else>
            <div class="grid text-[10px] text-n-slate-9 px-3 pb-1.5" style="grid-template-columns: minmax(0,2.2fr) 1fr 1fr 1fr 1fr 1.2fr">
              <span>Termo / campanha</span>
              <span class="text-right">Leads</span>
              <span class="text-right">Agendaram</span>
              <span class="text-right">Compareceram</span>
              <span class="text-right">Cirurgias</span>
              <span class="text-right">Receita</span>
            </div>
            <div class="space-y-1 max-h-96 overflow-y-auto">
              <div
                v-for="r in funnel.rows"
                :key="r.term"
                class="relative grid items-center px-3 py-1.5 rounded-lg bg-n-alpha-1 overflow-hidden"
                style="grid-template-columns: minmax(0,2.2fr) 1fr 1fr 1fr 1fr 1.2fr"
              >
                <div
                  class="absolute inset-y-0 left-0 rounded-lg"
                  :style="{ width: `${(r.leads / maxFunnelLeads) * 100}%`, background: 'rgba(52, 168, 83, 0.10)' }"
                />
                <span class="relative text-xs text-n-slate-12 truncate pr-2" :title="r.term">{{ r.term }}</span>
                <span class="relative text-xs text-right font-bold text-n-slate-12">{{ fmtNum(r.leads) }}</span>
                <span class="relative text-xs text-right text-n-slate-11">{{ fmtNum(r.booked) }}</span>
                <span class="relative text-xs text-right text-n-slate-11">{{ fmtNum(r.attended) }}</span>
                <span class="relative text-xs text-right font-semibold" :class="r.surgeries > 0 ? 'text-emerald-600' : 'text-n-slate-10'">
                  {{ fmtNum(r.surgeries) }}
                </span>
                <span class="relative text-xs text-right font-semibold" :class="r.revenue > 0 ? 'text-emerald-600' : 'text-n-slate-10'">
                  {{ r.revenue > 0 ? fmtMoney(r.revenue) : '—' }}
                </span>
              </div>
            </div>
          </template>
        </div>

        <!-- série diária das conversões enviadas -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <h2 class="text-sm font-bold text-n-slate-12 mb-3">Conversões enviadas por dia — no período</h2>
          <div class="flex items-end gap-[3px] h-24 rounded-lg bg-n-alpha-1 px-2 pt-2">
            <div
              v-for="d in data.series"
              :key="d.date"
              class="flex-1 rounded-t-sm"
              :style="{
                height: `${Math.max((d.total / maxDay) * 100, d.total ? 8 : 1)}%`,
                background: d.total ? 'linear-gradient(180deg, #34A853, #1E40AF)' : 'rgba(148,163,184,0.25)',
              }"
              :title="barTitle(d)"
            />
          </div>
          <div v-if="Object.keys(data.totals_by_event || {}).length" class="flex items-center gap-2 flex-wrap mt-3">
            <span
              v-for="(n, event) in data.totals_by_event"
              :key="event"
              class="text-[11px] px-2 py-0.5 rounded-full border border-n-weak bg-n-solid-1 text-n-slate-11"
            >
              {{ event }} · <b>{{ n }}</b>
            </span>
          </div>
          <p v-else class="text-xs text-n-slate-9 mt-2">nenhuma conversão enviada ainda — plugue a ação "Conversão do Google" nas colunas (consulta realizada, cirurgia realizada…).</p>
        </div>

        <!-- onde está plugado -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <h2 class="text-sm font-bold text-n-slate-12 mb-2">Colunas que enviam conversão</h2>
          <template v-if="data.automations?.length">
            <div v-for="(a, ai) in data.automations" :key="ai" class="flex items-center gap-2 text-xs text-n-slate-11 mb-1">
              <span class="i-lucide-columns-3 text-sm text-n-slate-9" />
              <b class="text-n-slate-12">{{ a.stage || 'coluna' }}</b>
              <span class="i-lucide-arrow-right text-xs text-n-slate-9" />
              <span>{{ a.event || 'evento' }}</span>
            </div>
          </template>
          <p v-else class="text-xs text-n-slate-9">
            Nenhuma coluna plugada — no CRM, adicione a automação "Conversão do Google" nas colunas-chave (Consulta Realizada, Cirurgia Realizada…).
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
