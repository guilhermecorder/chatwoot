<script setup>
import { computed, inject } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import ConversationCard from './widgets/conversation/ConversationCard.vue';
import ConversationCardExpanded from 'dashboard/components-next/Conversation/ConversationCard/ConversationCardExpanded.vue';
// 🖱️ item 384 (04/11): o MENU DO BOTÃO DIREITO do CEVICO (o mesmo da Agenda e
// do CRM) no lugar do menu padrão do Chatwoot — toque longo no celular.
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { vCvMenu } from 'dashboard/composables/useCevicoContextMenu';
import { useCevicoSpaceName } from 'dashboard/composables/useCevicoSpaceName';

const props = defineProps({
  source: { type: Object, required: true },
  teamId: { type: [String, Number], default: 0 },
  label: { type: String, default: '' },
  conversationType: { type: String, default: '' },
  foldersId: { type: [String, Number], default: 0 },
  showAssignee: { type: Boolean, default: false },
  showExpanded: { type: Boolean, default: false },
});
// 🏠 11/11 (LIFE): nome do ambiente da pessoa pelo vocabulário da empresa
const { openSpaceLabel } = useCevicoSpaceName();

const router = useRouter();
const store = useStore();

const selectConversation = inject('selectConversation');
const deSelectConversation = inject('deSelectConversation');
const assignAgent = inject('assignAgent');
const assignLabels = inject('assignLabels');
const removeLabels = inject('removeLabels');
const updateConversationStatus = inject('updateConversationStatus');
const markAsUnread = inject('markAsUnread');
const markAsRead = inject('markAsRead');
const assignPriority = inject('assignPriority');
const isConversationSelected = inject('isConversationSelected');


const currentChat = useMapGetter('getSelectedChat');
const inboxesList = useMapGetter('inboxes/getInboxes');
const activeInbox = useMapGetter('getSelectedInbox');
const accountId = useMapGetter('getCurrentAccountId');

const chatMetadata = computed(() => props.source.meta || {});
const assignee = computed(() => chatMetadata.value.assignee || {});
const senderId = computed(() => chatMetadata.value.sender?.id);

const currentContact = computed(() =>
  senderId.value ? store.getters['contacts/getContact'](senderId.value) : {}
);

const isActiveChat = computed(() => currentChat.value.id === props.source.id);

const inbox = computed(() => {
  const inboxId = props.source.inbox_id;
  return inboxId ? store.getters['inboxes/getInbox'](inboxId) : {};
});

const showInboxName = computed(
  () => !activeInbox.value && inboxesList.value.length > 1
);
const isInboxView = computed(() => !!activeInbox.value);
const showAssigneeForExpandedCard = computed(
  () => props.showExpanded || props.showAssignee
);

const conversationPath = computed(() =>
  frontendURL(
    conversationUrl({
      accountId: accountId.value,
      activeInbox: activeInbox.value,
      id: props.source.id,
      label: props.label,
      teamId: props.teamId,
      conversationType: props.conversationType,
      foldersId: props.foldersId,
    })
  )
);

const onCardClick = e => {
  const path = conversationPath.value;
  if (!path) return;

  if (e.metaKey || e.ctrlKey) {
    e.preventDefault();
    window.open(
      `${window.chatwootConfig.hostURL}${path}`,
      '_blank',
      'noopener,noreferrer'
    );
    return;
  }

  if (isActiveChat.value) return;
  router.push({ path });
};

const onExpandedSelect = checked => {
  if (checked) {
    selectConversation(props.source.id, inbox.value.id);
  } else {
    deSelectConversation(props.source.id, inbox.value.id);
  }
};

