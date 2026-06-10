<script setup>
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { computed, onMounted, ref } from 'vue';
import { useBranding } from 'shared/composables/useBranding';
import { picoSearch } from '@scmmishra/pico-search';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import IntegrationItem from './IntegrationItem.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const getters = useStoreGetters();
const router = useRouter();
const { accountId } = useAccount();
const { replaceInstallationName } = useBranding();

const CRM_INTEGRATIONS = [
  {
    id: 'n8n',
    name: 'n8n',
    description: 'Acione workflows do n8n automaticamente nas automações do CRM via webhook.',
    icon: 'i-lucide-workflow',
    color: '#EA4B71',
    route: 'settings_integrations_n8n',
  },
  {
    id: 'meta-ads',
    name: 'Meta Ads',
    description: 'Envie conversões de leads para o Meta (Facebook/Instagram) via Conversions API server-side.',
    icon: 'i-lucide-bar-chart-2',
    color: '#1877F2',
    route: 'settings_integrations_meta_ads',
  },
  {
    id: 'google-ads',
    name: 'Google Ads',
    description: 'Envie eventos de conversão para o Google via GA4 Measurement Protocol server-side.',
    icon: 'i-lucide-trending-up',
    color: '#4285F4',
    route: 'settings_integrations_google_ads',
  },
];

const goToIntegration = (routeName) => {
  router.push({ name: routeName, params: { accountId: accountId.value } });
};

const searchQuery = ref('');
const uiFlags = getters['integrations/getUIFlags'];

const integrationList = computed(
  () => getters['integrations/getAppIntegrations'].value
);

const filteredIntegrationList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return integrationList.value;
  return picoSearch(integrationList.value, query, ['name', 'description']);
});

onMounted(() => {
  store.dispatch('integrations/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('INTEGRATION_SETTINGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('INTEGRATION_SETTINGS.HEADER')"
        :description="
          replaceInstallationName($t('INTEGRATION_SETTINGS.DESCRIPTION'))
        "
        :link-text="$t('INTEGRATION_SETTINGS.LEARN_MORE')"
        :search-placeholder="$t('INTEGRATION_SETTINGS.SEARCH_PLACEHOLDER')"
        feature-name="integrations"
      />
    </template>
    <template #body>
      <div class="flex-grow flex-shrink overflow-auto space-y-8">

        <!-- Native integrations -->
        <span
          v-if="!filteredIntegrationList.length && searchQuery"
          class="flex-1 flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
        >
          {{ $t('INTEGRATION_SETTINGS.NO_RESULTS') }}
        </span>
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4"
        >
          <IntegrationItem
            v-for="item in filteredIntegrationList"
            :id="item.id"
            :key="item.id"
            :logo="item.logo"
            :name="item.name"
            :description="item.description"
            :enabled="item.enabled"
          />
        </div>

        <!-- CRM Ads Integrations section -->
        <div v-if="!searchQuery">
          <div class="flex items-center gap-3 mb-4">
            <h3 class="text-sm font-semibold text-n-slate-12">CRM — Rastreamento de Conversões</h3>
            <span class="text-[10px] bg-n-brand/10 text-n-brand px-2 py-0.5 rounded-full font-medium">CRM</span>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            <button
              v-for="item in CRM_INTEGRATIONS"
              :key="item.id"
              class="flex items-start gap-4 p-5 bg-n-solid-2 rounded-2xl border border-n-weak hover:border-n-brand/30 hover:shadow-sm transition-all text-left group"
              @click="goToIntegration(item.route)"
            >
              <img
                :src="`/dashboard/images/integrations/${item.id}.png`"
                :alt="item.name"
                class="w-10 h-10 rounded-xl object-contain flex-shrink-0 border border-n-weak"
              />
              <div class="min-w-0">
                <p class="text-sm font-semibold text-n-slate-12 group-hover:text-n-brand transition-colors">{{ item.name }}</p>
                <p class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">{{ item.description }}</p>
              </div>
              <span class="i-lucide-chevron-right text-n-slate-9 group-hover:text-n-brand transition-colors flex-shrink-0 mt-1 ml-auto" />
            </button>
          </div>
        </div>

      </div>
    </template>
  </SettingsLayout>
</template>
