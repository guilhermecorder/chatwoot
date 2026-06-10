<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const emit = defineEmits(['close']);

const store = useStore();
const settings  = useMapGetter('crm/getSettings');
const workflows = useMapGetter('crm/getN8nWorkflows');

const n8nUrl    = ref('');
const n8nApiKey = ref('');
const isSaving  = ref(false);
const isTesting = ref(false);
const isFetching = ref(false);
const testResult = ref(null);   // { success, message }

onMounted(async () => {
  await store.dispatch('crm/fetchSettings');
  n8nUrl.value    = settings.value.n8n_base_url || '';
  n8nApiKey.value = '';  // nunca pré-preenche a key por segurança
});

const isConfigured = computed(() => settings.value.n8n_api_key_configured && settings.value.n8n_base_url);
const workflowCount = computed(() => workflows.value?.length ?? 0);
const fetchedAt = computed(() => {
  const d = settings.value.n8n_workflows_fetched_at;
  if (!d) return null;
  return new Date(d).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
});

const saveSettings = async () => {
  if (!n8nUrl.value.trim()) return;
  isSaving.value = true;
  testResult.value = null;
  try {
    const payload = { n8n_base_url: n8nUrl.value.trim() };
    if (n8nApiKey.value.trim()) payload.n8n_api_key = n8nApiKey.value.trim();
    await store.dispatch('crm/updateSettings', payload);
    n8nApiKey.value = '';
    useAlert('Configurações salvas');
  } catch {
    useAlert('Erro ao salvar configurações.');
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
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-lg flex flex-col max-h-[88vh]">

      <!-- Header -->
      <div class="flex items-center justify-between px-5 pt-5 pb-4 border-b border-n-weak flex-shrink-0">
        <div class="flex items-center gap-2.5">
          <span class="i-lucide-plug text-lg text-n-brand" />
          <h2 class="text-base font-semibold text-n-slate-12">Integrações</h2>
        </div>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
          @click="emit('close')"
        />
      </div>

      <!-- Body -->
      <div class="flex-1 overflow-y-auto p-5 space-y-6">

        <!-- n8n Section -->
        <div>
          <!-- Section header -->
          <div class="flex items-center gap-3 mb-4">
            <div class="w-9 h-9 rounded-xl bg-[#EA4B71]/10 flex items-center justify-center flex-shrink-0">
              <span class="i-lucide-workflow text-lg text-[#EA4B71]" />
            </div>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">n8n</h3>
              <p class="text-xs text-n-slate-10">Conecte seu n8n para acionar workflows automaticamente</p>
            </div>
            <!-- Status badge -->
            <span
              class="ml-auto text-[11px] px-2 py-0.5 rounded-full font-medium flex-shrink-0"
              :class="isConfigured
                ? 'bg-green-500/15 text-green-600'
                : 'bg-n-alpha-2 text-n-slate-9'"
            >
              {{ isConfigured ? '✓ Conectado' : 'Não configurado' }}
            </span>
          </div>

          <!-- URL do n8n -->
          <div class="space-y-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">URL base do n8n</label>
              <input
                v-model="n8nUrl"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
                placeholder="https://n8n.seudominio.com"
              />
            </div>

            <!-- API Key -->
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                API Key
                <span v-if="isConfigured" class="text-green-600 font-normal ml-1">(já configurada)</span>
              </label>
              <input
                v-model="n8nApiKey"
                type="password"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
                :placeholder="isConfigured ? 'Digite para substituir a key atual' : 'n8n_api_...'"
              />
              <p class="text-xs text-n-slate-9 mt-1">
                Encontre em: n8n → Settings → API → Create an API key
              </p>
            </div>

            <!-- Botões salvar + testar -->
            <div class="flex gap-2">
              <button
                class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
                :disabled="isSaving || !n8nUrl.trim()"
                @click="saveSettings"
              >
                {{ isSaving ? 'Salvando...' : 'Salvar' }}
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

          <!-- Divider -->
          <div class="border-t border-n-weak my-5" />

          <!-- Workflows section -->
          <div>
            <div class="flex items-center justify-between mb-3">
              <div>
                <h4 class="text-xs font-semibold text-n-slate-12">Workflows disponíveis</h4>
                <p v-if="fetchedAt" class="text-[11px] text-n-slate-9 mt-0.5">
                  Última importação: {{ fetchedAt }}
                </p>
              </div>
              <button
                class="flex items-center gap-1.5 px-3 py-1.5 border border-n-weak rounded-lg text-xs text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors"
                :disabled="isFetching || !isConfigured"
                @click="fetchWorkflows"
              >
                <span :class="isFetching ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-refresh-cw'" class="text-sm" />
                {{ isFetching ? 'Buscando...' : 'Buscar workflows' }}
              </button>
            </div>

            <!-- Empty state -->
            <div
              v-if="workflowCount === 0"
              class="flex flex-col items-center justify-center py-8 bg-n-alpha-1 rounded-xl text-center"
            >
              <span class="i-lucide-workflow text-2xl text-n-slate-9 mb-2" />
              <p class="text-xs text-n-slate-10">
                {{ isConfigured
                  ? 'Clique em "Buscar workflows" para importar os workflows do seu n8n.'
                  : 'Configure a URL e a API Key para buscar workflows.' }}
              </p>
            </div>

            <!-- Workflow list -->
            <div v-else class="space-y-1.5">
              <div
                v-for="wf in workflows"
                :key="wf.id"
                class="flex items-center gap-3 px-3 py-2.5 bg-n-solid-2 rounded-lg border border-n-weak"
              >
                <span
                  class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                  :class="wf.active ? 'bg-green-500' : 'bg-n-slate-9'"
                />
                <span class="text-sm text-n-slate-12 flex-1 truncate">{{ wf.name }}</span>
                <span class="text-[10px] text-n-slate-9 font-mono flex-shrink-0">{{ wf.id }}</span>
                <span
                  class="text-[10px] px-1.5 py-0.5 rounded font-medium flex-shrink-0"
                  :class="wf.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
                >
                  {{ wf.active ? 'Ativo' : 'Off' }}
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- Placeholder para integrações futuras -->
        <div class="border-t border-n-weak pt-5">
          <h3 class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide mb-3">Em breve</h3>
          <div class="space-y-2">
            <div
              v-for="item in ['Meta Ads (Conversions API)', 'Google Ads (Enhanced Conversions)', 'WhatsApp Business API']"
              :key="item"
              class="flex items-center gap-3 px-3 py-2.5 rounded-lg border border-dashed border-n-weak opacity-50"
            >
              <span class="i-lucide-link text-sm text-n-slate-9" />
              <span class="text-sm text-n-slate-10">{{ item }}</span>
              <span class="ml-auto text-[10px] bg-n-alpha-2 text-n-slate-9 px-1.5 py-0.5 rounded">Em breve</span>
            </div>
          </div>
        </div>

      </div>
    </div>
  </div>
</template>
