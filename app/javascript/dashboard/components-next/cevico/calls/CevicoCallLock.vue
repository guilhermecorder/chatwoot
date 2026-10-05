<script setup>
// 📵🔒 TRAVA DA LIGAÇÃO (item 325, 05/10). Pedido do Guilherme: "após 5
// segundos da ligação chamando, ela impeça qualquer outra ação; e se não foi
// atendida, fique travada até ligar de volta… se o paciente não atendeu, o
// ideal seria que a gente ligasse duas vezes".
//
// Duas travas, só para quem RESPONDE pela coluna do CRM do paciente
// (Integrações → Ligações → Trava e responsáveis):
//   1. TOCANDO — passados N segundos chamando, a tela escurece e só sobra o
//      cartão da ligação (Atender / Recusar), que fica por cima.
//   2. PERDIDA — a tela fica travada com o cartão "Ligue de volta" até a
//      ligação ser retornada: o paciente atendeu, ou as tentativas foram
//      feitas, ou alguém marcou "já retornei por outro meio".
// Durante a ligação de volta a trava se recolhe (o cartão da chamada manda)
// e volta sozinha se ainda faltar tentativa. Erro aqui nunca trava ninguém:
// sem resposta do servidor, a tela fica livre.
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoCallsStore } from 'dashboard/stores/cevicoCalls';
import { formatPhoneBR } from 'dashboard/helper/cevicoCallsFormat';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';

const calls = useCevicoCallsStore();

const lock = ref(null); // { call, attempts_done, attempts_needed }
const shaking = ref(false);
const busy = ref(false);
let timer = null;

const check = async () => {
  try {
    const { data } = await CevicoCallsAPI.lock();
    lock.value = data?.lock || null;
  } catch {
    lock.value = null; // sem resposta = tela livre
  }
};

onMounted(() => {
  setTimeout(check, 3000);
  // travado: reconfere a cada 20 s (um colega pode ter retornado); livre: a cada 60 s
  timer = setInterval(check, 20 * 1000);
});
onBeforeUnmount(() => clearInterval(timer));
watch(
  () => calls.lockTick,
  () => setTimeout(check, 800)
);

// 1. tocando para mim há mais de N segundos
const ringLocked = computed(() => calls.lockRinging.length > 0);
const ringingCall = computed(() => calls.calls[calls.lockRinging[0]] || null);
// 2. perdida: recolhe enquanto estou numa chamada (a ligação de volta)
const missedLocked = computed(
  () => !!lock.value && !calls.active && !ringLocked.value
);

const call = computed(() => lock.value?.call || {});
const patientName = computed(
  () => call.value.contact?.name || call.value.display_name || 'Paciente'
);
const phone = computed(() =>
  formatPhoneBR(call.value.contact?.phone_number || call.value.wa_id || '')
);
const stageName = computed(() => call.value.crm?.cards?.[0]?.stage_name || '');
const calledAt = computed(() => {
  const at = call.value.started_at || call.value.created_at;
  if (!at) return '';
  return new Date(at).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
});
const attemptsDone = computed(() => lock.value?.attempts_done || 0);
const attemptsNeeded = computed(() => lock.value?.attempts_needed || 2);
const attemptLabel = computed(() =>
  attemptsDone.value
    ? `Você já ligou ${attemptsDone.value} de ${attemptsNeeded.value} vezes e o paciente não atendeu. Ligue mais uma vez.`
    : `Se o paciente não atender, ligue de novo: são ${attemptsNeeded.value} tentativas.`
);

const shake = () => {
  shaking.value = true;
  setTimeout(() => {
    shaking.value = false;
  }, 450);
};

const callBack = async () => {
  const contactId = call.value.contact?.id || call.value.contact_id;
  if (!contactId || busy.value) return;
  busy.value = true;
  try {
    const result = await calls.startOutbound(contactId, call.value.inbox_id);
    // a Meta pediu permissão do paciente: o pedido saiu e conta como tentativa registrada à mão
    if (result?.error)
      useAlert(
        'Não deu para ligar agora (o WhatsApp pediu a permissão do paciente). Tente de novo em instantes ou use "Já retornei por outro meio".'
      );
  } finally {
    busy.value = false;
    setTimeout(check, 1500);
  }
};

