<script setup>
// 🌡️ 11/11/2026 (LIFE, pedido do Guilherme): as TAREFAS do Meu Painel para quem
// vende — maiores e mais claras. Cada cartão diz QUEM é o cliente, O QUE
// precisa ser feito, ATÉ QUANDO (selo verde/amarelo/vermelho), em que ETAPA do
// funil está, o VALOR do orçamento quando houver e a TEMPERATURA, que põe a
// lista em ordem de prioridade (regra em app/services/crm/task_priority.rb).
// Cartões retos de vidro, sem emoji, nada cortado com reticências; no celular
// tudo empilha e os botões ficam do tamanho do dedo.
import { computed, ref, onMounted, onUnmounted } from 'vue';
import { stageDeadline } from 'dashboard/helper/taskDue';
import {
  HEAT_RULE,
  HEAT_LEVELS,
  heatMeta,
  heatBreakdown,
  heatCounts,
  filterTasks,
  clientLine,
  splitTaskTitle,
  moneyBR,
} from 'dashboard/helper/taskPriority';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { openPatientChat } from 'dashboard/composables/useCevicoPatientChat';
import ClientSummaryLines from 'dashboard/components-next/cevico/ClientSummaryLines.vue';
import { useCevicoProposal } from 'dashboard/composables/useCevicoProposal';

const props = defineProps({
  tasks: { type: Array, default: () => [] },
  // quantas tarefas a pessoa tem ao todo (a lista traz até 40)
  total: { type: Number, default: 0 },
});
const emit = defineEmits(['openTask', 'openSpace']);

// 📄 botão "Gerar proposta": abre o gerador já neste cliente
const { canMakeProposal, openProposal, proposalLabel, proposalTitle } =
  useCevicoProposal();

const { spaceName, openSpaceLabel, canView } = useCevicoAccess();
// o botão da Central do cliente só aparece para quem pode abri-la (na triagem
// do administrador ela pode estar fechada: o clique voltaria para o início)
const canOpenSpace = computed(() => canView('pacientes'));

// o relógio anda sozinho: os selos ("atrasou 2 horas") não ficam velhos
const now = ref(new Date());
let clock = null;
onMounted(() => {
  clock = setInterval(() => {
    now.value = new Date();
  }, 60 * 1000);
});
onUnmounted(() => clearInterval(clock));

const FIRST_PAGE = 8;
const filter = ref('todas');
const expanded = ref(false);
const showRule = ref(false);
const whyOpen = ref(null);

const counts = computed(() => heatCounts(props.tasks, now.value));
const FILTERS = [
  { key: 'todas', label: 'Todas', icon: 'i-lucide-list-checks' },
  { key: 'quentes', label: 'Quentes', icon: 'i-lucide-flame' },
  { key: 'atrasadas', label: 'Atrasadas', icon: 'i-lucide-alarm-clock' },
];
const pickFilter = key => {
  filter.value = key;
  expanded.value = false;
};

const rows = computed(() =>
  filterTasks(props.tasks, filter.value, now.value).map((task, index) => {
    const { who, what } = splitTaskTitle(task.title, task.contact?.name);
    return {
      task,
      rank: index + 1,
      who,
      what,
      heat: heatMeta(task),
      level: task.heat?.level || 'fria',
      points: task.heat?.points ?? 0,
      due: stageDeadline(task.due_at, now.value),
      dueFull: task.due_at
        ? new Date(task.due_at).toLocaleString('pt-BR', {
            weekday: 'short',
            day: '2-digit',
            month: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
          })
        : null,
      stage: task.card?.stage || null,
      value: moneyBR(task.card?.value),
      client: clientLine(task, now.value),
      why: heatBreakdown(task),
    };
  })
);
const visible = computed(() =>
  expanded.value ? rows.value : rows.value.slice(0, FIRST_PAGE)
);
const hiddenCount = computed(() => rows.value.length - visible.value.length);

