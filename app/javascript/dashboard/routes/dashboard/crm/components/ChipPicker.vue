<script setup>
import { ref, computed } from 'vue';

const props = defineProps({
  // [{ id, label, color }]
  options: { type: Array, default: () => [] },
  modelValue: { type: Array, default: () => [] },
  placeholder: { type: String, default: '+ Adicionar' },
  // brand | red | green | purple
  accent: { type: String, default: 'brand' },
});

const emit = defineEmits(['update:modelValue']);

const open = ref(false);
const search = ref('');

const ACCENT = {
  brand:  { chip: 'bg-n-brand/10 border-n-brand text-n-brand', dot: '' },
  red:    { chip: 'bg-red-500/10 border-red-500 text-red-600', dot: '' },
  green:  { chip: 'bg-green-500/10 border-green-500 text-green-600', dot: '' },
  purple: { chip: 'bg-purple-500/10 border-purple-500 text-purple-600', dot: '' },
};

const accentChip = computed(() => ACCENT[props.accent]?.chip ?? ACCENT.brand.chip);

const selectedOptions = computed(() =>
  props.options.filter(o => props.modelValue.includes(o.id))
);

const availableOptions = computed(() => {
  const q = search.value.toLowerCase().trim();
  return props.options.filter(
    o =>
      !props.modelValue.includes(o.id) &&
      (!q || String(o.label).toLowerCase().includes(q))
  );
});

const add = id => {
  emit('update:modelValue', [...props.modelValue, id]);
  search.value = '';
};

const remove = id => {
  emit('update:modelValue', props.modelValue.filter(v => v !== id));
};

const toggleOpen = () => {
  open.value = !open.value;
  search.value = '';
};
</script>

<template>
  <div class="relative">
    <div class="flex flex-wrap items-center gap-1.5">
      <!-- Chips selecionados -->
      <span
        v-for="o in selectedOptions"
        :key="o.id"
        class="text-xs pl-2.5 pr-1 py-1 rounded-full border flex items-center gap-1.5"
        :class="accentChip"
      >
        <span v-if="o.color" class="w-2 h-2 rounded-full" :style="{ backgroundColor: o.color }" />
        {{ o.label }}
        <button
          class="i-lucide-x text-xs opacity-60 hover:opacity-100"
          @click="remove(o.id)"
        />
      </span>

      <!-- Botão adicionar -->
      <button
        class="text-xs px-2.5 py-1 rounded-full border border-dashed border-n-weak text-n-slate-10 hover:border-n-brand hover:text-n-brand transition-colors flex items-center gap-1"
        @click="toggleOpen"
      >
        <span class="i-lucide-plus text-xs" />
        {{ placeholder }}
      </button>
    </div>

    <!-- Dropdown -->
    <div
      v-if="open"
      class="absolute z-30 mt-1.5 w-64 bg-n-solid-1 border border-n-weak rounded-xl shadow-lg overflow-hidden"
    >
      <div class="p-2 border-b border-n-weak">
        <input
          v-model="search"
          class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
          placeholder="Buscar…"
        />
      </div>
      <div class="max-h-48 overflow-y-auto py-1">
        <button
          v-for="o in availableOptions"
          :key="o.id"
          class="w-full flex items-center gap-2 px-3 py-1.5 text-xs text-n-slate-12 hover:bg-n-alpha-1 text-left"
          @click="add(o.id)"
        >
          <span v-if="o.color" class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: o.color }" />
          <span class="truncate">{{ o.label }}</span>
        </button>
        <p v-if="!availableOptions.length" class="text-xs text-n-slate-9 px-3 py-2">
          Nada encontrado
        </p>
      </div>
      <div class="border-t border-n-weak">
        <button
          class="w-full py-1.5 text-xs text-n-slate-10 hover:bg-n-alpha-1"
          @click="open = false"
        >Fechar</button>
      </div>
    </div>
  </div>
</template>
