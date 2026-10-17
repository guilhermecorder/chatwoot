<script setup>
// 📊 ANÁLISE DE PÁGINAS — refeita no formato do Meu Painel novo (16/10/2026:
// "deixar bem completo, estilo o ambiente atualizado do meu painel… organize
// indicadores primários, secundários e terciários, pra gente analisar").
//
// Mesmas peças da Visão geral do Meu Painel (guia arejado): cabeçalho na cor
// do dia, vitrine giratória, blocos com fileira de NÚMEROS + fileira de
// GRÁFICOS e o PAINEL LATERAL com a história de cada número. Os três níveis:
//   PRIMÁRIOS   o resultado que decide — leads, agendaram, cirurgias,
//               receita e visita → lead (bloco na cor do dia, 60%)
//   SECUNDÁRIOS o caminho que explica — visitas, clicam no WhatsApp, chegam
//               na caixa, agendam, leram até o fim (bloco de apoio, 30%)
//   TERCIÁRIOS  o que sustenta — Google, páginas no ar, testes A/B, funis
//               e pontos a melhorar (bloco neutro)
// Depois: página por página (Lista | Cards, cada uma abre a própria
// história) e o montador de funis de sempre.
//
// Os números do período vêm do mesmo relatório dos Resultados de tráfego
// (Cevico::TrafficReport, com a régua padrão e o período anterior para
// comparar); a série de 30 dias, a leitura, o A/B e os funis vêm do
// pages_dashboard. Filtro por categoria/palavra-chave = page_ids no servidor.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import FunnelSteps from 'dashboard/components-next/cevico/FunnelSteps.vue';
import AreaChart from 'dashboard/components-next/cevico/AreaChart.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import CvCabecalho from 'dashboard/components-next/cevico/guia/CvCabecalho.vue';
import CvVitrine from 'dashboard/components-next/cevico/guia/CvVitrine.vue';
import CvBloco from 'dashboard/components-next/cevico/guia/CvBloco.vue';
import CvIndicador from 'dashboard/components-next/cevico/guia/CvIndicador.vue';
import CvPainelLateral from 'dashboard/components-next/cevico/guia/CvPainelLateral.vue';

const router = useRouter();
const route = useRoute();

const pal = useCevicoPalette({
  scope: 'report:paginas',
  blocks: [
    { id: 'primarios', label: 'Primários', icon: 'i-lucide-target' },
    { id: 'secundarios', label: 'Secundários', icon: 'i-lucide-route' },
    { id: 'terciarios', label: 'Terciários', icon: 'i-lucide-layers' },
    { id: 'paginas', label: 'Página por página', icon: 'i-lucide-files' },
    { id: 'funis', label: 'Funis', icon: 'i-lucide-git-branch' },
  ],
});
const { cvVars } = pal;

// ── cores dos gráficos: a família da cor do dia (como a Visão geral) ──
const varOf = (key, fallback) => cvVars.value?.[key] || fallback;
const cor = computed(() => varOf('--cv', '#3060e0'));
const corDeep = computed(() => varOf('--cv-deep', cor.value));
const corDestaque = computed(() => varOf('--cv-destaque', cor.value));
const corGrad = computed(() => varOf('--cv-grad', cor.value));
const corGrad2 = computed(() => varOf('--cv-grad-2', cor.value));

// ── estado ──
const periodo = ref({ preset: 'month', from: '', to: '' });
const isLoading = ref(true);
const isReportLoading = ref(false);
const dash = ref(null); // pages_dashboard: páginas (30 dias, A/B, leitura) + funis
const report = ref(null); // pages_report: o período da régua
const categoryFilter = ref('');
const keywordFilter = ref('');
const pagesView = ref('lista');
const pagesSort = ref('leads');