const CLIENT_ICON = {
  wait: 'i-lucide-message-circle-warning',
  talk: 'i-lucide-message-circle',
  quiet: 'i-lucide-moon',
  none: 'i-lucide-message-circle-off',
};
const EMPTY_TEXT = {
  todas: 'Nada esperando você agora.',
  quentes: 'Nenhuma tarefa quente agora.',
  atrasadas: 'Nenhuma tarefa atrasada. Tudo em dia.',
};

// os textos fixos da tela, num lugar só
const TXT = {
  filters: 'Filtrar as tarefas',
  how: 'Como a temperatura funciona',
  ruleLead:
    'A temperatura é uma soma de pontos, de 0 a 10, só com o que o sistema já sabe. A lista fica em ordem: mais pontos em cima.',
  ruleFoot:
    'Empate: primeiro o maior valor de orçamento, depois o prazo mais antigo.',
  openTask: 'Abrir a tarefa',
  noDue: 'sem prazo',
  chat: 'Conversa',
  chatTitle: 'Abrir a conversa do WhatsApp aqui mesmo',
  whyTitle: 'Ver de onde vêm os pontos desta tarefa',
  noSignal:
    'Nenhum sinal por enquanto: sem mensagem recente do cliente, sem etapa avançada e com prazo folgado.',
};
const pointsText = n => `${n} ${n === 1 ? 'ponto' : 'pontos'}`;
const moreText = n => `Ver mais ${n} ${n === 1 ? 'tarefa' : 'tarefas'}`;
const cutText = (shown, total) =>
  `Aqui estão as ${shown} mais importantes de ${total}. As outras estão em Tarefas.`;

const toggleWhy = id => {
  whyOpen.value = whyOpen.value === id ? null : id;
};
const openChat = task => openPatientChat({ contactId: task.contact?.id });
</script>

