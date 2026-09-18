<script setup>
// 🗺️ Assistente "Nova mensagem" da jornada (item 168) em 3 passos:
// 1 QUANDO (gatilho + dias + hora), 2 PARA QUEM (público, silêncio,
// aprovação, resposta esperada), 3 O QUÊ (caixa, modelo aprovado com as
// variáveis ligadas aos dados do paciente — ou texto livre — + prévia
// com um paciente real). Edita também uma mensagem existente.
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import ChipPicker from './ChipPicker.vue';
import CevicoJourneyAPI from 'dashboard/api/cevicoJourney';

const props = defineProps({
  message: { type: Object, default: null }, // null = nova
  steps: { type: Object, default: () => ({}) },
  kinds: { type: Object, default: () => ({}) },
  tokens: { type: Array, default: () => [] },
  inboxes: { type: Array, default: () => [] },
  labelOptions: { type: Array, default: () => [] },
  labelTitleOptions: { type: Array, default: () => [] },
  stageOptions: { type: Array, default: () => [] },
});
const emit = defineEmits(['close', 'saved']);

const store = useStore();
const GRADIENT = 'linear-gradient(135deg, #0F766E, #14B8A6)';

const KIND_META = {
  surgery: {
    icon: 'i-lucide-stethoscope',
    hint: 'Cirurgias agendadas no OftalmoFácil (espelho sincronizado a cada 15 min).',
    step: 'cirurgia',
  },
  appointment: {
    icon: 'i-lucide-calendar-check',
    hint: 'Consultas registradas na Agenda do sistema.',
    step: 'consulta',
  },
  stage: {
    icon: 'i-lucide-kanban',
    hint: 'Quando o card do paciente entra nesta coluna do CRM.',
    step: 'orcamento',
  },
  label: {
    icon: 'i-lucide-tag',
    hint: 'Quando o paciente recebe esta etiqueta.',
    step: 'lead',
  },
  call_missed: {
    icon: 'i-lucide-phone-missed',
    hint: 'Ligação de WhatsApp perdida que ninguém retornou (item 167).',
    step: 'lead',
  },
};
const TOKEN_HINTS = {
  nome: 'nome completo',
  primeiro_nome: 'primeiro nome',
  data: 'data (dd/mm)',
  dia_semana: 'dia da semana',
  hora: 'hora (HH:MM)',
  unidade: 'unidade / clínica',
  endereco: 'endereço da unidade',
  procedimento: 'procedimento',
  medico: 'médico',
};
// sugestão automática de variável pelo número da posição no modelo
const DEFAULT_MAP = [
  '{{primeiro_nome}}',
  '{{data}}',
  '{{hora}}',
  '{{unidade}}',
  '{{endereco}}',
];

const step = ref(1);
const isSaving = ref(false);

const form = ref({
  name: '',
  step: 'consulta',
  inbox_id: null,
  trigger: {
    kind: 'surgery',
    offset_days: -1,
    at: '10:00',
    stage_id: null,
    label: '',
  },
  audience: {
    include_label_ids: [],
    include_stage_ids: [],
    exclude_label_ids: [],
    exclude_stage_ids: [],
  },
  content: {
    mode: 'template',
    template_params: null,
    message_preview: '',
    text: '',
  },
  approval: 'auto',
  expects_reply: false,
  confirm_label: '',
  decline_alert: true,
  respect_quiet: true,
  active: true,
});

// "quando": véspera / no dia / N dias antes / N dias depois
const offsetMode = ref('before'); // before | same | after
const offsetN = ref(1);
const syncOffsetFromForm = () => {
  const d = Number(form.value.trigger.offset_days || 0);
  if (d === 0) offsetMode.value = 'same';
  else if (d < 0) {
    offsetMode.value = 'before';
    offsetN.value = Math.abs(d);
  } else {
    offsetMode.value = 'after';
    offsetN.value = d;
  }
};
watch([offsetMode, offsetN], () => {
  const n = Math.max(0, Number(offsetN.value) || 0);
  let days = n;
  if (offsetMode.value === 'same') days = 0;
  if (offsetMode.value === 'before') days = -n;
  form.value.trigger.offset_days = days;
});

