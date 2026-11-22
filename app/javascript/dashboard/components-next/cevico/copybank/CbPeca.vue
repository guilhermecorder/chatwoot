<script setup>
// 🪝 item 397: uma peça do banco (gancho, história, oferta ou regancho).
// 18/11 (tarde), Guilherme: "muito poluído, sopa de letrinhas… conduzir o
// olho" → LINHA FINA: fechada mostra só o texto, quantas vezes foi usada e
// UMA ação (Usar). O resto (exemplo, original, vídeo, selo, editar) aparece
// ao clicar na linha. `aberta` força tudo aberto (o "ver tudo" da lista).
// modo 'escolher' = botão Usar (ambiente de criação) · 'banco' = editar/apagar.
import { ref, computed } from 'vue';
import { SAUDE, TIPO, pieces } from './cbMeta';

const props = defineProps({
  peca: { type: Object, required: true },
  modo: { type: String, default: 'escolher' },
  podeEditar: { type: Boolean, default: false },
  mostrarTipo: { type: Boolean, default: false },
  clinica: { type: Boolean, default: true },
  aberta: { type: Boolean, default: false },
});
const emit = defineEmits([
  'usar',
  'usarExemplo',
  'favoritar',
  'editar',
  'apagar',
]);
const clicada = ref(false);
const open = computed(() => props.aberta || clicada.value);
const SAUDE_COR = { pronto: '#059669', adaptar: '#d97706', evitar: '#dc2626' };
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div class="min-w-0">
    <div
      class="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-n-alpha-1 transition-colors"
      @click="clicada = !clicada"
    >
      <span
        v-if="clinica && peca.kind === 'gancho'"
        class="w-2 h-2 rounded-full flex-shrink-0"
        :style="{ background: SAUDE_COR[peca.saude] }"
        :title="SAUDE[peca.saude]?.label"
      />
      <div class="flex-1 min-w-0">
        <p
          v-if="mostrarTipo && peca.kind === 'gancho'"
          class="text-[11px] font-semibold uppercase tracking-wide mb-0.5"
          :style="{ color: TIPO[peca.categoria]?.color }"
        >
          {{ TIPO[peca.categoria]?.label || peca.categoria }}
        </p>
        <p
          v-else-if="peca.kind !== 'gancho' && peca.categoria"
          class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10 mb-0.5"
        >
          {{ peca.categoria }}
        </p>
        <p
          class="text-[15px] font-medium text-n-slate-12 leading-snug break-words"
        >
          <template v-for="(p, i) in pieces(peca.texto)" :key="i">
            <span v-if="p.gap" class="text-[#2563eb]">{{ p.t }}</span>
            <template v-else>{{ p.t }}</template>
          </template>
        </p>
      </div>
      <span
        v-if="peca.usos"
        class="text-xs font-bold px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-12 flex-shrink-0"
        :title="`Usado ${peca.usos} vez(es)`"
      >
        {{ `${peca.usos}×` }}
      </span>
      <button
        class="text-base leading-none px-1 flex-shrink-0"
        :class="peca.favorito ? '' : 'opacity-40 hover:opacity-100'"
        :title="peca.favorito ? 'Tirar dos favoritos' : 'Favoritar'"
        :disabled="!podeEditar"
        @click.stop="emit('favoritar', peca)"
      >
        {{ peca.favorito ? '⭐' : '☆' }}
      </button>
      <button
        v-if="modo === 'escolher'"
        class="cv-btn cv-btn-sm cv-blue flex-shrink-0"
        @click.stop="emit('usar', peca)"
      >
        Usar
      </button>
      <span
        class="i-lucide-chevron-down text-n-slate-10 flex-shrink-0 transition-transform duration-200"
        :class="{ 'rotate-180': open }"
      />
    </div>

    <div v-if="open" class="px-4 pb-4 flex flex-col gap-2">
      <p
        v-if="clinica && peca.kind === 'gancho'"
        class="text-xs font-semibold"
        :style="{ color: SAUDE_COR[peca.saude] }"
      >
        {{ SAUDE[peca.saude]?.label }}
      </p>
      <p
        v-if="peca.exemplo"
        class="text-sm text-n-slate-11 break-words rounded-xl bg-n-alpha-1 p-3"
      >
        <span class="font-semibold text-n-slate-12">Exemplo: </span>
        {{ peca.exemplo }}
      </p>
      <p v-if="peca.original" class="text-xs text-n-slate-10 break-words">
        {{ `Original: ${peca.original}` }}
      </p>
      <div class="flex flex-wrap gap-2 pt-1">
        <button
          v-if="modo === 'escolher' && peca.exemplo"
          class="cv-btn cv-btn-sm cv-btn-ghost"
          @click="emit('usarExemplo', peca)"
        >
          Usar o exemplo
        </button>
        <a
          v-if="peca.referencia"
          :href="peca.referencia"
          target="_blank"
          rel="noopener noreferrer"
          class="cv-btn cv-btn-sm cv-btn-ghost"
        >
          <span class="i-lucide-play" />
          Vídeo de referência
        </a>
        <template v-if="modo === 'banco' && podeEditar">
          <button
            class="cv-btn cv-btn-sm cv-btn-ghost"
            @click="emit('editar', peca)"
          >
            <span class="i-lucide-pencil" />
            Editar
          </button>
          <button
            class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger"
            @click="emit('apagar', peca)"
          >
            <span class="i-lucide-trash-2" />
            Apagar
          </button>
        </template>
      </div>
    </div>
  </div>
</template>
