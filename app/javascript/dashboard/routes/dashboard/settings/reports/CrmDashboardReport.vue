<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ReportHeader from './components/ReportHeader.vue';
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
    <ReportHeader
      header-title="Dashboard CRM"
      header-description="Métricas automáticas dos funis de vendas: leads, valor em pipeline, conversão e mais."
    >
      <!-- Pipeline selector no slot do header -->
      <div v-if="pipelines.length > 1" class="flex items-center gap-2">
        <label class="text-xs text-n-slate-10 whitespace-nowrap">Funil:</label>
        <select
          v-model="selectedPipelineId"
          class="h-9 text-sm border border-n-weak rounded-xl px-3 bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
        >
          <option v-for="p in pipelines" :key="p.id" :value="p.id">
            {{ p.name }}
          </option>
        </select>
      </div>
    </ReportHeader>

    <!-- Loading inicial dos pipelines -->
    <div v-if="uiFlags.isFetchingPipelines" class="flex justify-center items-center py-24">
      <Spinner :size="32" class="text-n-brand" />
    </div>

    <!-- Sem pipelines -->
    <div
      v-else-if="!pipelines.length"
      class="flex flex-col items-center justify-center py-24 text-n-slate-10"
    >
      <span class="i-lucide-layout-kanban text-5xl mb-3" />
      <p class="text-sm">Nenhum funil CRM criado ainda.</p>
      <p class="text-xs mt-1">
        Crie um funil na seção CRM para ver as métricas aqui.
      </p>
    </div>

    <!-- Dashboard -->
    <CrmDashboard
      v-else-if="selectedPipeline"
      :pipeline="selectedPipeline"
    />
  </div>
</template>
