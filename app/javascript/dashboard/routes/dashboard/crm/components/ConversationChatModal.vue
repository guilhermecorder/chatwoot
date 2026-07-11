<script setup>
import { ref, computed, onMounted, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import MessageApi from 'dashboard/api/inbox/message';
import ConversationApi from 'dashboard/api/inbox/conversation';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contact: { type: Object, required: true }, // card do CRM (contact_json)
});

const emit = defineEmits(['close', 'replied']);

const { t } = useI18n();

const conversationId = computed(() => props.contact.last_conversation_id);

const messages = ref([]);
const isLoading = ref(true);
const isLoadingMore = ref(false);
const hasMore = ref(false);
const isSending = ref(false);
const replyText = ref('');
const messagesEl = ref(null);

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

      <!-- Reply box -->
      <div class="border-t border-n-weak p-3 flex-shrink-0">
        <div class="flex items-end gap-2">
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
