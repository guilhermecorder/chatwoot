<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import TemplatesPicker from 'dashboard/components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const props = defineProps({
  bot: { type: Object, default: null },       // editar
  stageId: { type: Number, default: null },    // robô por coluna (modo programação)
  pipelineId: { type: Number, default: null },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const accountLabels = useMapGetter('labels/getLabels');
const whatsappInboxes = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::Whatsapp')
);

const isStageBot = computed(() => !!props.stageId);
const isSaving = ref(false);

const newStep = () => ({
  delay_value: 3,
  delay_unit: 'hours',
  delay_from: 'silence',
  kind: 'text',
  message: 'Oi, pode falar?',
  template_params: null,
  skip_labels: [],
  only_labels: [],
});

// aceita etapas legadas ({delay_hours}) e as novas
const normalizeStep = s => ({
  delay_value: s.delay_value ?? s.delay_hours ?? 3,
  delay_unit: s.delay_unit ?? 'hours',
  delay_from: s.delay_from ?? 'silence',
  kind: s.template_params ? 'template' : 'text',
  message: s.message ?? '',
  template_params: s.template_params ?? null,
  skip_labels: [...(s.skip_labels ?? [])],
  only_labels: [...(s.only_labels ?? [])],
});

// regras de etiqueta POR ETAPA (item 127) — aberto quando a etapa já tem regra
const labelRulesOpen = ref({});
const toggleLabelRules = i => {
  labelRulesOpen.value = { ...labelRulesOpen.value, [i]: !labelRulesOpen.value[i] };
};
const stepHasLabelRules = step =>
  (step.skip_labels?.length ?? 0) > 0 || (step.only_labels?.length ?? 0) > 0;

const toLocalInput = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const form = ref({
  name: '',
  inbox_id: null,
  active: true,
  steps: [newStep()],
  required_labels: [],
  exclude_labels: [],
  starts_at: '',
  ends_at: '',
});

onMounted(() => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  if (!accountLabels.value.length) store.dispatch('labels/get').catch(() => {});
  if (props.bot) {
    form.value = {
      name: props.bot.name,
      inbox_id: props.bot.inbox_id,
      active: props.bot.active,
      steps: props.bot.steps.length ? props.bot.steps.map(normalizeStep) : [newStep()],
      required_labels: [...(props.bot.required_labels ?? [])],
      exclude_labels: [...(props.bot.exclude_labels ?? [])],
      starts_at: toLocalInput(props.bot.starts_at),
      ends_at: toLocalInput(props.bot.ends_at),
    };
  }
  // novo robô nasce em modo AUTOMÁTICO (caixa da conversa do card)
});

const toggleListItem = (list, value) => {
  const idx = list.indexOf(value);
  if (idx === -1) list.push(value);
  else list.splice(idx, 1);
};

const addStep = () => {
  const last = form.value.steps[form.value.steps.length - 1];
  form.value.steps.push({
    ...newStep(),
    delay_value: (Number(last?.delay_value) || 0) + (last?.delay_unit === 'days' ? 1 : 7),
    delay_unit: last?.delay_unit ?? 'hours',
    message: '',
  });
};
const removeStep = i => form.value.steps.splice(i, 1);

const setStepKind = (step, kind) => {
  step.kind = kind;
  if (kind === 'text') step.template_params = null;
};

// ── Escolha de mensagem modelo para uma etapa ──
const templateStepIndex = ref(null); // índice da etapa escolhendo modelo
const pickerTemplate = ref(null);    // template selecionado (aguardando variáveis)

const templatePickerInboxId = computed(
  () => form.value.inbox_id ?? whatsappInboxes.value[0]?.id
);

const openTemplatePicker = i => {
  templateStepIndex.value = i;
  pickerTemplate.value = null;
};

const closeTemplatePicker = () => {
  templateStepIndex.value = null;
  pickerTemplate.value = null;
};

const useTemplate = payload => {
  const step = form.value.steps[templateStepIndex.value];
  if (step) {
    step.kind = 'template';
    step.message = payload.message;
    step.template_params = payload.templateParams;
  }
  closeTemplatePicker();
};

const stepValid = s =>
  Number(s.delay_value) >= 0 &&
  (s.kind === 'template' ? !!s.template_params : !!s.message?.trim());

const canSave = computed(
  () =>
    form.value.name?.trim() &&
    form.value.steps?.length &&
    form.value.steps.every(stepValid)
);

