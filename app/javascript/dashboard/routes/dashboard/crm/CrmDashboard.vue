<script setup>
// Dashboard CEVICO — paleta oficial: azul #0F5FA6, branco, roxo #7C3AED,
// dourado #D4A017; verde-limão #84CC16 reservado para o que é MUITO bom
// (valor em pipeline, cirurgias). "Conversa" no lugar de "lead".
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';
import KpiDetailPopup from 'dashboard/components-next/cevico/KpiDetailPopup.vue';
import {
  Chart as ChartJS,
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  ArcElement,
  PointElement, LineElement, Filler,
} from 'chart.js';
import { Bar, Doughnut, Line } from 'vue-chartjs';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import ProMaxStudio from './components/ProMaxStudio.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import { useAdmin } from 'dashboard/composables/useAdmin';
import {
  inboxGradientFor,
  inboxSolidFor,
  ALL_INBOXES_GRADIENT,
} from 'dashboard/helper/cevicoInboxColors.js';

ChartJS.register(
  Title, Tooltip, Legend,
  BarElement, CategoryScale, LinearScale,
  ArcElement,
  PointElement, LineElement, Filler,
);

const props = defineProps({
  pipeline: { type: Object, required: true },
});

const AZUL = '#0F5FA6';
const ROXO = '#7C3AED';
const OURO = '#D4A017';
const LIME = '#84CC16';
const PALETTE = [AZUL, ROXO, OURO, LIME, '#3B82F6', '#A78BFA', '#F0C420', '#22D3EE', '#EA580C', '#10B981', '#F472B6', '#94A3B8'];

const store   = useStore();
const router  = useRouter();
const route   = useRoute();
const data    = ref(null);

// ── 🟥 item 103 (20/07): ambiente de PERDAS — padrão de etiquetas + análise ──
// os motivos oficiais de perda da CEVICO; cada um vira uma etiqueta vermelha
// "perda_*" que a atendente aplica no balão/card quando o lead esfria
const LOSS_LABELS = [
  { title: 'perda_nao_respondeu', name: 'Não respondeu' },
  { title: 'perda_sem_interesse', name: 'Sem interesse' },
  { title: 'perda_valor', name: 'Valor' },
  { title: 'perda_convenio', name: 'Convênio' },
  { title: 'perda_distancia', name: 'Distância' },
  { title: 'perda_momento_futuro', name: 'Momento futuro' },
];
const lossNameOf = title =>
  LOSS_LABELS.find(l => l.title === title)?.name ||
  title.replace('perda_', '').replaceAll('_', ' ');
const accountLabels = computed(() => store.getters['labels/getLabels'] || []);
const missingLossLabels = computed(() =>
  LOSS_LABELS.filter(l => !accountLabels.value.some(al => al.title === l.title))
);
const creatingLossLabels = ref(false);
const createLossLabels = async () => {
  if (creatingLossLabels.value) return;
  creatingLossLabels.value = true;
  try {
    // sequencial de propósito: cria uma a uma, sem estourar a API
    const pending = [...missingLossLabels.value];
    for (let i = 0; i < pending.length; i += 1) {
      // eslint-disable-next-line no-await-in-loop
      await store.dispatch('labels/create', {
        title: pending[i].title,
        description: `Motivo de perda: ${pending[i].name}`,
        color: '#EF4444',
        show_on_sidebar: false,
      });
    }
  } finally {
    creatingLossLabels.value = false;
  }
};
// perdas por motivo no período — v2 (item 145): o bloco próprio `losses`
// traz também a tendência vs o período anterior e o VALOR dos cards
// perdidos (dos que têm valor preenchido)
const lossRows = computed(() => {
  const counted = data.value?.losses?.items ||
    (data.value?.by_label?.items || []).filter(i => i.label?.startsWith('perda_'));
  const rows = LOSS_LABELS.map(l => {
    const c = counted.find(x => x.label === l.title) || {};
    return {
      title: l.title,
      name: l.name,
      count: c.count || 0,
      prev: c.prev ?? null,
      value: c.value || 0,
      valueCount: c.value_count || 0,
    };
  });
  // etiquetas perda_* extras criadas à mão também entram
  counted.forEach(c => {
    if (!rows.some(r => r.title === c.label)) {
      rows.push({
        title: c.label, name: lossNameOf(c.label), count: c.count || 0,
        prev: c.prev ?? null, value: c.value || 0, valueCount: c.value_count || 0,
      });
    }
  });
  return rows.sort((a, b) => b.count - a.count);
});
const lossTotal = computed(() => lossRows.value.reduce((s, r) => s + r.count, 0));
const lossValueTotal = computed(() => lossRows.value.reduce((s, r) => s + (r.value || 0), 0));
const lossPrevLabel = computed(() => data.value?.losses?.previous_label || 'período anterior');
// % sobre os leads do período (a coorte do funil) — perda relativa à entrada
const lossPctOfLeads = row => {
  const base = data.value?.kpis?.cohort_total || 0;
  return base ? Math.round((row.count / base) * 1000) / 10 : null;
};
// tendência: perda SUBIR é ruim (vermelho); cair é bom (verde)
const lossTrend = row => {
  if (row.prev === null || row.prev === undefined) return null;
  if (row.count === row.prev) return null;
  const up = row.count > row.prev;
  return {
    arrow: up ? '▲' : '▼',
    color: up ? '#DC2626' : '#059669',
    title: `${up ? 'subiu' : 'caiu'} vs ${lossPrevLabel.value} (antes: ${row.prev})`,
  };
};
// 🛟 lista de resgate: clique no motivo → os pacientes que estão lá
const lossModal = ref(null);
const lossContacts = ref([]);
const loadingLossContacts = ref(false);
const openLossModal = async row => {
  if (!row.count) return;
  lossModal.value = row;
  loadingLossContacts.value = true;
  lossContacts.value = [];
  try {
    const { data: res } = await CrmAPI.getLossContacts(props.pipeline.id, {
      label: row.title,
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
      ...(inboxFilterActive.value ? { inbox_ids: [...selectedInboxIds.value] } : {}),
    });
    lossContacts.value = res.items || [];
  } catch {
    lossContacts.value = [];
  } finally {
    loadingLossContacts.value = false;
  }
};
const openPatientSpace = c =>
  router.push(`/app/accounts/${route.params.accountId}/patient/${c.contact_id}`);
onMounted(() => {
  if (!accountLabels.value.length) store.dispatch('labels/get').catch(() => {});
});
const loading = ref(false);
const error   = ref(false);

// régua de período PADRÃO CEVICO (06/08) — default 'month' (antes: 30 dias)
const period = ref({ preset: 'month', from: '', to: '' });

// ── Load ─────────────────────────────────────────────────────────────

// ── 📥 Filtro por caixa de entrada (missão 03/08) ────────────────────
// a caixa "dona" do lead é a da PRIMEIRA conversa dele. MESMO modo de
// seleção das pílulas de Conversas (pedido 03/08): aceita VÁRIAS caixas
// ao mesmo tempo, "Todas" limpa, e a escolha fica salva no navegador
// (pré-selecionada ao voltar no dashboard).
const DASH_INBOX_PILLS_KEY = 'cevico_dashboard_inboxes';
const { isAdmin } = useAdmin();
const accountInboxes = useMapGetter('inboxes/getInboxes');
const inboxOptions = computed(() =>
  [...(accountInboxes.value || [])].sort((a, b) => a.id - b.id)
);
const inboxGrad = idOrName =>
  inboxGradientFor(accountInboxes.value || [], idOrName);
const inboxDot = idOrName =>
  inboxSolidFor(accountInboxes.value || [], idOrName);

const loadSavedInboxPills = () => {
  try {
    const raw = JSON.parse(localStorage.getItem(DASH_INBOX_PILLS_KEY) || '[]');
    return Array.isArray(raw) ? raw.map(Number).filter(Boolean) : [];
  } catch {
    return [];
  }
};
const selectedInboxIds = ref(loadSavedInboxPills());
const activeInboxSet = computed(() => new Set(selectedInboxIds.value));
const inboxFilterActive = computed(() => selectedInboxIds.value.length > 0);

const selectInboxPill = id => {
  if (!id) {
    // "Todas": limpa a seleção
    selectedInboxIds.value = [];
  } else {
    const base = [...selectedInboxIds.value];
    const idx = base.indexOf(id);
    if (idx >= 0) base.splice(idx, 1);
    else base.push(id);
    selectedInboxIds.value = base;
  }
  localStorage.setItem(
    DASH_INBOX_PILLS_KEY,
    JSON.stringify(selectedInboxIds.value)
  );
};

const selectedInboxNames = computed(() =>
  inboxOptions.value
    .filter(i => activeInboxSet.value.has(i.id))
    .map(i => i.name)
    .join(', ')
);

