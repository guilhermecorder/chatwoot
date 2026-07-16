<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

// inline: renderiza como PÁGINA em vez de modal flutuante
// only: mostra só uma seção ('n8n' | 'meta' | 'google' | 'ai') — usado
// pelos cards "Configurar" da página de Integrações
const props = defineProps({
  inline: { type: Boolean, default: false },
  only: { type: String, default: null },
});

const showSection = s => !props.only || props.only === s;

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

// ── Claude (IA nativa) ─────────────────────────────────────
const ai = ref({ api_key: '', model: '', effort: '' });
const isAiSaving = ref(false);
const isAiTesting = ref(false);
const aiTestResult = ref(null);

const testAi = async () => {
  isAiTesting.value = true;
  aiTestResult.value = null;
  try {
    const { data } = await CrmAPI.testAi();
    aiTestResult.value = data;
  } catch {
    aiTestResult.value = { success: false, message: 'Erro ao testar a conexão.' };
  } finally {
    isAiTesting.value = false;
  }
};

const AI_MODELS = [
  { value: 'claude-opus-4-8', label: 'Claude Opus 4.8 — melhor análise (padrão)' },
  { value: 'claude-sonnet-5', label: 'Claude Sonnet 5 — equilíbrio' },
  { value: 'claude-haiku-4-5', label: 'Claude Haiku 4.5 — mais barato e rápido' },
];

// Esforço = quanto a IA "pensa" antes de responder (mais esforço =
// análise melhor e um pouco mais cara/lenta). O Haiku ignora este campo.
const AI_EFFORTS = [
  { value: 'low', label: 'Baixo — rápido e econômico' },
  { value: 'medium', label: 'Médio — equilíbrio' },
  { value: 'high', label: 'Alto — padrão recomendado' },
  { value: 'max', label: 'Máximo — melhor análise possível' },
];

// ── Gemini (Google) — integração nativa: chave p/ gerar IMAGENS nas Páginas ──
const gemini = ref({ api_key: '' });
const isGeminiSaving = ref(false);
const isGeminiTesting = ref(false);
const geminiTestResult = ref(null);

const saveGemini = async () => {
  if (!gemini.value.api_key.trim()) {
    useAlert('Cole a chave do Gemini para salvar.');
    return;
  }
  isGeminiSaving.value = true;
  try {
    await CrmAPI.updateAi({ gemini_api_key: gemini.value.api_key.trim() });
    gemini.value.api_key = '';
    await store.dispatch('crm/fetchSettings');
    useAlert('Chave do Gemini salva!');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao salvar a chave do Gemini.');
  } finally {
    isGeminiSaving.value = false;
  }
};

const testGeminiConnection = async () => {
  isGeminiTesting.value = true;
  geminiTestResult.value = null;
  try {
    const { data } = await CrmAPI.testGemini();
    geminiTestResult.value = data;
  } catch {
    geminiTestResult.value = { success: false, message: 'Erro ao testar a conexão.' };
  } finally {
    isGeminiTesting.value = false;
  }
};

const saveAi = async () => {
  isAiSaving.value = true;
  try {
    const payload = { model: ai.value.model, effort: ai.value.effort };
    if (ai.value.api_key.trim()) payload.api_key = ai.value.api_key.trim();
    await CrmAPI.updateAi(payload);
    ai.value.api_key = '';
    await store.dispatch('crm/fetchSettings');
    useAlert('Configurações de IA salvas');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao salvar configurações de IA.');
  } finally {
    isAiSaving.value = false;
  }
};

// ── Google Sheets (planilha de cirurgias) ──────────────────
const sheets = ref({ sheet_url: '' });
const isSheetsSaving = ref(false);
const isSheetsTesting = ref(false);
const sheetsTestResult = ref(null);
const sheetsPreview = ref(null);

const saveSheets = async () => {
  isSheetsSaving.value = true;
  sheetsTestResult.value = null;
  sheetsPreview.value = null;
  try {
    await CrmAPI.updateSheets({ sheet_url: sheets.value.sheet_url.trim() });
    await store.dispatch('crm/fetchSettings');
    useAlert('Planilha salva');
  } catch {
    useAlert('Erro ao salvar a planilha.');
  } finally {
    isSheetsSaving.value = false;
  }
};

