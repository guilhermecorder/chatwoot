<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const store = useStore();
const settings = useMapGetter('crm/getSettings');
const { accountId } = useAccount();

const pixelId       = ref('');
const accessToken   = ref('');
const adAccountId   = ref('');
const testEventCode = ref('');
const isSaving      = ref(false);
const isTesting     = ref(false);
const testResult    = ref(null);

const metaConfig = computed(() => settings.value?.meta_ads ?? {});
const isConfigured = computed(() => metaConfig.value.configured);

// ── Lead Ads (formulários instantâneos) ─────────────────────────────
const pageId          = ref('');
const pageToken       = ref('');
const appSecret       = ref('');
const leadInboxId     = ref('');
const isSavingLeads   = ref(false);
const isTestingLeads  = ref(false);
const leadsTestResult = ref(null);
const isImporting     = ref(false);
let importPoll = null;

const leadsConfigured = computed(() => metaConfig.value.leads_configured);
const lastImport = computed(() => metaConfig.value.last_lead_import || null);
const webhookUrl = computed(
  () => `${window.location.origin}/webhooks/meta_leads/${accountId.value}`
);
const inboxes = useMapGetter('inboxes/getInboxes');

const startImportPoll = () => {
  clearInterval(importPoll);
  importPoll = setInterval(async () => {
    await store.dispatch('crm/fetchSettings');
    if (lastImport.value?.status !== 'running') clearInterval(importPoll);
  }, 5000);
};

onMounted(async () => {
  store.dispatch('inboxes/get');
  await store.dispatch('crm/fetchSettings');
  pixelId.value       = metaConfig.value.pixel_id       || '';
  adAccountId.value   = metaConfig.value.ad_account_id  || '';
  testEventCode.value = metaConfig.value.test_event_code || '';
  pageId.value        = metaConfig.value.page_id        || '';
  leadInboxId.value   = metaConfig.value.lead_inbox_id  || '';
  // tokens nunca são pré-preenchidos por segurança
  if (lastImport.value?.status === 'running') startImportPoll();
});

onBeforeUnmount(() => clearInterval(importPoll));

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

// ── Lead Ads ────────────────────────────────────────────────────────
const saveLeads = async () => {
  if (!pageId.value.trim()) {
    useAlert('Informe o ID da página do Facebook.');
    return;
  }
  isSavingLeads.value = true;
  leadsTestResult.value = null;
  try {
    const payload = {
      page_id: pageId.value.trim(),
      lead_inbox_id: leadInboxId.value || null,
    };
    if (pageToken.value.trim()) payload.page_access_token = pageToken.value.trim();
    if (appSecret.value.trim()) payload.app_secret = appSecret.value.trim();
    await store.dispatch('crm/updateMetaAds', payload);
    pageToken.value = '';
    appSecret.value = '';
    useAlert('Configurações de Lead Ads salvas!');
  } catch {
    useAlert('Erro ao salvar. Tente novamente.');
  } finally {
    isSavingLeads.value = false;
  }
};

const testLeads = async () => {
  isTestingLeads.value = true;
  leadsTestResult.value = null;
  try {
    leadsTestResult.value = await store.dispatch('crm/testMetaLeads');
  } catch {
    leadsTestResult.value = { success: false, error: 'Erro inesperado.' };
  } finally {
    isTestingLeads.value = false;
  }
};

const importLeads = async () => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Importar agora todos os leads que estão no Meta (últimos 90 dias)? Leads já importados não entram de novo.')) return;
  isImporting.value = true;
  try {
    const result = await store.dispatch('crm/importMetaLeads');
    if (result.error) {
      useAlert(result.error);
    } else {
      useAlert('Importação iniciada! Acompanhe o resultado aqui no card.');
      startImportPoll();
    }
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Erro ao iniciar a importação.');
  } finally {
    isImporting.value = false;
  }
};

