<script setup>
// 📊 27/11/2026 (LIFE, pedido do Guilherme): CUSTOS E RETORNO no Meu Painel —
// "quanto está custando, qual que é o nosso ROAS… quanto a gente está
// investindo, tanto em anúncio, quanto em API e inteligência artificial, e
// quanto está voltando. Quanto tempo mais ou menos demora para a gente
// fechar, quais são os maiores intervalos do dia em horário comercial…
// o Fernando… ficar exposto para mim e para ele".
// Todo mundo que abre o Meu Painel vê; lançar e apagar custo é só de
// administrador. A régua está em app/services/crm/sales_economics.rb e
// app/services/crm/team_response.rb.
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import CrmAPI from 'dashboard/api/crm';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';

const TXT = {
  title: 'Custos e retorno',
  subtitle: 'Quanto investimos, quanto voltou e quanto tempo leva',
  invested: 'Investido',
  revenue: 'Retorno',
  roas: 'ROAS',
  roasAds: 'só anúncio',
  perQuote: 'Custo por orçamento',
  toClose: 'Tempo até fechar',
  sales: 'vendas',
  sale: 'venda',
  noSales: 'nenhuma venda no período',
  onTable: 'na mesa',
  quotesOut: 'orçamentos enviados',
  costs: 'De onde vem o custo',
  launched: 'Lançado',
  measured: 'Medido pelo sistema',
  used: 'Conta no ROAS',
  fromLaunched: 'lançado',
  fromMeasured: 'medido',
  notMeasured: 'sem medição',
  add: 'Lançar custo',
  cancel: 'Cancelar',
  save: 'Lançar',
  saving: 'Lançando',
  category: 'O quê',
  amount: 'Valor (R$)',
  amountHint: '1.500,00',
  span: 'Período',
  week: 'Semana',
  month: 'Mês',
  date: 'A partir de',
  monthOf: 'Mês de',
  note: 'Observação (opcional)',
  entries: 'Últimos lançamentos',
  remove: 'Apagar',
  confirmRemove: 'Apagar este lançamento?',
  perStep: 'Custo por etapa',
  times: 'Quanto tempo leva',
  toBill: 'Chegada → conta',
  toQuote: 'Chegada → orçamento',
  toContract: 'Chegada → contrato',
  hours: 'h',
  days: 'dias',
  people: 'pessoas',
  team: 'Equipe no horário comercial',
  msgs: 'mensagens escritas',
  inHours: 'no horário',
  reply: 'Responde o cliente em',
  within30: 'em até 30 min',
  over4h: 'acima de 4 h',
  gaps: 'Maiores intervalos sem mensagem',
  avgGap: 'Maior intervalo do dia, em média',
  absent: 'Dias úteis sem nenhuma mensagem',
  ofDays: 'de',
  presence: 'Presença por hora (dias com mensagem)',
  requests: 'Quando a IA pede gente',
  requestsTotal: 'pedidos',
  answeredIn: 'respondidos em',
  waiting: 'ainda sem resposta',
  owner: 'responsável',
  phone: 'sem nome: saiu do app no celular',
  active: 'Tempo em atividade',
  perWorkedDay: 'por dia trabalhado',
  startEnd: 'Começa e termina',
  medianDay: 'horário típico',
  mostHours: 'Horas em que mais responde',
  leastHours: 'Horas em que menos responde',
  inBusiness: 'no horário comercial',
  viewMonth: 'Mês',
  viewWeek: 'Semana',
  viewDay: 'Dia',
  monthHint:
    'Cada dia: mensagens escritas e das quantas às quantas. Clique no dia para abrir.',
  weekHint:
    'Mensagens por dia da semana e hora, somando o período. A área clara é o horário comercial.',
  replyByHour:
    'Quanto o cliente espera, pela hora em que ele escreveu (horário comercial)',
  msgsShort: 'msg',
  noMsgs: 'nenhuma mensagem',
  blocks: 'Blocos de trabalho',
  blocksHint: 'mensagens com até 30 min entre uma e outra',
  dayMax: 'Maior intervalo no horário',
  noDayGap: 'sem intervalo no horário comercial',
  closed: 'sem expediente',
  today: 'hoje',
  why: 'Por que a IA pede gente',
  whyHint: 'assunto do pedido, pelo motivo que a IA deixou na tarefa',
  all: 'Todos',
  whoWaits: 'Quem está esperando',
  aiSaid: 'IA',
  clientSaid: 'Cliente',
  noReason: 'a IA não deixou o motivo',
  clientWaiting: 'cliente escreveu por último',
  requestsN: 'pedidos',
  showAll: 'Ver todos',
  showLess: 'Ver menos',
  stage: 'coluna',
  loading: 'Carregando os números',
  error: 'Não consegui carregar os números agora.',
  legend:
    'O lançado à mão vale no lugar do medido e é dividido pelos dias que cobre (no meio do mês conta a parte dos dias que já passaram). Retorno = cartões que entraram em Contrato Assinado no período. Mensagens automáticas (IA e robôs) não contam para a equipe.',
};
const CATS = [
  { key: 'trafego', label: 'Tráfego (anúncios)' },
  { key: 'ia', label: 'API de IA' },
  { key: 'whatsapp', label: 'WhatsApp API oficial' },
];

const route = useRoute();
const { isAdmin } = useAdmin();

const PERIOD_KEY = 'cevico:economics:periodo';
const savedPeriod = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(PERIOD_KEY) || 'null');
    if (saved?.preset) return saved;
  } catch {
    // sem memória do navegador: segue no padrão
  }
  return { preset: 'month', from: '', to: '' };
};
const periodo = ref(savedPeriod());
const report = ref(null);
const loading = ref(false);
const failed = ref(false);
const formOpen = ref(false);
const saving = ref(false);
const formError = ref('');
const today = new Date().toISOString().slice(0, 10);
const form = ref({
  category: 'trafego',
  amount: '',
  span: 'mes',
  date: today,
  note: '',
});
let seq = 0;

const money = v =>
  v === null || v === undefined
    ? '—'
    : Number(v).toLocaleString('pt-BR', {
        style: 'currency',
        currency: 'BRL',
        maximumFractionDigits: Number(v) >= 1000 ? 0 : 2,
      });
