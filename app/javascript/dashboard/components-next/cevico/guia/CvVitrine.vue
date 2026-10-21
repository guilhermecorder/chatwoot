<script setup>
// 🧭 Guia arejado — VITRINE GIRATÓRIA (ideia da tela de login do SavWin):
// a faixa do cabeçalho troca de painel a cada entrada e a cada 8 s.
// paineis: [{ etiqueta, titulo, texto, tom: 'dia'|'apoio'|'escuro',
//             acao: { label, onClick } }]
// Lembra o último painel no navegador (chave `lembrar`) para a próxima
// entrada mostrar o SEGUINTE; pausa ao passar o mouse; sem movimento
// com prefers-reduced-motion (troca seca pelo CSS).
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';

const props = defineProps({
  paineis: { type: Array, required: true },
  intervalo: { type: Number, default: 8000 },
  lembrar: { type: String, default: 'cevico:vitrine' },
});

const lista = computed(() => (props.paineis || []).slice(0, 4));
const atual = ref(0);
let timer = null;

const lerUltimo = () => {
  try {
    const n = parseInt(localStorage.getItem(props.lembrar) || '', 10);
    return Number.isNaN(n) ? -1 : n;
  } catch {
    return -1;
  }
};
const guardar = n => {
  try {
    localStorage.setItem(props.lembrar, String(n));
  } catch {
    // navegação privada: só não lembra
  }
};
const mostrar = n => {
  if (!lista.value.length) return;
  atual.value =
    ((n % lista.value.length) + lista.value.length) % lista.value.length;
  guardar(atual.value);
};
const parar = () => {
  if (timer) clearInterval(timer);
  timer = null;
};
const girar = () => {
  parar();
  if (lista.value.length < 2) return;
  timer = setInterval(() => mostrar(atual.value + 1), props.intervalo);
};

onMounted(() => {
  mostrar(lerUltimo() + 1);
  girar();
});
onBeforeUnmount(parar);
watch(lista, () => mostrar(atual.value));
</script>

<template>
  <div
    v-if="lista.length"
    class="cvg-vitrine"
    aria-roledescription="vitrine"
    aria-live="polite"
    @mouseenter="parar"
    @mouseleave="girar"
  >
    <div
      v-for="(p, i) in lista"
      :key="i"
      class="cvg-vitrine-painel"
      :class="p.tom ? `cvg-vitrine-painel--${p.tom}` : ''"
      :aria-hidden="i === atual ? 'false' : 'true'"
    >
      <span v-if="p.etiqueta" class="cvg-vitrine-etq">{{ p.etiqueta }}</span>
      <p class="cvg-vitrine-titulo">{{ p.titulo }}</p>
      <p v-if="p.texto" class="cvg-vitrine-texto">{{ p.texto }}</p>
      <button
        v-if="p.acao"
        type="button"
        class="cvg-btn cvg-btn--principal cvg-btn--sm self-start mt-1"
        :tabindex="i === atual ? 0 : -1"
        @click="p.acao.onClick && p.acao.onClick()"
      >
        {{ p.acao.label }}
      </button>
    </div>
    <div
      v-if="lista.length > 1"
      class="cvg-vitrine-pontos"
      role="tablist"
      aria-label="Painéis"
    >
      <button
        v-for="(p, i) in lista"
        :key="`dot-${i}`"
        type="button"
        role="tab"
        :aria-current="i === atual ? 'true' : null"
        :aria-label="p.etiqueta || p.titulo"
        @click="
          mostrar(i);
          girar();
        "
      />
    </div>
  </div>
</template>
