<script setup>
// 📞 Popup das CHAMADAS NATIVAS de WhatsApp (item 167) — cards empilhados no
// canto inferior direito, vidro CEVICO, claro/escuro. Quatro cards:
//   tocando   → avatar/iniciais, nome, telefone, Atender / Recusar, pulso
//   em chamada → timer mm:ss, Mudo, Desligar, "Ir para a conversa", REC
//   encerrada → resumo por 6 s e some
//   perdida   → "📵 Chamada perdida de X · há 2 min" + Abrir conversa + fechar
// Vários cards ao mesmo tempo (duas tocando, uma perdida…). Montado no
// Dashboard.vue ao lado do RadarPriorityPopup.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useCevicoCallsStore } from 'dashboard/stores/cevicoCalls';
import {
  formatPhoneBR,
  formatClock,
  formatTalkTime,
  agoLabel,
  initialsOf,
  END_REASON_LABELS,
} from 'dashboard/helper/cevicoCallsFormat';

const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const calls = useCevicoCallsStore();

// relógio do card em chamada (1 s)
const now = ref(Date.now());
let ticker = null;
onMounted(() => {
  ticker = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});
onBeforeUnmount(() => clearInterval(ticker));

const elapsed = computed(() => {
  if (!calls.activeSince) return 0;
  return Math.floor((now.value - calls.activeSince) / 1000);
});

const activeIsRinging = computed(() => {
  const c = calls.activeCall;
  return c && c.direction === 'outbound' && !calls.activeSince;
});

const phoneOf = call =>
  formatPhoneBR(call?.contact?.phone_number || call?.wa_id || '');
const nameOf = call => call?.contact?.name || call?.display_name || 'Paciente';

const openConversation = call => {
  const id = call?.conversation_id;
  if (!id) return;
  router.push(`/app/accounts/${accountId.value}/conversations/${id}`);
};

const missedText = m => {
  const reason = END_REASON_LABELS[m.reason];
  const when = agoLabel(m.at);
  return [reason && reason !== 'Ninguém atendeu' ? reason : '', when]
    .filter(Boolean)
    .join(' · ');
};

