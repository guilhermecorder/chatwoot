<script setup>
// 🤖📞 Agente de Ligação (IA) — ElevenLabs (item 169). Sub-página de
// Integrações no mesmo molde de CevicoCalls.vue: formulário ligado a
// settings.voice (crm/getSettings), salvar via crm/updateVoice, "Testar
// conexão" (crm/testVoice), "Sincronizar com a ElevenLabs" (crm/syncVoice,
// mostra o log passo a passo e o erro cru), busca de contas WhatsApp e de
// vozes na ElevenLabs, painel de Estado (crm/voiceState) com as últimas
// ligações da IA. Segredos nunca voltam do backend: só as flags `*_set`.
import { ref, computed, onMounted, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import {
  callIcon,
  formatTalkTime,
  formatPhoneBR,
  shortDateTime,
} from 'dashboard/helper/cevicoCallsFormat';

const store = useStore();
const router = useRouter();
const settings = useMapGetter('crm/getSettings');
const inboxes = useMapGetter('inboxes/getInboxes');
const accountId = useMapGetter('getCurrentAccountId');

// defaults espelhados do contrato (docs/AGENTE_LIGACAO.md §2) — a tela
// precisa abrir bonita mesmo quando settings.voice ainda vem vazio
const DEFAULT_AGENT_NAME = 'Assistente virtual da CEVICO';
const DEFAULT_LLM = 'gemini-2.5-flash';
const DEFAULT_LLM_OPTIONS = [
  'gemini-2.5-flash',
  'gemini-3.5-flash',
  'claude-haiku-4-5',
  'claude-sonnet-4-5',
  'gpt-4.1-mini',
];
const DEFAULT_LANGUAGE_OPTIONS = ['pt-br', 'pt'];
const DEFAULT_TTS_MODEL = 'eleven_flash_v2_5';
const LLM_LABELS = {
  'gemini-2.5-flash': 'Gemini 2.5 Flash — rápido e econômico (padrão)',
  'gemini-3.5-flash': 'Gemini 3.5 Flash — mais novo',
  'claude-haiku-4-5': 'Claude Haiku 4.5 — rápido',
  'claude-sonnet-4-5': 'Claude Sonnet 4.5 — mais esperto, mais caro',
  'gpt-4.1-mini': 'GPT-4.1 mini',
};
const LANGUAGE_LABELS = {
  'pt-br': 'Português (Brasil)',
  pt: 'Português (Portugal)',
};
// chaves literais não podem aparecer dentro de interpolação no template
const wrapToken = t => '{{' + t + '}}';
const NAME_TOKEN = wrapToken('paciente_nome');
const CONTACT_TOKEN = wrapToken('contact.first_name');

const voice = computed(() => settings.value?.voice ?? {});

const blankForm = () => ({
  enabled: false,
  api_key: '', // só vai no payload se digitada
  webhook_secret: '', // idem
  agent_name: DEFAULT_AGENT_NAME,
  whatsapp_phone_number_id: '',
  whatsapp_number: '',
  voice_id: '',
  voice_name: '',
  llm: DEFAULT_LLM,
  language: 'pt-br',
  tts_model: DEFAULT_TTS_MODEL,
  first_message: '',
  transfer_number: '',
  transfer_condition: '',
  handoff_inbox_id: null,
  handoff_template_params: {},
  permission_template: { name: '', language: 'pt_BR' },
  max_minutes: 10, // max_duration_seconds ÷ 60 (mais humano na tela)
  daily_limit: 200,
  hours: { start: '08:00', end: '19:00' },
});

const form = ref(blankForm());
// o script vive fora do form: null no backend = usa o padrão
const promptText = ref('');

const isLoading = ref(true);
const isSaving = ref(false);
const isTesting = ref(false);
const isSyncing = ref(false);
const testResult = ref(null); // { ok, name, tier, error }
const syncResult = ref(null); // { ok, log, error }

// ── modelo de continuidade (template p/ abrir conversa fora das 24 h) ──
// mesmo fluxo dos lembretes de consulta: escolhe a caixa → lista os modelos
// aprovados → escolhe um → preenche as variáveis → vira `template_params`
const handoffTemplates = ref([]);
const handoffTplName = ref('');
const handoffVars = ref({});
const isLoadingHandoffTemplates = ref(false);
const loadHandoffTemplates = async inboxId => {
  if (!inboxId) {
    handoffTemplates.value = [];
    return;
  }
  isLoadingHandoffTemplates.value = true;
  try {
    const data = await store.dispatch('crm/fetchWhatsappTemplates', inboxId);
    handoffTemplates.value = Array.isArray(data) ? data : [];
  } catch {
    handoffTemplates.value = [];
  } finally {
    isLoadingHandoffTemplates.value = false;
  }
};

const fillForm = () => {
  const v = voice.value || {};
  form.value = {
    ...blankForm(),
    enabled: Boolean(v.enabled),
    agent_name: v.agent_name || DEFAULT_AGENT_NAME,
    whatsapp_phone_number_id: v.whatsapp_phone_number_id || '',
    whatsapp_number: v.whatsapp_number || '',
    voice_id: v.voice_id || '',
    voice_name: v.voice_name || '',
    llm: v.llm || DEFAULT_LLM,
    language: v.language || 'pt-br',
    tts_model: v.tts_model || DEFAULT_TTS_MODEL,
    first_message: v.first_message || '',
    transfer_number: v.transfer_number || '',
    transfer_condition: v.transfer_condition || '',
    handoff_inbox_id: v.handoff_inbox_id || null,
    handoff_template_params: v.handoff_template_params || {},
    permission_template: {
      name: v.permission_template?.name || '',
      language: v.permission_template?.language || 'pt_BR',
    },
    max_minutes: Math.max(
      1,
      Math.round(Number(v.max_duration_seconds || 600) / 60)
    ),
    daily_limit: Number(v.daily_limit ?? 200),
    hours: {
      start: v.hours?.start || '08:00',
      end: v.hours?.end || '19:00',
    },
  };
  promptText.value = v.prompt ?? v.default_prompt ?? '';
  // modelo de continuidade já salvo → mostra o nome e as variáveis
  const saved = v.handoff_template_params || {};
  handoffTplName.value = saved.name || '';
  handoffVars.value = { ...(saved.processed_params?.body || {}) };
  if (form.value.handoff_inbox_id) {
    loadHandoffTemplates(form.value.handoff_inbox_id);
  }
};

// ── opções dos selects (do backend, com fallback) ──
const llmOptions = computed(() => {
  const list =
    Array.isArray(voice.value.llm_options) && voice.value.llm_options.length
      ? voice.value.llm_options
      : DEFAULT_LLM_OPTIONS;
  // o modelo salvo pode ter saído da lista — mantém p/ não trocar sem avisar
  return form.value.llm && !list.includes(form.value.llm)
    ? [...list, form.value.llm]
    : list;
});
const languageOptions = computed(() =>
  Array.isArray(voice.value.language_options) &&
  voice.value.language_options.length
    ? voice.value.language_options
    : DEFAULT_LANGUAGE_OPTIONS
);
const llmLabel = key => LLM_LABELS[key] || key;
const languageLabel = key => LANGUAGE_LABELS[key] || key;

// ── script (prompt): null = padrão ──
const defaultPrompt = computed(() => voice.value.default_prompt || '');
const isCustomPrompt = computed(() => {
  const text = promptText.value.trim();
  return Boolean(text) && text !== defaultPrompt.value.trim();
});
const restoreDefaultPrompt = () => {
  promptText.value = defaultPrompt.value;
};

// ── caixa da clínica (só WhatsApp Cloud, como em CevicoCalls.vue) ──
const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(
    i =>
      i.channel_type === 'Channel::Whatsapp' && i.provider === 'whatsapp_cloud'
  )
);

