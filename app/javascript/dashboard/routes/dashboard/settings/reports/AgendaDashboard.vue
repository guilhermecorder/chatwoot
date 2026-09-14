<script setup>
// Dashboard da AGENDA (análise do gestor) — a página de Relatórios.
// O miolo mora em components-next/cevico/AgendaDashboardCore.vue e também
// é embutido no Meu Painel (item 136); aqui fica só o banner + a régua.
import { ref } from 'vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import AgendaDashboardCore from 'dashboard/components-next/cevico/AgendaDashboardCore.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';

// 🍎 formato novo (rodada 163): kit "iMac G3 + vidro" com a paleta desta
// página (o admin escolhe pelo chip do banner; cada seção do miolo pode
// ter a sua — os ids batem com os do AgendaDashboardCore)
const pal = useCevicoPalette({
  scope: 'report:agenda',
  blocks: [
    { id: 'kpis', label: 'Consultas', icon: 'i-lucide-calendar-check' },
    { id: 'tipos', label: 'Consultas por tipo', icon: 'i-lucide-tags' },
    { id: 'semana', label: 'Volume por dia da semana', icon: 'i-lucide-calendar-range' },
    { id: 'medicos', label: 'Por médico', icon: 'i-lucide-stethoscope' },
    { id: 'unidades', label: 'Por unidade', icon: 'i-lucide-map-pin' },
    { id: 'cirurgias', label: 'Agenda de Cirurgias', icon: 'i-lucide-slice' },
    { id: 'ocupacao', label: 'Ocupação', icon: 'i-lucide-gauge' },
  ],
});
const { cvVars, blockFamily } = pal;

const period = ref({ preset: 'month', from: '', to: '' });
</script>

<template>
  <div class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1" :style="cvVars">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- banner de vidro na paleta da página (rodada 163) -->
      <CevicoHero
        :pal="pal"
        title="Dashboard da Agenda"
        subtitle="comparecimento · modalidades · médicos · unidades · cirurgias · ocupação"
        icon="i-lucide-calendar-days"
      />

      <!-- Período (régua padrão CEVICO) -->
      <PeriodRuler v-model="period" glass class="mb-6" />

      <AgendaDashboardCore :period="period" glass :family="blockFamily('kpis')" :pal="pal" />
    </div>
  </div>
</template>