// ── 🖱️ item 384: menu do botão direito do CEVICO ───────────────────────
// As ações são as mesmas que a lista já injeta (status, pessoa, etiquetas,
// lida/não lida, prioridade); o que é da casa entra junto: Espaço do
// Paciente, copiar telefone e nome.
const accountLabels = useMapGetter('labels/getLabels');
const copyToClipboard = async (text, okMessage) => {
  if (!text) return;
  try {
    await copyTextToClipboard(String(text));
    useAlert(okMessage);
  } catch {
    useAlert('Não deu para copiar.');
  }
};
const openPatientSpace = () => {
  if (!senderId.value) return;
  router.push(frontendURL(`accounts/${accountId.value}/patient/${senderId.value}`));
};
const assignableAgents = () => {
  const list = store.getters['inboxAssignableAgents/getAssignableAgents'](inbox.value?.id) || [];
  if (!list.length && inbox.value?.id) {
    store.dispatch('inboxAssignableAgents/fetch', [inbox.value.id]).catch(() => {});
  }
  return list;
};
const PRIORITIES = [
  { key: null, label: 'Sem prioridade' },
  { key: 'urgent', label: 'Urgente' },
  { key: 'high', label: 'Alta' },
  { key: 'medium', label: 'Média' },
  { key: 'low', label: 'Baixa' },
];
const cevicoMenu = () => {
  const chat = props.source;
  const contact = currentContact.value || {};
  const status = chat.status;
  const applied = new Set(chat.labels || []);
  const agents = assignableAgents();
  const items = [
    { label: 'Abrir conversa', icon: 'i-lucide-message-circle', hidden: isActiveChat.value, action: () => router.push({ path: conversationPath.value }) },
    { label: openSpaceLabel.value, icon: 'i-lucide-user-round', hidden: !senderId.value, action: openPatientSpace },
    { separator: true },
    { label: 'Marcar como resolvida', icon: 'i-lucide-check-check', hidden: status === 'resolved', action: () => updateConversationStatus(chat.id, 'resolved') },
    { label: 'Reabrir', icon: 'i-lucide-rotate-ccw', hidden: status === 'open', action: () => updateConversationStatus(chat.id, 'open') },
    { label: 'Deixar pendente', icon: 'i-lucide-clock', hidden: status === 'pending', action: () => updateConversationStatus(chat.id, 'pending') },
    { label: 'Marcar como não lida', icon: 'i-lucide-mail', hidden: chat.unread_count > 0, action: () => markAsUnread(chat.id) },
    { label: 'Marcar como lida', icon: 'i-lucide-mail-open', hidden: !(chat.unread_count > 0), action: () => markAsRead(chat.id) },
    { separator: true },
    {
      label: 'Atribuir a',
      icon: 'i-lucide-user-plus',
      hint: assignee.value?.name || 'ninguém',
      children: agents.length
        ? agents.map(a => ({
            label: a.name,
            icon: assignee.value?.id === a.id ? 'i-lucide-check' : 'i-lucide-user',
            action: () => assignAgent(a, [chat.id]),
          }))
        : [{ label: 'Carregando a equipe…', disabled: true }],
    },
    {
      label: 'Etiquetas',
      icon: 'i-lucide-tag',
      hint: applied.size ? `${applied.size}` : '',
      children: (accountLabels.value || []).map(l => ({
        label: l.title,
        icon: applied.has(l.title) ? 'i-lucide-check' : 'i-lucide-tag',
        action: () => (applied.has(l.title) ? removeLabels([l.title], [chat.id]) : assignLabels([l.title], [chat.id])),
      })),
    },
    {
      label: 'Prioridade',
      icon: 'i-lucide-flag',
      hint: PRIORITIES.find(p => p.key === (chat.priority || null))?.label || '',
      children: PRIORITIES.map(p => ({
        label: p.label,
        icon: (chat.priority || null) === p.key ? 'i-lucide-check' : 'i-lucide-flag',
        action: () => assignPriority(p.key, chat.id),
      })),
    },
    { separator: true },
    { label: 'Copiar telefone', icon: 'i-lucide-phone', hint: contact.phone_number || '', hidden: !contact.phone_number, action: () => copyToClipboard(contact.phone_number, 'Telefone copiado ✓') },
    { label: 'Copiar nome', icon: 'i-lucide-copy', hidden: !contact.name, action: () => copyToClipboard(contact.name, 'Nome copiado ✓') },
  ];
  return {
    title: contact.name || 'Conversa',
    subtitle: [inbox.value?.name, contact.phone_number].filter(Boolean).join(' · '),
    items,
  };
};
</script>

<template>
  <!-- 🖱️ item 384: botão direito / toque longo = menu do CEVICO (display: contents não mexe no layout) -->
  <div v-cv-menu="cevicoMenu" class="contents">
  <!-- Expanded layout: wide screen + expanded setting -->
  <ConversationCardExpanded
    v-if="showExpanded"
    :chat="source"
    :current-contact="currentContact"
    :assignee="assignee"
    :inbox="inbox"
    :selected="isConversationSelected(source.id)"
    :is-active-chat="isActiveChat"
    :show-assignee="showAssigneeForExpandedCard"
    :show-inbox-name="showInboxName"
    :is-inbox-view="isInboxView"
    @select-conversation="onExpandedSelect"
    @de-select-conversation="onExpandedSelect"
    @click="onCardClick"
  />

  <!-- Default (condensed) layout -->
  <ConversationCard
    v-else
    :chat="source"
    :current-contact="currentContact"
    :assignee="assignee"
    :inbox="inbox"
    :selected="isConversationSelected(source.id)"
    :is-active-chat="isActiveChat"
    :show-assignee="showAssignee"
    :show-inbox-name="showInboxName"
    @click="onCardClick"
    @select-conversation="selectConversation"
    @de-select-conversation="deSelectConversation"
  />
  </div>
</template>