<template>
  <div class="tp">
    <div class="tp-bar">
      <div class="tp-filters" role="group" :aria-label="TXT.filters">
        <button
          v-for="f in FILTERS"
          :key="f.key"
          class="tp-filter"
          :class="filter === f.key ? 'tp-filter-on' : ''"
          :aria-pressed="filter === f.key"
          @click="pickFilter(f.key)"
        >
          <span class="tp-filter-icon text-[13px]" :class="f.icon" />
          {{ f.label }}
          <b class="tabular-nums">{{ counts[f.key] }}</b>
        </button>
      </div>
      <button
        class="tp-how"
        :aria-expanded="showRule"
        @click="showRule = !showRule"
      >
        <span class="i-lucide-thermometer text-[13px]" />
        {{ TXT.how }}
        <span
          class="text-[12px]"
          :class="showRule ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>
    </div>

    <!-- a regra, à mostra para quem quiser conferir -->
    <div v-if="showRule" class="tp-rule">
      <p class="tp-rule-lead">
        {{ TXT.ruleLead }}
      </p>
      <div class="tp-rule-grid">
        <div v-for="r in HEAT_RULE" :key="r.key" class="tp-rule-item">
          <b>{{ r.title }}</b>
          <span>{{ r.detail }}</span>
        </div>
      </div>
      <div class="tp-rule-levels">
        <span
          v-for="(lvl, key) in HEAT_LEVELS"
          :key="key"
          class="tp-heat"
          :class="`tp-heat-${key}`"
        >
          <span class="text-[13px]" :class="lvl.icon" />
          {{ lvl.label }}
          <span class="tp-heat-range">{{ `${lvl.range} · ${lvl.hint}` }}</span>
        </span>
      </div>
      <p class="tp-rule-foot">
        {{ TXT.ruleFoot }}
      </p>
    </div>

    <p v-if="!rows.length" class="tp-empty">{{ EMPTY_TEXT[filter] }}</p>

    <ol v-else class="tp-list">
      <li
        v-for="row in visible"
        :key="row.task.id"
        class="tp-card"
        :class="`tp-card-${row.level}`"
      >
        <div class="tp-row">
          <div
            class="tp-main"
            role="button"
            tabindex="0"
            :title="TXT.openTask"
            @click="emit('openTask', row.task)"
            @keydown.enter="emit('openTask', row.task)"
          >
            <span class="tp-rank tabular-nums">{{ row.rank }}</span>
            <div class="tp-body">
              <div class="tp-top">
                <span class="tp-heat" :class="`tp-heat-${row.level}`">
                  <span class="text-[13px]" :class="row.heat.icon" />
                  {{ row.heat.label }}
                </span>
                <span
                  v-if="row.due"
                  class="tp-due"
                  :class="`tp-due-${row.due.tone}`"
                  :title="row.dueFull"
                >
                  <span class="i-lucide-alarm-clock text-[13px]" />
                  {{ row.due.text }}
                </span>
                <span v-else class="tp-due tp-due-none">{{ TXT.noDue }}</span>
              </div>

              <h3 class="tp-who">{{ row.who || row.what }}</h3>
              <p v-if="row.who" class="tp-what">{{ row.what }}</p>
              <ClientSummaryLines
                v-if="row.task.summary?.length"
                class="tp-summary"
                :lines="row.task.summary"
              />

              <div class="tp-meta">
                <span v-if="row.stage" class="tp-chip">
                  <span
                    class="tp-dot"
                    :style="{ background: row.stage.color || '#64748b' }"
                  />
                  {{ row.stage.name }}
                </span>
                <span v-if="row.value" class="tp-chip tp-chip-value">
                  <span class="i-lucide-banknote text-[13px]" />
                  {{ row.value }}
                </span>
                <span
                  v-if="row.client"
                  class="tp-client"
                  :class="`tp-client-${row.client.tone}`"
                >
                  <span
                    class="text-[13px]"
                    :class="CLIENT_ICON[row.client.tone]"
                  />
                  {{ row.client.text }}
                </span>
              </div>
            </div>
          </div>

          <div class="tp-actions">
            <button
              v-if="row.task.contact"
              class="tp-btn"
              :title="TXT.chatTitle"
              @click="openChat(row.task)"
            >
              <span class="i-lucide-message-circle text-[14px]" />
              {{ TXT.chat }}
            </button>
            <button
              v-if="row.task.contact && canOpenSpace"
              class="tp-btn"
              :title="openSpaceLabel"
              @click="emit('openSpace', row.task.contact.id)"
            >
              <span class="i-lucide-user-round text-[14px]" />
              {{ spaceName }}
            </button>
            <!-- 📄 Gerar proposta: abre o gerador (Cotador) já neste cliente -->
            <button
              v-if="row.task.contact && canMakeProposal"
              class="tp-btn tp-btn-main"
              :title="proposalTitle"
              @click="openProposal(row.task.contact.id)"
            >
              <span class="i-lucide-file-text text-[14px]" />
              {{ proposalLabel }}
            </button>
            <button
              class="tp-btn tp-btn-ghost"
              :aria-expanded="whyOpen === row.task.id"
              :title="TXT.whyTitle"
              @click="toggleWhy(row.task.id)"
            >
              <span class="i-lucide-thermometer text-[14px]" />
              {{ pointsText(row.points) }}
            </button>
          </div>
        </div>

        <div v-if="whyOpen === row.task.id" class="tp-why">
          <template v-if="row.why.length">
            <span v-for="part in row.why" :key="part.key" class="tp-why-part">
              {{ part.title }} <b>{{ `+${part.points}` }}</b>
            </span>
          </template>
          <span v-else class="tp-why-part">
            {{ TXT.noSignal }}
          </span>
        </div>
      </li>
    </ol>

    <button v-if="hiddenCount > 0" class="tp-more" @click="expanded = true">
      <span class="i-lucide-chevron-down text-[14px]" />
      {{ moreText(hiddenCount) }}
    </button>
    <p v-if="total > tasks.length" class="tp-note">
      {{ cutText(tasks.length, total) }}
    </p>
  </div>
</template>

