<script setup>
import { ref, computed, onMounted, nextTick } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import MessageApi from 'dashboard/api/inbox/message';
import ConversationApi from 'dashboard/api/inbox/conversation';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TemplatesPicker from 'dashboard/components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue';
import WhatsAppTemplateReply from 'dashboard/components/widgets/conversation/WhatsappTemplates/WhatsAppTemplateReply.vue';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';
import { onClickOutside } from '@vueuse/core';

const props = defineProps({
  contact: { type: Object, required: true }, // card do CRM (contact_json)
});

const emit = defineEmits(['close', 'replied', 'resolved']);

const { t } = useI18n();
const store = useStore();

const conversationId = computed(() => props.contact.last_conversation_id);
const inboxId = computed(() => props.contact.last_conversation?.inbox_id);
const isWhatsapp = computed(
  () => props.contact.last_conversation?.channel_type === 'Channel::Whatsapp'
);

const messages = ref([]);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const hasMore = ref(false);
const isSending = ref(false);
const replyText = ref('');
const messagesEl = ref(null);

// status da conversa (open/resolved/pending/snoozed)
const convStatus = ref(props.contact.last_conversation?.status || 'open');
const isResolving = ref(false);

// templates (remarketing)
const showTemplates = ref(false);
const selectedTemplate = ref(null);

// emoji picker
const showEmoji = ref(false);
const emojiWrap = ref(null);
onClickOutside(emojiWrap, () => { showEmoji.value = false; });
const onInsertEmoji = e => {
  replyText.value += e.emoji ?? e.value ?? '';
};

// message_type: 0 incoming | 1 outgoing | 2 activity | 3 template
const isIncoming = m => m.message_type === 0;
const isActivity = m => m.message_type === 2;

const toDate = ts =>
  typeof ts === 'number' ? new Date(ts * 1000) : new Date(ts);

const formatTime = ts => {
  const d = toDate(ts);
  const today = new Date();
  const sameDay = d.toDateString() === today.toDateString();
  const time = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  if (sameDay) return time;
  return `${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${time}`;
};

const attachmentLabel = fileType => {
  const map = {
    image: '🖼️ Imagem',
    audio: '🎧 Áudio',
    video: '🎬 Vídeo',
    file: '📎 Arquivo',
    location: '📍 Localização',
    contact: '👤 Contato',
  };
  return map[fileType] ?? '📎 Anexo';
};

const scrollToBottom = async () => {
  await nextTick();
  if (messagesEl.value) messagesEl.value.scrollTop = messagesEl.value.scrollHeight;
};

const loadMessages = async () => {
  isLoading.value = true;
  try {
    const { data } = await MessageApi.getPreviousMessages({
      conversationId: conversationId.value,
    });
    const payload = data.payload ?? [];
    messages.value = payload.filter(m => !m.private);
    hasMore.value = payload.length >= 20;
    await scrollToBottom();
    // marca como lida (zera "não lidas" na caixa de entrada e no card)
    ConversationApi.markMessageRead({ id: conversationId.value }).catch(() => {});
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isLoading.value = false;
  }
};

const loadMore = async () => {
  if (isLoadingMore.value || !messages.value.length) return;
  isLoadingMore.value = true;
  try {
    const { data } = await MessageApi.getPreviousMessages({
      conversationId: conversationId.value,
      before: messages.value[0].id,
    });
    const payload = (data.payload ?? []).filter(m => !m.private);
    messages.value = [...payload, ...messages.value];
    hasMore.value = payload.length >= 20;
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isLoadingMore.value = false;
  }
};

const sendReply = async () => {
  const content = replyText.value.trim();
  if (!content || isSending.value) return;
  isSending.value = true;
  try {
    const { data } = await MessageApi.create({
      conversationId: conversationId.value,
      message: content,
      private: false,
    });
    messages.value.push(data);
    replyText.value = '';
    await scrollToBottom();
    emit('replied');
  } catch {
    useAlert(t('CRM.CHAT.SEND_ERROR'));
  } finally {
    isSending.value = false;
  }
};

const onKeydown = e => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendReply();
  }
};

// ── Resolver / reabrir conversa ────────────────────────────
const isResolved = computed(() => convStatus.value === 'resolved');

const toggleResolve = async () => {
  if (isResolving.value) return;
  isResolving.value = true;
  const nextStatus = isResolved.value ? 'open' : 'resolved';
  try {
    await ConversationApi.toggleStatus({
      conversationId: conversationId.value,
      status: nextStatus,
    });
    convStatus.value = nextStatus;
    useAlert(
      nextStatus === 'resolved' ? t('CRM.CHAT.RESOLVED') : t('CRM.CHAT.REOPENED')
    );
    emit('resolved', { conversationId: conversationId.value, status: nextStatus });
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isResolving.value = false;
  }
};

