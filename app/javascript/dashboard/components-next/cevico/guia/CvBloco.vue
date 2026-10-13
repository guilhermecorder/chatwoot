<script setup>
// 🧭 Guia arejado — BLOCO: título curto e grande, uma linha de contexto e
// o miolo (fileira de indicadores, lista, o que for). `tom`:
//   dia    → 1º bloco da tela, título na cor do dia (60%)
//   apoio  → 2º bloco, título e cartões no apoio (30%)
//   neutro → os demais
// Slot `acoes` = chavinha Lista|Cards, botão secundário etc.
defineProps({
  titulo: { type: String, required: true },
  subtitulo: { type: String, default: '' },
  tom: { type: String, default: 'neutro' }, // dia | apoio | neutro
  icon: { type: String, default: '' },
});
</script>

<template>
  <section class="cvg-bloco" :class="`cvg-bloco--${tom}`">
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
