<script setup>
// CELEBRAÇÃO (rodada 25): "anime os relatórios nos indicadores em que
// houve progresso — bonito, animado, alegre, colorido, na nossa paleta".
// Sobreposição de vidro azul-noite com partículas leves, medalhão que
// pulsa, cartões que entram em cascata, números que CONTAM até o valor
// e barras que enchem. Respeita prefers-reduced-motion. Vale pra semana
// fechada (Warrior ou programa pessoal) e pra medição registrada.
import { ref, watch, onBeforeUnmount } from 'vue';
import { ROYAL, ROYAL_CLARO, LARANJA, LARANJA_CLARO, GRAD_LARANJA } from './palette';

const props = defineProps({
  // { emoji, title, subtitle, items: [{ icon, label, big?, value?, suffix?, pct?, sub?, small? }] }
  data: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const COLORS = [ROYAL, ROYAL_CLARO, LARANJA, LARANJA_CLARO, '#ffffff'];
const particles = ref([]);
const counts = ref({});
let raf = null;

const makeParticles = () =>
  Array.from({ length: 26 }, (_, i) => {
    const size = 5 + Math.round(Math.random() * 7);
    return {
      id: i,
      style: {
        left: `${Math.round(Math.random() * 100)}%`,
        width: `${size}px`,
        height: `${size}px`,
        background: COLORS[i % COLORS.length],
        borderRadius: i % 3 === 0 ? '50%' : '2px',
        animationDelay: `${(Math.random() * 1.6).toFixed(2)}s`,
        animationDuration: `${(2.8 + Math.random() * 2.2).toFixed(2)}s`,
        opacity: 0.55 + Math.random() * 0.45,
      },
    };
  });

// números "contando" até o valor (ease-out), um por cartão
const runCounters = items => {
  if (raf) cancelAnimationFrame(raf);
  const targets = items.map(it => (typeof it.big === 'number' ? it.big : null));
  const reduce =
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches;
  const start = performance.now();
  const dur = reduce ? 0 : 1100;
  const tick = now => {
    const t = dur ? Math.min(1, (now - start) / dur) : 1;
    const e = 1 - (1 - t) ** 3;
    const next = {};
    targets.forEach((v, i) => {
      if (v === null) return;
      next[i] = Number.isInteger(v) ? Math.round(v * e) : Math.round(v * e * 10) / 10;
    });
    counts.value = next;
    if (t < 1) raf = requestAnimationFrame(tick);
  };
  raf = requestAnimationFrame(tick);
};

watch(
  () => props.data,
  d => {
    if (!d) return;
    particles.value = makeParticles();
    runCounters(d.items || []);
  },
  { immediate: true }
);
onBeforeUnmount(() => raf && cancelAnimationFrame(raf));

const fmt = v => String(v).replace('.', ',');
const shown = (it, i) => {
  if (typeof it.big === 'number') return `${fmt(counts.value[i] ?? 0)}${it.suffix || ''}`;
  return it.value || '';
};
</script>

<template>
  <Teleport to="body">
    <Transition name="hub-cele">
      <div v-if="data" class="hub-cele-backdrop" role="dialog" aria-modal="true" @click.self="emit('close')">
        <div class="hub-cele-particles" aria-hidden="true">
          <span v-for="p in particles" :key="p.id" class="hub-cele-particle" :style="p.style" />
        </div>
        <div class="hub-cele-card">
          <div class="hub-cele-shine" aria-hidden="true" />
          <div class="hub-cele-badge-wrap">
            <span class="hub-cele-ring" />
            <span class="hub-cele-ring hub-cele-ring-2" />
            <span class="hub-cele-badge" :style="{ background: GRAD_LARANJA }"><span v-if="data.ico" :class="data.ico" class="hub-cele-badge-ico" /><template v-else>{{ data.emoji }}</template></span>
          </div>
          <h2 class="hub-cele-title">{{ data.title }}</h2>
          <p class="hub-cele-sub">{{ data.subtitle }}</p>

          <div class="hub-cele-items">
            <div
              v-for="(it, i) in data.items"
              :key="`${it.label}-${i}`"
              class="hub-cele-item"
              :class="{ 'hub-cele-item-small': it.small }"
              :style="{ animationDelay: `${0.35 + i * 0.13}s` }"
            >
              <span class="hub-cele-icon" :style="{ background: it.small ? 'rgba(65,105,225,0.25)' : 'rgba(255,138,0,0.22)' }"><span v-if="it.ico" :class="it.ico" class="hub-cele-item-ico" /><template v-else>{{ it.icon }}</template></span>
              <div class="hub-cele-body">
                <p class="hub-cele-label">{{ it.label }}</p>
                <p class="hub-cele-value">{{ shown(it, i) }}</p>
                <p v-if="it.sub" class="hub-cele-small">{{ it.sub }}</p>
                <div class="hub-cele-bar" aria-hidden="true">
                  <i :style="{ width: `${Math.round(Math.max(0.08, Math.min(1, it.pct ?? 0.5)) * 100)}%`, animationDelay: `${0.5 + i * 0.13}s` }" />
                </div>
              </div>
              <span class="hub-cele-up">▲</span>
            </div>
          </div>

          <button class="hub-cele-btn" :style="{ background: GRAD_LARANJA }" @click="emit('close')">
            Continuar
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.hub-cele-backdrop {
  position: fixed;
  inset: 0;
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: radial-gradient(120% 90% at 50% 0%, rgba(65, 105, 225, 0.45), rgba(17, 28, 63, 0.92) 55%, rgba(8, 12, 30, 0.96));
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  overflow: hidden;
}
.hub-cele-enter-active,
.hub-cele-leave-active {
  transition: opacity 0.35s ease;
}
.hub-cele-enter-from,
.hub-cele-leave-to {
  opacity: 0;
}
.hub-cele-enter-active .hub-cele-card {
  animation: hub-cele-pop 0.55s cubic-bezier(0.2, 1.4, 0.4, 1) both;
}
@keyframes hub-cele-pop {
  from {
    transform: translateY(24px) scale(0.92);
    opacity: 0;
  }
  to {
    transform: none;
    opacity: 1;
  }
}

.hub-cele-particles {
  position: absolute;
  inset: 0;
  pointer-events: none;
}
.hub-cele-particle {
  position: absolute;
  top: -12px;
  display: block;
  animation-name: hub-cele-fall;
  animation-timing-function: linear;
  animation-iteration-count: infinite;
  box-shadow: 0 0 10px rgba(255, 255, 255, 0.35);
}
@keyframes hub-cele-fall {
  0% {
    transform: translateY(-5vh) rotate(0deg);
  }
  100% {
    transform: translateY(105vh) rotate(540deg);
  }
}

.hub-cele-card {
  position: relative;
  width: 100%;
  max-width: 440px;
  max-height: calc(100vh - 32px);
  overflow-y: auto;
  border-radius: 28px;
  padding: 28px 22px 22px;
  color: #fff;
  text-align: center;
  background: linear-gradient(160deg, rgba(255, 255, 255, 0.16), rgba(255, 255, 255, 0.06) 45%, rgba(65, 105, 225, 0.18));
  border: 1px solid rgba(255, 255, 255, 0.28);
  box-shadow:
    0 30px 80px rgba(0, 0, 0, 0.45),
    inset 0 1px 0 rgba(255, 255, 255, 0.45);
}
.hub-cele-shine {
  position: absolute;
  top: 0;
  left: -60%;
  width: 50%;
  height: 100%;
  background: linear-gradient(105deg, transparent, rgba(255, 255, 255, 0.22), transparent);
  animation: hub-cele-shine 2.6s ease-in-out 0.6s 1;
  pointer-events: none;
}
@keyframes hub-cele-shine {
  to {
    left: 120%;
  }
}

.hub-cele-badge-wrap {
  position: relative;
  width: 84px;
  height: 84px;
  margin: 0 auto 12px;
}
.hub-cele-badge-ico { width: 36px; height: 36px; color: #fff; display: block; }
.hub-cele-item-ico { width: 20px; height: 20px; color: #fff; display: block; }
.hub-cele-item-small .hub-cele-item-ico { width: 16px; height: 16px; }
.hub-cele-badge {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  font-size: 38px;
  box-shadow: 0 12px 30px rgba(255, 107, 26, 0.45);
  animation: hub-cele-bounce 1.6s ease-in-out 0.3s infinite;
}
@keyframes hub-cele-bounce {
  0%,
  100% {
    transform: translateY(0) scale(1);
  }
  50% {
    transform: translateY(-4px) scale(1.04);
  }
}
.hub-cele-ring {
  position: absolute;
  inset: -6px;
  border-radius: 50%;
  border: 2px solid rgba(255, 178, 94, 0.8);
  animation: hub-cele-ring 1.8s ease-out 0.2s infinite;
}
.hub-cele-ring-2 {
  border-color: rgba(143, 169, 245, 0.8);
  animation-delay: 0.8s;
}
@keyframes hub-cele-ring {
  from {
    transform: scale(0.85);
    opacity: 0.9;
  }
  to {
    transform: scale(1.7);
    opacity: 0;
  }
}

.hub-cele-title {
  font-size: 22px;
  font-weight: 900;
  letter-spacing: -0.01em;
  color: #fff;
  margin: 0 0 4px;
}
.hub-cele-sub {
  font-size: 12px;
  opacity: 0.88;
  margin: 0 auto 16px;
  max-width: 34ch;
}

.hub-cele-items {
  display: flex;
  flex-direction: column;
  gap: 8px;
  text-align: left;
  margin-bottom: 18px;
}
.hub-cele-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.18);
  animation: hub-cele-in 0.5s cubic-bezier(0.2, 1.2, 0.4, 1) both;
}
.hub-cele-item-small {
  padding: 7px 12px;
}
@keyframes hub-cele-in {
  from {
    transform: translateX(-18px);
    opacity: 0;
  }
  to {
    transform: none;
    opacity: 1;
  }
}
.hub-cele-icon {
  width: 38px;
  height: 38px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  flex-shrink: 0;
}
.hub-cele-item-small .hub-cele-icon {
  width: 30px;
  height: 30px;
  font-size: 14px;
}
.hub-cele-body {
  flex: 1;
  min-width: 0;
}
.hub-cele-label {
  font-size: 11px;
  opacity: 0.85;
  margin: 0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.hub-cele-value {
  font-size: 22px;
  font-weight: 900;
  line-height: 1.1;
  margin: 0;
  color: #ffb25e;
  text-shadow: 0 0 18px rgba(255, 138, 0, 0.45);
}
.hub-cele-item-small .hub-cele-value {
  font-size: 15px;
  color: #8fa9f5;
  text-shadow: 0 0 14px rgba(65, 105, 225, 0.5);
}
.hub-cele-small {
  font-size: 10px;
  opacity: 0.75;
  margin: 2px 0 0;
}
.hub-cele-bar {
  height: 4px;
  margin-top: 6px;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.14);
  overflow: hidden;
}
.hub-cele-item-small .hub-cele-bar {
  display: none;
}
.hub-cele-bar i {
  display: block;
  height: 100%;
  border-radius: 999px;
  background: linear-gradient(90deg, #4169e1, #8fa9f5 50%, #ff8a00);
  transform-origin: left;
  animation: hub-cele-fill 0.9s cubic-bezier(0.2, 0.9, 0.3, 1) both;
  box-shadow: 0 0 10px rgba(255, 138, 0, 0.55);
}
@keyframes hub-cele-fill {
  from {
    transform: scaleX(0);
  }
  to {
    transform: scaleX(1);
  }
}
.hub-cele-up {
  color: #ffb25e;
  font-size: 14px;
  font-weight: 900;
  animation: hub-cele-up 1.2s ease-in-out infinite;
}
@keyframes hub-cele-up {
  0%,
  100% {
    transform: translateY(0);
    opacity: 0.7;
  }
  50% {
    transform: translateY(-3px);
    opacity: 1;
  }
}

.hub-cele-btn {
  width: 100%;
  height: 46px;
  border-radius: 14px;
  border: 0;
  color: #fff;
  font-weight: 800;
  font-size: 14px;
  box-shadow: 0 10px 26px rgba(255, 107, 26, 0.4);
  cursor: pointer;
  transition: transform 0.12s ease;
}
.hub-cele-btn:active {
  transform: scale(0.98);
}

@media (prefers-reduced-motion: reduce) {
  .hub-cele-particle,
  .hub-cele-badge,
  .hub-cele-ring,
  .hub-cele-shine,
  .hub-cele-up,
  .hub-cele-item,
  .hub-cele-bar i,
  .hub-cele-enter-active .hub-cele-card {
    animation: none !important;
  }
}
</style>