const load = async () => {
  loading.value = true;
  error.value   = false;
  try {
    data.value = await store.dispatch('crm/fetchDashboard', {
      pipelineId: props.pipeline.id,
      preset: period.value.preset,
      ...(period.value.preset === 'custom'
        ? { from: period.value.from, to: period.value.to }
        : {}),
      inboxIds: inboxFilterActive.value
        ? [...selectedInboxIds.value]
        : undefined,
    });
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
};

// metas oficiais do mês (Painel de Metas) → selos de recorde/meta nos KPIs
const goals = useCevicoGoals();

// ── 🔍 POPUP dos KPIs (item 145): o mesmo popup-análise do Meu Painel —
// gráfico do cesto c/ mini-régua, período anterior, meta e 📌 ações ──
const kpiPopup = ref(null);
const openKpiPopup = key => {
  const k = data.value?.kpis || {};
  const defs = {
    new_leads: {
      label: 'Novas no período', icon: 'i-lucide-user-plus',
      grad: 'linear-gradient(135deg, #0F5FA6, #3B82F6)',
      value: k.new_in_period ?? 0,
      sub: 'caixas de captação · igual ao Meu Painel',
      chartKey: 'new_leads',
      goalTarget: goals.goalFor('new_leads')?.target || null,
      about: 'Contatos novos do período pelas caixas de captação — mesma régua do Meu Painel. O gráfico mostra a chegada balde a balde, com o período anterior tracejado.',
    },
    closed_value: {
      label: 'Valor fechado', icon: 'i-lucide-badge-dollar-sign',
      grad: 'linear-gradient(135deg, #65A30D, #84CC16)',
      value: formatCurrency(k.closed_value),
      sub: 'cirurgias dos leads do período',
      chartKey: 'revenue', format: 'currency',
      about: 'O número do card soma o valor dos leads do período que fecharam (coorte). O gráfico mostra o faturamento REGISTRADO em cada balde (entrou em "Cirurgia Realizada") — dois ângulos do mesmo fechamento.',
    },
    closed_count: {
      label: 'Fechamentos', icon: 'i-lucide-heart-pulse',
      grad: 'linear-gradient(135deg, #B8860B, #D4A017)',
      value: k.closed_count ?? 0,
      sub: 'leads do período que chegaram à cirurgia',
      chartMatch: 'cirurgia agendada',
      goalTarget: goals.goalFor('surgeries_booked')?.target || null,
      components: ['indications'],
      about: 'O card conta a coorte (leads do período que já fecharam). O gráfico mostra o ritmo: entradas na coluna "Cirurgia Agendada" em cada balde.',
    },
    close_rate: {
      label: 'Taxa de fechamento', icon: 'i-lucide-percent',
      grad: 'linear-gradient(135deg, #5B21B6, #7C3AED)',
      value: `${k.close_rate ?? 0}%`,
      sub: `${k.closed_count ?? 0} de ${k.cohort_total ?? 0} leads do período`,
      chartMatch: 'cirurgia agendada',
      components: ['new_leads', 'indications'],
      about: 'De cada 100 leads do período, quantos chegaram à cirurgia. O gráfico mostra o ritmo de fechamento; as séries abaixo mostram a matéria-prima (entrada e indicações).',
    },
  };
  kpiPopup.value = defs[key] || null;
};

// ── 💰 DINHEIRO PARADO (item 145): a coluna ativa com mais R$ estagnado
// (cards sem se mexer há 15+ dias) vira aviso com atalho pro board ──
const stalledSpot = computed(() => {
  const rows = data.value?.value_by_stage || [];
  const candidates = rows.filter(
    s => (s.stalled_value || 0) > 0 && !/realizada|pós|sem indica/i.test(s.stage_name || '')
  );
  if (!candidates.length) return null;
  return [...candidates].sort((a, b) => b.stalled_value - a.stalled_value)[0];
});
const goToBoardStage = stage =>
  router.push({
    name: 'crm_board',
    params: { accountId: route.params.accountId },
    query: { focus_stage: stage.stage_id },
  });

onMounted(() => {
  load();
  goals.load();
  if (!(accountInboxes.value || []).length) {
    store.dispatch('inboxes/get').catch(() => {});
  }
});
watch(period, load, { deep: true });
watch(selectedInboxIds, load);
watch(() => props.pipeline?.id, load);

// ── Helpers ───────────────────────────────────────────────────────────

const formatDuration = (mins) => {
  if (!mins || mins <= 0) return '—';
  if (mins < 60)  return `${mins}min`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  if (h < 24) return m > 0 ? `${h}h ${m}min` : `${h}h`;
  const d = Math.floor(h / 24);
  const rh = h % 24;
  return rh > 0 ? `${d}d ${rh}h` : `${d}d`;
};

const formatSeconds = (secs) => {
  if (!secs || secs <= 0) return '—';
  if (secs < 60) return `${Math.round(secs)}s`;
  return formatDuration(Math.round(secs / 60));
};

const formatCurrency = (val) =>
  val > 0
    ? 'R$ ' + Number(val).toLocaleString('pt-BR', { maximumFractionDigits: 0 })
    : 'R$ 0';

// com centavos — CPL/CAC pequenos perdem o sentido arredondados
const formatMoney2 = val =>
  val || val === 0
    ? 'R$ ' +
      Number(val).toLocaleString('pt-BR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })
    : '—';

// ── 📥 Resultados por caixa de entrada ───────────────────────────────
const inboxRows = computed(() => data.value?.inbox_results?.rows || []);
const showFinancials = computed(
  () => isAdmin.value && data.value?.inbox_results?.admin
);

// frase por extenso do retorno — a régua que o Guilherme usa nas reuniões
const roasPhrase = row => {
  if (!row.roas) return '';
  return `Cada R$ 1 investido voltou como R$ ${Number(row.roas).toLocaleString(
    'pt-BR',
    { minimumFractionDigits: 2, maximumFractionDigits: 2 }
  )}`;
};

// edição do investimento (só admin) — por caixa: manual (R$/mês) ou
// automático puxando o gasto REAL do Meta Ads ("as coisas conversam");
// Google automático chega quando o Google liberar o developer token
const editingInvest = ref(false);
const savingInvest = ref(false);
const investDraft = ref({});
// portas de entrada (caixas de captação): régua da atribuição por caixa
const captureDraft = ref([]);
const openInvestEditor = () => {
  const draft = {};
  inboxOptions.value.forEach(i => {
    const row = inboxRows.value.find(r => r.inbox_id === i.id);
    draft[i.id] = {
      mode: ['meta_auto', 'google_auto'].includes(row?.investment_mode)
        ? row.investment_mode
        : 'manual',
      monthly: row?.investment_monthly || null,
    };
  });
  investDraft.value = draft;
  captureDraft.value = [...(data.value?.inbox_results?.capture_inbox_ids || [])];
  editingInvest.value = true;
};
const toggleCapture = id => {
  const idx = captureDraft.value.indexOf(id);
  if (idx >= 0) captureDraft.value.splice(idx, 1);
  else captureDraft.value.push(id);
};
const saveInvestments = async () => {
  savingInvest.value = true;
  try {
    const payload = {};
    Object.entries(investDraft.value).forEach(([id, cfg]) => {
      if (cfg.mode === 'meta_auto' || cfg.mode === 'google_auto') {
        payload[id] = { mode: cfg.mode };
        return;
      }
      const v = parseFloat(String(cfg.monthly ?? '').replace(',', '.'));
      if (v > 0) payload[id] = { mode: 'manual', monthly: v };
    });
    await store.dispatch('crm/updateInboxInvestments', {
      investments: payload,
      captureInboxIds: [...captureDraft.value],
    });
    editingInvest.value = false;
    await load();
  } catch {
    // mantém o editor aberto para tentar de novo
  } finally {
    savingInvest.value = false;
  }
};

// ── 💰 Faturamento por caixa — áreas em camadas (modelo enviado 03/08) ──
const REVENUE_FALLBACK = { outras: '#64748B', none: '#475569' };
const revenueSeriesColor = serie => {
  if (serie.inbox_id === 'outras') return REVENUE_FALLBACK.outras;
  if (!serie.inbox_id) return REVENUE_FALLBACK.none;
  return inboxDot(serie.inbox_id);
};

const revenueGranularityLabel = computed(() => {
  const g = data.value?.revenue_over_time?.granularity;
  if (g === 'hour') return 'por hora do dia';
  if (g === 'week') return 'por semana';
  if (g === 'month') return 'por mês';
  return 'por dia';
});

const revenueTotal = computed(() =>
  (data.value?.revenue_over_time?.series || []).reduce(
    (sum, s) => sum + s.values.reduce((a, v) => a + v, 0),
    0
  )
);

const revenueChart = computed(() => {
  const rot = data.value?.revenue_over_time;
  if (!rot?.points?.length || !rot?.series?.length) return null;

  // linha do TOTAL (somatório das caixas): dourada, tracejada, fora da
  // pilha ('stack' próprio = valor absoluto). Primeira da lista = desenha
  // por cima das camadas.
  const totalValues = rot.points.map((_, i) =>
    rot.series.reduce((sum, s) => sum + (s.values[i] || 0), 0)
  );
  const totalDataset = {
    label: 'Total (todas as caixas)',
    data: totalValues,
    borderColor: '#FBBF24',
    borderWidth: 2.5,
    borderDash: [6, 4],
    pointRadius: 0,
    pointHoverRadius: 4,
    pointHoverBackgroundColor: '#FFFFFF',
    tension: 0.45,
    fill: false,
    stack: 'cevico-total',
  };

  const datasets = [
    totalDataset,
    ...rot.series.map(serie =>
      areaDataset(serie.name, serie.values, revenueSeriesColor(serie))
    ),
  ];
  return {
    data: { labels: rot.points.map(p => p.label), datasets },
    options: layeredAreaOptions({ stacked: true, format: formatCurrency }),
  };
});

// ── Charts ────────────────────────────────────────────────────────────

// fatia com gradiente vertical (mesmo aspecto "macio e brilhante" do donut
// de Tarefas): topo mais claro, base na cor cheia
const shinySlices = colors => ctx => {
  const base = colors[ctx.dataIndex % colors.length];
  const { chartArea, ctx: c } = ctx.chart;
  if (!chartArea) return base;
  const g = c.createLinearGradient(chartArea.left, chartArea.top, chartArea.left, chartArea.bottom);
  g.addColorStop(0, base + '99');
  g.addColorStop(1, base);
  return g;
};

const CHART_OPTIONS_BASE = {
  responsive: true,
  maintainAspectRatio: false,
  plugins: { legend: { display: false } },
  animation: { duration: 400 },
};

// ── estilo compartilhado: áreas em camadas com gradiente sobre navy ──
// (modelo enviado 03/08 — usado no Faturamento e nas Conversas ao longo
// do tempo, mesmo código pros dois)
const areaDataset = (label, values, solid) => ({
  label,
  data: values,
  borderColor: solid,
  borderWidth: 2,
  pointRadius: 0,
  pointHoverRadius: 4,
  pointHoverBackgroundColor: '#FFFFFF',
  tension: 0.45,
  fill: true,
  // gradiente vertical: cor viva em cima desvanecendo pra base — o
  // visual "camadas de luz" da referência
  backgroundColor: ctx => {
    const { chartArea, ctx: c } = ctx.chart;
    if (!chartArea) return solid + '66';
    const g = c.createLinearGradient(0, chartArea.top, 0, chartArea.bottom);
    g.addColorStop(0, solid + 'CC');
    g.addColorStop(0.65, solid + '55');
    g.addColorStop(1, solid + '0D');
    return g;
  },
});

const layeredAreaOptions = ({ stacked = false, format = v => v } = {}) => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: {
      display: true,
      position: 'bottom',
      labels: { boxWidth: 12, padding: 14, font: { size: 11 }, color: '#CBD5E1' },
    },
    tooltip: {
      callbacks: { label: ctx => ` ${ctx.dataset.label}: ${format(ctx.raw)}` },
    },
  },
  scales: {
    y: {
      stacked,
      beginAtZero: true,
      ticks: { maxTicksLimit: 6, precision: 0, color: '#94A3B8', callback: v => format(v) },
      grid: { color: 'rgba(148, 163, 184, 0.14)' },
    },
    x: {
      ticks: { maxTicksLimit: 14, color: '#94A3B8' },
      grid: { display: false },
    },
  },
  animation: { duration: 500, easing: 'easeOutQuart' },
});

