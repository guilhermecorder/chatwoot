<script setup>
// 🚨→😊 Popup "prioridade máxima" do Radar de Oportunidades.
// Quando a atendente está online e um paciente quente espera há 20+ min,
// a janela salta com animação de gênio da lâmpada (macOS). Não dá para
// ignorar: clicar fora treme a janela, mostra "Essa é a prioridade
// máxima. 😊", o card fica azulzinho e o botão Atender agora pulsa —
// cobrança amigável e bem-humorada, do jeito CEVICO.
// 🔓 12/11/2026 (LIFE, pedido do Guilherme: "está atrapalhando o Fernando"): a janela NÃO bloqueia mais a
// tela (dá para clicar em tudo e abrir outras abas). Fica só a janelinha no canto, PULSANDO, e a cor muda
// com a espera: verde até 15 min, amarela até 30 min, vermelha pulsando forte depois de 30 min.
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';

const router = useRouter();
const route = useRoute();
const accountId = useMapGetter('getCurrentAccountId');

const alert = ref(null);
const leaving = ref(false);
let timer = null;
// relógio da espera: conta a partir do que o servidor disse no aviso
const shownAt = ref(0);
const now = ref(Date.now());
let clock = null;

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
      shownAt.value = Date.now();
      alert.value = a;
    }
  } catch {
    // silêncio: o popup nunca pode atrapalhar o sistema
  }
};

onMounted(() => {
  setTimeout(poll, 4000); // respiro após o login
  timer = setInterval(poll, 90 * 1000);
  clock = setInterval(() => {
    now.value = Date.now();
  }, 30 * 1000);
});
onBeforeUnmount(() => {
  clearInterval(timer);
  clearInterval(clock);
});

// minutos de espera agora (o do aviso + o tempo que a janelinha já está na tela)
const waitingNow = computed(() => {
  const base = Number(alert.value?.waiting_minutes) || 0;
  return base + Math.max(0, Math.floor((now.value - shownAt.value) / 60000));
});
// verde → amarelo (15 min) → vermelho pulsando forte (30 min)
const level = computed(() => {
  if (waitingNow.value >= 30) return 'red';
  if (waitingNow.value >= 15) return 'amber';
  return 'green';
});
const BACKGROUND = {
  green: 'linear-gradient(135deg, #059669, #4ADE80)',
  amber: 'linear-gradient(135deg, #D97706, #FBBF24)',
  red: 'linear-gradient(135deg, #B91C1C, #F87171)',
};
const BUTTON_TEXT = {
  green: 'text-emerald-600',
  amber: 'text-amber-700',
  red: 'text-red-700',
};

const waitingLabel = computed(() => {
  const m = waitingNow.value;
  if (!m) return '';
  return m >= 60
    ? `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}`
    : `${m} min`;
});

// 🔧 rodada 192: rótulo por tipo de aviso (ligação perdida, "não vou",
// agente remarcou/cancelou a consulta)
const KIND_LABEL = {
  missed_call: '📵 Ligação perdida',
  journey_reply: '🗓️ Respondeu "não vou"',
  agente_remarcou: '🔧 Agente remarcou a consulta',
  agente_cancelou: '🔧 Agente cancelou a consulta',
  nao_confirmou: '❌ Respondeu NÃO ao lembrete da consulta',
  // ⏰ 08/11 (LIFE): chegou o dia/hora de uma tarefa com data (retorno combinado)
  tarefa_no_prazo: '⏰ Chegou o dia de chamar o cliente',
};
const kindLabel = computed(() => KIND_LABEL[alert.value?.kind] || '');
// item 217: o "não confirmou" usa o mesmo caminho (aviso amarrado à consulta)
const isAgentAlert = computed(
  () =>
    String(alert.value?.kind || '').startsWith('agente_') ||
    alert.value?.kind === 'nao_confirmou' ||
    alert.value?.kind === 'tarefa_no_prazo'
);

