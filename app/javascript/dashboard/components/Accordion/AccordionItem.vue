<script setup>
import EmojiOrIcon from 'shared/components/EmojiOrIcon.vue';

defineProps({
  title: {
    type: String,
    required: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
  icon: {
    type: String,
    default: '',
  },
  emoji: {
    type: String,
    default: '',
  },
  isOpen: {
    type: Boolean,
    default: true,
  },
  // CEVICO 199: ícone lucide (classe i-lucide-…) + cor do squircle
  lucide: {
    type: String,
    default: '',
  },
  tone: {
    type: String,
    default: 'slate',
  },
});

const emit = defineEmits(['toggle']);

const onToggle = () => {
  emit('toggle');
};
</script>

<template>
  <div class="text-sm accordion-item">
    <button
      class="flex items-center select-none w-full rounded-lg bg-n-slate-2 outline outline-1 outline-n-weak m-0 cursor-grab justify-between py-2 px-4 drag-handle"
      :class="{ 'rounded-bl-none rounded-br-none': isOpen }"
      @click.stop="onToggle"
    >
      <div class="flex items-center gap-2">
        <span
          v-if="lucide"
          class="cv-side-icon"
          :class="`cv-side-icon-${tone}`"
          ><span :class="lucide"
        /></span>
        <EmojiOrIcon
          v-else-if="icon || emoji"
          class="inline-block w-5"
          :icon="icon"
          :emoji="emoji"
        />
        <h5 class="text-n-slate-12 text-sm mb-0 py-0 pr-2 pl-0">
          {{ title }}
        </h5>
      </div>
      <div class="flex flex-row items-center">
        <slot name="button" />
        <span
          class="accordion-chevron i-lucide-chevron-down text-base text-n-slate-10 transition-transform"
          :class="isOpen ? '' : '-rotate-90'"
        />
      </div>
    </button>
    <div
      v-if="isOpen"
      class="outline outline-1 outline-n-weak -mt-[-1px] border-t-0 rounded-br-lg rounded-bl-lg"
      :class="compact ? 'p-0' : 'px-2 py-4'"
    >
      <slot />
    </div>
  </div>
</template>
