<script setup>
// Régua de período PADRÃO do sistema (06/08; item 321 — 03/10: a mesma em
// todos os ambientes):
//   Hoje | Ontem | Últimos 7 dias | Semana passada | Este mês | Mês passado |
//   90 dias | Este ano | Personalizado
//
// v-model = { preset, from, to } — from/to SEMPRE preenchidos (YYYY-MM-DD),
// mesmo nos presets, para telas cujo backend só entende De/Até. Backends
// migrados usam o preset direto (concern Crm::ResolvesPeriod).
import { ref, computed, watch } from 'vue';
import {
  PERIOD_PRESETS,
  periodDateStr,
  periodRangeFor,
} from 'dashboard/helper/cevicoPeriod';

const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({ preset: 'month', from: '', to: '' }),
  },
  // esconde pílulas específicas quando uma tela não suporta (evitar!)
  hiddenPresets: { type: Array, default: () => [] },
  // 🍎 formato novo (rodada 161): a régua veste o segmentado de vidro do
  // kit .cv-* (cor do dia). Só o Meu Painel liga; os relatórios seguem iguais.
  glass: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

// item 321: a lista é UMA só para o sistema inteiro (helper/cevicoPeriod.js)
const presets = computed(() =>
  PERIOD_PRESETS.filter(p => !props.hiddenPresets.includes(p.key))
);

const dateStr = periodDateStr;
const rangeFor = periodRangeFor;

const activePreset = computed(() => props.modelValue?.preset ?? 'month');

const showCustom = ref(false);
const customFrom = ref(
  props.modelValue?.preset === 'custom' ? props.modelValue.from : ''
);
const customTo = ref(
  props.modelValue?.preset === 'custom' ? props.modelValue.to : ''
);

watch(
  () => props.modelValue,
  v => {
    if (v?.preset === 'custom') {
      customFrom.value = v.from || '';
      customTo.value = v.to || '';
    }
  }
);

const pick = key => {
  showCustom.value = false;
  emit('update:modelValue', { preset: key, ...rangeFor(key) });
};

const applyCustom = () => {
  if (!customFrom.value && !customTo.value) return;
  const from = customFrom.value || customTo.value;
  const to = customTo.value || dateStr(new Date());
  emit('update:modelValue', { preset: 'custom', from, to });
};

const clearCustom = () => {
  customFrom.value = '';
  customTo.value = '';
  showCustom.value = false;
  pick('month');
};
</script>

<template>
  <!-- item 321: com 9 opções a régua QUEBRA em duas linhas quando não cabe
       (no celular continua rolando para o lado) -->
  <div
    class="inline-flex items-center gap-0.5 max-w-full flex-nowrap overflow-x-auto md:flex-wrap md:overflow-visible"
    :class="
      glass
        ? 'cv-seg'
        : 'min-h-[34px] py-0.5 bg-n-solid-2 border border-n-weak rounded-xl px-0.5'
    "
  >
    <span
      class="i-lucide-calendar-clock text-sm ml-2 mr-0.5 flex-shrink-0"
      :style="{ color: glass ? 'var(--cv)' : '#7c3aed' }"
    />
    <button
      v-for="p in presets"
      :key="p.key"
      class="text-xs font-medium transition-colors whitespace-nowrap flex-shrink-0"
      :class="
        glass
          ? ['cv-seg-item', activePreset === p.key ? 'cv-seg-on' : '']
          : [
              'h-7 px-2.5 rounded-lg',
              activePreset === p.key
                ? 'text-white'
                : 'text-n-slate-11 hover:bg-n-alpha-1',
            ]
      "
      :style="
        !glass && activePreset === p.key
          ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' }
          : {}
      "
      @click="pick(p.key)"
    >
      {{ p.label }}
    </button>

    <div class="relative flex-shrink-0">
      <button
        class="text-xs font-medium transition-colors whitespace-nowrap"
        :class="
          glass
            ? ['cv-seg-item', activePreset === 'custom' ? 'cv-seg-on' : '']
            : [
                'h-7 px-2.5 rounded-lg',
                activePreset === 'custom'
                  ? 'text-white'
                  : 'text-n-slate-11 hover:bg-n-alpha-1',
              ]
        "
        :style="
          !glass && activePreset === 'custom'
            ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' }
            : {}
        "
        title="Escolher um intervalo de datas"
        @click="showCustom = !showCustom"
      >
        Personalizado
      </button>
      <div
        v-if="showCustom"
        class="absolute top-9 right-0 z-50 p-3 flex items-center gap-2"
        :class="
          glass
            ? 'cv-pop'
            : 'bg-white dark:bg-n-solid-2 border border-n-weak rounded-2xl shadow-xl'
        "
        @click.stop
      >
        <input
          v-model="customFrom"
          type="date"
          class="h-8 text-xs text-n-slate-12"
          :class="
            glass
              ? 'cv-input !h-8 !rounded-full'
              : 'border border-n-weak rounded-full px-2.5 bg-n-solid-1'
          "
          style="width: 8.4rem"
          title="De"
          @change="applyCustom"
        />
        <span class="text-[10px] text-n-slate-9">até</span>
        <input
          v-model="customTo"
          type="date"
          class="h-8 text-xs text-n-slate-12"
          :class="
            glass
              ? 'cv-input !h-8 !rounded-full'
              : 'border border-n-weak rounded-full px-2.5 bg-n-solid-1'
          "
          style="width: 8.4rem"
          title="Até (vazio = hoje)"
          @change="applyCustom"
        />
        <button
          class="w-7 h-7 rounded-full flex items-center justify-center text-n-slate-10 hover:bg-n-alpha-1"
          title="Limpar intervalo"
          @click="clearCustom"
        >
          <span class="i-lucide-x text-xs" />
        </button>
      </div>
    </div>
  </div>
</template>
