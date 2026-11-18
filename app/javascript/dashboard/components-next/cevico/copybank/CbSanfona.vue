<script setup>
// 🪝 item 397: sanfona do Banco de Ganchos — cabeçalho com medalhão, título,
// contagem e um resumo (o que já foi escolhido) quando está fechada.
defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, required: true },
  icon: { type: String, default: 'i-lucide-folder' },
  color: { type: String, default: '' },
  count: { type: [Number, String], default: null },
  desc: { type: String, default: '' },
  summary: { type: String, default: '' },
  size: { type: String, default: 'lg' }, // lg = passo/peça · sm = categoria dentro
  done: { type: Boolean, default: false },
});
const emit = defineEmits(['toggle']);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div class="cv-sub min-w-0" :class="size === 'lg' ? 'mb-5' : 'mb-3'">
    <button
      type="button"
      class="w-full flex items-center gap-3 text-left min-w-0"
      :class="size === 'lg' ? 'p-4 sm:p-5' : 'px-4 py-3'"
      :aria-expanded="open"
      @click="emit('toggle')"
    >
      <span
        class="flex-shrink-0 flex items-center justify-center text-white"
        :class="size === 'lg' ? 'w-10 h-10 rounded-[13px]' : 'w-8 h-8 rounded-[10px]'"
        :style="{ background: color ? `linear-gradient(135deg, ${color}, ${color}cc)` : 'var(--cv-grad, #2563eb)' }"
      >
        <span v-if="done" class="i-lucide-check" :class="size === 'lg' ? 'text-xl' : 'text-base'" />
        <span v-else :class="[icon, size === 'lg' ? 'text-xl' : 'text-base']" />
      </span>
      <span class="min-w-0 flex-1">
        <span class="flex items-center gap-2 flex-wrap">
          <span class="font-bold text-n-slate-12 leading-tight" :class="size === 'lg' ? 'text-lg sm:text-xl tracking-tight' : 'text-[15px]'">{{ title }}</span>
          <span v-if="count !== null" class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11 font-semibold">{{ count }}</span>
        </span>
        <span v-if="!open && summary" class="block text-sm text-n-slate-11 mt-0.5 line-clamp-2 break-words">{{ summary }}</span>
        <span v-else-if="desc" class="block text-xs sm:text-sm text-n-slate-10 mt-0.5">{{ desc }}</span>
      </span>
      <span class="i-lucide-chevron-down text-xl text-n-slate-10 flex-shrink-0 transition-transform duration-200" :class="{ 'rotate-180': open }" />
    </button>
    <div v-if="open" :class="size === 'lg' ? 'px-4 pb-5 sm:px-6 sm:pb-6' : 'px-3 pb-4 sm:px-4'">
      <slot />
    </div>
  </div>
</template>