// ── formatação ──
const n = v => Number(v || 0).toLocaleString('pt-BR');
const pctTxt = v =>
  v === null || v === undefined
    ? '—'
    : `${Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const brl = v =>
  Number(v || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
const rate = (part, total) =>
  total ? Math.round((part / total) * 1000) / 10 : null;
const fmtPos = v =>
  v === null || v === undefined
    ? '—'
    : String(Math.round(v * 10) / 10).replace('.', ',');
const dateBR = iso => {
  if (!iso) return '';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  return `${d}/${m}/${y}`;
};
// comparação com o período anterior (mesma régua da Visão geral)
const cmp = (atual, anterior, { bomQuandoSobe = true } = {}) => {
  if (anterior === null || anterior === undefined) return null;
  if (!anterior && !atual)
    return { texto: 'sem movimento nos dois períodos', estado: 'neutro' };
  if (!anterior) return { texto: 'antes: 0', estado: 'neutro' };
  const arred = Math.round(((atual - anterior) / anterior) * 100);
  if (arred === 0)
    return {
      texto: `igual ao período anterior (${n(anterior)})`,
      estado: 'neutro',
    };
  const subiu = arred > 0;
  return {
    texto: `${subiu ? '+' : ''}${arred}% vs anterior (${n(anterior)})`,
    estado: subiu === bomQuandoSobe ? 'bom' : 'atencao',
    seta: true,
  };
};
const cmpPct = (atual, anterior) => {
  if (atual === null || anterior === null || anterior === undefined)
    return null;
  const delta = Math.round((atual - anterior) * 10) / 10;
  if (!delta)
    return {
      texto: `igual ao período anterior (${pctTxt(anterior)})`,
      estado: 'neutro',
    };
  return {
    texto: `${delta > 0 ? '+' : ''}${String(delta).replace('.', ',')} pontos vs anterior (${pctTxt(anterior)})`,
    estado: delta > 0 ? 'bom' : 'atencao',
    seta: true,
  };
};

// ── páginas e filtros (categoria da jornada + palavra-chave) ──
const CATEGORY_ORDER = [
  'captacao',
  'pre_consulta',
  'pre_cirurgia',
  'pos_operatorio',
];
const CATEGORY_META = {
  captacao: { label: 'Captação', icon: 'i-lucide-megaphone' },
  pre_consulta: { label: 'Pré-consulta', icon: 'i-lucide-stethoscope' },
  pre_cirurgia: { label: 'Pré-cirurgia', icon: 'i-lucide-heart-pulse' },
  pos_operatorio: { label: 'Pós-operatório', icon: 'i-lucide-shield-check' },
};
const allPages = computed(() => dash.value?.pages || []);
const funnels = computed(() => dash.value?.funnels || []);
const keywordsOf = p =>
  (p.seo_keywords || '')
    .split(',')
    .map(k => k.trim().toLowerCase())
    .filter(Boolean);
const allKeywords = computed(() => {
  const counts = {};
  allPages.value.forEach(p =>
    keywordsOf(p).forEach(k => {
      counts[k] = (counts[k] || 0) + 1;
    })
  );
  return Object.entries(counts).sort((a, b) => b[1] - a[1]);
});
const filtering = computed(
  () => !!(categoryFilter.value || keywordFilter.value)
);
const filteredPages = computed(() =>
  allPages.value.filter(
    p =>
      (!categoryFilter.value || p.category === categoryFilter.value) &&
      (!keywordFilter.value || keywordsOf(p).includes(keywordFilter.value))
  )
);
const filteredIds = computed(() => new Set(filteredPages.value.map(p => p.id)));
const setCategory = cat => {
  categoryFilter.value = categoryFilter.value === cat ? '' : cat;
};
const setKeyword = kw => {
  keywordFilter.value = keywordFilter.value === kw ? '' : kw;
};
const filterLabel = computed(() => {
  const parts = [];
  if (categoryFilter.value)
    parts.push(CATEGORY_META[categoryFilter.value]?.label);
  if (keywordFilter.value) parts.push(`🔑 ${keywordFilter.value}`);
  return parts.length ? parts.join(' · ') : 'todas as páginas';
});

// ── carregar ──
const periodParams = () => ({
  preset: periodo.value.preset,
  ...(periodo.value.preset === 'custom'
    ? { from: periodo.value.from, to: periodo.value.to }
    : {}),
});
let reportSeq = 0;
const loadReport = async () => {
  // filtro que não casa com nenhuma página: nada a perguntar
  if (filtering.value && !filteredPages.value.length) {
    report.value = null;
    return;
  }
  isReportLoading.value = true;
  reportSeq += 1;
  const seq = reportSeq;
  try {
    const params = periodParams();
    if (filtering.value) params.page_ids = [...filteredIds.value];
    const { data } = await CrmAPI.getPagesReport(params);
    // filtro trocado no meio do caminho: só a última pergunta vale
    if (seq === reportSeq) report.value = data;
  } catch {
    useAlert('Não consegui carregar os números do período.');
  } finally {
    isReportLoading.value = false;
  }
};
const loadDash = async () => {
  const { data } = await CrmAPI.getPagesDashboard();
  dash.value = data;
};
const load = async () => {
  isLoading.value = true;
  try {
    await loadDash();
    await loadReport();
  } catch {
    useAlert('Não consegui carregar a análise.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
watch(periodo, loadReport, { deep: true });
watch([categoryFilter, keywordFilter], loadReport);

// ── o período ──
const T = computed(
  () =>
    report.value?.totals || {
      views: 0,
      cta: 0,
      leads: 0,
      booked: 0,
      conversions: 0,
      revenue: 0,
    }
);
const P = computed(() => report.value?.previous?.totals || null);
const S = computed(() => report.value?.series || null);
const rows = computed(() => report.value?.rows || []);
const sourceLabels = computed(() => report.value?.sources || {});
const sourceLabel = src => sourceLabels.value[src] || src;
const rowByPage = computed(() =>
  Object.fromEntries(rows.value.map(r => [r.page_id ?? 'hub', r]))
);
const periodoTxt = computed(() =>
  report.value
    ? `${dateBR(report.value.since)} a ${dateBR(report.value.until)}`
    : ''
);
const GRAIN = { day: 'por dia', week: 'por semana', month: 'por mês' };
const grao = computed(() => GRAIN[S.value?.granularity] || 'por dia');

// soma das origens de todas as páginas do recorte
const sourceAgg = computed(() => {
  const acc = {};
  rows.value.forEach(r => {
    Object.entries(r.sources || {}).forEach(([src, b]) => {
      acc[src] = acc[src] || {
        views: 0,
        cta: 0,
        leads: 0,
        booked: 0,
        conversions: 0,
        revenue: 0,
      };
      Object.keys(acc[src]).forEach(k => {
        acc[src][k] += b[k] || 0;
      });
    });
  });
  return acc;
});
const sourcesBy = key =>
  Object.entries(sourceAgg.value)
    .map(([src, b]) => ({ src, label: sourceLabel(src), ...b }))
    .filter(r => r[key] > 0)
    .sort((a, b) => b[key] - a[key]);

// leitura do recorte (soma da rolagem das páginas no período)
const leitura = computed(() => {
  const sum = { 25: 0, 50: 0, 75: 0, 100: 0 };
  rows.value.forEach(r => {
    Object.keys(sum).forEach(k => {
      sum[k] += Number(r.scroll?.[k] || 0);
    });
  });
  return sum;
});
const temLeitura = computed(() => Object.values(leitura.value).some(Boolean));

// ════════════ PRIMÁRIOS — o resultado ════════════
const taxaLead = computed(() => rate(T.value.leads, T.value.views));
const taxaLeadAntes = computed(() =>
  P.value ? rate(P.value.leads, P.value.views) : null
);
const funilPrimario = computed(() => [
  {
    key: 'views',
    label: 'Visitas',
    value: T.value.views,
    color: corDeep.value,
  },
  { key: 'cta', label: 'WhatsApp', value: T.value.cta, color: cor.value },
  {
    key: 'leads',
    label: 'Leads',
    value: T.value.leads,
    color: corDestaque.value,
  },
  {
    key: 'booked',
    label: 'Agendaram',
    value: T.value.booked,
    color: '#0891B2',
  },
  {
    key: 'conversions',
    label: 'Cirurgias',
    value: T.value.conversions,
    color: '#7C3AED',
  },
]);
const areaPrimaria = computed(() => [
  {
    key: 'leads',
    label: 'Leads',
    color: corDestaque.value,
    values: S.value?.leads || [],
  },
  {
    key: 'booked',
    label: 'Agendaram',
    color: '#0891B2',
    values: S.value?.booked || [],
  },
]);
const barrasLeadsOrigem = computed(() =>
  sourcesBy('leads')
    .slice(0, 6)
    .map(r => ({ label: r.label, values: [r.leads, r.booked] }))
);

// ════════════ SECUNDÁRIOS — o caminho ════════════
const taxaClique = computed(() => rate(T.value.cta, T.value.views));
const taxaCaixa = computed(() => rate(T.value.leads, T.value.cta));
const taxaAgenda = computed(() => rate(T.value.booked, T.value.leads));
const antes = (a, b) => (P.value ? rate(P.value[a], P.value[b]) : null);
const leramFim = computed(() => rate(leitura.value[100], T.value.views));
const leramMetade = computed(() => rate(leitura.value[50], T.value.views));
const protocolo = computed(
  () => report.value?.protocol || { minted: 0, matched: 0 }
);
const areaTaxas = computed(() => {
  const views = S.value?.views || [];
  const ratio = key =>
    (S.value?.[key] || []).map((v, i) =>
      views[i] ? Math.min(Math.round((v / views[i]) * 1000) / 10, 100) : 0
    );
  return [
    {
      key: 'click',
      label: 'Clicam no WhatsApp',
      color: cor.value,
      values: ratio('cta'),
    },
    {
      key: 'lead',
      label: 'Viram lead',
      color: corDestaque.value,
      values: ratio('leads'),
    },
  ];
});
const fmtPctChart = v =>
  `${String(Math.round(v * 10) / 10).replace('.', ',')}%`;
const barrasLeitura = computed(() =>
  ['25', '50', '75', '100'].map(k => ({
    label: k === '100' ? 'até o fim' : `${k}% da página`,
    values: [rate(leitura.value[k], T.value.views) || 0],
  }))
);
const barrasCliquePagina = computed(() =>
  rows.value
    .filter(r => r.views >= 5)
    .sort((a, b) => b.views - a.views)
    .slice(0, 6)
    .map(r => ({
      label: r.title,
      sub: `${n(r.views)} visitas`,
      values: [rate(r.cta, r.views) || 0],
    }))
);

// ════════════ TERCIÁRIOS — o que sustenta ════════════
const gsc = computed(() => report.value?.search_console || null);
const gscReady = computed(() => !!gsc.value?.ready);
// com filtro, soma só as páginas do recorte; sem filtro, o domínio inteiro
const gscNums = computed(() => {
  if (!gscReady.value) return null;
  if (!filtering.value) {
    const c = gsc.value.totals?.current || {};
    const p = gsc.value.totals?.previous || {};
    return { cur: c, prev: p, escopo: 'domínio inteiro' };
  }
  const list = (gsc.value.pages || []).filter(x =>
    filteredIds.value.has(x.page_id)
  );
  const sum = (arr, k) => arr.reduce((s, x) => s + (x[k] || 0), 0);
  const pos = arr => {
    const w = sum(arr, 'impressions');
    return w
      ? arr.reduce((s, x) => s + (x.position || 0) * x.impressions, 0) / w
      : null;
  };
  const prevs = list.map(x => x.previous).filter(Boolean);
  return {
    cur: {
      impressions: sum(list, 'impressions'),
      clicks: sum(list, 'clicks'),
      position: pos(list),
    },
    prev: prevs.length
      ? {
          impressions: sum(prevs, 'impressions'),
          clicks: sum(prevs, 'clicks'),
          position: pos(prevs),
        }
      : null,
    escopo: 'páginas do recorte',
  };
});
const posCmp = computed(() => {
  const c = gscNums.value?.cur?.position;
  const p = gscNums.value?.prev?.position;
  if (!c || !p) return null;
  const diff = Math.round((p - c) * 10) / 10;
  if (!diff)
    return {
      texto: `igual aos 28 dias antes (${fmtPos(p)})`,
      estado: 'neutro',
    };
  return diff > 0
    ? {
        texto: `subiu ${fmtPos(diff)} · antes ${fmtPos(p)}`,
        estado: 'bom',
        seta: true,
      }
    : {
        texto: `caiu ${fmtPos(-diff)} · antes ${fmtPos(p)}`,
        estado: 'atencao',
        seta: true,
      };
});
const gscSerie = computed(() =>
  !filtering.value ? (gsc.value?.daily || []).map(d => d[2]) : []
);
const areaGoogle = computed(() => [
  {
    key: 'clicks',
    label: 'Cliques no Google',
    color: corDestaque.value,
    values: (gsc.value?.daily || []).map(d => d[1]),
  },
]);
const rotulosGoogle = computed(() =>
  (gsc.value?.daily || []).map(d => `${d[0].slice(8, 10)}/${d[0].slice(5, 7)}`)
);
const publicadas = computed(() =>
  filteredPages.value.filter(p => p.status === 'published')
);
const semVisita = computed(() =>
  publicadas.value.filter(p => !(rowByPage.value[p.id]?.views > 0))
);
const comAB = computed(() => filteredPages.value.filter(p => p.ab_running));
const funisDoRecorte = computed(() =>
  funnels.value.filter(
    f => !filtering.value || f.steps.some(s => filteredIds.value.has(s.id))
  )
);
const elos = computed(() =>
  funisDoRecorte.value.reduce((s, f) => s + Math.max(f.steps.length - 1, 0), 0)
);
const seguiram = computed(() =>
  funisDoRecorte.value.reduce(
    (s, f) =>
      s + f.steps.slice(0, -1).reduce((x, st) => x + (st.next_clicks || 0), 0),
    0
  )
);
const insights = computed(() => report.value?.insights || []);
const LEVEL_LABEL = {
  alerta: 'Vazamentos',
  atencao: 'Atenção',
  oportunidade: 'Oportunidades',
  seo: 'Google (SEO)',
};
const barrasInsights = computed(() =>
  Object.entries(LEVEL_LABEL)
    .map(([lvl, label]) => ({
      label,
      values: [insights.value.filter(i => i.level === lvl).length],
    }))
    .filter(r => r.values[0] > 0)
);
const barrasVisitasOrigem = computed(() =>
  sourcesBy('views')
    .slice(0, 6)
    .map(r => ({ label: r.label, values: [r.views] }))
);
const goOtimizar = () =>
  router.push({
    name: 'cevico_pages_results',
    params: { accountId: route.params.accountId },
    query: { aba: 'otimizar' },
  });

// corta na palavra, com reticências (a vitrine tem altura fixa)
const curto = (txt, max = 150) =>
  txt.length > max ? `${txt.slice(0, txt.lastIndexOf(' ', max))}…` : txt;

// ── vitrine: o que o sistema achou de mais importante no período ──
const vitrinePaineis = computed(() => {
  const list = insights.value;
  const picks = [
    list.find(i => i.level === 'alerta'),
    list.find(i => i.rule === 'campea'),
    list.find(i => i.level === 'seo' && i.rule?.startsWith('gsc')) ||
      list.find(i => i.level === 'seo'),
  ].filter(Boolean);
  const ETQ = {
    alerta: 'Vazamento',
    oportunidade: 'Oportunidade',
    seo: 'Google',
    atencao: 'Atenção',
  };
  const paineis = picks.map((i, idx) => ({
    etiqueta: ETQ[i.level] || 'Ponto a melhorar',
    titulo: i.title,
    // a página + a 1ª frase do que fazer (a vitrine tem altura fixa)
    texto: curto(
      `${i.page_title} — ${String(i.suggestion || '').split('. ')[0]}`
    ),
    tom: ['dia', 'apoio', 'escuro'][idx] || 'dia',
    acao: { label: 'Ver o que fazer', onClick: goOtimizar },
  }));
  if (!paineis.length && report.value) {
    paineis.push({
      etiqueta: 'Período',
      titulo: T.value.views
        ? `${n(T.value.views)} visitas e ${n(T.value.leads)} lead(s) em ${filterLabel.value}`
        : 'Ainda sem visitas neste recorte',
      texto:
        'Quando houver volume, os pontos a melhorar de cada página aparecem aqui.',
      tom: 'dia',
    });
  }
  return paineis;
});

// ════════════ PÁGINA POR PÁGINA ════════════
const reportPages = computed(() =>
  Object.fromEntries((report.value?.pages || []).map(p => [p.id, p]))
);
const gscByPage = computed(() =>
  Object.fromEntries(
    (gsc.value?.pages || []).filter(p => p.page_id).map(p => [p.page_id, p])
  )
);
const insightsOf = id => insights.value.filter(i => i.page_id === id);
const pageList = computed(() => {
  const list = filteredPages.value
    .filter(p => p.status === 'published' || rowByPage.value[p.id])
    .map(p => {
      const r = rowByPage.value[p.id] || {};
      return {
        ...p,
        views: r.views || 0,
        cta: r.cta || 0,
        leads: r.leads || 0,
        booked: r.booked || 0,
        conversions: r.conversions || 0,
        revenue: r.revenue || 0,
        row: r,
        gsc: gscByPage.value[p.id] || null,
        public_url: reportPages.value[p.id]?.public_url,
        builder_url: reportPages.value[p.id]?.builder_url,
      };
    });
  const hub = !filtering.value && rowByPage.value.hub;
  if (hub)
    list.push({
      id: 'hub',
      title: 'Porta de entrada (hub)',
      emoji: '🚪',
      status: 'published',
      category: 'captacao',
      views: hub.views,
      cta: hub.cta,
      leads: hub.leads,
      booked: hub.booked,
      conversions: hub.conversions,
      revenue: hub.revenue,
      row: hub,
      gsc: null,
    });
  const SORTS = {
    leads: p => [p.leads, p.views],
    visitas: p => [p.views, p.leads],
    taxa: p => [rate(p.leads, p.views) || 0, p.views],
    google: p => [p.gsc ? -(p.gsc.position || 99) : -999, p.views],
  };
  const key = SORTS[pagesSort.value];
  return list.sort((a, b) => {
    const [a1, a2] = key(a);
    const [b1, b2] = key(b);
    return b1 - a1 || b2 - a2;
  });
});
const SORT_OPTIONS = [
  ['leads', 'Mais leads'],
  ['visitas', 'Mais visitas'],
  ['taxa', 'Melhor visita → lead'],
  ['google', 'Melhor posição no Google'],
];
const sparkPath = p => {
  const values = (p.row?.spark || []).map(x => x[0]);
  if (values.length < 2 || !values.some(v => v > 0)) return '';
  const max = Math.max(...values, 1);
  const step = 100 / (values.length - 1);
  return values
    .map(
      (v, i) =>
        `${i ? 'L' : 'M'}${(i * step).toFixed(1)},${(26 - (v / max) * 24).toFixed(1)}`
    )
    .join(' ');
};

// ════════════ PAINEL LATERAL (a história de cada número) ════════════
const painel = ref(null); // { key, titulo, valor, comparacao, pageId? }
const abrir = (key, titulo, valor, comparacao = null) => {
  painel.value = { key, titulo, valor, comparacao };
};
const abrirPagina = p => {
  painel.value = {
    key: 'page',
    pageId: p.id,
    titulo: `${p.emoji || '📄'} ${p.title}`,
    valor: `${n(p.leads)} lead(s)`,
    comparacao: {
      texto: `${n(p.views)} visitas · ${pctTxt(rate(p.leads, p.views))} viram lead`,
      estado: 'neutro',
    },
  };
};
const fechar = () => {
  painel.value = null;
};
const PAINEL_METRICA = {
  leads: {
    campo: 'leads',
    como: 'Lead = paciente que chegou na caixa do WhatsApp com o Protocolo da página (o código que vai na mensagem pronta). Conta pela data em que chegou.',
  },
  booked: {
    campo: 'booked',
    como: 'Dos leads do período, quem tem consulta marcada na Agenda. Sobe com o tempo: o lead de hoje pode marcar semana que vem.',
  },
  conversions: {
    campo: 'conversions',
    como: 'Dos leads do período, quem chegou numa etapa de cirurgia do CRM (mesma régua do relatório de Anúncios).',
  },
  revenue: {
    campo: 'revenue',
    como: 'Soma do valor do card no CRM dos leads que chegaram à cirurgia.',
    dinheiro: true,
  },
  views: {
    campo: 'views',
    como: 'Cada abertura da página com o rastreio do sistema (não conta robôs nem a equipe na montagem).',
  },
};
const metricaAberta = computed(() => PAINEL_METRICA[painel.value?.key] || null);
const porPagina = campo =>
  rows.value
    .filter(r => r[campo] > 0)
    .sort((a, b) => b[campo] - a[campo])
    .map(r => ({ label: r.title, count: r[campo] }));
const totalDe = list => list.reduce((s, r) => s + (r.count || 0), 0) || 1;
const fmtCount = (v, dinheiro) => (dinheiro ? brl(v) : n(v));
const RATE_KEYS = {
  taxa_lead: [
    'leads',
    'views',
    'Leads ÷ visitas: de cada 100 pessoas que abriram a página, quantas mandaram a mensagem com o Protocolo.',
  ],
  taxa_clique: ['cta', 'views', 'Toques no botão do WhatsApp ÷ visitas.'],
  taxa_caixa: [
    'leads',
    'cta',
    'Leads ÷ toques no WhatsApp. Quem toca e não manda (ou apaga o Protocolo) fica fora.',
  ],
  taxa_agenda: ['booked', 'leads', 'Leads que marcaram consulta ÷ leads.'],
};
const taxaAberta = computed(() => RATE_KEYS[painel.value?.key] || null);
const taxaPorPagina = computed(() => {
  const t = taxaAberta.value;
  if (!t) return [];
  const [a, b] = t;
  return rows.value
    .filter(r => r[b] >= 3)
    .map(r => ({
      label: r.title,
      sub: `${n(r[a])} de ${n(r[b])}`,
      pct: rate(r[a], r[b]) || 0,
    }))
    .sort((x, y) => y.pct - x.pct);
});
const taxaPorOrigem = computed(() => {
  const t = taxaAberta.value;
  if (!t) return [];
  const [a, b] = t;
  return Object.entries(sourceAgg.value)
    .filter(([, v]) => v[b] >= 3)
    .map(([src, v]) => ({
      label: sourceLabel(src),
      sub: `${n(v[a])} de ${n(v[b])}`,
      pct: rate(v[a], v[b]) || 0,
    }))
    .sort((x, y) => y.pct - x.pct);
});
const leituraPorPagina = computed(() =>
  rows.value
    .filter(r => r.views >= 5 && r.scroll?.['100'] !== undefined)
    .map(r => ({
      label: r.title,
      sub: `metade ${pctTxt(rate(r.scroll['50'] || 0, r.views))}`,
      pct: rate(r.scroll['100'] || 0, r.views) || 0,
    }))
    .sort((x, y) => y.pct - x.pct)
);
const googlePorPagina = computed(() =>
  (gsc.value?.pages || [])
    .filter(p => !filtering.value || filteredIds.value.has(p.page_id))
    .map(p => ({
      label: p.title,
      sub: `${n(p.clicks)} cliques · posição ${fmtPos(p.position)}`,
      count: p.impressions,
    }))
);
const abLista = computed(() =>
  comAB.value.map(p => {
    const results = p.ab_results || {};
    const variants = p.ab_variants || [];
    return {
      id: p.id,
      title: p.title,
      linhas: Object.keys(results).map(k => {
        const t = results[k];
        const clicks = (t.cta || 0) + (t.next || 0);
        return {
          key: k,
          name:
            k === 'a'
              ? 'Original'
              : variants.find(v => v.key === k)?.name ||
                `Variação ${k.toUpperCase()}`,
          views: t.view || 0,
          leads: t.lead || 0,
          pct: t.view ? rate(clicks, t.view) : null,
        };
      }),
    };
  })
);
// a página aberta no painel
const paginaAberta = computed(() =>
  painel.value?.key === 'page'
    ? pageList.value.find(p => p.id === painel.value.pageId)
    : null
);
const serie30 = computed(() => {
  const s = paginaAberta.value?.series || [];
  return {
    rotulos: s.map(d => `${d.date.slice(8, 10)}/${d.date.slice(5, 7)}`),
    series: [
      {
        key: 'view',
        label: 'Visitas',
        color: cor.value,
        values: s.map(d => d.view),
      },
      {
        key: 'cta',
        label: 'WhatsApp',
        color: corDestaque.value,
        values: s.map(d => d.cta),
      },
    ],
  };
});
const fontesDaPagina = computed(() =>
  Object.entries(paginaAberta.value?.row?.sources || {})
    .map(([src, b]) => ({
      label: sourceLabel(src),
      count: b.views,
      leads: b.leads,
    }))
    .sort((a, b) => b.count - a.count)
);
const vindasDeOutra = computed(() =>
  Object.entries(paginaAberta.value?.origins || {}).map(([slug, c]) => ({
    label: `/${slug}`,
    count: c,
  }))
);
// textos curtos da tela (montados aqui para o modelo ficar limpo)
const chipsTxt = p =>
  [
    CATEGORY_META[p.category]?.label || p.category,
    p.status !== 'published' ? 'rascunho' : '',
    p.ab_running ? 'teste A/B no ar' : '',
    p.id !== 'hub' && insightsOf(p.id).length
      ? `💡 ${insightsOf(p.id).length} a melhorar`
      : '',
  ]
    .filter(Boolean)
    .join(' · ');
const ctaTxt = step =>
  `💬 ${n(step.cta_clicks)} WhatsApp (${pctTxt(step.cta_rate)})`;
const desdeTxt = p => `${n(p.views_count)} visitas desde que nasceu`;
const abTxt = l =>
  `${n(l.views)} visitas · ${n(l.leads)} leads · ${pctTxt(l.pct)} clicam`;
const termTxt = t => `${n(t.impressions)} · posição ${fmtPos(t.position)}`;
const fimTxt = p => pctTxt(rate(p.row?.scroll?.['100'] || 0, p.views));
const abrirUrl = url => url && window.open(url, '_blank', 'noopener');

// ════════════ FUNIS (montador de sempre) ════════════
const savingLink = ref(0);
const setNext = async (page, nextId) => {
  savingLink.value = page.id;
  try {
    await CrmAPI.updatePage(page.id, { next_page_id: nextId || null });
    await loadDash();
    useAlert(
      nextId
        ? 'Funil atualizado! O botão da página já aponta para o novo destino.'
        : 'Elo removido — o botão volta para o WhatsApp.'
    );
  } catch {
    useAlert('Não consegui atualizar o funil.');
  } finally {
    savingLink.value = 0;
  }
};
const linkCandidates = page => allPages.value.filter(p => p.id !== page.id);
const loosePages = computed(() => {
  const inFunnel = new Set();
  funnels.value.forEach(f => f.steps.forEach(s => inFunnel.add(s.id)));
  return allPages.value.filter(
    p => p.status === 'published' && !inFunnel.has(p.id)
  );
});
</script>

<template>
  <div
    class="cv-page cv-overlay cvg-page cvg-pa w-full min-w-0"
    :style="cvVars"
  >
    <CvCabecalho
      :pal="pal"
      title="Análise de Páginas"
      subtitle="O que as páginas trouxeram, por onde o caminho passa e o que sustenta tudo — em três níveis, no período da régua."
      icon="i-lucide-chart-line"
    >
      <template #acoes>
        <button
          class="cvg-btn cvg-btn--principal"
          type="button"
          @click="goOtimizar"
        >
          <span class="i-lucide-lightbulb text-base" /> Pontos a melhorar
          <b v-if="insights.length">{{ insights.length }}</b>
        </button>
      </template>
    </CvCabecalho>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="dash">
      <!-- recorte: categoria da jornada e palavra-chave -->
      <div class="cvg-pa-recorte">
        <!-- a régua fica fora do cabeçalho: no celular ela rola sozinha -->
        <div class="cvg-pa-regua">
          <PeriodRuler v-model="periodo" glass class="max-w-full min-w-0" />
        </div>
        <div class="cvg-pa-recorte-linha">
          <span class="cvg-rotulo">Categoria</span>
          <button
            type="button"
            class="cvg-chip cvg-chip--marcavel"
            :class="!categoryFilter ? 'cvg-on' : ''"
            @click="categoryFilter = ''"
          >
            Todas
          </button>
          <button
            v-for="cat in CATEGORY_ORDER"
            :key="cat"
            type="button"
            class="cvg-chip cvg-chip--marcavel"
            :class="categoryFilter === cat ? 'cvg-on' : ''"
            @click="setCategory(cat)"
          >
            <span :class="CATEGORY_META[cat].icon" class="text-xs" />
            {{ CATEGORY_META[cat].label }}
          </button>
        </div>
        <div v-if="allKeywords.length" class="cvg-pa-recorte-linha">
          <span class="cvg-rotulo">Palavra-chave</span>
          <button
            v-for="[kw, count] in allKeywords"
            :key="kw"
            type="button"
            class="cvg-chip cvg-chip--marcavel"
            :class="keywordFilter === kw ? 'cvg-on' : ''"
            @click="setKeyword(kw)"
          >
            🔑 {{ kw }} <b>{{ count }}</b>
          </button>
        </div>
      </div>

      <div class="cvg-arejado-vitrine">
        <CvVitrine :paineis="vitrinePaineis" lembrar="cevico:vitrine:paginas" />
      </div>

      <p v-if="!report && filtering" class="cvg-vazio">
        Nenhuma página em {{ filterLabel }}.
      </p>

      <template v-if="report">
        <!-- ══ 1 · PRIMÁRIOS — o resultado ══ -->
        <CvBloco
          titulo="Primários · o que as páginas trouxeram"
          :subtitulo="`O resultado que decide: paciente na caixa, consulta e cirurgia · ${filterLabel} · ${periodoTxt}`"
          tom="dia"
          icon="i-lucide-target"
        >
          <div
            class="cvg-bloco-pilha"
            :class="isReportLoading ? 'opacity-60' : ''"
          >
            <div class="cvg-fila cvg-fila--5">
              <CvIndicador
                rotulo="Leads na caixa"
                :valor="n(T.leads)"
                :comparacao="cmp(T.leads, P?.leads)"
                :contexto="`${pctTxt(taxaLead)} das visitas viraram lead.`"
                :serie="S?.leads || []"
                heroi
                pe="por página e origem"
                @abrir="
                  abrir(
                    'leads',
                    'Leads na caixa',
                    n(T.leads),
                    cmp(T.leads, P?.leads)
                  )
                "
              />
              <CvIndicador
                rotulo="Agendaram consulta"
                :valor="n(T.booked)"
                :comparacao="cmp(T.booked, P?.booked)"
                :contexto="`${pctTxt(rate(T.booked, T.leads))} dos leads.`"
                :serie="S?.booked || []"
                @abrir="
                  abrir(
                    'booked',
                    'Agendaram consulta',
                    n(T.booked),
                    cmp(T.booked, P?.booked)
                  )
                "
              />
              <CvIndicador
                rotulo="Cirurgias"
                :valor="n(T.conversions)"
                :comparacao="cmp(T.conversions, P?.conversions)"
                :contexto="`${pctTxt(rate(T.conversions, T.leads))} dos leads · sobe com o tempo.`"
                @abrir="
                  abrir(
                    'conversions',
                    'Cirurgias',
                    n(T.conversions),
                    cmp(T.conversions, P?.conversions)
                  )
                "
              />
              <CvIndicador
                rotulo="Receita das cirurgias"
                :valor="brl(T.revenue)"
                :comparacao="cmp(T.revenue, P?.revenue)"
                :contexto="
                  T.views ? `${brl(T.revenue / T.views)} por visita.` : ''
                "
                @abrir="
                  abrir(
                    'revenue',
                    'Receita das cirurgias',
                    brl(T.revenue),
                    cmp(T.revenue, P?.revenue)
                  )
                "
              />
              <CvIndicador
                rotulo="Visita → lead"
                :valor="pctTxt(taxaLead)"
                :comparacao="cmpPct(taxaLead, taxaLeadAntes)"
                contexto="De cada 100 visitas, quantas mandaram a mensagem."
                pe="leads ÷ visitas"
                @abrir="
                  abrir(
                    'taxa_lead',
                    'Visita → lead',
                    pctTxt(taxaLead),
                    cmpPct(taxaLead, taxaLeadAntes)
                  )
                "
              />
            </div>
            <!-- o funil de 5 degraus pede a largura inteira -->
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>O caminho inteiro</span>
                <span>{{ pctTxt(taxaLead) }} viram lead</span>
              </span>
              <div class="cvg-grafico-corpo">
                <!-- no computador: degraus lado a lado; no celular: em pé -->
                <div class="hidden md:block">
                  <FunnelSteps
                    :steps="funilPrimario"
                    :height="140"
                    start-text="das visitas"
                  />
                </div>
                <div class="md:hidden">
                  <div
                    v-for="st in funilPrimario"
                    :key="st.key"
                    class="cvg-pa-barra"
                  >
                    <div class="cvg-pa-barra-linha">
                      <span>{{ st.label }}</span>
                      <small class="cvg-texto-3">
                        {{ pctTxt(rate(st.value, T.views)) }}
                      </small>
                      <b>{{ n(st.value) }}</b>
                    </div>
                    <div class="cvg-pa-barra-trilho">
                      <i
                        :style="{
                          width: `${(st.value / Math.max(T.views, 1)) * 100}%`,
                          background: st.color,
                        }"
                      />
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <div class="cvg-graficos cvg-graficos--2">
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Leads × agendaram</span>
                  <span>{{ grao }}</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <AreaChart
                    v-if="(S?.labels || []).length > 1"
                    :series="areaPrimaria"
                    :labels="S.labels"
                    :height="150"
                    unit="pessoas"
                  />
                  <p v-else class="cvg-vazio">
                    período curto demais para a linha
                  </p>
                </div>
              </div>
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>De onde vieram os leads</span>
                  <span>leads × agendaram</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <HBars
                    :rows="barrasLeadsOrigem"
                    :series="[
                      { label: 'leads', color: corGrad2 },
                      { label: 'agendaram', color: corGrad },
                    ]"
                    :label-width="8"
                    :highlight-max="false"
                    empty-text="sem lead no período"
                  />
                </div>
                <p class="cvg-grafico-nota">
                  origem da visita que gerou o Protocolo
                </p>
              </div>
            </div>
          </div>
        </CvBloco>

        <!-- ══ 2 · SECUNDÁRIOS — o caminho ══ -->
        <CvBloco
          titulo="Secundários · o caminho até o lead"
          subtitulo="O que explica o resultado: quanta gente abriu, quanto leu, quanto tocou no WhatsApp e quanto chegou na caixa"
          tom="apoio"
          icon="i-lucide-route"
        >
          <div
            class="cvg-bloco-pilha"
            :class="isReportLoading ? 'opacity-60' : ''"
          >
            <div class="cvg-fila cvg-fila--5">
              <CvIndicador
                rotulo="Visitas"
                :valor="n(T.views)"
                :comparacao="cmp(T.views, P?.views)"
                :contexto="`${n(publicadas.length - semVisita.length)} página(s) com visita.`"
                :serie="S?.views || []"
                heroi
                apoio
                pe="por página e origem"
                @abrir="
                  abrir('views', 'Visitas', n(T.views), cmp(T.views, P?.views))
                "
              />
              <CvIndicador
                rotulo="Clicam no WhatsApp"
                :valor="pctTxt(taxaClique)"
                :comparacao="cmpPct(taxaClique, antes('cta', 'views'))"
                :contexto="`${n(T.cta)} toque(s) no botão.`"
                apoio
                pe="toques ÷ visitas"
                @abrir="
                  abrir(
                    'taxa_clique',
                    'Clicam no WhatsApp',
                    pctTxt(taxaClique),
                    cmpPct(taxaClique, antes('cta', 'views'))
                  )
                "
              />
              <CvIndicador
                rotulo="Chegam na caixa"
                :valor="pctTxt(taxaCaixa)"
                :comparacao="cmpPct(taxaCaixa, antes('leads', 'cta'))"
                :contexto="`${n(protocolo.matched)} de ${n(protocolo.minted)} Protocolos gerados chegaram.`"
                apoio
                pe="leads ÷ toques"
                @abrir="
                  abrir(
                    'taxa_caixa',
                    'Chegam na caixa',
                    pctTxt(taxaCaixa),
                    cmpPct(taxaCaixa, antes('leads', 'cta'))
                  )
                "
              />
              <CvIndicador
                rotulo="Agendam consulta"
                :valor="pctTxt(taxaAgenda)"
                :comparacao="cmpPct(taxaAgenda, antes('booked', 'leads'))"
                contexto="Dos leads, quantos marcaram."
                apoio
                pe="agendaram ÷ leads"
                @abrir="
                  abrir(
                    'taxa_agenda',
                    'Agendam consulta',
                    pctTxt(taxaAgenda),
                    cmpPct(taxaAgenda, antes('booked', 'leads'))
                  )
                "
              />
              <CvIndicador
                rotulo="Leram até o fim"
                :valor="pctTxt(leramFim)"
                :contexto="
                  temLeitura
                    ? `${pctTxt(leramMetade)} chegaram à metade.`
                    : 'Sem dados de leitura no período.'
                "
                apoio
                pe="por página"
                @abrir="abrir('leitura', 'Leram até o fim', pctTxt(leramFim))"
              />
            </div>
            <div class="cvg-graficos">
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Taxas ao longo do período</span>
                  <span>{{ grao }}</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <AreaChart
                    v-if="(S?.labels || []).length > 1 && T.views"
                    :legend="false"
                    :series="areaTaxas"
                    :labels="S.labels"
                    :height="150"
                    :format="fmtPctChart"
                    :axis-width="44"
                  />
                  <p v-else class="cvg-vazio">sem visita para calcular</p>
                </div>
              </div>
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Até onde leram</span>
                  <span>% das visitas</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <HBars
                    v-if="temLeitura"
                    :rows="barrasLeitura"
                    :series="[{ label: 'das visitas', color: corGrad }]"
                    :format="fmtPctChart"
                    :label-width="7"
                    :highlight-max="false"
                  />
                  <p v-else class="cvg-vazio">as próximas visitas já contam</p>
                </div>
              </div>
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Clique no WhatsApp por página</span>
                  <span>as mais visitadas</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <HBars
                    :rows="barrasCliquePagina"
                    :series="[{ label: 'clicam', color: corGrad2 }]"
                    :format="fmtPctChart"
                    :label-width="9"
                    empty-text="nenhuma página com 5+ visitas"
                  />
                </div>
              </div>
            </div>
          </div>
        </CvBloco>

        <!-- ══ 3 · TERCIÁRIOS — o que sustenta ══ -->
        <CvBloco
          titulo="Terciários · o que sustenta"
          subtitulo="O contexto: como as páginas aparecem no Google, quantas estão trabalhando, os testes, os funis e o que o sistema já apontou"
          icon="i-lucide-layers"
        >
          <div
            class="cvg-bloco-pilha"
            :class="isReportLoading ? 'opacity-60' : ''"
          >
            <div class="cvg-fila cvg-fila--5">
              <CvIndicador
                rotulo="Aparições no Google"
                :valor="gscNums ? n(gscNums.cur.impressions) : '—'"
                :comparacao="
                  gscNums
                    ? cmp(gscNums.cur.impressions, gscNums.prev?.impressions)
                    : null
                "
                :contexto="
                  gscNums
                    ? `${n(gscNums.cur.clicks)} cliques · últimos 28 dias do Google · ${gscNums.escopo}.`
                    : 'Search Console ainda não ligado (Integrações → Google).'
                "
                :serie="gscSerie"
                heroi
                pe="por página"
                @abrir="
                  abrir(
                    'google',
                    'Aparições no Google',
                    gscNums ? n(gscNums.cur.impressions) : '—'
                  )
                "
              />
              <CvIndicador
                rotulo="Posição média no Google"
                :valor="gscNums ? fmtPos(gscNums.cur.position) : '—'"
                :comparacao="posCmp"
                contexto="1 = primeiro resultado da busca."
                @abrir="
                  abrir(
                    'google',
                    'Posição no Google',
                    gscNums ? fmtPos(gscNums.cur.position) : '—',
                    posCmp
                  )
                "
              />
              <CvIndicador
                rotulo="Páginas no ar"
                :valor="n(publicadas.length)"
                :contexto="
                  semVisita.length
                    ? `${n(semVisita.length)} sem visita no período.`
                    : 'Todas receberam visita.'
                "
                :comparacao="
                  semVisita.length
                    ? {
                        texto: `${n(semVisita.length)} paradas`,
                        estado: 'atencao',
                      }
                    : null
                "
                @abrir="abrir('paradas', 'Páginas no ar', n(publicadas.length))"
              />
              <CvIndicador
                rotulo="Testes A/B no ar"
                :valor="n(comAB.length)"
                :contexto="
                  comAB.length
                    ? 'Variações dividindo as visitas.'
                    : 'Nenhum teste rodando.'
                "
                @abrir="abrir('ab', 'Testes A/B no ar', n(comAB.length))"
              />
              <CvIndicador
                rotulo="Funis montados"
                :valor="n(funisDoRecorte.length)"
                :contexto="`${n(elos)} elo(s) · ${n(seguiram)} seguiram para a próxima página.`"
                pe="página → página → WhatsApp"
              />
            </div>
            <div class="cvg-graficos">
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Cliques no Google</span>
                  <span>{{
                    gscReady ? 'domínio · 56 dias' : 'não ligado'
                  }}</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <AreaChart
                    v-if="gscReady && rotulosGoogle.length > 1"
                    :legend="false"
                    :series="areaGoogle"
                    :labels="rotulosGoogle"
                    :height="150"
                    unit="cliques"
                  />
                  <p v-else class="cvg-vazio">
                    ligue o Search Console em Integrações → Google
                  </p>
                </div>
                <p v-if="gsc?.demo" class="cvg-grafico-nota">
                  dados de exemplo (local)
                </p>
              </div>
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Visitas por origem</span>
                  <span>{{ n(T.views) }} no período</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <HBars
                    :rows="barrasVisitasOrigem"
                    :series="[{ label: 'visitas', color: corGrad }]"
                    :label-width="8"
                    empty-text="sem visita no período"
                  />
                </div>
              </div>
              <div class="cvg-grafico">
                <span class="cvg-grafico-titulo">
                  <span>Pontos a melhorar</span>
                  <span>{{ n(insights.length) }} no período</span>
                </span>
                <div class="cvg-grafico-corpo">
                  <HBars
                    :rows="barrasInsights"
                    :series="[{ label: 'pontos', color: corGrad2 }]"
                    :label-width="8"
                    :highlight-max="false"
                    empty-text="nada apontado — falta volume ou está tudo na média"
                  />
                </div>
                <button
                  v-if="insights.length"
                  type="button"
                  class="cvg-btn cvg-btn--ghost cvg-btn--sm self-start"
                  @click="goOtimizar"
                >
                  Abrir o Otimizar ›
                </button>
              </div>
            </div>
          </div>
        </CvBloco>

        <!-- ══ 4 · PÁGINA POR PÁGINA ══ -->
        <CvBloco
          titulo="Página por página"
          subtitulo="Os mesmos três níveis de cada página. Toque numa página para ver a história completa dela."
          icon="i-lucide-files"
        >
          <template #acoes>
            <select
              v-model="pagesSort"
              class="cvg-campo cvg-campo--sm cvg-pa-ordem"
              aria-label="Ordenar"
            >
              <option
                v-for="[key, label] in SORT_OPTIONS"
                :key="key"
                :value="key"
              >
                {{ label }}
              </option>
            </select>
            <div class="cvg-chave" role="group" aria-label="Visualização">
              <button
                type="button"
                :aria-pressed="pagesView === 'lista' ? 'true' : 'false'"
                @click="pagesView = 'lista'"
              >
                <span class="i-lucide-list text-sm" /> Lista
              </button>
              <button
                type="button"
                :aria-pressed="pagesView === 'cards' ? 'true' : 'false'"
                @click="pagesView = 'cards'"
              >
                <span class="i-lucide-layout-grid text-sm" /> Cards
              </button>
            </div>
          </template>

          <p v-if="!pageList.length" class="cvg-vazio">
            Nenhuma página neste recorte.
          </p>

          <!-- LISTA -->
          <div v-else-if="pagesView === 'lista'" class="cvg-lista">
            <button
              v-for="p in pageList"
              :key="p.id"
              type="button"
              class="cvg-linha cvg-pa-linha"
              @click="abrirPagina(p)"
            >
              <span class="cvg-pa-quem">
                <span class="cvg-pa-emoji">{{ p.emoji || '📄' }}</span>
                <span class="cvg-linha-quem">
                  <b>{{ p.title }}</b>
                  <span class="cvg-legenda cvg-pa-chips">{{
                    chipsTxt(p)
                  }}</span>
                </span>
              </span>
              <svg
                v-if="sparkPath(p)"
                viewBox="0 0 100 28"
                preserveAspectRatio="none"
                class="cvg-pa-spark"
                aria-hidden="true"
              >
                <path :d="sparkPath(p)" />
              </svg>
              <span class="cvg-pa-nums">
                <span class="cvg-pa-num cvg-pa-num--primario">
                  <b>{{ n(p.leads) }}</b>
                  <small>leads</small>
                </span>
                <span class="cvg-pa-num cvg-pa-num--primario">
                  <b>{{ n(p.booked) }}</b>
                  <small>agendaram</small>
                </span>
                <span class="cvg-pa-num cvg-pa-num--primario">
                  <b>{{ n(p.conversions) }}</b>
                  <small>cirurgias</small>
                </span>
                <span class="cvg-pa-num">
                  <b>{{ n(p.views) }}</b>
                  <small>visitas</small>
                </span>
                <span class="cvg-pa-num">
                  <b>{{ pctTxt(rate(p.cta, p.views)) }}</b>
                  <small>clicam</small>
                </span>
                <span class="cvg-pa-num cvg-pa-num--terciario">
                  <b>{{ p.gsc ? fmtPos(p.gsc.position) : '—' }}</b>
                  <small>Google</small>
                </span>
              </span>
            </button>
          </div>

          <!-- CARDS -->
          <div v-else class="cvg-cards">
            <button
              v-for="p in pageList"
              :key="p.id"
              type="button"
              class="cvg-card cvg-pa-card"
              @click="abrirPagina(p)"
            >
              <span class="cvg-legenda">
                {{ p.emoji || '📄' }}
                {{ CATEGORY_META[p.category]?.label || p.category }}
                <template v-if="p.ab_running"> · A/B no ar</template>
              </span>
              <h3 class="cvg-card-titulo">{{ p.title }}</h3>
              <span class="cvg-pa-card-nivel">
                <span class="cvg-rotulo">Primários</span>
                <span>
                  <b>{{ n(p.leads) }}</b> leads ·
                  <b>{{ n(p.booked) }}</b> agendaram ·
                  <b>{{ n(p.conversions) }}</b> cirurgias
                </span>
              </span>
              <span class="cvg-pa-card-nivel">
                <span class="cvg-rotulo">Secundários</span>
                <span>
                  {{ n(p.views) }} visitas ·
                  {{ pctTxt(rate(p.cta, p.views)) }} clicam ·
                  {{ pctTxt(rate(p.leads, p.views)) }} viram lead
                </span>
              </span>
              <span class="cvg-pa-card-nivel">
                <span class="cvg-rotulo">Terciários</span>
                <span>
                  Google
                  {{
                    p.gsc
                      ? `posição ${fmtPos(p.gsc.position)} · ${n(p.gsc.clicks)} cliques`
                      : '—'
                  }}
                  <template v-if="p.id !== 'hub' && insightsOf(p.id).length">
                    · 💡 {{ insightsOf(p.id).length }}
                  </template>
                </span>
              </span>
            </button>
          </div>
        </CvBloco>
      </template>

      <!-- ══ 5 · FUNIS (o "link build") ══ -->
      <CvBloco
        titulo="Funis montados"
        subtitulo="O caminho do visitante: página → página → WhatsApp. Troque o destino de qualquer elo aqui — o botão da página passa a apontar para o novo destino na hora."
        icon="i-lucide-git-branch"
      >
        <p v-if="!funnels.length" class="cvg-vazio">
          Nenhum funil montado ainda — escolha o destino de uma página solta
          aqui embaixo para criar o primeiro caminho.
        </p>
        <div v-for="f in funnels" :key="f.key" class="cvg-pa-trilha">
          <template v-for="(step, si) in f.steps" :key="step.id">
            <div class="cvg-card cvg-pa-no">
              <b class="truncate">{{ step.emoji || '📄' }} {{ step.title }}</b>
              <span class="cvg-legenda truncate">/{{ step.slug }}</span>
              <span class="cvg-corpo">
                {{ n(step.views) }} visitas
                <template v-if="step.views_from_previous !== null">
                  · <b>{{ n(step.views_from_previous) }}</b> do elo anterior
                </template>
              </span>
              <span class="cvg-legenda">{{ ctaTxt(step) }}</span>
              <select
                class="cvg-campo cvg-campo--sm"
                :disabled="savingLink === step.id"
                :value="step.next_page_id || ''"
                aria-label="Próximo passo"
                @change="setNext(step, $event.target.value)"
              >
                <option value="">➡ termina no WhatsApp</option>
                <option
                  v-for="c in linkCandidates(step)"
                  :key="c.id"
                  :value="c.id"
                >
                  ➡ {{ c.title }}
                </option>
              </select>
            </div>
            <span
              v-if="si < f.steps.length - 1"
              class="cvg-pa-seta"
              :class="step.next_rate >= 10 ? 'cvg-bom' : 'cvg-texto-3'"
            >
              <small>{{ n(step.next_clicks) }} seguiram</small>
              <span class="i-lucide-arrow-right text-lg" />
              <small>{{ pctTxt(step.next_rate) }}</small>
            </span>
          </template>
          <span class="cvg-chip cvg-pa-fim">💬 WhatsApp</span>
        </div>

        <template v-if="loosePages.length">
          <h3 class="cvg-rotulo cvg-pa-sub">
            Páginas publicadas fora de funil
          </h3>
          <div class="cvg-lista">
            <div
              v-for="p in loosePages"
              :key="p.id"
              class="cvg-linha cvg-pa-solta"
            >
              <span class="cvg-linha-quem">
                <b>{{ p.emoji || '📄' }} {{ p.title }}</b>
                <span class="cvg-legenda">{{ desdeTxt(p) }}</span>
              </span>
              <select
                class="cvg-campo cvg-campo--sm"
                :disabled="savingLink === p.id"
                :value="p.next_page_id || ''"
                aria-label="Próximo passo"
                @change="setNext(p, $event.target.value)"
              >
                <option value="">➡ termina no WhatsApp</option>
                <option
                  v-for="c in linkCandidates(p)"
                  :key="c.id"
                  :value="c.id"
                >
                  ➡ {{ c.title }}
                </option>
              </select>
            </div>
          </div>
        </template>
      </CvBloco>
    </template>

    <!-- ══ PAINEL LATERAL ══ -->
    <CvPainelLateral
      :aberto="!!painel"
      :titulo="painel?.titulo || ''"
      :valor="painel?.valor ?? ''"
      :comparacao="painel?.comparacao"
      :vars="cvVars"
      :largura="460"
      @fechar="fechar"
    >
      <template v-if="painel">
        <!-- números contados (leads, agendaram, cirurgias, receita, visitas) -->
        <template v-if="metricaAberta">
          <section class="cvg-painel-sec">
            <h3>Como é contado</h3>
            <p class="cvg-corpo">{{ metricaAberta.como }}</p>
          </section>
          <section
            v-if="porPagina(metricaAberta.campo).length"
            class="cvg-painel-sec"
          >
            <h3>Por página</h3>
            <div
              v-for="r in porPagina(metricaAberta.campo)"
              :key="r.label"
              class="cvg-pa-barra"
            >
              <div class="cvg-pa-barra-linha">
                <span>{{ r.label }}</span>
                <b>{{ fmtCount(r.count, metricaAberta.dinheiro) }}</b>
              </div>
              <div class="cvg-pa-barra-trilho">
                <i
                  :style="{
                    width: `${(r.count / totalDe(porPagina(metricaAberta.campo))) * 100}%`,
                  }"
                />
              </div>
            </div>
          </section>
          <section
            v-if="sourcesBy(metricaAberta.campo).length"
            class="cvg-painel-sec"
          >
            <h3>Por origem da visita</h3>
            <div
              v-for="r in sourcesBy(metricaAberta.campo)"
              :key="r.src"
              class="cvg-pa-barra"
            >
              <div class="cvg-pa-barra-linha">
                <span>{{ r.label }}</span>
                <b>{{
                  fmtCount(r[metricaAberta.campo], metricaAberta.dinheiro)
                }}</b>
              </div>
              <div class="cvg-pa-barra-trilho">
                <i
                  :style="{
                    width: `${(r[metricaAberta.campo] / Math.max(T[metricaAberta.campo], 1)) * 100}%`,
                  }"
                />
              </div>
            </div>
          </section>
        </template>

        <!-- taxas -->
        <template v-if="taxaAberta">
          <section class="cvg-painel-sec">
            <h3>Como é contado</h3>
            <p class="cvg-corpo">{{ taxaAberta[2] }}</p>
          </section>
          <section v-if="taxaPorPagina.length" class="cvg-painel-sec">
            <h3>Por página (com volume mínimo)</h3>
            <div v-for="r in taxaPorPagina" :key="r.label" class="cvg-pa-barra">
              <div class="cvg-pa-barra-linha">
                <span>{{ r.label }}</span>
                <small class="cvg-texto-3">{{ r.sub }}</small>
                <b>{{ pctTxt(r.pct) }}</b>
              </div>
              <div class="cvg-pa-barra-trilho">
                <i :style="{ width: `${Math.min(r.pct, 100)}%` }" />
              </div>
            </div>
          </section>
          <section v-if="taxaPorOrigem.length" class="cvg-painel-sec">
            <h3>Por origem</h3>
            <div v-for="r in taxaPorOrigem" :key="r.label" class="cvg-pa-barra">
              <div class="cvg-pa-barra-linha">
                <span>{{ r.label }}</span>
                <small class="cvg-texto-3">{{ r.sub }}</small>
                <b>{{ pctTxt(r.pct) }}</b>
              </div>
              <div class="cvg-pa-barra-trilho">
                <i :style="{ width: `${Math.min(r.pct, 100)}%` }" />
              </div>
            </div>
          </section>
        </template>

        <!-- leitura -->
        <section v-if="painel.key === 'leitura'" class="cvg-painel-sec">
          <h3>Leram até o fim, por página</h3>
          <p v-if="!leituraPorPagina.length" class="cvg-corpo cvg-texto-3">
            Ainda sem página com 5+ visitas e leitura medida no período.
          </p>
          <div
            v-for="r in leituraPorPagina"
            :key="r.label"
            class="cvg-pa-barra"
          >
            <div class="cvg-pa-barra-linha">
              <span>{{ r.label }}</span>
              <small class="cvg-texto-3">{{ r.sub }}</small>
              <b>{{ pctTxt(r.pct) }}</b>
            </div>
            <div class="cvg-pa-barra-trilho">
              <i :style="{ width: `${Math.min(r.pct, 100)}%` }" />
            </div>
          </div>
        </section>

        <!-- Google -->
        <template v-if="painel.key === 'google'">
          <section class="cvg-painel-sec">
            <h3>Como é contado</h3>
            <p class="cvg-corpo">
              Do Google Search Console: quantas vezes a página apareceu na
              busca, quantos clicaram e a posição média, nos 28 dias que o
              Google já fechou{{
                gsc?.window
                  ? ` (${dateBR(gsc.window.since)} a ${dateBR(gsc.window.until)})`
                  : ''
              }}. Não segue a régua de período: o Google tem 2–3 dias de atraso.
            </p>
          </section>
          <section v-if="googlePorPagina.length" class="cvg-painel-sec">
            <h3>Aparições por endereço</h3>
            <div
              v-for="r in googlePorPagina"
              :key="r.label"
              class="cvg-pa-barra"
            >
              <div class="cvg-pa-barra-linha">
                <span>{{ r.label }}</span>
                <small class="cvg-texto-3">{{ r.sub }}</small>
                <b>{{ n(r.count) }}</b>
              </div>
              <div class="cvg-pa-barra-trilho">
                <i
                  :style="{
                    width: `${(r.count / totalDe(googlePorPagina)) * 100}%`,
                  }"
                />
              </div>
            </div>
          </section>
          <section class="cvg-painel-sec">
            <button
              type="button"
              class="cvg-btn cvg-btn--sm"
              @click="goOtimizar"
            >
              Ver termos e diagnósticos no Otimizar ›
            </button>
          </section>
        </template>

        <!-- páginas paradas -->
        <section v-if="painel.key === 'paradas'" class="cvg-painel-sec">
          <h3>Sem visita no período</h3>
          <p v-if="!semVisita.length" class="cvg-corpo">
            Todas as páginas no ar receberam visita.
          </p>
          <div
            v-for="p in semVisita"
            :key="p.id"
            class="cvg-linha cvg-visao-linha2"
          >
            <span>{{ p.emoji || '📄' }} {{ p.title }}</span>
            <small class="cvg-texto-3">{{ desdeTxt(p) }}</small>
          </div>
        </section>

        <!-- A/B -->
        <template v-if="painel.key === 'ab'">
          <p v-if="!abLista.length" class="cvg-corpo cvg-texto-3">
            Nenhum teste A/B rodando neste recorte.
          </p>
          <section v-for="t in abLista" :key="t.id" class="cvg-painel-sec">
            <h3>{{ t.title }}</h3>
            <div
              v-for="l in t.linhas"
              :key="l.key"
              class="cvg-linha cvg-visao-linha2"
            >
              <span>{{ l.key.toUpperCase() }} · {{ l.name }}</span>
              <small>{{ abTxt(l) }}</small>
            </div>
          </section>
        </template>

        <!-- a história de UMA página -->
        <template v-if="paginaAberta">
          <section class="cvg-painel-sec">
            <h3>Primários · {{ periodoTxt }}</h3>
            <div class="cvg-pa-mini">
              <span>
                <b>{{ n(paginaAberta.leads) }}</b>
                <small>leads</small>
              </span>
              <span>
                <b>{{ n(paginaAberta.booked) }}</b>
                <small>agendaram</small>
              </span>
              <span>
                <b>{{ n(paginaAberta.conversions) }}</b>
                <small>cirurgias</small>
              </span>
              <span>
                <b>{{ brl(paginaAberta.revenue) }}</b>
                <small>receita</small>
              </span>
            </div>
          </section>
          <section class="cvg-painel-sec">
            <h3>Secundários</h3>
            <div class="cvg-pa-mini">
              <span>
                <b>{{ n(paginaAberta.views) }}</b>
                <small>visitas</small>
              </span>
              <span>
                <b>{{ pctTxt(rate(paginaAberta.cta, paginaAberta.views)) }}</b>
                <small>clicam</small>
              </span>
              <span>
                <b>{{ pctTxt(rate(paginaAberta.leads, paginaAberta.cta)) }}</b>
                <small>chegam na caixa</small>
              </span>
              <span>
                <b>{{ fimTxt(paginaAberta) }}</b>
                <small>leram até o fim</small>
              </span>
            </div>
          </section>
          <section v-if="serie30.rotulos.length > 1" class="cvg-painel-sec">
            <h3>Últimos 30 dias</h3>
            <AreaChart
              :series="serie30.series"
              :labels="serie30.rotulos"
              :height="130"
            />
          </section>
          <section v-if="fontesDaPagina.length" class="cvg-painel-sec">
            <h3>De onde vieram (no período)</h3>
            <div
              v-for="r in fontesDaPagina"
              :key="r.label"
              class="cvg-pa-barra"
            >
              <div class="cvg-pa-barra-linha">
                <span>{{ r.label }}</span>
                <small class="cvg-texto-3">{{ n(r.leads) }} lead(s)</small>
                <b>{{ n(r.count) }}</b>
              </div>
              <div class="cvg-pa-barra-trilho">
                <i
                  :style="{
                    width: `${(r.count / totalDe(fontesDaPagina)) * 100}%`,
                  }"
                />
              </div>
            </div>
          </section>
          <section v-if="vindasDeOutra.length" class="cvg-painel-sec">
            <h3>Vindas de outra página (funil)</h3>
            <div
              v-for="r in vindasDeOutra"
              :key="r.label"
              class="cvg-linha cvg-visao-linha2"
            >
              <span>{{ r.label }}</span>
              <b>{{ n(r.count) }}</b>
            </div>
          </section>
          <section class="cvg-painel-sec">
            <h3>Terciários · no Google</h3>
            <template v-if="paginaAberta.gsc">
              <div class="cvg-pa-mini">
                <span>
                  <b>{{ n(paginaAberta.gsc.impressions) }}</b>
                  <small>aparições</small>
                </span>
                <span>
                  <b>{{ n(paginaAberta.gsc.clicks) }}</b>
                  <small>cliques</small>
                </span>
                <span>
                  <b>{{ fmtPos(paginaAberta.gsc.position) }}</b>
                  <small>posição</small>
                </span>
              </div>
              <div
                v-for="t in (paginaAberta.gsc.terms || []).slice(0, 6)"
                :key="t.query"
                class="cvg-linha cvg-visao-linha2"
              >
                <span>{{ t.query }}</span>
                <small>{{ termTxt(t) }}</small>
              </div>
            </template>
            <p v-else class="cvg-corpo cvg-texto-3">
              {{
                gscReady
                  ? 'A página ainda não apareceu no Google nos últimos 28 dias.'
                  : 'Search Console ainda não ligado.'
              }}
            </p>
          </section>
          <section
            v-if="paginaAberta.ab_variants?.length"
            class="cvg-painel-sec"
          >
            <h3>Teste A/B</h3>
            <div
              v-for="l in abLista.find(t => t.id === paginaAberta.id)?.linhas ||
              []"
              :key="l.key"
              class="cvg-linha cvg-visao-linha2"
            >
              <span>{{ l.key.toUpperCase() }} · {{ l.name }}</span>
              <small>{{ abTxt(l) }}</small>
            </div>
          </section>
          <section
            v-if="
              paginaAberta.id !== 'hub' && insightsOf(paginaAberta.id).length
            "
            class="cvg-painel-sec"
          >
            <h3>Pontos a melhorar</h3>
            <div
              v-for="i in insightsOf(paginaAberta.id)"
              :key="i.key"
              class="cvg-linha cvg-visao-linha2"
            >
              <span>💡 {{ i.title }}</span>
            </div>
            <button
              type="button"
              class="cvg-btn cvg-btn--sm mt-2"
              @click="goOtimizar"
            >
              Ver o que fazer no Otimizar ›
            </button>
          </section>
        </template>
      </template>
      <template v-if="paginaAberta && paginaAberta.id !== 'hub'" #rodape>
        <button
          v-if="paginaAberta.public_url"
          type="button"
          class="cvg-btn cvg-btn--sm"
          @click="abrirUrl(paginaAberta.public_url)"
        >
          <span class="i-lucide-external-link text-sm" /> Ver a página
        </button>
        <button
          v-if="paginaAberta.builder_url"
          type="button"
          class="cvg-btn cvg-btn--ghost cvg-btn--sm"
          @click="abrirUrl(paginaAberta.builder_url)"
        >
          <span class="i-lucide-wand-sparkles text-sm" /> Abrir a montagem
        </button>
      </template>
    </CvPainelLateral>
  </div>
</template>

<style lang="scss">
/* 📊 Análise de Páginas (16/10) — o que o guia ainda não tinha */
.cv-page.cvg-pa .cvg-cab > .flex-1 {
  /* o título ganha a linha inteira antes de espremer: o botão desce */
  flex: 1 1 280px;
}
.cv-page.cvg-pa .cvg-pa-regua {
  max-width: 100%;
  min-width: 0;
  overflow-x: auto;
}
.cv-page.cvg-pa .cvg-pa-ordem {
  width: auto;
}
.cv-page.cvg-pa .cvg-pa-recorte {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.cv-page.cvg-pa .cvg-pa-recorte-linha {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}
.cv-page.cvg-pa .cvg-pa-recorte-linha .cvg-rotulo {
  margin-right: 4px;
}
.cv-page.cvg-pa .cvg-pa-recorte .cvg-chip {
  border: 0;
}
.cv-page.cvg-pa .cvg-pa-recorte .cvg-chip.cvg-on {
  background: var(--cv);
  color: #fff;
}
.cv-page.cvg-pa .cvg-arejado-vitrine {
  margin-bottom: 0;
}

/* lista de páginas: quem · sparkline · números (primários fortes) */
.cv-page.cvg-pa .cvg-pa-linha {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  width: 100%;
  text-align: left;
  cursor: pointer;
  background: transparent;
}
.cv-page.cvg-pa .cvg-pa-linha:hover {
  background: rgb(var(--cv-rgb) / 0.05);
}
.cv-page.cvg-pa .cvg-pa-quem {
  display: flex;
  align-items: center;
  gap: 12px;
  flex: 1 1 260px;
  min-width: 0;
}
.cv-page.cvg-pa .cvg-pa-emoji {
  font-size: 22px;
  flex-shrink: 0;
}
.cv-page.cvg-pa .cvg-pa-chips {
  overflow-wrap: anywhere;
}
.cv-page.cvg-pa .cvg-pa-spark {
  width: 96px;
  height: 28px;
  flex-shrink: 0;
}
.cv-page.cvg-pa .cvg-pa-spark path {
  fill: none;
  stroke: var(--cv);
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
  vector-effect: non-scaling-stroke;
}
@media (max-width: 720px) {
  .cv-page.cvg-pa .cvg-pa-spark {
    display: none;
  }
}
.cv-page.cvg-pa .cvg-pa-nums {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 18px;
}
.cv-page.cvg-pa .cvg-pa-num {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  min-width: 52px;
  line-height: 1.1;
}
.cv-page.cvg-pa .cvg-pa-num b {
  font-size: 17px;
  font-weight: 600;
  color: var(--g-texto-2);
}
.cv-page.cvg-pa .cvg-pa-num--primario b {
  color: var(--g-texto);
  font-size: 19px;
}
.cv-page.cvg-pa .cvg-pa-num--terciario b {
  color: var(--g-texto-3);
  font-size: 15px;
}
.cv-page.cvg-pa .cvg-pa-num small {
  font-size: 11px;
  color: var(--g-texto-3);
}

/* cards de página: um degrau por nível */
.cv-page.cvg-pa .cvg-pa-card {
  text-align: left;
  cursor: pointer;
}
.cv-page.cvg-pa .cvg-pa-card-nivel {
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 14px;
  line-height: 20px;
  color: var(--g-texto-2);
}

/* barras do painel lateral (o mesmo desenho da Visão geral) */
.cvg-pa-barra {
  margin-bottom: 10px;
}
.cvg-pa-barra-linha {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  font-size: 14px;
  line-height: 20px;
}
.cvg-pa-barra-linha > span {
  flex: 1;
  min-width: 0;
}
.cvg-pa-barra-linha small {
  white-space: nowrap;
}
.cvg-pa-barra-linha b {
  font-weight: 600;
  white-space: nowrap;
}
.cvg-pa-barra-trilho {
  height: 6px;
  border-radius: 999px;
  background: rgb(var(--cv-rgb) / 0.12);
  overflow: hidden;
  margin-top: 4px;
}
.cvg-pa-barra-trilho i {
  display: block;
  height: 100%;
  border-radius: 999px;
  background: var(--cv-grad, var(--cv));
}
.cvg-pa-mini {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
  gap: 10px;
  margin-bottom: 6px;
}
.cvg-pa-mini span {
  display: flex;
  flex-direction: column;
  font-size: 12px;
  color: var(--g-texto-3);
}
.cvg-pa-mini b {
  font-size: 20px;
  line-height: 26px;
  font-weight: 600;
  color: var(--g-texto);
}
.cvg-painel .cvg-linha.cvg-visao-linha2 {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  min-height: 40px;
  font-size: 14px;
}

/* funis: trilha horizontal com a conversão de cada elo */
.cv-page.cvg-pa .cvg-pa-trilha {
  display: flex;
  align-items: stretch;
  overflow-x: auto;
  padding-bottom: 8px;
  margin-bottom: 12px;
}
.cv-page.cvg-pa .cvg-pa-no {
  width: 230px;
  flex-shrink: 0;
  gap: 6px;
}
.cv-page.cvg-pa .cvg-pa-seta {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 0 8px;
  flex-shrink: 0;
  font-size: 12px;
}
.cv-page.cvg-pa .cvg-pa-fim {
  align-self: center;
  margin-left: 8px;
  flex-shrink: 0;
}
.cv-page.cvg-pa .cvg-pa-sub {
  display: block;
  margin: 16px 0 4px;
}
.cv-page.cvg-pa .cvg-pa-solta {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
}
</style>
