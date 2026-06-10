<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const settings = useMapGetter('crm/getSettings');

const measurementId = ref('');
const apiSecret     = ref('');
const clientId      = ref('');
const isSaving      = ref(false);
const isTesting     = ref(false);
const testResult    = ref(null);

const gadsConfig   = computed(() => settings.value?.google_ads ?? {});
const isConfigured = computed(() => gadsConfig.value.configured);

onMounted(async () => {
  await store.dispatch('crm/fetchSettings');
  measurementId.value = gadsConfig.value.measurement_id || '';
  clientId.value      = gadsConfig.value.client_id      || '';
  // api_secret nunca pré-preenchido
});

const save = async () => {
  if (!measurementId.value.trim()) {
    useAlert('Informe o Measurement ID do GA4.');
    return;
  }
  isSaving.value = true;
  testResult.value = null;
  try {
    const payload = {
      measurement_id: measurementId.value.trim(),
      client_id:      clientId.value.trim() || undefined,
    };
    if (apiSecret.value.trim()) payload.api_secret = apiSecret.value.trim();
    await store.dispatch('crm/updateGoogleAds', payload);
    apiSecret.value = '';
    useAlert('Configurações salvas com sucesso!');
  } catch {
    useAlert('Erro ao salvar. Tente novamente.');
  } finally {
    isSaving.value = false;
  }
};

const testConnection = async () => {
  isTesting.value = true;
  testResult.value = null;
  try {
    const result = await store.dispatch('crm/testGoogleAds');
    testResult.value = result;
  } catch {
    testResult.value = { success: false, error: 'Erro inesperado.' };
  } finally {
    isTesting.value = false;
  }
};
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        title="Google Ads — Conversões via GA4"
        description="Envie eventos de conversão do CRM para o Google via GA4 Measurement Protocol. O GA4 importa automaticamente as conversões para o Google Ads."
        link-text=""
        feature-name="integrations"
      />
    </template>

    <template #body>
      <div class="max-w-2xl space-y-8">

        <!-- Status banner -->
        <div
          class="flex items-center gap-3 px-4 py-3 rounded-xl border"
          :class="isConfigured
            ? 'bg-green-500/8 border-green-500/20 text-green-700'
            : 'bg-n-alpha-1 border-n-weak text-n-slate-10'"
        >
          <img :src="'/dashboard/images/integrations/google-ads.png'" alt="Google Ads" class="w-6 h-6 rounded flex-shrink-0" />
          <span class="text-sm font-medium">
            {{ isConfigured ? 'Conectado — GA4 Measurement Protocol ativo' : 'Não configurado' }}
          </span>
          <span v-if="isConfigured && gadsConfig.measurement_id" class="ml-auto text-xs font-mono text-n-slate-10">
            {{ gadsConfig.measurement_id }}
          </span>
        </div>

        <!-- Form card -->
        <div class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5">
          <div class="flex items-center gap-3 mb-1">
            <img
              :src="'/dashboard/images/integrations/google-ads.png'"
              alt="Google Ads"
              class="w-10 h-10 rounded-xl object-contain border border-n-weak flex-shrink-0"
            />
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Credenciais GA4</h3>
              <p class="text-xs text-n-slate-10">Google Analytics 4 → Admin → Data Streams → seu stream</p>
            </div>
          </div>

          <!-- Measurement ID -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Measurement ID <span class="text-red-500">*</span></label>
            <input
              v-model="measurementId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="G-XXXXXXXXXX"
            />
            <p class="text-xs text-n-slate-9 mt-1">GA4 → Admin → Data Streams → Web stream → Measurement ID</p>
          </div>

          <!-- API Secret -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              API Secret (Measurement Protocol)
              <span v-if="isConfigured" class="text-green-600 font-normal ml-1">(já configurado)</span>
              <span v-else class="text-red-500">*</span>
            </label>
            <input
              v-model="apiSecret"
              type="password"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              :placeholder="isConfigured ? 'Digite para substituir o secret atual' : 'secretXXXXXXX'"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              GA4 → Admin → Data Streams → seu stream → Measurement Protocol API secrets → Criar
            </p>
          </div>

          <!-- Client ID (opcional) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Client ID padrão
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </label>
            <input
              v-model="clientId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="crm-server-side"
            />
            <p class="text-xs text-n-slate-9 mt-1">Identificador do cliente nos eventos. Se vazio, usa o ID do contato automaticamente.</p>
          </div>

          <!-- Botões -->
          <div class="flex gap-2 pt-1">
            <button
              class="flex-1 bg-[#4285F4] text-white rounded-lg py-2 text-sm font-medium hover:bg-[#4285F4]/90 disabled:opacity-50 transition-colors"
              :disabled="isSaving || !measurementId.trim()"
              @click="save"
            >
              {{ isSaving ? 'Salvando...' : 'Salvar configurações' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isTesting || !isConfigured"
              @click="testConnection"
            >
              <span :class="isTesting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-send'" class="text-sm" />
              {{ isTesting ? 'Enviando...' : 'Testar evento' }}
            </button>
          </div>

          <!-- Test result -->
          <div
            v-if="testResult"
            class="flex items-start gap-2 px-3 py-2.5 rounded-lg text-sm"
            :class="testResult.success
              ? 'bg-green-500/10 text-green-700 border border-green-500/20'
              : 'bg-red-500/10 text-red-700 border border-red-500/20'"
          >
            <span
              class="text-base flex-shrink-0 mt-0.5"
              :class="testResult.success ? 'i-lucide-check-circle' : 'i-lucide-alert-circle'"
            />
            <span v-if="testResult.success">Evento de teste enviado ao GA4 com sucesso!</span>
            <span v-else>{{ testResult.error }}</span>
          </div>
        </div>

        <!-- Como usar -->
        <div class="bg-n-alpha-1 rounded-2xl p-6 space-y-3">
          <h4 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-lightbulb text-yellow-500" />
            Como usar com automações do CRM
          </h4>
          <ol class="space-y-2 text-sm text-n-slate-11 list-decimal list-inside">
            <li>Configure o Measurement ID e o API Secret acima e salve.</li>
            <li>No <strong>Google Ads</strong>, vincule sua propriedade GA4 e configure <em>importação de conversões</em>.</li>
            <li>No CRM, crie uma automação com a ação <strong>"Conversão Google Ads"</strong>.</li>
            <li>Configure o nome do evento GA4 (ex: <code>generate_lead</code>, <code>purchase</code>).</li>
            <li>O sistema enviará os eventos via Measurement Protocol server-side — sem depender de pixel no navegador.</li>
          </ol>
          <div class="flex items-start gap-2 px-3 py-2.5 bg-blue-500/8 border border-blue-400/20 rounded-lg mt-3">
            <span class="i-lucide-info text-blue-500 flex-shrink-0 mt-0.5" />
            <p class="text-xs text-n-slate-11">
              O GA4 Measurement Protocol é <strong>server-side</strong> — funciona mesmo com Ad Blockers e iOS 17+.
              Os eventos ficam visíveis em GA4 → Relatórios → Tempo real.
            </p>
          </div>
        </div>

      </div>
    </template>
  </SettingsLayout>
</template>