// ── modelos (declarados antes do onMounted que os usa) ──
const templates = ref([]);
const tplName = ref('');
const tplVars = ref({});
const isLoadingTemplates = ref(false);
const loadTemplates = async inboxId => {
  if (!inboxId) return;
  isLoadingTemplates.value = true;
  try {
    const data = await store.dispatch('crm/fetchWhatsappTemplates', inboxId);
    templates.value = Array.isArray(data) ? data : [];
  } catch {
    templates.value = [];
  } finally {
    isLoadingTemplates.value = false;
  }
};
const braces = key => `{{${key}}}`;

onMounted(() => {
  if (props.message) {
    const m = props.message;
    form.value = {
      name: m.name || '',
      step: m.step || 'consulta',
      inbox_id: m.inbox_id || null,
      trigger: {
        kind: 'surgery',
        offset_days: -1,
        at: '10:00',
        stage_id: null,
        label: '',
        ...(m.trigger || {}),
      },
      audience: {
        include_label_ids: [],
        include_stage_ids: [],
        exclude_label_ids: [],
        exclude_stage_ids: [],
        ...(m.audience || {}),
      },
      content: {
        mode: 'template',
        template_params: null,
        message_preview: '',
        text: '',
        ...(m.content || {}),
      },
      approval: m.approval || 'auto',
      expects_reply: Boolean(m.expects_reply),
      confirm_label: m.confirm_label || '',
      decline_alert: m.decline_alert !== false,
      respect_quiet: m.respect_quiet !== false,
      active: m.active !== false,
    };
    tplName.value = m.content?.template_params?.name || '';
    tplVars.value = {
      ...(m.content?.template_params?.processed_params?.body || {}),
    };
  } else if (props.inboxes.length === 1) {
    form.value.inbox_id = props.inboxes[0].id;
  }
  syncOffsetFromForm();
  if (form.value.inbox_id) loadTemplates(form.value.inbox_id);
});

const pickKind = kind => {
  form.value.trigger.kind = kind;
  if (!props.message)
    form.value.step = KIND_META[kind]?.step || form.value.step;
  if (kind === 'call_missed') {
    offsetMode.value = 'same';
  }
};

const onInbox = () => {
  tplName.value = '';
  tplVars.value = {};
  loadTemplates(form.value.inbox_id);
};
const currentTpl = computed(
  () => templates.value.find(t => t.name === tplName.value) || null
);
const tplBody = computed(
  () => currentTpl.value?.components?.find(c => c.type === 'BODY')?.text || ''
);
const tplTokens = computed(() => {
  const out = [];
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(tplBody.value);
  while (m !== null) {
    if (!out.includes(m[1])) out.push(m[1]);
    m = re.exec(tplBody.value);
  }
  return out;
});
watch(tplName, name => {
  if (!name) return;
  // sugere as variáveis na ordem clássica (nome, data, hora…)
  const next = {};
  tplTokens.value.forEach((k, i) => {
    next[k] = tplVars.value[k] || DEFAULT_MAP[i] || '';
  });
  tplVars.value = next;
});
const insertToken = (key, token) => {
  tplVars.value = { ...tplVars.value, [key]: `{{${token}}}` };
};
const appendTokenToText = token => {
  form.value.content.text = `${form.value.content.text || ''}{{${token}}}`;
};

// prévia com o texto do modelo + variáveis (sem paciente) — rápida
const localPreview = computed(() => {
  if (form.value.content.mode === 'text') return form.value.content.text;
  let text = tplBody.value || form.value.content.message_preview || '';
  Object.entries(tplVars.value).forEach(([k, v]) => {
    text = text.replace(
      new RegExp(`\\{\\{\\s*${k}\\s*\\}\\}`, 'g'),
      v || `{{${k}}}`
    );
  });
  return text;
});

