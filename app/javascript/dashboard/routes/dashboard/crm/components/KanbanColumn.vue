<script setup>
import { ref, computed, watch } from 'vue';
import { useWindowSize } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import draggable from 'vuedraggable';
import ContactCard from './ContactCard.vue';
import StageEditModal from './StageEditModal.vue';
import ColumnAutomationsModal from './ColumnAutomationsModal.vue';
import FollowupBotModal from './FollowupBotModal.vue';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  stage:           { type: Object, required: true },
  contacts:        { type: Array, default: () => [] },
  pipelineId:      { type: Number, required: true },
  editMode:        { type: Boolean, default: false },
  programmingMode: { type: Boolean, default: false },
  allStages:       { type: Array, default: () => [] },
  // preset de visualização: coluna fora do preset fica oculta
  // (v-show externo não funciona em componente multi-root)
  hidden:          { type: Boolean, default: false },
  // contagem/soma VERDADEIRAS da coluna no período (servidor) — null quando
  // um filtro local está em jogo (aí vale o nº de cards visíveis)
  totalCount:      { type: Number, default: null },
  totalValue:      { type: Number, default: null },
  loadingMore:     { type: Boolean, default: false },
});

const emit = defineEmits(['cardClick', 'stageDrop', 'addContact', 'openChat', 'loadMore']);

const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

// No celular o arrasto briga com o deslize entre colunas (pedido 24/07:
// "no mobile não quero mover os cards arrastando, quero navegar") — abaixo
// de md (768px, mesmo corte do navegador de colunas) o drag fica desligado.
const { width: windowWidth } = useWindowSize();
const isMobile = computed(() => windowWidth.value < 768);

