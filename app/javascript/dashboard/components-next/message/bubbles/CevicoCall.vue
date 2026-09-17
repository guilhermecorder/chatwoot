<script setup>
// 📞 Card da CHAMADA NATIVA de WhatsApp na conversa (item 167). Lê
// contentAttributes.cevico_call (payload §4 do contrato — o MessageList
// camelíza as chaves, então lemos nas duas grafias): ícone por direção e
// status, título humano, "atendida por", duração, player da gravação,
// transcrição dobrável (Atendente:/Paciente:), resumo e o botão
// "Transcrever" quando a transcrição falhou/foi pulada.
import { ref, computed } from 'vue';
import { useMessageContext } from '../provider.js';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';
import { useAlert } from 'dashboard/composables';
import {
  pick,
  callIcon,
  callTitle,
  formatTalkTime,
  shortDateTime,
} from 'dashboard/helper/cevicoCallsFormat';

const { contentAttributes } = useMessageContext();

// mudanças locais (transcrição pedida/carregada) por cima do payload
const local = ref({});
const call = computed(() => ({
  ...(contentAttributes.value?.cevicoCall ||
    contentAttributes.value?.cevico_call ||
    {}),
  ...local.value,
}));

const callId = computed(() => pick(call.value, 'id'));
const status = computed(() => pick(call.value, 'status'));
const direction = computed(() => pick(call.value, 'direction'));
const title = computed(() => callTitle(call.value));
const icon = computed(() => callIcon(call.value));
const recordingUrl = computed(() => pick(call.value, 'recording_url'));
const summary = computed(() => pick(call.value, 'summary'));
const transcriptStatus = computed(
  () => pick(call.value, 'transcript_status') || null
);
const hasTranscript = computed(
  () =>
    Boolean(pick(call.value, 'has_transcript')) ||
    Boolean(local.value.transcript)
);
const simulated = computed(() => Boolean(pick(call.value, 'simulated')));
const startedAt = computed(() => pick(call.value, 'started_at'));
const waitSeconds = computed(() =>
  Number(pick(call.value, 'wait_seconds') || 0)
);
const duration = computed(() => Number(pick(call.value, 'duration') || 0));
const answered = computed(() =>
  ['accepted', 'completed'].includes(status.value)
);

const isTranscribing = computed(() =>
  ['pending', 'processing'].includes(transcriptStatus.value)
);
const canTranscribe = computed(
  () =>
    Boolean(recordingUrl.value) &&
    !hasTranscript.value &&
    !isTranscribing.value &&
    ['failed', 'skipped', null].includes(transcriptStatus.value)
);

// ── transcrição (dobrável; o texto vem só no GET crm/calls/:id) ──
const showTranscript = ref(false);
const isLoadingTranscript = ref(false);
const transcriptLines = computed(() => {
  const text = local.value.transcript || '';
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .map(line => {
      const m = line.match(
        /^(Atendente|Paciente|Clínica|Cliente)\s*:\s*(.*)$/i
      );
      return m
        ? { who: m[1], text: m[2], mine: /atendente|cl[ií]nica/i.test(m[1]) }
        : { who: '', text: line, mine: false };
    });
});

const toggleTranscript = async () => {
  showTranscript.value = !showTranscript.value;
  if (!showTranscript.value || local.value.transcript || !callId.value) return;
  isLoadingTranscript.value = true;
  try {
    const { data } = await CevicoCallsAPI.show(callId.value);
    local.value = {
      ...local.value,
      transcript: data.transcript || '',
      summary: data.summary || summary.value,
      transcript_status: data.transcript_status || transcriptStatus.value,
    };
  } catch {
    useAlert('Não consegui carregar a transcrição.');
    showTranscript.value = false;
  } finally {
    isLoadingTranscript.value = false;
  }
};

const isRequestingTranscript = ref(false);
const transcribe = async () => {
  if (!callId.value || isRequestingTranscript.value) return;
  isRequestingTranscript.value = true;
  try {
    await CevicoCallsAPI.transcribe(callId.value);
    local.value = { ...local.value, transcript_status: 'pending' };
    useAlert('Transcrição pedida — em instantes ela aparece aqui.');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Não consegui pedir a transcrição.'
    );
  } finally {
    isRequestingTranscript.value = false;
  }
};

