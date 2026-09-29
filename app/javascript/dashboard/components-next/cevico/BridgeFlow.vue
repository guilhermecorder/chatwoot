<script setup>
// 🌉 BridgeFlow (kit CEVICO, item 285 — 29/09): a PONTE entre dois números
// que moram na mesma tela e não batem ("4 entraram na coluna × 13 marcadas").
// Filosofia dele: revelar os dados pelas conexões — de onde veio, como se
// ramifica, pra onde vai. Cada número vira uma raiz com os seus RAMOS
// (fitas com a grossura do tamanho de cada ramo); o ramo em comum é
// destacado nos dois lados. Clicar num ramo emite `pick` (a tela abre os nomes).
//   sides = [{ key, title, total, unit, color, caption, branches: [
//             { key, label, hint, count, stages: [{ name, color, count }] } ] }]
//   shared = chave do ramo que existe nos dois lados ('both')
import { computed } from 'vue';

const props = defineProps({
  sides: { type: Array, default: () => [] },
  shared: { type: String, default: 'both' },
});
const emit = defineEmits(['pick']);

const ROW = 64;
const GAP = 10;
const RIBBON_W = 84;
const MIN_THICK = 5;
const MAX_THICK = 40;

const drawn = computed(() =>
  props.sides.map(side => {
    const branches = (side.branches || []).filter(b => b.count > 0);
    const total = Math.max(
      1,
      branches.reduce((a, b) => a + b.count, 0)
    );
    const height = Math.max(
      ROW,
      branches.length * ROW + (branches.length - 1) * GAP
    );
    const thick = branches.map(b =>
      Math.max(MIN_THICK, Math.round((b.count / total) * MAX_THICK * 1.6))
    );
    const trunk = thick.reduce((a, b) => a + b, 0);
    let from = height / 2 - trunk / 2;
    const ribbons = branches.map((b, i) => {
      const y1 = from + thick[i] / 2;
      from += thick[i];
      const y2 = i * (ROW + GAP) + ROW / 2;
      const mid = RIBBON_W / 2;
      const isShared = b.key === props.shared;
      return {
        ...b,
        stages: (b.stages || []).filter(st => st.name !== 'sem card'),
        isShared,
        thick: thick[i],
        pct: Math.round((b.count / total) * 100),
        path: `M0,${y1} C${mid},${y1} ${mid},${y2} ${RIBBON_W},${y2}`,
        color: isShared ? '#16a34a' : side.color,
      };
    });
    return { ...side, ribbons, height };
  })
);
</script>

<template>
  <div class="cv-bridge">
    <section
      v-for="side in drawn"
      :key="side.key"
      class="cv-bridge-side"
      :style="{ '--side': side.color }"
    >
      <div class="cv-bridge-root">
        <p class="cv-bridge-root-title">{{ side.title }}</p>
        <p class="cv-bridge-root-num">{{ side.total }}</p>
        <p class="cv-bridge-root-unit">{{ side.unit }}</p>
        <p v-if="side.caption" class="cv-bridge-root-cap">
          {{ side.caption }}
        </p>
      </div>
      <svg
        class="cv-bridge-ribbons"
        :width="RIBBON_W"
        :height="side.height"
        :viewBox="`0 0 ${RIBBON_W} ${side.height}`"
        aria-hidden="true"
      >
        <path
          v-for="r in side.ribbons"
          :key="r.key"
          :d="r.path"
          fill="none"
          :stroke="r.color"
          :stroke-width="r.thick"
          stroke-linecap="butt"
          :opacity="r.isShared ? 0.75 : 0.4"
        />
      </svg>
      <ul class="cv-bridge-branches">
        <li v-for="r in side.ribbons" :key="r.key">
          <button
            type="button"
            class="cv-bridge-branch"
            :class="{ 'cv-bridge-shared': r.isShared }"
            :title="`${r.hint} · clique para ver os nomes`"
            @click="emit('pick', { side, branch: r })"
          >
            <span class="cv-bridge-count" :style="{ color: r.color }">
              {{ r.count }}
            </span>
            <span class="min-w-0 flex-1">
              <span class="cv-bridge-label">
                {{ r.label }}
                <span v-if="r.isShared" class="cv-bridge-tag">
                  nos dois números
                </span>
              </span>
              <span class="cv-bridge-hint">{{ r.hint }}</span>
              <span
                v-if="r.stages && r.stages.length && !r.isShared"
                class="cv-bridge-stages"
              >
                <span class="cv-bridge-stages-lead">hoje estão em</span>
                <span
                  v-for="st in r.stages.slice(0, 4)"
                  :key="st.name"
                  class="cv-bridge-stage"
                >
                  <span
                    class="cv-bridge-dot"
                    :style="{ background: st.color }"
                  />
                  {{ st.name }} <b>{{ st.count }}</b>
                </span>
              </span>
            </span>
            <span class="cv-bridge-pct">{{ r.pct }}%</span>
            <span class="i-lucide-chevron-right cv-bridge-go" />
          </button>
        </li>
        <li v-if="!side.ribbons.length" class="cv-bridge-empty">
          ninguém no período
        </li>
      </ul>
    </section>
  </div>
