<script setup>
// 📞 item 281 — QUEM está ligando: a coluna do CRM (chip na cor da etapa),
// a caixa de origem e a última/próxima consulta. Usado no popup da chamada
// (Recusar/Atender), no card "ao vivo" e no histórico de Chamadas. O popup
// mora fora da .cv-page (Teleport), por isso o chip tem estilo próprio.
import { computed } from 'vue';

const props = defineProps({
  call: { type: Object, required: true },
  // 'full' = chips + linha de origem/consultas; 'chips' = só a coluna (listas)
  mode: { type: String, default: 'full' },
});

const crm = computed(() => props.call?.crm || {});
const cards = computed(() => crm.value.cards || []);
const multiFunnel = computed(
  () => new Set(cards.value.map(c => c.pipeline_id)).size > 1
);
const shownCards = computed(() =>
  props.mode === 'chips' ? cards.value.slice(0, 1) : cards.value
);

const chipStyle = card => {
  const color = card.stage_color || '#6B7280';
  return {
    '--stage': color,
    background: `color-mix(in srgb, ${color} 14%, transparent)`,
    borderColor: `color-mix(in srgb, ${color} 45%, transparent)`,
  };
};
const chipTitle = card =>
  `Coluna do CRM: ${card.stage_name} · funil ${card.pipeline_name}`;

const dayLabel = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const sameYear = d.getFullYear() === new Date().getFullYear();
  const date = d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    ...(sameYear ? {} : { year: '2-digit' }),
  });
  const time = d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${date} ${time}`;
};
const ATTENDANCE = { attended: 'compareceu', missed: 'faltou' };

const facts = computed(() => {
  const list = [];
  // item 282: a caixa de entrada PARA ONDE o paciente está ligando
  if (props.call?.inbox_name && props.call?.direction !== 'outbound') {
    list.push({
      icon: 'i-lucide-phone-incoming',
      text: `ligando para ${props.call.inbox_name}`,
      strong: true,
    });
  }
  const next = crm.value.next_appointment;
  const last = crm.value.last_appointment;
  if (next) {
    list.push({
      icon: 'i-lucide-calendar-check',
      text: `próxima consulta ${dayLabel(next.at)}`,
    });
  }
  if (last) {
    const how = ATTENDANCE[last.attendance];
    list.push({
      icon: 'i-lucide-calendar',
      text: `última consulta ${dayLabel(last.at)}${how ? ` · ${how}` : ''}`,
    });
  }
  if (crm.value.origin_inbox?.name) {
    list.push({
      icon: 'i-lucide-inbox',
      text: `chegou por ${crm.value.origin_inbox.name}`,
    });
  }
  return list;
});

const isUnknown = computed(
  () => !cards.value.length && !facts.value.length && props.mode === 'full'
);
</script>

<template>
  <div
    v-if="shownCards.length || (mode === 'full' && (facts.length || isUnknown))"
    class="cevico-call-ctx min-w-0"
  >
    <div v-if="shownCards.length" class="flex flex-wrap items-center gap-1">
      <span
        v-for="card in shownCards"
        :key="`${card.pipeline_id}-${card.stage_id}`"
        class="cevico-stage-chip"
        :style="chipStyle(card)"
        :title="chipTitle(card)"
      >
        <span class="cevico-stage-dot" />
        <span class="truncate">{{ card.stage_name }}</span>
        <span v-if="multiFunnel && mode === 'full'" class="cevico-stage-funnel">
          {{ card.pipeline_name }}
        </span>
      </span>
    </div>
    <template v-if="mode === 'full'">
      <p v-if="isUnknown" class="text-[11px] text-n-slate-10 mt-1">
        Primeiro contato — ainda não está no CRM
      </p>
      <ul v-else-if="facts.length" class="mt-1.5 space-y-0.5">
        <li
          v-for="f in facts"
          :key="f.text"
          class="text-[11px] flex items-center gap-1.5 min-w-0"
          :class="
            f.strong ? 'text-n-slate-12 font-semibold' : 'text-n-slate-10'
          "
        >
          <span :class="f.icon" class="text-xs flex-shrink-0" />
          <span class="truncate">{{ f.text }}</span>
        </li>
      </ul>
    </template>
  </div>
</template>

<style scoped>
.cevico-stage-chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  max-width: 100%;
  height: 22px;
  padding: 0 9px;
  border-radius: 9999px;
  border: 1px solid transparent;
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  white-space: nowrap;
  color: rgb(30 41 59);
}
.dark .cevico-stage-chip {
  color: rgb(241 245 249);
}
.cevico-stage-dot {
  width: 7px;
  height: 7px;
  border-radius: 9999px;
  background: var(--stage);
  flex-shrink: 0;
}
.cevico-stage-funnel {
  font-weight: 400;
  opacity: 0.7;
}
</style>
