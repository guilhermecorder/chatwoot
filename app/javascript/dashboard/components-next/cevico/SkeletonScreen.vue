<script setup>
// TELA-ESQUELETO "Homem de Ferro" (item 89 — em TODOS os ambientes):
// composições prontas de SkeletonPiece para cada tipo de tela. As peças
// se encaixam em sequência enquanto os dados chegam.
//  · board     = pílulas + colunas com cards (CRM, Tarefas, Conteúdos…)
//  · dashboard = KPIs + blocos de gráfico (relatórios, Financeiro…)
//  · list      = título + linhas empilhadas (Formulários, Campanhas…)
//  · calendar  = barra de navegação + grade grande (Agenda)
import SkeletonPiece from './SkeletonPiece.vue';

defineProps({
  variant: { type: String, default: 'dashboard' },
});
</script>

<template>
  <div class="p-6 space-y-4 w-full">
    <div class="flex items-center gap-3">
      <SkeletonPiece variant="circle" class="w-9 h-9" :order="0" />
      <SkeletonPiece variant="title" :order="1" />
    </div>

    <template v-if="variant === 'board'">
      <div class="flex gap-2 flex-wrap">
        <SkeletonPiece v-for="i in 4" :key="`p${i}`" variant="pill" :order="1 + i" />
      </div>
      <div class="flex gap-4 overflow-hidden">
        <div v-for="c in 4" :key="`c${c}`" class="w-64 flex-shrink-0 space-y-2">
          <SkeletonPiece variant="block" class="h-10 !rounded-xl" :order="5 + c" />
          <SkeletonPiece
            v-for="r in 2 + (c % 2)"
            :key="`r${r}`"
            variant="block"
            class="h-24 !rounded-xl"
            :order="7 + c + r * 2"
          />
        </div>
      </div>
    </template>

    <template v-else-if="variant === 'calendar'">
      <div class="flex gap-2 flex-wrap">
        <SkeletonPiece v-for="i in 5" :key="`p${i}`" variant="pill" :order="1 + i" />
      </div>
      <SkeletonPiece variant="block" class="h-[420px]" :order="7" />
    </template>

    <template v-else-if="variant === 'list'">
      <SkeletonPiece
        v-for="i in 6"
        :key="`l${i}`"
        variant="block"
        class="h-16 !rounded-xl"
        :order="1 + i"
      />
    </template>

    <template v-else>
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <SkeletonPiece v-for="i in 4" :key="`t${i}`" variant="tile" :order="1 + i" />
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <SkeletonPiece variant="block" class="h-56" :order="6" />
        <SkeletonPiece variant="block" class="h-56" :order="7" />
      </div>
    </template>
  </div>
</template>
