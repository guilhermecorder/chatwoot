<script setup>
// Régua de período PADRÃO dos dashboards (06/08):
//   Hoje | Ontem | Últimos 7 dias | Este mês | Este ano | Personalizado
//
// v-model = { preset, from, to } — from/to SEMPRE preenchidos (YYYY-MM-DD),
// mesmo nos presets, para telas cujo backend só entende De/Até. Backends
// migrados usam o preset direto (concern Crm::ResolvesPeriod).
import { ref, computed, watch } from 'vue';

const props = defineProps({
  modelValue: {
    type: Object,
    default: () => ({ preset: 'month', from: '', to: '' }),
  },
  // esconde pílulas específicas quando uma tela não suporta (evitar!)
  hiddenPresets: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const ALL_PRESETS = [
  { key: 'today', label: 'Hoje' },
  { key: 'yesterday', label: 'Ontem' },
  { key: 'last7', label: 'Últimos 7 dias' },
  { key: 'last_week', label: 'Semana passada' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
  { key: 'year', label: 'Este ano' },
];

const presets = computed(() =>
  ALL_PRESETS.filter(p => !props.hiddenPresets.includes(p.key))
);

const pad = n => String(n).padStart(2, '0');
const dateStr = d =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

const rangeFor = key => {
  const now = new Date();
  const today = dateStr(now);
  if (key === 'yesterday') {
    const y = new Date(now);
    y.setDate(y.getDate() - 1);
    const d = dateStr(y);
    return { from: d, to: d };
  }
  if (key === 'last7') {
    const s = new Date(now);
    s.setDate(s.getDate() - 6);
    return { from: dateStr(s), to: today };
  }
  if (key === 'last_week') {
    // semana passada = segunda a domingo ANTERIORES (fuso local)
    const dow = (now.getDay() + 6) % 7; // seg=0 … dom=6
    const end = new Date(now);
    end.setDate(now.getDate() - dow - 1); // domingo passado
    const start = new Date(end);
    start.setDate(end.getDate() - 6); // segunda passada
    return { from: dateStr(start), to: dateStr(end) };
  }
  if (key === 'month') {
    return {
      from: dateStr(new Date(now.getFullYear(), now.getMonth(), 1)),
      to: today,
    };
  }
  if (key === 'last_month') {
    return {
      from: dateStr(new Date(now.getFullYear(), now.getMonth() - 1, 1)),
      to: dateStr(new Date(now.getFullYear(), now.getMonth(), 0)),
    };
  }
  if (key === 'year') {
    return { from: dateStr(new Date(now.getFullYear(), 0, 1)), to: today };
  }
  return { from: today, to: today }; // today
};

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
  <div
    class="inline-flex items-center h-[34px] bg-n-solid-2 border border-n-weak rounded-xl px-0.5 gap-0.5 flex-nowrap overflow-x-auto md:overflow-visible"
  >
    <span
      class="i-lucide-calendar-clock text-sm ml-2 mr-0.5 flex-shrink-0"
      style="color: #7c3aed"
    />
    <button
      v-for="p in presets"
      :key="p.key"
      class="h-7 px-2.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap flex-shrink-0"
      :class="
        activePreset === p.key
          ? 'text-white'
          : 'text-n-slate-11 hover:bg-n-alpha-1'
      "
      :style="
        activePreset === p.key
          ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' }
          : {}
      "
      @click="pick(p.key)"
    >
      {{ p.label }}
    </button>

    <div class="relative flex-shrink-0">
      <button
        class="h-7 px-2.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap"
        :class="
          activePreset === 'custom'
            ? 'text-white'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        :style="
          activePreset === 'custom'
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
        class="absolute top-9 right-0 z-50 bg-white dark:bg-n-solid-2 border border-n-weak rounded-2xl shadow-xl p-3 flex items-center gap-2"
        @click.stop
      >
        <input
          v-model="customFrom"
          type="date"
          class="h-8 text-xs border border-n-weak rounded-full px-2.5 bg-n-solid-1 text-n-slate-12"
          style="width: 8.4rem"
          title="De"
          @change="applyCustom"
        />
        <span class="text-[10px] text-n-slate-9">até</span>
        <input
          v-model="customTo"
          type="date"
          class="h-8 text-xs border border-n-weak rounded-full px-2.5 bg-n-solid-1 text-n-slate-12"
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
