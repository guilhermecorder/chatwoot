<script setup>
// 💬 item 298: o popup de conversa do paciente, montado uma vez no Dashboard.
// Quem abre é o openPatientChat() (Agenda, Espaço do Paciente, botão direito).
import ConversationChatModal from 'dashboard/routes/dashboard/crm/components/ConversationChatModal.vue';
import { useCevicoPatientChat } from 'dashboard/composables/useCevicoPatientChat';

const { state, closePatientChat } = useCevicoPatientChat();
const onStarted = card => {
  state.card = { ...state.card, ...card };
};
</script>

<template>
  <ConversationChatModal
    v-if="state.card"
    :key="`${state.card.contact_id}-${state.card.last_conversation_id}`"
    :contact="state.card"
    :pipeline-id="state.card.pipeline_id"
    :stages="state.stages"
    @close="closePatientChat"
    @conversation-started="onStarted"
  />
</template>
