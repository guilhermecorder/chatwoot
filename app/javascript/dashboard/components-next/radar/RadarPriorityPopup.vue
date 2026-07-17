<script setup>
// 🚨→😊 Popup "prioridade máxima" do Radar de Oportunidades.
// Quando a atendente está online e um paciente quente espera há 20+ min,
// a janela salta com animação de gênio da lâmpada (macOS). Não dá para
// ignorar: clicar fora treme a janela, mostra "Essa é a prioridade
// máxima. 😊", o card fica azulzinho e o botão Atender agora pulsa —
// cobrança amigável e bem-humorada, do jeito CEVICO.
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';

const router = useRouter();
const route = useRoute();
const accountId = useMapGetter('getCurrentAccountId');

const alert = ref(null);
const calmed = ref(false); // depois da 1ª tentativa de fuga: azul + recado
const shaking = ref(false);
const leaving = ref(false);
let timer = null;

const ACK_KEY = 'cevico_radar_ack'; // conversa atendida → não repete por 15 min
const ackMap = () => {
  try {
    return JSON.parse(localStorage.getItem(ACK_KEY) || '{}');
  } catch {
    return {};
  }
};
const isAcked = id => {
  const at = ackMap()[id];
  return at && Date.now() - at < 15 * 60 * 1000;
};
const ack = id => {
  const map = ackMap();
  map[id] = Date.now();
  localStorage.setItem(ACK_KEY, JSON.stringify(map));
};

// no Meu Painel os avisos completos já estão na tela — lá o popup não
// aparece; e se estava aberto, ele some: o aviso fez o serviço dele
const onMeuPainel = () => route.name === 'inicio_home';

const dismissQuietly = () => {
  if (!alert.value) return;
  ack(alert.value.conversation_id);
  leaving.value = true;
  setTimeout(() => {
    alert.value = null;
    leaving.value = false;
    calmed.value = false;
  }, 350);
};

watch(
  () => route.name,
  () => {
    if (onMeuPainel()) dismissQuietly();
  }
);

const poll = async () => {
  if (document.visibilityState !== 'visible' || alert.value || onMeuPainel())
    return;
  try {
    const { data } = await CrmAPI.radarPing();
    const a = data.alert;
    if (a && !isAcked(a.conversation_id)) {
      calmed.value = false;
      alert.value = a;
    }
  } catch {
    // silêncio: o popup nunca pode atrapalhar o sistema
  }
};

onMounted(() => {
  setTimeout(poll, 4000); // respiro após o login
  timer = setInterval(poll, 90 * 1000);
});
onBeforeUnmount(() => clearInterval(timer));

// tentativa de clicar em outra coisa: tremidinha + recado + vira azul
const blockEscape = () => {
  shaking.value = true;
  calmed.value = true;
  setTimeout(() => {
    shaking.value = false;
  }, 450);
};

const waitingLabel = computed(() => {
  const m = alert.value?.waiting_minutes;
  if (!m) return '';
  return m >= 60 ? `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}` : `${m} min`;
});

const attendNow = () => {
  const id = alert.value?.conversation_id;
  if (!id) return;
  ack(id);
  leaving.value = true;
  setTimeout(() => {
    alert.value = null;
    leaving.value = false;
    calmed.value = false;
  }, 350);
  router.push(`/app/accounts/${accountId.value}/conversations/${id}`);
};
</script>

<template>
  <Teleport to="body">
    <div v-if="alert" class="fixed inset-0 z-[9998]" @click="blockEscape" />
    <div
      v-if="alert"
      class="cevico-genie fixed bottom-6 right-6 z-[9999] w-[340px] rounded-2xl text-white shadow-2xl overflow-hidden"
      :class="[shaking ? 'cevico-shake' : '', leaving ? 'cevico-genie-out' : '']"
      :style="{
        background: calmed
          ? 'linear-gradient(135deg, #0369A1, #2563EB)'
          : 'linear-gradient(135deg, #059669, #4ADE80)',
        transition: 'background .6s ease',
      }"
    >
      <div class="p-4">
        <div class="flex items-center gap-2 mb-1.5">
          <span class="i-lucide-radar text-lg" />
          <p class="text-sm font-bold flex-1">
            {{ calmed ? 'Essa é a prioridade máxima. 😊' : 'Paciente quente esperando!' }}
          </p>
        </div>
        <p class="text-sm font-semibold">
          {{ alert.contact_name }}
          <span class="opacity-80 font-normal">· esperando há {{ waitingLabel }}</span>
        </p>
        <p v-if="alert.motivo" class="text-xs opacity-90 mt-1 leading-relaxed">{{ alert.motivo }}</p>
        <p v-if="alert.acao" class="text-xs mt-1.5 bg-white/15 rounded-lg px-2.5 py-1.5 leading-relaxed">
          💡 {{ alert.acao }}
        </p>
        <button
          class="mt-3 w-full py-2.5 rounded-xl font-bold text-sm bg-white shadow"
          :class="calmed ? 'text-blue-700 cevico-btn-pulse' : 'text-emerald-600'"
          @click.stop="attendNow"
        >
          Atender agora →
        </button>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* gênio da lâmpada: nasce esticado do canto e se materializa */
.cevico-genie {
  transform-origin: 95% 120%;
  animation: cevicoGenieIn 0.55s cubic-bezier(0.22, 1.1, 0.35, 1);
}
@keyframes cevicoGenieIn {
  0% {
    transform: translate(30%, 55%) scale(0.06, 0.4) skewX(-14deg);
    opacity: 0;
    border-radius: 50%;
  }
  55% {
    transform: translate(0, -2%) scale(1.05, 0.9) skewX(3deg);
    opacity: 1;
  }
  80% {
    transform: scale(0.98, 1.03);
  }
  100% {
    transform: none;
  }
}
.cevico-genie-out {
  animation: cevicoGenieOut 0.35s ease forwards;
}
@keyframes cevicoGenieOut {
  to {
    transform: translate(25%, 50%) scale(0.1, 0.3) skewX(-10deg);
    opacity: 0;
  }
}
/* tremidinha simpática quando tentam fugir */
.cevico-shake {
  animation: cevicoShake 0.45s ease;
}
@keyframes cevicoShake {
  0%, 100% { margin-right: 0; }
  20% { margin-right: 10px; }
  40% { margin-right: -8px; }
  60% { margin-right: 6px; }
  80% { margin-right: -4px; }
}
/* botão pulsando depois do recado */
.cevico-btn-pulse {
  animation: cevicoBtnPulse 1.2s ease-in-out infinite;
}
@keyframes cevicoBtnPulse {
  0%, 100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.55); }
  50% { transform: scale(1.04); box-shadow: 0 0 0 9px rgba(255, 255, 255, 0); }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-genie, .cevico-shake, .cevico-btn-pulse, .cevico-genie-out { animation: none; }
}
</style>
