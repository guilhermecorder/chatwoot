<script setup>
// 📖 A HISTÓRIA das páginas (item 353, 19/10): a gramática da página de
// produto da Apple a serviço da análise — uma ideia por seção, um número
// herói com uma frase que diz o que ele significa, respiro generoso e ordem
// narrativa de cima para baixo. O tom não é de venda: é de decisão. Um índice
// fixo no topo pula para cada seção; os blocos operacionais do kit continuam
// embaixo, com a densidade de sempre.
import { computed } from 'vue';

const props = defineProps({
  // [{ key, kicker, title, number, sub, text, tone: 'dia'|'bom'|'atencao'|'neutro', chips: [{ text, tone }], items: [{ title, sub }], cta: { label, key } }]
  sections: { type: Array, default: () => [] },
  // [{ key, label }] — o índice fixo (seções + blocos de baixo)
  index: { type: Array, default: () => [] },
});
const emit = defineEmits(['go']);

const list = computed(() => props.sections.filter(s => s && s.title));
const go = key => emit('go', key);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <section class="cvs">
    <nav v-if="index.length" class="cvs-index" aria-label="Seções da análise">
      <button
        v-for="i in index"
        :key="i.key"
        type="button"
        class="cvs-index-item"
        @click="go(i.key)"
      >
        {{ i.label }}
      </button>
    </nav>

    <article
      v-for="(s, idx) in list"
      :id="`cvs-${s.key}`"
      :key="s.key"
      class="cvs-sec"
      :class="[
        `cvs-sec--${s.tone || 'neutro'}`,
        idx === 0 ? 'cvs-sec--hero' : '',
      ]"
    >
      <p v-if="s.kicker" class="cvs-kicker">{{ s.kicker }}</p>
      <h2 class="cvs-title">{{ s.title }}</h2>
      <p v-if="s.number !== undefined && s.number !== null" class="cvs-number">
        {{ s.number }}
        <span v-if="s.sub" class="cvs-number-sub">{{ s.sub }}</span>
      </p>
      <p v-if="s.text" class="cvs-text">{{ s.text }}</p>
      <div v-if="s.chips?.length" class="cvs-chips">
        <span
          v-for="(c, ci) in s.chips"
          :key="ci"
          class="cvs-chip"
          :class="c.tone ? `cvs-chip--${c.tone}` : ''"
        >
          {{ c.text }}
        </span>
      </div>
      <ol v-if="s.items?.length" class="cvs-items">
        <li v-for="(it, ii) in s.items" :key="ii" class="cvs-item">
          <span class="cvs-item-n">{{ ii + 1 }}</span>
          <span class="min-w-0">
            <span class="cvs-item-title">{{ it.title }}</span>
            <span v-if="it.sub" class="cvs-item-sub">{{ it.sub }}</span>
          </span>
        </li>
      </ol>
      <button v-if="s.cta" type="button" class="cvs-cta" @click="go(s.cta.key)">
        {{ s.cta.label }}
        <span class="i-lucide-arrow-down text-sm" />
      </button>
    </article>
  </section>
</template>

<style scoped>
/* A gramática Apple: tipografia grande, uma ideia por tela, muito respiro.
   Cores pelas variáveis da cor do dia (--cv, --cv-deep, --cv-grad). */