const toneBox = computed(() => {
  if (status.value === 'missed') return 'border-red-300/60 bg-red-500/5';
  if (['rejected', 'failed', 'canceled'].includes(status.value)) {
    return 'border-amber-300/60 bg-amber-500/5';
  }
  if (direction.value === 'outbound') return 'border-blue-300/60 bg-blue-500/5';
  return 'border-emerald-300/60 bg-emerald-500/5';
});
</script>

<template>
  <div
    class="cevico-call-bubble w-[min(100%,28rem)] rounded-2xl border px-4 py-3 text-sm text-n-slate-12 shadow-sm"
    :class="toneBox"
    data-bubble-name="cevico-call"
  >
    <div class="flex items-start gap-3">
      <span
        class="w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 bg-white/70 dark:bg-white/10"
        :class="icon.tone"
      >
        <span :class="icon.icon" class="text-base" />
      </span>
      <div class="min-w-0 flex-1">
        <p class="font-semibold leading-snug">{{ title }}</p>
        <p class="text-[11px] text-n-slate-10 mt-0.5 flex flex-wrap gap-x-2">
          <span v-if="startedAt">{{ shortDateTime(startedAt) }}</span>
          <span v-if="answered && waitSeconds">
            esperou {{ formatTalkTime(waitSeconds) }}
          </span>
          <span v-if="simulated" class="text-n-slate-9">· simulação</span>
        </p>
      </div>
    </div>

    <!-- gravação -->
    <audio
      v-if="recordingUrl"
      controls
      preload="none"
      :src="recordingUrl"
      class="w-full mt-2.5 h-9"
    />

    <!-- resumo da IA -->
    <p
      v-if="summary"
      class="mt-2 text-xs text-n-slate-11 leading-relaxed rounded-lg bg-white/60 dark:bg-white/5 px-2.5 py-1.5"
    >
      ✨ {{ summary }}
    </p>

    <!-- transcrição / transcrever -->
    <div v-if="hasTranscript || canTranscribe || isTranscribing" class="mt-2">
      <button
        v-if="hasTranscript"
        class="text-[11px] font-semibold text-n-brand hover:underline flex items-center gap-1"
        @click="toggleTranscript"
      >
        <span
          :class="
            showTranscript ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
          "
          class="text-xs"
        />
        {{ showTranscript ? 'Esconder transcrição' : 'Ver transcrição' }}
      </button>
      <p
        v-else-if="isTranscribing"
        class="text-[11px] text-n-slate-9 flex items-center gap-1"
      >
        <span class="i-lucide-loader-2 animate-spin text-xs" />
        Transcrevendo a gravação…
      </p>
      <button
        v-else
        class="text-[11px] font-semibold px-2.5 py-1 rounded-lg border border-n-weak text-n-slate-11 hover:text-n-brand hover:border-n-brand/40 transition-colors disabled:opacity-50 flex items-center gap-1"
        :disabled="isRequestingTranscript"
        @click="transcribe"
      >
        <span
          :class="
            isRequestingTranscript
              ? 'i-lucide-loader-2 animate-spin'
              : 'i-lucide-file-text'
          "
          class="text-xs"
        />
        Transcrever
        <span
          v-if="transcriptStatus === 'failed'"
          class="text-n-slate-9 font-normal"
        >
          (a última tentativa falhou)
        </span>
      </button>

      <div
        v-if="showTranscript"
        class="mt-2 rounded-lg bg-white/70 dark:bg-white/5 px-2.5 py-2"
      >
        <p v-if="isLoadingTranscript" class="text-[11px] text-n-slate-9">
          Carregando transcrição…
        </p>
        <p
          v-else-if="!transcriptLines.length"
          class="text-[11px] text-n-slate-9"
        >
          A transcrição veio vazia.
        </p>
        <div v-else class="space-y-1 max-h-64 overflow-y-auto">
          <p
            v-for="(line, i) in transcriptLines"
            :key="i"
            class="text-xs leading-relaxed"
            :class="line.mine ? 'text-n-slate-12' : 'text-n-slate-11'"
          >
            <b
              v-if="line.who"
              :class="line.mine ? 'text-blue-700' : 'text-emerald-700'"
            >
              {{ line.who }}:
            </b>
            {{ line.text }}
          </p>
        </div>
      </div>
    </div>

    <p
      v-if="duration && !answered && direction === 'outbound'"
      class="text-[11px] text-n-slate-9 mt-1"
    >
      tocou por {{ formatTalkTime(duration) }}
    </p>
  </div>
</template>
