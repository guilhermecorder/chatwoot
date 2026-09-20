<script setup>
// 📞 Detalhe de uma chamada (item 176): linha do tempo (events), gravação,
// transcrição/resumo e ações — abrir conversa/paciente, retornar ligação,
// marcar como retornada, transcrever. Modal do kit (.cv-modal).
import { computed, ref } from 'vue';
import {
  callIcon,
  callTitle,
  formatTalkTime,
  formatPhoneBR,
  initialsOf,
  STATUS_LABELS,
  END_REASON_LABELS,
} from 'dashboard/helper/cevicoCallsFormat';

const props = defineProps({
  call: { type: Object, required: true },
  cvVars: { type: Object, default: () => ({}) },
  canCall: { type: Boolean, default: false },
  isBusy: { type: Boolean, default: false },
});
const emit = defineEmits([
  'close',
  'conversation',
  'contact',
  'return',
  'mark-returned',
  'transcribe',
]);

const c = computed(() => props.call);
const name = computed(
  () => c.value.contact?.name || c.value.display_name || 'Paciente'
);
const phone = computed(() =>
  formatPhoneBR(c.value.contact?.phone_number || c.value.wa_id || '')
);
const icon = computed(() => callIcon(c.value));
const missedLike = computed(() =>
  ['missed', 'rejected', 'failed', 'canceled'].includes(c.value.status)
);
const showTranscript = ref(false);

const fmtFull = ts =>
  ts
    ? new Date(ts).toLocaleString('pt-BR', {
        weekday: 'short',
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const fmtTime = ts =>
  ts
    ? new Date(ts).toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
      })
    : '';

