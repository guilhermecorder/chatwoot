<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const settings = useMapGetter('crm/getSettings');

const pixelId       = ref('');
const accessToken   = ref('');
const adAccountId   = ref('');
const testEventCode = ref('');
const isSaving      = ref(false);
const isTesting     = ref(false);
const testResult    = ref(null);

const metaConfig = computed(() => settings.value?.meta_ads ?? {});
const isConfigured = computed(() => metaConfig.value.configured);

onMounted(async () => {
  await store.dispatch('crm/fetchSettings');
  pixelId.value       = metaConfig.value.pixel_id       || '';
  adAccountId.value   = metaConfig.value.ad_account_id  || '';
  testEventCode.value = metaConfig.value.test_event_code || '';
  // access_token nunca é pré-preenchido por segurança
});

const save = async () => {
  if (!pixelId.value.trim()) {
    useAlert('Informe o Pixel ID.');
    return;
  }
  isSaving.value = true;
  testResult.value = null;
  try {
    const payload = {
      pixel_id: pixelId.value.trim(),
      test_event_code: testEventCode.value.trim(),
      ad_account_id: adAccountId.value.trim(),
    };
    if (accessToken.value.trim()) payload.access_token = accessToken.value.trim();
    await store.dispatch('crm/updateMetaAds', payload);
    accessToken.value = '';
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
    const result = await store.dispatch('crm/testMetaAds');
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
        title="Meta Ads — Conversions API"
        description="Envie conversões de leads do CRM diretamente para o Meta (Facebook/Instagram) via Conversions API server-side."
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
          <img :src="'/dashboard/images/integrations/meta-ads.png'" alt="Meta" class="w-6 h-6 rounded flex-shrink-0" />
          <span class="text-sm font-medium">
            {{ isConfigured ? 'Conectado — Conversions API ativo' : 'Não configurado' }}
          </span>
          <span v-if="isConfigured && metaConfig.pixel_id" class="ml-auto text-xs font-mono text-n-slate-10">
            Pixel {{ metaConfig.pixel_id }}
          </span>
        </div>

        <!-- Form card -->
        <div class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5">
          <div class="flex items-center gap-3 mb-1">
            <img
              :src="'/dashboard/images/integrations/meta-ads.png'"
              alt="Meta Ads"
              class="w-10 h-10 rounded-xl object-contain border border-n-weak flex-shrink-0"
            />
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Credenciais Meta</h3>
              <p class="text-xs text-n-slate-10">Encontre no Gerenciador de Eventos do Meta Business Suite</p>
            </div>
          </div>

          <!-- Pixel ID -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Pixel ID <span class="text-red-500">*</span></label>
            <input
              v-model="pixelId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="Ex: 1234567890123456"
            />
            <p class="text-xs text-n-slate-9 mt-1">Meta Business Suite → Gerenciador de Eventos → seu Pixel → Configurações</p>
          </div>

          <!-- Access Token -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Access Token
              <span v-if="isConfigured" class="text-green-600 font-normal ml-1">(já configurado)</span>
              <span v-else class="text-red-500">*</span>
            </label>
            <input
              v-model="accessToken"
              type="password"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              :placeholder="isConfigured ? 'Digite para substituir o token atual' : 'EAAxxxxxx...'"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Meta Business Suite → Gerenciador de Eventos → seu Pixel → Configurações → API de Conversões → Gerar token de acesso
            </p>
          </div>

          <!-- Ad Account ID (para o Funil de Tráfego) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              ID da conta de anúncios
              <span class="text-n-slate-9 font-normal">(para o relatório Funil de Tráfego)</span>
            </label>
            <input
              v-model="adAccountId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="Ex: act_1234567890 ou 1234567890"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Gerenciador de Anúncios → Configurações da conta. Com isso preenchido, o relatório
              Funil de Tráfego mostra investimento, alcance e cliques automaticamente.
            </p>
          </div>

          <!-- Test Event Code (opcional) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Código de evento de teste
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </label>
            <input
              v-model="testEventCode"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="TEST12345"
            />
            <p class="text-xs text-n-slate-9 mt-1">Use para validar eventos no painel de testes do Meta antes de ativar em produção. Remova após validar.</p>
          </div>

          <!-- Botões -->
          <div class="flex gap-2 pt-1">
            <button
              class="flex-1 bg-[#1877F2] text-white rounded-lg py-2 text-sm font-medium hover:bg-[#1877F2]/90 disabled:opacity-50 transition-colors"
              :disabled="isSaving || !pixelId.trim()"
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
            <div>
              <span v-if="testResult.success">
                Evento enviado com sucesso!
                <span v-if="testResult.fbtrace_id" class="font-mono text-xs ml-1">(trace: {{ testResult.fbtrace_id }})</span>
              </span>
              <span v-else>{{ testResult.error }}</span>
            </div>
          </div>
        </div>

        <!-- Como usar -->
        <div class="bg-n-alpha-1 rounded-2xl p-6 space-y-3">
          <h4 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-lightbulb text-yellow-500" />
            Como usar com automações do CRM
          </h4>
          <ol class="space-y-2 text-sm text-n-slate-11 list-decimal list-inside">
            <li>Configure o Pixel ID e o Access Token acima e salve.</li>
            <li>No CRM, entre no <strong>Modo Programação</strong> de qualquer coluna.</li>
            <li>Crie uma automação com a ação <strong>"Enviar evento Meta Ads"</strong>.</li>
            <li>Escolha o evento: <em>Lead, Purchase, CompleteRegistration</em>, etc.</li>
            <li>O sistema enviará os dados do contato (e-mail e telefone anonimizados via SHA-256) para o Meta automaticamente.</li>
          </ol>
          <div class="flex items-start gap-2 px-3 py-2.5 bg-yellow-500/8 border border-yellow-400/20 rounded-lg mt-3">
            <span class="i-lucide-shield text-yellow-500 flex-shrink-0 mt-0.5" />
            <p class="text-xs text-n-slate-11">
              Os dados pessoais (email, telefone) são <strong>hashed com SHA-256</strong> antes de serem enviados ao Meta, em conformidade com a LGPD.
            </p>
          </div>
        </div>

      </div>
    </template>
  </SettingsLayout>
</template>