const onHandoffInboxChange = () => {
  handoffTplName.value = '';
  handoffVars.value = {};
  loadHandoffTemplates(form.value.handoff_inbox_id);
};
const handoffTpl = computed(
  () =>
    handoffTemplates.value.find(t => t.name === handoffTplName.value) || null
);
const handoffBody = computed(
  () => handoffTpl.value?.components?.find(c => c.type === 'BODY')?.text || ''
);
const handoffTokens = computed(() => {
  const tokens = new Set();
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(handoffBody.value);
  while (m !== null) {
    tokens.add(m[1]);
    m = re.exec(handoffBody.value);
  }
  return [...tokens];
});
const savedHandoffName = computed(
  () => form.value.handoff_template_params?.name || ''
);
const clearHandoffTemplate = () => {
  handoffTplName.value = '';
  handoffVars.value = {};
  form.value.handoff_template_params = {};
};
// mesma forma usada nas campanhas/lembretes (Crm::SendTemplateService)
const handoffParamsPayload = () => {
  const tpl = handoffTpl.value;
  if (tpl) {
    return {
      name: tpl.name,
      namespace: tpl.namespace ?? '',
      language: tpl.language,
      category: tpl.category,
      processed_params: { body: { ...handoffVars.value } },
    };
  }
  // sem re-seleção: mantém o que já estava salvo (ou vazio)
  return form.value.handoff_template_params || {};
};

// ── contas WhatsApp importadas na ElevenLabs ──
const waAccounts = ref([]);
const isLoadingWa = ref(false);
const waError = ref('');
const waFetched = ref(false);
const fetchWaAccounts = async () => {
  if (isLoadingWa.value) return;
  isLoadingWa.value = true;
  waError.value = '';
  try {
    const result = await store.dispatch('crm/voiceWhatsappAccounts');
    waAccounts.value = Array.isArray(result?.items) ? result.items : [];
    if (result?.error) waError.value = result.error;
    waFetched.value = true;
  } catch (error) {
    waAccounts.value = [];
    waError.value =
      error?.response?.data?.error ||
      'Não consegui falar com a ElevenLabs agora. A chave está salva?';
  } finally {
    isLoadingWa.value = false;
  }
};
const onWaAccountChange = () => {
  const a = waAccounts.value.find(
    x => x.phone_number_id === form.value.whatsapp_phone_number_id
  );
  if (a) form.value.whatsapp_number = a.phone_number || '';
};
const waAccountLabel = a => {
  const parts = [a.phone_number_name || a.business_account_name || 'Conta'];
  if (a.phone_number) parts.push(formatPhoneBR(a.phone_number));
  return parts.join(' · ');
};
const selectedWaAccount = computed(() =>
  waAccounts.value.find(
    x => x.phone_number_id === form.value.whatsapp_phone_number_id
  )
);

// ── vozes ──
const voiceSearch = ref('');
const voices = ref([]);
const isLoadingVoices = ref(false);
const voicesError = ref('');
const voicesFetched = ref(false);
const fetchVoices = async () => {
  if (isLoadingVoices.value) return;
  isLoadingVoices.value = true;
  voicesError.value = '';
  try {
    const result = await store.dispatch('crm/voiceVoices', {
      search: voiceSearch.value.trim(),
    });
    voices.value = Array.isArray(result?.voices) ? result.voices : [];
    if (result?.error) voicesError.value = result.error;
    voicesFetched.value = true;
  } catch (error) {
    voices.value = [];
    voicesError.value =
      error?.response?.data?.error ||
      'Não consegui buscar as vozes agora. A chave está salva?';
  } finally {
    isLoadingVoices.value = false;
  }
};
const pickVoice = v => {
  form.value.voice_id = v.voice_id;
  form.value.voice_name = v.name || '';
};
const voiceLabels = v => {
  const labels = v.labels && typeof v.labels === 'object' ? v.labels : {};
  return Object.values(labels).filter(Boolean).join(' · ');
};

// ── estado (crm/voiceState) ──
const stateData = ref(null); // { state, calls }
const isLoadingState = ref(false);
const stateError = ref('');
const loadState = async () => {
  if (isLoadingState.value) return;
  isLoadingState.value = true;
  stateError.value = '';
  try {
    stateData.value = await store.dispatch('crm/voiceState');
  } catch (error) {
    stateError.value =
      error?.response?.data?.error || 'Não consegui consultar o estado agora.';
  } finally {
    isLoadingState.value = false;
  }
};
const liveState = computed(
  () => stateData.value?.state || voice.value.state || {}
);
const recentCalls = computed(() =>
  Array.isArray(stateData.value?.calls) ? stateData.value.calls : []
);
const lastSyncLog = computed(() =>
  Array.isArray(liveState.value.last_sync_log)
    ? liveState.value.last_sync_log
    : []
);
const showSyncLog = ref(false);
const openConversation = c => {
  if (!c?.conversation_id) return;
  router.push(
    `/app/accounts/${accountId.value}/conversations/${c.conversation_id}`
  );
};
const callContactName = c => c.contact?.name || c.display_name || 'Paciente';
const callContactPhone = c =>
  formatPhoneBR(c.contact?.phone_number || c.wa_id || '');

// ── carga ──
onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('crm/fetchSettings'),
      store.dispatch('inboxes/get'),
    ]);
  } catch {
    // a tela abre mesmo assim, com o que tiver
  }
  fillForm();
  isLoading.value = false;
  loadState();
});
watch(voice, () => {
  if (!isSaving.value && !isSyncing.value) fillForm();
});

