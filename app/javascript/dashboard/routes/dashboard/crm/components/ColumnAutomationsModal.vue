<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

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
const agents       = useMapGetter('agents/getAgents');
const hasN8nWorkflows = computed(() => n8nWorkflows.value?.length > 0);

// Carrega settings e agentes ao abrir
store.dispatch('crm/fetchSettings').catch(() => {});
onMounted(() => {
  if (!agents.value.length) store.dispatch('agents/get');
});

const isEditing = computed(() => !!props.initialAutomation);

const TRIGGERS = [
  { value: 'card_entered',  label: 'Card entrou nesta coluna',     icon: 'i-lucide-log-in' },
  { value: 'card_left',     label: 'Card saiu desta coluna',       icon: 'i-lucide-log-out' },
  { value: 'card_stalled',  label: 'Card parado por X tempo',      icon: 'i-lucide-clock' },
  { value: 'label_added',   label: 'Etiqueta adicionada',          icon: 'i-lucide-tag' },
  { value: 'label_removed', label: 'Etiqueta removida',            icon: 'i-lucide-tag' },
];

const DELAY_PRESETS = [
  { value: 0,    label: 'Imediatamente' },
  { value: 60,   label: 'Após 1 hora' },
  { value: 180,  label: 'Após 3 horas' },
  { value: 1440, label: 'Após 24 horas' },
  { value: 4320, label: 'Após 3 dias' },
  { value: -1,   label: 'Personalizado' },
];

const ACTIONS = [
  { value: 'webhook',              label: 'Disparar webhook',        icon: 'i-lucide-globe' },
  { value: 'n8n_flow',             label: 'Acionar fluxo n8n',       icon: 'i-lucide-workflow' },
  { value: 'apply_label',          label: 'Aplicar etiqueta',        icon: 'i-lucide-tag' },
  { value: 'move_card',            label: 'Mover para coluna',       icon: 'i-lucide-arrow-right-circle' },
  { value: 'log_timeline',         label: 'Registrar na timeline',   icon: 'i-lucide-clock' },
  { value: 'notify_team',          label: 'Notificar equipe',        icon: 'i-lucide-bell' },
  { value: 'meta_ads_event',       label: 'Evento Meta Ads',         icon: 'i-lucide-bar-chart-2' },
  { value: 'google_ads_conversion',label: 'Conversão Google Ads',    icon: 'i-lucide-trending-up' },
];

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
    },
  };
}, { immediate: true });

const isCustomDelay = computed(() => form.value.delay_minutes === -1);

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

        <!-- Ação -->
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1.5">O que fazer?</label>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="action in ACTIONS"
              :key="action.value"
              class="flex items-center gap-2 px-3 py-2.5 rounded-lg border text-sm transition-colors text-left"
              :class="form.action_type === action.value
                ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
                : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:border-n-brand/40'"
              @click="form.action_type = action.value"
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

        <!-- Config extra: filtro de etiqueta para triggers label_added/label_removed -->
        <div
          v-if="['label_added','label_removed'].includes(form.trigger_type)"
          class="space-y-1.5 border-t border-n-weak pt-4"
        >
          <label class="text-xs font-medium text-n-slate-11 block">
            Etiqueta específica <span class="text-n-slate-9 font-normal">(opcional — deixe vazio para qualquer etiqueta)</span>
          </label>
          <input
            v-model="form.action_config.label_filter"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
            placeholder="Ex: vip, follow-up, cirurgia"
          />
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
