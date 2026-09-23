<script setup>
import { computed, ref, watch } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import MessagePreview from './MessagePreview.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { inboxSolidFor } from 'dashboard/helper/cevicoInboxColors';
import { firstNameOf, initialOf } from 'dashboard/helper/cevicoPersonColors';
import { useCevicoPersonColors } from 'dashboard/composables/useCevicoPersonColors';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);

const unreadCount = computed(() => props.chat.unread_count);
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const isAgentBotAssignee = computed(
  () => props.chat?.meta?.assignee_type === 'AgentBot'
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !props.currentContact?.blocked
);

const messagePreviewClass = computed(() => {
  return [
    hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
    !props.compact && hasUnread.value ? 'ltr:pr-4 rtl:pl-4' : '',
    props.compact && hasUnread.value ? 'ltr:pr-6 rtl:pl-6' : '',
  ];
});

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);

// ── CEVICO (item 90 — 19/07 → 212 — 23/09): indicador VIVO da caixa + balão
// da jornada — a cor sólida da caixa pinta o ícone do canal e o nome da caixa
// na 2ª linha (o nome do paciente ficou neutro); chip com a coluna do CRM
// que abre um balãozinho de "botões em linha" para mover
const allInboxes = useMapGetter('inboxes/getInboxes');
const crmPipelines = useMapGetter('crm/getPipelines');
const nameColor = computed(() =>
  inboxSolidFor(allInboxes.value || [], props.chat.inbox_id)
);
const journeyStages = computed(() =>
  (crmPipelines.value || []).flatMap(p => p.stages || [])
);
const chatStage = computed(
  () => journeyStages.value.find(s => s.id === props.chat.crm_stage_id) || null
);
const showStagePopover = ref(false);
const isMovingStage = ref(false);
// balão via Teleport (fora do card): a animação do card ativo cria stacking
// context e prendia o z-index — dentro da lista o balão ficava "vazado"
const chipEl = ref(null);
const popoverPos = ref({ x: 0, y: 0 });
const toggleStagePopover = () => {
  if (!showStagePopover.value && chipEl.value) {
    const r = chipEl.value.getBoundingClientRect();
    popoverPos.value = {
      x: Math.min(r.left, window.innerWidth - 272),
      y: r.bottom + 4,
    };
  }
  showStagePopover.value = !showStagePopover.value;
};
const pickStage = async stage => {
  if (isMovingStage.value || stage.id === props.chat.crm_stage_id) return;
  isMovingStage.value = true;
  try {
    await CrmAPI.moveConversationStage(props.chat.id, stage.id);
    // eslint-disable-next-line vue/no-mutating-props
    props.chat.crm_stage_id = stage.id;
    showStagePopover.value = false;
  } catch {
    // mantém o balão aberto para tentar de novo
  } finally {
    isMovingStage.value = false;
  }
};

// ── CEVICO item 212 (23/09): a COR DE CADA PESSOA no cartão ──────────────
// crachá redondo sobre a foto do paciente + pílula com o primeiro nome, na
// cor fixa da pessoa (helper cevicoPersonColors). Robô/Atendente IA = lilás.
const { colorFor, patientGradientFor } = useCevicoPersonColors();
// a "foto" do paciente (iniciais) na cor de quem cuida dele; sem ninguém = cinza
const patientGradient = computed(() => patientGradientFor(props.chat));
const hasAssignee = computed(() => !!props.assignee?.name);
const assigneeColor = computed(() =>
  colorFor({
    id: props.assignee?.id,
    name: props.assignee?.name,
    assignee_type: props.chat?.meta?.assignee_type,
  })
);
const assigneeFirst = computed(() => firstNameOf(props.assignee?.name));
const assigneeInitial = computed(() => initialOf(props.assignee?.name));
const showWhoRow = computed(() => props.showInboxName || props.showAssignee);