// ── Agentes de IA nas automações: card destacado + edição rápida dali ──
const AI_AGENT_ACTIONS = {
  ai_analyze: { key: 'conversation', title: 'Analista de Conversas', grad: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' },
  schedule_appointment: { key: 'scheduler', title: 'Secretário da Agenda', grad: 'linear-gradient(135deg, #B8860B, #D4A017)' },
  closing_extract: { key: 'closing', title: 'Monitor de Fechamento', grad: 'linear-gradient(135deg, #065F46, #10B981)' },
  nps_score: { key: 'nps', title: 'Agente de NPS', grad: 'linear-gradient(135deg, #0D9488, #2DD4BF)' },
};
const agentOf = auto => AI_AGENT_ACTIONS[auto.action_type] || null;
const agentEnabled = auto => {
  const meta = agentOf(auto);
  if (!meta) return false;
  return store.getters['crm/getSettings']?.ai?.agents?.[meta.key]?.enabled === true;
};

const showAgentModal = ref(false);
const agentModal = ref(null); // { key, title, grad }
const agentForm = ref({ enabled: false, prompt: '', model: '', default_prompt: '' });
const isSavingAgent = ref(false);
const openAgentModal = async auto => {
  const meta = agentOf(auto);
  if (!meta) return;
  agentModal.value = meta;
  await store.dispatch('crm/fetchSettings').catch(() => {});
  const a = store.getters['crm/getSettings']?.ai?.agents?.[meta.key] || {};
  agentForm.value = {
    enabled: a.enabled === true,
    prompt: a.prompt || '',
    model: a.model || '',
    default_prompt: a.default_prompt || '',
  };
  showAgentModal.value = true;
};
const saveAgentModal = async () => {
  if (isSavingAgent.value) return;
  isSavingAgent.value = true;
  try {
    await CrmAPI.updateAi({
      agents: {
        [agentModal.value.key]: {
          enabled: agentForm.value.enabled,
          prompt: agentForm.value.prompt,
          model: agentForm.value.model,
        },
      },
    });
    await store.dispatch('crm/fetchSettings').catch(() => {});
    showAgentModal.value = false;
    useAlert(`${agentModal.value.title} atualizado — vale a partir das próximas análises.`);
  } catch {
    useAlert('Erro ao salvar o agente.');
  } finally {
    isSavingAgent.value = false;
  }
};

// ── Modals ────────────────────────────────────────────────────────
const showEditModal         = ref(false);
const showAutomationForm    = ref(false);
const editingAutomation     = ref(null);  // null = create, object = edit

// ── Robôs de follow-up desta coluna ───────────────────────────────
const followupBots      = ref([]);
const showBotModal      = ref(false);
const editingBot        = ref(null);
const deleteBotConfirmId = ref(null);

const loadFollowupBots = async () => {
  if (!isAdmin.value) return;
  try {
    followupBots.value = await store.dispatch('crm/fetchFollowupBots', { stage_id: props.stage.id });
  } catch {
    followupBots.value = [];
  }
};

const openCreateBot = () => { editingBot.value = null; showBotModal.value = true; };
const openEditBot = bot => { editingBot.value = bot; showBotModal.value = true; };
const onBotSaved = async () => { showBotModal.value = false; editingBot.value = null; await loadFollowupBots(); };

const toggleBot = async bot => {
  try {
    await store.dispatch('crm/updateFollowupBot', { id: bot.id, active: !bot.active });
    bot.active = !bot.active;
  } catch { useAlert(t('CRM.ERROR.GENERIC')); }
};

const deleteBot = async bot => {
  try {
    await store.dispatch('crm/deleteFollowupBot', bot.id);
    followupBots.value = followupBots.value.filter(b => b.id !== bot.id);
    deleteBotConfirmId.value = null;
  } catch { useAlert(t('CRM.ERROR.GENERIC')); }
};

// unidade correta por etapa: minutos ÷ 60, dias × 24 (igual ao backend)
const botDelayLabel = step => {
  let hours;
  if (step.delay_value != null) {
    const v = Number(step.delay_value);
    if (step.delay_unit === 'days') hours = v * 24;
    else if (step.delay_unit === 'minutes') hours = v / 60;
    else hours = v;
  } else {
    hours = Number(step.delay_hours);
  }
  if (hours < 1) return `${Math.round(hours * 60)}min`;
  if (hours < 24) return `${Math.round(hours * 10) / 10}h`;
  return `${Math.round(hours / 24)}d`;
};

// ── Delete flow ───────────────────────────────────────────────────
const showDeleteConfirm = ref(false);
const moveToStageId     = ref('');
const isDeleting        = ref(false);

// ── Automations (loaded when programming mode is ON) ──────────────
const automations         = ref([]);
const isLoadingAutomations = ref(false);
const deleteConfirmAutoId  = ref(null);

const TRIGGER_ICONS = {
  card_entered:    'i-lucide-log-in',
  card_left:       'i-lucide-log-out',
  card_stalled:    'i-lucide-clock',
  label_added:     'i-lucide-tag',
  label_removed:   'i-lucide-tag',
  message_created: 'i-lucide-message-circle',
  value_added:     'i-lucide-circle-dollar-sign',
};

const TRIGGER_LABELS = {
  card_entered:    'Entrou na coluna',
  card_left:       'Saiu da coluna',
  card_stalled:    'Parado por X tempo',
  label_added:     'Etiqueta adicionada',
  label_removed:   'Etiqueta removida',
  message_created: 'Mensagem criada',
  value_added:     'Valor adicionado',
};

const ACTION_ICONS = {
  webhook:          'i-lucide-globe',
  n8n_flow:         'i-lucide-workflow',
  apply_label:      'i-lucide-tag',
  move_card:        'i-lucide-arrow-right-circle',
  log_timeline:     'i-lucide-clock',
  notify_team:      'i-lucide-bell',
  template_message: 'i-lucide-megaphone',
  meta_ads_event:   'i-lucide-megaphone',
  google_ads_conversion: 'i-lucide-megaphone',
  send_form:        'i-lucide-clipboard-list',
  ai_analyze:       'i-lucide-sparkles',
  schedule_appointment: 'i-lucide-calendar-plus',
  set_value:        'i-lucide-circle-dollar-sign',
};

const ACTION_LABELS = {
  webhook:          'Webhook',
  n8n_flow:         'n8n',
  apply_label:      'Etiqueta',
  move_card:        'Mover card',
  log_timeline:     'Timeline',
  notify_team:      'Notificar',
  template_message: 'Mensagem Meta',
  meta_ads_event:   'Evento Meta',
  google_ads_conversion: 'Conversão Google',
  send_form:        'Enviar formulário',
  ai_analyze:       'IA: Analista',
  schedule_appointment: 'IA: Secretário da Agenda',
  set_value:        'Preço no card',
};

const loadAutomations = async () => {
  isLoadingAutomations.value = true;
  try {
    const list = await store.dispatch('crm/fetchAutomations', {
      pipelineId: props.pipelineId,
      stageId:    props.stage.id,
    });
    automations.value = list || [];
  } finally {
    isLoadingAutomations.value = false;
  }
};

watch(() => props.programmingMode, (on) => {
  if (on) { loadAutomations(); loadFollowupBots(); }
  else { automations.value = []; followupBots.value = []; }
}, { immediate: true });

// ── Kanban helpers ────────────────────────────────────────────────
const otherStages = computed(() =>
  props.allStages.filter(s => s.id !== props.stage.id)
);

const hasCards = computed(() => props.contacts.length > 0);

const localContacts = computed({
  get: () => props.contacts,
  set: (val) => emit('stageDrop', { stageId: props.stage.id, contacts: val }),
});

// soma local dos cards carregados; a prop totalValue (servidor) vence quando
// existe — com paginação por coluna, a soma local seria só uma fatia
const localValue = computed(() =>
  props.contacts.reduce((sum, c) => sum + (Number(c.value) || 0), 0)
);
const totalValue = computed(() =>
  props.totalValue !== null ? props.totalValue : localValue.value
);

// contagem do cabeçalho: total REAL do período (servidor) quando disponível
const headerCount = computed(() =>
  props.totalCount !== null ? props.totalCount : props.contacts.length
);

// tem mais cards no servidor do que os carregados?
const hasMoreCards = computed(() =>
  props.totalCount !== null && props.totalCount > props.contacts.length
);

const confirmDelete = () => {
  moveToStageId.value = otherStages.value[0]?.id ?? '';
  showDeleteConfirm.value = true;
};

const cancelDelete = () => {
  showDeleteConfirm.value = false;
  moveToStageId.value = '';
};

const deleteStage = async () => {
  isDeleting.value = true;
  try {
    if (hasCards.value && moveToStageId.value) {
      for (const contact of props.contacts) {
        await store.dispatch('crm/moveContact', {
          pipelineId: props.pipelineId,
          id: contact.id,
          stageId: Number(moveToStageId.value),
        });
      }
    }
    await store.dispatch('crm/deleteStage', {
      pipelineId: props.pipelineId,
      stageId: props.stage.id,
    });
    useAlert(t('CRM.SUCCESS.STAGE_DELETED'));
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isDeleting.value = false;
    showDeleteConfirm.value = false;
  }
};

// ── Automation actions ─────────────────────────────────────────────
const openCreateAutomation = () => {
  editingAutomation.value = null;
  showAutomationForm.value = true;
};

const openEditAutomation = (auto) => {
  // réguas de mensagem são gerenciadas na central Campanha WhatsApp
  if (auto.kind === 'message_automation') return;
  editingAutomation.value = auto;
  showAutomationForm.value = true;
};

const onAutomationSaved = async () => {
  showAutomationForm.value = false;
  editingAutomation.value = null;
  await loadAutomations();
};

const toggleAutomationActive = async (auto) => {
  try {
    if (auto.kind === 'message_automation') {
      await store.dispatch('crm/updateMessageAutomation', {
        id: auto.id,
        active: !auto.active,
      });
    } else {
      await store.dispatch('crm/updateAutomation', {
        pipelineId:    props.pipelineId,
        stageId:       props.stage.id,
        id:            auto.id,
        name:          auto.name,
        trigger_type:  auto.trigger_type,
        delay_minutes: auto.delay_minutes,
        action_type:   auto.action_type,
        action_config: auto.action_config,
        active:        !auto.active,
      });
    }
    await loadAutomations();
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const deleteAutomation = async (auto) => {
  try {
    if (auto.kind === 'message_automation') {
      await store.dispatch('crm/deleteMessageAutomation', auto.id);
    } else {
      await store.dispatch('crm/deleteAutomation', {
        pipelineId: props.pipelineId,
        stageId:    props.stage.id,
        id: auto.id,
      });
    }
    deleteConfirmAutoId.value = null;
    await loadAutomations();
    useAlert('Automação excluída');
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  }
};

const delayLabel = (minutes) => {
  if (minutes === 0)    return 'Imediatamente';
  if (minutes < 60)     return `${minutes}min`;
  if (minutes < 1440)   return `${Math.round(minutes / 60)}h`;
  return `${Math.round(minutes / 1440)}d`;
};
</script>

<template>
  <!-- RAIZ ÚNICA: o vuedraggable exige um único nó raiz por item (o drag de
       colunas quebra com multi-root) — os modais vivem DENTRO desta div. -->
  <div
    v-show="!hidden"
    class="flex flex-col bg-n-alpha-1 rounded-xl w-[86vw] min-w-[86vw] snap-center md:w-64 md:min-w-64 md:snap-align-none flex-shrink-0 h-full transition-all"
    :class="programmingMode ? 'ring-2 ring-yellow-400/50' : ''"
  >

    <!-- ── Header (no modo edição, o header inteiro arrasta a coluna) ── -->
    <div
      class="px-3 py-2.5 border-b border-n-weak flex-shrink-0"
      :class="[
        programmingMode ? 'bg-yellow-500/5' : '',
        editMode ? 'column-drag-handle cursor-grab active:cursor-grabbing' : '',
      ]"
    >

      <!-- Delete confirmation -->
      <div v-if="showDeleteConfirm" class="space-y-2">
        <template v-if="hasCards">
          <p class="text-xs text-n-slate-11">
            {{ $t('CRM.DELETE_STAGE_HAS_CARDS', { count: contacts.length }) }}
          </p>
          <select
            v-model="moveToStageId"
            class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
          >
            <option v-for="s in otherStages" :key="s.id" :value="s.id">{{ s.name }}</option>
          </select>
          <div class="flex gap-2">
            <button
              class="flex-1 bg-red-500 text-white rounded-lg py-1.5 text-xs disabled:opacity-50"
              :disabled="isDeleting || !moveToStageId"
              @click="deleteStage"
            >{{ isDeleting ? '...' : $t('CRM.DELETE_MOVE_AND_DELETE') }}</button>
            <button
              class="flex-1 border border-n-weak rounded-lg py-1.5 text-xs text-n-slate-11"
              @click="cancelDelete"
            >{{ $t('CRM.CANCEL') }}</button>
          </div>
        </template>
        <template v-else>
          <p class="text-xs text-n-slate-11">{{ $t('CRM.DELETE_STAGE_CONFIRM') }}</p>
          <div class="flex gap-2">
            <button
              class="flex-1 bg-red-500 text-white rounded-lg py-1.5 text-xs disabled:opacity-50"
              :disabled="isDeleting"
              @click="deleteStage"
            >{{ isDeleting ? '...' : $t('CRM.DELETE_STAGE') }}</button>
            <button
              class="flex-1 border border-n-weak rounded-lg py-1.5 text-xs text-n-slate-11"
              @click="cancelDelete"
            >{{ $t('CRM.CANCEL') }}</button>
          </div>
        </template>
      </div>

      <!-- Normal header -->
      <div v-else>
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2 min-w-0">
            <span
              class="w-2.5 h-2.5 rounded-full flex-shrink-0"
              :style="{ backgroundColor: stage.color }"
            />
            <span class="text-sm font-semibold text-n-slate-12 truncate">{{ stage.name }}</span>
            <!-- No modo programação: mostra nº de automações em vez de cards -->
            <span
              class="text-xs rounded px-1.5 py-0.5 flex-shrink-0"
              :class="programmingMode
                ? 'text-yellow-600 bg-yellow-500/15'
                : 'text-n-slate-10 bg-n-alpha-2'"
            >
              {{ programmingMode ? automations.length : headerCount.toLocaleString('pt-BR') }}
            </span>
          </div>

          <div class="flex items-center gap-1 flex-shrink-0 ml-1">
            <!-- Arrastar coluna — só admin e SÓ no modo edição -->
            <span
              v-if="isAdmin && editMode"
              class="column-drag-handle i-lucide-grip-vertical text-sm text-n-slate-9 hover:text-n-slate-12 cursor-grab active:cursor-grabbing"
              title="Arrastar para reordenar a coluna"
            />
            <!-- Modo Edição -->
            <template v-if="editMode">
              <button
                class="text-n-slate-10 hover:text-n-slate-12 i-lucide-pencil text-sm"
                @click="showEditModal = true"
              />
              <button
                class="text-n-slate-10 hover:text-red-500 i-lucide-trash-2 text-sm"
                @click="confirmDelete"
              />
            </template>
          </div>
        </div>

        <!-- Subtítulo no modo programação -->
        <p v-if="programmingMode" class="text-[11px] text-yellow-600/80 mt-1">
          ⚡ Automações da coluna
        </p>
        <!-- Valor total no modo normal (só admin vê valores) -->
        <p v-else-if="isAdmin && totalValue > 0" class="text-sm font-semibold text-green-600 text-center mt-1.5">
          R$ {{ totalValue.toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
        </p>
      </div>
    </div>

    <!-- ── Body: MODO PROGRAMAÇÃO → lista de automações ──────── -->
    <div
      v-if="programmingMode"
      class="flex-1 overflow-y-auto p-2 space-y-2 min-h-0"
      style="scrollbar-width:thin;scrollbar-color:rgba(148,163,184,0.35) transparent;"
    >

      <!-- Loading -->
      <div v-if="isLoadingAutomations" class="flex justify-center pt-6">
        <span class="i-lucide-loader-2 animate-spin text-yellow-500 text-lg" />
      </div>

      <!-- Empty state -->
      <div
        v-else-if="automations.length === 0"
        class="flex flex-col items-center justify-center py-8 text-center"
      >
        <span class="i-lucide-zap text-2xl text-yellow-400/50 mb-2" />
        <p class="text-xs text-n-slate-10 leading-relaxed">
          Nenhuma automação.<br/>Clique em "+ Automação" para criar.
        </p>
      </div>

      <!-- Automation cards -->
      <template v-else>
        <div
          v-for="auto in automations"
          :key="auto.id"
          class="rounded-lg border bg-n-solid-1 transition-all"
          :class="auto.active
            ? 'border-yellow-400/30 hover:border-yellow-400/60'
            : 'border-n-weak opacity-50 hover:opacity-70'"
        >
          <!-- Delete confirm inline -->
          <div v-if="deleteConfirmAutoId === auto.id" class="p-2.5 space-y-2">
            <p class="text-xs text-n-slate-11">Excluir <strong>{{ auto.name }}</strong>?</p>
            <div class="flex gap-1.5">
              <button
                class="flex-1 bg-red-500 text-white rounded py-1 text-xs"
                @click="deleteAutomation(auto)"
              >Excluir</button>
              <button
                class="flex-1 border border-n-weak rounded py-1 text-xs text-n-slate-11"
                @click="deleteConfirmAutoId = null"
              >Cancelar</button>
            </div>
          </div>

          <template v-else>
            <!-- Card body — clicável para editar -->
            <div
              class="p-2.5 cursor-pointer"
              @click="openEditAutomation(auto)"
            >
              <!-- Nome + status badge -->
              <div class="flex items-start justify-between gap-1 mb-1.5">
                <span class="text-xs font-semibold text-n-slate-12 leading-tight line-clamp-2">
                  {{ auto.name }}
                </span>
                <span
                  class="text-[10px] px-1.5 py-0.5 rounded flex-shrink-0 font-medium"
                  :class="auto.active
                    ? 'bg-green-500/15 text-green-600'
                    : 'bg-n-alpha-2 text-n-slate-9'"
                >
                  {{ auto.active ? 'Ativa' : 'Off' }}
                </span>
              </div>

              <!-- Trigger → Action pills -->
              <div class="flex items-center gap-1 flex-wrap">
                <span class="flex items-center gap-1 bg-n-alpha-2 rounded px-1.5 py-0.5 text-[10px] text-n-slate-10">
                  <span :class="TRIGGER_ICONS[auto.trigger_type]" class="text-xs" />
                  {{ TRIGGER_LABELS[auto.trigger_type] }}
                </span>
                <span class="i-lucide-arrow-right text-[10px] text-n-slate-8" />
                <span class="flex items-center gap-1 bg-n-brand/10 rounded px-1.5 py-0.5 text-[10px] text-n-brand">
                  <span :class="ACTION_ICONS[auto.action_type]" class="text-xs" />
                  {{ ACTION_LABELS[auto.action_type] }}
                </span>
              </div>

              <!-- 🤖 agente de IA: faixa com edição rápida dali mesmo -->
              <div
                v-if="agentOf(auto)"
                class="mt-1.5 rounded-lg px-2 py-1.5 text-white flex items-center gap-1.5"
                :style="{ background: agentOf(auto).grad }"
              >
                <span class="i-lucide-sparkles text-xs flex-shrink-0" />
                <span class="text-[10px] font-bold flex-1 truncate">{{ agentOf(auto).title }}</span>
                <span
                  class="text-[9px] px-1.5 py-px rounded-full font-semibold flex-shrink-0"
                  :class="agentEnabled(auto) ? 'bg-white/25' : 'bg-black/30'"
                >
                  {{ agentEnabled(auto) ? 'LIGADO' : 'desligado' }}
                </span>
                <button
                  class="text-[10px] underline font-semibold flex-shrink-0"
                  title="Abrir a edição rápida do agente de IA"
                  @click.stop="openAgentModal(auto)"
                >
                  editar
                </button>
              </div>

              <!-- Delay tag -->
              <div v-if="auto.delay_minutes > 0" class="mt-1.5">
                <span class="flex items-center gap-1 text-[10px] text-n-slate-9">
                  <span class="i-lucide-clock text-xs" />
                  {{ delayLabel(auto.delay_minutes) }}
                </span>
              </div>

              <p v-if="auto.kind === 'message_automation'" class="text-[10px] text-n-slate-9 mt-1 italic">
                Gerenciada em Campanha WhatsApp
              </p>
            </div>

            <!-- Footer actions -->
            <div class="flex items-center border-t border-n-weak/50 divide-x divide-n-weak/50">
              <!-- Toggle active -->
              <button
                class="flex-1 flex items-center justify-center gap-1 py-1.5 text-[11px] hover:bg-n-alpha-1 transition-colors rounded-bl-lg"
                :class="auto.active ? 'text-yellow-600' : 'text-green-600'"
                @click.stop="toggleAutomationActive(auto)"
              >
                <span :class="auto.active ? 'i-lucide-pause' : 'i-lucide-play'" class="text-xs" />
                {{ auto.active ? 'Pausar' : 'Ativar' }}
              </button>
              <!-- Delete -->
              <button
                class="px-3 py-1.5 text-n-slate-9 hover:text-red-500 hover:bg-red-500/5 transition-colors rounded-br-lg"
                @click.stop="deleteConfirmAutoId = auto.id"
              >
                <span class="i-lucide-trash-2 text-xs" />
              </button>
            </div>
          </template>
        </div>
      </template>

      <!-- Robôs de follow-up desta coluna (só admin) -->
      <div v-if="isAdmin" class="mt-3 pt-3 border-t border-yellow-400/20">
        <p class="text-[11px] font-semibold text-yellow-600/90 mb-2 flex items-center gap-1">
          <span class="i-lucide-bot text-xs" /> Robôs de follow-up
        </p>
        <div v-if="!followupBots.length" class="text-[11px] text-n-slate-9 mb-2">
          Cutucadas automáticas para os cards parados nesta coluna.
        </div>
        <div
          v-for="bot in followupBots"
          :key="bot.id"
          class="rounded-lg border bg-n-solid-1 mb-2"
          :class="bot.active ? 'border-yellow-400/30' : 'border-n-weak opacity-50'"
        >
          <div v-if="deleteBotConfirmId === bot.id" class="p-2.5 space-y-2">
            <p class="text-xs text-n-slate-11">Excluir <strong>{{ bot.name }}</strong>?</p>
            <div class="flex gap-1.5">
              <button class="flex-1 bg-red-500 text-white rounded py-1 text-xs" @click="deleteBot(bot)">Excluir</button>
              <button class="flex-1 border border-n-weak rounded py-1 text-xs text-n-slate-11" @click="deleteBotConfirmId = null">Cancelar</button>
            </div>
          </div>
          <template v-else>
            <div class="p-2.5 cursor-pointer" @click="openEditBot(bot)">
              <div class="flex items-start justify-between gap-1 mb-1.5">
                <span class="text-xs font-semibold text-n-slate-12 leading-tight">{{ bot.name }}</span>
                <span
                  class="text-[10px] px-1.5 py-0.5 rounded flex-shrink-0 font-medium"
                  :class="bot.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
                >{{ bot.active ? 'Ativo' : 'Off' }}</span>
              </div>
              <div class="flex flex-wrap gap-1">
                <span
                  v-for="(s, i) in bot.steps"
                  :key="i"
                  class="text-[10px] bg-n-alpha-2 text-n-slate-10 rounded px-1.5 py-0.5"
                >{{ botDelayLabel(s) }}: {{ s.template_params ? `📋 ${s.template_params.name}` : `"${s.message}"` }}</span>
              </div>
            </div>
            <div class="flex items-center border-t border-n-weak/50 divide-x divide-n-weak/50">
              <button
                class="flex-1 flex items-center justify-center gap-1 py-1.5 text-[11px] hover:bg-n-alpha-1 rounded-bl-lg"
                :class="bot.active ? 'text-yellow-600' : 'text-green-600'"
                @click.stop="toggleBot(bot)"
              >
                <span :class="bot.active ? 'i-lucide-pause' : 'i-lucide-play'" class="text-xs" />
                {{ bot.active ? 'Pausar' : 'Ativar' }}
              </button>
              <button
                class="px-3 py-1.5 text-n-slate-9 hover:text-red-500 hover:bg-red-500/5 rounded-br-lg"
                @click.stop="deleteBotConfirmId = bot.id"
              >
                <span class="i-lucide-trash-2 text-xs" />
              </button>
            </div>
          </template>
        </div>
        <button
          class="w-full flex items-center justify-center gap-1.5 text-[11px] text-yellow-600 hover:text-yellow-700 py-1.5 rounded-lg hover:bg-yellow-500/10 border border-dashed border-yellow-400/40"
          @click="openCreateBot"
        >
          <span class="i-lucide-plus text-xs" /> Robô de follow-up
        </button>
      </div>
    </div>

    <!-- ── Body: MODO NORMAL → cards ────────────────────────── -->
    <div
      v-else
      class="column-cards-scroll p-2"
      style="flex:1;overflow-y:scroll;min-height:0;scrollbar-width:thin;scrollbar-color:rgba(148,163,184,0.35) transparent;"
    >
      <draggable
        :key="isMobile ? 'drag-off' : 'drag-on'"
        v-model="localContacts"
        group="crm-contacts"
        item-key="id"
        :animation="150"
        :empty-insert-threshold="120"
        :disabled="isMobile"
        ghost-class="opacity-40"
        class="min-h-full"
      >
        <template #item="{ element }">
          <ContactCard
            :contact="element"
            @click="emit('cardClick', element)"
            @open-chat="emit('openChat', $event)"
          />
        </template>
      </draggable>

      <!-- Paginação da coluna: a contagem do cabeçalho é a REAL do período;
           os cards entram em lotes para o board não pesar -->
      <button
        v-if="hasMoreCards && !editMode"
        class="w-full flex items-center justify-center gap-1.5 text-xs text-n-brand hover:text-n-brand/80 py-2 mt-1 rounded-lg border border-dashed border-n-brand/40 hover:bg-n-brand/5 transition-colors"
        :disabled="loadingMore"
        @click="emit('loadMore')"
      >
        <span v-if="loadingMore" class="i-lucide-loader-circle animate-spin text-sm" />
        <span v-else class="i-lucide-chevrons-down text-sm" />
        {{ loadingMore
          ? 'Carregando…'
          : `Carregar mais (${contacts.length.toLocaleString('pt-BR')} de ${totalCount.toLocaleString('pt-BR')})` }}
      </button>
    </div>

    <!-- ── Footer ─────────────────────────────────────────────── -->
    <div class="px-2 pb-2 flex-shrink-0">
      <!-- Modo programação: botão nova automação -->
      <button
        v-if="programmingMode"
        class="w-full flex items-center justify-center gap-1.5 text-xs text-yellow-600 hover:text-yellow-700 py-2 rounded-lg hover:bg-yellow-500/10 border border-dashed border-yellow-400/50 hover:border-yellow-500 transition-colors"
        @click="openCreateAutomation"
      >
        <span class="i-lucide-plus text-sm" />
        Nova automação
      </button>

      <!-- Modo normal: botão adicionar contato -->
      <button
        v-else
        class="w-full flex items-center justify-center gap-1 text-xs text-n-slate-10 hover:text-n-brand py-1.5 rounded-lg hover:bg-n-alpha-1 transition-colors"
        @click="emit('addContact', stage.id)"
      >
        <span class="i-lucide-plus text-sm" />
        {{ $t('CRM.ADD_CONTACT') }}
      </button>
    </div>

    <!-- Stage edit modal (overlay fixed — dentro da raiz p/ manter raiz única) -->
    <StageEditModal
      :stage="showEditModal ? stage : null"
      :pipeline-id="pipelineId"
      @close="showEditModal = false"
      @saved="showEditModal = false"
    />

    <!-- Automation create/edit modal -->
    <ColumnAutomationsModal
      v-if="showAutomationForm"
      :stage="stage"
      :pipeline-id="pipelineId"
      :all-stages="allStages"
      :initial-automation="editingAutomation"
      @close="showAutomationForm = false"
      @saved="onAutomationSaved"
    />

    <!-- Edição rápida do agente de IA (dali mesmo, sem sair do board) -->
    <Teleport to="body">
      <div
        v-if="showAgentModal"
        class="fixed inset-0 z-[70] flex items-center justify-center bg-black/60 p-4"
        @click.self="showAgentModal = false"
      >
        <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md max-h-[85vh] flex flex-col overflow-hidden">
          <div class="h-1.5 w-full flex-shrink-0" :style="{ background: agentModal.grad }" />
          <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
            <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
              <span class="i-lucide-sparkles" />
              {{ agentModal.title }}
            </h2>
            <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showAgentModal = false" />
          </div>
          <div class="flex-1 overflow-y-auto p-5 space-y-3">
            <button
              class="w-full flex items-center justify-between rounded-xl border px-3 py-2.5"
              :class="agentForm.enabled ? 'border-green-500/40 bg-green-500/5' : 'border-n-weak bg-n-solid-2'"
              @click="agentForm.enabled = !agentForm.enabled"
            >
              <span class="text-sm font-medium text-n-slate-12">{{ agentForm.enabled ? '✅ Agente LIGADO' : '⏹ Agente desligado' }}</span>
              <span class="text-[10px] text-n-slate-9">clique para {{ agentForm.enabled ? 'desligar' : 'ligar' }}</span>
            </button>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Modelo</label>
              <select v-model="agentForm.model" class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12">
                <option value="">⭐ Recomendado do agente</option>
                <option value="claude-opus-4-8">Opus 4.8 — melhor análise</option>
                <option value="claude-sonnet-5">Sonnet 5 — equilíbrio</option>
                <option value="claude-haiku-4-5">Haiku 4.5 — mais barato e rápido</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">
                Instruções (prompt)
                <span class="text-n-slate-9 font-normal">— vazio = padrão do agente</span>
              </label>
              <textarea
                v-model="agentForm.prompt"
                rows="7"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-xs bg-n-solid-2 text-n-slate-12 resize-none focus:outline-none focus:border-n-brand font-mono"
                :placeholder="agentForm.default_prompt ? agentForm.default_prompt.slice(0, 400) + '…' : 'Instruções personalizadas do agente'"
              />
            </div>
            <p class="text-[10px] text-n-slate-9">
              A configuração completa (colunas de atuação, rascunhos, registro) fica em
              Automações → Agentes de IA. Salvar aqui PUBLICA na hora.
            </p>
          </div>
          <div class="px-5 py-4 border-t border-n-weak flex gap-2 flex-shrink-0">
            <button
              class="flex-1 text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
              :style="{ background: agentModal.grad }"
              :disabled="isSavingAgent"
              @click="saveAgentModal"
            >
              {{ isSavingAgent ? 'Salvando…' : 'Salvar e publicar' }}
            </button>
            <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showAgentModal = false">
              Cancelar
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Robô de follow-up da coluna -->
    <FollowupBotModal
      v-if="showBotModal"
      :bot="editingBot"
      :stage-id="stage.id"
      :pipeline-id="pipelineId"
      @close="showBotModal = false"
      @saved="onBotSaved"
    />
  </div>
</template>