const endedTalk = e =>
  formatTalkTime(e.call?.duration || e.call?.recording_duration || 0);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="calls.hasCards"
      class="cevico-calls fixed bottom-6 right-6 z-[10000] flex flex-col items-end gap-3 w-[340px] max-w-[calc(100vw-2rem)]"
    >
      <!-- 📵 perdidas -->
      <div
        v-for="m in calls.missedCalls"
        :key="`missed-${m.id}`"
        class="cevico-call-card cevico-call-in w-full px-4 py-3 flex items-center gap-3"
      >
        <span
          class="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 bg-red-500/12 text-red-500"
        >
          <span class="i-lucide-phone-missed text-base" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-[13px] font-bold text-n-slate-12 truncate">
            📵 Chamada perdida de {{ nameOf(m.call) }}
          </p>
          <p class="text-[11px] text-n-slate-10 truncate">
            {{ missedText(m) || phoneOf(m.call) }}
          </p>
          <button
            v-if="m.call.conversation_id"
            class="mt-1 text-[11px] font-semibold text-n-brand hover:underline"
            @click="
              openConversation(m.call);
              calls.dismiss(m.id);
            "
          >
            Abrir conversa →
          </button>
        </div>
        <button
          class="w-7 h-7 rounded-full flex items-center justify-center text-n-slate-9 hover:bg-n-alpha-2 flex-shrink-0"
          title="Fechar"
          @click="calls.dismiss(m.id)"
        >
          <span class="i-lucide-x text-sm" />
        </button>
      </div>

      <!-- ✅ encerradas (resumo de 6 s) -->
      <div
        v-for="e in calls.endedCalls"
        :key="`ended-${e.id}`"
        class="cevico-call-card cevico-call-in w-full px-4 py-3 flex items-center gap-3"
      >
        <span
          class="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 bg-n-alpha-2 text-n-slate-11"
        >
          <span class="i-lucide-phone-off text-base" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-[13px] font-bold text-n-slate-12 truncate">
            Chamada encerrada · {{ nameOf(e.call) }}
          </p>
          <p class="text-[11px] text-n-slate-10">
            {{ endedTalk(e) }} de conversa
            <template v-if="e.call.recording_url || calls.isRecording">
              · gravação salva na conversa
            </template>
          </p>
        </div>
        <button
          class="w-7 h-7 rounded-full flex items-center justify-center text-n-slate-9 hover:bg-n-alpha-2 flex-shrink-0"
          title="Fechar"
          @click="calls.dismiss(e.id)"
        >
          <span class="i-lucide-x text-sm" />
        </button>
      </div>

      <!-- 🟢 em chamada -->
      <div
        v-if="calls.activeCall"
        class="cevico-call-card cevico-call-in cevico-call-active w-full p-4"
      >
        <div class="flex items-center gap-3">
          <div class="relative flex-shrink-0">
            <img
              v-if="calls.activeCall.contact?.thumbnail"
              :src="calls.activeCall.contact.thumbnail"
              alt=""
              class="w-11 h-11 rounded-full object-cover"
            />
            <span
              v-else
              class="w-11 h-11 rounded-full flex items-center justify-center text-sm font-bold text-white"
              style="background: linear-gradient(135deg, #059669, #34d399)"
            >
              {{ initialsOf(nameOf(calls.activeCall)) }}
            </span>
            <span
              v-if="calls.isRecording"
              class="cevico-rec absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-red-500 border-2 border-white dark:border-slate-900"
              title="Gravando"
            />
          </div>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-bold text-n-slate-12 truncate">
              {{ nameOf(calls.activeCall) }}
            </p>
            <p class="text-[11px] text-n-slate-10 truncate">
              {{ phoneOf(calls.activeCall) }}
            </p>
          </div>
          <div class="text-right flex-shrink-0">
            <p
              v-if="activeIsRinging"
              class="text-xs font-semibold text-emerald-600 cevico-pulse-text"
            >
              Chamando…
            </p>
            <p v-else class="text-lg font-bold tabular-nums text-n-slate-12">
              {{ formatClock(elapsed) }}
            </p>
            <p
              class="text-[10px] text-n-slate-9 flex items-center justify-end gap-1"
            >
              <template v-if="calls.isRecording">
                <span class="w-1.5 h-1.5 rounded-full bg-red-500 cevico-rec" />
                REC
              </template>
              <template v-else-if="calls.activeCall.simulated">
                simulação
              </template>
              <template v-else>WhatsApp</template>
            </p>
          </div>
        </div>
        <div class="grid grid-cols-3 gap-2 mt-3">
          <button
            class="h-10 rounded-xl text-xs font-semibold flex items-center justify-center gap-1.5 transition-colors"
            :class="
              calls.isMuted
                ? 'bg-amber-500/15 text-amber-600'
                : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'
            "
            :disabled="calls.activeCall.simulated"
            :title="
              calls.isMuted ? 'Reativar o microfone' : 'Silenciar o microfone'
            "
            @click="calls.toggleMute()"
          >
            <span
              :class="calls.isMuted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
              class="text-sm"
            />
            {{ calls.isMuted ? 'Mudo' : 'Mudo' }}
          </button>
          <button
            class="h-10 rounded-xl text-xs font-semibold flex items-center justify-center gap-1.5 bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3 transition-colors disabled:opacity-40"
            :disabled="!calls.activeCall.conversation_id"
            title="Ir para a conversa"
            @click="openConversation(calls.activeCall)"
          >
            <span class="i-lucide-message-square text-sm" />
            Conversa
          </button>
          <button
            class="h-10 rounded-xl text-xs font-bold flex items-center justify-center gap-1.5 text-white shadow disabled:opacity-60"
            style="background: linear-gradient(135deg, #991b1b, #ef4444)"
            :disabled="calls.isBusy"
            @click="calls.hangup(calls.activeCall.id)"
          >
            <span class="i-lucide-phone-off text-sm" />
            Desligar
          </button>
        </div>
      </div>

      <!-- 📞 tocando -->
      <div
        v-for="c in calls.ringingCalls"
        :key="`ring-${c.id}`"
        class="cevico-call-card cevico-call-in cevico-call-ringing w-full p-4"
      >
        <div class="flex items-center gap-3">
          <div class="relative flex-shrink-0">
            <span class="cevico-ring-pulse" aria-hidden="true" />
            <img
              v-if="c.contact?.thumbnail"
              :src="c.contact.thumbnail"
              alt=""
              class="relative w-12 h-12 rounded-full object-cover"
            />
            <span
              v-else
              class="relative w-12 h-12 rounded-full flex items-center justify-center text-base font-bold text-white"
              style="background: linear-gradient(135deg, #059669, #34d399)"
            >
              {{ initialsOf(nameOf(c)) }}
            </span>
          </div>
          <div class="min-w-0 flex-1">
            <p
              class="text-[11px] font-semibold text-emerald-600 flex items-center gap-1"
            >
              <span class="i-lucide-phone-incoming text-xs" />
              Chamada de WhatsApp
              <span v-if="c.simulated" class="text-n-slate-9 font-normal">
                · simulação
              </span>
            </p>
            <p class="text-sm font-bold text-n-slate-12 truncate">
              {{ nameOf(c) }}
            </p>
            <p class="text-[11px] text-n-slate-10 truncate">{{ phoneOf(c) }}</p>
            <button
              v-if="c.conversation_id"
              class="text-[11px] text-n-brand hover:underline mt-0.5"
              @click="openConversation(c)"
            >
              Ver conversa →
            </button>
          </div>
        </div>
        <div class="grid grid-cols-2 gap-2 mt-3">
          <button
            class="h-11 rounded-xl text-sm font-bold flex items-center justify-center gap-1.5 text-white shadow disabled:opacity-60"
            style="background: linear-gradient(135deg, #991b1b, #ef4444)"
            :disabled="calls.isBusy"
            @click="calls.reject(c.id)"
          >
            <span class="i-lucide-phone-off text-base" />
            Recusar
          </button>
          <button
            class="cevico-accept h-11 rounded-xl text-sm font-bold flex items-center justify-center gap-1.5 text-white shadow disabled:opacity-60"
            style="background: linear-gradient(135deg, #059669, #4ade80)"
            :disabled="calls.isBusy"
            @click="calls.accept(c.id)"
          >
            <span class="i-lucide-phone text-base" />
            {{ calls.isBusy ? 'Conectando…' : 'Atender' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* vidro CEVICO: cantos 16px, sombra suave, claro/escuro */
.cevico-call-card {
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid rgba(255, 255, 255, 0.7);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.9),
    0 18px 40px -16px rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
}
:global(.dark) .cevico-call-card {
  background: rgba(23, 25, 28, 0.92);
  border-color: rgba(255, 255, 255, 0.1);
  box-shadow: 0 18px 40px -16px rgba(0, 0, 0, 0.7);
}
.cevico-call-ringing {
  border-color: rgba(5, 150, 105, 0.45);
}
.cevico-call-active {
  border-color: rgba(37, 99, 235, 0.35);
}
/* entrada suave, de baixo pra cima */
.cevico-call-in {
  animation: cevicoCallIn 0.32s cubic-bezier(0.22, 1.1, 0.35, 1);
}
@keyframes cevicoCallIn {
  from {
    transform: translateY(16px) scale(0.96);
    opacity: 0;
  }
  to {
    transform: none;
    opacity: 1;
  }
}
/* pulso verde ao redor do avatar enquanto toca */
.cevico-ring-pulse {
  position: absolute;
  inset: -4px;
  border-radius: 9999px;
  border: 2px solid rgba(5, 150, 105, 0.6);
  animation: cevicoRingPulse 1.4s ease-out infinite;
}
@keyframes cevicoRingPulse {
  0% {
    transform: scale(0.9);
    opacity: 0.9;
  }
  100% {
    transform: scale(1.5);
    opacity: 0;
  }
}
.cevico-accept {
  animation: cevicoAcceptPulse 1.3s ease-in-out infinite;
}
@keyframes cevicoAcceptPulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(5, 150, 105, 0.5);
  }
  50% {
    box-shadow: 0 0 0 8px rgba(5, 150, 105, 0);
  }
}
.cevico-rec {
  animation: cevicoRec 1.2s ease-in-out infinite;
}
@keyframes cevicoRec {
  0%,
  100% {
    opacity: 1;
  }
  50% {
    opacity: 0.35;
  }
}
.cevico-pulse-text {
  animation: cevicoRec 1.6s ease-in-out infinite;
}
@media (prefers-reduced-motion: reduce) {
  .cevico-call-in,
  .cevico-ring-pulse,
  .cevico-accept,
  .cevico-rec,
  .cevico-pulse-text {
    animation: none;
  }
}
</style>