const times = v => (v === null || v === undefined ? '—' : `${v}x`);
const minutes = m => {
  if (m === null || m === undefined) return '—';
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  const rest = m % 60;
  return rest ? `${h} h ${String(rest).padStart(2, '0')}` : `${h} h`;
};
const dayLabel = iso => {
  const [y, m, d] = iso.split('-');
  const wd = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'][
    new Date(Number(y), Number(m) - 1, Number(d)).getDay()
  ];
  return `${wd} ${d}/${m}`;
};
const pct = (part, whole) =>
  whole ? `${Math.round((part * 100) / whole)}%` : '';

const costs = computed(() => report.value?.costs || { rows: [], total: 0 });
const revenue = computed(() => report.value?.revenue || {});
const perStep = computed(() => report.value?.per_step || []);
const tm = computed(() => report.value?.times || {});
const team = computed(() => report.value?.team || { people: [] });
const entries = computed(() => report.value?.entries || []);
const perQuote = computed(
  () => perStep.value.find(s => s.key === 'enviado')?.cost
);

const cards = computed(() => [
  {
    key: 'invested',
    label: TXT.invested,
    value: money(costs.value.total),
    foot: costs.value.rows
      .filter(r => r.valor)
      .map(r => `${r.label.split(' ')[0]} ${money(r.valor)}`)
      .join(' · '),
  },
  {
    key: 'revenue',
    label: TXT.revenue,
    value: money(revenue.value.total || 0),
    foot: revenue.value.sales
      ? `${revenue.value.sales} ${revenue.value.sales === 1 ? TXT.sale : TXT.sales}`
      : TXT.noSales,
  },
  {
    key: 'roas',
    label: TXT.roas,
    value: times(report.value?.roas),
    foot:
      report.value?.roas_ads !== null && report.value?.roas_ads !== undefined
        ? `${times(report.value.roas_ads)} ${TXT.roasAds}`
        : '',
  },
  {
    key: 'quote',
    label: TXT.perQuote,
    value: money(perQuote.value),
    foot: report.value?.pipeline?.quotes
      ? `${money(report.value.pipeline.value)} ${TXT.onTable}`
      : '',
  },
  {
    key: 'close',
    label: TXT.toClose,
    value:
      tm.value.ate_fechar?.mediana_dias !== null &&
      tm.value.ate_fechar?.mediana_dias !== undefined
        ? `${tm.value.ate_fechar.mediana_dias} ${TXT.days}`
        : '—',
    foot: tm.value.ate_fechar?.n
      ? `${tm.value.ate_fechar.n} ${TXT.sales}`
      : TXT.noSales,
  },
]);

const withUnit = (value, unit) =>
  value === null || value === undefined ? '—' : `${value} ${unit}`;
const timeRows = computed(() => [
  {
    key: 'conta',
    label: TXT.toBill,
    foot: `${tm.value.ate_conta?.n || 0} ${TXT.people}`,
    value: withUnit(tm.value.ate_conta?.mediana_horas, TXT.hours),
  },
  {
    key: 'orcamento',
    label: TXT.toQuote,
    foot: `${tm.value.ate_orcamento?.n || 0} ${TXT.people}`,
    value: withUnit(tm.value.ate_orcamento?.mediana_horas, TXT.hours),
  },
  {
    key: 'fechar',
    label: TXT.toContract,
    foot: `${tm.value.ate_fechar?.n || 0} ${TXT.sales}`,
    value: withUnit(tm.value.ate_fechar?.mediana_dias, TXT.days),
  },
]);
const entryLine = e =>
  [
    `${e.span === 'mes' ? TXT.month : TXT.week} ${dayLabel(e.from)} a ${dayLabel(e.to)}`,
    e.note,
  ]
    .filter(Boolean)
    .join(' · ');

const conversationUrl = displayId =>
  `/app/accounts/${route.params.accountId}/conversations/${displayId}`;

// ── horários de quem atende: mês, semana e dia (27/11, 2º pedido) ──────────
const WEEK = [
  { wday: 1, label: 'seg' },
  { wday: 2, label: 'ter' },
  { wday: 3, label: 'qua' },
  { wday: 4, label: 'qui' },
  { wday: 5, label: 'sex' },
  { wday: 6, label: 'sáb' },
  { wday: 0, label: 'dom' },
];
const BUSINESS = { 1: [8, 18], 2: [8, 18], 3: [8, 18], 4: [8, 18], 5: [8, 18] };
BUSINESS[6] = [8, 12];
const inBusiness = (wday, hour) =>
  !!BUSINESS[wday] && hour >= BUSINESS[wday][0] && hour < BUSINESS[wday][1];
const toMin = hhmm => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};
const fromMin = total =>
  `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(Math.round(total % 60)).padStart(2, '0')}`;
const medianOf = list => {
  if (!list.length) return null;
  const s = [...list].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
};
const wdayOf = iso => {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d).getDay();
};

const views = ref({});
const viewOf = p => views.value[p.id] || 'mes';
const setView = (p, v) => {
  views.value = { ...views.value, [p.id]: v };
};
const picked = ref({});
const workedDays = p => (p.days_detail || []).filter(d => d.msgs);
const pickedDay = p => {
  const list = p.days_detail || [];
  const key = picked.value[p.id];
  return (
    list.find(d => d.day === key) ||
    workedDays(p).slice(-1)[0] ||
    list.slice(-1)[0]
  );
};
const openDay = (p, d) => {
  picked.value = { ...picked.value, [p.id]: d.day };
  setView(p, 'dia');
};
const stepDay = (p, delta) => {
  const list = p.days_detail || [];
  const at = list.findIndex(d => d.day === pickedDay(p)?.day);
  const next = list[at + delta];
  if (next) picked.value = { ...picked.value, [p.id]: next.day };
};

// números de cima: tempo em atividade, começo e fim típicos, horas fortes e fracas
const summaryOf = p => {
  const worked = workedDays(p);
  const active = worked.reduce((sum, d) => sum + d.active_min, 0);
  const firsts = worked.map(d => toMin(d.first));
  const lasts = worked.map(d => toMin(d.last));
  const byHour = Array.from({ length: 24 }, (_, h) =>
    (p.heat || []).reduce((sum, row) => sum + row[h], 0)
  );
  const busHours = Array.from({ length: 10 }, (_, i) => 8 + i);
  const weekdayHits = h =>
    [1, 2, 3, 4, 5].reduce((sum, w) => sum + (p.heat?.[w]?.[h] || 0), 0);
  const most = byHour
    .map((n, h) => ({ h, n }))
    .filter(x => x.n)
    .sort((a, b) => b.n - a.n)
    .slice(0, 3);
  const least = busHours
    .map(h => ({ h, n: weekdayHits(h) }))
    .sort((a, b) => a.n - b.n || a.h - b.h)
    .slice(0, 3);
  return {
    active,
    perDay: worked.length ? Math.round(active / worked.length) : null,
    worked: worked.length,
    start: firsts.length ? fromMin(medianOf(firsts)) : null,
    end: lasts.length ? fromMin(medianOf(lasts)) : null,
    most,
    least,
  };
};
const hoursLabel = list =>
  list.length ? list.map(x => `${x.h}h (${x.n})`).join(' · ') : '—';