.cvs {
  margin: 0 0 28px;
}
.cvs-index {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  gap: 6px;
  overflow-x: auto;
  padding: 8px 2px;
  margin: 0 0 10px;
  scrollbar-width: none;
  backdrop-filter: blur(14px);
  -webkit-backdrop-filter: blur(14px);
  background: rgba(255, 255, 255, 0.55);
  border-radius: 14px;
}
.cvs-index::-webkit-scrollbar {
  display: none;
}
:global(.dark) .cvs-index {
  background: rgba(20, 22, 26, 0.6);
}
.cvs-index-item {
  flex-shrink: 0;
  height: 28px;
  padding: 0 12px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 600;
  color: var(--cv-deep, #1e3a8a);
  background: rgb(var(--cv-rgb, 37 99 235) / 0.1);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.25);
  cursor: pointer;
  white-space: nowrap;
}
.cvs-index-item:hover {
  background: rgb(var(--cv-rgb, 37 99 235) / 0.2);
}
.cvs-sec {
  text-align: center;
  padding: 56px 20px;
  margin: 0 0 14px;
  border-radius: 28px;
  background: rgba(255, 255, 255, 0.6);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.14);
}
:global(.dark) .cvs-sec {
  background: rgba(255, 255, 255, 0.04);
}
.cvs-sec--hero {
  padding: 72px 20px 64px;
  color: #fff;
  background: var(--cv-grad, linear-gradient(135deg, #1e3a8a, #3b82f6));
  border: 0;
}
.cvs-sec--bom {
  background: linear-gradient(
    180deg,
    rgba(5, 150, 105, 0.1),
    rgba(255, 255, 255, 0.5)
  );
}
.cvs-sec--atencao {
  background: linear-gradient(
    180deg,
    rgba(217, 119, 6, 0.12),
    rgba(255, 255, 255, 0.5)
  );
}
.cvs-kicker {
  margin: 0 0 10px;
  font-size: 13px;
  font-weight: 700;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  opacity: 0.7;
}
.cvs-title {
  margin: 0 auto;
  max-width: 720px;
  font-size: clamp(26px, 4vw, 44px);
  font-weight: 800;
  line-height: 1.08;
  letter-spacing: -0.02em;
}
.cvs-number {
  margin: 22px 0 8px;
  font-size: clamp(48px, 9vw, 96px);
  font-weight: 800;
  line-height: 1;
  letter-spacing: -0.03em;
  font-variant-numeric: tabular-nums;
}
.cvs-number-sub {
  display: block;
  margin-top: 6px;
  font-size: clamp(14px, 1.6vw, 18px);
  font-weight: 500;
  opacity: 0.75;
}
.cvs-text {
  margin: 14px auto 0;
  max-width: 640px;
  font-size: clamp(16px, 1.8vw, 20px);
  line-height: 1.45;
  opacity: 0.88;
}
.cvs-chips {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 8px;
  margin: 18px 0 0;
}
.cvs-chip {
  display: inline-flex;
  align-items: center;
  height: 30px;
  padding: 0 14px;
  border-radius: 9999px;
  font-size: 13px;
  font-weight: 600;
  background: rgba(255, 255, 255, 0.7);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.25);
}
.cvs-sec--hero .cvs-chip {
  background: rgba(255, 255, 255, 0.18);
  border-color: rgba(255, 255, 255, 0.35);
  color: #fff;
}
.cvs-chip--bom {
  color: #065f46;
  background: rgba(16, 185, 129, 0.15);
  border-color: rgba(5, 150, 105, 0.35);
}
.cvs-chip--atencao {
  color: #92400e;
  background: rgba(245, 158, 11, 0.16);
  border-color: rgba(217, 119, 6, 0.35);
}
.cvs-chip--problema {
  color: #991b1b;
  background: rgba(239, 68, 68, 0.14);
  border-color: rgba(220, 38, 38, 0.35);
}
.cvs-items {
  list-style: none;
  margin: 22px auto 0;
  padding: 0;
  max-width: 620px;
  text-align: left;
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.cvs-item {
  display: flex;
  gap: 12px;
  align-items: flex-start;
  padding: 12px 14px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.72);
  border: 1px solid rgb(var(--cv-rgb, 37 99 235) / 0.16);
}
:global(.dark) .cvs-item {
  background: rgba(255, 255, 255, 0.06);
}
.cvs-item-n {
  flex-shrink: 0;
  width: 26px;
  height: 26px;
  border-radius: 9999px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 800;
  color: #fff;
  background: var(--cv, #2563eb);
}
.cvs-item-title {
  display: block;
  font-size: 15px;
  font-weight: 700;
  line-height: 1.3;
}
.cvs-item-sub {
  display: block;
  margin-top: 2px;
  font-size: 13px;
  opacity: 0.75;
  line-height: 1.35;
}
.cvs-cta {
  margin: 24px auto 0;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 40px;
  padding: 0 20px;
  border-radius: 9999px;
  font-size: 14px;
  font-weight: 700;
  color: #fff;
  background: var(--cv, #2563eb);
  border: 0;
  cursor: pointer;
}
.cvs-sec--hero .cvs-cta {
  color: var(--cv-deep, #1e3a8a);
  background: #fff;
}
@media (max-width: 640px) {
  .cvs-sec {
    padding: 40px 16px;
    border-radius: 22px;
  }
  .cvs-sec--hero {
    padding: 48px 16px 44px;
  }
}
</style>