// prévia com PACIENTE REAL (próximo evento do gatilho)
const preview = ref(null);
const isPreviewing = ref(false);
const buildPayload = () => {
  const content = { ...form.value.content };
  if (content.mode === 'template') {
    const tpl = currentTpl.value;
    if (tpl) {
      content.template_params = {
        name: tpl.name,
        namespace: tpl.namespace ?? '',
        language: tpl.language,
        category: tpl.category,
        processed_params: { body: { ...tplVars.value } },
      };
      content.message_preview = tplBody.value;
    }
  }
  return {
    ...form.value,
    content,
    trigger: { ...form.value.trigger },
    audience: { ...form.value.audience },
  };
};
const runPreview = async () => {
  isPreviewing.value = true;
  try {
    const { data } = await CevicoJourneyAPI.preview(buildPayload());
    preview.value = data;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui montar a prévia.');
  } finally {
    isPreviewing.value = false;
  }
};

// ── validação por passo ──
const stepError = computed(() => {
  const t = form.value.trigger;
  if (step.value === 1) {
    if (!form.value.name.trim()) return 'Dê um nome à mensagem.';
    if (t.kind === 'stage' && !t.stage_id) return 'Escolha a coluna do CRM.';
    if (t.kind === 'label' && !t.label) return 'Escolha a etiqueta.';
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(t.at))
      return 'Hora no formato HH:MM.';
  }
  if (step.value === 3) {
    if (!form.value.inbox_id) return 'Escolha a caixa do WhatsApp.';
    if (
      form.value.content.mode === 'template' &&
      !currentTpl.value &&
      !form.value.content.template_params
    )
      return 'Escolha a mensagem modelo.';
    if (form.value.content.mode === 'text' && !form.value.content.text.trim())
      return 'Escreva o texto.';
  }
  return '';
});
const next = () => {
  if (stepError.value) return useAlert(stepError.value);
  step.value = Math.min(3, step.value + 1);
  return null;
};
const back = () => {
  step.value = Math.max(1, step.value - 1);
};

const save = async () => {
  if (stepError.value) return useAlert(stepError.value);
  isSaving.value = true;
  try {
    const payload = buildPayload();
    const { data } = props.message
      ? await CevicoJourneyAPI.update(props.message.id, payload)
      : await CevicoJourneyAPI.create(payload);
    useAlert(
      props.message
        ? 'Mensagem atualizada.'
        : 'Mensagem criada. Ela entra na fila do dia na próxima rodada (até 15 min).'
    );
    emit('saved', data);
  } catch (error) {
    const msg = error?.response?.data?.message || error?.response?.data?.error;
    useAlert(
      Array.isArray(msg) ? msg.join(' · ') : msg || 'Não consegui salvar.'
    );
  } finally {
    isSaving.value = false;
  }
  return null;
};

const inputClass =
  'w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:border-n-brand outline-none';
</script>

