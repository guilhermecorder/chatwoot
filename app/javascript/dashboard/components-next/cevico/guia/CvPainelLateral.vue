<script setup>
// 🧭 Guia arejado — PAINEL LATERAL: desliza pela direita com a história
// completa de um número (de onde veio, com o que se compara, a lista por
// trás). A visão geral fica visível, escurecida, atrás. Fecha no X, no Esc
// e clicando fora; o foco vai para o título ao abrir.
// Teleporta para o body, mas carrega as variáveis do .cv-page que o abriu
// (`vars` = o cvVars da página) para manter as cores do ambiente.
import { ref, watch, nextTick, onBeforeUnmount } from 'vue';

const props = defineProps({
  aberto: { type: Boolean, default: false },
  titulo: { type: String, default: '' },
  valor: { type: [String, Number], default: '' },
  comparacao: { type: Object, default: null }, // { texto, estado }
  vars: { type: Object, default: () => ({}) },
  largura: { type: Number, default: 420 },
});
const emit = defineEmits(['fechar']);
const tituloEl = ref(null);

const onKey = e => {
  if (e.key === 'Escape') emit('fechar');
};
watch(
  () => props.aberto,
  async open => {
    if (open) {
      document.addEventListener('keydown', onKey);
      await nextTick();
      tituloEl.value?.focus();
    } else {
      document.removeEventListener('keydown', onKey);
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => document.removeEventListener('keydown', onKey));
const estadoClass = () => {
  const e = props.comparacao?.estado;
  return e && e !== 'neutro' ? `cvg-${e}` : 'cvg-texto-3';
};
</script>

<template>
  <Teleport to="body">
    <template v-if="aberto">
      <div class="cvg-veu cv-page" :style="vars" @click="emit('fechar')" />
      <aside
        class="cvg-painel cv-page"
        :style="{ ...vars, width: `${largura}px` }"
        role="dialog"
        aria-modal="true"
        :aria-label="titulo"
      >
        <header class="cvg-painel-head">
          <div class="min-w-0">
            <h2 ref="tituloEl" class="cvg-titulo-bloco" tabindex="-1">
              {{ titulo }}
            </h2>
            <div v-if="valor !== ''" class="cvg-numero-heroi">{{ valor }}</div>
            <div
              v-if="comparacao?.texto"
              class="cvg-comparacao"
              :class="estadoClass()"
            >
              {{ comparacao.texto }}
            </div>
            <slot name="cabecalho" />
          </div>
          <button
            type="button"
            class="cvg-btn cvg-btn--icone cvg-btn--sm"
            aria-label="Fechar"
            @click="emit('fechar')"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </header>
        <div class="cvg-painel-corpo">
          <slot />
        </div>
        <footer v-if="$slots.rodape" class="cvg-painel-pe">
          <slot name="rodape" />
        </footer>
      </aside>
    </template>
  </Teleport>
</template>