const testSheets = async () => {
  isSheetsTesting.value = true;
  sheetsTestResult.value = null;
  sheetsPreview.value = null;
  try {
    const { data } = await CrmAPI.testSheets();
    sheetsTestResult.value = data;
    if (data.success) sheetsPreview.value = data.preview || [];
    await store.dispatch('crm/fetchSettings');
  } catch {
    sheetsTestResult.value = { success: false, message: 'Erro ao testar a planilha.' };
  } finally {
    isSheetsTesting.value = false;
  }
};

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

  const a = settings.value.ai || {};
  ai.value = { api_key: '', model: a.model || 'claude-opus-4-8', effort: a.effort || 'high' };

  const g = settings.value.google_ads || {};
  google.value = {
    measurement_id: g.measurement_id || '',
    api_secret: '',
    client_id: g.client_id || '',
    developer_token: '',
    customer_id: g.customer_id || '',
  };

  sheets.value = { sheet_url: settings.value.sheets?.sheet_url || '' };
});

const metaStatus = computed(() => settings.value.meta_ads || {});
const googleStatus = computed(() => settings.value.google_ads || {});
const aiStatus = computed(() => settings.value.ai || {});
const sheetsStatus = computed(() => settings.value.sheets || {});

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
    :class="props.inline
      ? 'w-full flex justify-center'
      : 'fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4'"
    @click.self="!props.inline && emit('close')"
  >
    <div
      class="bg-n-solid-1 rounded-2xl flex flex-col w-full"
      :class="props.inline
        ? 'max-w-2xl border border-n-weak shadow-sm'
        : 'shadow-2xl max-w-lg max-h-[88vh]'"
    >

      <!-- Header -->
      <div class="flex items-center justify-between px-5 pt-5 pb-4 border-b border-n-weak flex-shrink-0">
        <div class="flex items-center gap-2.5">
          <span class="i-lucide-plug text-lg text-n-brand" />
          <h2 class="text-base font-semibold text-n-slate-12">Integrações</h2>
        </div>
        <button
          v-if="!props.inline"
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
          @click="emit('close')"
        />
      </div>

      <!-- Body -->
      <div class="flex-1 overflow-y-auto p-5 space-y-6">

        <!-- n8n Section -->
        <div v-if="showSection('n8n')">
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
        <div v-if="showSection('meta')" :class="props.only ? '' : 'border-t border-n-weak pt-5'">
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

          <!-- Atribuição de anúncio (CTWA) — automática -->
          <div class="mt-3 bg-n-alpha-1 rounded-xl p-3.5 text-xs text-n-slate-11 space-y-1.5">
            <p class="flex items-center gap-1.5 font-medium text-n-slate-12">
              <span class="i-lucide-megaphone text-blue-500" />
              Atribuição de anúncio (click-to-WhatsApp) — automática
            </p>
            <p>
              Quando o paciente chega clicando em um anúncio, a Meta manda os dados
              do anúncio junto com a primeira mensagem. O sistema grava isso no
              contato ("Veio de anúncio") e usa nas conversões enviadas (ctwa_clid) —
              não precisa configurar nada.
            </p>
            <p>
              O ranking completo (qual anúncio gerou cirurgia, CPL, CAC, ROAS) fica
              em <b>Relatórios → Anúncios (Meta)</b>, onde também dá para processar
              o histórico de mensagens antigas.
            </p>
          </div>
        </div>

        <!-- ══ Google (GA4 + Google Ads) ══ -->
        <div v-if="showSection('google')" :class="props.only ? '' : 'border-t border-n-weak pt-5'">
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

        <!-- ══ Claude (IA nativa do sistema) ══ -->
        <div v-if="showSection('ai')" :class="props.only ? '' : 'border-t border-n-weak pt-5'">
          <div class="flex items-center gap-3 mb-4">
            <div class="w-9 h-9 rounded-xl bg-[#D97706]/10 flex items-center justify-center flex-shrink-0">
              <span class="i-lucide-sparkles text-lg text-[#D97706]" />
            </div>
            <div class="min-w-0">
              <h3 class="text-sm font-semibold text-n-slate-12">Claude — IA nativa do sistema</h3>
              <p class="text-xs text-n-slate-10">Análise de conversas (interesse do paciente) e insights de marketing dos formulários</p>
            </div>
            <span
              class="ml-auto text-[10px] px-2 py-0.5 rounded-full font-medium flex-shrink-0"
              :class="aiStatus.configured ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
            >
              {{ aiStatus.configured ? '✓ Conectada' : 'Pendente' }}
            </span>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Chave da API (Anthropic)
                <span v-if="aiStatus.api_key_set" class="text-green-600 font-normal">(já configurada)</span>
              </label>
              <input
                v-model="ai.api_key"
                type="password"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                :placeholder="aiStatus.api_key_set ? 'Digite para substituir' : 'sk-ant-...'"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Modelo padrão</label>
              <select
                v-model="ai.model"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="m in AI_MODELS" :key="m.value" :value="m.value">{{ m.label }}</option>
              </select>
            </div>
            <div class="col-span-2">
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Esforço padrão
                <span class="text-n-slate-9 font-normal">(quanto a IA pensa antes de responder)</span>
              </label>
              <select
                v-model="ai.effort"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option v-for="e in AI_EFFORTS" :key="e.value" :value="e.value">{{ e.label }}</option>
              </select>
            </div>
          </div>

          <p class="text-[11px] text-n-slate-9 mt-2">
            Crie a chave em console.anthropic.com → API Keys. Modelo e esforço aqui são o
            PADRÃO — cada agente pode usar valores próprios em Automações → Agentes de IA.
            O Haiku ignora o campo de esforço.
          </p>

          <div class="flex gap-2 mt-3">
            <button
              class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
              :disabled="isAiSaving"
              @click="saveAi"
            >
              {{ isAiSaving ? 'Salvando...' : 'Salvar' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isAiTesting || !aiStatus.configured"
              @click="testAi"
            >
              <span :class="isAiTesting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-zap'" class="text-sm" />
              {{ isAiTesting ? 'Testando...' : 'Testar conexão' }}
            </button>
          </div>

          <div
            v-if="aiTestResult"
            class="mt-3 flex items-start gap-2 px-3 py-2.5 rounded-lg text-sm"
            :class="aiTestResult.success
              ? 'bg-green-500/10 text-green-700 border border-green-500/20'
              : 'bg-red-500/10 text-red-700 border border-red-500/20'"
          >
            <span
              class="text-base flex-shrink-0 mt-0.5"
              :class="aiTestResult.success ? 'i-lucide-check-circle' : 'i-lucide-alert-circle'"
            />
            {{ aiTestResult.message }}
          </div>
        </div>

        <!-- ══ Google Sheets (planilha de cirurgias) ══ -->
        <!-- ══ Gemini (Google) — imagens por IA nas Páginas ══ -->
        <div v-if="showSection('gemini')" :class="props.only ? '' : 'border-t border-n-weak pt-5'">
          <div class="flex items-center gap-2 mb-1">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #1A73E8, #9B72CB, #D96570)">
              <span class="i-lucide-image-plus text-white text-sm" />
            </span>
            <p class="text-sm font-semibold text-n-slate-12">Gemini — IA do Google</p>
            <span
              class="text-[10px] px-2 py-0.5 rounded-full font-medium"
              :class="aiStatus.gemini_key_set ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-10'"
            >
              ● {{ aiStatus.gemini_key_set ? 'Conectado' : 'Não configurado' }}
            </span>
          </div>
          <p class="text-xs text-n-slate-10 mb-3">
            Reservado para GERAR IMAGENS nas Páginas (heros, ilustrações de procedimentos).
            A chave sai do <a href="https://aistudio.google.com/apikey" target="_blank" rel="noopener" class="text-n-brand hover:underline">Google AI Studio</a> — gratuita para começar.
          </p>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Chave da API (Google AI Studio)
              <span v-if="aiStatus.gemini_key_set" class="text-green-600 font-normal">(já configurada)</span>
            </label>
            <input
              v-model="gemini.api_key"
              type="password"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
              :placeholder="aiStatus.gemini_key_set ? 'Digite para substituir' : 'AIza...'"
            />
          </div>
          <div class="flex items-center gap-2 mt-3 flex-wrap">
            <button
              class="h-9 px-4 rounded-lg bg-n-brand text-white text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50"
              :disabled="isGeminiSaving"
              @click="saveGemini"
            >
              {{ isGeminiSaving ? 'Salvando…' : 'Salvar chave' }}
            </button>
            <button
              class="h-9 px-4 rounded-lg border border-n-weak text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
              :disabled="isGeminiTesting || !aiStatus.gemini_key_set"
              @click="testGeminiConnection"
            >
              {{ isGeminiTesting ? 'Testando…' : 'Testar conexão' }}
            </button>
            <span
              v-if="geminiTestResult"
              class="text-xs font-medium"
              :class="geminiTestResult.success ? 'text-green-600' : 'text-red-500'"
            >
              {{ geminiTestResult.message }}
            </span>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-2">
            O botão "Gerar imagem" nas seções das Páginas entra na próxima rodada — a conexão já fica pronta.
          </p>
        </div>

        <div v-if="showSection('sheets')" :class="props.only ? '' : 'border-t border-n-weak pt-5'">
          <div class="flex items-center gap-3 mb-4">
            <div class="w-9 h-9 rounded-xl bg-[#0F9D58]/10 flex items-center justify-center flex-shrink-0">
              <span class="i-lucide-sheet text-lg text-[#0F9D58]" />
            </div>
            <div class="min-w-0">
              <h3 class="text-sm font-semibold text-n-slate-12">Google Sheets — planilha de cirurgias</h3>
              <p class="text-xs text-n-slate-10">Os dados da planilha entram no Dashboard CEVICO (bloco Cirurgias)</p>
            </div>
            <span
              class="ml-auto text-[10px] px-2 py-0.5 rounded-full font-medium flex-shrink-0"
              :class="sheetsStatus.configured ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
            >
              {{ sheetsStatus.configured ? '✓ Conectada' : 'Pendente' }}
            </span>
          </div>

          <div class="bg-n-alpha-1 rounded-xl p-3.5 mb-4 text-xs text-n-slate-11 space-y-1.5">
            <p class="font-medium text-n-slate-12">Como preparar a planilha (2 passos):</p>
            <p><b>1.</b> No Google Sheets: Compartilhar → Acesso geral → <b>"Qualquer pessoa com o link"</b> (Leitor) → copiar o link.</p>
            <p><b>2.</b> A primeira linha precisa ter os títulos das colunas. O sistema reconhece:
              <b>Data</b>, <b>Nome</b> (ou Paciente), <b>Telefone</b>, <b>Procedimento</b> (ou Cirurgia), <b>Valor</b> e <b>Unidade</b>.</p>
            <p class="text-n-slate-9">Só Data e Nome são obrigatórias — as demais enriquecem o Dashboard. A planilha é relida automaticamente a cada 1 hora.</p>
          </div>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Link da planilha</label>
            <input
              v-model="sheets.sheet_url"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="https://docs.google.com/spreadsheets/d/..."
            />
          </div>

          <div class="flex gap-2 mt-3">
            <button
              class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
              :disabled="isSheetsSaving"
              @click="saveSheets"
            >
              {{ isSheetsSaving ? 'Salvando...' : 'Salvar' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isSheetsTesting || !sheetsStatus.configured"
              @click="testSheets"
            >
              <span :class="isSheetsTesting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-download'" class="text-sm" />
              {{ isSheetsTesting ? 'Importando...' : 'Importar agora' }}
            </button>
          </div>

          <div
            v-if="sheetsTestResult"
            class="mt-3 flex items-start gap-2 px-3 py-2.5 rounded-lg text-sm"
            :class="sheetsTestResult.success
              ? 'bg-green-500/10 text-green-700 border border-green-500/20'
              : 'bg-red-500/10 text-red-700 border border-red-500/20'"
          >
            <span
              class="text-base flex-shrink-0 mt-0.5"
              :class="sheetsTestResult.success ? 'i-lucide-check-circle' : 'i-lucide-alert-circle'"
            />
            {{ sheetsTestResult.message }}
          </div>

          <!-- Prévia das primeiras linhas -->
          <div v-if="sheetsPreview?.length" class="mt-3 border border-n-weak rounded-xl overflow-hidden">
            <p class="text-[11px] font-medium text-n-slate-10 px-3 pt-2.5 pb-1">Prévia (primeiras linhas):</p>
            <div class="overflow-x-auto">
              <table class="w-full text-xs">
                <thead>
                  <tr class="text-left text-n-slate-10">
                    <th class="px-3 py-1.5 font-medium">Data</th>
                    <th class="px-3 py-1.5 font-medium">Nome</th>
                    <th class="px-3 py-1.5 font-medium">Procedimento</th>
                    <th class="px-3 py-1.5 font-medium">Valor</th>
                    <th class="px-3 py-1.5 font-medium">Unidade</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="(row, i) in sheetsPreview" :key="i" class="border-t border-n-weak text-n-slate-12">
                    <td class="px-3 py-1.5 whitespace-nowrap">{{ row.date || '—' }}</td>
                    <td class="px-3 py-1.5">{{ row.name || '—' }}</td>
                    <td class="px-3 py-1.5">{{ row.procedure || '—' }}</td>
                    <td class="px-3 py-1.5 whitespace-nowrap">{{ row.value || '—' }}</td>
                    <td class="px-3 py-1.5">{{ row.unit || '—' }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <p v-if="sheetsStatus.fetched_at" class="text-[11px] text-n-slate-9 mt-2">
            Última importação: {{ new Date(sheetsStatus.fetched_at).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' }) }}
            — {{ sheetsStatus.cached_count }} linha(s) em uso no Dashboard.
          </p>
        </div>

      </div>
    </div>
  </div>
</template>