// Conversas ao longo do tempo — áreas em camadas SOBREPOSTAS (agendou e
// operou são subconjuntos das novas, então nada de empilhar); cores vivas
// pra ler bem sobre o navy
const timelineChart = computed(() => {
  if (!data.value?.created_over_time) return null;
  const t = data.value.created_over_time;
  // o backend manda o rótulo pronto na granularidade certa (hora/dia/semana)
  const labels = t.map(d => {
    if (d.label) return d.label;
    const dt = new Date(d.date + 'T12:00:00');
    return dt.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  });
  return {
    data: {
      labels,
      datasets: [
        areaDataset('Novas conversas', t.map(d => d.count), '#3B82F6'),
        areaDataset('Chegaram a agendar', t.map(d => d.agendamentos), '#FBBF24'),
        areaDataset('Chegaram à cirurgia', t.map(d => d.cirurgias), '#84CC16'),
      ],
    },
    options: layeredAreaOptions(),
  };
});

// legenda do subtítulo acompanha a granularidade escolhida pelo backend
const timelineGranularity = computed(() => {
  const g = data.value?.created_over_time?.[0]?.granularity;
  if (g === 'hour') return 'por hora do dia';
  if (g === 'week') return 'por semana';
  if (g === 'month') return 'por mês';
  return 'por dia';
});