// ── payload / salvar ──
const payload = () => {
  const f = form.value;
  const p = {
    enabled: f.enabled,
    agent_name: f.agent_name.trim() || DEFAULT_AGENT_NAME,
    whatsapp_phone_number_id: String(f.whatsapp_phone_number_id || '').trim(),
    whatsapp_number: String(f.whatsapp_number || '').trim(),
    connection: 'whatsapp',
    voice_id: f.voice_id.trim(),
    voice_name: f.voice_name.trim(),
    llm: f.llm,
    language: f.language,
    tts_model: f.tts_model || DEFAULT_TTS_MODEL,
    first_message: f.first_message.trim(),
    prompt: isCustomPrompt.value ? promptText.value.trim() : null,
    transfer_number: f.transfer_number.trim(),
    transfer_condition: f.transfer_condition.trim(),
    handoff_inbox_id: f.handoff_inbox_id ? Number(f.handoff_inbox_id) : null,
    handoff_template_params: handoffParamsPayload(),
    permission_template: {
      name: f.permission_template.name.trim(),
      language: f.permission_template.language.trim() || 'pt_BR',
    },
    max_duration_seconds: Math.max(60, Number(f.max_minutes || 10) * 60),
    daily_limit: Math.max(0, Number(f.daily_limit || 0)),
    hours: { ...f.hours },
  };
  // segredos só viajam quando digitados — o backend nunca os devolve
  if (f.api_key.trim()) p.api_key = f.api_key.trim();
  if (f.webhook_secret.trim()) p.webhook_secret = f.webhook_secret.trim();
  return p;
};

const validate = () => {
  const f = form.value;
  if (f.enabled && !f.handoff_inbox_id) {
    useAlert(
      'Escolha a caixa de WhatsApp da clínica antes de ligar a assistente.'
    );
    return false;
  }
  const transfer = f.transfer_number.trim();
  if (transfer && !/^\+?\d{8,15}$/.test(transfer)) {
    useAlert(
      'O telefone de transferência precisa estar no formato +5511999999999.'
    );
    return false;
  }
  return true;
};

// salva e limpa os campos de segredo (já foram gravados)
const persist = async () => {
  await store.dispatch('crm/updateVoice', payload());
  form.value.api_key = '';
  form.value.webhook_secret = '';
};

const save = async () => {
  if (!validate()) return;
  isSaving.value = true;
  try {
    await persist();
    useAlert('Configurações da assistente virtual salvas!');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || 'Erro ao salvar. Tente novamente.'
    );
  } finally {
    isSaving.value = false;
  }
};

// liga/desliga na hora (salva o formulário junto)
const toggleEnabled = async () => {
  const turningOn = !form.value.enabled;
  if (turningOn && !(voice.value.api_key_set && voice.value.agent_id)) {
    useAlert(
      'Antes de ligar: salve a chave da API e clique em "Sincronizar com a ElevenLabs".'
    );
    return;
  }
  form.value.enabled = turningOn;
  if (!validate()) {
    form.value.enabled = !turningOn;
    return;
  }
  isSaving.value = true;
  try {
    await persist();
    useAlert(
      turningOn
        ? 'Assistente virtual ligada! Ela já atende o número dela.'
        : 'Assistente virtual desligada.'
    );
  } catch (error) {
    form.value.enabled = !turningOn;
    useAlert(error?.response?.data?.error || 'Não consegui mudar o estado.');
  } finally {
    isSaving.value = false;
  }
};

// testa a chave gravada (se acabou de digitar uma nova, salva antes)
const testConnection = async () => {
  if (isTesting.value) return;
  isTesting.value = true;
  testResult.value = null;
  try {
    if (form.value.api_key.trim()) {
      isSaving.value = true;
      await persist();
      isSaving.value = false;
    }
    const result = await store.dispatch('crm/testVoice');
    testResult.value = result || { ok: false, error: 'Sem resposta.' };
  } catch (error) {
    testResult.value = {
      ok: false,
      error:
        error?.response?.data?.error ||
        error?.message ||
        'Erro inesperado ao falar com a ElevenLabs.',
    };
  } finally {
    isSaving.value = false;
    isTesting.value = false;
  }
};

// salva → SyncService (webhook, ferramentas, agente, número) → log humano
const syncWithElevenLabs = async () => {
  if (isSyncing.value || !validate()) return;
  isSyncing.value = true;
  syncResult.value = null;
  try {
    await persist();
    const result = await store.dispatch('crm/syncVoice');
    syncResult.value = result || { ok: false, error: 'Sem resposta.' };
    if (result?.ok) useAlert('Sincronizado com a ElevenLabs!');
    loadState();
  } catch (error) {
    syncResult.value = {
      ok: false,
      log: error?.response?.data?.log || [],
      error:
        error?.response?.data?.error ||
        error?.message ||
        'Erro inesperado ao sincronizar.',
    };
  } finally {
    isSyncing.value = false;
  }
};

// ── utilidades de tela ──
const copy = async (text, label) => {
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
    useAlert(`${label} copiada!`);
  } catch {
    useAlert('Não consegui copiar — selecione o texto e copie manualmente.');
  }
};
const pretty = value => {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
};
const fmtDate = ts =>
  ts
    ? new Date(ts).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';

const statusTone = computed(() => {
  if (voice.value.enabled && voice.value.configured) return 'on';
  if (voice.value.enabled) return 'half';
  return 'off';
});
const statusClass = computed(() => {
  if (statusTone.value === 'on') {
    return 'bg-green-500/8 border-green-500/20 text-green-700';
  }
  if (statusTone.value === 'half') {
    return 'bg-yellow-500/8 border-yellow-400/20 text-yellow-700';
  }
  return 'bg-n-alpha-1 border-n-weak text-n-slate-10';
});
const handoffPlaceholder = computed(() => {
  if (savedHandoffName.value) return `Modelo salvo: ${savedHandoffName.value}`;
  if (isLoadingHandoffTemplates.value) return 'Carregando modelos…';
  return 'Escolha um modelo aprovado…';
});
const canSync = computed(
  () => Boolean(voice.value.api_key_set) || Boolean(form.value.api_key.trim())
);

const urlFields = computed(() => [
  {
    key: 'tools_base_url',
    label: 'Base das ferramentas',
    hint: 'a IA chama /tools/<nome> aqui (buscar paciente, horários, marcar…)',
    value: voice.value.tools_base_url || '',
  },
  {
    key: 'post_call_url',
    label: 'Webhook pós-chamada',
    hint: 'a ElevenLabs avisa aqui quando a ligação termina (transcrição + áudio)',
    value: voice.value.post_call_url || '',
  },
  {
    key: 'initiation_url',
    label: 'Webhook de início',
    hint: 'devolve o nome e a próxima consulta do paciente antes do "alô"',
    value: voice.value.initiation_url || '',
  },
]);

const inputClass =
  'w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand';
const smallBtn =
  'text-xs font-medium px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:text-n-brand hover:border-n-brand/40 disabled:opacity-50 flex items-center gap-1';