// faixa de horas dos mapas: 7h–19h, esticando se houver mensagem fora
const hourRange = p => {
  let lo = 7;
  let hi = 19;
  (p.heat || []).forEach(row =>
    row.forEach((n, h) => {
      if (!n) return;
      lo = Math.min(lo, h);
      hi = Math.max(hi, h);
    })
  );
  return Array.from({ length: hi - lo + 1 }, (_, i) => lo + i);
};
const heatRows = p =>
  WEEK.filter(w => w.wday !== 0 || (p.heat?.[0] || []).some(Boolean));
const heatMax = p => Math.max(1, ...(p.heat || []).flat());
const heatStyle = (p, n) =>
  n
    ? {
        background: `rgba(22, 163, 74, ${0.18 + (0.72 * n) / heatMax(p)})`,
      }
    : {};

// calendário do mês: semanas de seg a dom
const calendar = p => {
  const list = p.days_detail || [];
  if (!list.length) return [];
  const pad = (wdayOf(list[0].day) + 6) % 7;
  const cells = [...Array(pad).fill(null), ...list];
  while (cells.length % 7) cells.push(null);
  const weeks = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
};
const dayMax = p => Math.max(1, ...(p.days_detail || []).map(d => d.msgs));
const calClass = (p, d) => {
  if (!d) return 'ec-cal-pad';
  if (d.msgs || d.today) return '';
  return d.business ? 'ec-cal-absent' : 'ec-cal-off';
};
const calStyle = (p, d) =>
  d?.msgs
    ? {
        background: `rgba(22, 163, 74, ${0.14 + (0.6 * d.msgs) / dayMax(p)})`,
      }
    : {};

// o dia: barras por hora
const dayHours = p => {
  const d = pickedDay(p);
  let lo = 7;
  let hi = 19;
  (d?.by_hour || []).forEach((n, h) => {
    if (!n) return;
    lo = Math.min(lo, h);
    hi = Math.max(hi, h);
  });
  return Array.from({ length: hi - lo + 1 }, (_, i) => lo + i);
};
const dayLine = d =>
  `${d.msgs} ${TXT.msgsShort} · das ${d.first} às ${d.last} · ${minutes(d.active_min)} em atividade`;
const barHeight = (d, h) => {
  const max = Math.max(1, ...(d?.by_hour || [0]));
  return `${Math.round(((d?.by_hour?.[h] || 0) * 100) / max)}%`;
};

// ── IA pede gente: assunto e lista completa ─────────────────────────────────
const topic = ref('');
const showAllWaiting = ref(false);
const reqs = computed(() => team.value.human_requests || {});
const waitingList = computed(() =>
  (reqs.value.sem_resposta_lista || []).filter(
    w => !topic.value || w.topic === topic.value
  )
);
const waitingShown = computed(() =>
  showAllWaiting.value ? waitingList.value : waitingList.value.slice(0, 12)
);
const topicMax = computed(() =>
  Math.max(1, ...(reqs.value.motivos || []).map(t => t.total))
);

const load = async () => {
  seq += 1;
  const mine = seq;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmAPI.getHome({
      only: 'economics',
      preset: periodo.value.preset,
      from: periodo.value.from,
      to: periodo.value.to,
    });
    if (mine === seq) report.value = data.economics;
  } catch {
    if (mine === seq) failed.value = true;
  } finally {
    if (mine === seq) loading.value = false;
  }
};

const save = async () => {
  formError.value = '';
  saving.value = true;
  try {
    await CrmAPI.createSalesCost({ ...form.value });
    formOpen.value = false;
    form.value = { ...form.value, amount: '', note: '' };
    await load();
  } catch (e) {
    formError.value = e?.response?.data?.error || TXT.error;
  } finally {
    saving.value = false;
  }
};

const remove = async entry => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(TXT.confirmRemove)) return;
  await CrmAPI.deleteSalesCost(entry.id);
  await load();
};

watch(
  periodo,
  value => {
    try {
      localStorage.setItem(PERIOD_KEY, JSON.stringify(value));
    } catch {
      // sem memória do navegador: só não lembra na próxima visita
    }
    load();
  },
  { deep: true }
);

onMounted(load);
</script>