<style scoped>
.tp {
  /* o desenho segue a largura do BLOCO (ele pode estar em meia largura), não a da tela */
  container-type: inline-size;
  --tp-hot: #ea580c;
  --tp-warm: #f59e0b;
  --tp-cold: #94a3b8;
}
.tp-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 8px 12px;
  margin-bottom: 12px;
}
.tp-filters {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.tp-filter {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 32px;
  padding: 0 12px;
  border-radius: 9px;
  font-size: 12.5px;
  font-weight: 600;
  color: #475569;
  background: rgba(100, 116, 139, 0.1);
  border: 1px solid rgba(100, 116, 139, 0.22);
  transition: background 0.15s ease;
}
.tp-filter:hover {
  background: rgba(100, 116, 139, 0.18);
}
.tp-filter-on,
.tp-filter-on:hover {
  color: #fff;
  background: #1e293b;
  border-color: #1e293b;
}
:global(.dark .tp-filter) {
  color: rgba(255, 255, 255, 0.8);
  background: rgba(255, 255, 255, 0.07);
  border-color: rgba(255, 255, 255, 0.14);
}
:global(.dark .tp-filter-on),
:global(.dark .tp-filter-on:hover) {
  color: #0f172a;
  background: #fff;
  border-color: #fff;
}
.tp-how {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 32px;
  padding: 0 4px;
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--cv-deep-rgb, 51 65 85));
}
.tp-how:hover {
  text-decoration: underline;
}
:global(.dark .tp-how) {
  color: rgba(255, 255, 255, 0.85);
}

/* ── a regra ── */
.tp-rule {
  margin-bottom: 14px;
  padding: 16px;
  border-radius: 14px;
  border: 1px solid rgba(100, 116, 139, 0.28);
  background: rgba(255, 255, 255, 0.72);
}
:global(.dark .tp-rule) {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.14);
}
.tp-rule-lead,
.tp-rule-foot {
  font-size: 13px;
  line-height: 1.45;
  color: #475569;
}
.tp-rule-foot {
  margin-top: 12px;
}
.tp-rule-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
  margin: 12px 0;
}
@container (min-width: 620px) {
  .tp-rule-grid {
    grid-template-columns: 1fr 1fr;
  }
}
.tp-rule-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding-left: 10px;
  border-left: 3px solid var(--tp-hot);
  font-size: 13px;
  line-height: 1.4;
}
.tp-rule-item b {
  color: #0f172a;
}
.tp-rule-item span {
  color: #475569;
}
.tp-rule-levels {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.tp-heat-range {
  font-weight: 500;
  opacity: 0.85;
}
:global(.dark .tp-rule-lead),
:global(.dark .tp-rule-foot),
:global(.dark .tp-rule-item span) {
  color: rgba(255, 255, 255, 0.72);
}
:global(.dark .tp-rule-item b) {
  color: #fff;
}

/* ── a lista ── */
.tp-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.tp-card {
  position: relative;
  border-radius: 14px;
  border: 1px solid rgba(100, 116, 139, 0.26);
  border-left: 5px solid var(--tp-cold);
  background: rgba(255, 255, 255, 0.78);
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.05);
  transition:
    border-color 0.15s ease,
    box-shadow 0.15s ease;
}
.tp-card:hover {
  box-shadow: 0 8px 20px -12px rgba(15, 23, 42, 0.35);
}
.tp-card-quente {
  border-left-color: var(--tp-hot);
}
.tp-card-morna {
  border-left-color: var(--tp-warm);
}
:global(.dark .tp-card) {
  background: rgba(255, 255, 255, 0.045);
  border-color: rgba(255, 255, 255, 0.12);
  border-left-color: var(--tp-cold);
  box-shadow: none;
}
:global(.dark .tp-card-quente) {
  border-left-color: var(--tp-hot);
}
:global(.dark .tp-card-morna) {
  border-left-color: var(--tp-warm);
}

