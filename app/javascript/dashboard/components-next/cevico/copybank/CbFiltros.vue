<script setup>
// 🪝 item 397: barra de filtros do Banco de Ganchos (busca + saúde +
// favoritos/vídeo/mais usados + origem). v-model = objeto de filtrosPadrao().
import { SAUDE_FILTROS, FONTES, filtrosPadrao, filtroAtivo } from './cbMeta';

const props = defineProps({
  modelValue: { type: Object, required: true },
  total: { type: Number, default: null }, // quantos passam no filtro
  semFonte: { type: Boolean, default: false },
  padrao: { type: Object, default: null }, // o "limpar" volta para cá (Banco = todos; Criar = úteis)
});
const emit = defineEmits(['update:modelValue']);
const set = (k, v) => emit('update:modelValue', { ...props.modelValue, [k]: v });
const base = () => props.padrao || filtrosPadrao();
const limpar = () => emit('update:modelValue', base());
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div class="flex flex-col gap-3">
    <div class="flex flex-wrap items-center gap-3">
      <div class="relative flex-1 min-w-[220px]">
        <span class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-n-slate-10" />
        <input
          :value="modelValue.busca"
          class="cv-input w-full !pl-9"
          placeholder="Buscar palavra (ex.: erro, segredo, ninguém, olho…)"
          @input="set('busca', $event.target.value)"
        />
      </div>
      <span v-if="total !== null" class="text-sm text-n-slate-11 whitespace-nowrap">{{ `${total} encontrados` }}</span>
      <button v-if="filtroAtivo(modelValue, base())" class="cv-btn cv-btn-sm cv-btn-ghost" @click="limpar">
        <span class="i-lucide-x" />
        Limpar filtros
      </button>
    </div>
    <div class="flex flex-wrap items-center gap-2">
      <div class="cv-seg cv-seg-sm flex-wrap">
        <button v-for="s in SAUDE_FILTROS" :key="s.key" class="cv-seg-item" :class="{ 'cv-seg-on': modelValue.saude === s.key }" @click="set('saude', s.key)">
          {{ s.label }}
        </button>
      </div>
      <button class="cv-chip" :class="{ 'cv-chip-on': modelValue.favoritos }" @click="set('favoritos', !modelValue.favoritos)">⭐ Favoritos</button>
      <button class="cv-chip" :class="{ 'cv-chip-on': modelValue.comVideo }" @click="set('comVideo', !modelValue.comVideo)">▶ Com vídeo</button>
      <button class="cv-chip" :class="{ 'cv-chip-on': modelValue.usados }" @click="set('usados', !modelValue.usados)">🏆 Já usados</button>
      <div v-if="!semFonte" class="cv-seg cv-seg-sm flex-wrap">
        <button v-for="f in FONTES" :key="f.key" class="cv-seg-item" :class="{ 'cv-seg-on': modelValue.fonte === f.key }" @click="set('fonte', f.key)">
          {{ f.label }}
        </button>
      </div>
    </div>
  </div>
</template>
