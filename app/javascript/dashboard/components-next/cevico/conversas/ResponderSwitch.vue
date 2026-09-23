<script setup>
// 🤖 CEVICO item 212 (23/09): a CHAVINHA do Atendente IA no topo da conversa
// (antes era um botão no painel do paciente). Liga/desliga a IA SÓ para esta
// conversa; quando alguém da equipe responde, a IA pausa sozinha e a
// chavinha apaga na hora (o estado vem junto com a conversa pelo websocket).
import { ref, computed, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  conversationId: { type: Number, default: null },
  chat: { type: Object, default: () => ({}) },
});

const state = ref(null);
const isToggling = ref(false);

const load = async () => {
  if (!props.conversationId) {
    state.value = null;
    return;
  }
  try {
    const { data } = await CrmAPI.getResponderState(props.conversationId);
    state.value = data.responder;
  } catch {
    state.value = null;
  }
};
watch(() => props.conversationId, load, { immediate: true });

// a conversa no store muda (humano respondeu → pausou; 👍 → religou):
// espelha sem precisar buscar de novo
watch(
  () => props.chat?.additional_attributes?.cevico_atendente_wa,
  v => {
    if (!state.value) return;
    state.value = {
      ...state.value,
      paused: v?.paused === true,
      reason: v?.reason || null,
      by: v?.by || null,
    };
  },
  { deep: true }
);

const paused = computed(() => state.value?.paused === true);
const live = computed(() => state.value?.live === true);
const label = computed(() => {
  if (paused.value) return 'IA desligada';
  return live.value ? 'IA ligada' : 'IA em sombra';
});
const REASONS = {
  humano_assumiu: 'pausou sozinha quando alguém da equipe respondeu',
  chamar_humano: 'o agente pediu atendimento humano',
  chamou_humano: 'o agente pediu atendimento humano',
  botao: 'desligada pela chavinha',
  teto_diario: 'limite de mensagens do dia',
};
const hint = computed(() => {
  const s = state.value;
  if (!s) return '';
  if (s.paused) {
    const why = REASONS[s.reason] || s.reason_text || 'pausada';
    return `Atendente IA desligada nesta conversa: ${why}${s.by ? ` (${s.by})` : ''}. Toque para ligar de novo.`;
  }
  return live.value
    ? 'Atendente IA respondendo sozinha nesta conversa. Qualquer mensagem sua pausa; toque para desligar.'
    : 'Atendente IA só anota o que responderia (modo sombra). Toque para pausar até isso.';
});

const toggle = async () => {
  if (isToggling.value || !state.value) return;
  isToggling.value = true;
  try {
    const { data } = await CrmAPI.toggleResponder(
      props.conversationId,
      !paused.value
    );
    state.value = data.responder;
    useAlert(
      data.responder.paused
        ? 'Atendente IA desligada nesta conversa.'
        : 'Atendente IA ligada nesta conversa.'
    );
  } catch {
    useAlert('Não deu para mudar o Atendente IA.');
  } finally {
    isToggling.value = false;
  }
};
</script>

<template>
  <button
    v-if="state?.available"
    type="button"
    class="cv-ia"
    :class="{
      'cv-ia-on': !paused && live,
      'cv-ia-shadow': !paused && !live,
      'cv-ia-off': paused,
    }"
    :title="hint"
    :aria-pressed="!paused"
    :disabled="isToggling"
    @click="toggle"
  >
    <span
      class="cv-ia-icon"
      :class="paused ? 'i-lucide-bot-off' : 'i-lucide-bot'"
    />
    <span class="cv-ia-label">{{ label }}</span>
    <span class="cv-ia-switch" :class="{ 'cv-ia-switch-on': !paused }" />
  </button>
</template>