// Conversas por caixa de entrada (doughnut)
const inboxChart = computed(() => {
  if (!data.value?.by_inbox?.length) return null;
  const o = data.value.by_inbox;
  return {
    data: {
      labels: o.map(x => x.inbox),
      datasets: [{
        data: o.map(x => x.count),
        backgroundColor: shinySlices(PALETTE),
        borderWidth: 0,
        borderRadius: 14,
        spacing: 3,
        hoverOffset: 6,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: true, position: 'bottom', labels: { padding: 12, boxWidth: 12, font: { size: 11 } } },
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} conversas (${ctx.label})` } },
      },
      cutout: '66%',
      animation: { duration: 500, easing: 'easeOutQuart' },
    },
  };
});

// Etiquetas (doughnut com volume e %)
const labelChart = computed(() => {
  const items = data.value?.by_label?.items || [];
  if (!items.length) return null;
  return {
    data: {
      labels: items.map(x => x.label),
      datasets: [{
        data: items.map(x => x.count),
        backgroundColor: shinySlices(PALETTE),
        borderWidth: 0,
        borderRadius: 14,
        spacing: 3,
        hoverOffset: 6,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: ctx => {
              const item = items[ctx.dataIndex];
              return ` ${item.label}: ${item.count} (${item.pct}%)`;
            },
          },
        },
      },
      cutout: '66%',
      animation: { duration: 500, easing: 'easeOutQuart' },
    },
  };
});

// Conversas por etapa (horizontal)
const funnelChart = computed(() => {
  if (!data.value?.funnel) return null;
  const f = data.value.funnel;
  return {
    data: {
      labels: f.map(s => s.stage_name),
      datasets: [{
        data: f.map(s => s.count),
        backgroundColor: f.map((_, i) => PALETTE[i % PALETTE.length] + 'DD'),
        borderRadius: 8,
        borderSkipped: false,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      indexAxis: 'y',
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ` ${ctx.raw} conversas` } },
      },
      scales: {
        x: { ticks: { stepSize: 1 }, grid: { color: 'rgba(120,140,180,0.12)' } },
        y: { grid: { display: false } },
      },
    },
  };
});

// Valor em cada etapa do pipeline
const valueChart = computed(() => {
  if (!data.value?.value_by_stage) return null;
  const v = data.value.value_by_stage.filter(s => s.value > 0);
  if (!v.length) return null;
  return {
    data: {
      labels: v.map(s => s.stage_name),
      datasets: [{
        data: v.map(s => s.value),
        backgroundColor: v.map((_, i) => [AZUL, ROXO, OURO, LIME][i % 4] + 'E6'),
        borderRadius: 10,
        borderSkipped: false,
        maxBarThickness: 56,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ' R$ ' + Number(ctx.raw).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) } },
      },
      scales: {
        y: { grid: { color: 'rgba(120,140,180,0.12)' } },
        x: { grid: { display: false } },
      },
    },
  };
});

// Tempo médio por etapa
const timeChart = computed(() => {
  if (!data.value?.avg_time_by_stage) return null;
  const t = data.value.avg_time_by_stage.filter(s => s.avg_minutes > 0);
  if (!t.length) return null;
  return {
    data: {
      labels: t.map(s => s.stage_name),
      datasets: [{
        data: t.map(s => s.avg_minutes),
        backgroundColor: t.map((_, i) => PALETTE[i % PALETTE.length] + 'B3'),
        borderRadius: 10,
        borderSkipped: false,
        maxBarThickness: 56,
      }],
    },
    options: {
      ...CHART_OPTIONS_BASE,
      plugins: {
        ...CHART_OPTIONS_BASE.plugins,
        tooltip: { callbacks: { label: ctx => ' ' + formatDuration(ctx.raw) } },
      },
      scales: {
        y: { grid: { color: 'rgba(120,140,180,0.12)' }, ticks: { callback: v => formatDuration(v) } },
        x: { grid: { display: false } },
      },
    },
  };
});

// cores das 5 faixas de NPS (promotores → detratores)
const NPS_BAND_GRADS = [
  ['#059669', '#34D399'],
  ['#65A30D', '#A3E635'],
  ['#B8860B', '#D4A017'],
  ['#EA580C', '#FB923C'],
  ['#DC2626', '#F87171'],
];

// ── Responsividade ────────────────────────────────────────────────────
const resp = computed(() => data.value?.responsiveness ?? null);

// gradientes harmônicos (azul → roxo → dourado → laranja → verde → ciano),
// seguindo a paleta oficial do dashboard
// tema "Flor del Mar": fúcsia vibrante sobre azul-mar (referências)
const RESP_GRADS = [
  ['#9D174D', '#EC4899'],
  ['#1D4ED8', '#60A5FA'],
  ['#BE185D', '#F472B6'],
  ['#0369A1', '#38BDF8'],
  ['#DB2777', '#F9A8D4'],
  ['#0D9488', '#2DD4BF'],
  ['#7C3AED', '#A78BFA'],
  ['#B8860B', '#D4A017'],
];

// item 129: barras viraram CURVA DE QUEDA — a inclinação entre dois pontos
// é o tamanho do vazamento entre as etapas (pedido 10/08)
const respCurve = computed(() => {
  if (!resp.value?.stages?.length) return null;
  const rows = resp.value.stages.slice(1);
  return {
    data: {
      labels: rows.map(s => s.stage_name),
      datasets: [
        {
          label: '% que chegou até a etapa',
          data: rows.map(s => s.reached_pct),
          borderColor: '#7C3AED',
          backgroundColor: 'rgba(124, 58, 237, 0.16)',
          fill: true,
          tension: 0.4,
          borderWidth: 3,
          pointRadius: 4.5,
          pointHoverRadius: 7,
          pointBackgroundColor: rows.map((s, i) => RESP_GRADS[i % RESP_GRADS.length][0]),
          pointBorderColor: '#fff',
          pointBorderWidth: 1.5,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: ctx => {
              const s = rows[ctx.dataIndex];
              return `${s.reached_pct}% · ${s.reached.toLocaleString('pt-BR')} conversas chegaram até aqui`;
            },
          },
        },
      },
      scales: {
        x: { grid: { display: false }, ticks: { maxRotation: 45, font: { size: 10 } } },
        y: {
          beginAtZero: true,
          grid: { color: 'rgba(148,163,184,0.15)' },
          ticks: { callback: v => `${v}%` },
        },
      },
    },
  };
});

// estúdio PRO MAX (item 129/129B): null = fechado; '' = variáveis padrão;
// 'timeline' = conversas por caixa; 'revenue' = faturamento por caixa
const proMaxFocus = ref(null);

// ── Atendimento por agente ────────────────────────────────────────────
const selectedAgentId = ref('all');

const agentRows = computed(() => data.value?.agents?.rows ?? []);

const agentView = computed(() => {
  if (selectedAgentId.value === 'all') {
    return {
      name: 'Todos os agentes',
      open: agentRows.value.reduce((a, r) => a + r.open, 0) + (data.value?.agents?.unassigned?.open || 0),
      unanswered: agentRows.value.reduce((a, r) => a + r.unanswered, 0) + (data.value?.agents?.unassigned?.unanswered || 0),
      avg_first_response_seconds: (() => {
        const vals = agentRows.value.map(r => r.avg_first_response_seconds).filter(v => v);
        return vals.length ? vals.reduce((a, v) => a + v, 0) / vals.length : null;
      })(),
    };
  }
  return agentRows.value.find(r => r.id === selectedAgentId.value) || null;
});
</script>

<template>
  <div class="bg-n-solid-1 p-8 min-h-full">

    <!-- Header do dashboard -->
    <div class="flex items-center justify-between mb-8 flex-wrap gap-4">
      <div>
        <h2 class="text-lg font-bold text-n-slate-12">Dashboard — {{ pipeline.name }}</h2>
        <p class="text-xs text-n-slate-10 mt-0.5">Métricas automáticas com base nas conversas do funil</p>
      </div>
      <!-- Régua de período padrão CEVICO -->
      <PeriodRuler v-model="period" />
    </div>

    <!-- 📥 Filtro por caixa de entrada — o dashboard INTEIRO responde:
         quem "pertence" à caixa é o lead cuja PRIMEIRA conversa foi nela.
         Mesmo modo de seleção das pílulas de Conversas: aceita VÁRIAS
         caixas, "Todas" limpa, escolha salva no navegador -->
    <div class="flex items-center gap-2 mb-8 flex-wrap">
      <div class="flex flex-wrap items-center min-h-[34px] bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5">
        <span class="i-lucide-inbox text-sm ml-2 mr-0.5 text-n-slate-10 flex-shrink-0" />
        <button
          class="px-3 h-7 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0"
          :class="activeInboxSet.size === 0 ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeInboxSet.size === 0 ? { background: ALL_INBOXES_GRADIENT } : {}"
          @click="selectInboxPill(0)"
        >
          Todas
        </button>
        <button
          v-for="inbox in inboxOptions"
          :key="inbox.id"
          class="px-3 h-7 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0 flex items-center gap-1.5"
          :class="activeInboxSet.has(inbox.id) ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeInboxSet.has(inbox.id) ? { background: inboxGrad(inbox.id) } : {}"
          :title="activeInboxSet.has(inbox.id) ? 'Clique para tirar esta caixa da seleção' : 'Clique para somar esta caixa à seleção'"
          @click="selectInboxPill(inbox.id)"
        >
          <span
            v-if="!activeInboxSet.has(inbox.id)"
            class="w-1.5 h-1.5 rounded-full flex-shrink-0"
            :style="{ background: inboxDot(inbox.id) }"
          />
          {{ inbox.name }}
        </button>
      </div>
      <span v-if="inboxFilterActive" class="text-[11px] text-n-slate-10">
        mostrando só os leads que <b>chegaram</b> por: {{ selectedInboxNames }} (primeira conversa)
      </span>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="flex items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-loader-2 animate-spin text-2xl mr-2" />
      <span class="text-sm">Carregando métricas...</span>
    </div>

    <!-- Error -->
    <div v-else-if="error" class="flex flex-col items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-alert-circle text-3xl mb-2 text-red-400" />
      <p class="text-sm mb-3">Erro ao carregar o dashboard.</p>
      <button class="text-xs text-n-brand hover:underline" @click="load">Tentar novamente</button>
    </div>

    <!-- Content -->
    <div v-else-if="data">

      <!-- KPIs (padrão CEVICO: DashKpi c/ selos de recorde/meta do mês) —
           auto-ajuste (item 80): os cards sempre CABEM no espaço, em
           qualquer largura, sem cortar rótulo -->
      <!-- item 145: os KPIs com série viram botões — clique abre o popup
           c/ gráfico, mini-régua, período anterior, meta e 📌 ações -->
      <div class="grid gap-4 mb-8" style="grid-template-columns: repeat(auto-fit, minmax(170px, 1fr))">
        <DashKpi
          label="Total no funil"
          :value="data.kpis.total_leads"
          sub="desde o início (não muda com o período)"
          from="#0F5FA6"
          to="#0B4A82"
        />
        <div class="cursor-pointer transition-transform hover:scale-[1.02]" title="Ver o gráfico e a análise deste indicador" @click="openKpiPopup('new_leads')">
          <DashKpi
            label="Novas no período"
            :value="data.kpis.new_in_period"
            sub="caixas Google + Instagram · igual ao Meu Painel"
            value-color="#0F5FA6"
            :state="goals.stateFor('new_leads')"
            :goal="goals.goalFor('new_leads')"
          />
        </div>
        <div class="cursor-pointer transition-transform hover:scale-[1.02]" title="Ver o gráfico e a análise deste indicador" @click="openKpiPopup('closed_value')">
          <DashKpi
            label="Valor fechado"
            :value="Math.round(data.kpis.closed_value || 0)"
            prefix="R$ "
            sub="cirurgias dos leads do período"
            from="#65A30D"
            to="#84CC16"
          />
        </div>
        <div class="cursor-pointer transition-transform hover:scale-[1.02]" title="Ver o gráfico e a análise deste indicador" @click="openKpiPopup('closed_count')">
          <DashKpi
            label="Fechamentos"
            :value="data.kpis.closed_count"
            sub="leads do período que chegaram à cirurgia"
            from="#B8860B"
            to="#D4A017"
            :state="goals.stateFor('surgeries_booked')"
            :goal="goals.goalFor('surgeries_booked')"
          />
        </div>
        <div class="cursor-pointer transition-transform hover:scale-[1.02]" title="Ver o gráfico e a análise deste indicador" @click="openKpiPopup('close_rate')">
          <DashKpi
            label="Taxa de fechamento"
            :value="`${data.kpis.close_rate}%`"
            :sub="`${data.kpis.closed_count} de ${data.kpis.cohort_total} leads do período`"
            from="#5B21B6"
            to="#7C3AED"
          />
        </div>
        <DashKpi
          label="Tempo médio"
          :value="formatDuration(data.kpis.avg_conversion_minutes)"
          sub="da chegada até fechar a cirurgia"
        />
      </div>

      <!-- 📥 Resultados por caixa de entrada (missão 03/08): Google ×
           Instagram lado a lado — conversão, receita e, p/ admin, o
           retorno do anúncio (CPL/CAC/ROAS/ROI) -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center justify-between flex-wrap gap-3 mb-2">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-inbox text-white text-sm" />
            </span>
            Resultados por caixa de entrada
          </h3>
          <button
            v-if="showFinancials && !editingInvest"
            class="text-xs font-semibold px-3.5 py-2 rounded-xl text-white hover:opacity-90 shadow flex items-center gap-1.5"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            @click="openInvestEditor"
          >
            <span class="i-lucide-circle-dollar-sign text-sm" />
            Informar investimento mensal
          </button>
        </div>
        <p class="text-[11px] text-n-slate-10 mb-5">
          cada lead pertence à caixa em que <b>chegou</b> (primeira conversa) — as taxas olham os leads do período escolhido
        </p>

        <!-- editor do investimento mensal (admin) -->
        <div
          v-if="editingInvest"
          class="rounded-xl border border-dashed p-4 mb-5"
          style="border-color: rgba(212, 160, 23, 0.45); background: rgba(212, 160, 23, 0.06)"
        >
          <p class="text-xs text-n-slate-11 mb-3">
            De onde vem o investimento de cada caixa? <b>Meta (automático)</b> e
            <b>Google (automático)</b> puxam o gasto REAL do período direto das
            integrações. <b>R$/mês</b> = você digita e o sistema converte para o período.
            Caixa sem anúncio = deixe em branco.
            <span class="text-n-slate-10">O Google automático precisa da conta de serviço
            configurada em Integrações → Google Ads (passo a passo lá).</span>
          </p>
          <div class="space-y-2 mb-3">
            <div
              v-for="inbox in inboxOptions"
              :key="inbox.id"
              class="flex items-center gap-2 text-xs text-n-slate-12 flex-wrap"
            >
              <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ background: inboxDot(inbox.id) }" />
              <span class="w-44 truncate">{{ inbox.name }}</span>
              <div class="flex items-center bg-n-solid-1 border border-n-weak rounded-lg p-0.5 gap-0.5">
                <button
                  class="px-2 h-6 rounded text-[11px] font-medium transition-colors"
                  :class="investDraft[inbox.id]?.mode === 'manual' ? 'text-white' : 'text-n-slate-10 hover:bg-n-alpha-1'"
                  :style="investDraft[inbox.id]?.mode === 'manual' ? { background: 'linear-gradient(135deg, #B8860B, #D4A017)' } : {}"
                  @click="investDraft[inbox.id].mode = 'manual'"
                >
                  R$/mês
                </button>
                <button
                  class="px-2 h-6 rounded text-[11px] font-medium transition-colors"
                  :class="investDraft[inbox.id]?.mode === 'meta_auto' ? 'text-white' : 'text-n-slate-10 hover:bg-n-alpha-1'"
                  :style="investDraft[inbox.id]?.mode === 'meta_auto' ? { background: 'linear-gradient(135deg, #1877F2, #42A5F5)' } : {}"
                  title="Puxa o gasto real da conta de anúncios do Meta no período escolhido"
                  @click="investDraft[inbox.id].mode = 'meta_auto'"
                >
                  Meta (automático)
                </button>
                <button
                  class="px-2 h-6 rounded text-[11px] font-medium transition-colors"
                  :class="investDraft[inbox.id]?.mode === 'google_auto' ? 'text-white' : 'text-n-slate-10 hover:bg-n-alpha-1'"
                  :style="investDraft[inbox.id]?.mode === 'google_auto' ? { background: 'linear-gradient(135deg, #34A853, #4285F4)' } : {}"
                  title="Puxa o gasto real do Google Ads no período (via GA4 — configure em Integrações → Google Ads)"
                  @click="investDraft[inbox.id].mode = 'google_auto'"
                >
                  Google (automático)
                </button>
              </div>
              <input
                v-if="investDraft[inbox.id]?.mode === 'manual'"
                v-model="investDraft[inbox.id].monthly"
                type="number"
                min="0"
                step="50"
                placeholder="R$/mês"
                class="h-8 text-xs border rounded-lg px-2 bg-n-solid-1 text-n-slate-12 focus:outline-none"
                style="width: 110px; margin-bottom: 0; border: 1px solid rgba(212, 160, 23, 0.5)"
              />
              <span v-else class="text-[11px] text-n-slate-10">
                gasto real {{ investDraft[inbox.id]?.mode === 'google_auto' ? 'do Google Ads (via GA4)' : 'da conta do Meta' }} no período
              </span>
            </div>
          </div>
          <!-- Portas de entrada: quais caixas CAPTAM leads (a atribuição
               por caixa segue esta lista; as demais são operacionais) -->
          <div class="pt-3 mt-1" style="border-top: 1px dashed rgba(212, 160, 23, 0.35)">
            <p class="text-xs font-semibold text-n-slate-12 mb-1">🚪 Portas de entrada (caixas de captação)</p>
            <p class="text-[11px] text-n-slate-10 mb-2">
              O lead pertence à primeira porta de entrada por onde falou — caixas operacionais
              (confirmação, NPS...) não roubam a atribuição de quem veio do Google/Instagram.
              Esta lista também é a régua do "Novas no período" e do Meu Painel.
            </p>
            <div class="flex flex-wrap items-center gap-1">
              <button
                v-for="inbox in inboxOptions"
                :key="'cap-' + inbox.id"
                class="px-2.5 h-7 rounded-lg text-[11px] font-medium transition-colors flex items-center gap-1.5"
                :class="captureDraft.includes(inbox.id) ? 'text-white' : 'text-n-slate-10 hover:bg-n-alpha-1 border border-n-weak'"
                :style="captureDraft.includes(inbox.id) ? { background: inboxGrad(inbox.id) } : {}"
                @click="toggleCapture(inbox.id)"
              >
                <span :class="captureDraft.includes(inbox.id) ? 'i-lucide-door-open' : 'i-lucide-door-closed'" class="text-xs" />
                {{ inbox.name }}
              </button>
            </div>
          </div>

          <div class="flex items-center gap-2 mt-3">
            <button
              class="text-xs font-semibold text-white px-3.5 py-2 rounded-xl hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #B8860B, #D4A017)"
              :disabled="savingInvest"
              @click="saveInvestments"
            >
              <span :class="savingInvest ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-check'" class="text-sm" />
              {{ savingInvest ? 'Salvando…' : 'Salvar investimentos' }}
            </button>
            <button
              class="text-xs text-n-slate-10 hover:text-n-slate-12 px-2 py-2"
              :disabled="savingInvest"
              @click="editingInvest = false"
            >
              Cancelar
            </button>
          </div>
        </div>

        <div v-if="!inboxRows.length" class="flex flex-col items-center justify-center py-8 text-n-slate-10 text-sm gap-2">
          <span class="i-lucide-inbox text-2xl" />
          <span>Nenhum lead no período — os resultados por caixa aparecem aqui.</span>
        </div>

        <div v-else class="space-y-3">
          <div
            v-for="row in inboxRows"
            :key="String(row.inbox_id)"
            class="rounded-xl bg-n-alpha-1 p-4"
            :style="{ borderLeft: `4px solid ${row.inbox_id ? inboxDot(row.inbox_id) : '#64748B'}` }"
          >
            <div class="flex items-center gap-2 mb-3 flex-wrap">
              <span
                class="text-xs font-bold text-white px-2.5 py-1 rounded-lg"
                :style="{ background: row.inbox_id ? inboxGrad(row.inbox_id) : 'linear-gradient(135deg, #475569, #64748B)' }"
              >
                {{ row.name }}
              </span>
              <span
                v-if="row.inbox_id && !row.is_capture"
                class="text-[10px] px-2 py-0.5 rounded-full border text-n-slate-10"
                style="border-color: rgba(148, 163, 184, 0.4)"
                title="Caixa operacional: recebe pacientes que já chegaram pelas portas de entrada — só fica com quem nunca passou por porta nenhuma"
              >
                ⚙️ operacional
              </span>
              <span v-if="showFinancials && row.investment_mode === 'meta_auto' && row.investment_period" class="text-[11px] text-n-slate-10">
                investimento: {{ formatCurrency(row.investment_period) }} no período
                · <span style="color: #1877F2" class="font-semibold">puxado do Meta Ads</span>
              </span>
              <span v-else-if="showFinancials && row.investment_mode === 'google_auto' && row.investment_period" class="text-[11px] text-n-slate-10">
                investimento: {{ formatCurrency(row.investment_period) }} no período
                · <span style="color: #34A853" class="font-semibold">puxado do Google (GA4)</span>
              </span>
              <span v-else-if="showFinancials && row.investment_monthly" class="text-[11px] text-n-slate-10">
                investimento: {{ formatCurrency(row.investment_monthly) }}/mês
                · {{ formatCurrency(row.investment_period) }} no período
              </span>
              <span
                v-else-if="showFinancials && ['meta_auto', 'google_auto'].includes(row.investment_mode) && row.investment_note"
                class="text-[11px] font-medium"
                style="color: #B45309"
              >
                ⚠️ {{ row.investment_mode === 'google_auto' ? 'Google automático' : 'Meta automático' }}: {{ row.investment_note }}
              </span>
              <span
                v-if="showFinancials && row.roas"
                class="text-[11px] font-bold ml-auto px-2 py-0.5 rounded-full"
                :style="row.roas >= 1
                  ? 'color: #3F6212; background: rgba(132,204,22,0.15)'
                  : 'color: #B91C1C; background: rgba(239,68,68,0.12)'"
              >
                {{ roasPhrase(row) }}
              </span>
            </div>

            <div class="grid gap-3" style="grid-template-columns: repeat(auto-fit, minmax(110px, 1fr))">
              <div>
                <p class="text-[11px] text-n-slate-10">Leads</p>
                <p class="text-xl font-bold text-n-slate-12">{{ row.leads }}</p>
              </div>
              <div>
                <p class="text-[11px] text-n-slate-10">Agendaram</p>
                <p class="text-xl font-bold" style="color: #B8860B">
                  {{ row.scheduled }}
                  <span class="text-xs font-semibold">· {{ row.scheduling_rate }}%</span>
                </p>
              </div>
              <div>
                <p class="text-[11px] text-n-slate-10">Compareceram <span class="opacity-70">· % dos agendados</span></p>
                <p class="text-xl font-bold" style="color: #0D9488">
                  {{ row.attended }}
                  <span class="text-xs font-semibold">· {{ row.attendance_rate }}%</span>
                </p>
              </div>
              <div>
                <p class="text-[11px] text-n-slate-10">Fecharam cirurgia</p>
                <p class="text-xl font-bold" style="color: #65A30D">
                  {{ row.closed }}
                  <span class="text-xs font-semibold">· {{ row.close_rate }}%</span>
                </p>
              </div>
              <div>
                <p class="text-[11px] text-n-slate-10">Receita</p>
                <p class="text-xl font-bold" style="color: #65A30D">{{ formatCurrency(row.revenue) }}</p>
              </div>
              <template v-if="showFinancials">
                <div>
                  <p class="text-[11px] text-n-slate-10">CPL <span class="opacity-70">· custo por lead</span></p>
                  <p class="text-xl font-bold text-n-slate-12">{{ row.cpl ? formatMoney2(row.cpl) : '—' }}</p>
                </div>
                <div>
                  <p class="text-[11px] text-n-slate-10">Custo por agendamento</p>
                  <p class="text-xl font-bold text-n-slate-12">{{ row.cost_per_schedule ? formatMoney2(row.cost_per_schedule) : '—' }}</p>
                </div>
                <div>
                  <p class="text-[11px] text-n-slate-10">Custo por comparecimento</p>
                  <p class="text-xl font-bold text-n-slate-12">{{ row.cost_per_attendance ? formatMoney2(row.cost_per_attendance) : '—' }}</p>
                </div>
                <div>
                  <p class="text-[11px] text-n-slate-10">CAC <span class="opacity-70">· custo por cirurgia</span></p>
                  <p class="text-xl font-bold text-n-slate-12">{{ row.cac ? formatMoney2(row.cac) : '—' }}</p>
                </div>
                <div>
                  <p class="text-[11px] text-n-slate-10">ROAS <span class="opacity-70">· receita ÷ invest.</span></p>
                  <p class="text-xl font-bold" :style="{ color: row.roas >= 1 ? '#65A30D' : row.roas ? '#B91C1C' : undefined }">
                    {{ row.roas ? row.roas.toLocaleString('pt-BR', { maximumFractionDigits: 2 }) + 'x' : '—' }}
                  </p>
                </div>
                <div>
                  <p class="text-[11px] text-n-slate-10">ROI <span class="opacity-70">· lucro s/ invest.</span></p>
                  <p class="text-xl font-bold" :style="{ color: row.roi_pct >= 0 ? '#65A30D' : row.roi_pct !== null && row.roi_pct !== undefined ? '#B91C1C' : undefined }">
                    {{ row.roi_pct !== null && row.roi_pct !== undefined ? row.roi_pct.toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + '%' : '—' }}
                  </p>
                </div>
              </template>
            </div>
          </div>

          <p v-if="showFinancials && !inboxRows.some(r => r.investment_monthly)" class="text-[11px] text-n-slate-9 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            Informe o investimento mensal de cada caixa (botão dourado acima) para ver CPL, CAC, ROAS e ROI.
          </p>
          <p class="text-[11px] text-n-slate-9 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            A receita vem do valor dos cards que chegaram à coluna de cirurgia — a mesma régua do card "Valor fechado".
          </p>
        </div>
      </div>

      <!-- Atendimento por agente -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center justify-between flex-wrap gap-3 mb-5">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-headset text-white text-sm" />
            </span>
            Atendimento por agente
          </h3>
          <select
            v-model="selectedAgentId"
            class="h-9 text-sm border border-n-weak rounded-xl px-3 bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
          >
            <option value="all">Todos os agentes</option>
            <option v-for="a in agentRows" :key="a.id" :value="a.id">{{ a.name }}</option>
          </select>
        </div>

        <div v-if="agentView" class="grid grid-cols-1 sm:grid-cols-3 gap-5">
          <div class="rounded-xl p-4 bg-n-alpha-1" style="border-left: 4px solid #0F5FA6">
            <p class="text-xs text-n-slate-10 mb-1">Conversas em aberto</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ agentView.open }}</p>
          </div>
          <div class="rounded-xl p-4 bg-n-alpha-1" style="border-left: 4px solid #D4A017">
            <p class="text-xs text-n-slate-10 mb-1">Sem resposta (paciente aguardando)</p>
            <p class="text-2xl font-bold" :style="{ color: agentView.unanswered > 0 ? '#B8860B' : undefined }">
              {{ agentView.unanswered }}
            </p>
          </div>
          <div class="rounded-xl p-4 bg-n-alpha-1" style="border-left: 4px solid #7C3AED">
            <p class="text-xs text-n-slate-10 mb-1">Tempo de 1ª resposta (período)</p>
            <p class="text-2xl font-bold text-n-slate-12">{{ formatSeconds(agentView.avg_first_response_seconds) }}</p>
          </div>
        </div>

        <p v-if="selectedAgentId === 'all' && data.agents?.unassigned?.open" class="text-[11px] text-n-slate-9 mt-3">
          Inclui {{ data.agents.unassigned.open }} conversas abertas sem agente atribuído.
        </p>
      </div>

      <!-- Responsividade das conversas -->
      <div v-if="resp && resp.total > 0" class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center justify-between flex-wrap gap-2 mb-5">
          <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-activity text-white text-sm" />
            </span>
            Responsividade das conversas
          </h3>
          <div class="flex items-center gap-3 flex-wrap">
            <span class="text-xs text-n-slate-10 hidden lg:inline">leads do período · % = quanto do total chegou até a etapa · a inclinação mostra o vazamento</span>
            <button
              class="text-xs font-bold px-3.5 py-1.5 rounded-xl text-white hover:opacity-90 shadow flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
              title="Análise por período, estilos de gráfico (até candles) e ações da empresa na linha do tempo"
              @click="proMaxFocus = ''"
            >
              <span class="i-lucide-sparkles text-sm" />
              Visualização PRO MAX
            </button>
          </div>
        </div>

        <div class="h-72">
          <Line v-if="respCurve" :data="respCurve.data" :options="respCurve.options" />
        </div>

        <div class="mt-5 flex items-center gap-3 rounded-xl p-4 flex-wrap border-2" style="background: rgba(212,160,23,0.08); border-color: rgba(212,160,23,0.35)">
          <span class="i-lucide-user-x text-xl flex-shrink-0" style="color: #B8860B" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-bold text-n-slate-12">
              {{ resp.stuck.count }} conversas pouco responsivas ({{ resp.stuck.pct }}%)
            </p>
            <p class="text-xs text-n-slate-10">
              paradas em "{{ resp.stuck.stage_name }}" — não avançaram no funil. Público ideal para uma campanha de reativação.
            </p>
          </div>
          <button
            class="text-xs font-bold px-4 py-2 rounded-xl text-white hover:opacity-90 flex-shrink-0 shadow"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            @click="$router.push({ name: 'crm_campaigns' })"
          >
            Criar campanha →
          </button>
        </div>
      </div>

      <!-- Linha do tempo + Caixas de entrada -->
      <div class="grid grid-cols-1 xl:grid-cols-3 gap-6 mb-10">

        <!-- Conversas ao longo do tempo — áreas em camadas sobre navy
             (mesmo estilo do Faturamento, pedido 03/08) -->
        <div
          class="xl:col-span-2 rounded-2xl p-6 shadow-lg"
          style="background: linear-gradient(160deg, #0A1130, #101A45 55%, #0C1338); border: 1px solid rgba(148, 163, 184, 0.18)"
        >
          <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
            <h3 class="text-sm font-bold text-white">Conversas ao longo do tempo</h3>
            <button
              class="text-[11px] font-bold px-3 py-1.5 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)"
              title="Abrir no estúdio: conversas por caixa de entrada, estilos de gráfico e ações da empresa"
              @click="proMaxFocus = 'timeline'"
            >
              <span class="i-lucide-sparkles text-xs" />
              PRO MAX
            </button>
          </div>
          <p class="text-[11px] mb-4" style="color: #94A3B8">
            {{ timelineGranularity }}, pela data em que o lead chegou — e, desses leads, quantos avançaram até agendar ou operar
          </p>
          <div class="h-64">
            <Line
              v-if="timelineChart"
              :data="timelineChart.data"
              :options="timelineChart.options"
            />
            <div v-else class="flex items-center justify-center h-full text-sm" style="color: #64748B">
              Sem dados no período
            </div>
          </div>
        </div>

        <!-- Conversas por caixa de entrada -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-1">Conversas por caixa de entrada</h3>
          <p class="text-[11px] text-n-slate-10 mb-4">
            todas as caixas do período{{ inboxFilterActive ? ' (não muda com o filtro de caixa)' : '' }}
          </p>
          <div class="h-64">
            <Doughnut
              v-if="inboxChart"
              :data="inboxChart.data"
              :options="inboxChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-pie-chart text-2xl" />
              <span>Sem conversas no período</span>
            </div>
          </div>
        </div>
      </div>

      <!-- 💰 Faturamento por caixa de entrada — áreas em camadas com
           gradiente sobre navy (modelo que o Guilherme enviou 03/08) -->
      <div
        class="rounded-2xl p-6 mb-10 shadow-lg"
        style="background: linear-gradient(160deg, #0A1130, #101A45 55%, #0C1338); border: 1px solid rgba(148, 163, 184, 0.18)"
      >
        <div class="flex items-center justify-between flex-wrap gap-2 mb-1">
          <h3 class="text-sm font-bold text-white flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
              <span class="i-lucide-trending-up text-white text-sm" />
            </span>
            Faturamento por caixa de entrada
          </h3>
          <div class="flex items-center gap-3">
            <span v-if="revenueTotal" class="text-sm font-bold" style="color: #FBBF24">
              {{ formatCurrency(revenueTotal) }} no período
            </span>
            <button
              class="text-[11px] font-bold px-3 py-1.5 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #B8860B, #D4A017)"
              title="Abrir no estúdio: faturamento por caixa de entrada, candles e ações da empresa"
              @click="proMaxFocus = 'revenue'"
            >
              <span class="i-lucide-sparkles text-xs" />
              PRO MAX
            </button>
          </div>
        </div>
        <p class="text-[11px] mb-4" style="color: #94A3B8">
          {{ revenueGranularityLabel }} · receita das cirurgias fechadas, pela data de chegada do lead · cada camada é uma caixa de entrada
        </p>
        <div class="h-72">
          <Line
            v-if="revenueChart"
            :data="revenueChart.data"
            :options="revenueChart.options"
          />
          <div v-else class="flex flex-col items-center justify-center h-full text-sm gap-2" style="color: #64748B">
            <span class="i-lucide-trending-up text-2xl" />
            <span>Sem faturamento no período — cards que chegarem à coluna de cirurgia aparecem aqui.</span>
          </div>
        </div>
      </div>

      <!-- Etiquetas + Radar de Oportunidades -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Etiquetas (volume e proporção) -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <div class="flex items-center gap-2 mb-5">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
              <span class="i-lucide-tags text-white text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Etiquetas dos leads <span class="font-normal text-n-slate-10">· período escolhido</span></h3>
            <span v-if="data.by_label?.total" class="text-[11px] text-n-slate-9 ml-auto">
              {{ data.by_label.total }} etiquetas aplicadas
            </span>
          </div>
          <div v-if="!labelChart" class="flex flex-col items-center justify-center h-64 text-n-slate-10 text-sm gap-2">
            <span class="i-lucide-tags text-2xl" />
            <span>Nenhuma etiqueta aplicada nos leads deste funil</span>
          </div>
          <div v-else class="flex flex-col sm:flex-row items-center gap-5">
            <div class="h-52 w-52 flex-shrink-0">
              <Doughnut :data="labelChart.data" :options="labelChart.options" />
            </div>
            <div class="flex-1 w-full space-y-2 max-h-52 overflow-y-auto pr-1" style="scrollbar-width: thin;">
              <!-- colunas arredondadas em gradiente (mínimo 33% preenchido) -->
              <div v-for="(item, i) in data.by_label.items" :key="item.label" class="flex items-center gap-2 text-xs">
                <span class="text-n-slate-12 w-24 truncate flex-shrink-0">{{ item.label }}</span>
                <div class="flex-1 h-5 rounded-full bg-n-alpha-1 overflow-hidden">
                  <div
                    class="h-full rounded-full flex items-center justify-end pr-2"
                    :style="{
                      width: Math.max((item.count / (data.by_label.items[0]?.count || 1)) * 100, 33) + '%',
                      background: `linear-gradient(90deg, ${PALETTE[i % PALETTE.length]}, ${PALETTE[i % PALETTE.length]}99)`,
                    }"
                  >
                    <span class="text-[10px] font-bold text-white drop-shadow">{{ item.count }}</span>
                  </div>
                </div>
                <span class="text-n-slate-9 w-10 text-right flex-shrink-0">{{ item.pct }}%</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Radar de Oportunidades × Consultas -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <div class="flex items-center gap-2 mb-5">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #059669, #4ADE80)">
              <span class="i-lucide-radar text-white text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Radar de Oportunidades</h3>
            <span class="text-[11px] text-n-slate-9 ml-auto">no período selecionado</span>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #059669, #4ADE80)">
              <p class="text-xs font-medium text-white/80 mb-1">Oportunidades detectadas</p>
              <p class="text-3xl font-bold">{{ data.radar?.opportunities ?? 0 }}</p>
              <p class="text-[11px] text-white/70 mt-1">
                pacientes quentes sem atendimento{{ inboxFilterActive ? ' · todas as caixas' : '' }}
              </p>
            </div>
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
              <p class="text-xs font-medium text-white/80 mb-1">Consultas agendadas</p>
              <p class="text-3xl font-bold">{{ data.radar?.appointments ?? 0 }}</p>
              <p class="text-[11px] text-white/70 mt-1">criadas na Agenda no período</p>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-4 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            O Radar audita as colunas vigiadas (07:30–18h a cada 10 min; madrugada a cada 4h)
            e avisa no Meu Painel — configure em Automações → Agentes de IA.
          </p>
        </div>
      </div>

      <!-- 🟥 Perdas por motivo (item 103) — ambiente das tags de perda -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6">
        <div class="flex items-center gap-2 mb-5 flex-wrap">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #B91C1C, #EF4444)">
            <span class="i-lucide-heart-crack text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">🟥 Perdas por motivo <span class="font-normal text-n-slate-10">· período escolhido</span></h3>
          <span v-if="lossTotal" class="text-[11px] text-n-slate-9 ml-auto">
            {{ lossTotal }} etiqueta(s) de perda
            <template v-if="lossValueTotal"> · {{ formatCurrency(lossValueTotal) }} em cards perdidos</template>
          </span>
        </div>

        <!-- padrão ainda não criado: um clique e as 6 etiquetas nascem -->
        <div
          v-if="missingLossLabels.length"
          class="rounded-xl border border-dashed p-4 mb-4"
          style="border-color: rgba(239, 68, 68, 0.4); background: rgba(239, 68, 68, 0.04)"
        >
          <p class="text-xs text-n-slate-11 mb-2.5">
            Padrão CEVICO de motivos de perda ({{ missingLossLabels.length }} faltando) — cada um vira uma
            etiqueta vermelha <b>perda_*</b> pronta para a atendente aplicar no balão quando o lead esfriar:
          </p>
          <div class="flex flex-wrap gap-1.5 mb-3">
            <span
              v-for="l in missingLossLabels"
              :key="l.title"
              class="inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full border"
              style="border-color: rgba(239, 68, 68, 0.45); color: #B91C1C"
            >
              <span class="w-1.5 h-1.5 rounded-full" style="background: #EF4444" />
              {{ l.name }}
            </span>
          </div>
          <button
            class="text-xs font-semibold text-white px-3.5 py-2 rounded-xl hover:opacity-90 disabled:opacity-50 flex items-center gap-1.5"
            style="background: linear-gradient(135deg, #B91C1C, #EF4444)"
            :disabled="creatingLossLabels"
            @click="createLossLabels"
          >
            <span :class="creatingLossLabels ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-tags'" class="text-sm" />
            {{ creatingLossLabels ? 'Criando…' : 'Criar as etiquetas padrão de perdas' }}
          </button>
        </div>

        <!-- ranking dos motivos (barras vermelhas, estilo etiquetas) -->
        <div v-if="!lossTotal && !missingLossLabels.length" class="flex flex-col items-center justify-center py-6 text-n-slate-10 text-sm gap-2">
          <span class="i-lucide-heart-crack text-2xl" />
          <span>Nenhuma perda etiquetada no período — quando um lead esfriar, aplique o motivo <b>perda_*</b> no balão do card.</span>
        </div>
        <div v-else-if="lossTotal" class="space-y-2 max-w-2xl">
          <!-- item 145: linha clicável → lista de resgate; ▲/▼ vs período
               anterior (perda subir é RUIM = vermelho); % sobre os leads
               do período; valor dos cards perdidos -->
          <button
            v-for="r in lossRows"
            :key="r.title"
            class="w-full flex items-center gap-2 text-xs group"
            :class="r.count ? 'cursor-pointer' : 'cursor-default'"
            :title="r.count ? 'Ver os pacientes deste motivo (lista de resgate)' : ''"
            @click="openLossModal(r)"
          >
            <span class="text-n-slate-12 w-32 truncate flex-shrink-0 text-left group-hover:underline">{{ r.name }}</span>
            <span v-if="lossTrend(r)" class="w-4 flex-shrink-0 font-bold" :style="{ color: lossTrend(r).color }" :title="lossTrend(r).title">{{ lossTrend(r).arrow }}</span>
            <span v-else class="w-4 flex-shrink-0" />
            <div class="flex-1 h-5 rounded-full bg-n-alpha-1 overflow-hidden">
              <div
                class="h-full rounded-full flex items-center justify-end pr-2 transition-all duration-500"
                :style="{
                  width: Math.max((r.count / (lossRows[0]?.count || 1)) * 100, r.count ? 33 : 0) + '%',
                  background: 'linear-gradient(90deg, #B91C1C, #EF4444)',
                }"
              >
                <span v-if="r.count" class="text-[10px] font-bold text-white drop-shadow">{{ r.count }}</span>
              </div>
            </div>
            <span class="text-n-slate-9 w-14 text-right flex-shrink-0" :title="'% sobre os leads do período'">
              {{ lossPctOfLeads(r) !== null ? String(lossPctOfLeads(r)).replace('.', ',') + '% dos leads' : (lossTotal ? Math.round((r.count / lossTotal) * 100) + '%' : '0%') }}
            </span>
            <span class="w-20 text-right flex-shrink-0" :class="r.value ? 'text-red-500 font-semibold' : 'text-n-slate-9'" :title="r.value ? `valor dos ${r.valueCount} card(s) perdidos com valor preenchido` : ''">
              {{ r.value ? formatCurrency(r.value) : '—' }}
            </span>
          </button>
          <p class="text-[11px] text-n-slate-9 pt-1 flex items-center gap-1.5">
            <span class="i-lucide-info text-xs" />
            Clique no motivo pra ver os pacientes — é a matéria-prima da campanha de resgate (Colheitadeira / Tratamento de dados). R$ = valor dos cards perdidos que tinham valor preenchido.
          </p>
        </div>
      </div>

      <!-- 🌟 Satisfação (NPS) — pós-operatório -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-10">
        <div class="flex items-center gap-2 mb-5 flex-wrap">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0D9488, #2DD4BF)">
            <span class="i-lucide-smile text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Satisfação dos pacientes (NPS)</h3>
          <span class="text-[11px] text-n-slate-9 ml-auto">
            {{ data.nps?.stage_name ? `pacientes do período que chegaram a "${data.nps.stage_name}"` : 'leads do período' }} · notas lidas pelo agente de NPS
          </span>
        </div>
        <div v-if="!data.nps?.total" class="flex flex-col items-center justify-center py-8 text-n-slate-10 text-sm gap-2">
          <span class="i-lucide-smile text-2xl" />
          <span>Sem respostas de NPS ainda — ligue o Agente de NPS numa coluna do pós-operatório (Automações → Agentes de IA).</span>
        </div>
        <div v-else class="grid grid-cols-1 sm:grid-cols-3 gap-4 items-center">
          <div class="rounded-2xl p-5 text-white shadow-lg text-center" style="background: linear-gradient(135deg, #0D9488, #2DD4BF)">
            <p class="text-xs font-medium text-white/80 mb-1">% satisfação (notas 9-10)</p>
            <p class="text-4xl font-bold">{{ data.nps.satisfaction }}%</p>
            <p class="text-[11px] text-white/70 mt-1">NPS {{ data.nps.nps_score }} · {{ data.nps.total }} resposta(s)</p>
          </div>
          <div class="sm:col-span-2 space-y-2.5">
            <div
              v-for="(band, bi) in data.nps.bands"
              :key="band.key"
              class="flex items-center gap-3"
            >
              <span class="text-xs text-n-slate-12 w-44 flex-shrink-0 truncate">{{ band.label }}</span>
              <div class="flex-1 h-6 rounded-full bg-n-alpha-1 overflow-hidden">
                <div
                  class="h-full rounded-full flex items-center justify-end pr-2"
                  :style="{
                    width: Math.max((band.count / data.nps.total) * 100, band.count ? 33 : 4) + '%',
                    background: `linear-gradient(90deg, ${NPS_BAND_GRADS[bi][0]}, ${NPS_BAND_GRADS[bi][1]})`,
                  }"
                >
                  <span v-if="band.count" class="text-[10px] font-bold text-white drop-shadow">{{ band.count }}</span>
                </div>
              </div>
              <span class="text-xs text-n-slate-9 w-12 text-right">{{ Math.round((band.count / data.nps.total) * 100) }}%</span>
            </div>
            <p class="text-[10px] text-n-slate-9">Etiquetas nps-9-10 / nps-7-8 / nps-0-6 aplicadas pelo agente — também dá pra filtrar o board por elas.</p>
          </div>
        </div>
      </div>

      <!-- Cirurgias da planilha (Google Sheets) -->
      <div
        v-if="data.sheet_surgeries?.configured"
        class="bg-n-solid-2 border border-n-weak rounded-2xl p-6 mb-6"
      >
        <div class="flex items-center gap-2 mb-5">
          <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F9D58, #34A853)">
            <span class="i-lucide-sheet text-white text-sm" />
          </span>
          <h3 class="text-sm font-bold text-n-slate-12">Cirurgias — planilha (Google Sheets)</h3>
          <span class="text-[11px] text-n-slate-9 ml-auto">
            mesmo período selecionado acima{{ inboxFilterActive ? ' · a planilha não separa por caixa' : '' }}
          </span>
        </div>

        <p v-if="data.sheet_surgeries.error" class="text-sm text-n-slate-10">
          {{ data.sheet_surgeries.error }}
        </p>
        <template v-else>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-5 mb-6">
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #0F9D58, #34A853)">
              <p class="text-xs font-medium text-white/80 mb-1">Cirurgias no período</p>
              <p class="text-3xl font-bold">{{ data.sheet_surgeries.count }}</p>
            </div>
            <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #65A30D, #84CC16)">
              <p class="text-xs font-medium text-white/80 mb-1">Receita (planilha)</p>
              <p class="text-2xl font-bold leading-tight">{{ formatCurrency(data.sheet_surgeries.revenue) }}</p>
            </div>
            <div class="col-span-2 bg-n-solid-1 border border-n-weak rounded-2xl p-5">
              <p class="text-xs font-medium text-n-slate-10 mb-2">Por unidade</p>
              <div v-if="data.sheet_surgeries.by_unit?.length" class="space-y-1.5">
                <div v-for="u in data.sheet_surgeries.by_unit" :key="u.name" class="flex items-center gap-2 text-sm">
                  <span class="text-n-slate-12 flex-1 truncate">{{ u.name }}</span>
                  <span class="font-semibold text-n-slate-12">{{ u.count }}</span>
                  <span class="text-xs text-n-slate-10 w-24 text-right">{{ formatCurrency(u.value) }}</span>
                </div>
              </div>
              <p v-else class="text-xs text-n-slate-10">Sem coluna "Unidade" na planilha.</p>
            </div>
          </div>

          <div v-if="data.sheet_surgeries.by_procedure?.length">
            <p class="text-xs font-medium text-n-slate-10 mb-2">Por procedimento</p>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-x-8 gap-y-1.5">
              <div v-for="p in data.sheet_surgeries.by_procedure" :key="p.name" class="flex items-center gap-2 text-sm">
                <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" style="background: #0F9D58" />
                <span class="text-n-slate-12 flex-1 truncate">{{ p.name }}</span>
                <span class="font-semibold text-n-slate-12">{{ p.count }}</span>
                <span class="text-xs text-n-slate-10 w-24 text-right">{{ formatCurrency(p.value) }}</span>
              </div>
            </div>
          </div>
          <p v-if="!data.sheet_surgeries.count" class="text-sm text-n-slate-10">
            Nenhuma cirurgia na planilha dentro do período selecionado.
          </p>
        </template>
      </div>

      <!-- 💰 DINHEIRO PARADO (item 145): a coluna ativa com mais R$ sem se
           mexer há 15+ dias — do gráfico direto pra fila de trabalho -->
      <div
        v-if="stalledSpot"
        class="rounded-2xl border-2 overflow-hidden mb-6"
        style="border-color: rgba(212, 160, 23, 0.5); background: rgba(212, 160, 23, 0.06)"
      >
        <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #B8860B, #D4A017)" />
        <div class="p-4 sm:p-5 flex items-center gap-3 flex-wrap">
          <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
            <span class="i-lucide-hourglass text-white text-base" />
          </span>
          <div class="flex-1 min-w-[240px]">
            <p class="text-sm font-bold text-n-slate-12">
              {{ formatCurrency(stalledSpot.stalled_value) }} parados em "{{ stalledSpot.stage_name }}"
            </p>
            <p class="text-xs text-n-slate-10 mt-0.5">
              {{ stalledSpot.stalled_count }} paciente(s) sem se mexer há mais de {{ stalledSpot.stalled_days }} dias
              · a coluna tem {{ stalledSpot.count }} no total ({{ formatCurrency(stalledSpot.value) }})
            </p>
          </div>
          <button
            class="text-xs font-semibold text-white px-4 py-2.5 rounded-xl hover:opacity-90 shadow flex items-center gap-1.5"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            @click="goToBoardStage(stalledSpot)"
          >
            Ver no board →
          </button>
        </div>
      </div>

      <!-- Funil + Valor + Tempo -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">

        <!-- Conversas por etapa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5">Conversas por etapa <span class="font-normal text-n-slate-10">· leads do período</span></h3>
          <div class="h-56">
            <Bar
              v-if="funnelChart"
              :data="funnelChart.data"
              :options="funnelChart.options"
            />
            <div v-else class="flex items-center justify-center h-full text-n-slate-10 text-sm">
              Sem dados
            </div>
          </div>
        </div>

        <!-- Valor em cada etapa do pipeline -->
        <div class="rounded-2xl p-6 border-2" style="border-color: rgba(132,204,22,0.35); background: rgba(132,204,22,0.05)">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5 flex items-center gap-2">
            <span class="i-lucide-circle-dollar-sign" style="color: #65A30D" />
            Valor em cada etapa do pipeline
            <span class="font-normal text-n-slate-10 text-xs">· leads do período</span>
          </h3>
          <div class="h-56">
            <Bar
              v-if="valueChart"
              :data="valueChart.data"
              :options="valueChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-dollar-sign text-2xl" />
              <span>Preencha o valor das conversas</span>
            </div>
          </div>
        </div>

        <!-- Tempo médio por etapa -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-6">
          <h3 class="text-sm font-bold text-n-slate-12 mb-5">Tempo médio por etapa <span class="font-normal text-n-slate-10">· leads do período</span></h3>
          <div class="h-56">
            <Bar
              v-if="timeChart"
              :data="timeChart.data"
              :options="timeChart.options"
            />
            <div v-else class="flex flex-col items-center justify-center h-full text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-clock text-2xl" />
              <span>Mova conversas entre etapas para gerar dados</span>
            </div>
          </div>
        </div>

      </div>

    </div>

    <!-- Empty state -->
    <div v-else class="flex flex-col items-center justify-center py-24 text-n-slate-10">
      <span class="i-lucide-layout-dashboard text-4xl mb-3" />
      <p class="text-sm">Nenhum dado disponível ainda.</p>
      <p class="text-xs mt-1">Adicione conversas ao funil para ver as métricas.</p>
    </div>

    <!-- 📈 Estúdio PRO MAX (item 129/129B) -->
    <ProMaxStudio
      v-if="proMaxFocus !== null"
      :pipeline-id="props.pipeline.id"
      :initial-from="period.from"
      :initial-to="period.to"
      :focus="proMaxFocus"
      @close="proMaxFocus = null"
    />

    <!-- 🔍 popup-análise dos KPIs (item 145) -->
    <KpiDetailPopup
      v-if="kpiPopup"
      :tile="kpiPopup"
      :period="period"
      accent="#0F5FA6"
      @close="kpiPopup = null"
    />

    <!-- 🛟 Lista de resgate de um motivo de perda (item 145) -->
    <Teleport to="body">
      <div
        v-if="lossModal"
        class="fixed inset-0 z-[70] flex items-center justify-center bg-black/50 p-4"
        @click.self="lossModal = null"
      >
        <div class="w-full max-w-lg rounded-2xl overflow-hidden shadow-2xl bg-n-solid-1 max-h-[85vh] flex flex-col">
          <div class="p-5 text-white flex-shrink-0" style="background: linear-gradient(135deg, #B91C1C, #EF4444)">
            <div class="flex items-center gap-2 text-white/90">
              <span class="i-lucide-heart-crack text-base" />
              <p class="text-sm font-bold flex-1">Perda: {{ lossModal.name }}</p>
              <button class="w-7 h-7 rounded-lg bg-white/15 hover:bg-white/30 flex items-center justify-center" @click="lossModal = null">
                <span class="i-lucide-x text-sm" />
              </button>
            </div>
            <p class="text-xs text-white/85 mt-1">
              {{ lossModal.count }} paciente(s) no período
              <template v-if="lossModal.value"> · {{ formatCurrency(lossModal.value) }} em cards com valor</template>
            </p>
          </div>
          <div class="p-4 overflow-y-auto">
            <div v-if="loadingLossContacts" class="flex items-center justify-center py-8 text-n-slate-10 text-sm gap-2">
              <span class="i-lucide-loader-circle animate-spin" /> buscando os pacientes…
            </div>
            <template v-else>
              <button
                v-for="c in lossContacts"
                :key="c.contact_id"
                class="w-full flex items-center gap-2.5 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 mb-1.5 text-left hover:border-red-400/60 transition-colors"
                title="Abrir o Espaço do Paciente"
                @click="openPatientSpace(c)"
              >
                <span class="w-7 h-7 rounded-full flex items-center justify-center text-white text-[10px] font-bold flex-shrink-0" style="background: linear-gradient(135deg, #B91C1C, #EF4444)">
                  {{ (c.name || '?').split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase() }}
                </span>
                <span class="flex-1 min-w-0">
                  <span class="block text-xs font-semibold text-n-slate-12 truncate">{{ c.name }}</span>
                  <span class="block text-[10px] text-n-slate-10 truncate">
                    {{ c.phone || 'sem telefone' }}<template v-if="c.stage_name"> · {{ c.stage_name }}</template>
                  </span>
                </span>
                <span v-if="c.days_still !== null" class="text-[10px] text-n-slate-9 flex-shrink-0">{{ c.days_still }}d parado</span>
                <span v-if="c.value" class="text-[11px] font-bold text-red-500 flex-shrink-0">{{ formatCurrency(c.value) }}</span>
              </button>
              <p v-if="!lossContacts.length" class="text-center text-xs text-n-slate-10 py-6">
                Nenhum paciente encontrado neste recorte.
              </p>
              <p v-else class="text-[11px] text-n-slate-9 mt-2 flex items-start gap-1.5">
                <span class="i-lucide-lightbulb text-xs mt-0.5" />
                Essa lista é a matéria-prima do resgate: a 🌾 Colheitadeira (Automações → Agentes) ou o Tratamento de dados atacam esses pacientes em massa com etiqueta e mensagem aprovada.
              </p>
            </template>
          </div>
        </div>
      </div>
    </Teleport>

  </div>
</template>
