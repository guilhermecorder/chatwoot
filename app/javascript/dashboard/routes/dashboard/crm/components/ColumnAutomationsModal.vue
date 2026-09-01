<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import {
  inboxGradientFor,
  inboxSolidFor,
  ALL_INBOXES_GRADIENT,
} from 'dashboard/helper/cevicoInboxColors.js';

const props = defineProps({
  stage:              { type: Object, required: true },
  pipelineId:         { type: Number, required: true },
  allStages:          { type: Array, default: () => [] },
  initialAutomation:  { type: Object, default: null },  // null = criar, objeto = editar
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const isSaving     = ref(false);
const n8nWorkflows = useMapGetter('crm/getN8nWorkflows');

// formulários ativos para a ação "Enviar formulário"
const availableForms = ref([]);
onMounted(async () => {
  try {
    const { data } = await CrmAPI.getForms();
    availableForms.value = data.filter(f => f.active);
  } catch { /* sem permissão ou sem formulários — o seletor fica vazio */ }
});
const agents       = useMapGetter('agents/getAgents');
const accountLabels = useMapGetter('labels/getLabels');
const hasN8nWorkflows = computed(() => n8nWorkflows.value?.length > 0);

// Carrega settings, agentes e etiquetas ao abrir
store.dispatch('crm/fetchSettings').catch(() => {});
onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
  // 'labels/fetch' não existe no store (erro no console toda vez que o
  // modal abria e etiquetas vazias nunca carregavam) — a ação certa é get
  if (!accountLabels.value.length) store.dispatch('labels/get').catch(() => {});
  if (!(accountInboxes.value || []).length) {
    store.dispatch('inboxes/get').catch(() => {});
  }
});

// condição "caixa de chegada do lead" (missão 03/08): pílulas coloridas
// multi-seleção — a automação só dispara para leads cuja PRIMEIRA conversa
// foi numa das caixas escolhidas (ex.: evento Google só da caixa GOOGLE)
const accountInboxes = useMapGetter('inboxes/getInboxes');
const conditionInboxes = computed(() =>
  [...(accountInboxes.value || [])].sort((a, b) => a.id - b.id)
);
const condInboxGrad = id => inboxGradientFor(accountInboxes.value || [], id);
const condInboxDot = id => inboxSolidFor(accountInboxes.value || [], id);
const toggleConditionInbox = id => {
  const list = [...(form.value.action_config.inbox_ids || [])];
  if (!id) {
    form.value.action_config.inbox_ids = [];
    return;
  }
  const idx = list.indexOf(id);
  if (idx >= 0) list.splice(idx, 1);
  else list.push(id);
  form.value.action_config.inbox_ids = list;
};
const conditionInboxSet = computed(
  () => new Set(form.value.action_config.inbox_ids || [])
);

const isEditing = computed(() => !!props.initialAutomation);

const TRIGGERS = [
  { value: 'card_entered',    label: 'Card entrou nesta coluna',     icon: 'i-lucide-log-in' },
  { value: 'card_left',       label: 'Card saiu desta coluna',       icon: 'i-lucide-log-out' },
  { value: 'card_stalled',    label: 'Card parado por X tempo',      icon: 'i-lucide-clock' },
  { value: 'label_added',     label: 'Etiqueta adicionada',          icon: 'i-lucide-tag' },
  { value: 'label_removed',   label: 'Etiqueta removida',            icon: 'i-lucide-tag' },
  { value: 'message_created', label: 'Mensagem criada na conversa',  icon: 'i-lucide-message-circle' },
  { value: 'value_added',     label: 'Valor adicionado no card',     icon: 'i-lucide-circle-dollar-sign' },
];

const DELAY_PRESETS = [
  { value: 0,    label: 'Imediatamente' },
  { value: 60,   label: 'Após 1 hora' },
  { value: 180,  label: 'Após 3 horas' },
  { value: 1440, label: 'Após 24 horas' },
  { value: 4320, label: 'Após 3 dias' },
  { value: -1,   label: 'Personalizado' },
];

// "Adicionar agente de IA" agrupa as ações de IA num botão só — o agente
// específico é escolhido num seletor (por baixo continua sendo
// ai_analyze / schedule_appointment, sem mudança no backend)
const AI_ACTION_TYPES = ['ai_analyze', 'schedule_appointment', 'closing_extract', 'nps_score'];