const attendNow = () => {
  const id = alert.value?.conversation_id;
  if (!id) return;
  ack(id);
  leaving.value = true;
  setTimeout(() => {
    alert.value = null;
    leaving.value = false;
  }, 350);
  router.push(`/app/accounts/${accountId.value}/conversations/${id}`);
};
</script>

<template>
  <Teleport to="body">
    <div
      v-if="alert"
      class="cevico-genie fixed bottom-6 right-6 z-[9999] w-[340px] rounded-2xl text-white shadow-2xl overflow-hidden"
      :class="[leaving ? 'cevico-genie-out' : '', `cevico-radar-${level}`]"
      :style="{
        background: BACKGROUND[level],
        transition: 'background .6s ease',
      }"
    >
      <div class="p-4">
        <div class="flex items-center gap-2 mb-1.5">
          <span class="i-lucide-radar text-lg" />
          <p class="text-sm font-bold flex-1">
            {{
              level === 'red'
                ? 'Essa é a prioridade máxima. 😊'
                : kindLabel || 'Paciente quente esperando!'
            }}
          </p>
        </div>
        <p class="text-sm font-semibold">
          {{ alert.contact_name }}
          <span class="opacity-80 font-normal">· {{ isAgentAlert ? 'há' : 'esperando há' }}
            {{ waitingLabel }}</span>
        </p>
        <p v-if="alert.motivo" class="text-xs opacity-90 mt-1 leading-relaxed">
          {{ alert.motivo }}
        </p>
        <p
          v-if="alert.acao"
          class="text-xs mt-1.5 bg-white/15 rounded-lg px-2.5 py-1.5 leading-relaxed"
        >
          💡 {{ alert.acao }}
        </p>
        <button
          class="mt-3 w-full py-2.5 rounded-xl font-bold text-sm bg-white shadow"
          :class="[
            BUTTON_TEXT[level],
            level === 'red' ? 'cevico-btn-pulse' : '',
          ]"
          @click.stop="attendNow"
        >
          {{ isAgentAlert ? 'Ver conversa →' : 'Atender agora →' }}
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
/* a janelinha pulsa sempre; depois de 30 min, vermelha e pulsando mais forte e mais rápido */
.cevico-radar-green,
.cevico-radar-amber {
  animation:
    cevicoGenieIn 0.55s cubic-bezier(0.22, 1.1, 0.35, 1),
    cevicoRadarPulse 2.4s ease-in-out 0.6s infinite;
}
.cevico-radar-red {
  animation:
    cevicoGenieIn 0.55s cubic-bezier(0.22, 1.1, 0.35, 1),
    cevicoRadarPulseRed 1.1s ease-in-out 0.6s infinite;
}
@keyframes cevicoRadarPulse {
  0%,
  100% {
    box-shadow:
      0 12px 30px rgba(0, 0, 0, 0.25),
      0 0 0 0 rgba(255, 255, 255, 0.35);
  }
  50% {
    box-shadow:
      0 12px 30px rgba(0, 0, 0, 0.25),
      0 0 0 10px rgba(255, 255, 255, 0);
  }
}
@keyframes cevicoRadarPulseRed {
  0%,
  100% {
    transform: scale(1);
    box-shadow:
      0 12px 30px rgba(0, 0, 0, 0.3),
      0 0 0 0 rgba(248, 113, 113, 0.75);
  }
  50% {
    transform: scale(1.03);
    box-shadow:
      0 12px 30px rgba(0, 0, 0, 0.3),
      0 0 0 16px rgba(248, 113, 113, 0);
  }
}
/* botão pulsando depois do recado */
.cevico-btn-pulse {
  animation: cevicoBtnPulse 1.2s ease-in-out infinite;
}
@keyframes cevicoBtnPulse {
  0%,
  100% {
    transform: scale(1);
    box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.55);
  }
  50% {
    transform: scale(1.04);
    box-shadow: 0 0 0 9px rgba(255, 255, 255, 0);
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-genie,
  .cevico-radar-green,
  .cevico-radar-amber,
  .cevico-radar-red,
  .cevico-btn-pulse,
  .cevico-genie-out {
    animation: none;
  }
}
</style>
