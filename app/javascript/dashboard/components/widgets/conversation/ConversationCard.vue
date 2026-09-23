<script setup>
import { computed, ref, watch } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MessagePreview from './MessagePreview.vue';
import InboxName from '../InboxName.vue';
import TimeAgo from 'dashboard/components/ui/TimeAgo.vue';
import CardLabels from './conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import UnreadBadge from 'dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue';
import SLACardLabel from './components/SLACardLabel.vue';
import VoiceCallStatus from './VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { inboxSolidFor } from 'dashboard/helper/cevicoInboxColors';
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

const showMetaSection = computed(() => {
  return (
    props.showInboxName ||
    (props.showAssignee && props.assignee.name) ||
    props.chat.priority
  );
});

const isAgentBotAssignee = computed(
  () => props.chat?.meta?.assignee_type === 'AgentBot'
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !props.currentContact?.blocked
);

const showLabelsSection = computed(() => {
  return props.chat.labels?.length > 0 || hasSlaPolicyId.value;
});

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

// ── CEVICO (item 90 — 19/07): indicador VIVO da caixa + balão da jornada ──
// nome do contato na cor sólida da própria caixa de entrada; chip com a
// coluna do CRM que abre um balãozinho de "botões em linha" para mover
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
</script>

<template>
  <!-- CEVICO 199 (22/09): cartão no formato do WhatsApp com acabamento Apple —
       foto redonda grande, nome + hora na 1ª linha, caixa/responsável na 2ª,
       prévia + bolinha verde de não lidas na 3ª, coluna do CRM e etiquetas
       na 4ª. As classes cv-card* vestem o visual (_cevico-conversas.scss). -->
  <div
    class="cv-card relative flex items-center gap-3 cursor-pointer conversation group"
    :class="{
      'cv-card-on active animate-card-select': isActiveChat,
      'cv-card-sel selected': selected,
      'cv-card-compact': compact,
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
    </div>

    <div class="flex-1 min-w-0 flex flex-col gap-0.5">
      <!-- 1ª linha: nome (na cor da caixa) + prioridade + hora -->
      <div class="flex items-center gap-2 min-w-0">
        <h4
          class="conversation--user flex-1 min-w-0 truncate text-[14px] leading-5 m-0 text-n-slate-12"
          :class="hasUnread ? 'font-bold' : 'font-semibold'"
          :style="nameColor ? { color: nameColor } : {}"
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

      <!-- 2ª linha: caixa de entrada + pessoa responsável -->
      <div
        v-if="showMetaSection"
        class="flex items-center gap-2 min-w-0 text-[11px] leading-4"
      >
        <InboxName v-if="showInboxName" :inbox="inbox" class="min-w-0" />
        <span
          v-if="showAssignee && assignee.name"
          class="cv-card-assignee inline-flex items-center gap-0.5 min-w-0 truncate ml-auto"
        >
          <Icon
            :icon="isAgentBotAssignee ? 'i-lucide-bot' : 'i-lucide-user-round'"
            class="size-3 flex-shrink-0"
          />
          <span class="truncate">{{ assignee.name }}</span>
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

      <!-- 4ª linha: coluna da jornada (CRM) + etiquetas -->
      <div
        v-if="chatStage || showLabelsSection"
        class="flex items-center gap-1 flex-wrap mt-0.5 min-w-0"
      >
        <div v-if="chatStage" class="relative min-w-0" @click.stop>
          <button
            ref="chipEl"
            class="cv-card-stage inline-flex items-center gap-1 h-5 px-1.5 rounded-full border text-[10px] font-medium transition-colors max-w-full"
            title="Coluna da jornada — toque para mover"
            @click="toggleStagePopover"
          >
            <span
              class="w-2 h-2 rounded-full flex-shrink-0"
              :style="{ background: chatStage.color }"
            />
            <span class="truncate">{{ chatStage.name }}</span>
            <span class="i-lucide-chevron-down text-[10px] flex-shrink-0" />
          </button>

          <Teleport v-if="showStagePopover" to="body">
            <div
              class="fixed inset-0 z-[9998]"
              @click.stop="showStagePopover = false"
            />
            <div
              class="fixed z-[9999] w-64 rounded-xl border border-n-weak bg-white dark:bg-n-solid-2 shadow-xl p-2"
              :style="{ left: `${popoverPos.x}px`, top: `${popoverPos.y}px` }"
              @click.stop
            >
              <p class="text-[10px] font-bold text-n-slate-10 uppercase mb-1.5">
                Mover para a coluna
              </p>
              <div class="flex flex-wrap gap-1">
                <button
                  v-for="s in journeyStages"
                  :key="s.id"
                  class="inline-flex items-center gap-1 h-6 px-2 rounded-full text-[10px] font-medium border transition-all"
                  :class="
                    s.id === chat.crm_stage_id
                      ? 'text-white'
                      : 'text-n-slate-11 hover:bg-n-alpha-1 border-n-weak'
                  "
                  :style="
                    s.id === chat.crm_stage_id
                      ? { background: s.color, borderColor: s.color }
                      : {}
                  "
                  :disabled="isMovingStage"
                  @click="pickStage(s)"
                >
                  <span
                    v-if="s.id !== chat.crm_stage_id"
                    class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                    :style="{ background: s.color }"
                  />
                  {{ s.name }}
                </button>
              </div>
            </div>
          </Teleport>
        </div>

        <CardLabels
          v-if="showLabelsSection"
          :conversation-labels="chat.labels"
          class="!mt-0 !mx-0 !mb-0 min-w-0"
        >
          <template v-if="hasSlaPolicyId" #before>
            <SLACardLabel :chat="chat" class="ltr:mr-1 rtl:ml-1" />
          </template>
        </CardLabels>
      </div>
    </div>
  </div>
</template>