// linha do tempo humana: dos eventos crus (webhook/ações) para frases
const EVENT_LABELS = {
  connect: 'Paciente ligou',
  ringing: 'Tocando',
  accepted_by_agent: 'Atendida',
  rejected_by_agent: 'Recusada pela equipe',
  hangup_by_agent: 'Desligada pela equipe',
  terminate: 'Ligação encerrada',
  outside_hours: 'Fora do horário de atendimento',
  initiated: 'Clínica ligou para o paciente',
  returned: 'Marcada como retornada',
  permission_reply: 'Paciente respondeu a permissão',
};
const timeline = computed(() =>
  (Array.isArray(c.value.events) ? c.value.events : []).map((e, i) => {
    const raw = e.raw || {};
    const who = raw.user_name ? ` · ${raw.user_name}` : '';
    const status = e.status ? ` (${String(e.status).toLowerCase()})` : '';
    return {
      key: `${i}-${e.at}`,
      at: fmtTime(e.at),
      label: `${EVENT_LABELS[e.event] || e.event}${status}${who}`,
      note: raw.note || '',
    };
  })
);
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page fixed inset-0 z-[60] flex items-start sm:items-center justify-center bg-black/60 p-2 sm:p-6"
      :style="cvVars"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-2xl max-h-[95vh] flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span class="cv-icon cv-icon-lg">
            <span :class="icon.icon" class="text-lg" />
          </span>
          <div class="min-w-0 flex-1">
            <p class="text-[11px] opacity-80">{{ callTitle(c) }}</p>
            <h2 class="text-base font-bold leading-snug truncate">
              {{ name }}
              <span class="font-normal opacity-80 text-sm">{{ phone }}</span>
            </h2>
          </div>
          <button
            class="cv-iconbtn cv-iconbtn-lg"
            title="Fechar"
            @click="emit('close')"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>

        <div class="flex-1 min-h-0 overflow-y-auto p-4 sm:p-6 space-y-5">
          <!-- resumo em números -->
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
            <div class="cv-stat text-center">
              <p class="text-[10px] text-n-slate-9">Quando</p>
              <p class="text-sm font-bold text-n-slate-12">
                {{ fmtFull(c.started_at) }}
              </p>
            </div>
            <div class="cv-stat text-center">
              <p class="text-[10px] text-n-slate-9">Situação</p>
              <p class="text-sm font-bold text-n-slate-12">
                {{ STATUS_LABELS[c.status] || c.status }}
                <span v-if="c.end_reason" class="font-normal text-n-slate-10">
                  · {{ END_REASON_LABELS[c.end_reason] || c.end_reason }}
                </span>
              </p>
            </div>
            <div class="cv-stat text-center">
              <p class="text-[10px] text-n-slate-9">Espera</p>
              <p class="text-sm font-bold text-n-slate-12">
                {{
                  c.wait_seconds != null ? formatTalkTime(c.wait_seconds) : '—'
                }}
              </p>
            </div>
            <div class="cv-stat text-center">
              <p class="text-[10px] text-n-slate-9">Conversa</p>
              <p class="text-sm font-bold text-n-slate-12">
                {{ Number(c.duration) ? formatTalkTime(c.duration) : '—' }}
              </p>
            </div>
          </div>

          <!-- quem cuidou -->
          <div
            class="flex items-center gap-3 flex-wrap text-xs text-n-slate-11"
          >
            <template v-if="c.handled_by === 'ai'">
              <span class="cv-chip">🤖 assistente virtual</span>
              <span v-if="c.outcome_label || c.outcome" class="cv-chip">
                {{ c.outcome_label || c.outcome }}
              </span>
            </template>
            <template v-else-if="c.user">
              <img
                v-if="c.user.avatar_url"
                :src="c.user.avatar_url"
                alt=""
                class="w-6 h-6 rounded-full object-cover"
              />
              <span
                v-else
                class="w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold text-white"
                style="background: var(--cv-grad-2)"
              >
                {{ initialsOf(c.user.name) }}
              </span>
              <span
                >atendida por <b>{{ c.user.name }}</b></span
              >
            </template>
            <span v-else-if="missedLike">ninguém atendeu</span>
            <span v-if="c.inbox_name" class="cv-chip">{{ c.inbox_name }}</span>
            <span v-if="c.returned_at" class="cv-chip cv-green">
              retornada {{ fmtFull(c.returned_at) }}
            </span>
            <span v-if="c.simulated" class="cv-chip">simulação</span>
          </div>

          <!-- gravação -->
          <div v-if="c.recording_url" class="cv-sub p-3">
            <p class="cv-label mb-1.5">Gravação</p>
            <audio controls :src="c.recording_url" class="w-full h-8" />
          </div>

          <!-- resumo + transcrição -->
          <div
            v-if="c.summary || c.has_transcript || c.transcript_status"
            class="cv-sub p-3"
          >
            <div class="flex items-center gap-2 mb-1.5">
              <p class="cv-label">Resumo da IA</p>
              <span
                v-if="c.transcript_status === 'pending'"
                class="cv-chip cv-amber"
              >
                transcrevendo…
              </span>
              <span
                v-else-if="c.transcript_status === 'failed'"
                class="cv-chip cv-red"
                :title="c.transcript_error || ''"
              >
                falhou
              </span>
              <button
                v-if="c.has_transcript"
                class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
                @click="showTranscript = !showTranscript"
              >
                {{
                  showTranscript ? 'Esconder transcrição' : 'Ver transcrição'
                }}
              </button>
            </div>
            <p v-if="c.summary" class="text-sm text-n-slate-12 leading-relaxed">
              {{ c.summary }}
            </p>
            <p v-else class="text-xs text-n-slate-9">Sem resumo ainda.</p>
            <pre
              v-if="showTranscript && c.transcript"
              class="mt-3 text-xs text-n-slate-11 whitespace-pre-wrap font-sans leading-relaxed max-h-64 overflow-y-auto"
              >{{ c.transcript }}</pre
            >
          </div>

          <!-- linha do tempo -->
          <div>
            <p class="cv-label mb-2">Linha do tempo</p>
            <p v-if="!timeline.length" class="text-xs text-n-slate-9">
              Sem eventos registrados.
            </p>
            <ol v-else class="space-y-1.5">
              <li
                v-for="e in timeline"
                :key="e.key"
                class="flex items-start gap-2 text-xs"
              >
                <span class="text-n-slate-9 tabular-nums w-16 flex-shrink-0">{{
                  e.at
                }}</span>
                <span
                  class="w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0"
                  style="background: var(--cv)"
                />
                <span class="text-n-slate-12">
                  {{ e.label }}
                  <span v-if="e.note" class="text-n-slate-10">
                    — {{ e.note }}</span
                  >
                </span>
              </li>
            </ol>
          </div>
        </div>

        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <button
            v-if="c.conversation_id"
            class="cv-btn cv-btn-sm"
            @click="emit('conversation', c)"
          >
            <span class="i-lucide-message-circle text-xs" />
            Abrir conversa
          </button>
          <button
            v-if="c.contact?.id"
            class="cv-btn cv-btn-ghost cv-btn-sm"
            @click="emit('contact', c)"
          >
            <span class="i-lucide-user text-xs" />
            Paciente
          </button>
          <button
            v-if="
              c.recording_url &&
              !c.has_transcript &&
              c.transcript_status !== 'pending'
            "
            class="cv-btn cv-btn-ghost cv-btn-sm"
            @click="emit('transcribe', c)"
          >
            <span class="i-lucide-sparkles text-xs" />
            Transcrever
          </button>
          <span class="flex-1" />
          <button
            v-if="missedLike && !c.returned_at"
            class="cv-btn cv-btn-ghost cv-btn-sm"
            :disabled="isBusy"
            @click="emit('mark-returned', c)"
          >
            <span class="i-lucide-check text-xs" />
            Marcar como retornada
          </button>
          <button
            v-if="canCall && c.contact?.id"
            class="cv-btn cv-btn-sm"
            :disabled="isBusy"
            @click="emit('return', c)"
          >
            <span class="i-lucide-phone-outgoing text-xs" />
            Ligar para o paciente
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