// ── etiquetas SEM medir largura (item 212): o cartão antigo media os chips
// no mount e, dentro da lista virtual, media 0 → etiquetas sumiam e sobrava
// só um ">" (o "falhado" dos prints). Agora: até 3 sempre visíveis, o resto
// atrás de um "+N" que abre e fecha.
const accountLabels = useMapGetter('labels/getLabels');
const activeLabels = computed(() => {
  const titles = props.chat.labels || [];
  if (!titles.length) return [];
  return (accountLabels.value || []).filter(l => titles.includes(l.title));
});
const LABELS_SHOWN = 3;
const labelsExpanded = ref(false);
const visibleLabels = computed(() =>
  labelsExpanded.value
    ? activeLabels.value
    : activeLabels.value.slice(0, LABELS_SHOWN)
);
const hiddenLabels = computed(() =>
  Math.max(0, activeLabels.value.length - LABELS_SHOWN)
);
const toggleLabels = () => {
  labelsExpanded.value = !labelsExpanded.value;
};
// 🧹 item 214: "lista limpa" — o admin liga em Configurações → Painéis e as
// atendentes deixam de ver a coluna do CRM e as etiquetas; admin vê sempre
const { isAdmin } = useAdmin();
const crmSettings = useMapGetter('crm/getSettings');
// modos: full (tudo) · no_stage (só sem a coluna) · clean (sem coluna e etiquetas)
const listMode = computed(() => {
  if (isAdmin.value) return 'full';
  const mode = crmSettings.value?.list_clean_mode;
  if (['full', 'no_stage', 'clean'].includes(mode)) return mode;
  return crmSettings.value?.list_clean_for_agents === true ? 'clean' : 'full';
});
const hideStage = computed(() => listMode.value !== 'full');
const hideLabels = computed(() => listMode.value === 'clean');
// a 4ª linha existe sempre que há jornada configurada (coluna ou "sem
// coluna"), etiqueta ou SLA — assim os cartões ficam alinhados entre si
const showJourneyRow = computed(
  () =>
    (!hideStage.value && journeyStages.value.length > 0) ||
    (!hideLabels.value &&
      (activeLabels.value.length > 0 || hasSlaPolicyId.value))
);
// sem nada embaixo (modo clean): nomes um pouco maiores e linhas realinhadas
const isCleanCard = computed(() => listMode.value === 'clean');
</script>

