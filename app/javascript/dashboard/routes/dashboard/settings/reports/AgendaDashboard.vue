<script setup>
// Dashboard da AGENDA (análise do gestor) — a página de Relatórios.
// O miolo mora em components-next/cevico/AgendaDashboardCore.vue e também
// é embutido no Meu Painel (item 136); aqui fica só o header + a régua.
import { ref } from 'vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import AgendaDashboardCore from 'dashboard/components-next/cevico/AgendaDashboardCore.vue';
import { termo } from 'dashboard/helper/segmento';

const period = ref({ preset: 'month', from: '', to: '' });
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
          <span class="i-lucide-calendar-days text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Dashboard da Agenda</h1>
          <p class="text-xs text-n-slate-10">comparecimento · modalidades · {{ termo('profissionais') }} · unidades · {{ termo('vendas') }} · ocupação</p>
        </div>
      </div>

      <!-- Período (régua padrão CEVICO) -->
      <PeriodRuler v-model="period" class="mb-6" />

      <AgendaDashboardCore :period="period" />
    </div>
  </div>
</template>
