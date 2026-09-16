<script setup>
// DASHBOARD GOOGLE (Ads + GA4) — 06/08, repaginado; 14/09 gráficos do kit:
//  • régua de período padrão (Hoje/Ontem/7 dias/Mês/Ano/Personalizado);
//  • PALAVRAS-CHAVE, termos de pesquisa e campanhas com cliques/custo/CPC
//    lidos do GA4 (conta de serviço — sem developer token do Ads);
//  • funil DO TERMO À CIRURGIA: leads carimbados nas páginas (utm_term)
//    cruzados com consultas agendadas/realizadas e cirurgias fechadas;
//  • 14/09: as DUAS "conversões" explicadas na tela (enviadas pela CEVICO ×
//    eventos-chave do GA4), barras do kit (MiniBars/HBars/ShareBar) no lugar
//    das divs, e "como cada número é calculado" por extenso.
import { ref, computed, onMounted, watch } from 'vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexFromGrad } from 'dashboard/helper/cevicoPalettes';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const route = useRoute();
const router = useRouter();
const isLoading = ref(true);
const data = ref(null);
const period = ref({ preset: 'month', from: '', to: '' });

// 🍎 formato novo (rodada 163): kit "iMac G3 + vidro" com a paleta desta
// página (o admin escolhe pelo chip do banner; cada bloco pode ter a sua)
const pal = useCevicoPalette({
  scope: 'report:google',
  blocks: [
    {
      id: 'integracao',
      label: 'Estado da integração',
      icon: 'i-lucide-plug-zap',
    },
    { id: 'palavras', label: 'Palavras e campanhas', icon: 'i-lucide-search' },
    { id: 'funil', label: 'Do termo à cirurgia', icon: 'i-lucide-route' },
    { id: 'conversoes', label: 'Conversões por dia', icon: 'i-lucide-send' },
    { id: 'colunas', label: 'Colunas plugadas', icon: 'i-lucide-columns-3' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

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
    data.value = {
      configured: false,
      series: [],
      totals_by_event: {},
      automations: [],
    };
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);
watch(period, load, { deep: true });

const fmtMoney = v =>
  'R$ ' +
  Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
const fmtMoneyShort = v =>
  'R$ ' + Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 0 });
const fmtNum = v => Number(v || 0).toLocaleString('pt-BR');
const pctOf = (part, whole) =>
  whole > 0 ? `${Math.round((part / whole) * 100)}%` : '—';

// ── conversões ENVIADAS (o que a CEVICO mandou pro Google) ──
const totalSent = computed(() =>
  (data.value?.series || []).reduce((s, d) => s + d.total, 0)
);
const dailyValues = computed(() =>
  (data.value?.series || []).map(d => d.total)
);
const dailyLabels = computed(() =>
  (data.value?.series || []).map(d =>
    new Date(`${d.date}T12:00:00`).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
    })
  )
);
const eventSlices = computed(() =>
  Object.entries(data.value?.totals_by_event || {}).map(([label, value]) => ({
    label,
    value,
  }))
);
const goIntegrations = () =>
  router.push(
    frontendURL(`accounts/${route.params.accountId}/crm-integrations`)
  );

// ── Tabelas do GA4: palavras-chave | termos de pesquisa | campanhas ──
const GOOGLE_TABS = [
  {
    key: 'keywords',
    label: 'Palavras-chave',
    hint: 'a palavra que você COMPROU no Google Ads',
  },
  {
    key: 'queries',
    label: 'Termos de pesquisa',
    hint: 'o que a pessoa DIGITOU no Google',
  },
  {
    key: 'campaigns',
    label: 'Campanhas',
    hint: 'cliques e custo por campanha',
  },
];
const googleTab = ref('keywords');