// ── Templates (remarketing) ────────────────────────────────
const openTemplates = () => {
  selectedTemplate.value = null;
  showTemplates.value = true;
  // garante que as inboxes/templates estão carregadas para o picker
  store.dispatch('inboxes/get').catch(() => {});
};

const onTemplateSelect = template => {
  selectedTemplate.value = template;
};

const onTemplateSend = async payload => {
  if (isSending.value) return;
  isSending.value = true;
  try {
    const { data } = await MessageApi.create({
      conversationId: conversationId.value,
      message: payload.message,
      templateParams: payload.templateParams,
      private: false,
    });
    messages.value.push(data);
    showTemplates.value = false;
    selectedTemplate.value = null;
    await scrollToBottom();
    // enviar template reabre a conversa no fluxo de atendimento
    if (isResolved.value) convStatus.value = 'open';
    emit('replied');
  } catch {
    useAlert(t('CRM.CHAT.SEND_ERROR'));
  } finally {
    isSending.value = false;
  }
};

onMounted(loadMessages);
</script>

<template>
  <div
    class="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-lg h-[85vh] flex flex-col">
      <!-- Header -->
      <div class="flex items-center gap-3 px-4 py-3 border-b border-n-weak flex-shrink-0">
        <div class="w-9 h-9 rounded-full bg-n-brand flex items-center justify-center text-white text-xs font-semibold flex-shrink-0 overflow-hidden">
          <img v-if="contact.avatar_url" :src="contact.avatar_url" class="w-9 h-9 object-cover" />
          <span v-else>{{ contact.name?.[0]?.toUpperCase() ?? '?' }}</span>
        </div>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12 truncate">{{ contact.name }}</p>
          <p class="text-xs text-n-slate-10 truncate">
            {{ contact.last_conversation?.inbox_name }} · #{{ conversationId }}
          </p>
        </div>
        <!-- Status resolvido -->
        <span
          v-if="isResolved"
          class="text-[10px] font-medium px-2 py-0.5 rounded-full bg-green-500/15 text-green-600 flex-shrink-0"
        >
          {{ $t('CRM.CHAT.STATUS_RESOLVED') }}
        </span>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl flex-shrink-0"
          @click="emit('close')"
        />
      </div>

      <!-- Messages -->
      <div
        ref="messagesEl"
        class="flex-1 overflow-y-auto px-4 py-3 space-y-2 min-h-0 bg-n-alpha-1"
        style="scrollbar-width:thin;"
      >
        <div v-if="isLoading" class="flex justify-center items-center h-full">
          <Spinner :size="28" class="text-n-brand" />
        </div>

        <template v-else>
          <div v-if="hasMore" class="flex justify-center pb-1">
            <button
              class="text-xs text-n-brand hover:underline disabled:opacity-50"
              :disabled="isLoadingMore"
              @click="loadMore"
            >
              {{ isLoadingMore ? $t('CRM.MODAL.LOADING') : $t('CRM.CHAT.LOAD_MORE') }}
            </button>
          </div>

          <div v-if="!messages.length" class="flex flex-col items-center justify-center h-full text-n-slate-10">
            <span class="i-lucide-message-square-off text-3xl mb-2" />
            <p class="text-sm">{{ $t('CRM.MODAL.NO_MESSAGES') }}</p>
          </div>

          <template v-for="m in messages" :key="m.id">
            <!-- Atividade (centralizada) -->
            <div v-if="isActivity(m)" class="flex justify-center">
              <span class="text-[11px] text-n-slate-9 bg-n-alpha-2 rounded-full px-2.5 py-0.5 text-center">
                {{ m.content }}
              </span>
            </div>

            <!-- Bolha -->
            <div v-else class="flex" :class="isIncoming(m) ? 'justify-start' : 'justify-end'">
              <div
                class="max-w-[80%] rounded-2xl px-3 py-2"
                :class="isIncoming(m)
                  ? 'bg-n-solid-2 border border-n-weak text-n-slate-12 rounded-bl-sm'
                  : 'bg-n-brand text-white rounded-br-sm'"
              >
                <p v-if="m.content" class="text-sm whitespace-pre-wrap break-words leading-relaxed">{{ m.content }}</p>
                <div v-if="m.attachments?.length" class="space-y-1" :class="m.content ? 'mt-1.5' : ''">
                  <a
                    v-for="att in m.attachments"
                    :key="att.id"
                    :href="att.data_url"
                    target="_blank"
                    rel="noopener"
                    class="block text-xs underline"
                    :class="isIncoming(m) ? 'text-n-brand' : 'text-white/90'"
                  >
                    {{ attachmentLabel(att.file_type) }}
                  </a>
                </div>
                <p
                  class="text-[10px] mt-1 text-right"
                  :class="isIncoming(m) ? 'text-n-slate-9' : 'text-white/70'"
                >
                  {{ formatTime(m.created_at) }}
                </p>
              </div>
            </div>
          </template>
        </template>
      </div>

      <!-- ── Painel de Templates (remarketing) ── -->
      <div v-if="showTemplates" class="border-t border-n-weak p-3 flex-shrink-0 max-h-[55%] overflow-y-auto">
        <div class="flex items-center justify-between mb-2">
          <p class="text-sm font-semibold text-n-slate-12 flex items-center gap-1.5">
            <span class="i-lucide-message-square-text text-base text-n-brand" />
            {{ selectedTemplate ? $t('CRM.CHAT.TEMPLATE_FILL') : $t('CRM.CHAT.TEMPLATES_TITLE') }}
          </p>
          <button
            class="text-xs text-n-slate-10 hover:text-n-slate-12 flex items-center gap-1"
            @click="showTemplates = false; selectedTemplate = null"
          >
            <span class="i-lucide-x text-sm" />
            {{ $t('CRM.CANCEL') }}
          </button>
        </div>

        <WhatsAppTemplateReply
          v-if="selectedTemplate"
          :template="selectedTemplate"
          @send-message="onTemplateSend"
          @reset-template="selectedTemplate = null"
        />
        <TemplatesPicker
          v-else
          :inbox-id="inboxId"
          @on-select="onTemplateSelect"
        />
      </div>

      <!-- Reply box -->
      <div v-else class="border-t border-n-weak p-3 flex-shrink-0">
        <!-- Ações: resolver + templates -->
        <div class="flex items-center gap-2 mb-2">
          <button
            class="flex items-center gap-1.5 text-xs px-2.5 py-1.5 rounded-lg border transition-colors"
            :class="isResolved
              ? 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
              : 'border-green-500/40 text-green-600 hover:bg-green-500/10'"
            :disabled="isResolving"
            @click="toggleResolve"
          >
            <span
              :class="isResolving ? 'i-lucide-loader-2 animate-spin' : (isResolved ? 'i-lucide-rotate-ccw' : 'i-lucide-check-check')"
              class="text-sm"
            />
            {{ isResolved ? $t('CRM.CHAT.REOPEN') : $t('CRM.CHAT.RESOLVE') }}
          </button>

          <button
            v-if="isWhatsapp"
            class="flex items-center gap-1.5 text-xs px-2.5 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
            @click="openTemplates"
          >
            <span class="i-lucide-message-square-text text-sm" />
            {{ $t('CRM.CHAT.TEMPLATES') }}
          </button>
        </div>

        <div class="flex items-end gap-2">
          <!-- Emoji -->
          <div ref="emojiWrap" class="relative flex-shrink-0">
            <button
              class="flex items-center justify-center w-10 h-10 rounded-xl border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
              :title="$t('CRM.CHAT.EMOJI')"
              @click="showEmoji = !showEmoji"
            >
              <span class="i-lucide-smile text-base" />
            </button>
            <div v-if="showEmoji" class="absolute bottom-12 left-0 z-20">
              <EmojiPicker @select="onInsertEmoji" />
            </div>
          </div>
          <textarea
            v-model="replyText"
            rows="2"
            class="flex-1 border border-n-weak rounded-xl px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 resize-none focus:outline-none focus:border-n-brand"
            :placeholder="$t('CRM.CHAT.REPLY_PLACEHOLDER')"
            @keydown="onKeydown"
          />
          <button
            class="flex items-center justify-center w-10 h-10 rounded-xl bg-n-brand text-white hover:bg-n-brand/90 transition-colors disabled:opacity-50 flex-shrink-0"
            :disabled="!replyText.trim() || isSending"
            :title="$t('CRM.CHAT.SEND')"
            @click="sendReply"
          >
            <span :class="isSending ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-send'" class="text-base" />
          </button>
        </div>
        <p class="text-[10px] text-n-slate-9 mt-1.5">
          {{ $t('CRM.CHAT.OFFICIAL_NOTE', { inbox: contact.last_conversation?.inbox_name ?? '' }) }}
        </p>
      </div>
    </div>
  </div>
</template>