.tp-main {
  display: flex;
  gap: 12px;
  padding: 14px 16px 10px 14px;
  cursor: pointer;
  border-radius: 12px;
  outline: none;
}
.tp-main:focus-visible {
  box-shadow: 0 0 0 2px var(--tp-hot);
}
.tp-rank {
  flex-shrink: 0;
  width: 26px;
  height: 26px;
  margin-top: 1px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 700;
  color: #475569;
  background: rgba(100, 116, 139, 0.14);
}
:global(.dark .tp-rank) {
  color: rgba(255, 255, 255, 0.85);
  background: rgba(255, 255, 255, 0.1);
}
.tp-body {
  min-width: 0;
  flex: 1;
}
.tp-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 6px 8px;
  margin-bottom: 8px;
}

/* temperatura: quente cheio, morna clara, fria apagada */
.tp-heat {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 26px;
  padding: 3px 10px;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 700;
  line-height: 1.2;
  border: 1px solid transparent;
}
.tp-heat-quente {
  color: #fff;
  background: var(--tp-hot);
}
.tp-heat-morna {
  color: #92400e;
  background: rgba(245, 158, 11, 0.16);
  border-color: rgba(245, 158, 11, 0.45);
}
.tp-heat-fria {
  color: #475569;
  background: rgba(100, 116, 139, 0.12);
  border-color: rgba(100, 116, 139, 0.3);
}
:global(.dark .tp-heat-morna) {
  color: #fcd34d;
  background: rgba(245, 158, 11, 0.2);
}
:global(.dark .tp-heat-fria) {
  color: #cbd5e1;
  background: rgba(148, 163, 184, 0.16);
}

/* selo do prazo: as mesmas três cores do cartão do funil */
.tp-due {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 26px;
  padding: 3px 10px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 700;
  line-height: 1.2;
  border: 1px solid transparent;
}
.tp-due-later {
  color: #166534;
  background: rgba(34, 197, 94, 0.12);
  border-color: rgba(34, 197, 94, 0.32);
}
.tp-due-soon {
  color: #92400e;
  background: rgba(245, 158, 11, 0.14);
  border-color: rgba(245, 158, 11, 0.4);
}
.tp-due-late {
  color: #b91c1c;
  background: rgba(239, 68, 68, 0.12);
  border-color: rgba(239, 68, 68, 0.4);
}
.tp-due-none {
  color: #64748b;
  font-weight: 500;
  border-color: rgba(100, 116, 139, 0.3);
}
:global(.dark .tp-due-later) {
  color: #86efac;
  background: rgba(34, 197, 94, 0.18);
}
:global(.dark .tp-due-soon) {
  color: #fcd34d;
  background: rgba(245, 158, 11, 0.2);
}
:global(.dark .tp-due-late) {
  color: #fca5a5;
  background: rgba(239, 68, 68, 0.2);
}
:global(.dark .tp-due-none) {
  color: #cbd5e1;
}

.tp-who {
  margin: 0;
  font-size: 17px;
  font-weight: 700;
  line-height: 1.25;
  color: #0f172a;
  overflow-wrap: anywhere;
}
.tp-what {
  margin: 2px 0 0;
  font-size: 14px;
  line-height: 1.4;
  color: #334155;
  overflow-wrap: anywhere;
}
:global(.dark .tp-who) {
  color: #fff;
}
:global(.dark .tp-what) {
  color: rgba(255, 255, 255, 0.8);
}

.tp-summary {
  margin-top: 8px;
}
.tp-meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px 8px;
  margin-top: 10px;
}
.tp-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 26px;
  padding: 3px 10px;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.2;
  color: #334155;
  background: rgba(100, 116, 139, 0.1);
  border: 1px solid rgba(100, 116, 139, 0.22);
}
.tp-chip-value {
  color: #0f172a;
  font-variant-numeric: tabular-nums;
}
.tp-dot {
  width: 8px;
  height: 8px;
  border-radius: 9999px;
  flex-shrink: 0;
}
.tp-client {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12.5px;
  font-weight: 500;
  line-height: 1.3;
  color: #475569;
}
.tp-client-wait {
  color: #c2410c;
  font-weight: 700;
}
:global(.dark .tp-chip) {
  color: rgba(255, 255, 255, 0.88);
  background: rgba(255, 255, 255, 0.07);
  border-color: rgba(255, 255, 255, 0.14);
}
:global(.dark .tp-chip-value) {
  color: #fff;
}
:global(.dark .tp-client) {
  color: rgba(255, 255, 255, 0.72);
}
:global(.dark .tp-client-wait) {
  color: #fdba74;
}

