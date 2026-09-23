<script setup>
// 🍎 item 215 (23/09): o cartão do paciente no design Apple — o mesmo cartão
// das Conversas (branco, 16 px, fio quase invisível que fica azul royal no
// hover), "cara" com o degradê fixo da pessoa quando não há foto, etiquetas
// .cv-tag (item 212), pílula âmbar de "aguardando", bolinha da caixa na cor
// oficial e ações redondas (Espaço do Paciente, conversa). Comportamento
// idêntico ao cartão antigo: clique abre a ficha, botões emitem os eventos.
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { frontendURL } from 'dashboard/helper/URLHelper';
import PatientSpaceIcon from 'dashboard/routes/dashboard/patient/PatientSpaceIcon.vue';
import { personGradient } from 'dashboard/helper/cevicoPersonGradient';
import { inboxSolidFor } from 'dashboard/helper/cevicoInboxColors.js';
import { relativeTime } from '../helpers';

const props = defineProps({
  contact: { type: Object, required: true },
});

const emit = defineEmits(['click', 'openChat']);

const route = useRoute();
const router = useRouter();
// Espaço do Paciente: a página única com toda a jornada
const openPatient = () => {
  router.push(frontendURL(`accounts/${route.params.accountId}/patient/${props.contact.contact_id}`));
};

const { isAdmin } = useAdmin();
const accountLabels = useMapGetter('labels/getLabels');
const accountInboxes = useMapGetter('inboxes/getInboxes');

const unreadCount = computed(() => props.contact.last_conversation?.unread_count ?? 0);
const isAwaitingReply = computed(() => props.contact.last_conversation?.awaiting_reply ?? false);
const waitingTime = computed(() => relativeTime(props.contact.last_conversation?.waiting_since));
const unreadPreview = computed(() =>
  unreadCount.value > 0 ? props.contact.last_conversation?.last_message : null
);

const initials = computed(() => {
  if (!props.contact.name) return '?';
  return props.contact.name.split(' ').map(w => w[0]).slice(0, 2).join('').toUpperCase();
});
const faceStyle = computed(() => ({ background: personGradient(props.contact.name) }));

const labelColorMap = computed(() => {
  const map = {};
  accountLabels.value.forEach(l => { map[l.title] = l.color; });
  return map;
});

const visibleLabels = computed(() => props.contact.labels?.slice(0, 4) ?? []);
const extraLabels = computed(() => Math.max(0, (props.contact.labels?.length ?? 0) - 4));

const entryDate = computed(() => {
  if (!props.contact.crm_created_at) return null;
  return new Date(props.contact.crm_created_at).toLocaleDateString('pt-BR', {
    day: '2-digit', month: '2-digit', year: '2-digit',
  });
});

const lastActivity = computed(() => relativeTime(props.contact.last_activity_at));
const inboxName = computed(() => props.contact.last_conversation?.inbox_name || '');
const inboxDot = computed(() =>
  inboxName.value ? inboxSolidFor(accountInboxes.value || [], inboxName.value) : '#94a3b8'
);

const channelIcon = (channelType) => {
  const map = {
    'Channel::Whatsapp':    'i-lucide-message-circle',
    'Channel::WebWidget':   'i-lucide-globe',
    'Channel::Email':       'i-lucide-mail',
    'Channel::Sms':         'i-lucide-smartphone',
    'Channel::TwilioSms':   'i-lucide-smartphone',
    'Channel::Api':         'i-lucide-code',
    'Channel::TelegramBot': 'i-lucide-send',
    'Channel::FacebookPage':'i-lucide-message-square',
    'Channel::Instagram':   'i-lucide-instagram',
  };
  return map[channelType] ?? 'i-lucide-inbox';
};
</script>

