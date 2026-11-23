<script setup>
// 👓 22/11/2026 (pedido do Guilherme): JORNADA DA ÓTICA no Meu Painel — a
// mesma tecnologia da "Jornada da venda" da LIFE, no caminho da ótica:
// NA CONVERSA novos → mandou a foto → recebeu a prova → agendou → confirmou
// NA LOJA     veio → comprou → óculos pronto → retirou.
// Enriquecida com o que o painel da ótica já tinha: o dinheiro de quem
// chegou (vendas, faturamento, ticket), quem desmarcou ou faltou, o exame
// pago no PIX (quando a conta usa), as fontes com faturamento e, no clique
// de cada etapa, QUEM parou ali (abre a conversa).
// Pouco texto, número grande, cartões retos. A régua está em
// app/services/otica/journey.rb.
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import CrmAPI from 'dashboard/api/crm';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';

const TXT = {
  title: 'Jornada da ótica',
  subtitle: 'Quem chegou no período e até onde já andou',
  next: 'seguem',
  ofLeads: 'de quem chegou',
  sources: 'Por fonte',
  toBooked: 'agendam',
  revenue: 'faturamento',
  sales: 'Vendas',
  revenueTitle: 'Faturamento',
  ticket: 'Ticket médio',
  missed: 'desmarcaram ou faltaram',
  exams: 'agendaram exame',
  pix: 'pagaram o exame no PIX',
  stopped: 'pararam aqui',
  peopleTitle: 'Pararam em',
  noPeople: 'Ninguém parou nesta etapa.',
  more: 'mostrando os 30 mais recentes',
  close: 'Fechar',
  openChat: 'Abrir conversa',
  loading: 'Carregando a jornada',
  empty: 'Ninguém chegou neste período.',
  error: 'Não consegui carregar a jornada agora.',
  arrow: '→',
  hint: 'Toque numa etapa para ver quem parou nela.',
};

const route = useRoute();
const accountId = computed(() => route.params.accountId);

const PERIOD_KEY = 'cevico:jornada-otica:periodo';
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
const openStep = ref(null);
let seq = 0;

const steps = computed(() => journey.value?.steps || []);
const groups = computed(() =>
  (journey.value?.groups || []).map(group => ({
    ...group,
    steps: steps.value
      .map((step, index) => ({ ...step, index }))
      .filter(step => step.group === group.key),
  }))
);
const jumps = computed(() =>
  (journey.value?.jumps || []).filter(j => j.pct !== null)
);
const sources = computed(() => journey.value?.sources || []);
const money = computed(() => journey.value?.money || {});
const extras = computed(() => journey.value?.extras || {});
const leads = computed(() => steps.value[0]?.count || 0);
const selected = computed(() =>
  steps.value.find(step => step.key === openStep.value)
);

const brl = value =>
  Number(value || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
const pctText = value =>
  value === null || value === undefined ? '' : `${value}%`;
const jumpText = jump => `${jump.from_label} ${TXT.arrow} ${jump.to_label}`;
const barWidth = step => `${Math.max(step.of_leads ?? 0, step.count ? 4 : 0)}%`;
const ago = iso => {
  if (!iso) return '';
  const hours = (Date.now() - new Date(iso).getTime()) / 36e5;
  if (hours < 1) return 'chegou agora';
  if (hours < 24) return `chegou há ${Math.round(hours)} h`;
  const days = Math.round(hours / 24);
  return days === 1 ? 'chegou ontem' : `chegou há ${days} dias`;
};
const chatLink = person =>
  person.conversation_id
    ? `/app/accounts/${accountId.value}/conversations/${person.conversation_id}`
    : null;
const toggleStep = step => {
  openStep.value = openStep.value === step.key ? null : step.key;
};

const load = async () => {
  seq += 1;
  const mine = seq;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmAPI.getHome({
      only: 'otica_journey',
      preset: periodo.value.preset,
      from: periodo.value.from,
      to: periodo.value.to,
    });
    if (mine === seq) journey.value = data.otica_journey;
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
    openStep.value = null;
    load();
  },
  { deep: true }
);

onMounted(load);
</script>

