<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store    = useStore();
const settings  = useMapGetter('crm/getSettings');
const workflows = useMapGetter('crm/getN8nWorkflows');

const n8nUrl    = ref('');
const n8nApiKey = ref('');
const isSaving   = ref(false);
const isTesting  = ref(false);
const isFetching = ref(false);
const testResult = ref(null);

const isConfigured  = computed(() => settings.value?.n8n_api_key_configured && settings.value?.n8n_base_url);
const workflowCount = computed(() => workflows.value?.length ?? 0);
const fetchedAt     = computed(() => {
  const d = settings.value?.n8n_workflows_fetched_at;
  if (!d) return null;
  return new Date(d).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
});

onMounted(async () => {
  await store.dispatch('crm/fetchSettings');
  n8nUrl.value = settings.value?.n8n_base_url || '';
});

const save = async () => {
  if (!n8nUrl.value.trim()) {
    useAlert('Informe a URL base do n8n.');
    return;
  }
  isSaving.value = true;
  testResult.value = null;
  try {
    const payload = { n8n_base_url: n8nUrl.value.trim() };
    if (n8nApiKey.value.trim()) payload.n8n_api_key = n8nApiKey.value.trim();
    await store.dispatch('crm/updateSettings', payload);
    n8nApiKey.value = '';
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
    const result = await store.dispatch('crm/testN8n');
    testResult.value = result;
  } catch {
    testResult.value = { success: false, message: 'Erro inesperado ao testar conexão.' };
  } finally {
    isTesting.value = false;
  }
};

const fetchWorkflows = async () => {
  isFetching.value = true;
  try {
    const result = await store.dispatch('crm/fetchN8nWorkflows');
    if (result.success) {
      useAlert(`${result.count} workflow(s) importado(s) com sucesso`);
    } else {
      useAlert(result.message || 'Erro ao buscar workflows.');
    }
  } catch {
    useAlert('Erro ao buscar workflows.');
  } finally {
    isFetching.value = false;
  }
};
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader
        title="n8n — Automação de Workflows"
        description="Conecte seu n8n para acionar workflows automaticamente a partir das automações do CRM."
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
          <span class="i-lucide-workflow w-6 h-6 flex-shrink-0" />
          <span class="text-sm font-medium">
            {{ isConfigured ? 'Conectado — n8n configurado' : 'Não configurado' }}
          </span>
          <span v-if="isConfigured && settings.n8n_base_url" class="ml-auto text-xs font-mono text-n-slate-10 truncate max-w-xs">
            {{ settings.n8n_base_url }}
          </span>
        </div>

        <!-- Credenciais -->
        <div class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5">
          <div class="flex items-center gap-3 mb-1">
            <span
              class="i-lucide-workflow w-10 h-10 rounded-xl border border-n-weak flex-shrink-0 text-n-brand p-2"
            />
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Credenciais n8n</h3>
              <p class="text-xs text-n-slate-10">n8n → Settings → API → Create an API key</p>
            </div>
          </div>

          <!-- URL base -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">URL base do n8n <span class="text-red-500">*</span></label>
            <input
              v-model="n8nUrl"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="https://n8n.seudominio.com"
            />
            <p class="text-xs text-n-slate-9 mt-1">Sem barra no final. Ex: <code>https://n8n.cevico.com.br</code></p>
          </div>

          <!-- API Key -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              API Key
              <span v-if="isConfigured" class="text-green-600 font-normal ml-1">(já configurada)</span>
              <span v-else class="text-red-500">*</span>
            </label>
            <input
              v-model="n8nApiKey"
              type="password"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              :placeholder="isConfigured ? 'Digite para substituir a key atual' : 'n8n_api_xxxxxxxxxxxxxxxx'"
            />
            <p class="text-xs text-n-slate-9 mt-1">n8n → Settings → API → Create an API key</p>
          </div>

          <!-- Botões -->
          <div class="flex gap-2 pt-1">
            <button
              class="flex-1 bg-[#EA4B71] text-white rounded-lg py-2 text-sm font-medium hover:bg-[#EA4B71]/90 disabled:opacity-50 transition-colors"
              :disabled="isSaving || !n8nUrl.trim()"
              @click="save"
            >
              {{ isSaving ? 'Salvando...' : 'Salvar configurações' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isTesting || !isConfigured"
              @click="testConnection"
            >
              <span :class="isTesting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-zap'" class="text-sm" />
              {{ isTesting ? 'Testando...' : 'Testar conexão' }}
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
            {{ testResult.message }}
          </div>
        </div>

        <!-- Workflows -->
        <div class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Workflows disponíveis</h3>
              <p v-if="fetchedAt" class="text-xs text-n-slate-9 mt-0.5">Última importação: {{ fetchedAt }}</p>
              <p v-else class="text-xs text-n-slate-9 mt-0.5">Importe para usar nos menus de automação do CRM</p>
            </div>
            <button
              class="flex items-center gap-1.5 px-3 py-1.5 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex-shrink-0"
              :disabled="isFetching || !isConfigured"
              @click="fetchWorkflows"
            >
              <span :class="isFetching ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-refresh-cw'" class="text-sm" />
              {{ isFetching ? 'Buscando...' : 'Buscar workflows' }}
            </button>
          </div>

          <!-- Empty -->
          <div
            v-if="workflowCount === 0"
            class="flex flex-col items-center justify-center py-10 bg-n-alpha-1 rounded-xl text-center"
          >
            <span class="i-lucide-workflow text-3xl text-n-slate-9 mb-2" />
            <p class="text-sm text-n-slate-10">
              {{ isConfigured
                ? 'Clique em "Buscar workflows" para importar os workflows ativos do n8n.'
                : 'Configure a URL e a API Key para importar workflows.' }}
            </p>
          </div>

          <!-- List -->
          <div v-else class="space-y-2">
            <div
              v-for="wf in workflows"
              :key="wf.id"
              class="flex items-center gap-3 px-3 py-2.5 bg-n-solid-1 rounded-xl border border-n-weak"
            >
              <span
                class="w-2 h-2 rounded-full flex-shrink-0"
                :class="wf.active ? 'bg-green-500' : 'bg-n-slate-9'"
              />
              <span class="text-sm text-n-slate-12 flex-1 truncate">{{ wf.name }}</span>
              <span class="text-[10px] font-mono text-n-slate-9 flex-shrink-0">{{ wf.id }}</span>
              <span
                class="text-[10px] px-1.5 py-0.5 rounded font-medium flex-shrink-0"
                :class="wf.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >
                {{ wf.active ? 'Ativo' : 'Off' }}
              </span>
              <span v-if="wf.webhook_url" class="i-lucide-link text-n-slate-9 text-sm flex-shrink-0" title="Webhook URL detectada" />
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
            <li>Configure a URL base e a API Key e salve.</li>
            <li>Clique em <strong>"Buscar workflows"</strong> para importar os workflows ativos do n8n.</li>
            <li>No CRM, entre no <strong>Modo Programação</strong> de qualquer coluna.</li>
            <li>Crie uma automação com a ação <strong>"Acionar fluxo n8n"</strong>.</li>
            <li>Selecione o workflow no dropdown — a URL do webhook é detectada automaticamente.</li>
          </ol>
        </div>

      </div>
    </template>
  </SettingsLayout>
</template>