<template>
  <div
    class="cv-crm-card cursor-pointer select-none"
    :class="unreadCount > 0 ? 'cv-crm-card-unread' : ''"
    @click="emit('click', contact)"
  >
    <!-- Identidade: cara (foto ou degradê da pessoa), nome inteiro, telefone -->
    <div class="flex items-center gap-2.5">
      <div
        class="w-9 h-9 rounded-full flex items-center justify-center text-white text-[11px] font-bold flex-shrink-0 overflow-hidden"
        :style="faceStyle"
      >
        <img v-if="contact.avatar_url" :src="contact.avatar_url" class="w-9 h-9 rounded-full object-cover" />
        <span v-else>{{ initials }}</span>
      </div>
      <div class="flex-1 min-w-0">
        <p class="cv-crm-card-name">{{ contact.name }}</p>
        <p v-if="contact.phone_number" class="cv-crm-card-sub truncate">{{ contact.phone_number }}</p>
      </div>
      <!-- Não lidas: a bolinha verde do WhatsApp -->
      <span
        v-if="unreadCount > 0"
        class="cv-crm-badge flex-shrink-0"
        :title="$t('CRM.CARD.UNREAD', { count: unreadCount })"
      >
        {{ unreadCount > 9 ? '9+' : unreadCount }}
      </span>
    </div>

    <!-- Aguardando resposta -->
    <div v-if="isAwaitingReply" class="mt-2">
      <span class="cv-crm-wait">
        <span class="i-lucide-clock text-[11px]" />
        {{ $t('CRM.CARD.AWAITING_REPLY') }}<template v-if="waitingTime"> · {{ waitingTime }}</template>
      </span>
    </div>

    <!-- Prévia da última mensagem do paciente (quando há não lidas) -->
    <div v-if="unreadPreview" class="cv-crm-preview">
      <p class="line-clamp-2">{{ unreadPreview }}</p>
    </div>

    <!-- Etiquetas no design Apple (tinta da própria cor) -->
    <div v-if="visibleLabels.length" class="flex flex-wrap gap-1 mt-2">
      <span
        v-for="label in visibleLabels"
        :key="label"
        class="cv-tag"
        :style="{ '--lb': labelColorMap[label] ?? '#6B7280' }"
      >
        <span class="cv-tag-dot" />
        <span class="truncate">{{ label }}</span>
      </span>
      <span v-if="extraLabels > 0" class="cv-tag cv-tag-more">+{{ extraLabels }}</span>
    </div>

    <!-- Valor (só admin vê valores) -->
    <div v-if="isAdmin && contact.value" class="mt-1.5">
      <span class="cv-crm-value">
        R$&nbsp;{{ Number(contact.value).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
      </span>
    </div>

    <!-- Caixa (bolinha na cor oficial) + responsável -->
    <div class="flex items-center justify-between mt-2 gap-1">
      <div
        v-if="inboxName"
        class="cv-crm-meta flex items-center gap-1.5 min-w-0"
        :title="`Última conversa pela caixa ${inboxName}`"
      >
        <span class="cv-crm-inbox-dot" :style="{ background: inboxDot }" />
        <span :class="channelIcon(contact.last_conversation.channel_type)" class="text-[11px] flex-shrink-0" />
        <span class="truncate">{{ inboxName }}</span>
      </div>
      <span v-if="contact.assignee" class="cv-crm-meta flex items-center gap-1 flex-shrink-0 ml-auto">
        <span class="i-lucide-user text-[10px]" />
        <span>{{ contact.assignee.name }}</span>
      </span>
    </div>

    <!-- Data de entrada (esquerda) + última atividade + ações (direita) -->
    <div class="flex items-center justify-between mt-1.5 gap-1">
      <span v-if="entryDate" class="cv-crm-meta" title="Entrou no funil">{{ entryDate }}</span>
      <span class="flex items-center gap-1.5 ml-auto">
        <span v-if="lastActivity" class="cv-crm-meta">{{ lastActivity }}</span>
        <button
          class="cv-crm-act cv-crm-act-plain"
          title="Espaço do Paciente"
          @click.stop="openPatient"
        >
          <PatientSpaceIcon :size="22" />
        </button>
        <button
          class="cv-crm-act"
          :class="contact.last_conversation_id ? '' : 'cv-crm-act-off'"
          :title="contact.last_conversation_id ? $t('CRM.CHAT.OPEN') : $t('CRM.CHAT.START_TITLE')"
          @click.stop="emit('openChat', contact)"
        >
          <span class="i-lucide-message-circle-more text-base" />
        </button>
      </span>
    </div>
  </div>
</template>
