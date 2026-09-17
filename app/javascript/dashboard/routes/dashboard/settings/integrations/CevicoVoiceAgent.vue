<script setup>
// 🤖📞 Agente de Ligação (item 169) — esqueleto; a tela completa segue o
// contrato docs/AGENTE_LIGACAO.md §4 (mesmo padrão de CevicoCalls.vue)
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
</script>

<template>
  <SettingsLayout :is-loading="false">
    <template #header>
      <BaseSettingsHeader
        title="Agente de Ligação (IA)"
        description="Assistente virtual que atende e faz ligações pelo WhatsApp — em construção."
      />
    </template>
    <template #body>
      <div class="text-sm text-n-slate-11">Em construção.</div>
    </template>
  </SettingsLayout>
</template>