const ACTIONS = [
  { value: 'webhook',              label: 'Disparar webhook',        icon: 'i-lucide-globe' },
  { value: 'n8n_flow',             label: 'Acionar fluxo n8n',       icon: 'i-lucide-workflow' },
  { value: 'apply_label',          label: 'Aplicar etiqueta',        icon: 'i-lucide-tag' },
  { value: 'move_card',            label: 'Mover para coluna',       icon: 'i-lucide-arrow-right-circle' },
  { value: 'log_timeline',         label: 'Registrar na timeline',   icon: 'i-lucide-clock' },
  { value: 'notify_team',          label: 'Notificar equipe',        icon: 'i-lucide-bell' },
  { value: 'meta_ads_event',       label: 'Evento Meta Ads',         icon: 'i-lucide-bar-chart-2' },
  { value: 'google_ads_conversion',label: 'Conversão Google Ads',    icon: 'i-lucide-trending-up' },
  { value: 'send_form',            label: 'Enviar formulário',       icon: 'i-lucide-clipboard-list' },
  { value: 'send_template',        label: 'Enviar mensagem modelo',  icon: 'i-lucide-message-square-text' },
  { value: 'ai_agent',             label: 'Adicionar agente de IA',  icon: 'i-lucide-bot' },
  { value: 'set_value',            label: 'Adicionar preço no card', icon: 'i-lucide-circle-dollar-sign' },
];

// ── Enviar mensagem modelo (template aprovado do WhatsApp) ─────────────
// mesmo padrão das Campanhas: caixa WhatsApp → templates da Meta →
// variáveis {{n}} → prévia. O envio em si reusa o Crm::SendTemplateService.
const templates = ref([]);
const selectedTemplateName = ref('');
const varValues = ref({});
const isLoadingTemplates = ref(false);
const wrapToken = t => '{{' + t + '}}';
const TOKEN_HINT = wrapToken('contact.name');
const whatsappInboxes = computed(() =>
  (accountInboxes.value || []).filter(i => i.channel_type === 'Channel::Whatsapp')
);
const selectedTemplate = computed(
  () => templates.value.find(t => t.name === selectedTemplateName.value) ?? null
);
const templateBodyText = computed(() => {
  const body = selectedTemplate.value?.components?.find(c => c.type === 'BODY');
  return body?.text ?? '';
});
const variableTokens = computed(() => {
  const tokens = new Set();
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(templateBodyText.value);
  while (m !== null) {
    tokens.add(m[1]);
    m = re.exec(templateBodyText.value);
  }
  return [...tokens];
});
const renderedTemplatePreview = computed(() =>
  templateBodyText.value.replace(/\{\{\s*(\d+)\s*\}\}/g, (full, token) =>
    varValues.value[token]?.trim() ? varValues.value[token] : full
  )
);
const loadTemplates = async inboxId => {
  if (!inboxId) return;
  isLoadingTemplates.value = true;
  try {
    const data = await store.dispatch('crm/fetchWhatsappTemplates', inboxId);
    // resposta inesperada (token inválido etc.) vem como objeto — nunca
    // deixar algo que não é lista chegar nos computed (quebrava o modal)
    templates.value = Array.isArray(data) ? data : [];
    if (!Array.isArray(data) || !data.length) {
      useAlert('Nenhuma mensagem modelo encontrada nesta caixa — confira a conexão com a Meta.');
    }
  } catch {
    templates.value = [];
    useAlert('Erro ao carregar as mensagens modelo do WhatsApp');
  } finally {
    isLoadingTemplates.value = false;
  }
};
const onTemplateInboxChange = () => {
  selectedTemplateName.value = '';
  varValues.value = {};
  templates.value = [];
  loadTemplates(form.value.action_config.inbox_id);
};

const emptyForm = () => ({
  name:          '',
  trigger_type:  'card_entered',
  delay_minutes: 0,
  customDelay:   '',
  action_type:   'webhook',
  active:        true,
  action_config: {
    webhook_url:        '',
    n8n_workflow_id:    '',
    n8n_workflow_name:  '',
    n8n_webhook_url:    '',
    label:              '',
    target_stage_id:    '',
    message:            '',
    assignee_id:        '',
    label_filter:       '',
    // Meta Ads
    meta_event_name:    'Lead',
    // Google Ads
    ga4_event_name:     'generate_lead',
    conversion_value:   '',
    currency:           'BRL',
    // Formulário
    form_id:            '',
    // Mensagem modelo (WhatsApp)
    inbox_id:           null,
    template_params:    null,
    message_preview:    '',
    // Agendar consulta (IA)
    default_unit:       '',
    // Gatilho "Mensagem criada"
    message_direction:  'incoming',
    message_contains:   '',
    throttle_minutes:   0,
    // Adicionar preço no card
    value:              '',
    value_mode:         'always',
    // Condição: caixa de chegada do lead (vazio = todas)
    inbox_ids:          [],
  },
});

