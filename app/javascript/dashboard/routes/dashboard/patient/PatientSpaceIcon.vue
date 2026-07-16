<script setup>
// Ícone característico do Espaço do Paciente ("dopamine color"): o mesmo
// medalhão em gradiente vivo em TODOS os atalhos (card do CRM, balão,
// painel da conversa, Agenda) — bate o olho e sabe pra onde o botão leva.
defineProps({
  size: { type: Number, default: 20 },
});
</script>

<template>
  <span
    class="inline-flex items-center justify-center rounded-lg shrink-0 shadow-sm"
    :style="{
      width: `${size}px`,
      height: `${size}px`,
      background:
        'linear-gradient(135deg, #38BDF8 0%, #A78BFA 50%, #F472B6 100%)',
    }"
  >
    <span
      class="i-lucide-square-user-round text-white"
      :style="{ fontSize: `${Math.round(size * 0.62)}px` }"
    />
  </span>
</template>