const save = async () => {
  if (!canSave.value || isSaving.value) return;
  isSaving.value = true;
  try {
    const payload = {
      name: form.value.name.trim(),
      active: form.value.active,
      steps: form.value.steps.map(s => ({
        delay_value: Number(s.delay_value),
        delay_unit: s.delay_unit,
        delay_from: s.delay_from || 'silence',
        kind: s.kind,
        message: s.kind === 'template' ? s.message : s.message.trim(),
        template_params: s.kind === 'template' ? s.template_params : null,
        skip_labels: s.skip_labels ?? [],
        only_labels: s.only_labels ?? [],
      })),
      required_labels: form.value.required_labels,
      exclude_labels: form.value.exclude_labels,
      starts_at: form.value.starts_at ? new Date(form.value.starts_at).toISOString() : null,
      ends_at: form.value.ends_at ? new Date(form.value.ends_at).toISOString() : null,
    };
    payload.inbox_id = form.value.inbox_id; // no robô de coluna é opcional
    if (isStageBot.value) {
      payload.stage_id = props.stageId;
      payload.pipeline_id = props.pipelineId;
    }
    if (props.bot) {
      await store.dispatch('crm/updateFollowupBot', { id: props.bot.id, ...payload });
    } else {
      await store.dispatch('crm/createFollowupBot', payload);
    }
    useAlert('Robô salvo!');
    emit('saved');
  } catch {
    useAlert('Erro ao salvar o robô');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-xl max-h-[92vh] flex flex-col">
      <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
        <h2 class="text-base font-semibold text-n-slate-12">{{ bot ? 'Editar robô' : 'Novo robô de follow-up' }}</h2>
        <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="emit('close')" />
      </div>

      <!-- ── Sub-painel: escolher mensagem modelo ── -->
      <div v-if="templateStepIndex !== null" class="flex-1 overflow-y-auto p-5 space-y-3">
        <div class="flex items-center justify-between">
          <p class="text-sm font-semibold text-n-slate-12">
            {{ pickerTemplate ? 'Preencher variáveis do modelo' : 'Escolher mensagem modelo' }}
          </p>
          <button class="text-xs text-n-slate-10 hover:text-n-slate-12 flex items-center gap-1" @click="closeTemplatePicker">
            <span class="i-lucide-arrow-left text-sm" /> Voltar
          </button>
        </div>

        <WhatsAppTemplateParser
          v-if="pickerTemplate"
          :template="pickerTemplate"
          @send-message="useTemplate"
          @reset-template="pickerTemplate = null"
        >
          <template #actions="{ sendMessage, resetTemplate, disabled }">
            <footer class="flex gap-2 justify-end">
              <button class="px-3 py-1.5 text-sm border border-n-weak rounded-lg text-n-slate-11" @click="resetTemplate">
                Trocar modelo
              </button>
              <button
                class="px-4 py-1.5 text-sm bg-n-brand text-white rounded-lg disabled:opacity-50"
                :disabled="disabled"
                @click="sendMessage"
              >
                Usar este modelo
              </button>
            </footer>
          </template>
        </WhatsAppTemplateParser>
        <TemplatesPicker
          v-else
          :inbox-id="templatePickerInboxId"
          @on-select="pickerTemplate = $event"
        />
      </div>

      <!-- ── Formulário principal ── -->
      <div v-else class="flex-1 overflow-y-auto p-5 space-y-4">
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome do robô</label>
          <input
            v-model="form.name"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            placeholder="Ex.: Cutucada pós-orçamento"
          />
        </div>

        <div v-if="isStageBot" class="bg-n-brand/5 border border-n-brand/20 rounded-lg px-3 py-2 text-xs text-n-slate-11">
          <span class="i-lucide-info text-n-brand" />
          Este robô roda para os cards <strong>desta coluna</strong>.
        </div>
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1">
            Caixa de entrada
          </label>
          <select
            v-model="form.inbox_id"
            class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
          >
            <option :value="null">🔁 Automática — número da conversa do card (recomendado)</option>
            <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">Somente {{ i.name }}</option>
          </select>
          <p class="text-[11px] text-n-slate-9 mt-1">
            No modo automático, cada paciente recebe o follow-up pelo mesmo número em que já conversa.
            Escolha uma caixa específica só se quiser limitar o robô a um número.
          </p>
        </div>

        <!-- Etapas -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <label class="text-xs font-medium text-n-slate-11">Cadência de mensagens</label>
            <button class="text-xs text-n-brand hover:underline flex items-center gap-1" @click="addStep">
              <span class="i-lucide-plus text-xs" /> Adicionar etapa
            </button>
          </div>

          <div class="space-y-2.5">
            <div
              v-for="(step, i) in form.steps"
              :key="i"
              class="border border-n-weak rounded-xl p-3 space-y-2"
            >
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-xs text-n-slate-10">Após</span>
                <input
                  v-model.number="step.delay_value"
                  type="number"
                  min="0"
                  step="1"
                  class="w-16 border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
                />
                <select
                  v-model="step.delay_unit"
                  class="border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
                >
                  <option value="minutes">minuto(s)</option>
                  <option value="hours">hora(s)</option>
                  <option value="days">dia(s)</option>
                </select>
                <!-- Tipo da contagem -->
                <select
                  v-model="step.delay_from"
                  class="border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
                  title="A partir de quando o tempo é contado"
                >
                  <option value="silence">sem resposta do paciente</option>
                  <option v-if="isStageBot" value="stage_entry">desde a entrada na coluna</option>
                </select>
                <span class="text-xs text-n-slate-10">→ enviar:</span>

                <!-- Tipo da etapa -->
                <div class="flex rounded-lg border border-n-weak overflow-hidden ml-auto">
                  <button
                    class="px-2.5 py-1 text-xs"
                    :class="step.kind === 'text' ? 'bg-n-brand text-white' : 'text-n-slate-10 hover:bg-n-alpha-1'"
                    @click="setStepKind(step, 'text')"
                  >Texto</button>
                  <button
                    class="px-2.5 py-1 text-xs"
                    :class="step.kind === 'template' ? 'bg-n-brand text-white' : 'text-n-slate-10 hover:bg-n-alpha-1'"
                    @click="setStepKind(step, 'template')"
                  >Modelo</button>
                </div>

                <button
                  v-if="form.steps.length > 1"
                  class="text-n-slate-9 hover:text-red-500 i-lucide-x text-base flex-shrink-0"
                  @click="removeStep(i)"
                />
              </div>

              <!-- Texto simples -->
              <input
                v-if="step.kind === 'text'"
                v-model="step.message"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder='Ex.: [nome], no seu tempo ok?'
              />

              <!-- Mensagem modelo -->
              <div v-else class="flex items-center gap-2">
                <div class="flex-1 min-w-0">
                  <p v-if="step.template_params" class="text-xs text-n-slate-12 truncate">
                    📋 {{ step.template_params.name }}
                    <span class="text-n-slate-9">— "{{ step.message?.slice(0, 60) }}…"</span>
                  </p>
                  <p v-else class="text-xs text-amber-600">Nenhum modelo escolhido ainda.</p>
                </div>
                <button
                  class="text-xs px-2.5 py-1.5 rounded-lg border border-n-brand text-n-brand hover:bg-n-brand/10 flex-shrink-0"
                  @click="openTemplatePicker(i)"
                >
                  {{ step.template_params ? 'Trocar modelo' : 'Escolher modelo' }}
                </button>
              </div>

              <!-- Regras de etiqueta DESTA etapa (item 127): proteger quem já
                   avançou (ex.: cta_agendamento fora da cutucada de 24h) sem
                   tirar essas pessoas das etapas longas -->
              <div>
                <button
                  class="text-[11px] flex items-center gap-1 transition-colors"
                  :class="stepHasLabelRules(step) ? 'text-amber-600 dark:text-amber-400 font-medium' : 'text-n-slate-9 hover:text-n-slate-11'"
                  @click="toggleLabelRules(i)"
                >
                  <span class="i-lucide-tags text-xs" />
                  {{ stepHasLabelRules(step)
                    ? `Regras de etiqueta ativas (${(step.skip_labels?.length ?? 0) + (step.only_labels?.length ?? 0)})`
                    : 'Regras de etiqueta desta etapa' }}
                  <span class="text-xs" :class="labelRulesOpen[i] ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" />
                </button>

                <div v-if="labelRulesOpen[i]" class="mt-2 space-y-2.5 bg-n-alpha-1 rounded-lg p-2.5">
                  <div>
                    <label class="text-[11px] font-medium text-n-slate-11 block mb-1">
                      PULAR quem tem <span class="text-n-slate-9 font-normal">(a etapa não sai para quem tiver alguma destas — as outras etapas seguem valendo)</span>
                    </label>
                    <div class="flex flex-wrap gap-1.5">
                      <button
                        v-for="l in accountLabels"
                        :key="`skip-${i}-${l.id}`"
                        class="flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full border transition-colors"
                        :class="step.skip_labels.includes(l.title)
                          ? 'bg-red-500/15 border-red-500 text-red-600 font-medium line-through'
                          : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                        @click="toggleListItem(step.skip_labels, l.title)"
                      >
                        <span class="w-1.5 h-1.5 rounded-full" :style="{ backgroundColor: l.color ?? '#6B7280' }" />
                        {{ l.title }}
                      </button>
                    </div>
                  </div>

                  <div>
                    <label class="text-[11px] font-medium text-n-slate-11 block mb-1">
                      SÓ para quem tem <span class="text-n-slate-9 font-normal">(vazio = etapa para todos)</span>
                    </label>
                    <div class="flex flex-wrap gap-1.5">
                      <button
                        v-for="l in accountLabels"
                        :key="`only-${i}-${l.id}`"
                        class="flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full border transition-colors"
                        :class="step.only_labels.includes(l.title)
                          ? 'bg-sky-500/15 border-sky-500 text-sky-700 dark:text-sky-400 font-medium'
                          : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                        @click="toggleListItem(step.only_labels, l.title)"
                      >
                        <span class="w-1.5 h-1.5 rounded-full" :style="{ backgroundColor: l.color ?? '#6B7280' }" />
                        {{ l.title }}
                      </button>
                    </div>
                  </div>

                  <p class="text-[10px] text-n-slate-9">
                    Ex.: na cutucada de 24h, marque <strong>cta_agendamento</strong> em "PULAR quem tem" —
                    quem já topou agendar não é reabordado cedo, mas continua recebendo as etapas de 30 dias+.
                  </p>
                </div>
              </div>
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-2">
            Use <code class="bg-n-alpha-2 px-1 rounded">[nome]</code> para o primeiro nome do paciente —
            o robô limpa emojis e símbolos do nome do WhatsApp e, se o contato não tiver nome aproveitável,
            escreve "oi" no lugar (sem "Oi oi").
            Após 24h de silêncio, o WhatsApp só entrega mensagem MODELO — use etapas de modelo para prazos em dias.
          </p>
        </div>

        <!-- Janela de funcionamento -->
        <div class="border-t border-n-weak pt-4">
          <p class="text-xs font-semibold text-n-slate-12 mb-2">Quando funciona?</p>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Começa em <span class="text-n-slate-9">(opcional)</span></label>
              <input
                v-model="form.starts_at"
                type="datetime-local"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Para em <span class="text-n-slate-9">(opcional)</span></label>
              <input
                v-model="form.ends_at"
                type="datetime-local"
                class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
              />
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-2">
            O robô também para quando: você clicar em <strong>Pausar</strong>, o paciente <strong>responder</strong>
            (a cadência daquela conversa é interrompida), ou o contato ganhar uma etiqueta da lista "NÃO TEM".
          </p>
        </div>

        <!-- Filtros de etiqueta: quem recebe a cadência -->
        <div class="border-t border-n-weak pt-4 space-y-3">
          <p class="text-xs font-semibold text-n-slate-12">Quem recebe? (filtros de etiqueta)</p>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              TEM as etiquetas <span class="text-n-slate-9 font-normal">(precisa ter todas — vazio ignora)</span>
            </label>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="l in accountLabels"
                :key="`req-${l.id}`"
                class="flex items-center gap-1 text-xs px-2 py-1 rounded-full border transition-colors"
                :class="form.required_labels.includes(l.title)
                  ? 'bg-green-500/15 border-green-500 text-green-700 dark:text-green-400 font-medium'
                  : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                @click="toggleListItem(form.required_labels, l.title)"
              >
                <span class="w-1.5 h-1.5 rounded-full" :style="{ backgroundColor: l.color ?? '#6B7280' }" />
                {{ l.title }}
              </button>
            </div>
          </div>

          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              NÃO TEM as etiquetas <span class="text-n-slate-9 font-normal">(quem tiver alguma fica de fora)</span>
            </label>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="l in accountLabels"
                :key="`exc-${l.id}`"
                class="flex items-center gap-1 text-xs px-2 py-1 rounded-full border transition-colors"
                :class="form.exclude_labels.includes(l.title)
                  ? 'bg-red-500/15 border-red-500 text-red-600 font-medium line-through'
                  : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
                @click="toggleListItem(form.exclude_labels, l.title)"
              >
                <span class="w-1.5 h-1.5 rounded-full" :style="{ backgroundColor: l.color ?? '#6B7280' }" />
                {{ l.title }}
              </button>
            </div>
          </div>
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-11 cursor-pointer">
          <input v-model="form.active" type="checkbox" class="rounded accent-n-brand" />
          Ativo
        </label>
      </div>

      <div v-if="templateStepIndex === null" class="px-5 py-4 border-t border-n-weak flex-shrink-0 flex gap-2">
        <button
          class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
          :disabled="!canSave || isSaving"
          @click="save"
        >{{ isSaving ? 'Salvando...' : 'Salvar robô' }}</button>
        <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="emit('close')">
          Cancelar
        </button>
      </div>
    </div>
  </div>
</template>
