<script setup>
// Chavinhas que escolhem os eixos da teia de UM ambiente (fichas, tabela,
// Ver a fundo, Comparar, Recordes, peças). A escolha vale para todos os
// cards daquele ambiente e fica guardada no navegador. Mínimo 3 eixos.
import { computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import { availableAxes, useRadarAxes, DEFAULT_AXES } from './radarAxes';

const props = defineProps({
  env: { type: String, required: true },
  scope: { type: String, default: 'creative' },
  relativeOk: { type: Boolean, default: true },
  label: { type: String, default: 'Teia' },
});

const { isOn, toggle } = useRadarAxes(props.env, DEFAULT_AXES[props.scope]);
const options = computed(() => availableAxes(props.scope, props.relativeOk));
const flip = key => {
  if (!toggle(key)) useAlert('A teia precisa de pelo menos 3 eixos.');
};
</script>

<template>
  <div class="flex items-center gap-x-3 gap-y-1.5 flex-wrap text-[11px]">
    <span
      class="inline-flex items-center gap-1 text-n-slate-10 font-semibold"
      title="Escolha o que a teia mede. 100 = atingiu o parâmetro bom; 50 = na linha do ruim; sem parâmetro, contra o melhor do recorte."
    >
      <span class="i-lucide-radar text-sm" />{{ label }}
    </span>
    <button
      v-for="a in options"
      :key="a.key"
      type="button"
      class="inline-flex items-center gap-1.5"
      :title="a.metric"
      @click="flip(a.key)"
    >
      <span class="cv-switch" :class="{ 'cv-switch-on': isOn(a.key) }" />
      <span
        :class="
          isOn(a.key) ? 'text-n-slate-12 font-semibold' : 'text-n-slate-10'
        "
        >{{ a.label }}</span
      >
    </button>
  </div>
</template>