const googleData = computed(() => data.value?.google_data || null);
const googleRows = computed(
  () => googleData.value?.[googleTab.value]?.rows ?? []
);
const googleTabError = computed(
  () => googleData.value?.[googleTab.value]?.error || googleData.value?.error
);
const maxClicks = computed(() =>
  Math.max(1, ...googleRows.value.map(r => r.clicks))
);
const cpc = r => (r.clicks > 0 ? r.cost / r.clicks : 0);
const googleTotals = computed(() =>
  googleRows.value.reduce(
    (acc, r) => ({
      clicks: acc.clicks + (r.clicks || 0),
      cost: acc.cost + (r.cost || 0),
      sessions: acc.sessions + (r.sessions || 0),
      key_events: acc.key_events + (r.key_events || 0),
    }),
    { clicks: 0, cost: 0, sessions: 0, key_events: 0 }
  )
);
// gráfico do bloco: os 8 termos que mais custaram × o que trouxeram de clique
const costRows = computed(() =>
  [...googleRows.value]
    .sort((a, b) => (b.cost || 0) - (a.cost || 0))
    .slice(0, 8)
    .map(r => ({
      label: r.term,
      values: [r.cost],
      hint: `${fmtNum(r.clicks)} cliques · CPC ${fmtMoney(cpc(r))}`,
    }))
);

// ── Funil do termo (banco) ───────────────────────────────────────────
const funnel = computed(
  () => data.value?.keyword_funnel || { total_leads: 0, with_term: 0, rows: [] }
);
const maxFunnelLeads = computed(() =>
  Math.max(1, ...funnel.value.rows.map(r => r.leads))
);
const termHintNeeded = computed(
  () =>
    funnel.value.total_leads >= 5 &&
    funnel.value.with_term / Math.max(funnel.value.total_leads, 1) < 0.3
);
const funnelTotals = computed(() =>
  funnel.value.rows.reduce(
    (acc, r) => ({
      leads: acc.leads + r.leads,
      booked: acc.booked + r.booked,
      attended: acc.attended + r.attended,
      surgeries: acc.surgeries + r.surgeries,
      revenue: acc.revenue + r.revenue,
    }),
    { leads: 0, booked: 0, attended: 0, surgeries: 0, revenue: 0 }
  )
);
// as 4 etapas do funil, lado a lado (barras da mesma escala = leads)
const funnelSteps = computed(() => {
  const t = funnelTotals.value;
  return [
    { label: 'Leads do Google', values: [t.leads] },
    {
      label: 'Agendaram consulta',
      values: [t.booked],
      hint: pctOf(t.booked, t.leads),
    },
    {
      label: 'Compareceram',
      values: [t.attended],
      hint: pctOf(t.attended, t.leads),
    },
    {
      label: 'Fecharam cirurgia',
      values: [t.surgeries],
      hint: pctOf(t.surgeries, t.leads),
    },
  ];
});
const greenHex = '#059669';
const stepColorFor = i =>
  [
    blockFamily('funil')[0],
    blockFamily('funil')[1],
    blockFamily('funil')[2],
    greenHex,
  ][i];