<template>
  <div class="cv-block mb-6">
    <div class="oj p-4 sm:p-5">
      <div class="oj-head">
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
      <div class="oj-ruler">
        <PeriodRuler v-model="periodo" glass />
      </div>

      <p v-if="failed" class="oj-note">{{ TXT.error }}</p>
      <p v-else-if="!journey && loading" class="oj-note">{{ TXT.loading }}</p>

      <template v-else-if="journey">
        <!-- as etapas em dois grupos: na conversa e na loja -->
        <div :class="loading ? 'oj-dim' : ''">
          <section
            v-for="group in groups"
            :key="group.key"
            class="oj-group"
            :class="`oj-group-${group.key}`"
          >
            <p class="oj-group-title">{{ group.label }}</p>
            <ol class="oj-steps">
              <li v-for="step in group.steps" :key="step.key">
                <button
                  type="button"
                  class="oj-step"
                  :class="[
                    `oj-step-${step.key}`,
                    openStep === step.key ? 'oj-step-open' : '',
                  ]"
                  :aria-expanded="openStep === step.key"
                  @click="toggleStep(step)"
                >
                  <span class="oj-label">{{ step.label }}</span>
                  <b class="oj-count tabular-nums">{{ step.count }}</b>
                  <span class="oj-bar">
                    <span
                      class="oj-bar-fill"
                      :style="{ width: barWidth(step) }"
                    />
                  </span>
                  <span v-if="step.to_next !== null" class="oj-next">
                    <span class="i-lucide-arrow-right text-[13px]" />
                    <b class="tabular-nums">{{ pctText(step.to_next) }}</b>
                    {{ TXT.next }}
                  </span>
                  <span
                    v-else-if="step.index === steps.length - 1 && step.count"
                    class="oj-next oj-end"
                  >
                    <b class="tabular-nums">{{ pctText(step.of_leads) }}</b>
                    {{ TXT.ofLeads }}
                  </span>
                  <span v-if="step.stopped" class="oj-stopped">
                    {{ step.stopped }} {{ TXT.stopped }}
                  </span>
                </button>
              </li>
            </ol>
          </section>
        </div>

        <!-- quem parou na etapa tocada -->
        <div v-if="selected" class="oj-people">
          <div class="oj-people-head">
            <b>{{ TXT.peopleTitle }} «{{ selected.label }}»</b>
            <span class="oj-people-count tabular-nums">
              {{ selected.stopped }}
            </span>
            <button
              type="button"
              class="oj-close"
              :aria-label="TXT.close"
              @click="openStep = null"
            >
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <p v-if="!selected.people.length" class="oj-note">
            {{ TXT.noPeople }}
          </p>
          <ul v-else class="oj-people-list">
            <li v-for="person in selected.people" :key="person.id">
              <span class="oj-person-name">{{ person.name }}</span>
              <span class="oj-person-meta">
                {{ person.source }} · {{ ago(person.arrived_at) }}
              </span>
              <router-link
                v-if="chatLink(person)"
                :to="chatLink(person)"
                class="oj-person-link"
              >
                <span class="i-lucide-message-circle text-[13px]" />
                {{ TXT.openChat }}
              </router-link>
            </li>
          </ul>
          <p v-if="selected.stopped > selected.people.length" class="oj-more">
            {{ TXT.more }}
          </p>
        </div>

        <p v-if="!leads" class="oj-note">{{ TXT.empty }}</p>

        <template v-else>
          <p v-if="!selected" class="oj-hint">{{ TXT.hint }}</p>

          <!-- o dinheiro de quem chegou + o que acontece ao lado da linha -->
          <div class="oj-cards">
            <div class="oj-card">
              <span class="oj-card-label">{{ TXT.sales }}</span>
              <b class="oj-card-value tabular-nums">{{ money.sales || 0 }}</b>
            </div>
            <div class="oj-card">
              <span class="oj-card-label">{{ TXT.revenueTitle }}</span>
              <b class="oj-card-value tabular-nums">
                {{ brl(money.revenue) }}
              </b>
            </div>
            <div class="oj-card">
              <span class="oj-card-label">{{ TXT.ticket }}</span>
              <b class="oj-card-value tabular-nums">
                {{ money.ticket ? brl(money.ticket) : '—' }}
              </b>
            </div>
          </div>

          <div class="oj-jumps">
            <span v-for="jump in jumps" :key="jump.to" class="oj-jump">
              <b class="tabular-nums">{{ pctText(jump.pct) }}</b>
              {{ jumpText(jump) }}
            </span>
            <span v-if="extras.exams" class="oj-jump">
              <b class="tabular-nums">{{ extras.exams }}</b>
              {{ TXT.exams }}
            </span>
            <span v-if="extras.pix_asked" class="oj-jump">
              <b class="tabular-nums">
                {{ extras.pix_paid }}/{{ extras.pix_asked }}
              </b>
              {{ TXT.pix }}
            </span>
            <span v-if="extras.missed" class="oj-jump oj-jump-bad">
              <b class="tabular-nums">{{ extras.missed }}</b>
              {{ TXT.missed }}
            </span>
          </div>

          <!-- por fonte de tráfego -->
          <div v-if="sources.length" class="oj-sources">
            <p class="oj-sources-title">{{ TXT.sources }}</p>
            <div class="oj-table">
              <div class="oj-row oj-row-head">
                <span />
                <span v-for="step in steps" :key="step.key">
                  {{ step.short }}
                </span>
                <span class="oj-conv">{{ TXT.toBooked }}</span>
                <span class="oj-rev">{{ TXT.revenue }}</span>
              </div>
              <div v-for="source in sources" :key="source.key" class="oj-row">
                <b class="oj-source">{{ source.label }}</b>
                <span
                  v-for="(count, index) in source.counts"
                  :key="index"
                  class="oj-cell tabular-nums"
                  :class="count ? '' : 'oj-zero'"
                >
                  <small class="oj-cell-label">{{ steps[index]?.short }}</small>
                  {{ count }}
                </span>
                <b class="oj-conv tabular-nums">
                  {{ pctText(source.lead_to_booked) }}
                  <small class="oj-cell-label">{{ TXT.toBooked }}</small>
                </b>
                <b class="oj-rev tabular-nums">
                  {{ brl(source.revenue) }}
                </b>
              </div>
            </div>
          </div>
        </template>
      </template>
    </div>
  </div>
