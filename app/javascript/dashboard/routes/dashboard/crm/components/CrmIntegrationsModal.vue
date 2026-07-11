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

// ── Meta (Facebook/Instagram Ads) ──────────────────────────
const meta = ref({ pixel_id: '', access_token: '', ad_account_id: '', test_event_code: '' });
const isMetaSaving = ref(false);
const isMetaTesting = ref(false);
const metaTestResult = ref(null);
const showMetaRequirements = ref(false);

// ── Google ─────────────────────────────────────────────────
const google = ref({ measurement_id: '', api_secret: '', client_id: '', developer_token: '', customer_id: '' });
const isGoogleSaving = ref(false);
const isGoogleTesting = ref(false);
const googleTestResult = ref(null);
const showGoogleRequirements = ref(false);

onMounted(async () => {
  await store.dispatch('crm/fetchSettings');
  n8nUrl.value    = settings.value.n8n_base_url || '';
  n8nApiKey.value = '';  // nunca pré-preenche a key por segurança

  const m = settings.value.meta_ads || {};
  meta.value = {
    pixel_id: m.pixel_id || '',
    access_token: '', // nunca pré-preenche
    ad_account_id: m.ad_account_id || '',
    test_event_code: m.test_event_code || '',
  };

  const g = settings.value.google_ads || {};
  google.value = {
    measurement_id: g.measurement_id || '',
    api_secret: '',
    client_id: g.client_id || '',
    developer_token: '',
    customer_id: g.customer_id || '',
  };
});

const metaStatus = computed(() => settings.value.meta_ads || {});
const googleStatus = computed(() => settings.value.google_ads || {});

const saveMeta = async () => {
  isMetaSaving.value = true;
  metaTestResult.value = null;
  try {
    const payload = {};
    if (meta.value.pixel_id.trim()) payload.pixel_id = meta.value.pixel_id.trim();
    if (meta.value.access_token.trim()) payload.access_token = meta.value.access_token.trim();
    payload.ad_account_id = meta.value.ad_account_id.trim();
    payload.test_event_code = meta.value.test_event_code.trim();
    await store.dispatch('crm/updateMetaAds', payload);
    meta.value.access_token = '';
    useAlert('Configurações da Meta salvas');
  } catch {
    useAlert('Erro ao salvar configurações da Meta.');
  } finally {
    isMetaSaving.value = false;
  }
};

const testMeta = async () => {
  isMetaTesting.value = true;
  metaTestResult.value = null;
  try {
    const result = await store.dispatch('crm/testMetaAds');
    metaTestResult.value = result.success
      ? { success: true, message: `Evento de teste enviado! (${result.events_received ?? 1} recebido pela Meta)` }
      : { success: false, message: result.error || 'Falha no envio.' };
  } catch {
    metaTestResult.value = { success: false, message: 'Erro inesperado ao testar.' };
  } finally {
    isMetaTesting.value = false;
  }
};

const saveGoogle = async () => {
  isGoogleSaving.value = true;
  googleTestResult.value = null;
  try {
    const payload = {};
    if (google.value.measurement_id.trim()) payload.measurement_id = google.value.measurement_id.trim();
    if (google.value.api_secret.trim()) payload.api_secret = google.value.api_secret.trim();
    if (google.value.client_id.trim()) payload.client_id = google.value.client_id.trim();
    if (google.value.developer_token.trim()) payload.developer_token = google.value.developer_token.trim();
    payload.customer_id = google.value.customer_id.trim();
    await store.dispatch('crm/updateGoogleAds', payload);
    google.value.api_secret = '';
    google.value.developer_token = '';
    useAlert('Configurações do Google salvas');
  } catch {
    useAlert('Erro ao salvar configurações do Google.');
  } finally {
    isGoogleSaving.value = false;
  }
};