const chipOn = 'bg-green-500/10 border-green-500/30 text-green-700';
const chipOff = 'bg-n-alpha-1 border-n-weak text-n-slate-10';
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    loading-message="Carregando a assistente virtual…"
  >
    <template #header>
      <BaseSettingsHeader
        title="Agente de Ligação (IA)"
        description="Uma assistente virtual que atende e faz ligações pelo WhatsApp num número próprio da clínica: consulta a agenda, marca consulta, manda a confirmação por mensagem e deixa o card da chamada na conversa do paciente."
        link-text=""
        feature-name="integrations"
      />
    </template>

    <template #body>
      <div class="max-w-2xl space-y-8">
        <!-- Status -->
        <div
          class="flex items-center gap-3 px-4 py-3 rounded-xl border"
          :class="statusClass"
        >
          <span class="i-lucide-bot text-base flex-shrink-0" />
          <span class="text-sm font-medium flex-1 min-w-0">
            <template v-if="statusTone === 'on'">
              Assistente virtual ligada — atende e faz ligações pelo número dela
              <template v-if="voice.whatsapp_number">
                ({{ formatPhoneBR(voice.whatsapp_number) }})
              </template>
            </template>
            <template v-else-if="statusTone === 'half'">
              Ligada aqui, mas ainda falta a chave ou a sincronização com a
              ElevenLabs
            </template>
            <template v-else>Assistente virtual desligada</template>
          </span>
          <button
            class="text-xs font-bold px-3 py-1.5 rounded-lg text-white disabled:opacity-50 flex items-center gap-1.5 flex-shrink-0"
            :style="{
              background: form.enabled
                ? 'linear-gradient(135deg, #6b7280, #9ca3af)'
                : 'linear-gradient(135deg, #7C3AED, #DB2777)',
            }"
            :disabled="isSaving"
            :title="
              form.enabled
                ? 'Desligar a assistente (ela para de atender)'
                : 'Ligar a assistente no número dela'
            "
            @click="toggleEnabled"
          >
            <span
              :class="form.enabled ? 'i-lucide-power-off' : 'i-lucide-power'"
              class="text-xs"
            />
            {{ form.enabled ? 'Desligar' : 'Ligar' }}
          </button>
        </div>

        <!-- ══ 1 · Conexão ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5"
        >
          <div class="flex items-center gap-3 mb-1">
            <span
              class="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold flex-shrink-0"
              style="background: linear-gradient(135deg, #7c3aed, #db2777)"
            >
              1
            </span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Conexão</h3>
              <p class="text-xs text-n-slate-10">
                A chave da ElevenLabs e as URLs que ela usa para falar com o
                sistema
              </p>
            </div>
          </div>

          <div class="flex flex-wrap gap-1.5">
            <span
              class="text-[11px] px-2 py-0.5 rounded-full border"
              :class="voice.api_key_set ? chipOn : chipOff"
            >
              {{ voice.api_key_set ? 'chave configurada ✓' : 'sem chave' }}
            </span>
            <span
              class="text-[11px] px-2 py-0.5 rounded-full border"
              :class="voice.webhook_secret_set ? chipOn : chipOff"
            >
              {{
                voice.webhook_secret_set
                  ? 'segredo do webhook ✓'
                  : 'webhook ainda não criado'
              }}
            </span>
            <span
              class="text-[11px] px-2 py-0.5 rounded-full border"
              :class="voice.tools_token_set ? chipOn : chipOff"
            >
              {{
                voice.tools_token_set
                  ? 'token das ferramentas ✓'
                  : 'token gerado no 1º salvar'
              }}
            </span>
            <span
              class="text-[11px] px-2 py-0.5 rounded-full border"
              :class="voice.agent_id ? chipOn : chipOff"
              :title="voice.agent_id || ''"
            >
              {{
                voice.agent_id
                  ? 'agente criado na ElevenLabs ✓'
                  : 'agente ainda não criado'
              }}
            </span>
          </div>

          <!-- chave -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Chave da API (xi-api-key)
              <span v-if="!voice.api_key_set" class="text-red-500">*</span>
            </label>
            <div class="flex items-center gap-2">
              <input
                v-model="form.api_key"
                type="password"
                autocomplete="new-password"
                :class="inputClass"
                :placeholder="
                  voice.api_key_set
                    ? 'Chave já salva — cole outra só para trocar'
                    : 'Cole a chave da ElevenLabs'
                "
              />
              <button
                :class="smallBtn"
                class="flex-shrink-0"
                :disabled="isTesting || !canSync"
                @click="testConnection"
              >
                <span
                  :class="
                    isTesting
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-plug-zap'
                  "
                  class="text-xs"
                />
                {{ isTesting ? 'Testando…' : 'Testar conexão' }}
              </button>
            </div>
            <p class="text-xs text-n-slate-9 mt-1">
              Em ElevenLabs → perfil → API keys. Precisa de um plano com Agents.
              A chave fica guardada no servidor e nunca volta para a tela.
            </p>
          </div>

          <div
            v-if="testResult"
            class="rounded-lg border px-3 py-2.5 text-sm space-y-1"
            :class="
              testResult.ok
                ? 'bg-green-500/10 text-green-700 border-green-500/20'
                : 'bg-red-500/10 text-red-700 border-red-500/20'
            "
          >
            <p class="flex items-start gap-2">
              <span
                class="text-base flex-shrink-0 mt-0.5"
                :class="
                  testResult.ok
                    ? 'i-lucide-check-circle'
                    : 'i-lucide-alert-circle'
                "
              />
              <span>
                <template v-if="testResult.ok">
                  Conectado
                  <template v-if="testResult.name">
                    como <strong>{{ testResult.name }}</strong>
                  </template>
                  <template v-if="testResult.tier">
                    · plano {{ testResult.tier }}
                  </template>
                </template>
                <template v-else>
                  {{ testResult.error || 'A ElevenLabs não aceitou a chave.' }}
                </template>
              </span>
            </p>
            <div
              v-if="!testResult.ok && testResult.error"
              class="text-[11px] font-mono whitespace-pre-wrap break-words rounded-md bg-black/5 dark:bg-white/5 p-2 text-n-slate-12 max-h-40 overflow-auto"
            >
              {{ pretty(testResult.error) }}
            </div>
          </div>

          <!-- segredo do webhook -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Segredo do webhook
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </label>
            <input
              v-model="form.webhook_secret"
              type="password"
              autocomplete="new-password"
              :class="inputClass"
              :placeholder="
                voice.webhook_secret_set
                  ? 'Segredo já salvo — cole outro só para trocar'
                  : 'Deixe vazio: o Sincronizar cria o webhook e guarda o segredo'
              "
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Só preencha se você criou o webhook à mão no painel da ElevenLabs.
              Ele confere a assinatura de cada aviso de fim de ligação.
            </p>
          </div>

          <!-- URLs prontas -->
          <div class="space-y-2">
            <p class="text-xs font-medium text-n-slate-11">
              URLs deste sistema
              <span class="text-n-slate-9 font-normal">
                (o Sincronizar já cadastra; ficam aqui para conferir ou colar à
                mão)
              </span>
            </p>
            <div
              v-for="u in urlFields"
              :key="u.key"
              class="rounded-lg bg-n-alpha-1 px-3 py-2"
            >
              <p class="text-[11px] text-n-slate-9">{{ u.label }}</p>
              <div class="flex items-center gap-2">
                <input
                  :value="u.value || 'aparece depois do primeiro salvar'"
                  readonly
                  class="flex-1 min-w-0 bg-transparent text-xs font-mono text-n-slate-12 focus:outline-none"
                />
                <button
                  :class="smallBtn"
                  class="flex-shrink-0"
                  :disabled="!u.value"
                  title="Copiar"
                  @click="copy(u.value, u.label)"
                >
                  <span class="i-lucide-copy text-xs" />
                  Copiar
                </button>
              </div>
              <p class="text-[11px] text-n-slate-9 mt-0.5">{{ u.hint }}</p>
            </div>
          </div>
        </div>

        <!-- ══ 2 · Número do WhatsApp ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5"
        >
          <div class="flex items-center gap-3 mb-1">
            <span
              class="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold flex-shrink-0"
              style="background: linear-gradient(135deg, #128c7e, #25d366)"
            >
              2
            </span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">
                Número do WhatsApp da assistente
              </h3>
              <p class="text-xs text-n-slate-10">
                O número próprio que a IA atende — importado na ElevenLabs
              </p>
            </div>
          </div>

          <div
            class="flex items-start gap-2 px-3 py-2.5 bg-yellow-500/8 border border-yellow-400/20 rounded-lg"
          >
            <span class="i-lucide-info text-yellow-500 flex-shrink-0 mt-0.5" />
            <p class="text-xs text-n-slate-11">
              Antes, no painel da ElevenLabs:
              <strong>WhatsApp → Import account</strong> → autorização da Meta →
              escolha o número → <strong>desligue "Enable messaging"</strong>
              (a IA só cuida de ligações; as mensagens saem pela caixa da
              clínica, seção 4). No WhatsApp Manager → número →
              <strong>Call settings</strong>: ligue as chamadas.
            </p>
          </div>

          <div>
            <div class="flex items-center gap-2 mb-1.5">
              <label class="text-xs font-medium text-n-slate-11">
                Conta importada
              </label>
              <button
                :class="smallBtn"
                class="ml-auto"
                :disabled="isLoadingWa || !voice.api_key_set"
                :title="
                  voice.api_key_set
                    ? 'Lista as contas WhatsApp importadas na ElevenLabs'
                    : 'Salve a chave da API primeiro'
                "
                @click="fetchWaAccounts"
              >
                <span
                  :class="
                    isLoadingWa
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-search'
                  "
                  class="text-xs"
                />
                Buscar contas na ElevenLabs
              </button>
            </div>
            <select
              v-if="waAccounts.length"
              v-model="form.whatsapp_phone_number_id"
              :class="inputClass"
              @change="onWaAccountChange"
            >
              <option value="">Escolha a conta…</option>
              <option
                v-for="a in waAccounts"
                :key="a.phone_number_id"
                :value="a.phone_number_id"
              >
                {{ waAccountLabel(a) }}
              </option>
            </select>
            <div v-else class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <input
                v-model="form.whatsapp_phone_number_id"
                :class="inputClass"
                placeholder="ID da conta na ElevenLabs"
              />
              <input
                v-model="form.whatsapp_number"
                :class="inputClass"
                placeholder="Número (ex.: +5511999999999)"
              />
            </div>
            <p v-if="waError" class="text-xs text-red-600 mt-1">
              {{ waError }}
            </p>
            <p
              v-else-if="waFetched && !waAccounts.length"
              class="text-xs text-n-slate-9 mt-1"
            >
              Nenhuma conta importada ainda — faça o "Import account" no painel
              da ElevenLabs e busque de novo.
            </p>
            <p
              v-else-if="!waAccounts.length"
              class="text-xs text-n-slate-9 mt-1"
            >
              Clique em "Buscar contas" para escolher da lista, ou cole o ID e o
              número à mão.
            </p>
            <div
              v-if="selectedWaAccount"
              class="mt-2 text-xs text-n-slate-11 rounded-lg bg-n-alpha-1 px-3 py-2 space-y-0.5"
            >
              <p>
                <span class="text-n-slate-9">Número:</span>
                {{ formatPhoneBR(selectedWaAccount.phone_number) || '—' }}
                <template v-if="selectedWaAccount.business_account_name">
                  · {{ selectedWaAccount.business_account_name }}
                </template>
              </p>
              <p>
                <span class="text-n-slate-9">Agente ligado a ele:</span>
                {{ selectedWaAccount.assigned_agent_name || 'nenhum ainda' }}
              </p>
              <p
                v-if="selectedWaAccount.enable_messaging"
                class="text-yellow-700"
              >
                ⚠ "Enable messaging" está ligado — o Sincronizar desliga para
                você.
              </p>
            </div>
            <p
              v-else-if="form.whatsapp_number"
              class="text-xs text-n-slate-9 mt-1"
            >
              Número salvo: {{ formatPhoneBR(form.whatsapp_number) }}
            </p>
          </div>
        </div>

        <!-- ══ 3 · Persona e voz ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5"
        >
          <div class="flex items-center gap-3 mb-1">
            <span
              class="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold flex-shrink-0"
              style="background: linear-gradient(135deg, #9d174d, #db2777)"
            >
              3
            </span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">
                Persona e voz
              </h3>
              <p class="text-xs text-n-slate-10">
                Como a assistente se apresenta, fala e conduz a ligação
              </p>
            </div>
          </div>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Nome do agente
            </label>
            <input
              v-model="form.agent_name"
              :class="inputClass"
              :placeholder="DEFAULT_AGENT_NAME"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Aparece no painel da ElevenLabs. Na ligação ela sempre se
              apresenta como assistente virtual.
            </p>
          </div>

          <!-- voz -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Voz
            </label>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <input
                v-model="form.voice_id"
                :class="inputClass"
                placeholder="ID da voz (voice_id)"
              />
              <input
                v-model="form.voice_name"
                :class="inputClass"
                placeholder="Nome da voz (só para lembrar)"
              />
            </div>
            <div class="flex items-center gap-2 mt-2">
              <input
                v-model="voiceSearch"
                :class="inputClass"
                placeholder="Buscar voz em português (ex.: feminina, jovem…)"
                @keydown.enter.prevent="fetchVoices"
              />
              <button
                :class="smallBtn"
                class="flex-shrink-0"
                :disabled="isLoadingVoices || !voice.api_key_set"
                :title="
                  voice.api_key_set
                    ? 'Busca na biblioteca da ElevenLabs'
                    : 'Salve a chave da API primeiro'
                "
                @click="fetchVoices"
              >
                <span
                  :class="
                    isLoadingVoices
                      ? 'i-lucide-loader-2 animate-spin'
                      : 'i-lucide-audio-lines'
                  "
                  class="text-xs"
                />
                Buscar vozes
              </button>
            </div>
            <p v-if="voicesError" class="text-xs text-red-600 mt-1">
              {{ voicesError }}
            </p>
            <p
              v-else-if="voicesFetched && !voices.length"
              class="text-xs text-n-slate-9 mt-1"
            >
              Nenhuma voz encontrada com esse termo.
            </p>
            <div
              v-if="voices.length"
              class="mt-2 max-h-56 overflow-y-auto rounded-lg border border-n-weak divide-y divide-n-weak"
            >
              <button
                v-for="v in voices"
                :key="v.voice_id"
                type="button"
                class="w-full text-left px-3 py-2 flex items-center gap-2 hover:bg-n-alpha-1 transition-colors"
                :class="form.voice_id === v.voice_id ? 'bg-n-brand/10' : ''"
                @click="pickVoice(v)"
              >
                <span
                  class="text-sm flex-shrink-0"
                  :class="
                    form.voice_id === v.voice_id
                      ? 'i-lucide-check-circle-2 text-n-brand'
                      : 'i-lucide-mic text-n-slate-9'
                  "
                />
                <span class="min-w-0 flex-1">
                  <span class="text-xs font-medium text-n-slate-12 block">
                    {{ v.name }}
                  </span>
                  <span
                    v-if="voiceLabels(v)"
                    class="text-[11px] text-n-slate-9 block truncate"
                  >
                    {{ voiceLabels(v) }}
                  </span>
                </span>
                <span
                  class="text-[10px] font-mono text-n-slate-9 flex-shrink-0"
                >
                  {{ v.voice_id }}
                </span>
              </button>
            </div>
          </div>

          <!-- modelo + idioma -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Cérebro (modelo de linguagem)
              </label>
              <select v-model="form.llm" :class="inputClass">
                <option v-for="m in llmOptions" :key="m" :value="m">
                  {{ llmLabel(m) }}
                </option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Idioma
              </label>
              <select v-model="form.language" :class="inputClass">
                <option v-for="l in languageOptions" :key="l" :value="l">
                  {{ languageLabel(l) }}
                </option>
              </select>
            </div>
          </div>

          <!-- primeira frase -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Primeira frase
            </label>
            <textarea
              v-model="form.first_message"
              rows="2"
              :class="inputClass"
              placeholder="Vazio = usa a frase padrão (ela se apresenta como assistente virtual da CEVICO e pergunta como pode ajudar)"
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Pode usar
              <code class="bg-n-alpha-2 px-1 rounded">{{ NAME_TOKEN }}</code>
              — quando o número já é conhecido, ela chama pelo nome.
            </p>
          </div>

          <!-- script -->
          <div>
            <div class="flex items-center gap-2 mb-1.5">
              <label class="text-xs font-medium text-n-slate-11">
                Script da conversa
              </label>
              <span
                class="text-[11px] px-2 py-0.5 rounded-full border"
                :class="
                  isCustomPrompt
                    ? 'bg-purple-500/10 border-purple-500/30 text-purple-700'
                    : chipOff
                "
              >
                {{ isCustomPrompt ? 'personalizado' : 'usando o padrão' }}
              </span>
              <button
                :class="smallBtn"
                class="ml-auto"
                :disabled="!isCustomPrompt || !defaultPrompt"
                @click="restoreDefaultPrompt"
              >
                <span class="i-lucide-rotate-ccw text-xs" />
                Restaurar padrão
              </button>
            </div>
            <textarea
              v-model="promptText"
              rows="10"
              :class="inputClass"
              class="font-mono text-xs leading-relaxed"
              placeholder="O script padrão aparece aqui depois do primeiro carregamento. Edite à vontade — 'Restaurar padrão' volta ao original."
            />
            <p class="text-xs text-n-slate-9 mt-1">
              Regras de voz (frases curtas, números por extenso, no máximo 2
              horários por vez), o fluxo da ligação e quando transferir. A
              tabela de preços e as unidades entram sozinhas.
            </p>
          </div>

          <!-- transferência -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Transferir para
                <span class="text-n-slate-9 font-normal">(opcional)</span>
              </label>
              <input
                v-model="form.transfer_number"
                :class="inputClass"
                placeholder="+5511999999999"
              />
              <p class="text-xs text-n-slate-9 mt-1">
                Vazio = sem transferência: ela anota o recado e manda o
                WhatsApp.
              </p>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Quando transferir
              </label>
              <textarea
                v-model="form.transfer_condition"
                rows="2"
                :class="inputClass"
                placeholder="Ex.: o paciente pede para falar com uma pessoa, relata dor ou urgência, ou o assunto sai da agenda"
              />
            </div>
          </div>
        </div>

        <!-- ══ 4 · WhatsApp da clínica ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5"
        >
          <div class="flex items-center gap-3 mb-1">
            <span
              class="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold flex-shrink-0"
              style="background: linear-gradient(135deg, #047857, #34d399)"
            >
              4
            </span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">
                WhatsApp da clínica
              </h3>
              <p class="text-xs text-n-slate-10">
                Por onde a assistente manda mensagens e onde o card da ligação
                aparece
              </p>
            </div>
          </div>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Caixa de WhatsApp <span class="text-red-500">*</span>
            </label>
            <select
              v-model="form.handoff_inbox_id"
              :class="inputClass"
              @change="onHandoffInboxChange"
            >
              <option :value="null">Escolha a caixa…</option>
              <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">
                {{ i.name
                }}<template v-if="i.phone_number">
                  · {{ i.phone_number }}
                </template>
              </option>
            </select>
            <p class="text-xs text-n-slate-9 mt-1">
              Só caixas do WhatsApp Cloud (API oficial da Meta). É a caixa onde
              o time já atende — a confirmação da consulta e o card da ligação
              caem aqui.
              <template v-if="!whatsappInboxes.length">
                Nenhuma encontrada nesta conta.
              </template>
            </p>
          </div>

          <!-- modelo de continuidade -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Modelo de continuidade
              <span class="text-n-slate-9 font-normal">(opcional)</span>
            </label>
            <p class="text-xs text-n-slate-9 mb-2">
              Quando o paciente não trocou mensagem nas últimas 24 h, a Meta só
              deixa abrir a conversa com um modelo aprovado. Sem modelo, ela só
              manda texto livre quando a janela está aberta.
            </p>
            <div class="flex items-center gap-2">
              <select
                v-model="handoffTplName"
                :class="inputClass"
                :disabled="!form.handoff_inbox_id || isLoadingHandoffTemplates"
              >
                <option value="">{{ handoffPlaceholder }}</option>
                <option
                  v-for="t in handoffTemplates"
                  :key="`${t.name}-${t.language}`"
                  :value="t.name"
                >
                  {{ t.name }} ({{ t.language }})
                </option>
              </select>
              <button
                v-if="savedHandoffName || handoffTplName"
                :class="smallBtn"
                class="flex-shrink-0"
                title="Ficar sem modelo (só texto livre)"
                @click="clearHandoffTemplate"
              >
                <span class="i-lucide-x text-xs" />
                Remover
              </button>
            </div>
            <template v-if="handoffTpl">
              <p
                class="mt-2 text-[11px] text-n-slate-10 whitespace-pre-wrap bg-n-alpha-1 rounded-lg px-2.5 py-1.5"
              >
                {{ handoffBody }}
              </p>
              <div
                v-if="handoffTokens.length"
                class="mt-1.5 grid grid-cols-1 sm:grid-cols-2 gap-1.5"
              >
                <input
                  v-for="token in handoffTokens"
                  :key="`hv-${token}`"
                  v-model="handoffVars[token]"
                  class="text-xs border border-n-weak rounded-lg px-2 py-1.5 bg-n-solid-1 font-mono text-n-slate-12 focus:outline-none focus:border-n-brand"
                  :placeholder="`Variável ${wrapToken(token)} — ex.: ${CONTACT_TOKEN}`"
                />
              </div>
              <p class="mt-1 text-[10px] text-n-slate-9">
                <code>{{ CONTACT_TOKEN }}</code> vira o nome do paciente na hora
                do envio.
              </p>
            </template>
          </div>

          <!-- template de permissão -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Modelo de permissão para ligar
              <span class="text-n-slate-9 font-normal">
                (obrigatório para as campanhas)
              </span>
            </label>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <input
                v-model="form.permission_template.name"
                :class="inputClass"
                placeholder="Nome do modelo (ex.: pedido_ligacao)"
              />
              <input
                v-model="form.permission_template.language"
                :class="inputClass"
                placeholder="Idioma (ex.: pt_BR)"
              />
            </div>
            <p class="text-xs text-n-slate-9 mt-1">
              Um modelo aprovado pela Meta com o botão de
              <strong>permissão de ligação</strong> (call_permission_request).
              Nas campanhas, a ElevenLabs manda esse pedido e liga quando o
              paciente aceita.
            </p>
          </div>
        </div>

        <!-- ══ 5 · Limites ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-5"
        >
          <div class="flex items-center gap-3 mb-1">
            <span
              class="w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold flex-shrink-0"
              style="background: linear-gradient(135deg, #d97706, #f59e0b)"
            >
              5
            </span>
            <div>
              <h3 class="text-sm font-semibold text-n-slate-12">Limites</h3>
              <p class="text-xs text-n-slate-10">
                Horário das campanhas, duração e quantidade por dia
              </p>
            </div>
          </div>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Horário em que as campanhas podem ligar
            </label>
            <div class="flex items-center gap-2">
              <input
                v-model="form.hours.start"
                type="time"
                :class="inputClass"
                style="width: 8rem"
              />
              <span class="text-xs text-n-slate-9"> até </span>
              <input
                v-model="form.hours.end"
                type="time"
                :class="inputClass"
                style="width: 8rem"
              />
            </div>
            <p class="text-xs text-n-slate-9 mt-1">
              Ligações recebidas ela atende a qualquer hora.
            </p>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Duração máxima de uma ligação
              </label>
              <div class="flex items-center gap-2">
                <input
                  v-model.number="form.max_minutes"
                  type="number"
                  min="1"
                  max="60"
                  :class="inputClass"
                  style="width: 7rem"
                />
                <span class="text-xs text-n-slate-9">minutos</span>
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Teto de ligações por dia
              </label>
              <div class="flex items-center gap-2">
                <input
                  v-model.number="form.daily_limit"
                  type="number"
                  min="0"
                  :class="inputClass"
                  style="width: 7rem"
                />
                <span class="text-xs text-n-slate-9">
                  ligações (recebidas + feitas)
                </span>
              </div>
            </div>
          </div>
        </div>

        <!-- ══ Barra de ações ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-4"
        >
          <div class="flex items-center gap-3 flex-wrap">
            <button
              class="px-4 py-2 rounded-lg text-sm font-semibold text-white bg-n-brand hover:opacity-90 disabled:opacity-50"
              :disabled="isSaving || isSyncing"
              @click="save"
            >
              {{ isSaving ? 'Salvando…' : 'Salvar' }}
            </button>
            <button
              class="px-4 py-2 rounded-lg text-sm font-semibold text-white disabled:opacity-50 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #7c3aed, #db2777)"
              :disabled="isSyncing || isSaving || !canSync"
              title="Cria/atualiza o webhook, as 6 ferramentas e o agente na ElevenLabs, e liga o número a ele"
              @click="syncWithElevenLabs"
            >
              <span
                :class="
                  isSyncing
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="text-sm"
              />
              {{
                isSyncing ? 'Sincronizando…' : 'Sincronizar com a ElevenLabs'
              }}
            </button>
            <div
              class="ml-auto flex items-center gap-2 select-none"
              title="Ligar/desligar salva na hora"
            >
              <span class="text-xs text-n-slate-11">
                {{ form.enabled ? 'Ligada' : 'Desligada' }}
              </span>
              <button
                type="button"
                class="w-10 h-6 rounded-full transition-colors relative flex-shrink-0 disabled:opacity-50"
                :class="form.enabled ? 'bg-green-500' : 'bg-n-slate-6'"
                :disabled="isSaving || isSyncing"
                @click="toggleEnabled"
              >
                <span
                  class="absolute top-1 w-4 h-4 rounded-full bg-white transition-all"
                  :class="form.enabled ? 'left-5' : 'left-1'"
                />
              </button>
            </div>
          </div>

          <!-- Resultado da sincronização (log + erro cru) -->
          <div
            v-if="syncResult"
            class="rounded-lg border px-3 py-2.5 text-sm space-y-2"
            :class="
              syncResult.ok
                ? 'bg-green-500/10 text-green-700 border-green-500/20'
                : 'bg-red-500/10 text-red-700 border-red-500/20'
            "
          >
            <p class="flex items-start gap-2">
              <span
                class="text-base flex-shrink-0 mt-0.5"
                :class="
                  syncResult.ok
                    ? 'i-lucide-check-circle'
                    : 'i-lucide-alert-circle'
                "
              />
              <span>
                <template v-if="syncResult.ok">
                  Tudo certo na ElevenLabs.
                </template>
                <template v-else>
                  {{ syncResult.error || 'A sincronização parou no meio.' }}
                </template>
              </span>
            </p>
            <ol
              v-if="Array.isArray(syncResult.log) && syncResult.log.length"
              class="text-xs space-y-0.5 list-decimal list-inside text-n-slate-12"
            >
              <li v-for="(line, i) in syncResult.log" :key="i">{{ line }}</li>
            </ol>
            <div
              v-if="!syncResult.ok && syncResult.error"
              class="text-[11px] font-mono whitespace-pre-wrap break-words rounded-md bg-black/5 dark:bg-white/5 p-2 text-n-slate-12 max-h-64 overflow-auto"
            >
              {{ pretty(syncResult.error) }}
            </div>
          </div>
        </div>

        <!-- ══ Estado ══ -->
        <div
          class="bg-n-solid-2 rounded-2xl border border-n-weak p-6 space-y-3"
        >
          <div class="flex items-center gap-2">
            <h3
              class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
            >
              <span class="i-lucide-radio text-base text-n-slate-10" />
              Estado
            </h3>
            <button
              :class="smallBtn"
              class="ml-auto"
              :disabled="isLoadingState"
              @click="loadState"
            >
              <span
                :class="
                  isLoadingState
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-refresh-cw'
                "
                class="text-xs"
              />
              Consultar agora
            </button>
          </div>
          <p v-if="stateError" class="text-xs text-red-600">
            {{ stateError }}
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Última sincronização</p>
              <p class="font-semibold text-n-slate-12">
                {{ fmtDate(liveState.synced_at) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Webhook criado em</p>
              <p class="font-semibold text-n-slate-12">
                {{ fmtDate(liveState.webhook_created_at) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Número ligado ao agente em</p>
              <p class="font-semibold text-n-slate-12">
                {{ fmtDate(liveState.whatsapp_assigned_at) }}
              </p>
            </div>
            <div class="rounded-lg bg-n-alpha-1 px-3 py-2">
              <p class="text-n-slate-9">Última ligação da IA</p>
              <p class="font-semibold text-n-slate-12">
                {{ fmtDate(liveState.last_call_at) }}
              </p>
            </div>
          </div>
          <p
            v-if="liveState.last_error"
            class="text-xs text-red-600 rounded-lg bg-red-500/10 px-3 py-2 break-words"
          >
            Último erro: {{ liveState.last_error }}
          </p>
          <div v-if="lastSyncLog.length">
            <button
              class="text-[11px] font-semibold text-n-brand hover:underline flex items-center gap-1"
              @click="showSyncLog = !showSyncLog"
            >
              <span
                :class="
                  showSyncLog ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
                "
                class="text-xs"
              />
              {{ showSyncLog ? 'Esconder' : 'Ver' }} o log da última
              sincronização
            </button>
            <ol
              v-if="showSyncLog"
              class="mt-1.5 text-[11px] space-y-0.5 list-decimal list-inside text-n-slate-11 rounded-lg bg-n-alpha-1 px-3 py-2"
            >
              <li v-for="(line, i) in lastSyncLog" :key="i">{{ line }}</li>
            </ol>
          </div>

          <!-- últimas ligações da IA -->
          <div class="pt-1">
            <p class="text-xs font-medium text-n-slate-11 mb-1.5">
              Últimas ligações da assistente
            </p>
            <p v-if="!recentCalls.length" class="text-xs text-n-slate-9 py-1">
              Nenhuma ligação da IA ainda.
            </p>
            <div v-else class="space-y-1">
              <div
                v-for="c in recentCalls"
                :key="c.id"
                class="rounded-lg bg-n-alpha-1 px-3 py-2 flex items-center gap-2 min-w-0"
              >
                <span
                  :class="[callIcon(c).icon, callIcon(c).tone]"
                  class="text-sm flex-shrink-0"
                />
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-medium text-n-slate-12 truncate">
                    {{ callContactName(c) }}
                    <span class="text-n-slate-9 font-normal">
                      {{ callContactPhone(c) }}
                    </span>
                  </p>
                  <p class="text-[11px] text-n-slate-10 truncate">
                    {{ shortDateTime(c.started_at) }}
                    <template v-if="Number(c.duration)">
                      · {{ formatTalkTime(c.duration) }}
                    </template>
                    <template v-if="c.summary"> · {{ c.summary }}</template>
                  </p>
                </div>
                <span
                  v-if="c.outcome_label || c.outcome"
                  class="text-[10px] px-2 py-0.5 rounded-full bg-purple-500/10 text-purple-700 border border-purple-500/20 flex-shrink-0"
                >
                  {{ c.outcome_label || c.outcome }}
                </span>
                <button
                  v-if="c.conversation_id"
                  :class="smallBtn"
                  class="flex-shrink-0"
                  title="Abrir a conversa"
                  @click="openConversation(c)"
                >
                  Conversa →
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Como usar -->
        <div class="bg-n-alpha-1 rounded-2xl p-6 space-y-3">
          <h4
            class="text-sm font-semibold text-n-slate-12 flex items-center gap-2"
          >
            <span class="i-lucide-lightbulb text-yellow-500" />
            Como usar
          </h4>
          <ol
            class="space-y-2 text-sm text-n-slate-11 list-decimal list-inside"
          >
            <li>
              Tenha uma conta na <strong>ElevenLabs</strong> com o plano de
              Agents, cole a <strong>chave da API</strong> na seção 1 e clique
              em <strong>Testar conexão</strong>.
            </li>
            <li>
              Crie um <strong>número novo</strong> no WhatsApp Manager da
              clínica (não pode estar no app WhatsApp Business nem em outro
              provedor). Na ElevenLabs: WhatsApp →
              <strong>Import account</strong> → autorize na Meta → escolha o
              número → desligue "Enable messaging". No WhatsApp Manager → número
              → <strong>Call settings</strong>: ligue as chamadas.
            </li>
            <li>
              Peça à Meta a aprovação de um
              <strong>modelo com o pedido de permissão de ligação</strong>
              (call_permission_request) e informe o nome e o idioma na seção 4 —
              é ele que libera as campanhas.
            </li>
            <li>
              O sistema precisa estar no ar com endereço público — as URLs da
              seção 1 são as que a ElevenLabs vai chamar.
            </li>
            <li>
              <strong>Salvar</strong> →
              <strong>Sincronizar com a ElevenLabs</strong> (cria o webhook, as
              ferramentas e o agente, e liga o número a ele) →
              <strong>Ligar</strong>. Pronto: ela atende o número dela e as
              campanhas em CRM → Campanhas → Ligações passam a discar.
            </li>
          </ol>
          <div
            class="flex items-start gap-2 px-3 py-2.5 bg-yellow-500/8 border border-yellow-400/20 rounded-lg mt-3"
          >
            <span
              class="i-lucide-shield text-yellow-500 flex-shrink-0 mt-0.5"
            />
            <p class="text-xs text-n-slate-11">
              As ligações no navegador dos atendentes (Integrações → Ligações
              (WhatsApp)) continuam como estão — a assistente usa um número
              separado.
            </p>
          </div>
        </div>
      </div>
    </template>
  </SettingsLayout>
</template>
