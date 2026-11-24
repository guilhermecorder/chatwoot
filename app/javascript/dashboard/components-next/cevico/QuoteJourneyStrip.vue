<script setup>
// 🧭 12/11/2026 (LIFE, pedido do Guilherme): JORNADA DA VENDA no Meu
// Painel — quem chegou no período e até onde andou, a conversão de
// cada etapa para a seguinte, dois saltos (chegou → recebeu orçamento,
// chegou → fechou) e a mesma conta por fonte de tráfego.
// ☀️ 16/11/2026: etapas no fluxo da energia solar (novos contatos →
// sondagem → conta para orçamento → orçamento enviado → crédito
// pré-aprovado → proposta de fechamento → contrato fechado) e o período
// pela régua normal do sistema (hoje, ontem, 7 dias, semana passada…).
// 🧭 18/11/2026: depois do orçamento o caminho ficou em 6 etapas
// (investimento possível → forma de pagamento → CPF e crédito → proposta
// de fechamento → contrato fechado → instalação realizada): 10 no total,
// em duas linhas de 5 no computador.
// Pouco texto, número grande, cartões retos. A régua está em
// app/services/crm/quote_journey.rb.
// 📈 24/11/2026 (pedido do Guilherme): cada cartão ganha um mini gráfico de
// linha com o histórico do período (hoje e ontem: os 7 dias que terminam
// nele; semana, mês, 90 dias, ano: o próprio período) e, no clique, a lista
// de quem está naquela etapa, com atalho para a conversa.
import { ref, computed, watch, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import PatientListPopup from 'dashboard/components-next/cevico/PatientListPopup.vue';
import { useAccount } from 'dashboard/composables/useAccount';

const TXT = {
  title: 'Jornada da venda',
  subtitle: 'Quem chegou no período e até onde já andou',
  next: 'seguem',
  ofLeads: 'de quem chegou',
  sources: 'Por fonte',
  toSent: 'recebem orçamento',
  loading: 'Carregando a jornada',
  empty: 'Ninguém chegou neste período.',
  error: 'Não consegui carregar a jornada agora.',
  arrow: '→',
  open: 'Ver quem está nesta etapa',
  stopped: 'parou aqui',
  loadingPeople: 'Carregando os contatos',
  peopleError: 'Não consegui carregar os contatos agora.',
  noun: 'contato',
};

const { accountId } = useAccount();

// o período escolhido fica lembrado neste navegador (só comodidade)
const PERIOD_KEY = 'cevico:jornada:periodo';
const savedPeriod = () => {
  try {
    const saved = JSON.parse(localStorage.getItem(PERIOD_KEY) || 'null');
    if (saved?.preset) return saved;
  } catch {
    // sem memória do navegador: segue no padrão
  }
  return { preset: 'last7', from: '', to: '' };
};
const periodo = ref(savedPeriod());
const journey = ref(null);
const loading = ref(false);
const failed = ref(false);
let seq = 0;

const steps = computed(() => journey.value?.steps || []);
const jumps = computed(() =>
  (journey.value?.jumps || []).filter(j => j.pct !== null)
);
const sources = computed(() => journey.value?.sources || []);
const leads = computed(() => steps.value[0]?.count || 0);

// 📈 mini gráfico: pontos da linha e da área num quadro de 100 × 30
const series = computed(() => journey.value?.series || null);
const SPARK_W = 100;
const SPARK_H = 30;
const spark = key => {
  const values = series.value?.values?.[key] || [];
  if (values.length < 2) return null;
  const max = Math.max(1, ...values);
  const pts = values.map((v, i) => [
    (i / (values.length - 1)) * SPARK_W,
    SPARK_H - 2 - (v / max) * (SPARK_H - 6),
  ]);
  const line = pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
  const last = pts[pts.length - 1];
  return {
    line,
    area: `0,${SPARK_H} ${line} ${SPARK_W},${SPARK_H}`,
    last,
    tip: values.map((v, i) => `${series.value.labels[i]}: ${v}`).join(' · '),
  };
};

// 👥 lista de quem está na etapa (janela com atalho para a conversa)
const popup = ref(null);
const openStep = async step => {
  popup.value = { title: step.label, subtitle: TXT.loadingPeople, people: [] };
  try {
    const { data } = await CrmAPI.getHome({
      only: 'quote_journey_people',
      step: step.key,
      preset: periodo.value.preset,
      from: periodo.value.from,
      to: periodo.value.to,
    });
    if (popup.value?.title !== step.label) return;
    const people = data.people || [];
    const stopped = people.filter(p => p.parou).length;
    popup.value = {
      title: step.label,
      subtitle: stopped ? `${stopped} ${TXT.stopped}` : '',
      people,
    };
  } catch {
    if (popup.value) popup.value.subtitle = TXT.peopleError;
  }
};
const rightOf = person => (person.parou ? TXT.stopped : person.etapa);

const pctText = value =>
  value === null || value === undefined ? '' : `${value}%`;
const jumpText = jump => `${jump.from_label} ${TXT.arrow} ${jump.to_label}`;
const barWidth = step => `${Math.max(step.of_leads ?? 0, step.count ? 4 : 0)}%`;

const load = async () => {
  seq += 1;
  const mine = seq;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmAPI.getHome({
      only: 'quote_journey',
      preset: periodo.value.preset,
      from: periodo.value.from,
      to: periodo.value.to,
    });
    if (mine === seq) journey.value = data.quote_journey;
  } catch {
    if (mine === seq) failed.value = true;
  } finally {
    if (mine === seq) loading.value = false;
  }
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
    <div class="qj p-4 sm:p-5">
      <div class="qj-head">
        <span class="cv-icon cv-icon-sm">
          <span class="i-lucide-route text-sm" />
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-bold text-n-slate-12 leading-none">
            {{ TXT.title }}
          </h2>
          <p class="text-[11px] text-n-slate-9 mt-0.5">{{ TXT.subtitle }}</p>
        </div>
      </div>
      <div class="qj-ruler">
        <PeriodRuler v-model="periodo" glass />
      </div>

      <p v-if="failed" class="qj-note">{{ TXT.error }}</p>
      <p v-else-if="!journey && loading" class="qj-note">{{ TXT.loading }}</p>

      <template v-else-if="journey">
        <!-- as etapas: número grande + quantos seguem para a próxima -->
        <ol class="qj-steps" :class="loading ? 'qj-dim' : ''">
          <li
            v-for="(step, index) in steps"
            :key="step.key"
            class="qj-step qj-click"
            :class="`qj-step-${index}`"
            role="button"
            tabindex="0"
            :title="TXT.open"
            @click="openStep(step)"
            @keydown.enter="openStep(step)"
          >
            <span class="qj-label">{{ step.label }}</span>
            <div class="qj-top">
              <b class="qj-count tabular-nums">{{ step.count }}</b>
              <svg
                v-if="spark(step.key)"
                class="qj-spark"
                :viewBox="`0 0 ${SPARK_W} ${SPARK_H}`"
                preserveAspectRatio="none"
                aria-hidden="true"
              >
                <title>{{ spark(step.key).tip }}</title>
                <polygon class="qj-spark-area" :points="spark(step.key).area" />
                <polyline
                  class="qj-spark-line"
                  :points="spark(step.key).line"
                  vector-effect="non-scaling-stroke"
                />
                <circle
                  class="qj-spark-dot"
                  :cx="spark(step.key).last[0]"
                  :cy="spark(step.key).last[1]"
                  r="2.2"
                  vector-effect="non-scaling-stroke"
                />
              </svg>
            </div>
            <span class="qj-bar">
              <span class="qj-bar-fill" :style="{ width: barWidth(step) }" />
            </span>
            <span v-if="step.to_next !== null" class="qj-next">
              <span class="i-lucide-arrow-right text-[13px]" />
              <b class="tabular-nums">{{ pctText(step.to_next) }}</b>
              {{ TXT.next }}
            </span>
            <span v-else-if="step.of_leads !== null" class="qj-next qj-end">
              <b class="tabular-nums">{{ pctText(step.of_leads) }}</b>
              {{ TXT.ofLeads }}
            </span>
          </li>
        </ol>

        <p v-if="!leads" class="qj-note">{{ TXT.empty }}</p>

        <template v-else>
          <!-- saltos: de quem chegou, quantos receberam orçamento / fecharam -->
          <div v-if="jumps.length" class="qj-jumps">
            <span v-for="jump in jumps" :key="jump.to" class="qj-jump">
              <b class="tabular-nums">{{ pctText(jump.pct) }}</b>
              {{ jumpText(jump) }}
            </span>
          </div>

          <!-- por fonte de tráfego -->
          <div v-if="sources.length" class="qj-sources">
            <p class="qj-sources-title">{{ TXT.sources }}</p>
            <div class="qj-table">
              <div class="qj-row qj-row-head">
                <span />
                <span v-for="step in steps" :key="step.key">
                  {{ step.short }}
                </span>
                <span class="qj-conv">{{ TXT.toSent }}</span>
              </div>
              <div v-for="source in sources" :key="source.key" class="qj-row">
                <b class="qj-source">{{ source.label }}</b>
                <span
                  v-for="(count, index) in source.counts"
                  :key="index"
                  class="qj-cell tabular-nums"
                  :class="count ? '' : 'qj-zero'"
                >
                  <small class="qj-cell-label">{{ steps[index]?.short }}</small>
                  {{ count }}
                </span>
                <b class="qj-conv tabular-nums">
                  {{ pctText(source.lead_to_sent) }}
                  <small class="qj-cell-label">{{ TXT.toSent }}</small>
                </b>
              </div>
            </div>
          </div>
        </template>
      </template>
    </div>
    <PatientListPopup
      v-if="popup"
      :title="popup.title"
      :subtitle="popup.subtitle"
      :people="popup.people"
      :account-id="accountId"
      :right="rightOf"
      :noun="TXT.noun"
      grad="linear-gradient(135deg, #c2410c, #fb923c)"
      icon="i-lucide-route"
      empty-text="Ninguém nesta etapa no período."
      @close="popup = null"
    />
  </div>
</template>

<style scoped>
.qj {
  container-type: inline-size;
  --qj-accent: #ea580c;
}
.qj-head {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px 12px;
  margin-bottom: 14px;
}
.qj-ruler {
  margin: -4px 0 14px;
  max-width: 100%;
}
.qj-note {
  padding: 14px 0 4px;
  font-size: 13px;
  color: #64748b;
}
.qj-dim {
  opacity: 0.55;
}

/* etapas */
.qj-steps {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}
@container (min-width: 520px) {
  .qj-steps {
    grid-template-columns: repeat(5, minmax(0, 1fr));
  }
}
.qj-step {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
  padding: 12px 12px 10px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  border-top: 3px solid var(--qj-accent);
  background: rgba(255, 255, 255, 0.78);
}
.qj-step-0 {
  border-top-color: #1e293b;
}
.qj-step-8,
.qj-step-9 {
  border-top-color: #16a34a;
}
.qj-label {
  font-size: 11px;
  font-weight: 700;
  line-height: 1.25;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.qj-count {
  font-size: 30px;
  font-weight: 800;
  line-height: 1.05;
  color: #0f172a;
}
.qj-bar {
  display: block;
  height: 4px;
  border-radius: 9999px;
  background: rgba(100, 116, 139, 0.18);
  overflow: hidden;
}
.qj-bar-fill {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: var(--qj-accent);
}
.qj-step-0 .qj-bar-fill {
  background: #1e293b;
}
.qj-step-8 .qj-bar-fill,
.qj-step-9 .qj-bar-fill {
  background: #16a34a;
}
.qj-next {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 2px;
  font-size: 11.5px;
  line-height: 1.3;
  color: #475569;
}
.qj-next b {
  font-size: 14px;
  color: #c2410c;
}
.qj-end b {
  color: #15803d;
}

/* saltos */
.qj-jumps {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 10px;
}
.qj-jump {
  display: inline-flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 6px;
  padding: 7px 12px;
  border-radius: 10px;
  font-size: 12.5px;
  color: #334155;
  background: rgba(100, 116, 139, 0.1);
  border: 1px solid rgba(100, 116, 139, 0.22);
}
.qj-jump b {
  font-size: 16px;
  color: #0f172a;
}

/* fontes */
.qj-sources {
  margin-top: 14px;
}
.qj-sources-title {
  margin-bottom: 6px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.qj-table {
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.24);
  background: rgba(255, 255, 255, 0.6);
  overflow: hidden;
}
.qj-row {
  display: grid;
  grid-template-columns: minmax(72px, 1.4fr) repeat(10, minmax(0, 1fr)) minmax(
      54px,
      1fr
    );
  align-items: center;
  gap: 4px;
  padding: 9px 12px;
  font-size: 14px;
  color: #0f172a;
  border-top: 1px solid rgba(100, 116, 139, 0.16);
}
.qj-row > span,
.qj-row > b {
  min-width: 0;
  text-align: right;
}
.qj-row > .qj-source {
  text-align: left;
  font-size: 13px;
  overflow-wrap: anywhere;
}
.qj-row-head {
  border-top: 0;
  padding-top: 8px;
  padding-bottom: 8px;
  font-size: 10px;
  font-weight: 700;
  line-height: 1.2;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  color: #64748b;
  background: rgba(100, 116, 139, 0.08);
}
.qj-conv {
  color: #c2410c;
}
.qj-row-head .qj-conv {
  color: #64748b;
}
.qj-zero {
  color: #94a3b8;
}
.qj-cell-label {
  display: none;
}
/* celular: período numa linha só dele; cada fonte vira um bloco (nome + conversão em cima,
   os números embaixo, cada um com o nome da etapa) */
@container (max-width: 520px) {
  .qj-row-head {
    display: none;
  }
  .qj-row {
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 6px 2px;
    padding: 10px 8px;
    font-size: 15px;
  }
  .qj-row:first-of-type + .qj-row,
  .qj-row:nth-child(2) {
    border-top: 0;
  }
  .qj-row > .qj-source {
    grid-column: 1 / span 3;
    order: 0;
    font-size: 14px;
  }
  .qj-row > .qj-conv {
    grid-column: 4 / span 2;
    order: 1;
    display: inline-flex;
    align-items: baseline;
    justify-content: flex-end;
    gap: 5px;
    font-size: 15px;
  }
  .qj-row > .qj-conv {
    white-space: nowrap;
  }
  .qj-row > .qj-conv .qj-cell-label {
    display: inline;
    font-size: 10px;
    font-weight: 500;
    color: #64748b;
  }
  .qj-row > .qj-cell {
    order: 2;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
    text-align: center;
    font-weight: 700;
  }
  .qj-cell .qj-cell-label {
    display: block;
    font-size: 8.5px;
    font-weight: 600;
    letter-spacing: 0;
    text-transform: uppercase;
    color: #64748b;
  }
  .qj-count {
    font-size: 26px;
  }
}

/* 📈 mini gráfico e clique (24/11) */
.qj-click {
  cursor: pointer;
  transition:
    transform 0.12s ease,
    box-shadow 0.12s ease;
}
.qj-click:hover {
  transform: translateY(-1px);
  box-shadow: 0 6px 18px rgba(15, 23, 42, 0.12);
}
.qj-click:focus-visible {
  outline: 2px solid var(--qj-accent);
  outline-offset: 2px;
}
.qj-top {
  display: flex;
  align-items: flex-end;
  gap: 8px;
  min-width: 0;
}
.qj-spark {
  flex: 1;
  min-width: 0;
  height: 30px;
  overflow: visible;
}
.qj-spark-line {
  fill: none;
  stroke: var(--qj-accent);
  stroke-width: 1.6;
  stroke-linejoin: round;
  stroke-linecap: round;
}
.qj-spark-area {
  fill: var(--qj-accent);
  opacity: 0.12;
}
.qj-spark-dot {
  fill: var(--qj-accent);
}
.qj-step-0 .qj-spark-line {
  stroke: #1e293b;
}
.qj-step-0 .qj-spark-area,
.qj-step-0 .qj-spark-dot {
  fill: #1e293b;
}
.qj-step-8 .qj-spark-line,
.qj-step-9 .qj-spark-line {
  stroke: #16a34a;
}
.qj-step-8 .qj-spark-area,
.qj-step-9 .qj-spark-area,
.qj-step-8 .qj-spark-dot,
.qj-step-9 .qj-spark-dot {
  fill: #16a34a;
}
:global(.dark .qj-step-0 .qj-spark-line) {
  stroke: #e2e8f0;
}
:global(.dark .qj-step-0 .qj-spark-area),
:global(.dark .qj-step-0 .qj-spark-dot) {
  fill: #e2e8f0;
}
:global(.dark .qj-click:hover) {
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.35);
}

/* tema escuro */
:global(.dark .qj-note),
:global(.dark .qj-label),
:global(.dark .qj-sources-title),
:global(.dark .qj-row-head),
:global(.dark .qj-row-head .qj-conv) {
  color: rgba(255, 255, 255, 0.62);
}
:global(.dark .qj-step) {
  background: rgba(255, 255, 255, 0.045);
  border-color: rgba(255, 255, 255, 0.12);
  border-top-color: var(--qj-accent);
}
:global(.dark .qj-step-0) {
  border-top-color: #e2e8f0;
}
:global(.dark .qj-step-8),
:global(.dark .qj-step-9) {
  border-top-color: #22c55e;
}
:global(.dark .qj-step-0 .qj-bar-fill) {
  background: #e2e8f0;
}
:global(.dark .qj-count),
:global(.dark .qj-jump b),
:global(.dark .qj-row) {
  color: #fff;
}
:global(.dark .qj-bar) {
  background: rgba(255, 255, 255, 0.12);
}
:global(.dark .qj-next),
:global(.dark .qj-jump) {
  color: rgba(255, 255, 255, 0.78);
}
:global(.dark .qj-next b),
:global(.dark .qj-conv) {
  color: #fdba74;
}
:global(.dark .qj-end b) {
  color: #86efac;
}
:global(.dark .qj-jump) {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.14);
}
:global(.dark .qj-table) {
  background: rgba(255, 255, 255, 0.03);
  border-color: rgba(255, 255, 255, 0.12);
}
:global(.dark .qj-row) {
  border-top-color: rgba(255, 255, 255, 0.08);
}
:global(.dark .qj-row-head) {
  background: rgba(255, 255, 255, 0.05);
}
:global(.dark .qj-zero) {
  color: rgba(255, 255, 255, 0.35);
}
:global(.dark .qj-cell-label) {
  color: rgba(255, 255, 255, 0.55) !important;
}
</style>