<template>
  <!-- CEVICO 199 (22/09) + 212 (23/09): cartão no formato do WhatsApp com
       acabamento Apple — foto redonda grande com o CRACHÁ de quem cuida,
       nome + hora na 1ª linha, caixa (à esquerda) e responsável (pílula à
       direita) na 2ª, prévia + bolinha verde na 3ª, coluna do CRM e
       etiquetas em pílulas na 4ª. As classes cv-card* vestem o visual
       (_cevico-conversas.scss). -->
  <div
    class="cv-card relative flex items-center gap-3 cursor-pointer conversation group"
    :class="{
      'cv-card-on active animate-card-select': isActiveChat,
      'cv-card-sel selected': selected,
      'cv-card-compact': compact,
      'cv-card-clean': isCleanCard,
    }"
    @click="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <div
      class="relative flex-shrink-0"
      @mouseenter="onThumbnailHover"
      @mouseleave="onThumbnailLeave"
    >
      <Avatar
        v-if="!hideThumbnail"
        :name="currentContact.name"
        :src="currentContact.thumbnail"
        :size="44"
        :status="currentContact.availability_status"
        hide-offline-status
        rounded-full
        gradient
        :gradient-override="patientGradient"
      >
        <template #overlay="{ size }">
          <label
            v-if="hovered || selected"
            class="flex items-center justify-center rounded-full cursor-pointer absolute inset-0 z-10 backdrop-blur-[2px]"
            :style="{ width: `${size}px`, height: `${size}px` }"
            @click.stop
          >
            <Checkbox v-model="selectedModel" />
          </label>
        </template>
      </Avatar>
      <!-- crachá de quem cuida (cor fixa da pessoa) -->
      <span
        v-if="!hideThumbnail && showAssignee && hasAssignee"
        class="cv-card-badge"
        :style="{ background: assigneeColor.grad }"
        :title="`Responsável: ${assignee.name}`"
      >
        <img
          v-if="assignee.thumbnail && !isAgentBotAssignee"
          :src="assignee.thumbnail"
          alt=""
        />
        <span v-else-if="isAgentBotAssignee" class="i-lucide-bot text-[10px]" />
        <span v-else>{{ assigneeInitial }}</span>
      </span>
    </div>

    <div class="flex-1 min-w-0 flex flex-col gap-[3px]">
      <!-- 1ª linha: nome (NEUTRO — decisão dele 23/09: a cor da caixa fica
           só na linha de baixo) + prioridade + hora -->
      <div class="flex items-center gap-2 min-w-0">
        <h4
          class="conversation--user flex-1 min-w-0 truncate text-[14px] leading-5 m-0 text-n-slate-12"
          :class="hasUnread ? 'font-bold' : 'font-semibold'"
          :title="currentContact.name"
        >
          {{ currentContact.name }}
        </h4>
        <CardPriorityIcon
          :priority="chat.priority"
          class="flex-shrink-0 !size-3.5"
        />
        <span
          class="cv-card-time flex-shrink-0 text-[11px] leading-4 whitespace-nowrap"
          :class="hasUnread ? 'cv-card-time-on' : ''"
        >
          <TimeAgo
            :last-activity-timestamp="chat.timestamp"
            :created-at-timestamp="chat.created_at"
            :conversation-id="chat.id"
          />
        </span>
      </div>

      <!-- 2ª linha: caixa de entrada (esquerda) + quem cuida (pílula à direita) -->
      <div v-if="showWhoRow" class="flex items-center gap-2 min-w-0 leading-4">
        <span
          v-if="showInboxName"
          class="cv-card-inbox min-w-0"
          :style="nameColor ? { color: nameColor } : {}"
          :title="inbox.name"
        >
          <ChannelIcon :inbox="inbox" class="size-3.5 flex-shrink-0" />
          <span class="truncate">{{ inbox.name }}</span>
        </span>
        <span
          v-if="showAssignee"
          class="cv-card-who ml-auto"
          :class="hasAssignee ? '' : 'cv-card-who-none'"
          :style="hasAssignee ? { '--pc': assigneeColor.solid } : {}"
          :title="
            hasAssignee
              ? `Responsável: ${assignee.name}`
              : 'Ninguém cuida desta conversa ainda'
          "
        >
          <template v-if="hasAssignee">
            <img
              v-if="assignee.thumbnail && !isAgentBotAssignee"
              :src="assignee.thumbnail"
              alt=""
            />
            <span
              v-else-if="isAgentBotAssignee"
              class="i-lucide-bot text-[11px] flex-shrink-0"
            />
            <span v-else class="cv-card-who-dot" />
            <span class="truncate">{{ assigneeFirst }}</span>
          </template>
          <template v-else>
            <span class="i-lucide-user-round-x text-[11px] flex-shrink-0" />
            <span class="truncate">sem responsável</span>
          </template>
        </span>
      </div>

      <!-- 3ª linha: prévia da última mensagem + não lidas -->
      <div class="flex items-center gap-2 min-w-0">
        <VoiceCallStatus
          v-if="voiceCallData.status"
          key="voice-status-row"
          :status="voiceCallData.status"
          :direction="voiceCallData.direction"
          :message-preview-class="messagePreviewClass"
          class="flex-1 min-w-0"
        />
        <MessagePreview
          v-else-if="lastMessageInChat"
          key="message-preview"
          :message="lastMessageInChat"
          class="cv-card-preview flex-1 min-w-0 text-[13px] leading-5 m-0"
          :class="[messagePreviewClass, hasUnread ? 'cv-card-preview-on' : '']"
        />
        <p
          v-else
          key="no-messages"
          class="cv-card-preview flex-1 min-w-0 text-[13px] leading-5 m-0"
          :class="messagePreviewClass"
        >
          <fluent-icon
            size="14"
            class="-mt-0.5 align-middle inline-block text-n-slate-10"
            icon="info"
          />
          <span class="mx-0.5">
            {{ $t(`CHAT_LIST.NO_MESSAGES`) }}
          </span>
        </p>
        <UnreadBadge
          v-if="hasUnread"
          :count="unreadCount"
          class="cv-card-unread flex-shrink-0"
        />
      </div>

      <!-- 4ª linha: coluna da jornada (CRM) + etiquetas, em pílulas -->
      <div
        v-if="showJourneyRow"
        class="cv-card-tags flex items-center gap-1 flex-wrap min-w-0"
      >
        <div
          v-if="journeyStages.length && !hideStage"
          class="relative min-w-0"
          @click.stop
        >
          <button
            v-if="chatStage"
            ref="chipEl"
            class="cv-tag cv-tag-btn max-w-full"
            :style="{ '--lb': chatStage.color || '#94A3B8' }"
            title="Coluna da jornada — toque para mover"
            @click="toggleStagePopover"
          >
            <span class="cv-tag-dot" />
            <span class="truncate">{{ chatStage.name }}</span>
            <span class="i-lucide-chevron-down text-[10px] flex-shrink-0" />
          </button>
          <span
            v-else
            class="cv-tag cv-tag-ghost"
            title="Este paciente ainda não tem card na jornada (o card nasce sozinho na 1ª etapa ou pelo CRM)"
          >
            <span class="i-lucide-columns-3 text-[10px] flex-shrink-0" />
            sem coluna
          </span>

          <Teleport v-if="showStagePopover" to="body">
            <div
              class="fixed inset-0 z-[9998]"
              @click.stop="showStagePopover = false"
            />
            <div
              class="fixed z-[9999] w-64 rounded-2xl border border-n-weak bg-white dark:bg-n-solid-2 shadow-xl p-3"
              :style="{ left: `${popoverPos.x}px`, top: `${popoverPos.y}px` }"
              @click.stop
            >
              <p
                class="text-[10px] font-bold text-n-slate-10 uppercase tracking-wide mb-2"
              >
                Mover para a coluna
              </p>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="s in journeyStages"
                  :key="s.id"
                  class="cv-tag cv-tag-btn cv-tag-md"
                  :class="s.id === chat.crm_stage_id ? 'cv-tag-solid' : ''"
                  :style="{ '--lb': s.color || '#94A3B8' }"
                  :disabled="isMovingStage"
                  @click="pickStage(s)"
                >
                  <span v-if="s.id !== chat.crm_stage_id" class="cv-tag-dot" />
                  {{ s.name }}
                </button>
              </div>
            </div>
          </Teleport>
        </div>

        <SLACardLabel v-if="hasSlaPolicyId && !hideLabels" :chat="chat" />

        <span
          v-for="label in hideLabels ? [] : visibleLabels"
          :key="label.id"
          class="cv-tag max-w-full"
          :style="{ '--lb': label.color || '#94A3B8' }"
          :title="label.description || label.title"
        >
          <span class="truncate">{{ label.title }}</span>
        </span>
        <button
          v-if="hiddenLabels > 0 && !hideLabels"
          class="cv-tag cv-tag-more"
          :title="labelsExpanded ? 'Mostrar menos' : 'Ver todas as etiquetas'"
          @click.stop="toggleLabels"
        >
          {{ labelsExpanded ? 'menos' : `+${hiddenLabels}` }}
        </button>
      </div>
    </div>
  </div>
</template>
