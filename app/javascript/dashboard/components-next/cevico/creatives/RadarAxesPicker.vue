<script setup>
// Chavinhas das TEIAS de um ambiente (fichas, tabela, Ver a fundo, Comparar,
// Recordes, peças): uma linha por teia — a pergunta que ela responde e os
// eixos que ficam ligados (mínimo 3). Vale para todos os cards do ambiente
// e fica guardado no navegador.
import { computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useRadarAxes, groupsFor } from './radarAxes';

const props = defineProps({
  env: { type: String, required: true },
  scope: { type: String, default: 'creative' },
  relativeOk: { type: Boolean, default: true },
  video: { type: Boolean, default: true },
  only: { type: Array, default: null }, // limitar a algumas teias
});

const { isOn, toggle, optionsFor } = useRadarAxes(props.env);
const groups = computed(() =>
  groupsFor(props.scope, props.relativeOk, props.video).filter(
    g => !props.only || props.only.includes(g.key)
  )
);
const options = g => optionsFor(g.key, props.scope, props.relativeOk);
const flip = (g, key) => {
  if (!toggle(g.key, key)) useAlert('A teia precisa de pelo menos 3 eixos.');
};
</script>

<template>
  <div class="flex flex-col gap-2 text-[11px]">
    <div
      v-for="g in groups"
      :key="g.key"
      class="flex items-center gap-x-2 gap-y-1 flex-wrap"
      :title="g.hint"
    >
      <span
        class="inline-flex items-center gap-1 text-n-slate-12 font-semibold mr-1"
      >
        <span :class="g.icon" class="text-sm" />{{ g.label }}
      </span>
      <button
        v-for="a in options(g)"
        :key="a.key"
        type="button"
        class="cv-chip cursor-pointer"
        :class="isOn(g.key, a.key) ? 'cv-green' : 'opacity-60'"
        :title="`${a.metric} · ${g.question}`"
        @click="flip(g, a.key)"
      >
        <span
          :class="isOn(g.key, a.key) ? 'i-lucide-check' : 'i-lucide-plus'"
          class="text-[10px]"
        />{{ a.label }}
      </button>
    </div>
  </div>
</template>
