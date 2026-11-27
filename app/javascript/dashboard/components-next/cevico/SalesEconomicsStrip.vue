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
  return rest ? `${h} h ${rest}` : `${h} h`;
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

const presenceLevel = slot => {
  const share = slot.of ? slot.days / slot.of : 0;
  if (share >= 0.66) return 'ec-pr-high';
  if (share >= 0.33) return 'ec-pr-mid';
  return slot.days ? 'ec-pr-low' : 'ec-pr-none';
};

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
            </div>
            <p class="ec-mini">{{ TXT.presence }}</p>
            <div class="ec-presence">
              <span
                v-for="slot in p.presence"
                :key="slot.hour"
                class="ec-pr"
                :class="presenceLevel(slot)"
                :title="`${slot.hour}h: ${slot.days} de ${slot.of} dias`"
              >
                <small>{{ `${slot.hour}h` }}</small>
                <b class="tabular-nums">{{
                  pct(slot.days, slot.of) || '0%'
                }}</b>
              </span>
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
                <b class="tabular-nums">{{
                  team.human_requests?.total || 0
                }}</b>
                <small class="ec-sub">{{ TXT.requestsTotal }}</small>
              </div>
              <div>
                <b class="tabular-nums">{{
                  minutes(team.human_requests?.mediana_min)
                }}</b>
                <small class="ec-sub">
                  {{ TXT.answeredIn
                  }}<template v-if="team.human_requests?.answered">
                    ·
                    {{
                      pct(
                        team.human_requests.ate_30_min,
                        team.human_requests.answered
                      )
                    }}
                    {{ TXT.within30 }}</template
                  >
                </small>
              </div>
              <div>
                <b
                  class="tabular-nums"
                  :class="team.human_requests?.sem_resposta ? 'ec-hot' : ''"
                  >{{ team.human_requests?.sem_resposta || 0 }}</b
                >
                <small class="ec-sub">{{ TXT.waiting }}</small>
              </div>
            </div>
            <ul
              v-if="team.human_requests?.sem_resposta_lista?.length"
              class="ec-gaps"
            >
              <li
                v-for="w in team.human_requests.sem_resposta_lista"
                :key="w.conversation_id"
              >
                <a :href="conversationUrl(w.display_id)" class="ec-link">
                  {{ w.name || `#${w.display_id}` }}
                </a>
                <span class="tabular-nums">#{{ w.display_id }}</span>
                <b class="tabular-nums ec-hot">{{ minutes(w.minutes) }}</b>
              </li>
            </ul>
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
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
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