</template>

<style scoped>
.cv-bridge {
  display: grid;
  gap: 28px;
  grid-template-columns: 1fr;
}
.cv-bridge-side {
  display: flex;
  align-items: center;
  min-width: 0;
}
.cv-bridge-root {
  flex-shrink: 0;
  width: 150px;
  padding: 16px 12px;
  border-radius: 18px;
  text-align: center;
  color: #fff;
  background: linear-gradient(
    150deg,
    var(--side),
    color-mix(in srgb, var(--side) 62%, #0f172a)
  );
  box-shadow: 0 14px 30px -16px var(--side);
}
.cv-bridge-root-title {
  font-size: 11px;
  font-weight: 600;
  line-height: 1.25;
  opacity: 0.92;
}
.cv-bridge-root-num {
  font-size: 40px;
  font-weight: 800;
  line-height: 1.05;
  letter-spacing: -0.02em;
  font-variant-numeric: tabular-nums;
}
.cv-bridge-root-unit {
  font-size: 11px;
  opacity: 0.9;
}
.cv-bridge-root-cap {
  margin-top: 6px;
  font-size: 10px;
  line-height: 1.3;
  opacity: 0.8;
}
.cv-bridge-ribbons {
  flex-shrink: 0;
  margin: 0 -1px;
}
.cv-bridge-branches {
  flex: 1;
  min-width: 0;
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.cv-bridge-branch {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-height: 64px;
  padding: 8px 12px;
  border-radius: 14px;
  text-align: left;
  cursor: pointer;
  color: inherit;
  background: color-mix(in srgb, var(--side) 7%, transparent);
  border: 1px solid color-mix(in srgb, var(--side) 22%, transparent);
  transition:
    transform 0.15s ease,
    background 0.15s ease;
}
.cv-bridge-branch:hover {
  transform: translateX(2px);
  background: color-mix(in srgb, var(--side) 14%, transparent);
}
.cv-bridge-shared {
  background: rgb(22 163 74 / 0.1);
  border-color: rgb(22 163 74 / 0.4);
}
.cv-bridge-shared:hover {
  background: rgb(22 163 74 / 0.18);
}
.cv-bridge-count {
  flex-shrink: 0;
  min-width: 34px;
  font-size: 24px;
  font-weight: 800;
  text-align: center;
  font-variant-numeric: tabular-nums;
}
.cv-bridge-label {
  display: block;
  font-size: 12.5px;
  font-weight: 700;
  line-height: 1.3;
}
.cv-bridge-tag {
  display: inline-block;
  margin-left: 4px;
  padding: 1px 7px;
  border-radius: 9999px;
  font-size: 9.5px;
  font-weight: 700;
  color: #fff;
  background: #16a34a;
  vertical-align: 1px;
}
.cv-bridge-hint {
  display: block;
  font-size: 11px;
  line-height: 1.35;
  opacity: 0.68;
}
.cv-bridge-stages {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 8px;
  margin-top: 3px;
  font-size: 10.5px;
}
.cv-bridge-stages-lead {
  opacity: 0.6;
}
.cv-bridge-stage {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-weight: 600;
}
.cv-bridge-dot {
  width: 7px;
  height: 7px;
  border-radius: 9999px;
}
.cv-bridge-pct {
  flex-shrink: 0;
  font-size: 11px;
  opacity: 0.6;
  font-variant-numeric: tabular-nums;
}
.cv-bridge-go {
  flex-shrink: 0;
  font-size: 14px;
  opacity: 0.4;
}
.cv-bridge-empty {
  font-size: 12px;
  opacity: 0.6;
  padding: 8px 12px;
}
@media (max-width: 560px) {
  .cv-bridge-side {
    flex-direction: column;
    align-items: stretch;
    gap: 10px;
  }
  .cv-bridge-root {
    width: auto;
  }
  .cv-bridge-ribbons {
    display: none;
  }
}
</style>