<template>
  <div class="cv-block mb-6">
    <div class="ec p-4 sm:p-5">
      <div class="ec-head">
        <span class="cv-icon cv-icon-sm">
          <span class="i-lucide-wallet text-sm" />
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-bold text-n-slate-12 leading-none">
            {{ TXT.title }}
          </h2>
          <p class="text-[11px] text-n-slate-9 mt-0.5">{{ TXT.subtitle }}</p>
        </div>
        <button
          v-if="isAdmin"
          type="button"
          class="ec-btn"
          @click="formOpen = !formOpen"
        >
          <span class="i-lucide-plus text-[13px]" />
          {{ formOpen ? TXT.cancel : TXT.add }}
        </button>
      </div>
      <div class="ec-ruler">
        <PeriodRuler v-model="periodo" glass />
      </div>

      <!-- lançar custo (só administrador) -->
      <form v-if="formOpen && isAdmin" class="ec-form" @submit.prevent="save">
        <label>
          <span>{{ TXT.category }}</span>
          <select v-model="form.category">
            <option v-for="c in CATS" :key="c.key" :value="c.key">
              {{ c.label }}
            </option>
          </select>
        </label>
        <label>
          <span>{{ TXT.amount }}</span>
          <input
            v-model="form.amount"
            inputmode="decimal"
            :placeholder="TXT.amountHint"
            required
          />
        </label>
        <label>
          <span>{{ TXT.span }}</span>
          <select v-model="form.span">
            <option value="mes">{{ TXT.month }}</option>
            <option value="semana">{{ TXT.week }}</option>
          </select>
        </label>
        <label>
          <span>{{ form.span === 'mes' ? TXT.monthOf : TXT.date }}</span>
          <input v-model="form.date" type="date" required />
        </label>
        <label class="ec-form-note">
          <span>{{ TXT.note }}</span>
          <input v-model="form.note" maxlength="120" />
        </label>
        <button type="submit" class="ec-btn ec-btn-solid" :disabled="saving">
          {{ saving ? TXT.saving : TXT.save }}
        </button>
        <p v-if="formError" class="ec-error">{{ formError }}</p>
      </form>

      <p v-if="failed" class="ec-note">{{ TXT.error }}</p>
      <p v-else-if="!report && loading" class="ec-note">{{ TXT.loading }}</p>

      <div v-else-if="report" :class="loading ? 'ec-dim' : ''">
        <!-- os 5 números do período -->
        <ol class="ec-cards">
          <li
            v-for="card in cards"
            :key="card.key"
            class="ec-card"
            :class="`ec-card-${card.key}`"
          >
            <span class="ec-label">{{ card.label }}</span>
            <b class="ec-count tabular-nums">{{ card.value }}</b>
            <span class="ec-foot">{{ card.foot }}</span>
          </li>
        </ol>

        <div class="ec-grid">
          <!-- de onde vem o custo -->
          <section class="ec-box">
            <p class="ec-section">{{ TXT.costs }}</p>
            <div class="ec-table">
              <div class="ec-row ec-row-head">
                <span />
                <span>{{ TXT.launched }}</span>
                <span>{{ TXT.measured }}</span>
                <span>{{ TXT.used }}</span>
              </div>
              <div v-for="row in costs.rows" :key="row.key" class="ec-row">
                <b>{{ row.label }}</b>
                <span
                  class="tabular-nums"
                  :class="row.lancado ? '' : 'ec-zero'"
                >
                  {{ row.lancado ? money(row.lancado) : '—' }}
                </span>
                <span
                  class="tabular-nums"
                  :class="row.medido === null ? 'ec-zero' : ''"
                >
                  {{
                    row.medido === null ? TXT.notMeasured : money(row.medido)
                  }}
                </span>
                <span class="tabular-nums">
                  <b>{{ money(row.valor || 0) }}</b>
                  <small v-if="row.fonte" class="ec-sub">
                    {{
                      row.fonte === 'lancado'
                        ? TXT.fromLaunched
                        : TXT.fromMeasured
                    }}
                  </small>
                </span>
              </div>
            </div>
            <div v-if="entries.length" class="ec-entries">
              <p class="ec-section">{{ TXT.entries }}</p>
              <ul>
                <li v-for="e in entries.slice(0, 6)" :key="e.id">
                  <span class="min-w-0">
                    <b>{{ e.label }}</b>
                    <small class="ec-sub">{{ entryLine(e) }}</small>
                  </span>
                  <b class="tabular-nums">{{ money(e.amount) }}</b>
                  <button
                    v-if="isAdmin"
                    type="button"
                    class="ec-x"
                    :title="TXT.remove"
                    @click="remove(e)"
                  >
                    <span class="i-lucide-x text-[13px]" />
                  </button>
                </li>
              </ul>
            </div>
          </section>

          <!-- custo por etapa e tempos -->
          <section class="ec-box">
            <p class="ec-section">{{ TXT.perStep }}</p>
            <ol class="ec-steps">
              <li v-for="s in perStep" :key="s.key">
                <span>{{ s.label }}</span>
                <small class="ec-sub tabular-nums">
                  {{ s.people }} {{ TXT.people }}
                </small>
                <b class="tabular-nums">{{ money(s.cost) }}</b>
              </li>
            </ol>
            <p class="ec-section mt-4">{{ TXT.times }}</p>
            <ol class="ec-steps">
              <li v-for="row in timeRows" :key="row.key">
                <span>{{ row.label }}</span>
                <small class="ec-sub tabular-nums">{{ row.foot }}</small>
                <b class="tabular-nums">{{ row.value }}</b>
              </li>
            </ol>
          </section>
        </div>

        <!-- equipe no horário comercial -->
        <p class="ec-section mt-5">
          {{ TXT.team }} <small class="ec-sub">· {{ team.hours }}</small>
        </p>
        <div class="ec-team">
          <section
            v-for="p in team.people"
            :key="p.id"
            class="ec-box ec-person"
            :class="p.owner ? 'ec-person-owner' : ''"
          >
            <div class="ec-person-head">
              <b>{{ p.name }}</b>
              <small v-if="p.owner" class="ec-tag">{{ TXT.owner }}</small>
              <small class="ec-sub tabular-nums">
                {{ p.messages }} {{ TXT.msgs }} · {{ p.in_hours }}
                {{ TXT.inHours }}
              </small>
              <small v-if="p.phone" class="ec-sub">· {{ TXT.phone }}</small>
            </div>
            <div class="ec-kpis">
              <div>
                <span class="ec-label">{{ TXT.reply }}</span>
                <b class="tabular-nums">{{ minutes(p.reply?.mediana_min) }}</b>
                <small v-if="p.reply?.n" class="ec-sub tabular-nums">
                  {{ pct(p.reply.ate_30_min, p.reply.n) }} {{ TXT.within30 }} ·
                  {{ p.reply.acima_4h }} {{ TXT.over4h }}
                </small>
              </div>
              <div>
                <span class="ec-label">{{ TXT.avgGap }}</span>
                <b class="tabular-nums">{{ minutes(p.avg_max_gap) }}</b>
              </div>
              <div>
                <span class="ec-label">{{ TXT.absent }}</span>
                <b
                  class="tabular-nums"
                  :class="p.days_absent ? 'ec-hot' : ''"
                  >{{ p.days_absent || 0 }}</b
                >
                <small class="ec-sub tabular-nums">
                  {{ TXT.ofDays }} {{ p.days }}
                </small>
              </div>
              <div>
                <span class="ec-label">{{ TXT.active }}</span>
                <b class="tabular-nums">{{ minutes(summaryOf(p).active) }}</b>
                <small v-if="summaryOf(p).perDay" class="ec-sub tabular-nums">
                  {{ minutes(summaryOf(p).perDay) }} {{ TXT.perWorkedDay }}
                </small>
              </div>
              <div>
                <span class="ec-label">{{ TXT.startEnd }}</span>
                <b class="tabular-nums">{{
                  summaryOf(p).start
                    ? `${summaryOf(p).start}–${summaryOf(p).end}`
                    : '—'
                }}</b>
                <small class="ec-sub">{{ TXT.medianDay }}</small>
              </div>
            </div>
            <div class="ec-hours-line">
              <span>
                <span class="ec-label">{{ TXT.mostHours }}</span>
                <b class="tabular-nums">{{ hoursLabel(summaryOf(p).most) }}</b>
              </span>
              <span>
                <span class="ec-label">{{ TXT.leastHours }}</span>
                <b class="tabular-nums ec-hot">{{
                  hoursLabel(summaryOf(p).least)
                }}</b>
                <small class="ec-sub">{{ TXT.inBusiness }}</small>
              </span>
            </div>

            <!-- mês · semana · dia -->
            <div class="ec-tabs" role="tablist">
              <button
                v-for="v in [
                  ['mes', TXT.viewMonth],
                  ['semana', TXT.viewWeek],
                  ['dia', TXT.viewDay],
                ]"
                :key="v[0]"
                type="button"
                class="ec-tab"
                :class="viewOf(p) === v[0] ? 'ec-tab-on' : ''"
                @click="setView(p, v[0])"
              >
                {{ v[1] }}
              </button>
            </div>

            <!-- MÊS: calendário -->
            <div v-if="viewOf(p) === 'mes'">
              <p class="ec-mini">{{ TXT.monthHint }}</p>
              <div class="ec-cal">
                <span v-for="w in WEEK" :key="w.wday" class="ec-cal-head">{{
                  w.label
                }}</span>
                <template v-for="(week, wi) in calendar(p)" :key="wi">
                  <button
                    v-for="(d, di) in week"
                    :key="`${wi}-${di}`"
                    type="button"
                    class="ec-cal-day"
                    :class="calClass(p, d)"
                    :style="calStyle(p, d)"
                    :disabled="!d"
                    @click="d && openDay(p, d)"
                  >
                    <template v-if="d">
                      <small>{{ d.day.slice(8) }}</small>
                      <b class="tabular-nums">{{ d.msgs || '' }}</b>
                      <small v-if="d.msgs" class="tabular-nums">{{
                        `${d.first}–${d.last}`
                      }}</small>
                      <small v-else-if="d.today">{{ TXT.today }}</small>
                      <small v-else-if="!d.business">{{ TXT.closed }}</small>
                      <small v-else>{{ TXT.noMsgs }}</small>
                    </template>
                  </button>
                </template>
              </div>
            </div>

            <!-- SEMANA: mapa dia da semana × hora -->
            <div v-else-if="viewOf(p) === 'semana'">
              <p class="ec-mini">{{ TXT.weekHint }}</p>
              <div class="ec-heat-wrap">
                <table class="ec-heat">
                  <thead>
                    <tr>
                      <th />
                      <th v-for="h in hourRange(p)" :key="h">{{ `${h}h` }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="w in heatRows(p)" :key="w.wday">
                      <th>{{ w.label }}</th>
                      <td
                        v-for="h in hourRange(p)"
                        :key="h"
                        class="tabular-nums"
                        :class="inBusiness(w.wday, h) ? 'ec-heat-bus' : ''"
                        :style="heatStyle(p, p.heat?.[w.wday]?.[h] || 0)"
                        :title="`${w.label} ${h}h: ${p.heat?.[w.wday]?.[h] || 0} ${TXT.msgsShort}`"
                      >
                        {{ p.heat?.[w.wday]?.[h] || '' }}
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <template v-if="p.reply?.by_hour?.length">
                <p class="ec-mini">{{ TXT.replyByHour }}</p>
                <div class="ec-reply-hours">
                  <span
                    v-for="r in p.reply.by_hour"
                    :key="r.hour"
                    class="ec-chip"
                    :class="r.mediana_min > 120 ? 'ec-chip-hot' : ''"
                    :title="`${r.n} ${TXT.people}`"
                  >
                    <small>{{ `${r.hour}h` }}</small>
                    <b class="tabular-nums">{{ minutes(r.mediana_min) }}</b>
                  </span>
                </div>
              </template>
            </div>

            <!-- DIA -->
            <div v-else-if="pickedDay(p)">
              <div class="ec-day-head">
                <button type="button" class="ec-btn" @click="stepDay(p, -1)">
                  <span class="i-lucide-chevron-left text-[13px]" />
                </button>
                <b>{{ dayLabel(pickedDay(p).day) }}</b>
                <button type="button" class="ec-btn" @click="stepDay(p, 1)">
                  <span class="i-lucide-chevron-right text-[13px]" />
                </button>
                <small class="ec-sub tabular-nums">
                  <template v-if="pickedDay(p).msgs">
                    {{ dayLine(pickedDay(p)) }}
                  </template>
                  <template v-else>{{
                    pickedDay(p).business ? TXT.noMsgs : TXT.closed
                  }}</template>
                </small>
              </div>
              <div class="ec-bars">
                <span
                  v-for="h in dayHours(p)"
                  :key="h"
                  class="ec-bar"
                  :class="
                    inBusiness(wdayOf(pickedDay(p).day), h) ? 'ec-heat-bus' : ''
                  "
                  :title="`${h}h: ${pickedDay(p).by_hour[h]} ${TXT.msgsShort}`"
                >
                  <b class="tabular-nums">{{
                    pickedDay(p).by_hour[h] || ''
                  }}</b>
                  <i :style="{ height: barHeight(pickedDay(p), h) }" />
                  <small>{{ `${h}h` }}</small>
                </span>
              </div>
              <div class="ec-day-cols">
                <div>
                  <p class="ec-mini">
                    {{ TXT.blocks }}
                    <small class="ec-sub">· {{ TXT.blocksHint }}</small>
                  </p>
                  <ul class="ec-gaps">
                    <li v-if="!pickedDay(p).sessions.length" class="ec-zero">
                      —
                    </li>
                    <li v-for="(s, si) in pickedDay(p).sessions" :key="si">
                      <span class="tabular-nums">{{ s.from }}–{{ s.to }}</span>
                      <span class="tabular-nums"
                        >{{ s.n }} {{ TXT.msgsShort }}</span
                      >
                      <b class="tabular-nums">{{ minutes(s.minutes) }}</b>
                    </li>
                  </ul>
                </div>
                <div>
                  <p class="ec-mini">{{ TXT.dayMax }}</p>
                  <ul class="ec-gaps">
                    <li v-if="pickedDay(p).max_gap">
                      <span class="tabular-nums"
                        >{{ pickedDay(p).max_gap.from }}–{{
                          pickedDay(p).max_gap.to
                        }}</span
                      >
                      <span />
                      <b class="tabular-nums ec-hot">{{
                        minutes(pickedDay(p).max_gap.minutes)
                      }}</b>
                    </li>
                    <li v-else class="ec-zero">{{ TXT.noDayGap }}</li>
                  </ul>
                </div>
              </div>
            </div>

            <p class="ec-mini">{{ TXT.gaps }}</p>
            <ul class="ec-gaps">
              <li v-if="!p.gaps.length" class="ec-zero">—</li>
              <li v-for="(g, i) in p.gaps.slice(0, 5)" :key="i">
                <span>{{ dayLabel(g.day) }}</span>
                <span class="tabular-nums">{{ g.from }}–{{ g.to }}</span>
                <b class="tabular-nums">{{ minutes(g.minutes) }}</b>
              </li>
            </ul>
          </section>

          <!-- IA pediu gente -->
          <section class="ec-box">
            <span class="ec-label">{{ TXT.requests }}</span>
            <div class="ec-kpis">
              <div>
                <b class="tabular-nums">{{ reqs.total || 0 }}</b>
                <small class="ec-sub">{{ TXT.requestsTotal }}</small>
              </div>
              <div>
                <b class="tabular-nums">{{ minutes(reqs.mediana_min) }}</b>
                <small class="ec-sub">
                  {{ TXT.answeredIn
                  }}<template v-if="reqs.answered">
                    ·
                    {{ pct(reqs.ate_30_min, reqs.answered) }}
                    {{ TXT.within30 }}</template
                  >
                </small>
              </div>
              <div>
                <b
                  class="tabular-nums"
                  :class="reqs.sem_resposta ? 'ec-hot' : ''"
                  >{{ reqs.sem_resposta || 0 }}</b
                >
                <small class="ec-sub">{{ TXT.waiting }}</small>
              </div>
            </div>

            <template v-if="reqs.motivos?.length">
              <p class="ec-mini">
                {{ TXT.why }} <small class="ec-sub">· {{ TXT.whyHint }}</small>
              </p>
              <ul class="ec-topics">
                <li
                  v-for="t in reqs.motivos"
                  :key="t.key"
                  :class="topic === t.key ? 'ec-topic-on' : ''"
                  @click="topic = topic === t.key ? '' : t.key"
                >
                  <span class="ec-topic-label">{{ t.label }}</span>
                  <span class="ec-topic-bar">
                    <i :style="{ width: `${(t.total * 100) / topicMax}%` }" />
                    <i
                      class="ec-topic-open"
                      :style="{
                        width: `${(t.sem_resposta * 100) / topicMax}%`,
                      }"
                    />
                  </span>
                  <b class="tabular-nums">{{ t.total }}</b>
                  <small class="ec-sub tabular-nums ec-hot"
                    >{{ t.sem_resposta }} {{ TXT.waiting }}</small
                  >
                </li>
              </ul>
            </template>

            <template v-if="reqs.sem_resposta_lista?.length">
              <p class="ec-mini">
                {{ TXT.whoWaits }} ({{ waitingList.length }})
                <button
                  v-if="topic"
                  type="button"
                  class="ec-clear"
                  @click="topic = ''"
                >
                  {{ TXT.all }}
                </button>
              </p>
              <ul class="ec-wait">
                <li v-for="w in waitingShown" :key="w.conversation_id">
                  <div class="ec-wait-top">
                    <a :href="conversationUrl(w.display_id)" class="ec-link">
                      {{ w.name || `#${w.display_id}` }}
                    </a>
                    <small class="ec-sub tabular-nums">
                      #{{ w.display_id }}
                      <template v-if="w.etapa">· {{ w.etapa }}</template>
                      <template v-if="w.pedidos > 1"
                        >· {{ w.pedidos }} {{ TXT.requestsN }}</template
                      >
                    </small>
                    <small v-if="w.cliente_esperando" class="ec-tag">{{
                      TXT.clientWaiting
                    }}</small>
                    <b class="tabular-nums ec-hot">{{ minutes(w.minutes) }}</b>
                  </div>
                  <p class="ec-wait-line">
                    <small class="ec-tag ec-tag-soft">{{
                      w.topic_label
                    }}</small>
                    <span v-if="w.motivo"
                      ><b>{{ TXT.aiSaid }}:</b> {{ w.motivo }}</span
                    >
                    <span v-else class="ec-zero">{{ TXT.noReason }}</span>
                  </p>
                  <p v-if="w.cliente_disse" class="ec-wait-line ec-sub">
                    <b>{{ TXT.clientSaid }}:</b> {{ `“${w.cliente_disse}”` }}
                  </p>
                </li>
              </ul>
              <button
                v-if="waitingList.length > 12"
                type="button"
                class="ec-btn mt-2"
                @click="showAllWaiting = !showAllWaiting"
              >
                {{
                  showAllWaiting
                    ? TXT.showLess
                    : `${TXT.showAll} (${waitingList.length})`
                }}
              </button>
            </template>
          </section>
        </div>
        <p class="ec-legend">{{ TXT.legend }}</p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.ec {
  container-type: inline-size;
  --ec-accent: #ea580c;
}
.ec-head {
  display: flex;
  align-items: center;
  gap: 10px 12px;
  margin-bottom: 14px;
}
.ec-ruler {
  margin: -4px 0 14px;
  max-width: 100%;
}
.ec-note {
  padding: 14px 0 4px;
  font-size: 13px;
  color: #64748b;
}
.ec-dim {
  opacity: 0.55;
}
.ec-section {
  margin-bottom: 6px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.ec-mini {
  margin: 12px 0 6px;
  font-size: 11px;
  font-weight: 600;
  color: #64748b;
}
.ec-sub {
  font-size: 11px;
  font-weight: 500;
  color: #64748b;
}
.ec-label {
  display: block;
  font-size: 11px;
  font-weight: 700;
  line-height: 1.25;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.ec-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  border-radius: 8px;
  border: 1px solid rgba(100, 116, 139, 0.35);
  font-size: 12px;
  font-weight: 700;
  color: inherit;
}
.ec-btn-solid {
  background: var(--ec-accent);
  border-color: var(--ec-accent);
  color: #fff;
  align-self: end;
  justify-content: center;
}
.ec-btn:disabled {
  opacity: 0.6;
}

/* formulário */
.ec-form {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
  margin-bottom: 16px;
  padding: 12px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
}
@container (min-width: 760px) {
  .ec-form {
    grid-template-columns: 1.4fr 1fr 0.8fr 1fr 1.6fr auto;
  }
}
.ec-form label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
  font-size: 11px;
  font-weight: 700;
  color: #64748b;
}
.ec-form input,
.ec-form select {
  height: 34px;
  padding: 0 8px;
  border-radius: 8px;
  border: 1px solid rgba(100, 116, 139, 0.35);
  background: transparent;
  font-size: 13px;
  font-weight: 500;
  color: inherit;
}
.ec-error {
  grid-column: 1 / -1;
  font-size: 12px;
  color: #dc2626;
}

