<script setup>
// 🧭 12/11/2026 (LIFE, pedido do Guilherme): JORNADA DO ORÇAMENTO no Meu
// Painel — quem chegou no período e até onde andou (conta pedida, conta
// recebida, orçamento gerado, orçamento enviado, fechado), a conversão de
// cada etapa para a seguinte, dois saltos (chegou → recebeu orçamento,
// chegou → fechou) e a mesma conta por fonte de tráfego.
// Pouco texto, número grande, cartões retos. A régua está em
// app/services/crm/quote_journey.rb.
import { ref, computed, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';

const TXT = {
  title: 'Jornada do orçamento',
  subtitle: 'Quem chegou no período e até onde já andou',
  days: 'dias',
  next: 'seguem',
  ofLeads: 'de quem chegou',
  sources: 'Por fonte',
  toSent: 'recebem orçamento',
  loading: 'Carregando a jornada',
  empty: 'Ninguém chegou neste período.',
  error: 'Não consegui carregar a jornada agora.',
  arrow: '→',
};

const days = ref(30);
const journey = ref(null);
const loading = ref(false);
const failed = ref(false);
let seq = 0;

const steps = computed(() => journey.value?.steps || []);
const jumps = computed(() =>
  (journey.value?.jumps || []).filter(j => j.pct !== null)
);
const sources = computed(() => journey.value?.sources || []);
const periods = computed(() => journey.value?.periods || [7, 30, 90]);
const leads = computed(() => steps.value[0]?.count || 0);

const pctText = value =>
  value === null || value === undefined ? '' : `${value}%`;
const periodText = p => `${p} ${TXT.days}`;
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
      days: days.value,
    });
    if (mine === seq) journey.value = data.quote_journey;
  } catch {
    if (mine === seq) failed.value = true;
  } finally {
    if (mine === seq) loading.value = false;
  }
};
const pickDays = value => {
  if (days.value === value) return;
  days.value = value;
  load();
};

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
        <div class="qj-periods" role="group">
          <button
            v-for="p in periods"
            :key="p"
            class="qj-period"
            :class="days === p ? 'qj-period-on' : ''"
            :aria-pressed="days === p"
            @click="pickDays(p)"
          >
            {{ periodText(p) }}
          </button>
        </div>
      </div>

      <p v-if="failed" class="qj-note">{{ TXT.error }}</p>
      <p v-else-if="!journey && loading" class="qj-note">{{ TXT.loading }}</p>

      <template v-else-if="journey">
        <!-- as 6 etapas: número grande + quantos seguem para a próxima -->
        <ol class="qj-steps" :class="loading ? 'qj-dim' : ''">
          <li
            v-for="(step, index) in steps"
            :key="step.key"
            class="qj-step"
            :class="`qj-step-${index}`"
          >
            <span class="qj-label">{{ step.label }}</span>
            <b class="qj-count tabular-nums">{{ step.count }}</b>
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
.qj-periods {
  display: flex;
  gap: 6px;
}
.qj-period {
  min-height: 32px;
  padding: 0 12px;
  border-radius: 9px;
  font-size: 12.5px;
  font-weight: 600;
  color: #475569;
  background: rgba(100, 116, 139, 0.1);
  border: 1px solid rgba(100, 116, 139, 0.22);
}
.qj-period-on {
  color: #fff;
  background: #1e293b;
  border-color: #1e293b;
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
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}
@container (min-width: 860px) {
  .qj-steps {
    grid-template-columns: repeat(6, minmax(0, 1fr));
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
.qj-step-5 {
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
.qj-step-5 .qj-bar-fill {
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
  grid-template-columns: minmax(72px, 1.4fr) repeat(6, minmax(0, 1fr)) minmax(
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
   os seis números embaixo, cada um com o nome da etapa) */
@container (max-width: 520px) {
  .qj-periods {
    flex-basis: 100%;
  }
  .qj-period {
    flex: 1;
    min-height: 36px;
  }
  .qj-row-head {
    display: none;
  }
  .qj-row {
    grid-template-columns: repeat(6, minmax(0, 1fr));
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
    grid-column: 4 / span 3;
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

/* tema escuro */
:global(.dark .qj-period) {
  color: rgba(255, 255, 255, 0.8);
  background: rgba(255, 255, 255, 0.07);
  border-color: rgba(255, 255, 255, 0.14);
}
:global(.dark .qj-period-on) {
  color: #0f172a;
  background: #fff;
  border-color: #fff;
}
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
:global(.dark .qj-step-5) {
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
