<script setup>
import { computed } from 'vue';

const props = defineProps({
  label: {
    type: [Object, String],
    required: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
  color: {
    type: String,
    default: 'slate',
    validator: value =>
      ['slate', 'amber', 'teal', 'ruby', 'blue', 'iris'].includes(value),
  },
});

const COLOR_CLASSES = {
  slate: 'bg-n-label-color outline-n-label-border text-n-slate-12',
  amber: 'bg-n-amber-2 outline-n-amber-4 text-n-amber-11',
  teal: 'bg-n-teal-2 outline-n-teal-4 text-n-teal-11',
  ruby: 'bg-n-ruby-2 outline-n-ruby-4 text-n-ruby-11',
  blue: 'bg-n-blue-2 outline-n-blue-4 text-n-blue-11',
  iris: 'bg-n-iris-2 outline-n-iris-4 text-n-iris-11',
};

const isStringLabel = computed(() => typeof props.label === 'string');

const labelTitle = computed(() => {
  return isStringLabel.value ? props.label : props.label?.title;
});

const labelDescription = computed(() => {
  return (!isStringLabel.value && props.label?.description) || '';
});

const labelColor = computed(() => {
  return isStringLabel.value ? null : props.label.color;
});

const colorClasses = computed(() => COLOR_CLASSES[props.color]);
</script>

<template>
  <!-- CEVICO 212: com cor própria vira pílula com a tinta da cor (cv-tag-tint) -->
  <div
    :title="labelDescription"
    class="rounded-full -outline-offset-1 outline outline-1 inline-flex items-center flex-shrink-0"
    :class="[
      colorClasses,
      labelColor ? 'cv-tag-tint font-semibold' : '',
      compact ? 'px-2 h-6 gap-1 rounded-full' : 'px-3 h-8 gap-1.5 rounded-full',
    ]"
    :style="labelColor ? { '--lb': labelColor } : {}"
  >
    <slot v-if="!labelColor" name="icon" />
    <span
      class="whitespace-nowrap"
      :class="compact ? 'text-label-small' : 'text-label !font-420'"
    >
      {{ labelTitle }}
    </span>
    <slot name="action" />
  </div>
</template>