// como cada número nasce — por extenso (padrão do painel da Meta)
const FORMULAS = [
  {
    label: 'Conversões enviadas',
    text: 'eventos que a CEVICO mandou ao GA4 quando o card entrou numa coluna plugada',
  },
  {
    label: 'Eventos-chave (GA4)',
    text: 'tudo que o GA4 marcou como conversão nas sessões daquele termo — inclui os nossos e os do site',
  },
  {
    label: 'Cliques · Custo · CPC',
    text: 'do Google Ads, lidos pelo GA4 vinculado · CPC = custo ÷ cliques',
  },
  { label: 'Sessões', text: 'visitas ao site vindas daquele termo (GA4)' },
  {
    label: 'Leads',
    text: 'contatos que chegaram carimbados como Google nas páginas (utm_term)',
  },
  {
    label: 'Agendaram · Compareceram',
    text: 'consultas criadas / com presença na Agenda para esses leads',
  },
  {
    label: 'Cirurgias · Receita',
    text: 'cards que passaram por uma coluna de cirurgia (sem as de indicação) e a soma do valor deles',
  },
];
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- banner de vidro na paleta da página (rodada 163) -->
      <CevicoHero
        :pal="pal"
        title="Google (Ads + GA4)"
        subtitle="palavras que trazem paciente, conversões que ensinam o Google — tudo num lugar só"
        icon="i-lucide-chart-column"
      />

      <!-- Período (régua padrão CEVICO) -->
      <PeriodRuler v-model="period" glass class="mb-6" />

      <div v-if="isLoading" class="flex justify-center py-16">
        <Spinner :size="32" class="text-n-brand" />
      </div>

      <template v-else>
        <!-- estado da integração (verde = conectado · âmbar = aguardando) -->
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('integracao')">
          <div class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-plug-zap text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Estado da integração
            </h2>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div
              class="cv-sub px-4 py-3"
              :class="data.configured ? 'cv-green' : 'cv-amber'"
            >
              <p class="text-[11px] font-medium text-n-slate-10">
                GA4 (Measurement Protocol) — a CEVICO ENVIA
              </p>
              <p
                class="text-sm font-bold"
                :style="{ color: data.configured ? '#047857' : '#B45309' }"
              >
                {{
                  data.configured
                    ? `Conectado (${data.measurement_id})`
                    : 'Aguardando conexão'
                }}
              </p>
              <button
                v-if="!data.configured"
                class="text-[11px] underline decoration-dotted text-n-slate-10 hover:text-n-brand mt-1"
                @click="goIntegrations"
              >
                conectar em Integrações → Google
              </button>
            </div>
            <DashKpi
              compact
              glass
              label="Conversões enviadas ao Google (período)"
              :value="totalSent"
              sub="eventos que a CEVICO mandou pelas colunas plugadas"
              :grad="blockFamily('integracao')[1]"
            />
            <div
              class="cv-sub px-4 py-3"
              :class="data.insights_configured ? 'cv-green' : 'cv-amber'"
            >
              <p class="text-[11px] font-medium text-n-slate-10">
                GA4 → Google Ads — a CEVICO LÊ
              </p>
              <p
                class="text-sm font-bold"
                :style="{
                  color: data.insights_configured ? '#047857' : '#B45309',
                }"
              >
                {{
                  data.insights_configured
                    ? 'Conta de serviço conectada'
                    : 'Entra com a conta de serviço'
                }}
              </p>
              <button
                v-if="!data.insights_configured"
                class="text-[11px] underline decoration-dotted text-n-slate-10 hover:text-n-brand mt-1"
                @click="goIntegrations"
              >
                preencher em Integrações → Google (propriedade GA4 + JSON)
              </button>
            </div>
          </div>
        </div>

        <!-- as DUAS "conversões" desta tela — não são a mesma coisa (14/09) -->
        <div
          class="cv-block cv-strip px-4 py-3.5 mb-6"
          :style="blockVars('integracao')"
        >
          <div class="flex items-center gap-2 mb-2">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-info text-xs"/></span>
            <p class="text-[11px] font-bold text-n-slate-11">
              Tem duas "conversões" nesta tela — e elas não deveriam bater
            </p>
          </div>
          <div
            class="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-2 text-[11px] text-n-slate-10 leading-relaxed"
          >
            <p>
              <b class="text-n-slate-12">Conversões enviadas ({{ fmtNum(totalSent) }})</b>
              = o que a <b>CEVICO mandou</b> para o Google: um evento por card
              que entrou numa coluna plugada (consulta realizada, cirurgia
              realizada…). É o dado que <b>ensina o Google</b> quem é paciente
              de verdade.
            </p>
            <p>
              <b class="text-n-slate-12">Eventos-chave (GA4)</b> na tabela =
              <b>tudo</b> que o GA4 marcou como conversão nas visitas daquele
              termo: clique no WhatsApp, formulário do site, <i>mais</i> os
              nossos eventos. Conta por sessão e no dia do clique — por isso é
              sempre maior. Para bater, deixe como evento-chave no GA4 só os
              eventos que a CEVICO envia.
            </p>
          </div>
        </div>

        <!-- ═══ PALAVRAS-CHAVE / TERMOS / CAMPANHAS (GA4) ═══ -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('palavras')">
          <div class="flex items-center gap-3 flex-wrap mb-1">
            <span class="cv-icon"><span class="i-lucide-search text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              O que traz clique (e custo) no Google
            </h2>
            <div class="cv-seg cv-seg-sm">
              <button
                v-for="tab in GOOGLE_TABS"
                :key="tab.key"
                class="cv-seg-item"
                :class="googleTab === tab.key ? 'cv-seg-on' : ''"
                :title="tab.hint"
                @click="googleTab = tab.key"
              >
                {{ tab.label }}
              </button>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            {{ GOOGLE_TABS.find(t => t.key === googleTab)?.hint }} — dados do
            GA4 vinculado ao Google Ads
          </p>

          <div
            v-if="!googleData || googleData.configured === false"
            class="cv-sub cv-amber text-xs text-n-slate-11 p-4"
          >
            <p class="font-semibold text-n-slate-12 mb-1">
              Falta conectar a leitura do GA4
            </p>
            <p>
              Em <b>Integrações → Google</b>, preencha a
              <b>propriedade do GA4</b> e o <b>JSON da conta de serviço</b> (a
              mesma usada no investimento automático). Com isso esta tela mostra
              cliques, custo e CPC por palavra-chave — sem precisar do developer
              token.
            </p>
          </div>
          <div
            v-else-if="googleTabError"
            class="cv-sub cv-red text-xs text-n-slate-11 p-4"
          >
            <p class="font-semibold text-n-slate-12 mb-1">
              Erro ao consultar o Google
            </p>
            <p>{{ googleTabError }}</p>
          </div>
          <div
            v-else-if="!googleRows.length"
            class="text-xs text-n-slate-9 py-4"
          >
            Nenhum dado do Google Ads no período — confira se a conta do Ads
            está vinculada à propriedade do GA4.
          </div>
          <template v-else>
            <!-- resumo do bloco em 4 números -->
            <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mb-4">
              <div class="cv-stat text-center">
                <p class="text-[10px] text-n-slate-9">Cliques</p>
                <p class="text-base font-bold text-n-slate-12">
                  {{ fmtNum(googleTotals.clicks) }}
                </p>
              </div>
              <div class="cv-stat text-center">
                <p class="text-[10px] text-n-slate-9">Custo</p>
                <p class="text-base font-bold text-n-slate-12">
                  {{ fmtMoneyShort(googleTotals.cost) }}
                </p>
              </div>
              <div class="cv-stat text-center">
                <p class="text-[10px] text-n-slate-9">CPC médio</p>
                <p class="text-base font-bold text-n-slate-12">
                  {{
                    googleTotals.clicks
                      ? fmtMoney(googleTotals.cost / googleTotals.clicks)
                      : '—'
                  }}
                </p>
              </div>
              <div class="cv-stat text-center">
                <p class="text-[10px] text-n-slate-9">Eventos-chave (GA4)</p>
                <p class="text-base font-bold text-n-slate-12">
                  {{ fmtNum(googleTotals.key_events) }}
                </p>
              </div>
            </div>

            <div class="grid grid-cols-1 xl:grid-cols-5 gap-5">
              <!-- gráfico: onde o dinheiro foi (8 maiores custos) -->
              <div class="xl:col-span-2 cv-sub p-4">
                <p class="text-[11px] font-bold text-n-slate-11 mb-0.5">
                  Onde o dinheiro foi
                </p>
                <p class="text-[10px] text-n-slate-9 mb-3">
                  os {{ costRows.length }}
                  {{ googleTab === 'campaigns' ? 'campanhas' : 'termos' }} que
                  mais custaram
                </p>
                <HBars
                  :rows="costRows"
                  :series="[{ label: 'Custo', format: fmtMoneyShort }]"
                  :label-width="9"
                />
              </div>

              <!-- tabela: barra fina = participação nos cliques -->
              <div class="xl:col-span-3 min-w-0">
                <div
                  class="grid text-[10px] text-n-slate-9 px-2 pb-1.5"
                  style="
                    grid-template-columns: minmax(0, 2.4fr) repeat(
                        4,
                        minmax(0, 1fr)
                      );
                  "
                >
                  <span>{{
                    googleTab === 'campaigns' ? 'Campanha' : 'Termo'
                  }}</span>
                  <span class="text-right">Cliques</span>
                  <span class="text-right">Custo</span>
                  <span class="text-right">CPC</span>
                  <span
                    class="text-right"
                    title="Tudo que o GA4 marcou como conversão nas sessões deste termo (inclui os eventos que a CEVICO envia)"
                    >Ev.-chave</span>
                </div>
                <div
                  class="space-y-1 max-h-[26rem] overflow-y-auto pr-1"
                  style="scrollbar-width: thin"
                >
                  <div
                    v-for="r in googleRows"
                    :key="r.term"
                    class="grid items-center px-2 py-1.5 rounded-xl hover:bg-[rgb(var(--cv-rgb)/0.07)] transition-colors"
                    style="
                      grid-template-columns: minmax(0, 2.4fr) repeat(
                          4,
                          minmax(0, 1fr)
                        );
                    "
                    :title="`${r.term}: ${fmtNum(r.clicks)} cliques · ${fmtNum(r.sessions)} sessões · ${fmtNum(r.key_events)} eventos-chave`"
                  >
                    <div class="min-w-0 pr-3">
                      <p class="text-xs text-n-slate-12 truncate">
                        {{ r.term }}
                      </p>
                      <div
                        class="cv-track mt-1"
                        style="height: 5px; box-shadow: none"
                      >
                        <div
                          class="cv-fill"
                          :style="{
                            width: `${Math.max(1.5, (r.clicks / maxClicks) * 100)}%`,
                          }"
                        />
                      </div>
                    </div>
                    <span
                      class="text-xs text-right font-bold tabular-nums text-n-slate-12 whitespace-nowrap"
                      >{{ fmtNum(r.clicks) }}</span>
                    <span
                      class="text-xs text-right tabular-nums text-n-slate-11 whitespace-nowrap"
                      >{{ fmtMoneyShort(r.cost) }}</span>
                    <span
                      class="text-xs text-right tabular-nums text-n-slate-11 whitespace-nowrap"
                      >{{ r.clicks ? fmtMoney(cpc(r)) : '—' }}</span>
                    <span
                      class="text-xs text-right tabular-nums whitespace-nowrap inline-flex items-center justify-end gap-1"
                      :class="
                        r.key_events > 0
                          ? 'text-n-slate-12 font-semibold'
                          : 'text-n-slate-9'
                      "
                    >
                      <span
                        v-if="r.key_events > 0"
                        class="w-1.5 h-1.5 rounded-full"
                        :style="{ background: greenHex }"
                      />
                      {{ fmtNum(r.key_events) }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </template>
        </div>

        <!-- ═══ DO TERMO À CIRURGIA (dados do sistema) ═══ -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('funil')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-route text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Do termo à cirurgia — o que vira paciente de verdade
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            leads do Google carimbados nas páginas (Protocolo) e a jornada deles
            no sistema:
            {{ fmtNum(funnel.total_leads) }} lead(s) no período
          </p>

          <div
            v-if="termHintNeeded"
            class="cv-sub cv-amber text-[11px] text-n-slate-11 p-3 mb-3"
          >
            <b>Dica:</b> a maioria dos leads chegou sem o termo de pesquisa. No
            Google Ads, adicione
            <code class="font-mono">utm_term={'{'}keyword{'}'}</code> ao modelo
            de acompanhamento da campanha — daí cada lead chega com a palavra
            que o trouxe.
          </div>

          <div v-if="!funnel.rows.length" class="text-xs text-n-slate-9 py-4">
            Nenhum lead do Google carimbado no período — os carimbos nascem nas
            páginas do sistema (Protocolo no WhatsApp) e nas campanhas com
            rastreamento.
          </div>
          <template v-else>
            <div class="grid grid-cols-1 xl:grid-cols-5 gap-5">
              <!-- o funil em 4 barras (mesma escala) -->
              <div class="xl:col-span-2 cv-sub p-4">
                <p class="text-[11px] font-bold text-n-slate-11 mb-0.5">
                  A jornada de quem veio do Google
                </p>
                <p class="text-[10px] text-n-slate-9 mb-3">
                  de {{ fmtNum(funnelTotals.leads) }} leads,
                  {{ fmtNum(funnelTotals.surgeries) }} fecharam cirurgia ({{
                    pctOf(funnelTotals.surgeries, funnelTotals.leads)
                  }}) · {{ fmtMoneyShort(funnelTotals.revenue) }}
                </p>
                <HBars
                  :rows="
                    funnelSteps.map((s, i) => ({
                      ...s,
                      color: stepColorFor(i),
                    }))
                  "
                  :series="[{ label: 'pessoas', format: fmtNum }]"
                  :label-width="9"
                  :highlight-max="false"
                />
              </div>

              <!-- por termo -->
              <div class="xl:col-span-3 min-w-0">
                <div
                  class="grid text-[10px] text-n-slate-9 px-2 pb-1.5"
                  style="
                    grid-template-columns:
                      minmax(0, 2.2fr) repeat(4, minmax(0, 0.8fr))
                      minmax(0, 1.1fr);
                  "
                >
                  <span>Termo / campanha</span>
                  <span class="text-right">Leads</span>
                  <span class="text-right">Agend.</span>
                  <span class="text-right">Compar.</span>
                  <span class="text-right">Cirurg.</span>
                  <span class="text-right">Receita</span>
                </div>
                <div
                  class="space-y-1 max-h-[26rem] overflow-y-auto pr-1"
                  style="scrollbar-width: thin"
                >
                  <div
                    v-for="r in funnel.rows"
                    :key="r.term"
                    class="grid items-center px-2 py-1.5 rounded-xl hover:bg-[rgb(var(--cv-rgb)/0.07)] transition-colors"
                    style="
                      grid-template-columns:
                        minmax(0, 2.2fr) repeat(4, minmax(0, 0.8fr))
                        minmax(0, 1.1fr);
                    "
                    :title="`${r.term}: ${fmtNum(r.leads)} leads · ${fmtNum(r.booked)} agendaram · ${fmtNum(r.attended)} compareceram · ${fmtNum(r.surgeries)} cirurgias`"
                  >
                    <div class="min-w-0 pr-3">
                      <p class="text-xs text-n-slate-12 truncate">
                        {{ r.term }}
                      </p>
                      <div
                        class="cv-track mt-1"
                        style="height: 5px; box-shadow: none"
                      >
                        <div
                          class="cv-fill"
                          :style="{
                            width: `${Math.max(1.5, (r.leads / maxFunnelLeads) * 100)}%`,
                          }"
                        />
                      </div>
                    </div>
                    <span
                      class="text-xs text-right font-bold tabular-nums text-n-slate-12 whitespace-nowrap"
                      >{{ fmtNum(r.leads) }}</span>
                    <span
                      class="text-xs text-right tabular-nums text-n-slate-11 whitespace-nowrap"
                      >{{ fmtNum(r.booked) }}</span>
                    <span
                      class="text-xs text-right tabular-nums text-n-slate-11 whitespace-nowrap"
                      >{{ fmtNum(r.attended) }}</span>
                    <span
                      class="text-xs text-right tabular-nums whitespace-nowrap inline-flex items-center justify-end gap-1"
                      :class="
                        r.surgeries > 0
                          ? 'text-n-slate-12 font-semibold'
                          : 'text-n-slate-9'
                      "
                    >
                      <span
                        v-if="r.surgeries > 0"
                        class="w-1.5 h-1.5 rounded-full"
                        :style="{ background: greenHex }"
                      />
                      {{ fmtNum(r.surgeries) }}
                    </span>
                    <span
                      class="text-xs text-right tabular-nums whitespace-nowrap"
                      :class="
                        r.revenue > 0
                          ? 'text-n-slate-12 font-semibold'
                          : 'text-n-slate-9'
                      "
                    >
                      {{ r.revenue > 0 ? fmtMoneyShort(r.revenue) : '—' }}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </template>
        </div>

        <!-- série diária das conversões enviadas -->
        <div class="cv-block p-5 sm:p-6 mb-6" :style="blockVars('conversoes')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-send text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Conversões enviadas ao Google, dia a dia
            </h2>
          </div>
          <p class="text-[11px] text-n-slate-9 mb-4">
            {{ fmtNum(totalSent) }} evento(s) no período · passe o mouse (ou
            toque) numa barra para ver o dia
          </p>
          <div class="grid grid-cols-1 xl:grid-cols-5 gap-5">
            <div class="xl:col-span-3 cv-sub p-4 pb-2">
              <MiniBars
                :values="dailyValues"
                :labels="dailyLabels"
                :color="hexFromGrad(blockFamily('conversoes')[1]) || '#0F5FA6'"
                :height="150"
                :format="v => `${fmtNum(v)} conv.`"
              />
            </div>
            <div class="xl:col-span-2 cv-sub p-4">
              <p class="text-[11px] font-bold text-n-slate-11 mb-0.5">
                Por tipo de evento
              </p>
              <p class="text-[10px] text-n-slate-9 mb-3">
                o nome que cada coluna plugada envia
              </p>
              <ShareBar
                :items="eventSlices"
                :family="blockFamily('conversoes')"
                :format="fmtNum"
              />
              <p v-if="!eventSlices.length" class="text-[11px] text-n-slate-9">
                nenhuma conversão enviada ainda — plugue a ação "Conversão do
                Google" nas colunas (consulta realizada, cirurgia realizada…).
              </p>
            </div>
          </div>
        </div>

        <!-- onde está plugado -->
        <div class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('colunas')">
          <div class="flex items-center gap-2 mb-3 flex-wrap">
            <span class="cv-icon"><span class="i-lucide-columns-3 text-base"/></span>
            <h2 class="text-sm font-bold text-n-slate-12">
              Colunas que enviam conversão
            </h2>
          </div>
          <template v-if="data.automations?.length">
            <div class="flex flex-wrap gap-2">
              <div
                v-for="(a, ai) in data.automations"
                :key="ai"
                class="cv-row inline-flex items-center gap-2 text-xs text-n-slate-11 px-3 py-2"
              >
                <span
                  class="i-lucide-columns-3 text-sm"
                  style="color: var(--cv)"
                />
                <b class="text-n-slate-12">{{ a.stage || 'coluna' }}</b>
                <span class="i-lucide-arrow-right text-xs text-n-slate-9" />
                <span>{{ a.event || 'generate_lead' }}</span>
              </div>
            </div>
          </template>
          <p v-else class="text-xs text-n-slate-9">
            Nenhuma coluna plugada — no CRM, adicione a automação "Conversão do
            Google" nas colunas-chave (Consulta Realizada, Cirurgia Realizada…).
          </p>
        </div>

        <!-- Como cada número é calculado — por extenso, sem mistério -->
        <div
          class="cv-block cv-strip px-4 py-3 mb-6"
          :style="blockVars('colunas')"
        >
          <div class="flex items-center gap-2 mb-2">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-info text-xs"/></span>
            <p class="text-[11px] font-bold text-n-slate-11">
              Como cada número é calculado
            </p>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1">
            <p
              v-for="f in FORMULAS"
              :key="f.label"
              class="text-[11px] text-n-slate-10"
            >
              <span class="font-bold text-n-slate-11">{{ f.label }}</span> =
              {{ f.text }}
            </p>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
