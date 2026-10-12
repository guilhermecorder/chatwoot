<script setup>
// 👁️ rodada 334 — pílula discreta "Só visualização": aparece perto do título
// quando a pessoa só pode VER a tela (sem criar/salvar/apagar/mover).
// Uso:  <CevicoViewOnlyPill v-if="!canEdit('crm')" />
defineProps({
  // texto curto (padrão "Só visualização"); a dica explica quem libera
  label: { type: String, default: 'Só visualização' },
  hint: {
    type: String,
    default:
      'Você pode ver esta área, mas não alterar. Peça a um administrador para liberar a edição.',
  },
});
</script>

<template>
  <span class="cv-view-only" :title="hint">
    <span class="i-lucide-eye text-[11px]" />
    {{ label }}
  </span>
</template>

<style scoped>
.cv-view-only {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  height: 22px;
  padding: 0 9px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
  white-space: nowrap;
  vertical-align: middle;
  color: #6b7280;
  background: rgba(107, 114, 128, 0.1);
  border: 1px solid rgba(107, 114, 128, 0.28);
  cursor: help;
}
</style>