const form = ref(emptyForm());

// Preenche o form ao editar
watch(() => props.initialAutomation, (auto) => {
  if (!auto) {
    form.value = emptyForm();
    return;
  }
  const preset = DELAY_PRESETS.find(p => p.value === auto.delay_minutes);
  form.value = {
    name:          auto.name,
    trigger_type:  auto.trigger_type,
    delay_minutes: preset ? auto.delay_minutes : -1,
    customDelay:   preset ? '' : String(auto.delay_minutes),
    action_type:   auto.action_type,
    active:        auto.active,
    action_config: {
      webhook_url:       auto.action_config?.webhook_url       ?? '',
      n8n_workflow_id:   auto.action_config?.n8n_workflow_id   ?? '',
      n8n_workflow_name: auto.action_config?.n8n_workflow_name ?? '',
      n8n_webhook_url:   auto.action_config?.n8n_webhook_url   ?? '',
      label:              auto.action_config?.label             ?? '',
      target_stage_id:    auto.action_config?.target_stage_id  ?? '',
      message:            auto.action_config?.message          ?? '',
      assignee_id:        auto.action_config?.assignee_id      ?? '',
      label_filter:       auto.action_config?.label_filter     ?? '',
      meta_event_name:    auto.action_config?.meta_event_name  ?? 'Lead',
      ga4_event_name:     auto.action_config?.ga4_event_name   ?? 'generate_lead',
      conversion_value:   auto.action_config?.conversion_value ?? '',
      currency:           auto.action_config?.currency         ?? 'BRL',
      form_id:            auto.action_config?.form_id          ?? '',
      inbox_id:           auto.action_config?.inbox_id         ?? null,
      template_params:    auto.action_config?.template_params  ?? null,
      message_preview:    auto.action_config?.message_preview  ?? '',
      default_unit:       auto.action_config?.default_unit     ?? '',
      message_direction:  auto.action_config?.message_direction ?? 'incoming',
      message_contains:   auto.action_config?.message_contains  ?? '',
      throttle_minutes:   auto.action_config?.throttle_minutes ?? 0,
      value:              auto.action_config?.value            ?? '',
      value_mode:         auto.action_config?.value_mode       ?? 'always',
      inbox_ids:          Array.isArray(auto.action_config?.inbox_ids)
        ? auto.action_config.inbox_ids.map(Number).filter(Boolean)
        : [],
    },
  };
  // edição de "mensagem modelo": recarrega os templates da caixa e repõe
  // a seleção + variáveis salvas
  if (auto.action_type === 'send_template' && auto.action_config?.inbox_id) {
    selectedTemplateName.value = auto.action_config?.template_params?.name ?? '';
    varValues.value = { ...(auto.action_config?.template_params?.processed_params?.body || {}) };
    loadTemplates(auto.action_config.inbox_id);
  }
}, { immediate: true });

const isCustomDelay = computed(() => form.value.delay_minutes === -1);

// o botão "Adicionar agente de IA" fica aceso para qualquer ação de IA
const isAiAction = computed(() => AI_ACTION_TYPES.includes(form.value.action_type));
const selectAction = value => {
  form.value.action_type = value === 'ai_agent' ? 'ai_analyze' : value;
};
const actionSelected = action =>
  action.value === 'ai_agent' ? isAiAction.value : form.value.action_type === action.value;

const otherStages = computed(() =>
  props.allStages.filter(s => s.id !== props.stage?.id)
);

const effectiveDelayMinutes = computed(() => {
  if (form.value.delay_minutes === -1) return parseInt(form.value.customDelay) || 0;
  return form.value.delay_minutes;
});

// Quando usuário seleciona workflow, auto-preenche a webhook URL se disponível
const onWorkflowSelected = () => {
  const wfId = form.value.action_config.n8n_workflow_id;
  if (!wfId) return;
  const wf = n8nWorkflows.value.find(w => w.id.toString() === wfId.toString());
  if (wf?.webhook_url) {
    form.value.action_config.n8n_webhook_url = wf.webhook_url;
  }
  // Salva também o nome para exibição
  form.value.action_config.n8n_workflow_name = wf?.name ?? '';
};