const testGoogle = async () => {
  isGoogleTesting.value = true;
  googleTestResult.value = null;
  try {
    const result = await store.dispatch('crm/testGoogleAds');
    googleTestResult.value = result.success
      ? { success: true, message: 'Evento de teste enviado ao GA4!' }
      : { success: false, message: result.error || 'Falha no envio.' };
  } catch {
    googleTestResult.value = { success: false, message: 'Erro inesperado ao testar.' };
  } finally {
    isGoogleTesting.value = false;
  }
};

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

        <!-- ══ Meta (Facebook / Instagram Ads) ══ -->
        <div class="border-t border-n-weak pt-5">
          <div class="flex items-center gap-3 mb-4">
            <div class="w-9 h-9 rounded-xl bg-[#1877F2]/10 flex items-center justify-center flex-shrink-0">
              <span class="i-lucide-facebook text-lg text-[#1877F2]" />
            </div>
            <div class="min-w-0">
              <h3 class="text-sm font-semibold text-n-slate-12">Meta — Facebook e Instagram Ads</h3>
              <p class="text-xs text-n-slate-10">Envia conversões (CAPI) e recebe dados das campanhas (Insights)</p>
            </div>
            <div class="ml-auto flex flex-col items-end gap-1 flex-shrink-0">
              <span
                class="text-[10px] px-2 py-0.5 rounded-full font-medium"
                :class="metaStatus.configured ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >
                {{ metaStatus.configured ? '✓ Envio (CAPI)' : 'Envio: pendente' }}
              </span>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full font-medium"
                :class="metaStatus.insights_configured ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >
                {{ metaStatus.insights_configured ? '✓ Recebimento (Insights)' : 'Recebimento: pendente' }}
              </span>
            </div>
          </div>

          <!-- Requisitos -->
          <button
            class="w-full flex items-center gap-2 text-xs text-n-brand mb-3"
            @click="showMetaRequirements = !showMetaRequirements"
          >
            <span :class="showMetaRequirements ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'" />
            O que é necessário para integrar com a Meta
          </button>
          <div v-if="showMetaRequirements" class="bg-n-alpha-1 rounded-xl p-3.5 mb-4 text-xs text-n-slate-11 space-y-2">
            <p><b>1. Business Manager</b> da clínica com acesso ao Pixel e à conta de anúncios.</p>
            <p><b>2. ID do Pixel</b> — Gerenciador de Eventos → Fontes de dados → seu Pixel (número de ~15 dígitos).</p>
            <p><b>3. Token de acesso do sistema</b> — Configurações do negócio → Usuários → Usuários do sistema → gerar token com permissões <code class="bg-n-alpha-2 px-1 rounded">ads_read</code> e <code class="bg-n-alpha-2 px-1 rounded">ads_management</code>.</p>
            <p><b>4. ID da conta de anúncios</b> (para RECEBER insights) — formato <code class="bg-n-alpha-2 px-1 rounded">act_1234567890</code>.</p>
            <p><b>5. Código de evento de teste</b> (opcional) — Gerenciador de Eventos → Testar eventos.</p>
            <p class="text-n-slate-9">Com isso o sistema ENVIA eventos (lead, agendamento, cirurgia — via automações do CRM) e RECEBE investimento/resultados das campanhas para o Funil de Tráfego e Dashboard.</p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">ID do Pixel</label>
              <input
                v-model="meta.pixel_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                placeholder="123456789012345"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Token de acesso
                <span v-if="metaStatus.access_token_set" class="text-green-600 font-normal">(já configurado)</span>
              </label>
              <input
                v-model="meta.access_token"
                type="password"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                :placeholder="metaStatus.access_token_set ? 'Digite para substituir' : 'EAAxxxx...'"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">ID da conta de anúncios</label>
              <input
                v-model="meta.ad_account_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                placeholder="act_1234567890"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Código de teste <span class="text-n-slate-9">(opcional)</span></label>
              <input
                v-model="meta.test_event_code"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                placeholder="TEST12345"
              />
            </div>
          </div>

          <div class="flex gap-2 mt-3">
            <button
              class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
              :disabled="isMetaSaving"
              @click="saveMeta"
            >
              {{ isMetaSaving ? 'Salvando...' : 'Salvar' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isMetaTesting || !metaStatus.configured"
              @click="testMeta"
            >
              <span :class="isMetaTesting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-zap'" class="text-sm" />
              {{ isMetaTesting ? 'Testando...' : 'Testar envio' }}
            </button>
          </div>

          <div
            v-if="metaTestResult"
            class="mt-3 flex items-start gap-2 px-3 py-2.5 rounded-lg text-sm"
            :class="metaTestResult.success
              ? 'bg-green-500/10 text-green-700 border border-green-500/20'
              : 'bg-red-500/10 text-red-700 border border-red-500/20'"
          >
            <span
              class="text-base flex-shrink-0 mt-0.5"
              :class="metaTestResult.success ? 'i-lucide-check-circle' : 'i-lucide-alert-circle'"
            />
            {{ metaTestResult.message }}
          </div>
        </div>

        <!-- ══ Google (GA4 + Google Ads) ══ -->
        <div class="border-t border-n-weak pt-5">
          <div class="flex items-center gap-3 mb-4">
            <div class="w-9 h-9 rounded-xl bg-[#4285F4]/10 flex items-center justify-center flex-shrink-0">
              <span class="i-lucide-chrome text-lg text-[#4285F4]" />
            </div>
            <div class="min-w-0">
              <h3 class="text-sm font-semibold text-n-slate-12">Google — GA4 e Google Ads</h3>
              <p class="text-xs text-n-slate-10">Envia conversões (Measurement Protocol) e prepara os Insights do Google Ads</p>
            </div>
            <div class="ml-auto flex flex-col items-end gap-1 flex-shrink-0">
              <span
                class="text-[10px] px-2 py-0.5 rounded-full font-medium"
                :class="googleStatus.configured ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >
                {{ googleStatus.configured ? '✓ Envio (GA4)' : 'Envio: pendente' }}
              </span>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full font-medium"
                :class="googleStatus.insights_configured ? 'bg-green-500/15 text-green-600' : 'bg-amber-500/15 text-amber-600'"
              >
                {{ googleStatus.insights_configured ? '✓ Recebimento (Ads API)' : 'Recebimento: aguarda token' }}
              </span>
            </div>
          </div>

          <!-- Requisitos -->
          <button
            class="w-full flex items-center gap-2 text-xs text-n-brand mb-3"
            @click="showGoogleRequirements = !showGoogleRequirements"
          >
            <span :class="showGoogleRequirements ? 'i-lucide-chevron-down' : 'i-lucide-chevron-right'" />
            O que é necessário para integrar com o Google
          </button>
          <div v-if="showGoogleRequirements" class="bg-n-alpha-1 rounded-xl p-3.5 mb-4 text-xs text-n-slate-11 space-y-2">
            <p><b>Para ENVIAR conversões (GA4):</b></p>
            <p><b>1. Measurement ID</b> — GA4 → Administrador → Fluxos de dados → seu site (formato <code class="bg-n-alpha-2 px-1 rounded">G-XXXXXXX</code>).</p>
            <p><b>2. API Secret</b> — no mesmo fluxo de dados → Measurement Protocol → Criar chave secreta.</p>
            <p class="pt-1"><b>Para RECEBER dados do Google Ads (investimento/campanhas):</b></p>
            <p><b>3. Developer Token</b> — Google Ads → Ferramentas → Central de API. ⚠ Aprovação do Google pode levar semanas; a tela já está pronta para quando chegar.</p>
            <p><b>4. Customer ID</b> — número da conta Google Ads (formato <code class="bg-n-alpha-2 px-1 rounded">123-456-7890</code>).</p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Measurement ID (GA4)</label>
              <input
                v-model="google.measurement_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                placeholder="G-XXXXXXXXXX"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                API Secret
                <span v-if="googleStatus.api_secret_set" class="text-green-600 font-normal">(já configurada)</span>
              </label>
              <input
                v-model="google.api_secret"
                type="password"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                :placeholder="googleStatus.api_secret_set ? 'Digite para substituir' : 'xxxxxxx'"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Developer Token <span class="text-n-slate-9">(Google Ads)</span>
                <span v-if="googleStatus.developer_token_set" class="text-green-600 font-normal">(já configurado)</span>
              </label>
              <input
                v-model="google.developer_token"
                type="password"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                :placeholder="googleStatus.developer_token_set ? 'Digite para substituir' : 'Aguardando aprovação do Google'"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Customer ID <span class="text-n-slate-9">(Google Ads)</span></label>
              <input
                v-model="google.customer_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                placeholder="123-456-7890"
              />
            </div>
          </div>

          <div class="flex gap-2 mt-3">
            <button
              class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
              :disabled="isGoogleSaving"
              @click="saveGoogle"
            >
              {{ isGoogleSaving ? 'Salvando...' : 'Salvar' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isGoogleTesting || !googleStatus.configured"
              @click="testGoogle"
            >
              <span :class="isGoogleTesting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-zap'" class="text-sm" />
              {{ isGoogleTesting ? 'Testando...' : 'Testar envio' }}
            </button>
          </div>

          <div
            v-if="googleTestResult"
            class="mt-3 flex items-start gap-2 px-3 py-2.5 rounded-lg text-sm"
            :class="googleTestResult.success
              ? 'bg-green-500/10 text-green-700 border border-green-500/20'
              : 'bg-red-500/10 text-red-700 border border-red-500/20'"
          >
            <span
              class="text-base flex-shrink-0 mt-0.5"
              :class="googleTestResult.success ? 'i-lucide-check-circle' : 'i-lucide-alert-circle'"
            />
            {{ googleTestResult.message }}
          </div>
        </div>

      </div>
    </div>
  </div>
</template>
