<script setup>
// 🧭 Guia arejado — BLOCO: título curto e grande, uma linha de contexto e
// o miolo (fileira de indicadores, lista, o que for). `tom`:
//   dia    → 1º bloco da tela, título na cor do dia (60%)
//   apoio  → 2º bloco, título e cartões no apoio (30%)
//   neutro → os demais
// Slot `acoes` = chavinha Lista|Cards, botão secundário etc.
// 21/10: a PALETA DO BLOCO (salada de frutas / fruta escolhida por bloco no
// popup de cores) vale aqui também: o useCevicoPalette da tela fornece a API
// e o bloco se reconhece pelo id="bloco-<id>" (o mesmo id da lista `blocks`).
import { computed, inject, useAttrs } from 'vue';

defineProps({
  titulo: { type: String, required: true },
  subtitulo: { type: String, default: '' },
  tom: { type: String, default: 'neutro' }, // dia | apoio | neutro
  icon: { type: String, default: '' },
});
const pal = inject('cevicoPalette', null);
const attrs = useAttrs();
const blocoVars = computed(() => {
  const key = String(attrs.id || '').replace(/^bloco-/, '');
  return pal && key ? pal.blockVars(key) : null;
});
</script>

<template>
  <section class="cvg-bloco" :class="`cvg-bloco--${tom}`" :style="blocoVars">
    <header class="cvg-bloco-head">
      <div class="cvg-bloco-titulo">
        <span v-if="icon" class="cvg-bloco-icone" aria-hidden="true">
          <span :class="icon" />
        </span>
        <div class="min-w-0">
          <h2 class="cvg-titulo-bloco">{{ titulo }}</h2>
          <p v-if="subtitulo" class="cvg-subtitulo">{{ subtitulo }}</p>
        </div>
      </div>
      <div v-if="$slots.acoes" class="cvg-bloco-acoes">
        <slot name="acoes" />
      </div>
    </header>
    <slot />
    <footer v-if="$slots.rodape" class="cvg-legenda">
      <slot name="rodape" />
    </footer>
  </section>
</template>