/* ── ações ── */
.tp-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 0 16px 12px 52px;
}
.tp-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 34px;
  padding: 0 12px;
  border-radius: 9px;
  font-size: 12.5px;
  font-weight: 600;
  color: #0f172a;
  background: rgba(255, 255, 255, 0.9);
  border: 1px solid rgba(100, 116, 139, 0.34);
  transition: background 0.15s ease;
}
.tp-btn:hover {
  background: rgba(100, 116, 139, 0.12);
}
.tp-btn-main,
.tp-btn-main:hover {
  color: #fff;
  background: #ea580c;
  border-color: #ea580c;
}
.tp-btn-ghost {
  color: #475569;
  background: transparent;
  border-style: dashed;
}
:global(.dark .tp-btn) {
  color: #fff;
  background: rgba(255, 255, 255, 0.07);
  border-color: rgba(255, 255, 255, 0.18);
}
:global(.dark .tp-btn:hover) {
  background: rgba(255, 255, 255, 0.14);
}
:global(.dark .tp-btn-ghost) {
  color: rgba(255, 255, 255, 0.75);
  background: transparent;
}

.tp-why {
  display: flex;
  flex-wrap: wrap;
  gap: 6px 14px;
  margin: 0 16px 12px 52px;
  padding: 10px 12px;
  border-radius: 10px;
  font-size: 12.5px;
  line-height: 1.4;
  color: #475569;
  background: rgba(100, 116, 139, 0.08);
}
.tp-why-part b {
  color: #c2410c;
}
:global(.dark .tp-why) {
  color: rgba(255, 255, 255, 0.78);
  background: rgba(255, 255, 255, 0.06);
}
:global(.dark .tp-why-part b) {
  color: #fdba74;
}

.tp-more {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  width: 100%;
  min-height: 40px;
  margin-top: 10px;
  border-radius: 12px;
  font-size: 13px;
  font-weight: 600;
  color: #334155;
  border: 1px dashed rgba(100, 116, 139, 0.4);
}
.tp-more:hover {
  background: rgba(100, 116, 139, 0.08);
}
:global(.dark .tp-more) {
  color: rgba(255, 255, 255, 0.85);
  border-color: rgba(255, 255, 255, 0.2);
}
.tp-empty,
.tp-note {
  font-size: 13px;
  color: #64748b;
}
.tp-empty {
  padding: 22px 0;
  text-align: center;
}
.tp-note {
  margin-top: 10px;
  text-align: right;
}

/* notebook: as ações sobem para o canto do cartão, na linha da etapa e do valor */
.tp-row {
  position: relative;
}
@container (min-width: 900px) {
  .tp-main {
    padding-bottom: 14px;
  }
  .tp-meta {
    min-height: 34px;
    padding-right: 530px;
  }
  .tp-actions {
    position: absolute;
    right: 16px;
    bottom: 14px;
    padding: 0;
    flex-wrap: nowrap;
  }
  .tp-why {
    margin-top: -2px;
  }
}

/* celular: ações alinhadas com a borda e botões do tamanho do dedo */
@container (max-width: 560px) {
  .tp-main {
    gap: 10px;
    padding: 12px 12px 8px 10px;
  }
  .tp-actions {
    padding: 0 12px 12px 12px;
  }
  .tp-why {
    margin: 0 12px 12px 12px;
  }
  .tp-btn {
    flex: 1 1 auto;
    justify-content: center;
    min-height: 40px;
  }
  .tp-btn-ghost {
    flex: 0 0 auto;
  }
  .tp-how,
  .tp-filter {
    min-height: 36px;
  }
  .tp-filter {
    padding: 0 10px;
  }
  .tp-filter-icon {
    display: none;
  }
}
</style>
