<script setup>
// 🕸️ Teia "este criativo × média × recorde da conta" (item 287, rodada 3):
// Gancho, Corpo, CTA, Conversa e Agendamento. A borda de fora (100) é o
// RECORDE da conta em cada ponta; a figura cheia é este anúncio e a tracejada
// é a média. Ao lado, os três valores escritos. Dados: `scorecard.radar`.
import { computed } from 'vue';
import MiniRadar from 'dashboard/components-next/cevico/MiniRadar.vue';

const props = defineProps({
  radar: { type: Object, required: true },
  color: { type: String, default: '#2563eb' },
  size: { type: Number, default: 240 },
});

const list = computed(() => props.radar.axes || []);
const axes = computed(() =>
  list.value.map(a => ({ key: a.key, label: a.label, short: a.label }))
);
const pick = (field, text) =>
  Object.fromEntries(list.value.map(a => [a.key, a[field] ?? text]));
const datasets = computed(() => {
  const sets = [
    {
      key: 'ad',
      label: 'este criativo',
      color: props.color,
      values: pick('score', 0),
      texts: pick('value_text', ''),
    },
  ];
  if (list.value.some(a => a.avg_score !== null && a.avg_score !== undefined))
    sets.push({
      key: 'avg',
      label: 'média da conta',
      color: '#94a3b8',
      dashed: true,
      values: pick('avg_score', 0),
      texts: pick('avg_text', ''),
    });
  if (list.value.some(a => a.record_score))
    sets.push({
      key: 'record',
      label: 'recorde da conta (borda)',
      color: '#d4a017',
      dashed: true,
      values: pick('record_score', 0),
      texts: pick('record_text', ''),
    });
  return sets;
});
</script>

<template>
  <div
    class="grid grid-cols-1 md:grid-cols-[auto_minmax(0,1fr)] gap-6 items-center"
  >
    <div class="flex justify-center px-14 py-2">
      <MiniRadar :axes="axes" :datasets="datasets" :size="size" legend />
    </div>
    <div class="min-w-0">
      <ul class="flex flex-col gap-2.5 list-none p-0 m-0">
        <li
          v-for="a in list"
          :key="a.key"
          class="cv-row px-5 py-3.5 grid grid-cols-[minmax(0,1fr)_auto_auto] gap-x-4 items-baseline text-sm"
        >
          <span class="font-bold text-n-slate-12">{{ a.label }}</span>
          <span class="tabular-nums text-lg font-extrabold text-n-slate-12">
            {{ a.value_text }}
          </span>
          <span class="tabular-nums text-sm text-n-slate-10">
            média {{ a.avg_text || '—' }}
          </span>
          <span class="col-span-3 text-[13px] text-n-slate-9">
            <template v-if="a.is_record">
              🏆 este anúncio é o recorde da conta
            </template>
            <template v-else-if="a.record_text">
              recorde da conta {{ a.record_text }}
              <template v-if="a.record_ad">({{ a.record_ad }})</template>
              · está em {{ a.score }}% do recorde
            </template>
            <template v-else>a conta ainda não tem recorde aqui</template>
          </span>
        </li>
      </ul>
      <p class="text-[13px] text-n-slate-9 mt-2 leading-snug">
        {{ radar.note }}
      </p>
    </div>
  </div>
</template>
