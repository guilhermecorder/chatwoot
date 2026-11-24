<script setup>
// 📬 22/11/2026 (LIFE, pedido do Guilherme): FOLLOW-UP DA VENDA no Meu
// Painel — "um dashboard aqui no meu painel da Life, com os envios das
// mensagens de follow-up… fazer esse tipo de acompanhamento aqui".
// O que os robôs mandaram no período, quem leu, quem respondeu (até 48 h)
// e quem andou no funil (até 7 dias), por momento da venda e por mensagem.
// Mesmo jeito da faixa "Jornada da venda": pouco texto, número grande,
// cartões retos. A régua está em app/services/crm/followup_panel.rb.
import { ref, computed, watch, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';

const TXT = {
  title: 'Follow-up da venda',
  subtitle: 'O que os robôs mandaram no período e quem respondeu',
  sent: 'Enviadas',
  people: 'Pessoas',
  read: 'Lidas',
  replied: 'Responderam',
  moved: 'Andaram no funil',
  failed: 'não entregues',
  ofSent: 'das enviadas',
  ofPeople: 'das pessoas',
  perDay: 'Envios por dia',
  moments: 'Por momento da venda',
  moment: 'Momento',
  off: 'desligado',
  peopleShort: 'pess.',
  open: 'Ver as mensagens',
  close: 'Fechar',
  loading: 'Carregando os envios',
  empty: 'Nenhuma mensagem de follow-up saiu neste período.',
  error: 'Não consegui carregar os envios agora.',
  note: 'Responderam = o cliente escreveu até 48 h depois. Andaram = o cartão foi para uma coluna mais adiante em até 7 dias.',
};

const PERIOD_KEY = 'cevico:followup:periodo';
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
const report = ref(null);
const loading = ref(false);
const failed = ref(false);
const opened = ref({});
let seq = 0;

const total = computed(() => report.value?.total || {});
const moments = computed(() => report.value?.moments || []);
const daily = computed(() => report.value?.daily || []);
const maxDay = computed(() => Math.max(1, ...daily.value.map(d => d.sent)));

const pct = (part, whole) =>
  whole ? `${Math.round((part * 100) / whole)}%` : '';

const cards = computed(() => {
  const t = total.value;
  return [
    { key: 'sent', label: TXT.sent, value: t.sent || 0, foot: '' },
    { key: 'people', label: TXT.people, value: t.people || 0, foot: '' },
    {
      key: 'read',
      label: TXT.read,
      value: t.read || 0,
      foot: t.sent ? `${pct(t.read, t.sent)} ${TXT.ofSent}` : '',
    },
    {
      key: 'replied',
      label: TXT.replied,
      value: t.replied || 0,
      foot: t.people ? `${pct(t.replied, t.people)} ${TXT.ofPeople}` : '',
    },
    {
      key: 'moved',
      label: TXT.moved,
      value: t.moved || 0,
      foot: t.people ? `${pct(t.moved, t.people)} ${TXT.ofPeople}` : '',
    },
  ];
});

const dayLabel = iso => {
  const [, m, d] = iso.split('-');
  return `${d}/${m}`;
};
const barHeight = day =>
  `${Math.max((day.sent * 100) / maxDay.value, day.sent ? 6 : 0)}%`;

const toggle = key => {
  opened.value = { ...opened.value, [key]: !opened.value[key] };
};

const load = async () => {
  seq += 1;
  const mine = seq;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await CrmAPI.getHome({
      only: 'followup_panel',
      preset: periodo.value.preset,
      from: periodo.value.from,
      to: periodo.value.to,
    });
    if (mine === seq) report.value = data.followup_panel;
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
    <div class="fu p-4 sm:p-5">
      <div class="fu-head">
        <span class="cv-icon cv-icon-sm">
          <span class="i-lucide-send text-sm" />
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-bold text-n-slate-12 leading-none">
            {{ TXT.title }}
          </h2>
          <p class="text-[11px] text-n-slate-9 mt-0.5">{{ TXT.subtitle }}</p>
        </div>
      </div>
      <div class="fu-ruler">
        <PeriodRuler v-model="periodo" glass />
      </div>

      <p v-if="failed" class="fu-note">{{ TXT.error }}</p>
      <p v-else-if="!report && loading" class="fu-note">{{ TXT.loading }}</p>

      <template v-else-if="report">
        <div :class="loading ? 'fu-dim' : ''">
          <!-- os números do período -->
          <ol class="fu-cards">
            <li
              v-for="card in cards"
              :key="card.key"
              class="fu-card"
              :class="`fu-card-${card.key}`"
            >
              <span class="fu-label">{{ card.label }}</span>
              <b class="fu-count tabular-nums">{{ card.value }}</b>
              <span class="fu-foot">
                <b v-if="card.foot" class="tabular-nums">{{
                  card.foot.split(' ')[0]
                }}</b>
                {{ card.foot.split(' ').slice(1).join(' ') }}
              </span>
            </li>
          </ol>
          <p v-if="total.failed" class="fu-failed">
            <span class="i-lucide-triangle-alert text-[13px]" />
            <b class="tabular-nums">{{ total.failed }}</b> {{ TXT.failed }}
          </p>

          <p v-if="!total.sent" class="fu-note">{{ TXT.empty }}</p>

          <template v-else>
            <!-- envios por dia -->
            <div v-if="daily.length > 1" class="fu-days">
              <p class="fu-section">{{ TXT.perDay }}</p>
              <div class="fu-chart">
                <div
                  v-for="day in daily"
                  :key="day.day"
                  class="fu-day"
                  :title="`${dayLabel(day.day)}: ${day.sent}`"
                >
                  <span class="fu-day-n tabular-nums">{{
                    day.sent || ''
                  }}</span>
                  <span class="fu-day-bar">
                    <span
                      class="fu-day-fill"
                      :style="{ height: barHeight(day) }"
                    />
                  </span>
                  <span class="fu-day-label">{{ dayLabel(day.day) }}</span>
                </div>
              </div>
            </div>
          </template>

          <!-- por momento da venda (cada robô) e, aberto, por mensagem -->
          <div v-if="moments.length" class="fu-moments">
            <p class="fu-section">{{ TXT.moments }}</p>
            <div class="fu-table">
              <div class="fu-row fu-row-head">
                <span>{{ TXT.moment }}</span>
                <span>{{ TXT.sent }}</span>
                <span>{{ TXT.read }}</span>
                <span>{{ TXT.replied }}</span>
                <span>{{ TXT.moved }}</span>
              </div>
              <template v-for="m in moments" :key="m.key">
                <button
                  type="button"
                  class="fu-row fu-row-moment"
                  :disabled="!m.steps.length"
                  :title="
                    m.steps.length ? (opened[m.key] ? TXT.close : TXT.open) : ''
                  "
                  @click="toggle(m.key)"
                >
                  <span class="fu-name">
                    <span
                      v-if="m.steps.length"
                      class="fu-chev text-[13px]"
                      :class="
                        opened[m.key]
                          ? 'i-lucide-chevron-down'
                          : 'i-lucide-chevron-right'
                      "
                    />
                    <span class="min-w-0">
                      <b>{{ m.name }}</b>
                      <small v-if="!m.active" class="fu-off">{{
                        TXT.off
                      }}</small>
                      <small class="fu-where">{{ m.where }}</small>
                    </span>
                  </span>
                  <span
                    class="fu-cell tabular-nums"
                    :class="m.sent ? '' : 'fu-zero'"
                  >
                    <small class="fu-cell-label">{{ TXT.sent }}</small>
                    {{ m.sent }}
                    <small v-if="m.people" class="fu-sub">
                      {{ m.people }} {{ TXT.peopleShort }}
                    </small>
                  </span>
                  <span
                    class="fu-cell tabular-nums"
                    :class="m.read ? '' : 'fu-zero'"
                  >
                    <small class="fu-cell-label">{{ TXT.read }}</small>
                    {{ m.read }}
                  </span>
                  <span
                    class="fu-cell fu-hot tabular-nums"
                    :class="m.replied ? '' : 'fu-zero'"
                  >
                    <small class="fu-cell-label">{{ TXT.replied }}</small>
                    {{ m.replied }}
                    <small v-if="m.people" class="fu-sub">{{
                      pct(m.replied, m.people)
                    }}</small>
                  </span>
                  <span
                    class="fu-cell tabular-nums"
                    :class="m.moved ? 'fu-good' : 'fu-zero'"
                  >
                    <small class="fu-cell-label">{{ TXT.moved }}</small>
                    {{ m.moved }}
                  </span>
                </button>
                <template v-if="opened[m.key]">
                  <div
                    v-for="s in m.steps"
                    :key="`${m.key}-${s.index}`"
                    class="fu-row fu-row-step"
                  >
                    <span class="fu-name fu-step-name">
                      <span class="min-w-0">
                        <b>{{ s.when }}</b>
                        <small class="fu-where">
                          <span
                            v-if="s.ai"
                            class="i-lucide-sparkles text-[11px]"
                          />
                          {{ s.text }}
                        </small>
                      </span>
                    </span>
                    <span
                      class="fu-cell tabular-nums"
                      :class="s.sent ? '' : 'fu-zero'"
                    >
                      <small class="fu-cell-label">{{ TXT.sent }}</small>
                      {{ s.sent }}
                    </span>
                    <span
                      class="fu-cell tabular-nums"
                      :class="s.read ? '' : 'fu-zero'"
                    >
                      <small class="fu-cell-label">{{ TXT.read }}</small>
                      {{ s.read }}
                    </span>
                    <span
                      class="fu-cell fu-hot tabular-nums"
                      :class="s.replied ? '' : 'fu-zero'"
                    >
                      <small class="fu-cell-label">{{ TXT.replied }}</small>
                      {{ s.replied }}
                      <small v-if="s.people" class="fu-sub">{{
                        pct(s.replied, s.people)
                      }}</small>
                    </span>
                    <span
                      class="fu-cell tabular-nums"
                      :class="s.moved ? 'fu-good' : 'fu-zero'"
                    >
                      <small class="fu-cell-label">{{ TXT.moved }}</small>
                      {{ s.moved }}
                    </span>
                  </div>
                </template>
              </template>
            </div>
            <p class="fu-legend">{{ TXT.note }}</p>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
.fu {
  container-type: inline-size;
  --fu-accent: #ea580c;
}
.fu-head {
  display: flex;
  align-items: center;
  gap: 10px 12px;
  margin-bottom: 14px;
}
.fu-ruler {
  margin: -4px 0 14px;
  max-width: 100%;
}
.fu-note {
  padding: 14px 0 4px;
  font-size: 13px;
  color: #64748b;
}
.fu-dim {
  opacity: 0.55;
}
.fu-section {
  margin-bottom: 6px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}

/* números do período */
.fu-cards {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}
@container (min-width: 520px) {
  .fu-cards {
    grid-template-columns: repeat(5, minmax(0, 1fr));
  }
}
.fu-card {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
  padding: 12px 12px 10px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  border-top: 3px solid var(--fu-accent);
  background: rgba(255, 255, 255, 0.78);
}
.fu-card-sent,
.fu-card-people {
  border-top-color: #1e293b;
}
.fu-card-moved {
  border-top-color: #16a34a;
}
.fu-label {
  font-size: 11px;
  font-weight: 700;
  line-height: 1.25;
  letter-spacing: 0.03em;
  text-transform: uppercase;
  color: #64748b;
}
.fu-count {
  font-size: 30px;
  font-weight: 800;
  line-height: 1.05;
  color: #0f172a;
}
.fu-foot {
  min-height: 18px;
  font-size: 11.5px;
  line-height: 1.3;
  color: #475569;
}
.fu-foot b {
  font-size: 14px;
  color: #c2410c;
}
.fu-card-moved .fu-foot b {
  color: #15803d;
}
.fu-failed {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  margin-top: 8px;
  padding: 5px 10px;
  border-radius: 9px;
  font-size: 12px;
  color: #b91c1c;
  background: rgba(220, 38, 38, 0.08);
  border: 1px solid rgba(220, 38, 38, 0.22);
}

/* envios por dia */
.fu-days {
  margin-top: 14px;
}
.fu-chart {
  display: flex;
  align-items: stretch;
  gap: 3px;
  height: 112px;
  padding: 10px 10px 6px;
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.24);
  background: rgba(255, 255, 255, 0.6);
  overflow-x: auto;
}
.fu-day {
  display: flex;
  flex: 1 0 18px;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  min-width: 18px;
}
.fu-day-n {
  height: 14px;
  font-size: 10px;
  font-weight: 700;
  color: #334155;
}
.fu-day-bar {
  position: relative;
  display: block;
  flex: 1;
  width: 100%;
  max-width: 26px;
}
.fu-day-fill {
  position: absolute;
  inset: auto 0 0;
  border-radius: 4px 4px 0 0;
  background: var(--fu-accent);
}
.fu-day-label {
  font-size: 9px;
  color: #64748b;
  white-space: nowrap;
}

/* por momento */
.fu-moments {
  margin-top: 14px;
}
.fu-table {
  border-radius: 12px;
  border: 1px solid rgba(100, 116, 139, 0.24);
  background: rgba(255, 255, 255, 0.6);
  overflow: hidden;
}
.fu-row {
  display: grid;
  grid-template-columns: minmax(0, 2.6fr) repeat(4, minmax(64px, 1fr));
  align-items: center;
  gap: 6px;
  width: 100%;
  padding: 10px 12px;
  font-size: 14px;
  text-align: left;
  color: #0f172a;
  border-top: 1px solid rgba(100, 116, 139, 0.16);
}
.fu-row > .fu-cell {
  text-align: right;
}
.fu-row-head {
  border-top: 0;
  padding-top: 8px;
  padding-bottom: 8px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  color: #64748b;
  background: rgba(100, 116, 139, 0.08);
}
.fu-row-head > span:not(:first-child) {
  text-align: right;
}
.fu-row-moment {
  cursor: pointer;
}
.fu-row-moment:disabled {
  cursor: default;
}
.fu-row-moment:hover:not(:disabled) {
  background: rgba(100, 116, 139, 0.06);
}
.fu-row-step {
  font-size: 13px;
  background: rgba(100, 116, 139, 0.05);
}
.fu-name {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  min-width: 0;
}
.fu-name b {
  font-size: 13.5px;
}
.fu-step-name {
  padding-left: 19px;
}
.fu-step-name b {
  font-size: 12.5px;
}
.fu-chev {
  flex: none;
  margin-top: 3px;
  color: #64748b;
}
.fu-where {
  display: block;
  margin-top: 1px;
  font-size: 11px;
  line-height: 1.35;
  color: #64748b;
  overflow-wrap: anywhere;
}
.fu-off {
  margin-left: 6px;
  padding: 1px 6px;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 600;
  color: #64748b;
  background: rgba(100, 116, 139, 0.14);
}
.fu-cell {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  font-weight: 700;
}
.fu-sub {
  font-size: 10.5px;
  font-weight: 600;
  color: #64748b;
}
.fu-hot {
  color: #c2410c;
}
.fu-good {
  color: #15803d;
}
.fu-zero {
  color: #94a3b8;
}
.fu-cell-label {
  display: none;
}
.fu-legend {
  margin-top: 8px;
  font-size: 11px;
  line-height: 1.4;
  color: #64748b;
}

/* celular: cada momento vira um bloco (nome em cima, 4 números embaixo) */
@container (max-width: 520px) {
  .fu-row-head {
    display: none;
  }
  .fu-row {
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 6px 4px;
    padding: 10px;
  }
  .fu-row > .fu-name {
    grid-column: 1 / -1;
  }
  .fu-row > .fu-cell {
    align-items: center;
    text-align: center;
  }
  .fu-cell-label {
    display: flex;
    align-items: flex-end;
    justify-content: center;
    min-height: 22px;
    font-size: 8.5px;
    font-weight: 600;
    text-transform: uppercase;
    color: #64748b;
  }
  .fu-step-name {
    padding-left: 0;
  }
  .fu-row > .fu-cell {
    justify-content: flex-start;
  }
  .fu-card-moved {
    grid-column: 1 / -1;
  }
  .fu-count {
    font-size: 26px;
  }
}

/* tema escuro */
:global(.dark .fu-note),
:global(.dark .fu-label),
:global(.dark .fu-section),
:global(.dark .fu-row-head),
:global(.dark .fu-legend),
:global(.dark .fu-where),
:global(.dark .fu-sub),
:global(.dark .fu-day-label),
:global(.dark .fu-chev) {
  color: rgba(255, 255, 255, 0.62);
}
:global(.dark .fu-card) {
  background: rgba(255, 255, 255, 0.045);
  border-color: rgba(255, 255, 255, 0.12);
  border-top-color: var(--fu-accent);
}
:global(.dark .fu-card-sent),
:global(.dark .fu-card-people) {
  border-top-color: #e2e8f0;
}
:global(.dark .fu-card-moved) {
  border-top-color: #22c55e;
}
:global(.dark .fu-count),
:global(.dark .fu-row),
:global(.dark .fu-day-n) {
  color: #fff;
}
:global(.dark .fu-foot) {
  color: rgba(255, 255, 255, 0.78);
}
:global(.dark .fu-foot b),
:global(.dark .fu-hot) {
  color: #fdba74;
}
:global(.dark .fu-card-moved .fu-foot b),
:global(.dark .fu-good) {
  color: #86efac;
}
:global(.dark .fu-table),
:global(.dark .fu-chart) {
  background: rgba(255, 255, 255, 0.03);
  border-color: rgba(255, 255, 255, 0.12);
}
:global(.dark .fu-row) {
  border-top-color: rgba(255, 255, 255, 0.08);
}
:global(.dark .fu-row-head) {
  background: rgba(255, 255, 255, 0.05);
}
:global(.dark .fu-row-step) {
  background: rgba(255, 255, 255, 0.025);
}
:global(.dark .fu-row-moment:hover:not(:disabled)) {
  background: rgba(255, 255, 255, 0.05);
}
:global(.dark .fu-off) {
  color: rgba(255, 255, 255, 0.7);
  background: rgba(255, 255, 255, 0.1);
}
:global(.dark .fu-zero) {
  color: rgba(255, 255, 255, 0.35);
}
:global(.dark .fu-failed) {
  color: #fca5a5;
  background: rgba(220, 38, 38, 0.14);
  border-color: rgba(248, 113, 113, 0.3);
}
:global(.dark .fu-cell-label) {
  color: rgba(255, 255, 255, 0.55) !important;
}
</style>