const save = async () => {
  if (!form.value.name.trim()) return;
  // mensagem modelo: precisa da caixa + template escolhido + variáveis
  if (form.value.action_type === 'send_template') {
    if (!form.value.action_config.inbox_id || !selectedTemplate.value) {
      useAlert('Escolha a caixa do WhatsApp e a mensagem modelo.');
      return;
    }
    if (!variableTokens.value.every(t => varValues.value[t]?.trim())) {
      useAlert('Preencha todas as variáveis da mensagem modelo.');
      return;
    }
    form.value.action_config.template_params = {
      name: selectedTemplate.value.name,
      namespace: selectedTemplate.value.namespace ?? '',
      language: selectedTemplate.value.language,
      category: selectedTemplate.value.category,
      processed_params: { body: { ...varValues.value } },
    };
    form.value.action_config.message_preview = templateBodyText.value;
  }
  isSaving.value = true;
  try {
    const payload = {
      name:          form.value.name,
      trigger_type:  form.value.trigger_type,
      delay_minutes: effectiveDelayMinutes.value,
      action_type:   form.value.action_type,
      active:        form.value.active,
      action_config: form.value.action_config,
    };

    if (isEditing.value) {
      await store.dispatch('crm/updateAutomation', {
        pipelineId: props.pipelineId,
        stageId:    props.stage.id,
        id:         props.initialAutomation.id,
        ...payload,
      });
      useAlert('Automação atualizada');
    } else {
      await store.dispatch('crm/createAutomation', {
        pipelineId: props.pipelineId,
        stageId:    props.stage.id,
        ...payload,
      });
      useAlert('Automação criada');
    }

    emit('saved');
  } catch {
    useAlert('Erro ao salvar automação. Tente novamente.');
  } finally {
    isSaving.value = false;
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
        <div>
          <div class="flex items-center gap-2">
            <span class="i-lucide-zap text-base text-yellow-500" />
            <h2 class="text-base font-semibold text-n-slate-12">
              {{ isEditing ? 'Editar automação' : 'Nova automação' }}
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mt-0.5 ml-6">{{ stage.name }}</p>
        </div>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
          @click="emit('close')"
        />
      </div>

      <!-- Form body -->
      <div class="flex-1 overflow-y-auto p-5 space-y-5">

        <!-- Nome -->
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Nome da automação</label>
          <input
            v-model="form.name"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            placeholder="Ex: Follow-up orçamento 24h"
            autofocus
          />
        </div>

        <!-- Gatilho -->
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Quando disparar?</label>
          <div class="space-y-1.5">
            <button
              v-for="tr in TRIGGERS"
              :key="tr.value"
              class="w-full flex items-center gap-2.5 px-3 py-2.5 rounded-lg border text-sm transition-colors text-left"
              :class="form.trigger_type === tr.value
                ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
                : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:border-n-brand/40'"
              @click="form.trigger_type = tr.value"
            >
              <span :class="tr.icon" class="text-base flex-shrink-0" />
              {{ tr.label }}
            </button>
          </div>

          <!-- Qual etiqueta dispara (para gatilhos de etiqueta) -->
          <div
            v-if="['label_added', 'label_removed'].includes(form.trigger_type)"
            class="mt-2 bg-n-brand/5 border border-n-brand/20 rounded-lg p-3 space-y-1.5"
          >
            <label class="text-xs font-medium text-n-slate-11 block">
              Qual etiqueta {{ form.trigger_type === 'label_added' ? 'adicionada' : 'removida' }} dispara?
            </label>
            <select
              v-model="form.action_config.label_filter"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option value="">Qualquer etiqueta</option>
              <option v-for="l in accountLabels" :key="l.id" :value="l.title">{{ l.title }}</option>
            </select>
          </div>

          <!-- Config do gatilho "Mensagem criada" -->
          <div
            v-if="form.trigger_type === 'message_created'"
            class="mt-2 bg-n-brand/5 border border-n-brand/20 rounded-lg p-3 space-y-3"
          >
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Mensagem de quem dispara?</label>
              <select
                v-model="form.action_config.message_direction"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option value="incoming">💬 Do paciente (recomendado)</option>
                <option value="outgoing">👤 Da atendente</option>
                <option value="both">Ambas</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                A mensagem contém as frases-chave <span class="text-n-slate-9 font-normal">(opcional — vazio = qualquer mensagem)</span>
              </label>
              <input
                v-model="form.action_config.message_contains"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder='Ex: quero agendar, pode marcar, "qual o valor"'
              />
              <p class="text-[11px] text-n-slate-9 mt-1">
                Separe alternativas por vírgula (qualquer uma dispara); use "aspas" para
                frase exata. Ignora acentos e maiúsculas — igual ao Tratamento de dados.
              </p>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Frequência <span class="text-n-slate-9 font-normal">(proteção contra disparo em rajada)</span>
              </label>
              <select
                v-model.number="form.action_config.throttle_minutes"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option :value="0">Toda mensagem (sem limite — ex.: fluxo n8n)</option>
                <option :value="5">No máximo 1 vez a cada 5 min por paciente</option>
                <option :value="30">No máximo 1 vez a cada 30 min por paciente</option>
                <option :value="60">No máximo 1 vez por hora por paciente</option>
                <option :value="1440">No máximo 1 vez por dia por paciente</option>
              </select>
            </div>
            <p class="text-xs text-n-slate-9">
              Dispara quando uma mensagem chega na conversa de um card que está NESTA coluna.
              Notas internas não contam.
            </p>
          </div>

          <!-- Explicação do gatilho "Valor adicionado" -->
          <div
            v-if="form.trigger_type === 'value_added'"
            class="mt-2 bg-n-brand/5 border border-n-brand/20 rounded-lg p-3"
          >
            <p class="text-xs text-n-slate-9">
              💰 Dispara quando um card NESTA coluna <b>ganha valor</b> (R$ &gt; 0) — vale para
              valor digitado no card, detectado pelo orçamento ou aplicado por outra automação.
              Uso típico: card recebeu orçamento em "Novos Contatos" → ação "Mover para coluna:
              Envio de Orçamento". Assim nenhum card com valor fica parado na coluna errada.
            </p>
          </div>
        </div>

        <!-- Tempo de espera -->
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Tempo de espera</label>
          <select
            v-model="form.delay_minutes"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
          >
            <option v-for="p in DELAY_PRESETS" :key="p.value" :value="p.value">{{ p.label }}</option>
          </select>
          <div v-if="isCustomDelay" class="mt-2 flex items-center gap-2">
            <input
              v-model="form.customDelay"
              type="number" min="1"
              class="w-28 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              placeholder="Minutos"
            />
            <span class="text-xs text-n-slate-10">minutos</span>
          </div>
        </div>

        <!-- Condição: caixa de chegada do lead (pílulas multi, kit CEVICO) -->
        <div v-if="conditionInboxes.length">
          <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
            Só para leads da caixa de entrada
          </label>
          <div class="flex flex-wrap items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5">
            <button
              type="button"
              class="px-3 h-7 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0"
              :class="conditionInboxSet.size === 0 ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="conditionInboxSet.size === 0 ? { background: ALL_INBOXES_GRADIENT } : {}"
              @click="toggleConditionInbox(0)"
            >
              Todas
            </button>
            <button
              v-for="ib in conditionInboxes"
              :key="ib.id"
              type="button"
              class="px-3 h-7 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0 flex items-center gap-1.5"
              :class="conditionInboxSet.has(ib.id) ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
              :style="conditionInboxSet.has(ib.id) ? { background: condInboxGrad(ib.id) } : {}"
              :title="conditionInboxSet.has(ib.id) ? 'Clique para tirar esta caixa da condição' : 'Clique para somar esta caixa à condição'"
              @click="toggleConditionInbox(ib.id)"
            >
              <span
                v-if="!conditionInboxSet.has(ib.id)"
                class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                :style="{ background: condInboxDot(ib.id) }"
              />
              {{ ib.name }}
            </button>
          </div>
          <p class="text-[11px] text-n-slate-10 mt-1.5">
            A automação só dispara para leads que <b>chegaram</b> por essas caixas (primeira
            conversa) — ex.: evento de conversão do Google só para a caixa GOOGLE. Vazio = todas.
          </p>
        </div>

        <!-- Ação -->
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1.5">O que fazer?</label>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="action in ACTIONS"
              :key="action.value"
              class="flex items-center gap-2 px-3 py-2.5 rounded-lg border text-sm transition-colors text-left"
              :class="actionSelected(action)
                ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
                : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:border-n-brand/40'"
              @click="selectAction(action.value)"
            >
              <span :class="action.icon" class="text-base flex-shrink-0" />
              {{ action.label }}
            </button>
          </div>
        </div>

        <!-- Config da ação selecionada -->
        <div v-if="form.action_type === 'webhook'" class="space-y-1.5">
          <label class="text-xs font-medium text-n-slate-11 block">URL do webhook</label>
          <input
            v-model="form.action_config.webhook_url"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
            placeholder="https://seu-servidor.com/webhook"
          />
          <p class="text-xs text-n-slate-9">POST com todos os dados do card/contato.</p>
        </div>

        <div v-else-if="form.action_type === 'n8n_flow'" class="space-y-3">
          <!-- Tem workflows em cache → mostra dropdown -->
          <template v-if="hasN8nWorkflows">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Workflow</label>
              <select
                v-model="form.action_config.n8n_workflow_id"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                @change="onWorkflowSelected"
              >
                <option value="">Selecione um workflow...</option>
                <option
                  v-for="wf in n8nWorkflows"
                  :key="wf.id"
                  :value="wf.id"
                >
                  {{ wf.active ? '● ' : '○ ' }}{{ wf.name }}
                </option>
              </select>
            </div>
            <!-- Webhook URL detectada automaticamente (editável) -->
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                URL do webhook
                <span class="text-n-slate-9 font-normal">(detectada automaticamente ou informe manualmente)</span>
              </label>
              <input
                v-model="form.action_config.n8n_webhook_url"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
                placeholder="https://n8n.seudominio.com/webhook/..."
              />
            </div>
          </template>

          <!-- Sem workflows → pede para configurar integração -->
          <template v-else>
            <div class="flex items-start gap-2.5 px-3 py-3 bg-yellow-500/8 border border-yellow-400/30 rounded-lg">
              <span class="i-lucide-alert-triangle text-sm text-yellow-500 flex-shrink-0 mt-0.5" />
              <div>
                <p class="text-xs font-medium text-n-slate-12">Nenhum workflow importado</p>
                <p class="text-xs text-n-slate-10 mt-0.5">
                  Configure a integração com n8n e busque os workflows antes de usar esta ação.
                  Use o botão <strong>Integrações</strong> no topo do CRM.
                </p>
              </div>
            </div>
            <!-- Fallback: URL manual -->
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Ou informe a URL do webhook diretamente</label>
              <input
                v-model="form.action_config.n8n_webhook_url"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
                placeholder="https://n8n.seudominio.com/webhook/..."
              />
            </div>
          </template>
        </div>

        <div v-else-if="form.action_type === 'apply_label'" class="space-y-1.5">
          <label class="text-xs font-medium text-n-slate-11 block">Nome da etiqueta</label>
          <input
            v-model="form.action_config.label"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            placeholder="Ex: follow-up-enviado"
          />
        </div>

        <div v-else-if="form.action_type === 'move_card'" class="space-y-1.5">
          <label class="text-xs font-medium text-n-slate-11 block">Mover para a coluna</label>
          <select
            v-model="form.action_config.target_stage_id"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
          >
            <option value="">Selecione uma coluna...</option>
            <option v-for="s in otherStages" :key="s.id" :value="s.id">{{ s.name }}</option>
          </select>
        </div>

        <div v-else-if="form.action_type === 'log_timeline'" class="space-y-1.5">
          <label class="text-xs font-medium text-n-slate-11 block">Mensagem na timeline</label>
          <input
            v-model="form.action_config.message"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            placeholder="Ex: Orçamento enviado ao paciente"
          />
        </div>

        <div v-else-if="form.action_type === 'notify_team'" class="space-y-3">
          <!-- Mensagem personalizada -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Mensagem <span class="text-n-slate-9 font-normal">(opcional)</span></label>
            <textarea
              v-model="form.action_config.message"
              rows="3"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
              placeholder="Ex: Lead chegou em Fechamento! Acompanhe de perto."
            />
            <p class="text-xs text-n-slate-9 mt-1">Aparece como nota interna na conversa do contato.</p>
          </div>
          <!-- Responsável (opcional) -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Atribuir conversa a <span class="text-n-slate-9 font-normal">(opcional)</span></label>
            <select
              v-model="form.action_config.assignee_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option value="">Não alterar responsável</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                {{ agent.name }}
              </option>
            </select>
          </div>
        </div>

        <!-- Meta Ads -->
        <div v-else-if="form.action_type === 'meta_ads_event'" class="space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Evento Meta</label>
            <select
              v-model="form.action_config.meta_event_name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option value="Lead">Lead</option>
              <option value="CompleteRegistration">CompleteRegistration (Cadastro)</option>
              <option value="Purchase">Purchase (Compra/Fechamento)</option>
              <option value="InitiateCheckout">InitiateCheckout (Proposta enviada)</option>
              <option value="ViewContent">ViewContent (Visualização)</option>
              <option value="Contact">Contact (Contato)</option>
              <option value="Schedule">Schedule (Agendamento)</option>
            </select>
            <p class="text-xs text-n-slate-9 mt-1">Configure o Pixel e Access Token em Configurações → Integrações → Meta Ads.</p>
          </div>
        </div>

        <!-- Enviar formulário -->
        <div v-else-if="form.action_type === 'send_form'" class="space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Formulário</label>
            <select
              v-model="form.action_config.form_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option value="">Selecione...</option>
              <option v-for="f in availableForms" :key="f.id" :value="f.id">{{ f.name }}</option>
            </select>
            <p class="text-xs text-n-slate-9 mt-1">
              Cada contato recebe um link único na conversa mais recente. Quem já
              respondeu não recebe de novo. Crie formulários na página "Formulários".
            </p>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Mensagem <span class="text-n-slate-9 font-normal">(use {{ '\{\{nome\}\}' }} e {{ '\{\{link\}\}' }})</span></label>
            <textarea
              v-model="form.action_config.message"
              rows="3"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              placeholder="Oi {{nome}}! Para agilizar sua consulta, responda nosso formulário (2 minutinhos): {{link}}"
            />
          </div>
        </div>

        <!-- Enviar mensagem modelo (template aprovado do WhatsApp) -->
        <div v-else-if="form.action_type === 'send_template'" class="space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Caixa do WhatsApp</label>
            <select
              v-model="form.action_config.inbox_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              @change="onTemplateInboxChange"
            >
              <option :value="null">Selecione...</option>
              <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">{{ i.name }}</option>
            </select>
          </div>
          <div v-if="form.action_config.inbox_id">
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Mensagem modelo</label>
            <select
              v-model="selectedTemplateName"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            >
              <option value="" disabled>{{ isLoadingTemplates ? 'Carregando…' : 'Selecione o template…' }}</option>
              <option v-for="tpl in templates" :key="`${tpl.name}-${tpl.language}`" :value="tpl.name">
                {{ tpl.name }} ({{ tpl.language }})
              </option>
            </select>
            <p class="text-xs text-n-slate-9 mt-1">
              São as mensagens aprovadas no Gerenciador da Meta — as mesmas das
              Campanhas. Chegam mesmo fora da janela de 24h do WhatsApp.
            </p>
          </div>
          <div v-if="selectedTemplate" class="space-y-3">
            <div class="bg-n-alpha-1 border border-n-weak rounded-lg p-3">
              <p class="text-xs text-n-slate-10 mb-1">Prévia da mensagem</p>
              <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ renderedTemplatePreview }}</p>
            </div>
            <div v-for="token in variableTokens" :key="token">
              <label class="text-xs font-medium text-n-slate-11 block mb-1">
                Variável {{ wrapToken(token) }}
              </label>
              <input
                v-model="varValues[token]"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                :placeholder="'Valor fixo ou ' + TOKEN_HINT + ' para personalizar'"
              />
            </div>
            <p v-if="variableTokens.length" class="text-xs text-n-slate-9">
              Dica: use <span class="font-mono">{{ TOKEN_HINT }}</span> para inserir o nome do paciente automaticamente.
            </p>
          </div>
          <div class="rounded-xl p-3 text-xs border-2 flex items-start gap-2" style="border-color: rgba(212,160,23,0.4); background: rgba(212,160,23,0.08)">
            <span class="i-lucide-shield-check text-sm flex-shrink-0 mt-0.5" style="color: #B8860B" />
            <p class="text-n-slate-11">
              Trava anti-rajada: esta automação <b>não reenvia</b> a mesma mensagem
              pro mesmo paciente dentro de 7 dias — card que entra e sai da coluna
              não vira spam.
            </p>
          </div>
        </div>

        <!-- Adicionar agente de IA (escolhe qual agente roda na coluna) -->
        <div v-else-if="isAiAction" class="space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Qual agente?</label>
            <select
              v-model="form.action_type"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            >
              <option value="ai_analyze">✨ Analista de Conversas — lê a conversa e dá o parecer de interesse</option>
              <option value="schedule_appointment">📅 Secretário da Agenda — cria a consulta na Agenda</option>
              <option value="closing_extract">💰 Monitor de Fechamento — valor fechado, forma de pagamento e data da cirurgia</option>
              <option value="nps_score">🌟 Agente de NPS — lê a nota 0-10 e etiqueta o paciente (9-10 / 7-8 / 0-6)</option>
            </select>
          </div>

          <!-- interruptor de segurança: sem agente LIGADO, nada roda -->
          <div class="rounded-xl p-3 text-xs border-2 flex items-start gap-2" style="border-color: rgba(212,160,23,0.4); background: rgba(212,160,23,0.08)">
            <span class="i-lucide-power text-sm flex-shrink-0 mt-0.5" style="color: #B8860B" />
            <p class="text-n-slate-11">
              Esta automação <b>só roda se o agente estiver LIGADO</b> no interruptor em
              Automações → Agentes de IA (o padrão é desligado). Desligar o agente lá
              para esta automação na hora — ela fica aqui, mas não faz nada.
            </p>
          </div>

          <div v-if="form.action_type === 'ai_analyze'" class="bg-n-alpha-1 rounded-xl p-3.5 text-xs text-n-slate-11 space-y-1.5">
            <p class="flex items-center gap-1.5 font-medium text-n-slate-12">
              <span class="i-lucide-sparkles" style="color: #D97706" />
              Analista de Conversas (Claude)
            </p>
            <p>
              Quando o card entrar aqui, a IA lê a conversa e salva o parecer
              (interesse alto/médio/baixo/perdido + resumo + próximo passo) —
              visível no painel da conversa e no balão do CRM. Cada análise
              custa centavos. Nunca fala com o paciente.
            </p>
          </div>

          <template v-else>
            <div class="bg-n-alpha-1 rounded-xl p-3.5 text-xs text-n-slate-11 space-y-1.5">
              <p class="flex items-center gap-1.5 font-medium text-n-slate-12">
                <span class="i-lucide-calendar-plus" style="color: #7C3AED" />
                Agente de Agendamento (Claude)
              </p>
              <p>
                Quando o card entrar aqui (ex.: coluna "Consulta agendada"), a IA lê a
                conversa, extrai <b>nome, telefone, dia, hora e unidade</b> e cria o
                compromisso na <b>Agenda</b> automaticamente. Nunca fala com o paciente.
              </p>
              <p>
                Se dia e hora não estiverem confirmados na conversa, ela cria uma tarefa
                "⚠️ Confirmar consulta" para a equipe completar — nada se perde.
              </p>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                Unidade padrão <span class="text-n-slate-9 font-normal">(usada quando a conversa não diz a unidade)</span>
              </label>
              <select
                v-model="form.action_config.default_unit"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              >
                <option value="">Deixar sem unidade</option>
                <option value="tatuape">Tatuapé</option>
                <option value="paulista">Av. Paulista</option>
              </select>
            </div>
          </template>
        </div>

        <!-- Adicionar preço no card -->
        <div v-else-if="form.action_type === 'set_value'" class="space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Valor (R$)</label>
            <input
              v-model="form.action_config.value"
              type="number" min="0" step="0.01"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              placeholder="Ex: 5000"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Como aplicar?</label>
            <select
              v-model="form.action_config.value_mode"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            >
              <option value="always">Substituir o valor do card</option>
              <option value="if_empty">Só preencher se o card estiver sem valor</option>
              <option value="add">Somar ao valor atual do card</option>
            </select>
          </div>
          <p class="text-xs text-n-slate-9">
            O valor alimenta o "Valor em pipeline" e o "valor por etapa" do Dashboard.
            Ex.: card entrou em "Envio de Orçamento" com etiqueta refrativa → R$ 5.000.
          </p>
        </div>

        <!-- Google Ads -->
        <div v-else-if="form.action_type === 'google_ads_conversion'" class="space-y-3">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Evento GA4</label>
            <input
              v-model="form.action_config.ga4_event_name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand font-mono"
              placeholder="generate_lead"
            />
            <p class="text-xs text-n-slate-9 mt-1">Nome do evento no GA4. Ex: <code>generate_lead</code>, <code>purchase</code>, <code>sign_up</code></p>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Valor da conversão <span class="text-n-slate-9 font-normal">(opcional)</span></label>
              <input
                v-model="form.action_config.conversion_value"
                type="number"
                step="0.01"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
                placeholder="0.00"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Moeda</label>
              <select
                v-model="form.action_config.currency"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              >
                <option value="BRL">BRL</option>
                <option value="USD">USD</option>
                <option value="EUR">EUR</option>
              </select>
            </div>
          </div>
          <p class="text-xs text-n-slate-9">Configure o Measurement ID e API Secret em Configurações → Integrações → Google Ads.</p>
        </div>

        <!-- Status -->
        <label class="flex items-center gap-3 cursor-pointer">
          <div
            class="relative w-10 h-5 rounded-full transition-colors flex-shrink-0"
            :class="form.active ? 'bg-n-brand' : 'bg-n-weak'"
            @click="form.active = !form.active"
          >
            <span
              class="absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform"
              :class="form.active ? 'translate-x-5' : 'translate-x-0'"
            />
          </div>
          <div>
            <p class="text-sm text-n-slate-12">{{ form.active ? 'Automação ativa' : 'Automação inativa' }}</p>
            <p class="text-xs text-n-slate-9">{{ form.active ? 'Será disparada automaticamente' : 'Não será disparada' }}</p>
          </div>
        </label>

      </div>

      <!-- Footer -->
      <div class="flex gap-2 px-5 py-4 border-t border-n-weak flex-shrink-0">
        <button
          class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50 transition-colors"
          :disabled="isSaving || !form.name.trim()"
          @click="save"
        >
          {{ isSaving ? 'Salvando...' : (isEditing ? 'Salvar alterações' : 'Criar automação') }}
        </button>
        <button
          class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
          @click="emit('close')"
        >
          Cancelar
        </button>
      </div>

    </div>
  </div>
</template>
