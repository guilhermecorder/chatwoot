<script setup>
// 💠 Card de KPI padrão CEVICO dos dashboards de Relatórios.
// Gradiente por dashboard, número com contagem animada e ESTADOS VIVOS
// contra a meta do mês do Painel de Metas:
//   🏆 record   = melhor mês dos últimos 12 → aura de átomos dourada
//   🎯 hit      = meta do mês batida → brilho verde pulsando
//   ⏳ low      = abaixo do ritmo esperado → selo âmbar
//   🚨 critical = muito abaixo do ritmo → anel vermelho pulsando
// Respeita prefers-reduced-motion (os estados viram só selos, sem animação).
import { ref, computed, watch, onMounted } from 'vue';
import TileAura from 'dashboard/components-next/radar/TileAura.vue';

const props = defineProps({
  label: { type: String, required: true },
  // Number = anima a contagem; String = mostra como veio
  value: { type: [String, Number], required: true },
  sub: { type: String, default: '' },
  prefix: { type: String, default: '' }, // ex.: "R$ "
  suffix: { type: String, default: '' }, // ex.: "%"
  // gradiente do card; vazio = card claro (branco/dark)
  from: { type: String, default: '' },
  to: { type: String, default: '' },
  valueColor: { type: String, default: '' }, // cor do número no card claro
  state: { type: String, default: '' }, // record | hit | low | critical
  // meta do mês (Painel de Metas): { current, target }
  goal: { type: Object, default: null },
  compact: { type: Boolean, default: false },
});

const isGradient = computed(() => Boolean(props.from && props.to));

// ── contagem animada (só quando value é número) ──
const displayNum = ref(0);
let raf = null;
const animateTo = target => {
  cancelAnimationFrame(raf);
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    displayNum.value = target;
    return;
  }
  const start = displayNum.value;
  const t0 = performance.now();
  const dur = 750;
  const tick = now => {
    const t = Math.min(1, (now - t0) / dur);
    const eased = 1 - (1 - t) ** 3; // easeOutCubic
    displayNum.value = start + (target - start) * eased;
    if (t < 1) raf = requestAnimationFrame(tick);
  };
  raf = requestAnimationFrame(tick);
};
onMounted(() => {
  if (typeof props.value === 'number') animateTo(props.value);
});
watch(
  () => props.value,
  v => {
    if (typeof v === 'number') animateTo(v);
  }
);

const shownValue = computed(() =>
  typeof props.value === 'number'
    ? Math.round(displayNum.value).toLocaleString('pt-BR')
    : props.value
);

// ── selo do estado ──
const STATE_META = {
  record: { emoji: '🏆', text: 'recorde de 12 meses' },
  hit: { emoji: '🎯', text: 'meta do mês batida' },
  low: { emoji: '⏳', text: 'abaixo do ritmo da meta' },
  critical: { emoji: '🚨', text: 'muito abaixo da meta' },
};
const stateMeta = computed(() => STATE_META[props.state] || null);

const goalPct = computed(() => {
  if (!props.goal?.target) return 0;
  return Math.min(
    100,
    Math.round((Number(props.goal.current || 0) / props.goal.target) * 100)
  );
});
const goalBarColor = computed(() => {
  if (props.state === 'critical') return '#EF4444';
  if (props.state === 'low') return '#F59E0B';
  return '#34D399';
});
</script>

