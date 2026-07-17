<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  to: { type: [Object, String], default: '' },
  label: { type: String, default: '' },
  icon: { type: [String, Object], default: '' },
  iconColor: { type: String, default: null },
  expandable: { type: Boolean, default: false },
  isExpanded: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  hasActiveChild: { type: Boolean, default: false },
  getterKeys: { type: Object, default: () => ({}) },
  // CEVICO: cor do contador por tipo de aviso — 'green' (oportunidade,
  // coisa boa) | 'gold' (tarefa, dourado brilhante) | null (neutro)
  countVariant: { type: String, default: null },
});

const emit = defineEmits(['toggle']);

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
const count = computed(() =>
  dynamicCount.value > 99 ? '99+' : dynamicCount.value
);
</script>

<template>
  <component
    :is="to ? 'router-link' : 'div'"
    class="flex items-center gap-2 px-1.5 py-1 rounded-lg h-8 min-w-0"
    role="button"
    draggable="false"
    :to="to"
    :title="label"
    :class="{
      'text-n-slate-12 bg-n-alpha-2 font-medium': isActive && !hasActiveChild,
      'text-n-slate-12 font-medium': hasActiveChild,
      'text-n-slate-11 hover:bg-n-alpha-2': !isActive && !hasActiveChild,
    }"
    @click.stop="emit('toggle')"
  >
    <div v-if="icon" class="relative flex items-center gap-2">
      <Icon
        v-if="icon"
        :icon="icon"
        class="size-4"
        :class="countVariant === 'radar' && dynamicCount ? 'cevico-radar-icon' : ''"
        :style="countVariant === 'radar' && dynamicCount ? { color: '#10B981' } : (iconColor ? { color: iconColor } : {})"
      />
      <span
        v-if="showBadge"
        class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2"
      />
    </div>
    <div
      class="flex items-center gap-1.5 flex-grow justify-between min-w-0 flex-1"
    >
      <span
        class="truncate"
        :class="{
          'text-body-main': !isActive,
          'font-medium text-sm': isActive || hasActiveChild,
        }"
      >
        {{ label }}
      </span>
      <span
        v-if="dynamicCount && !expandable"
        class="inline-grid h-5 min-w-5 place-items-center rounded-full px-1 text-xxs font-medium leading-3 flex-shrink-0"
        :class="{
          'bg-n-slate-4 text-n-slate-12 dark:bg-n-slate-5': !countVariant,
          'bg-green-500 text-white': countVariant === 'green',
          'cevico-gold-badge text-white font-semibold': countVariant === 'gold',
          'cevico-radar-badge text-white font-semibold': countVariant === 'radar',
        }"
      >
        {{ count }}
      </span>
    </div>
    <span
      v-if="expandable"
      v-show="isExpanded"
      class="i-lucide-chevron-up size-3"
      @click.stop="emit('toggle')"
    />
  </component>
</template>

<style scoped>
/* dourado SUTIL: só o círculo com o número + um pulso dourado suave em volta
   (pedido: sem brilho passando — apenas o círculo pulsante) */
.cevico-gold-badge {
  position: relative;
  background: linear-gradient(135deg, #b8860b, #d4a017);
}
.cevico-gold-badge::after {
  content: '';
  position: absolute;
  inset: -2px;
  border-radius: 9999px;
  border: 2px solid rgba(212, 160, 23, 0.65);
  animation: cevico-gold-pulse 2.2s ease-out infinite;
}
@keyframes cevico-gold-pulse {
  0% { transform: scale(0.85); opacity: 0.8; }
  70%, 100% { transform: scale(1.45); opacity: 0; }
}

/* Radar de Oportunidades: VERDE DOPAMINE pulsando — oportunidade é
   convite, não bronca (pedido 17/07); o ícone do menu pulsa junto */
.cevico-radar-badge {
  position: relative;
  background: linear-gradient(135deg, #059669, #4ade80);
  animation: cevico-radar-throb 2.2s ease-in-out infinite;
}
.cevico-radar-badge::after {
  content: '';
  position: absolute;
  inset: -2px;
  border-radius: 9999px;
  border: 2px solid rgba(52, 211, 153, 0.7);
  animation: cevico-radar-ring 2.2s ease-out infinite;
}
.cevico-radar-icon {
  animation: cevico-radar-throb 2.2s ease-in-out infinite;
}
@keyframes cevico-radar-throb {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.55; }
}
@keyframes cevico-radar-ring {
  0% { transform: scale(0.85); opacity: 0.8; }
  70%, 100% { transform: scale(1.5); opacity: 0; }
}
</style>