<template>
  <!-- clique fora NÃO fecha: são 3 passos de trabalho, fecha só no X/Cancelar -->
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-3"
  >
    <div
      class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-3xl max-h-[92vh] flex flex-col overflow-hidden"
    >
      <div class="h-1.5 w-full" :style="{ background: GRADIENT }" />
      <div
        class="flex items-center justify-between px-5 py-3 border-b border-n-weak"
      >
        <div class="flex items-center gap-2 min-w-0">
          <span class="i-lucide-route text-lg" style="color: #0f766e" />
          <h2 class="text-base font-semibold text-n-slate-12 truncate">
            {{
              message
                ? 'Editar mensagem da jornada'
                : 'Nova mensagem da jornada'
            }}
          </h2>
        </div>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
          @click="emit('close')"
        />
      </div>

      <!-- passos -->
      <div
        class="flex items-center gap-2 px-5 py-2 border-b border-n-weak text-xs"
      >
        <button
          v-for="(label, i) in ['1 · Quando', '2 · Para quem', '3 · O quê']"
          :key="i"
          class="px-3 py-1 rounded-full font-semibold transition-colors"
          :class="
            step === i + 1 ? 'text-white' : 'text-n-slate-10 bg-n-alpha-1'
          "
          :style="step === i + 1 ? { background: GRADIENT } : {}"
          @click="step = i + 1"
        >
          {{ label }}
        </button>
      </div>

      <div class="p-5 overflow-y-auto flex-1 space-y-4">
        <!-- PASSO 1: QUANDO -->
        <template v-if="step === 1">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Nome da mensagem</label
            >
            <input
              v-model="form.name"
              :class="inputClass"
              placeholder="Ex.: Confirmação de cirurgia (véspera)"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5"
              >O que dispara a mensagem</label
            >
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <button
                v-for="(label, kind) in kinds"
                :key="kind"
                type="button"
                class="text-left rounded-xl border px-3 py-2 transition-colors"
                :class="
                  form.trigger.kind === kind
                    ? 'border-teal-600 bg-teal-500/10'
                    : 'border-n-weak hover:border-teal-600/50'
                "
                @click="pickKind(kind)"
              >
                <p
                  class="text-sm font-semibold text-n-slate-12 flex items-center gap-1.5"
                >
                  <span :class="KIND_META[kind]?.icon" class="text-teal-700" />
                  {{ label }}
                </p>
                <p class="text-[11px] text-n-slate-10 mt-0.5">
                  {{ KIND_META[kind]?.hint }}
                </p>
              </button>
            </div>
          </div>
          <div v-if="form.trigger.kind === 'stage'">
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Coluna do CRM</label
            >
            <select v-model="form.trigger.stage_id" :class="inputClass">
              <option :value="null">Escolha…</option>
              <option v-for="s in stageOptions" :key="s.id" :value="s.id">
                {{ s.label }}
              </option>
            </select>
          </div>
          <div v-if="form.trigger.kind === 'label'">
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Etiqueta</label
            >
            <select v-model="form.trigger.label" :class="inputClass">
              <option value="">Escolha…</option>
              <option v-for="l in labelTitleOptions" :key="l.id" :value="l.id">
                {{ l.label }}
              </option>
            </select>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div class="sm:col-span-2">
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Quando enviar</label
              >
              <div class="flex items-center gap-2 flex-wrap">
                <select
                  v-model="offsetMode"
                  class="border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2"
                  style="margin-bottom: 0"
                >
                  <option value="before">dias antes</option>
                  <option value="same">no mesmo dia</option>
                  <option value="after">dias depois</option>
                </select>
                <input
                  v-if="offsetMode !== 'same'"
                  v-model.number="offsetN"
                  type="number"
                  min="0"
                  max="365"
                  class="w-20 border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-center"
                  style="margin-bottom: 0"
                />
                <span class="text-xs text-n-slate-10">
                  <template v-if="form.trigger.offset_days === -1"
                    >= véspera</template
                  >
                  <template v-else-if="form.trigger.offset_days === 0"
                    >= no dia</template
                  >
                </span>
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Às</label
              >
              <input
                v-model="form.trigger.at"
                type="time"
                :class="inputClass"
              />
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Etapa da jornada (onde fica pendurada na tela)</label
            >
            <select v-model="form.step" :class="inputClass">
              <option v-for="(label, key) in steps" :key="key" :value="key">
                {{ label }}
              </option>
            </select>
          </div>
        </template>

        <!-- PASSO 2: PARA QUEM -->
        <template v-if="step === 2">
          <p class="text-xs text-n-slate-10">
            Sem filtro = todo mundo que tiver o evento. Use etiquetas/colunas
            para restringir (ex.: só quem está em "Cirurgia agendada").
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Só quem tem a etiqueta</label
              >
              <ChipPicker
                v-model="form.audience.include_label_ids"
                :options="labelOptions"
                accent="green"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Só quem está na coluna</label
              >
              <ChipPicker
                v-model="form.audience.include_stage_ids"
                :options="stageOptions"
                accent="brand"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Nunca para quem tem a etiqueta</label
              >
              <ChipPicker
                v-model="form.audience.exclude_label_ids"
                :options="labelOptions"
                accent="red"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Nunca para quem está na coluna</label
              >
              <ChipPicker
                v-model="form.audience.exclude_stage_ids"
                :options="stageOptions"
                accent="red"
              />
            </div>
          </div>
          <div class="space-y-2 pt-2 border-t border-n-weak">
            <label class="flex items-start gap-3 cursor-pointer">
              <input
                v-model="form.respect_quiet"
                type="checkbox"
                class="mt-0.5"
              />
              <span class="text-sm text-n-slate-12"
                >Respeitar quem pediu silêncio
                <span class="text-xs text-n-slate-10"
                  >(etiquetas nao_perturbe / perda_*)</span
                ></span
              >
            </label>
            <label class="flex items-start gap-3 cursor-pointer">
              <input
                v-model="form.approval"
                type="checkbox"
                true-value="review"
                false-value="auto"
                class="mt-0.5"
              />
              <span class="text-sm text-n-slate-12"
                >Exigir aprovação na <b>Fila de hoje</b> antes de enviar
                <span class="text-xs text-n-slate-10"
                  >(alguém aprova ou pula cada envio)</span
                ></span
              >
            </label>
            <label class="flex items-start gap-3 cursor-pointer">
              <input
                v-model="form.expects_reply"
                type="checkbox"
                class="mt-0.5"
              />
              <span class="text-sm text-n-slate-12"
                >Espera resposta do paciente
                <span class="text-xs text-n-slate-10"
                  >("confirmo/sim" confirma; "não/remarcar" avisa o Radar)</span
                ></span
              >
            </label>
            <div
              v-if="form.expects_reply"
              class="pl-7 grid grid-cols-1 sm:grid-cols-2 gap-3"
            >
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1"
                  >Etiqueta ao confirmar (opcional)</label
                >
                <select v-model="form.confirm_label" :class="inputClass">
                  <option value="">Nenhuma</option>
                  <option
                    v-for="l in labelTitleOptions"
                    :key="l.id"
                    :value="l.id"
                  >
                    {{ l.label }}
                  </option>
                </select>
              </div>
              <label class="flex items-start gap-3 cursor-pointer pt-5">
                <input
                  v-model="form.decline_alert"
                  type="checkbox"
                  class="mt-0.5"
                />
                <span class="text-sm text-n-slate-12"
                  >"Não vou" vira aviso no Radar</span
                >
              </label>
            </div>
          </div>
        </template>

        <!-- PASSO 3: O QUÊ -->
        <template v-if="step === 3">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Caixa do WhatsApp</label
              >
              <select
                v-model="form.inbox_id"
                :class="inputClass"
                @change="onInbox"
              >
                <option :value="null">Escolha…</option>
                <option v-for="i in inboxes" :key="i.id" :value="i.id">
                  {{ i.name }}
                </option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Tipo</label
              >
              <div
                class="flex gap-1 bg-n-solid-2 border border-n-weak rounded-lg p-1"
              >
                <button
                  v-for="m in [
                    ['template', 'Modelo aprovado'],
                    ['text', 'Texto livre'],
                  ]"
                  :key="m[0]"
                  type="button"
                  class="flex-1 text-xs px-2 py-1.5 rounded-md font-medium"
                  :class="
                    form.content.mode === m[0]
                      ? 'text-white'
                      : 'text-n-slate-11'
                  "
                  :style="
                    form.content.mode === m[0] ? { background: GRADIENT } : {}
                  "
                  @click="form.content.mode = m[0]"
                >
                  {{ m[1] }}
                </button>
              </div>
              <p class="text-[11px] text-n-slate-10 mt-1">
                <template v-if="form.content.mode === 'template'"
                  >Chega mesmo com a janela de 24h fechada.</template
                >
                <template v-else
                  >Só chega se o paciente falou com a clínica nas últimas
                  24h.</template
                >
              </p>
            </div>
          </div>

          <template v-if="form.content.mode === 'template'">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Mensagem modelo</label
              >
              <select
                v-model="tplName"
                :class="inputClass"
                :disabled="!form.inbox_id || isLoadingTemplates"
              >
                <option value="">
                  {{
                    isLoadingTemplates
                      ? 'Carregando modelos…'
                      : form.content.template_params?.name && !tplName
                        ? `Modelo salva: ${form.content.template_params.name}`
                        : 'Escolha o modelo…'
                  }}
                </option>
                <option
                  v-for="t in templates"
                  :key="`${t.name}-${t.language}`"
                  :value="t.name"
                >
                  {{ t.name }} · {{ t.language }} · {{ t.category }}
                </option>
              </select>
            </div>
            <div v-if="tplTokens.length" class="space-y-2">
              <p class="text-xs font-medium text-n-slate-11">
                Variáveis do modelo — clique num dado do paciente ou escreva
              </p>
              <div
                v-for="k in tplTokens"
                :key="k"
                class="flex items-center gap-2 flex-wrap"
              >
                <span class="text-xs font-mono text-n-slate-10 w-10">
                  {{ braces(k) }}
                </span>
                <input
                  v-model="tplVars[k]"
                  :class="inputClass"
                  class="!w-56 !mb-0"
                  style="margin-bottom: 0"
                />
                <div class="flex gap-1 flex-wrap">
                  <button
                    v-for="tok in tokens"
                    :key="tok"
                    type="button"
                    class="text-[10px] px-1.5 py-0.5 rounded-full border border-n-weak text-n-slate-11 hover:border-teal-600 hover:text-teal-700"
                    :title="TOKEN_HINTS[tok]"
                    @click="insertToken(k, tok)"
                  >
                    {{ tok }}
                  </button>
                </div>
              </div>
            </div>
          </template>
          <template v-else>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Texto</label
              >
              <textarea
                v-model="form.content.text"
                rows="5"
                :class="inputClass"
                placeholder="Olá {{primeiro_nome}}! Sua consulta é {{data}} às {{hora}} na {{unidade}}."
              />
              <div class="flex gap-1 flex-wrap mt-1">
                <button
                  v-for="tok in tokens"
                  :key="tok"
                  type="button"
                  class="text-[10px] px-1.5 py-0.5 rounded-full border border-n-weak text-n-slate-11 hover:border-teal-600 hover:text-teal-700"
                  :title="TOKEN_HINTS[tok]"
                  @click="appendTokenToText(tok)"
                >
                  + {{ tok }}
                </button>
              </div>
            </div>
          </template>

          <!-- prévia -->
          <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-3">
            <div class="flex items-center justify-between gap-2 mb-1.5">
              <p
                class="text-xs font-semibold text-n-slate-11 flex items-center gap-1.5"
              >
                <span class="i-lucide-eye" /> Prévia
              </p>
              <button
                type="button"
                class="text-[11px] font-semibold text-teal-700 hover:underline disabled:opacity-50"
                :disabled="isPreviewing"
                @click="runPreview"
              >
                {{
                  isPreviewing
                    ? 'Buscando paciente…'
                    : 'Ver com um paciente real'
                }}
              </button>
            </div>
            <div
              class="rounded-2xl rounded-tl-sm bg-[#DCF8C6] dark:bg-teal-900/40 text-n-slate-12 text-sm px-3 py-2 whitespace-pre-wrap max-w-md"
            >
              {{ preview?.found ? preview.text : localPreview || '…' }}
            </div>
            <p v-if="preview" class="text-[11px] text-n-slate-10 mt-1.5">
              <template v-if="preview.found">
                Exemplo real: <b>{{ preview.contact?.name }}</b>
                <span v-if="preview.variables?.data">
                  · {{ preview.variables.data }}
                  {{ preview.variables.hora }}</span
                >
                <span v-if="preview.variables?.unidade">
                  · {{ preview.variables.unidade }}</span
                >
              </template>
              <template v-else>{{ preview.message }}</template>
            </p>
          </div>
        </template>
      </div>

      <footer
        class="flex items-center justify-between gap-2 px-5 py-3 border-t border-n-weak"
      >
        <button
          class="text-sm text-n-slate-10 hover:text-n-slate-12"
          @click="emit('close')"
        >
          Cancelar
        </button>
        <div class="flex items-center gap-2">
          <button
            v-if="step > 1"
            class="px-3 py-1.5 text-sm border border-n-weak rounded-lg text-n-slate-11"
            @click="back"
          >
            Voltar
          </button>
          <button
            v-if="step < 3"
            class="px-4 py-1.5 text-sm text-white rounded-lg font-semibold"
            :style="{ background: GRADIENT }"
            @click="next"
          >
            Continuar
          </button>
          <button
            v-else
            class="px-4 py-1.5 text-sm text-white rounded-lg font-semibold disabled:opacity-50"
            :style="{ background: GRADIENT }"
            :disabled="isSaving"
            @click="save"
          >
            {{ isSaving ? 'Salvando…' : message ? 'Salvar' : 'Criar mensagem' }}
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>