</template>

<style scoped>
.oj {
  container-type: inline-size;
  --oj-conversa: #2563eb;
  --oj-loja: #0e7490;
  --oj-bad: #dc2626;
}
.oj-head {
  display: flex;
  align-items: center;
  gap: 10px 12px;
  margin-bottom: 14px;
}
.oj-ruler {
  margin: -4px 0 14px;
  max-width: 100%;
}
.oj-note,
.oj-hint {
  padding: 12px 0 2px;
  font-size: 13px;
  color: #64748b;
}
.oj-hint {
  padding: 8px 0 0;
  font-size: 11.5px;
}
.oj-dim {
  opacity: 0.55;
}

/* grupos e etapas */
.oj-group {
  --oj-accent: var(--oj-conversa);
}
.oj-group-loja {
  --oj-accent: var(--oj-loja);
  margin-top: 12px;
}
.oj-group-title {
  margin-bottom: 6px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--oj-accent);
}
.oj-steps {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}
@container (min-width: 520px) {
  .oj-steps {
    grid-template-columns: repeat(5, minmax(0, 1fr));
  }
}
.oj-step {
  display: flex;
  flex-direction: column;
  gap: 4px;
  width: 100%;
  height: 100%;
  min-width: 0;
  padding: 12px 12px 10px;
  text-align: left;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  border-top: 3px solid var(--oj-accent);
  background: rgba(255, 255, 255, 0.78);
  cursor: pointer;
  transition:
    box-shadow 0.15s,
    border-color 0.15s;
}
.oj-step:hover {
  box-shadow: 0 2px 10px rgba(15, 23, 42, 0.08);
}
.oj-step:focus-visible {
  outline: 2px solid var(--oj-accent);
  outline-offset: 2px;
}
.oj-step-open {
  border-color: var(--oj-accent);
  box-shadow: 0 0 0 1px var(--oj-accent);
}
.oj-step-leads {
  border-top-color: #1e293b;
}
.oj-label {
  font-size: 11px;
  font-weight: 700;
  line-height: 1.25;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.oj-count {
  font-size: 30px;
  font-weight: 800;
  line-height: 1.05;
  color: #0f172a;
}
.oj-bar {
  display: block;
  height: 4px;
  border-radius: 9999px;
  background: rgba(100, 116, 139, 0.18);
  overflow: hidden;
}
.oj-bar-fill {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: var(--oj-accent);
}
.oj-step-leads .oj-bar-fill {
  background: #1e293b;
}
.oj-next {
  display: inline-flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 2px;
  font-size: 11.5px;
  line-height: 1.3;
  color: #475569;
}
.oj-next b {
  font-size: 14px;
  color: var(--oj-accent);
}
.oj-stopped {
  font-size: 10.5px;
  color: #94a3b8;
}

/* quem parou */
.oj-people {
  margin-top: 12px;
  padding: 12px 14px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  background: rgba(255, 255, 255, 0.7);
}
.oj-people-head {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: #0f172a;
}
.oj-people-count {
  padding: 1px 8px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 700;
  background: rgba(100, 116, 139, 0.14);
}
.oj-close {
  margin-left: auto;
  display: inline-flex;
  padding: 4px;
  border-radius: 8px;
  color: #64748b;
}
.oj-close:hover {
  background: rgba(100, 116, 139, 0.12);
}
.oj-people-list {
  margin: 8px 0 0;
  padding: 0;
  list-style: none;
}
.oj-people-list li {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px 10px;
  padding: 8px 0;
  border-top: 1px solid rgba(100, 116, 139, 0.14);
}
.oj-people-list li:first-child {
  border-top: 0;
}
.oj-person-name {
  font-size: 13.5px;
  font-weight: 600;
  color: #0f172a;
  overflow-wrap: anywhere;
}
.oj-person-meta {
  font-size: 11.5px;
  color: #64748b;
}
.oj-person-link {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 600;
  color: var(--oj-conversa);
  background: rgba(37, 99, 235, 0.08);
}
.oj-person-link:hover {
  background: rgba(37, 99, 235, 0.16);
}
.oj-more {
  margin-top: 6px;
  font-size: 11px;
  color: #94a3b8;
}

/* dinheiro */
.oj-cards {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px;
  margin-top: 12px;
}
.oj-card {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
  padding: 10px 12px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.22);
  background: rgba(100, 116, 139, 0.06);
}
.oj-card-label {
  font-size: 10.5px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.oj-card-value {
  font-size: 20px;
  font-weight: 800;
  line-height: 1.15;
  color: #0f172a;
  overflow-wrap: anywhere;
}

/* saltos e laterais */
.oj-jumps {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 10px;
}
.oj-jump {
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
.oj-jump b {
  font-size: 16px;
  color: #0f172a;
}
.oj-jump-bad {
  border-color: rgba(220, 38, 38, 0.3);
  background: rgba(220, 38, 38, 0.06);
}
.oj-jump-bad b {
  color: var(--oj-bad);
}

/* fontes */
.oj-sources {
  margin-top: 14px;
}
.oj-sources-title {
  margin-bottom: 6px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.oj-table {
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.24);
  background: rgba(255, 255, 255, 0.6);
  overflow: hidden;
}
.oj-row {
  display: grid;
  grid-template-columns:
    minmax(72px, 1.4fr) repeat(9, minmax(0, 1fr)) minmax(54px, 1fr)
    minmax(76px, 1.3fr);
  align-items: center;
  gap: 4px;
  padding: 9px 12px;
  font-size: 14px;
  color: #0f172a;
  border-top: 1px solid rgba(100, 116, 139, 0.16);
}
.oj-row > span,
.oj-row > b {
  min-width: 0;
  text-align: right;
}
.oj-row > .oj-source {
  text-align: left;
  font-size: 13px;
  overflow-wrap: anywhere;
}
.oj-row-head {
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
.oj-conv {
  color: var(--oj-conversa);
}
.oj-rev {
  font-size: 13px;
}
.oj-row-head .oj-conv,
.oj-row-head .oj-rev {
  color: #64748b;
  font-size: 10px;
}
.oj-zero {
  color: #94a3b8;
}
.oj-cell-label {
  display: none;
}
/* celular: cada fonte vira um bloco (nome + conversão em cima, os números embaixo) */
@container (max-width: 520px) {
  .oj-row-head {
    display: none;
  }
  .oj-row {
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 6px 2px;
    padding: 10px 8px;
    font-size: 15px;
  }
  .oj-row:nth-child(2) {
    border-top: 0;
  }
  .oj-row > .oj-source {
    grid-column: 1 / span 2;
    order: 0;
    font-size: 14px;
  }
  .oj-row > .oj-conv {
    grid-column: 3 / span 1;
    order: 1;
    display: inline-flex;
    flex-direction: column;
    align-items: flex-end;
    font-size: 15px;
    white-space: nowrap;
  }
  .oj-row > .oj-rev {
    grid-column: 4 / span 2;
    order: 1;
    font-size: 14px;
  }
  .oj-row > .oj-conv .oj-cell-label {
    display: inline;
    font-size: 10px;
    font-weight: 500;
    color: #64748b;
  }
  .oj-row > .oj-cell {
    order: 2;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
    text-align: center;
    font-weight: 700;
  }
  .oj-cell .oj-cell-label {
    display: block;
    font-size: 8.5px;
    font-weight: 600;
    text-transform: uppercase;
    color: #64748b;
  }
  .oj-count {
    font-size: 26px;
  }
  .oj-cards {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
  .oj-card-value {
    font-size: 16px;
  }
}

/* tema escuro */
:global(.dark .oj) {
  --oj-conversa: #60a5fa;
  --oj-loja: #22d3ee;
  --oj-bad: #f87171;
}
:global(.dark .oj-note),
:global(.dark .oj-hint),
:global(.dark .oj-label),
:global(.dark .oj-sources-title),
:global(.dark .oj-card-label),
:global(.dark .oj-person-meta),
:global(.dark .oj-row-head),
:global(.dark .oj-row-head .oj-conv),
:global(.dark .oj-row-head .oj-rev) {
  color: rgba(255, 255, 255, 0.62);
}
:global(.dark .oj-step),
:global(.dark .oj-people) {
  background: rgba(255, 255, 255, 0.045);
  border-color: rgba(255, 255, 255, 0.12);
}
:global(.dark .oj-step) {
  border-top-color: var(--oj-accent);
}
:global(.dark .oj-step-open) {
  border-color: var(--oj-accent);
}
:global(.dark .oj-step-leads) {
  border-top-color: #e2e8f0;
}
:global(.dark .oj-step-leads .oj-bar-fill) {
  background: #e2e8f0;
}
:global(.dark .oj-count),
:global(.dark .oj-jump b),
:global(.dark .oj-card-value),
:global(.dark .oj-people-head),
:global(.dark .oj-person-name),
:global(.dark .oj-row) {
  color: #fff;
}
:global(.dark .oj-bar) {
  background: rgba(255, 255, 255, 0.12);
}
:global(.dark .oj-next),
:global(.dark .oj-jump) {
  color: rgba(255, 255, 255, 0.78);
}
:global(.dark .oj-jump),
:global(.dark .oj-card) {
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.14);
}
:global(.dark .oj-jump-bad) {
  border-color: rgba(248, 113, 113, 0.35);
  background: rgba(248, 113, 113, 0.08);
}
:global(.dark .oj-jump-bad b) {
  color: var(--oj-bad);
}
:global(.dark .oj-people-list li) {
  border-top-color: rgba(255, 255, 255, 0.08);
}
:global(.dark .oj-person-link) {
  background: rgba(96, 165, 250, 0.12);
}
:global(.dark .oj-table) {
  background: rgba(255, 255, 255, 0.03);
  border-color: rgba(255, 255, 255, 0.12);
}
:global(.dark .oj-row) {
  border-top-color: rgba(255, 255, 255, 0.08);
}
:global(.dark .oj-row-head) {
  background: rgba(255, 255, 255, 0.05);
}
:global(.dark .oj-zero) {
  color: rgba(255, 255, 255, 0.35);
}
:global(.dark .oj-cell-label) {
  color: rgba(255, 255, 255, 0.55) !important;
}
</style>
