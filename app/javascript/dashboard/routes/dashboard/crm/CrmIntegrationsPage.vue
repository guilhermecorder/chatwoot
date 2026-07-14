<script setup>
// Aba "Integrações" — central única de conexões. Cards organizados como
// os aplicativos nativos; "Configurar" abre a janela da integração.
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters, useMapGetter } from 'dashboard/composables/store';
import CrmIntegrationsModal from './components/CrmIntegrationsModal.vue';
import IntegrationItem from 'dashboard/routes/dashboard/settings/integrations/IntegrationItem.vue';

const store = useStore();
const getters = useStoreGetters();
const settings = useMapGetter('crm/getSettings');

const configuring = ref(null); // 'n8n' | 'meta' | 'google' | 'ai' | 'sheets' | null

onMounted(() => {
  store.dispatch('integrations/get');
  store.dispatch('crm/fetchSettings');
});

const apps = computed(() => getters['integrations/getAppIntegrations'].value);

const cevicoCards = computed(() => [
  {
    key: 'n8n',
    name: 'n8n',
    icon: 'i-lucide-workflow',
    color: '#EA4B71',
    description: 'Acione workflows do n8n automaticamente nas automações do CRM.',
    enabled: !!(settings.value?.n8n_base_url && settings.value?.n8n_api_key_configured),
  },
  {
    key: 'meta',
    name: 'Meta Ads',
    icon: 'i-lucide-bar-chart-2',
    color: '#1877F2',
    description: 'Conversões via CAPI (com ctwa_clid), insights de campanha e atribuição de anúncios.',
    enabled: !!settings.value?.meta_ads?.configured,
  },
  {
    key: 'google',
    name: 'Google Ads',
    icon: 'i-lucide-trending-up',
    color: '#4285F4',
    description: 'Eventos de conversão via GA4 Measurement Protocol server-side.',
    enabled: !!settings.value?.google_ads?.configured,
  },
  {
    key: 'ai',
    name: 'Claude — IA nativa',
    icon: 'i-lucide-sparkles',
    color: '#D97706',
    description: 'Análise de conversas (interesse do paciente) e insights de marketing dos formulários.',
    enabled: !!settings.value?.ai?.configured,
  },
  {
    key: 'sheets',
    name: 'Google Sheets',
    icon: 'i-lucide-sheet',
    color: '#0F9D58',
    description: 'Importa a planilha de cirurgias (data, paciente, procedimento, valor, unidade) para o Dashboard.',
    enabled: !!settings.value?.sheets?.configured,
  },
]);

const closeConfig = () => {
  configuring.value = null;
  store.dispatch('crm/fetchSettings'); // atualiza os selos após configurar
};
</script>

<template>
  <div class="h-full overflow-y-auto bg-n-surface-1 p-8">
    <div class="max-w-5xl mx-auto">
      <div class="mb-8">
        <h1 class="text-lg font-bold text-n-slate-12 flex items-center gap-2">
          <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
            <span class="i-lucide-plug text-white text-base" />
          </span>
          Integrações
        </h1>
        <p class="text-xs text-n-slate-10 mt-1.5">
          Central única de conexões do CEVICO S.I — rastreamento de conversões, IA e aplicativos
        </p>
      </div>

      <!-- Central CEVICO -->
      <h2 class="text-sm font-bold text-n-slate-12 mb-1">CEVICO — Conversões e IA</h2>
      <p class="text-xs text-n-slate-10 mb-5">As conexões que alimentam o CRM, os relatórios e os agentes de IA</p>
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-5 mb-10">
        <div
          v-for="card in cevicoCards"
          :key="card.key"
          class="flex flex-col p-4 outline outline-n-container outline-1 bg-n-card rounded-xl"
        >
          <div class="flex items-start justify-between mb-2">
            <span
              class="w-12 h-12 rounded-xl flex items-center justify-center"
              :style="{ backgroundColor: card.color + '1A' }"
            >
              <span :class="card.icon" class="text-2xl" :style="{ color: card.color }" />
            </span>
            <span
              class="text-[10px] px-2 py-0.5 rounded-full font-medium"
              :class="card.enabled ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
            >
              {{ card.enabled ? 'Ativado' : 'Desativado' }}
            </span>
          </div>
          <div class="flex items-center justify-between gap-2 mb-1">
            <p class="text-sm font-semibold text-n-slate-12">{{ card.name }}</p>
            <button
              class="text-xs font-medium text-n-brand hover:underline flex items-center gap-1 flex-shrink-0"
              @click="configuring = card.key"
            >
              <span class="i-lucide-settings-2 text-xs" />
              Configurar
            </button>
          </div>
          <p class="text-xs text-n-slate-10 leading-relaxed">{{ card.description }}</p>
        </div>
      </div>

      <!-- Aplicativos nativos -->
      <h2 class="text-sm font-bold text-n-slate-12 mb-1">Aplicativos do sistema</h2>
      <p class="text-xs text-n-slate-10 mb-5">
        Webhooks, chatbots, tradutor e outras extensões do CEVICO S.I
      </p>
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
        <IntegrationItem
          v-for="app in apps"
          :id="app.id"
          :key="app.id"
          :name="app.name"
          :description="app.description"
          :enabled="app.enabled"
        />
      </div>
    </div>

    <!-- Janela de configuração (uma seção por vez) -->
    <CrmIntegrationsModal
      v-if="configuring"
      :only="configuring"
      @close="closeConfig"
    />
  </div>
</template>
