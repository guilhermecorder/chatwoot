<script setup>
// 📝 11/11/2026 (LIFE, pedido do Guilherme): o RESUMO ESCRITO DO CLIENTE em linhas
// curtas — "Conta de luz: R$ 300 · Vai aumentar o consumo: 2 ar-condicionados".
// Usado no cartão do funil e nas tarefas do Meu Painel. Mostra só o que já foi
// anotado (Crm::ClientSummary); nada é cortado com reticências.
defineProps({
  // [{ label, value }]
  lines: { type: Array, default: () => [] },
});
</script>

<template>
  <ul class="cs-lines">
    <li v-for="line in lines" :key="line.label" class="cs-line">
      <span class="cs-label">{{ line.label }}</span>
      <b class="cs-value">{{ line.value }}</b>
    </li>
  </ul>
</template>

<style scoped>
.cs-lines {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 6px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.cs-line {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 0 5px;
  max-width: 100%;
  padding: 3px 8px;
  border-radius: 7px;
  font-size: 11.5px;
  line-height: 1.35;
  background: rgba(234, 88, 12, 0.08);
  border: 1px solid rgba(234, 88, 12, 0.22);
}
.cs-label {
  color: #64748b;
}
.cs-value {
  color: #0f172a;
  font-weight: 600;
  overflow-wrap: anywhere;
}
:global(.dark .cs-line) {
  background: rgba(234, 88, 12, 0.14);
  border-color: rgba(234, 88, 12, 0.3);
}
:global(.dark .cs-label) {
  color: rgba(255, 255, 255, 0.65);
}
:global(.dark .cs-value) {
  color: #fff;
}
</style>