const copyText = async text => {
  try {
    await navigator.clipboard.writeText(text);
    useAlert('Copiado!');
  } catch {
    useAlert('Não foi possível copiar.');
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
              <span v-else-if="!testResult.results?.length">{{ testResult.error }}</span>
              <span v-else>Algum destino foi recusado — veja abaixo.</span>
            </div>
          </div>
          <!-- 📣 item 345: um resultado por destino (site + cada caixa do WhatsApp) -->
          <ul v-if="testResult?.results?.length" class="space-y-1 text-xs">
            <li
              v-for="r in testResult.results"
              :key="r.target"
              class="flex items-start gap-1.5 px-3 py-1.5 rounded-lg bg-n-alpha-1 text-n-slate-11"
            >
              <span class="flex-shrink-0">{{ r.skipped ? '⚪' : r.ok ? '✅' : '❌' }}</span>
              <span class="min-w-0">
                <b class="text-n-slate-12">{{ r.target }}</b>
                <template v-if="r.skipped"> — {{ r.note }}</template>
                <template v-else-if="r.ok"> — chegou na Meta</template>
                <template v-else> — {{ r.error || 'a Meta recusou' }}</template>
              </span>
            </li>
          </ul>
        </div>

        <!-- ── Lead Ads: formulários instantâneos ─────────────────── -->
        <div class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5">
          <div class="flex items-center gap-3 mb-1">
            <span class="w-10 h-10 rounded-xl border border-n-weak flex items-center justify-center text-xl flex-shrink-0">📋</span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Formulários de Lead Ads</h3>
              <p class="text-xs text-n-slate-10">Receba as respostas dos formulários instantâneos dos anúncios direto aqui — em tempo real</p>
            </div>
            <span
              class="ml-auto text-xs font-medium px-2.5 py-1 rounded-full"
              :class="leadsConfigured ? 'bg-green-500/10 text-green-700' : 'bg-n-alpha-1 text-n-slate-10'"
            >
              {{ leadsConfigured ? 'Conectado' : 'Não configurado' }}
            </span>
          </div>

          <!-- ID da página -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">ID da página do Facebook <span class="text-red-500">*</span></label>
            <input
              v-model="pageId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="Ex: 123456789012345"
            />
            <p class="text-xs text-n-slate-9 mt-1">Meta Business Suite → Configurações → Páginas (ou na seção "Sobre" da página)</p>
          </div>

          <!-- Token da página -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Token de acesso da página
              <span v-if="metaConfig.page_token_set" class="text-green-600 font-normal ml-1">(já configurado)</span>
              <span v-else class="text-red-500">*</span>
            </label>
            <input
              v-model="pageToken"
              type="password"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              :placeholder="metaConfig.page_token_set ? 'Digite para substituir o token atual' : 'EAAxxxxxx...'"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Token de PÁGINA com as permissões <span class="font-mono">leads_retrieval</span> e <span class="font-mono">pages_manage_ads</span> (gerado no app da Meta)
            </p>
          </div>

          <!-- App secret (opcional) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Chave secreta do app
              <span class="text-n-slate-9 font-normal">(opcional — valida a assinatura do webhook)</span>
              <span v-if="metaConfig.app_secret_set" class="text-green-600 font-normal ml-1">(já configurada)</span>
            </label>
            <input
              v-model="appSecret"
              type="password"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="App Secret do app da Meta"
            />
          </div>

          <!-- Caixa de destino -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Abrir conversa na caixa
              <span class="text-n-slate-9 font-normal">(opcional — cada lead vira uma conversa com as respostas)</span>
            </label>
            <select
              v-model="leadInboxId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
              style="margin-bottom: 0"
            >
              <option value="">Não abrir conversa (só contato + CRM)</option>
              <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">{{ inbox.name }}</option>
            </select>
          </div>

          <!-- Webhook -->
          <div v-if="metaConfig.leadgen_verify_token" class="bg-n-alpha-1 rounded-xl p-4 space-y-2.5">
            <p class="text-xs font-semibold text-n-slate-12">Webhook (cole no app da Meta → Webhooks → objeto "Página" → campo "leadgen")</p>
            <div class="flex items-center gap-2">
              <code class="text-xs font-mono text-n-slate-11 bg-n-solid-1 border border-n-weak rounded px-2 py-1.5 flex-1 truncate">{{ webhookUrl }}</code>
              <button class="text-xs text-n-slate-11 border border-n-weak rounded px-2 py-1.5 hover:bg-n-alpha-1" @click="copyText(webhookUrl)">Copiar</button>
            </div>
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-10 flex-shrink-0">Token de verificação:</span>
              <code class="text-xs font-mono text-n-slate-11 bg-n-solid-1 border border-n-weak rounded px-2 py-1.5 flex-1 truncate">{{ metaConfig.leadgen_verify_token }}</code>
              <button class="text-xs text-n-slate-11 border border-n-weak rounded px-2 py-1.5 hover:bg-n-alpha-1" @click="copyText(metaConfig.leadgen_verify_token)">Copiar</button>
            </div>
          </div>

          <!-- Botões -->
          <div class="flex gap-2 pt-1">
            <button
              class="flex-1 bg-[#1877F2] text-white rounded-lg py-2 text-sm font-medium hover:bg-[#1877F2]/90 disabled:opacity-50 transition-colors"
              :disabled="isSavingLeads || !pageId.trim()"
              @click="saveLeads"
            >
              {{ isSavingLeads ? 'Salvando...' : 'Salvar Lead Ads' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isTestingLeads || !leadsConfigured"
              @click="testLeads"
            >
              <span :class="isTestingLeads ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-plug-zap'" class="text-sm" />
              {{ isTestingLeads ? 'Testando...' : 'Testar conexão' }}
            </button>
            <button
              class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50 transition-colors flex items-center gap-1.5"
              :disabled="isImporting || !leadsConfigured || lastImport?.status === 'running'"
              @click="importLeads"
            >
              <span :class="(isImporting || lastImport?.status === 'running') ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-download'" class="text-sm" />
              {{ lastImport?.status === 'running' ? 'Importando...' : 'Importar leads' }}
            </button>
          </div>

          <!-- Resultado do teste -->
          <div
            v-if="leadsTestResult"
            class="px-3 py-2.5 rounded-lg text-sm space-y-1.5"
            :class="leadsTestResult.success
              ? 'bg-green-500/10 text-green-700 border border-green-500/20'
              : 'bg-red-500/10 text-red-700 border border-red-500/20'"
          >
            <template v-if="leadsTestResult.success">
              <p class="font-medium">✓ Conectado à página {{ leadsTestResult.page_name }}</p>
              <p v-if="!leadsTestResult.forms?.length" class="text-xs">Nenhum formulário instantâneo encontrado nesta página.</p>
              <ul v-else class="text-xs space-y-0.5">
                <li v-for="form in leadsTestResult.forms" :key="form.id">
                  {{ form.name }} — <strong>{{ form.leads_count ?? '?' }}</strong> leads
                  <span v-if="form.status && form.status !== 'ACTIVE'" class="opacity-70">({{ form.status.toLowerCase() }})</span>
                </li>
              </ul>
            </template>
            <span v-else>{{ leadsTestResult.error }}</span>
          </div>

          <!-- Última importação -->
          <div
            v-if="lastImport"
            class="px-3 py-2.5 rounded-lg text-sm border"
            :class="lastImport.status === 'error'
              ? 'bg-red-500/10 text-red-700 border-red-500/20'
              : 'bg-n-alpha-1 text-n-slate-11 border-n-weak'"
          >
            <template v-if="lastImport.status === 'running'">⏳ Importação em andamento...</template>
            <template v-else-if="lastImport.status === 'ok'">
              Última importação: <strong>{{ lastImport.imported }}</strong> leads novos,
              {{ lastImport.duplicates }} já existiam
              <span v-if="lastImport.errors > 0">, {{ lastImport.errors }} com erro</span>
              ({{ lastImport.forms }} formulários)
            </template>
            <template v-else>Importação falhou: {{ lastImport.error }}</template>
          </div>
        </div>

        <!-- Como conectar o Lead Ads -->
        <div class="bg-n-alpha-1 rounded-2xl p-6 space-y-3">
          <h4 class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-lightbulb text-yellow-500" />
            Como conectar os formulários dos anúncios
          </h4>
          <ol class="space-y-2 text-sm text-n-slate-11 list-decimal list-inside">
            <li>No app da Meta (developers.facebook.com), adicione as permissões <strong>leads_retrieval</strong> e <strong>pages_manage_ads</strong> e gere um <strong>token de página</strong>.</li>
            <li>Preencha o ID da página e o token acima e salve — o endereço do webhook aparece no card.</li>
            <li>No app da Meta → <strong>Webhooks</strong> → objeto <strong>Página</strong>: cole o endereço e o token de verificação, e assine o campo <strong>leadgen</strong>.</li>
            <li>Em <strong>Configurações da página → Apps conectados</strong>, confirme que o app está vinculado à página.</li>
            <li>Clique em <strong>Importar leads</strong> para trazer o que já está no Meta (eles guardam os últimos 90 dias).</li>
          </ol>
          <div class="flex items-start gap-2 px-3 py-2.5 bg-yellow-500/8 border border-yellow-400/20 rounded-lg mt-3">
            <span class="i-lucide-shield text-yellow-500 flex-shrink-0 mt-0.5" />
            <p class="text-xs text-n-slate-11">
              Cada resposta vira um <strong>contato</strong> com atribuição do anúncio (conta nos relatórios de Anúncios Meta),
              as respostas ficam no formulário-espelho <strong>"Meta: ..."</strong> em Formulários, e — se você escolher uma caixa —
              o lead abre uma <strong>conversa</strong> pronta para o primeiro contato.
            </p>
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
