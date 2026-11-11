<script setup>
// 🧭 Guia arejado — INDICADOR: um número que conta a sua história.
// rótulo → número → comparação (cor de ESTADO só aqui) → frase de contexto
// → gráfico de área com respiro. `heroi` = o único grande do bloco (44px,
// na cor de destaque); `apoio` = cartão no fundo do apoio (30%).
// Clicável quando tem ouvinte de `abrir` (abre o PainelLateral).
import { computed, getCurrentInstance } from 'vue';

const props = defineProps({
  rotulo: { type: String, required: true },
  valor: { type: [String, Number], required: true },
  // { texto: '+12% vs semana passada', estado: 'bom'|'atencao'|'problema'|'neutro' }
  comparacao: { type: Object, default: null },
  contexto: { type: String, default: '' },
  serie: { type: Array, default: () => [] }, // 7–30 números
  // 📐 item 394: a mesma série na BASE DE COMPARAÇÃO (linha mais clara,
  // tracejada, no mesmo eixo); null = balde que não existe na base
  serieAnterior: { type: Array, default: null },
  heroi: { type: Boolean, default: false },
  apoio: { type: Boolean, default: false },
  pe: { type: String, default: '' }, // texto pequeno à esquerda do "ver história"
  abrirLabel: { type: String, default: 'ver história ›' },
});
const emit = defineEmits(['abrir']);
// Vue não expõe "tem ouvinte" direto: olhamos o onAbrir do vnode do pai
const inst = getCurrentInstance();
const clicavel = computed(() => !!inst?.vnode?.props?.onAbrir);

const SETAS = { bom: '▲', atencao: '▼', problema: '▼', neutro: '' };
// seta só quando a comparação é uma VARIAÇÃO (seta: true); taxas e totais ficam sem
// item 394: quando a comparação já traz o SENTIDO ('▲' subiu / '▼' caiu), vale
// ele — falta que caiu é "▼" em verde, não "▲"
const seta = computed(() => {
  const s = props.comparacao?.seta;
  if (!s) return '';
  return typeof s === 'string' ? s : (SETAS[props.comparacao?.estado] ?? '');
});
const estadoClass = computed(() => {
  const e = props.comparacao?.estado;
  return e && e !== 'neutro' ? `cvg-${e}` : 'cvg-texto-3';
});

// área + linha numa caixa 300×64; a última bolinha marca o ponto de hoje
const graf = computed(() => {
  const pts = (props.serie || []).map(Number).filter(n => !Number.isNaN(n));
  if (pts.length < 2) return null;
  // a base para onde ela acaba (mês de 30 × 31 dias) e divide o eixo com a de agora
  const bruta = Array.isArray(props.serieAnterior) ? props.serieAnterior : [];
  const fim = bruta.findIndex(v => v === null || v === undefined);
  const antes = (fim === -1 ? bruta : bruta.slice(0, fim))
    .slice(0, pts.length)
    .map(v => Number(v) || 0);
  const max = Math.max(...pts, ...antes, 1);
  const min = Math.min(...pts, 0);
  const span = max - min || 1;
  const w = 300;
  const h = 64;
  const stepX = w / (pts.length - 1);
  const ponto = (v, i) => [
    Math.round(i * stepX),
    Math.round(h - 8 - ((v - min) / span) * (h - 16)),
  ];
  const caminho = lista =>
    lista.map(([x, y], i) => `${i ? 'L' : 'M'}${x} ${y}`).join(' ');
  const xy = pts.map(ponto);
  const linha = caminho(xy);
  const last = xy[xy.length - 1];
  return {
    linha,
    anterior:
      antes.length > 1 && antes.some(v => v > 0)
        ? caminho(antes.map(ponto))
        : '',
    area: `${linha} L${w} ${h} L0 ${h} Z`,
    cx: last[0],
    cy: last[1],
  };
});
</script>

<template>
  <component
    :is="clicavel ? 'button' : 'div'"
    :type="clicavel ? 'button' : null"
    class="cvg-ind"
    :class="{
      'cvg-ind--heroi': heroi,
      'cvg-ind--apoio': apoio,
      'cvg-ind--clicavel': clicavel,
    }"
    @click="clicavel && emit('abrir')"
  >
    <span class="cvg-rotulo">{{ rotulo }}</span>
    <span
      class="cvg-ind-valor"
      :class="heroi ? 'cvg-numero-heroi' : 'cvg-numero'"
    >
      {{ valor }}
    </span>
    <span
      v-if="comparacao?.texto"
      class="cvg-comparacao cvg-ind-cmp"
      :class="estadoClass"
    >
      <span v-if="seta" aria-hidden="true">{{ seta }}</span
      >{{ comparacao.texto }}
    </span>
    <p v-if="contexto" class="cvg-corpo cvg-ind-ctx">{{ contexto }}</p>
    <svg
      v-if="graf"
      class="cvg-ind-graf"
      viewBox="0 0 300 64"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <path class="area" :d="graf.area" />
      <path v-if="graf.anterior" class="linha-anterior" :d="graf.anterior" />
      <path class="linha" :d="graf.linha" />
      <circle class="ponto" :cx="graf.cx" :cy="graf.cy" r="4" />
    </svg>
    <span v-if="pe || clicavel" class="cvg-legenda cvg-ind-pe">
      <span>{{ pe }}</span>
      <span v-if="clicavel">{{ abrirLabel }}</span>
    </span>
  </component>
</template>