/* números do período */
.ec-cards {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}
@container (min-width: 620px) {
  .ec-cards {
    grid-template-columns: repeat(5, minmax(0, 1fr));
  }
}
.ec-card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
  padding: 12px 12px 10px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  border-top: 3px solid var(--ec-accent);
  background: rgba(255, 255, 255, 0.78);
}
.ec-card-invested {
  border-top-color: #1e293b;
}
.ec-card-revenue,
.ec-card-roas {
  border-top-color: #16a34a;
}
.ec-count {
  font-size: 26px;
  font-weight: 800;
  line-height: 1.05;
  color: #0f172a;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.ec-foot {
  font-size: 11px;
  line-height: 1.3;
  color: #475569;
}

/* blocos */
.ec-grid,
.ec-team {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: 10px;
  margin-top: 14px;
}
@container (min-width: 760px) {
  .ec-grid {
    grid-template-columns: 1.4fr 1fr;
  }
  .ec-team {
    grid-template-columns: minmax(0, 1fr);
    margin-top: 0;
  }
}
.ec-box {
  min-width: 0;
  padding: 12px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  background: rgba(255, 255, 255, 0.5);
}
.ec-person-owner {
  border-top: 3px solid var(--ec-accent);
}
.ec-table {
  font-size: 12px;
}
.ec-row {
  display: grid;
  grid-template-columns: 1.3fr 1fr 1.2fr 1fr;
  gap: 6px;
  align-items: baseline;
  padding: 7px 0;
  border-top: 1px solid rgba(100, 116, 139, 0.15);
}
.ec-row-head {
  border-top: 0;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  color: #64748b;
}
.ec-row > span {
  display: flex;
  flex-direction: column;
}
.ec-zero {
  color: #94a3b8;
}
.ec-entries ul,
.ec-steps,
.ec-gaps {
  margin: 0;
  padding: 0;
  list-style: none;
}
.ec-entries {
  margin-top: 12px;
}
.ec-entries li,
.ec-steps li,
.ec-gaps li {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto auto;
  gap: 8px;
  align-items: baseline;
  padding: 6px 0;
  border-top: 1px solid rgba(100, 116, 139, 0.15);
  font-size: 12px;
}
.ec-entries li span {
  display: flex;
  flex-direction: column;
}
.ec-x {
  color: #94a3b8;
}
.ec-x:hover {
  color: #dc2626;
}
.ec-person-head {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 8px;
  font-size: 14px;
}
.ec-tag {
  padding: 1px 6px;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  color: #9a3412;
  background: rgba(234, 88, 12, 0.12);
}
.ec-kpis {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 22px;
  margin-top: 10px;
}
.ec-kpis > div {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.ec-kpis b {
  font-size: 20px;
  font-weight: 800;
  line-height: 1.1;
}
.ec-presence {
  display: grid;
  grid-template-columns: repeat(10, minmax(0, 1fr));
  gap: 3px;
}
.ec-pr {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 4px 0;
  border-radius: 6px;
  font-size: 10px;
}
.ec-pr b {
  font-size: 10px;
}
.ec-pr-high {
  background: rgba(22, 163, 74, 0.22);
}
.ec-pr-mid {
  background: rgba(234, 179, 8, 0.22);
}
.ec-pr-low {
  background: rgba(234, 88, 12, 0.2);
}
.ec-pr-none {
  background: rgba(220, 38, 38, 0.18);
}
.ec-hot {
  color: #c2410c;
}
.ec-link {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 600;
  text-decoration: underline;
  text-underline-offset: 2px;
}
.ec-legend {
  margin-top: 12px;
  font-size: 11px;
  color: #64748b;
}

/* horários: mês · semana · dia (27/11) */
.ec-hours-line {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 28px;
  margin-top: 12px;
  font-size: 13px;
}
.ec-hours-line > span {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.ec-tabs {
  display: inline-flex;
  gap: 2px;
  margin-top: 14px;
  padding: 3px;
  border-radius: 10px;
  border: 1px solid rgba(100, 116, 139, 0.26);
}
.ec-tab {
  padding: 4px 14px;
  border-radius: 7px;
  font-size: 12px;
  font-weight: 700;
  color: #64748b;
}
.ec-tab-on {
  background: rgba(100, 116, 139, 0.16);
  color: inherit;
}
.ec-cal {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 4px;
}
.ec-cal-head {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  text-align: center;
  color: #64748b;
}
.ec-cal-day {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1px;
  min-height: 58px;
  padding: 5px 7px;
  border-radius: 8px;
  border: 1px solid rgba(100, 116, 139, 0.18);
  text-align: left;
  font-size: 10px;
  line-height: 1.2;
}
.ec-cal-day b {
  font-size: 16px;
  font-weight: 800;
}
.ec-cal-day:not(:disabled):hover {
  outline: 2px solid var(--ec-accent);
}
.ec-cal-pad {
  border-color: transparent;
}
.ec-cal-absent {
  background: rgba(220, 38, 38, 0.16);
}
.ec-cal-off {
  opacity: 0.45;
}
.ec-heat-wrap {
  overflow-x: auto;
}
.ec-heat {
  width: 100%;
  border-collapse: separate;
  border-spacing: 3px;
  font-size: 11px;
}
.ec-heat th {
  font-size: 10px;
  font-weight: 700;
  color: #64748b;
  text-align: center;
}
.ec-heat tbody th {
  text-align: left;
  text-transform: uppercase;
  padding-right: 4px;
}
.ec-heat td {
  min-width: 28px;
  height: 26px;
  border-radius: 5px;
  text-align: center;
  font-weight: 700;
  background: rgba(100, 116, 139, 0.06);
}
.ec-heat td.ec-heat-bus {
  box-shadow: inset 0 0 0 1px rgba(100, 116, 139, 0.35);
}
.ec-reply-hours {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
.ec-chip {
  display: flex;
  flex-direction: column;
  align-items: center;
  min-width: 52px;
  padding: 4px 6px;
  border-radius: 7px;
  font-size: 11px;
  background: rgba(22, 163, 74, 0.16);
}
.ec-chip-hot {
  background: rgba(234, 88, 12, 0.2);
}
.ec-day-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 10px;
  margin: 12px 0 8px;
  font-size: 14px;
}
.ec-day-head .ec-btn {
  padding: 4px 8px;
}
.ec-bars {
  display: flex;
  align-items: stretch;
  gap: 3px;
  height: 120px;
}
.ec-bar {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  align-items: center;
  gap: 2px;
  min-width: 0;
  padding: 2px 0;
  border-radius: 5px;
  font-size: 10px;
}
.ec-bar.ec-heat-bus {
  background: rgba(100, 116, 139, 0.08);
}
.ec-bar i {
  display: block;
  width: 70%;
  min-height: 0;
  border-radius: 3px 3px 0 0;
  background: #16a34a;
}
.ec-day-cols {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: 0 18px;
}
@container (min-width: 620px) {
  .ec-day-cols {
    grid-template-columns: 1.3fr 1fr;
  }
}
.ec-topics {
  margin: 0;
  padding: 0;
  list-style: none;
}
.ec-topics li {
  display: grid;
  grid-template-columns: minmax(0, 1.5fr) minmax(60px, 1fr) auto auto;
  gap: 8px;
  align-items: center;
  padding: 5px 4px;
  border-radius: 6px;
  font-size: 12px;
  cursor: pointer;
}
.ec-topics li:hover,
.ec-topic-on {
  background: rgba(100, 116, 139, 0.12);
}
.ec-topic-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.ec-topic-bar {
  position: relative;
  height: 8px;
  border-radius: 4px;
  background: rgba(100, 116, 139, 0.12);
}
.ec-topic-bar i {
  position: absolute;
  inset: 0 auto 0 0;
  border-radius: 4px;
  background: rgba(100, 116, 139, 0.45);
}
.ec-topic-bar i.ec-topic-open {
  background: var(--ec-accent);
}
.ec-clear {
  margin-left: 6px;
  text-decoration: underline;
  color: inherit;
}
.ec-wait {
  margin: 0;
  padding: 0;
  list-style: none;
}
.ec-wait li {
  padding: 8px 0;
  border-top: 1px solid rgba(100, 116, 139, 0.15);
  font-size: 12px;
}
.ec-wait-top {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 8px;
}
.ec-wait-top > b {
  margin-left: auto;
}
.ec-wait-line {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 6px;
  margin-top: 4px;
  line-height: 1.4;
}
.ec-tag-soft {
  text-transform: none;
  color: #334155;
  background: rgba(100, 116, 139, 0.14);
}
:global(.dark .ec-tab),
:global(.dark .ec-cal-head),
:global(.dark .ec-heat th) {
  color: rgba(255, 255, 255, 0.55);
}
:global(.dark .ec-tab-on) {
  background: rgba(255, 255, 255, 0.12);
  color: #fff;
}
:global(.dark .ec-tabs),
:global(.dark .ec-cal-day) {
  border-color: rgba(255, 255, 255, 0.12);
}
:global(.dark .ec-cal-day),
:global(.dark .ec-heat td),
:global(.dark .ec-hours-line),
:global(.dark .ec-wait li),
:global(.dark .ec-topics li),
:global(.dark .ec-day-head),
:global(.dark .ec-bar) {
  color: #fff;
}
:global(.dark .ec-heat td) {
  background-color: rgba(255, 255, 255, 0.04);
}
:global(.dark .ec-heat td.ec-heat-bus) {
  box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.22);
}
:global(.dark .ec-bar.ec-heat-bus) {
  background: rgba(255, 255, 255, 0.05);
}
:global(.dark .ec-wait li) {
  border-top-color: rgba(255, 255, 255, 0.08);
}
:global(.dark .ec-tag-soft) {
  color: rgba(255, 255, 255, 0.85);
  background: rgba(255, 255, 255, 0.1);
}
:global(.dark .ec-cal-absent) {
  background: rgba(220, 38, 38, 0.22);
}

/* tema escuro */
:global(.dark .ec-note),
:global(.dark .ec-label),
:global(.dark .ec-section),
:global(.dark .ec-mini),
:global(.dark .ec-sub),
:global(.dark .ec-row-head),
:global(.dark .ec-legend),
:global(.dark .ec-form label) {
  color: rgba(255, 255, 255, 0.62);
}
:global(.dark .ec-card),
:global(.dark .ec-box),
:global(.dark .ec-form) {
  background: rgba(255, 255, 255, 0.045);
  border-color: rgba(255, 255, 255, 0.12);
}
:global(.dark .ec-card-invested) {
  border-top-color: #e2e8f0;
}
:global(.dark .ec-card-revenue),
:global(.dark .ec-card-roas) {
  border-top-color: #22c55e;
}
:global(.dark .ec-card-quote),
:global(.dark .ec-card-close),
:global(.dark .ec-person-owner) {
  border-top-color: var(--ec-accent);
}
:global(.dark .ec-count),
:global(.dark .ec-row),
:global(.dark .ec-steps li),
:global(.dark .ec-gaps li),
:global(.dark .ec-entries li),
:global(.dark .ec-person-head) {
  color: #fff;
}
:global(.dark .ec-foot) {
  color: rgba(255, 255, 255, 0.78);
}
:global(.dark .ec-row),
:global(.dark .ec-steps li),
:global(.dark .ec-gaps li),
:global(.dark .ec-entries li) {
  border-top-color: rgba(255, 255, 255, 0.08);
}
:global(.dark .ec-zero) {
  color: rgba(255, 255, 255, 0.35);
}
:global(.dark .ec-hot) {
  color: #fdba74;
}
:global(.dark .ec-tag) {
  color: #fdba74;
  background: rgba(234, 88, 12, 0.2);
}
:global(.dark .ec-form input),
:global(.dark .ec-form select),
:global(.dark .ec-btn) {
  border-color: rgba(255, 255, 255, 0.2);
  color: #fff;
}
:global(.dark .ec-form select option) {
  color: #0f172a;
}
:global(.dark .ec-btn-solid) {
  border-color: var(--ec-accent);
}
</style>