<template>
  <div
    class="cevico-kpi relative rounded-2xl overflow-visible"
    :class="{
      'cevico-kpi--hit': state === 'hit',
      'cevico-kpi--critical': state === 'critical',
      'cevico-kpi--record': state === 'record',
    }"
  >
    <TileAura v-if="state === 'record'" :intensity="1" gold />
    <div
      class="relative rounded-2xl h-full"
      :class="[
        compact ? 'px-4 py-3' : 'p-5',
        isGradient
          ? 'text-white shadow-lg'
          : 'bg-white dark:bg-n-solid-2 border-2 border-n-weak shadow-sm',
      ]"
      :style="isGradient ? { background: `linear-gradient(135deg, ${from}, ${to})` } : {}"
    >
      <p
        class="mb-1.5 font-medium"
        :class="[compact ? 'text-[11px]' : 'text-xs', isGradient ? 'text-white/80' : 'text-n-slate-10']"
      >
        {{ label }}
      </p>
      <p
        class="font-bold leading-tight"
        :class="compact ? 'text-2xl' : 'text-3xl'"
        :style="!isGradient && valueColor ? { color: valueColor } : {}"
      >
        {{ prefix }}{{ shownValue }}{{ suffix }}
      </p>
      <p
        v-if="sub"
        class="mt-1"
        :class="[compact ? 'text-[10px]' : 'text-xs', isGradient ? 'text-white/70' : 'text-n-slate-9']"
      >
        {{ sub }}
      </p>

      <!-- meta do mês (Painel de Metas) -->
      <div v-if="goal?.target" class="mt-2">
        <div
          class="h-1.5 rounded-full overflow-hidden"
          :class="isGradient ? 'bg-white/25' : 'bg-n-alpha-1'"
        >
          <div
            class="h-full rounded-full transition-all duration-700"
            :style="{ width: `${Math.max(goalPct, 3)}%`, background: goalBarColor }"
          />
        </div>
        <p
          class="text-[10px] mt-0.5"
          :class="isGradient ? 'text-white/70' : 'text-n-slate-9'"
        >
          meta do mês: {{ Number(goal.current || 0).toLocaleString('pt-BR') }} de
          {{ Number(goal.target).toLocaleString('pt-BR') }} · {{ goalPct }}%
        </p>
      </div>

      <!-- selo do estado -->
      <span
        v-if="stateMeta"
        class="cevico-kpi__chip absolute -top-2 right-3 text-[10px] font-bold px-2 py-0.5 rounded-full shadow whitespace-nowrap"
        :class="{
          'cevico-kpi__chip--record': state === 'record',
          'cevico-kpi__chip--hit': state === 'hit',
          'cevico-kpi__chip--low': state === 'low',
          'cevico-kpi__chip--critical': state === 'critical',
        }"
      >
        {{ stateMeta.emoji }} {{ stateMeta.text }}
      </span>
    </div>
  </div>
</template>

<style scoped>
/* 🎯 meta batida: respiração verde */
.cevico-kpi--hit > div {
  animation: cevico-kpi-hit 2.4s ease-in-out infinite;
}
@keyframes cevico-kpi-hit {
  0%, 100% { box-shadow: 0 0 0 0 rgba(52, 211, 153, 0); }
  50% { box-shadow: 0 0 22px 2px rgba(52, 211, 153, 0.55); }
}

/* 🏆 recorde: brilho dourado constante (a aura orbita por cima) */
.cevico-kpi--record > div {
  box-shadow: 0 0 26px 2px rgba(212, 160, 23, 0.4);
}

/* 🚨 muito abaixo: anel vermelho pulsando (chama atenção sem gritar) */
.cevico-kpi--critical > div {
  animation: cevico-kpi-critical 1.6s ease-in-out infinite;
}
@keyframes cevico-kpi-critical {
  0%, 100% { box-shadow: 0 0 0 0 rgba(239, 68, 68, 0); }
  50% { box-shadow: 0 0 0 4px rgba(239, 68, 68, 0.35); }
}

.cevico-kpi__chip--record {
  color: #78350f;
  background: linear-gradient(110deg, #fcd34d 20%, #fff7d6 40%, #fcd34d 60%);
  background-size: 200% 100%;
  animation: cevico-chip-shimmer 2.2s linear infinite;
}
@keyframes cevico-chip-shimmer {
  to { background-position: -200% 0; }
}
.cevico-kpi__chip--hit { background: #059669; color: #fff; }
.cevico-kpi__chip--low { background: #f59e0b; color: #451a03; }
.cevico-kpi__chip--critical { background: #dc2626; color: #fff; }

@media (prefers-reduced-motion: reduce) {
  .cevico-kpi--hit > div,
  .cevico-kpi--critical > div,
  .cevico-kpi__chip--record {
    animation: none;
  }
}
</style>
