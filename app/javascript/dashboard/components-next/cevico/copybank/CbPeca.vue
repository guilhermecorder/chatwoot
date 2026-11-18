<script setup>
// 🪝 item 397: uma peça do banco em linha (gancho, história, oferta ou
// regancho): texto com [lacunas] destacadas, exemplo, selos e ações.
// modo 'escolher' = botão Usar (ambiente de criação) · 'banco' = editar/apagar.
import { ref } from 'vue';
import { SAUDE, TIPO, pieces } from './cbMeta';

defineProps({
  peca: { type: Object, required: true },
  modo: { type: String, default: 'escolher' },
  podeEditar: { type: Boolean, default: false },
  mostrarTipo: { type: Boolean, default: false },
});
const emit = defineEmits(['usar', 'usarExemplo', 'favoritar', 'editar', 'apagar']);
const original = ref(false);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div class="cv-sub p-4 flex flex-col gap-2 min-w-0">
    <div class="flex items-center gap-2 flex-wrap">
      <span v-if="mostrarTipo && peca.kind === 'gancho'" class="text-[11px] font-semibold uppercase tracking-wide" :style="{ color: TIPO[peca.categoria]?.color }">
        {{ TIPO[peca.categoria]?.label || peca.categoria }}
      </span>
      <span v-else-if="peca.kind !== 'gancho' && peca.categoria" class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10">{{ peca.categoria }}</span>
      <span v-if="peca.kind === 'gancho'" class="text-[11px] px-2 py-0.5 rounded-full font-medium" :class="SAUDE[peca.saude]?.cls">{{ SAUDE[peca.saude]?.short }}</span>
      <span v-if="peca.usos" class="text-[11px] text-n-slate-10">{{ `usado ${peca.usos}×` }}</span>
      <span class="flex-1" />
      <button class="text-base leading-none px-1" :title="peca.favorito ? 'Tirar dos favoritos' : 'Favoritar'" :disabled="!podeEditar" @click="emit('favoritar', peca)">
        {{ peca.favorito ? '⭐' : '☆' }}
      </button>
    </div>
    <p class="text-[15px] text-n-slate-12 leading-snug break-words">
      <template v-for="(p, i) in pieces(peca.texto)" :key="i">
        <span v-if="p.gap" class="px-1 rounded bg-[#2563eb1f] text-[#2563eb] font-medium">{{ p.t }}</span>
        <template v-else>{{ p.t }}</template>
      </template>
    </p>
    <p v-if="peca.exemplo" class="text-sm text-n-slate-11 italic break-words">{{ `Ex.: ${peca.exemplo}` }}</p>
    <p v-if="original && peca.original" class="text-xs text-n-slate-10 break-words">{{ `🇺🇸 ${peca.original}` }}</p>
    <div class="flex flex-wrap gap-2 pt-1">
      <template v-if="modo === 'escolher'">
        <button class="cv-btn cv-btn-sm cv-blue" @click="emit('usar', peca)">Usar</button>
        <button v-if="peca.exemplo" class="cv-btn cv-btn-sm cv-btn-ghost" @click="emit('usarExemplo', peca)">Usar o exemplo</button>
      </template>
      <a v-if="peca.referencia" :href="peca.referencia" target="_blank" rel="noopener noreferrer" class="cv-btn cv-btn-sm cv-btn-ghost">
        <span class="i-lucide-play" />
        Vídeo
      </a>
      <button v-if="peca.original" class="cv-btn cv-btn-sm cv-btn-ghost" @click="original = !original">Original</button>
      <template v-if="modo === 'banco' && podeEditar">
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="emit('editar', peca)">
          <span class="i-lucide-pencil" />
          Editar
        </button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger" @click="emit('apagar', peca)">
          <span class="i-lucide-trash-2" />
        </button>
      </template>
    </div>
  </div>
</template>
