<script setup>
// 🍎 rodada 163: o cabeçalho do core (ReportHeader) saiu — o banner de vidro
// (CevicoHero) e o seletor do funil moram DENTRO do CrmDashboard, que é
// quem tem a paleta da página. Aqui fica só a escolha do funil e os
// estados de carregamento / sem funil.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmDashboard from 'dashboard/routes/dashboard/crm/CrmDashboard.vue';

const store     = useStore();
const pipelines = useMapGetter('crm/getPipelines');
const uiFlags   = useMapGetter('crm/getUIFlags');

const selectedPipelineId = ref(null);

const selectedPipeline = computed(() =>
  pipelines.value.find(p => p.id === selectedPipelineId.value) ?? null
);

onMounted(async () => {
  if (!pipelines.value.length) {
    await store.dispatch('crm/fetchPipelines');
  }
  if (pipelines.value.length && !selectedPipelineId.value) {
    selectedPipelineId.value = pipelines.value[0].id;
  }
});
</script>

<template>
  <div>
    <!-- Loading inicial dos pipelines -->
    <div v-if="uiFlags.isFetchingPipelines" class="flex justify-center items-center py-24">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- Sem pipelines -->
    <div
      v-else-if="!pipelines.length"
      class="flex flex-col items-center justify-center py-24 text-n-slate-10"
    >
      <span class="i-lucide-kanban text-5xl mb-3" />
      <p class="text-sm">Nenhum funil CRM criado ainda.</p>
      <p class="text-xs mt-1">
        Crie um funil na seção CRM para ver as métricas aqui.
      </p>
    </div>

    <!-- Dashboard (banner + seletor do funil ficam dentro dele) -->
    <CrmDashboard
      v-else-if="selectedPipeline"
      v-model:selected-pipeline-id="selectedPipelineId"
      :pipeline="selectedPipeline"
      :pipelines="pipelines"
    />
  </div>
</template>
