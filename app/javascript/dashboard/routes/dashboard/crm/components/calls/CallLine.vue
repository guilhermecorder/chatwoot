<script setup>
// 📞 Uma chamada em UMA linha (item 176) — usada na Lista, na Linha do tempo
// e nas filas do ambiente Chamadas. Foto/iniciais, nome + telefone, ícone
// por direção/desfecho, quem cuidou, duração, chips e as ações (ouvir,
// conversa, detalhes) — tudo do kit .cv-*.
import { computed } from 'vue';
import {
  callIcon,
  formatTalkTime,
  formatPhoneBR,
  shortDateTime,
  initialsOf,
  STATUS_LABELS,
} from 'dashboard/helper/cevicoCallsFormat';

const props = defineProps({
  call: { type: Object, required: true },
  // 'time' mostra só a hora (linha do tempo); 'datetime' dd/mm hh:mm
  when: { type: String, default: 'datetime' },
  compact: { type: Boolean, default: false },
});
const emit = defineEmits(['open', 'conversation', 'play']);

const c = computed(() => props.call);
const name = computed(
  () => c.value.contact?.name || c.value.display_name || 'Paciente'
);
const phone = computed(() =>
  formatPhoneBR(c.value.contact?.phone_number || c.value.wa_id || '')
);
const icon = computed(() => callIcon(c.value));
const whenLabel = computed(() => {
  if (!c.value.started_at) return '';
  if (props.when === 'time') {
    return new Date(c.value.started_at).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    });
  }
  return shortDateTime(c.value.started_at);
});
const statusChip = computed(() => {
  const s = c.value.status;
  if (['completed', 'accepted'].includes(s)) return 'cv-green';
  if (s === 'missed') return 'cv-red';
  if (['rejected', 'failed', 'canceled'].includes(s)) return 'cv-amber';
  return '';
});
const who = computed(() => {
  if (c.value.handled_by === 'ai') return '🤖 assistente virtual';
  return c.value.user?.name || '';
});
</script>

<template>
  <div
    class="cv-row px-3 cursor-pointer"
    :class="compact ? 'py-1.5' : 'py-2'"
    role="button"
    tabindex="0"
    @click="emit('open', c)"
    @keydown.enter="emit('open', c)"
  >
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 min-w-0">
      <img
        v-if="c.contact?.thumbnail"
        :src="c.contact.thumbnail"
        alt=""
        class="w-9 h-9 rounded-full object-cover flex-shrink-0"
      />
      <span
        v-else
        class="w-9 h-9 rounded-full flex items-center justify-center text-[11px] font-bold text-white flex-shrink-0"
        style="background: var(--cv-grad-2)"
      >
        {{ initialsOf(name) }}
      </span>
      <div class="min-w-[9rem] flex-1">
        <p
          class="text-sm font-semibold text-n-slate-12 truncate flex items-center gap-1.5"
        >
          <span :class="[icon.icon, icon.tone]" class="text-sm flex-shrink-0" />
          <span class="truncate">{{ name }}</span>
          <span class="text-n-slate-9 font-normal text-xs truncate">{{
            phone
          }}</span>
        </p>
        <p class="text-[11px] text-n-slate-10 truncate">
          {{ whenLabel }}
          <template v-if="who"> · {{ who }}</template>
          <template v-if="Number(c.duration)">
            · {{ formatTalkTime(c.duration) }}
          </template>
          <template v-else-if="c.wait_seconds">
            · esperou {{ formatTalkTime(c.wait_seconds) }}
          </template>
          <template v-if="c.inbox_name"> · {{ c.inbox_name }}</template>
          <template v-if="c.simulated"> · simulação</template>
        </p>
      </div>
      <span
        v-if="c.returned_at"
        class="cv-chip flex-shrink-0 !hidden sm:!inline-flex"
        title="Alguém já retornou esta ligação"
      >
        retornada
      </span>
      <span
        v-if="c.handled_by === 'ai' && (c.outcome_label || c.outcome)"
        class="cv-chip flex-shrink-0 !hidden md:!inline-flex"
        :title="c.summary || ''"
      >
        {{ c.outcome_label || c.outcome }}
      </span>
      <span class="cv-chip flex-shrink-0" :class="statusChip">
        {{ STATUS_LABELS[c.status] || c.status }}
      </span>
      <button
        v-if="c.recording_url"
        class="cv-btn cv-btn-ghost cv-iconbtn flex-shrink-0"
        title="Ouvir a gravação"
        @click.stop="emit('play', c)"
      >
        <span class="i-lucide-play text-xs" />
      </button>
      <button
        v-if="c.conversation_id"
        class="cv-btn cv-btn-ghost cv-iconbtn flex-shrink-0 !hidden sm:!inline-flex"
        title="Abrir a conversa"
        @click.stop="emit('conversation', c)"
      >
        <span class="i-lucide-message-circle text-xs" />
      </button>
      <span
        class="i-lucide-chevron-right text-n-slate-8 text-sm flex-shrink-0 !hidden sm:!inline"
      />
    </div>
  </div>
</template>