const markReturned = async () => {
  if (!call.value.id || busy.value) return;
  busy.value = true;
  try {
    await CevicoCallsAPI.markReturned(
      call.value.id,
      'retornada por outro meio (pela trava)'
    );
    await check();
  } catch {
    useAlert('Não consegui marcar como retornada.');
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <Teleport to="body">
    <!-- 1. TOCANDO: escurece tudo; o cartão da ligação (z 10000) fica por cima -->
    <div
      v-if="ringLocked"
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-black/70 backdrop-blur-sm"
      @click="shake"
    >
      <div
        class="cevico-lock-card text-center"
        :class="{ 'cevico-lock-shake': shaking }"
      >
        <span class="cevico-lock-icon cevico-lock-icon-ring">
          <span class="i-lucide-phone-incoming text-3xl" />
        </span>
        <p class="cevico-lock-title">Atenda a ligação</p>
        <p class="cevico-lock-name">
          {{ ringingCall?.contact?.name || 'Paciente' }} está ligando
        </p>
        <p class="cevico-lock-text">
          Você responde por esta etapa. Use o cartão da ligação, no canto de
          baixo à direita, para atender ou recusar.
        </p>
      </div>
    </div>

    <!-- 2. PERDIDA: travada até ligar de volta -->
    <div
      v-else-if="missedLocked"
      class="fixed inset-0 z-[9998] flex items-center justify-center bg-black/70 backdrop-blur-sm p-4"
      @click.self="shake"
    >
      <div class="cevico-lock-card" :class="{ 'cevico-lock-shake': shaking }">
        <div class="flex items-center gap-3 mb-4">
          <span class="cevico-lock-icon cevico-lock-icon-missed">
            <span class="i-lucide-phone-missed text-2xl" />
          </span>
          <div class="min-w-0">
            <p class="cevico-lock-title">Ligação perdida — ligue de volta</p>
            <p class="cevico-lock-sub">
              ligou {{ calledAt }}{{ stageName ? ` · ${stageName}` : '' }}
            </p>
          </div>
        </div>
        <p class="cevico-lock-name">{{ patientName }}</p>
        <p class="cevico-lock-phone">{{ phone }}</p>

        <div class="cevico-lock-attempts">
          <span
            v-for="n in attemptsNeeded"
            :key="n"
            class="cevico-lock-dot"
            :class="{ 'cevico-lock-dot-on': n <= attemptsDone }"
          />
          <span class="flex-1 min-w-0">{{ attemptLabel }}</span>
        </div>

        <button
          class="cevico-lock-btn"
          :disabled="busy || calls.isBusy"
          @click="callBack"
        >
          <span class="i-lucide-phone-outgoing text-lg" />
          {{ busy ? 'Ligando…' : 'Ligar de volta agora' }}
        </button>
        <p class="cevico-lock-text mt-3">
          A tela libera quando o paciente atender ou depois das
          {{ attemptsNeeded }} tentativas.
        </p>
        <button class="cevico-lock-link" :disabled="busy" @click="markReturned">
          Já retornei por outro meio (fica registrado no meu nome)
        </button>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.cevico-lock-card {
  width: 100%;
  max-width: 26rem;
  padding: 1.75rem;
  border-radius: 1.5rem;
  background: #fff;
  color: #0f172a;
  box-shadow: 0 30px 80px -20px rgba(0, 0, 0, 0.6);
  animation: cevico-lock-pop 0.28s cubic-bezier(0.34, 1.4, 0.64, 1);
}
:global(.dark) .cevico-lock-card {
  background: #111827;
  color: #fff;
}
.cevico-lock-icon {
  width: 3.25rem;
  height: 3.25rem;
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 1rem;
  color: #fff;
}
.cevico-lock-icon-ring {
  width: 4.5rem;
  height: 4.5rem;
  margin: 0 auto 1rem;
  border-radius: 9999px;
  background: linear-gradient(135deg, #047857, #10b981);
  animation: cevico-lock-pulse 1.1s ease-in-out infinite;
}
.cevico-lock-icon-missed {
  background: linear-gradient(135deg, #b91c1c, #f97316);
}
.cevico-lock-title {
  font-size: 1.15rem;
  font-weight: 800;
  line-height: 1.2;
}
.cevico-lock-sub {
  font-size: 0.75rem;
  opacity: 0.7;
  margin-top: 2px;
}
.cevico-lock-name {
  font-size: 1.5rem;
  font-weight: 800;
  line-height: 1.15;
  overflow-wrap: anywhere;
}
.cevico-lock-phone {
  font-size: 1rem;
  font-weight: 600;
  opacity: 0.75;
  margin-top: 2px;
}
.cevico-lock-text {
  font-size: 0.78rem;
  line-height: 1.45;
  opacity: 0.75;
  margin-top: 0.5rem;
}
.cevico-lock-attempts {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin: 1.1rem 0;
  padding: 0.7rem 0.85rem;
  border-radius: 0.9rem;
  font-size: 0.78rem;
  line-height: 1.35;
  background: rgba(37, 99, 235, 0.08);
}
:global(.dark) .cevico-lock-attempts {
  background: rgba(96, 165, 250, 0.14);
}
.cevico-lock-dot {
  width: 0.7rem;
  height: 0.7rem;
  flex-shrink: 0;
  border-radius: 9999px;
  border: 2px solid #2563eb;
}
.cevico-lock-dot-on {
  background: #2563eb;
}
.cevico-lock-btn {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.9rem 1rem;
  border-radius: 1rem;
  font-size: 1rem;
  font-weight: 800;
  color: #fff;
  background: linear-gradient(135deg, #1d4ed8, #3b82f6);
  box-shadow: 0 12px 28px -12px rgba(29, 78, 216, 0.9);
  transition: transform 0.15s ease;
}
.cevico-lock-btn:hover:not(:disabled) {
  transform: translateY(-1px);
}
.cevico-lock-btn:disabled {
  opacity: 0.6;
}
.cevico-lock-link {
  display: block;
  width: 100%;
  margin-top: 0.9rem;
  font-size: 0.72rem;
  text-decoration: underline;
  opacity: 0.6;
}
.cevico-lock-shake {
  animation: cevico-lock-shake 0.45s ease;
}
@keyframes cevico-lock-pop {
  from {
    opacity: 0;
    transform: scale(0.92) translateY(12px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}
@keyframes cevico-lock-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.55);
  }
  50% {
    box-shadow: 0 0 0 18px rgba(16, 185, 129, 0);
  }
}
@keyframes cevico-lock-shake {
  0%,
  100% {
    transform: translateX(0);
  }
  20%,
  60% {
    transform: translateX(-8px);
  }
  40%,
  80% {
    transform: translateX(8px);
  }
}
</style>
