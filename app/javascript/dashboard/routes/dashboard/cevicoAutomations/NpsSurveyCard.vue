<script setup>
// 📊 item 256 (26/09): PESQUISA DE SATISFAÇÃO (NPS) pós-cirurgia como card do
// kit no grupo "Atendimento ao paciente" — substitui o "AGENTE DE NPS" do N8N.
// Envio: N dias depois da cirurgia realizada, com o dia POR TIPO de cirurgia;
// resposta: lida sem IA (etiqueta + nota + tarefa nas notas baixas) e a
// conversa segue com o Atendente de Pós-operatório. Config em
// agenda_config.nps_survey (Crm::NpsSurvey).
import { computed, ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  view: { type: String, default: 'cards' },
  open: { type: Boolean, default: false },
  opening: { type: Boolean, default: false },
  isAdmin: { type: Boolean, default: false },
});
const emit = defineEmits(['toggle', 'open-agent']);

const store = useStore();
const settings = useMapGetter('crm/getSettings');
const inboxes = useMapGetter('inboxes/getInboxes');

const META = {
  title: 'Pesquisa de satisfação (NPS)',
  tag: 'WhatsApp · pós-cirurgia',
  icon: 'i-lucide-smile-plus',
  color: '#7C3AED',
  gradient: 'linear-gradient(135deg, #6D28D9, #A78BFA)',
  description:
    'Alguns dias depois da cirurgia realizada (você escolhe quantos para cada tipo: catarata, refrativa, outras), manda a mensagem modelo da Meta com os botões de nota. O toque na nota é registrado sozinho (etiqueta nps-*, painel de satisfação) e nota de 1 a 6 vira tarefa no Meu Painel. A conversa continua com o Atendente de Pós-operatório: Google para quem deu 9–10, "o que faltou" para 7–8, formulário e equipe para as notas baixas — e ele segue tirando as outras dúvidas.',
};
const cardVars = {
  '--cv': META.color,
  '--cv-rgb': '124 58 237',
  '--cv-deep': '#6D28D9',
  '--cv-deep-rgb': '109 40 217',
  '--cv-grad': META.gradient,
  '--cv-grad-2': META.gradient,
  '--cv-grad-3': META.gradient,
};
const BAND_META = {
  '9-10': { label: '9 a 10', color: '#059669' },
  '7-8': { label: '7 a 8', color: '#65A30D' },
  '5-6': { label: '5 a 6', color: '#CA8A04' },
  '3-4': { label: '3 a 4', color: '#EA580C' },
  '1-2': { label: '1 a 2', color: '#DC2626' },
};
const SUGGESTED_VARS = { 1: '{{nome}}' };

// ── estado ────────────────────────────────────────────────────────────────
const form = ref(null);
const dirty = ref(false);
const saving = ref(false);
const toggling = ref(false);
const templates = ref([]);
const loadedInbox = ref(null);
let uid = 0;

const whatsappInboxes = computed(() =>
  (inboxes.value || []).filter(i => i.channel_type === 'Channel::Whatsapp')
);
const state = computed(() => settings.value?.nps_survey_state || {});
const posOp = computed(
  () => settings.value?.ai?.agents?.atendente_pos_op || {}
);

const hydrate = s => {
  const c = s?.nps_survey || {};
  form.value = {
    enabled: c.enabled === true,
    mode: c.mode === 'live' ? 'live' : 'shadow',
    hour: c.hour ?? 10,
    inbox_id: c.inbox_id || null,
    tplName: c.template_params?.name || '',
    vars: { ...(c.template_params?.processed_params?.body || {}) },
    savedTpl: c.template_params || null,
    preview: c.message_preview || '',
    google_review_url: c.google_review_url || '',
    complaint_form_url: c.complaint_form_url || '',
    min_interval_days: c.min_interval_days || 60,
    rules: (c.rules || []).map(r => {
      uid += 1;
      return {
        uid,
        key: r.key,
        label: r.label,
        days_after: r.days_after,
        enabled: r.enabled !== false,
        keywordsText: (r.keywords || []).join(', '),
      };
    }),
  };
  if (form.value.inbox_id) loadTemplates(form.value.inbox_id);
  dirty.value = false;
};

const loadTemplates = async inboxId => {
  if (!inboxId || loadedInbox.value === inboxId) return;
  loadedInbox.value = inboxId;
  try {
    const data = await store.dispatch('crm/fetchWhatsappTemplates', inboxId);
    templates.value = Array.isArray(data) ? data : [];
  } catch {
    templates.value = [];
  }
};

watch(
  settings,
  s => {
    if (!dirty.value) hydrate(s);
  },
  { immediate: true }
);
const touch = () => {
  dirty.value = true;
};

// ── modelo ────────────────────────────────────────────────────────────────
const tpl = computed(
  () => templates.value.find(t => t.name === form.value?.tplName) || null
);
const body = computed(
  () =>
    tpl.value?.components?.find(c => c.type === 'BODY')?.text ||
    form.value?.preview ||
    ''
);
const tokens = computed(() => {
  const found = new Set();
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(body.value);
  while (m !== null) {
    found.add(m[1]);
    m = re.exec(body.value);
  }
  return [...found];
});
const buttons = computed(
  () =>
    tpl.value?.components
      ?.find(c => c.type === 'BUTTONS')
      ?.buttons?.map(b => b.text) || []
);
const onPickTemplate = () => {
  form.value.vars = {};
  tokens.value.forEach(t => {
    form.value.vars[t] = SUGGESTED_VARS[t] || '';
  });
  touch();
};
const onInbox = () => {
  form.value.tplName = '';
  form.value.vars = {};
  loadedInbox.value = null;
  loadTemplates(form.value.inbox_id);
  touch();
};

// ── tipos de cirurgia ─────────────────────────────────────────────────────
const addRule = () => {
  uid += 1;
  form.value.rules.push({
    uid,
    key: '',
    label: '',
    days_after: 15,
    enabled: true,
    keywordsText: '',
  });
  touch();
};
const removeRule = rule => {
  form.value.rules = form.value.rules.filter(r => r.uid !== rule.uid);
  touch();
};
const hasCatchAll = computed(() =>
  (form.value?.rules || []).some(r => !r.keywordsText.trim())
);

// ── salvar ────────────────────────────────────────────────────────────────
const payload = (overrides = {}) => {
  const f = form.value;
  let templateParams = null;
  if (tpl.value) {
    templateParams = {
      name: tpl.value.name,
      namespace: tpl.value.namespace ?? '',
      language: tpl.value.language,
      category: tpl.value.category,
      processed_params: { body: { ...f.vars } },
    };
  } else if (f.tplName && f.savedTpl?.name === f.tplName) {
    templateParams = {
      ...f.savedTpl,
      processed_params: { body: { ...f.vars } },
    };
  }
  return {
    enabled: f.enabled,
    mode: f.mode,
    hour: f.hour,
    inbox_id: f.inbox_id,
    template_params: templateParams,
    message_preview:
      tpl.value?.components?.find(c => c.type === 'BODY')?.text || f.preview,
    google_review_url: f.google_review_url,
    complaint_form_url: f.complaint_form_url,
    min_interval_days: f.min_interval_days,
    rules: f.rules
      .filter(r => r.label.trim())
      .map(r => ({
        key: r.key,
        label: r.label.trim(),
        days_after: Number(r.days_after) || 15,
        enabled: r.enabled,
        keywords: r.keywordsText
          .split(',')
          .map(w => w.trim())
          .filter(Boolean),
      })),
    ...overrides,
  };
};
const problem = computed(() => {
  const f = form.value;
  if (!f) return '';
  if (!f.inbox_id) return 'escolha a caixa do WhatsApp';
  if (!f.tplName) return 'escolha a mensagem modelo';
  if (!f.rules.some(r => r.enabled && r.label.trim()))
    return 'deixe pelo menos um tipo de cirurgia ligado';
  return '';
});
const save = async (overrides = {}) => {
  const next = { ...payload(), ...overrides };
  if (next.enabled && next.mode === 'live' && problem.value) {
    useAlert(`Para ligar ao vivo: ${problem.value}.`);
    return false;
  }
  saving.value = true;
  try {
    await CrmAPI.saveNpsSurvey(next);
    dirty.value = false;
    await store.dispatch('crm/fetchSettings');
    return true;
  } catch {
    useAlert('Não consegui salvar a pesquisa. Tente de novo.');
    return false;
  } finally {
    saving.value = false;
  }
};
const saveClick = async () => {
  if (await save()) useAlert('Pesquisa de satisfação salva ✓');
};
const toggleMaster = async () => {
  toggling.value = true;
  const next = !form.value.enabled;
  if (await save({ enabled: next })) {
    useAlert(
      next
        ? `✅ Pesquisa de satisfação LIGADA (${form.value.mode === 'live' ? 'ao vivo' : 'em sombra'}).`
        : '⏹ Pesquisa de satisfação DESLIGADA.'
    );
  }
  toggling.value = false;
};
const discard = () => hydrate(settings.value);

// ── números ───────────────────────────────────────────────────────────────
const answers = computed(() => state.value.answers || []);
const bandCounts = computed(() => {
  const out = { '9-10': 0, '7-8': 0, '5-6': 0, '3-4': 0, '1-2': 0 };
  answers.value.forEach(a => {
    if (out[a.band] !== undefined) out[a.band] += 1;
  });
  return out;
});
const satisfaction = computed(() =>
  answers.value.length
    ? Math.round((bandCounts.value['9-10'] / answers.value.length) * 100)
    : null
);
const statusChip = computed(() => {
  if (!form.value?.enabled) return { label: 'Desligado', tone: 'cv-slate' };
  return form.value.mode === 'live'
    ? { label: 'Ao vivo', tone: 'cv-green' }
    : { label: 'Em sombra', tone: 'cv-slate' };
});
const posOpWarning = computed(() => {
  if (posOp.value.enabled !== true)
    return 'O Atendente de Pós-operatório está desligado: as notas são gravadas, mas ninguém continua a conversa sozinho.';
  if (
    form.value?.inbox_id &&
    !(posOp.value.inbox_ids || [])
      .map(Number)
      .includes(Number(form.value.inbox_id))
  )
    return 'Marque a caixa desta pesquisa nas caixas do Atendente de Pós-operatório, senão ele não responde quem tocou na nota.';
  return '';
});
const fmtDate = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      })
    : '';
const compact = computed(() => props.view === 'cards' && !props.open);
</script>

<template>
  <div
    id="cv-agent-nps_survey"
    class="cv-block flex flex-col"
    :class="[
      view === 'cards' && open ? 'cv-agent-open' : '',
      opening ? 'cv-agent-opening' : '',
    ]"
    :style="cardVars"
  >
    <div
      class="h-1 w-full flex-shrink-0"
      :style="{ background: META.gradient }"
    />
    <div
      v-if="form"
      :class="compact ? 'p-4 flex-1 flex flex-col' : 'p-5 sm:p-6'"
    >
      <!-- 🃏 compacto -->
      <div
        v-if="compact"
        class="flex-1 flex flex-col gap-2.5 cursor-pointer select-none"
        @click="emit('toggle')"
      >
        <div class="flex items-start justify-between gap-2">
          <span class="cv-icon cv-icon-xl"
            ><span :class="META.icon" class="text-lg"
          /></span>
          <div class="flex flex-col items-end gap-1" @click.stop>
            <button
              class="cv-switch cv-switch-lg"
              :class="form.enabled ? 'cv-switch-on' : ''"
              :disabled="toggling || !isAdmin"
              :aria-pressed="form.enabled"
              @click="toggleMaster"
            />
            <span class="text-[10px] text-n-slate-9">{{
              toggling ? 'salvando…' : form.enabled ? 'Ligado' : 'Desligado'
            }}</span>
          </div>
        </div>
        <div>
          <p class="text-base font-bold text-n-slate-12 leading-tight">
            {{ META.title }}
          </p>
          <div class="flex items-center gap-1.5 flex-wrap mt-1.5">
            <span class="cv-chip">{{ META.tag }}</span>
            <span class="cv-chip" :class="statusChip.tone"
              >● {{ statusChip.label }}</span
            >
          </div>
        </div>
        <p class="text-xs text-n-slate-10 leading-relaxed line-clamp-3">
          {{ META.description }}
        </p>
        <div class="mt-auto flex items-center gap-2 flex-wrap pt-1">
          <span class="cv-chip cv-slate"
            >{{ answers.length }} resposta(s){{
              satisfaction !== null ? ` · ${satisfaction}% nota 9–10` : ''
            }}</span
          >
          <button class="cv-btn cv-btn-sm ml-auto" @click.stop="emit('toggle')">
            <span class="i-lucide-maximize-2 text-xs" /> Abrir
          </button>
        </div>
      </div>

      <!-- cabeçalho completo -->
      <div
        v-else
        class="flex items-start gap-3 cursor-pointer select-none"
        :class="open ? 'mb-4' : ''"
        @click="emit('toggle')"
      >
        <span class="cv-icon cv-icon-xl"
          ><span :class="META.icon" class="text-lg"
        /></span>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <p class="text-base font-bold text-n-slate-12 leading-tight">
              {{ META.title }}
            </p>
            <span class="cv-chip">{{ META.tag }}</span>
            <span class="cv-chip" :class="statusChip.tone"
              >● {{ statusChip.label }}</span
            >
            <span v-if="dirty" class="cv-chip cv-amber"
              >📝 alterações não salvas</span
            >
          </div>
          <p
            class="text-xs text-n-slate-10 mt-1 leading-relaxed"
            :class="open ? '' : 'line-clamp-2'"
          >
            {{ META.description }}
          </p>
        </div>
        <div class="flex flex-col items-end gap-1 flex-shrink-0" @click.stop>
          <button
            class="cv-switch cv-switch-lg"
            :class="form.enabled ? 'cv-switch-on' : ''"
            :disabled="toggling || !isAdmin"
            :aria-pressed="form.enabled"
            @click="toggleMaster"
          />
          <span class="text-[10px] text-n-slate-9">{{
            toggling ? 'salvando…' : form.enabled ? 'Ligado' : 'Desligado'
          }}</span>
        </div>
        <span
          class="i-lucide-chevron-down text-n-slate-9 text-lg mt-2 flex-shrink-0 transition-transform duration-200"
          :class="open ? 'rotate-180' : ''"
        />
      </div>

      <div
        v-if="open"
        class="cevico-agent-body space-y-4"
        :class="!isAdmin ? 'pointer-events-none opacity-80' : ''"
      >
        <!-- situação -->
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div
            class="cv-stat px-3 py-2"
            :class="form.enabled ? 'cv-green' : ''"
          >
            <p class="text-[10px] text-n-slate-10">Situação</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ statusChip.label }}
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Última rodada</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ (state.sent || []).length }}
              <span class="text-[10px] font-normal text-n-slate-9">{{
                state.mode === 'live' ? 'enviada(s)' : 'receberia(m)'
              }}</span>
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Respostas</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ answers.length }}
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Nota 9–10</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ satisfaction !== null ? `${satisfaction}%` : '—' }}
            </p>
          </div>
        </div>

        <div
          v-if="posOpWarning"
          class="cv-sub p-3 text-[11px] text-amber-800 dark:text-amber-300 flex items-start gap-2"
        >
          <span class="i-lucide-triangle-alert text-sm mt-px" />
          <span class="flex-1">{{ posOpWarning }}</span>
          <button
            class="cv-btn cv-btn-sm"
            @click="emit('open-agent', 'atendente_pos_op')"
          >
            Abrir o Pós-operatório
          </button>
        </div>

        <div
          class="cv-sub p-3.5 text-[11px] text-n-slate-11 leading-relaxed space-y-1.5"
        >
          <p>
            <b>📅 Quem recebe:</b> quem tem cirurgia <b>realizada</b> na Agenda
            (presença marcada ou concluída — as do Oftalmofácil da CEVICO entram
            sozinhas) há exatamente N dias, conforme o tipo. 1 por cirurgia;
            nunca 2 pesquisas para a mesma pessoa dentro do intervalo mínimo
            (segundo olho).
          </p>
          <p>
            <b>👆 Resposta:</b> o toque na nota vira etiqueta (nps-9-10 …
            nps-1-2), aparece no painel de satisfação e fica na conversa. Nota
            de 1 a 6 abre tarefa no Meu Painel (1 a 4 urgente, com aviso no
            Radar).
          </p>
          <p>
            <b>🗣️ Conversa:</b> o Atendente de Pós-operatório continua daqui
            (Google, "o que faltou", formulário) e responde as outras dúvidas do
            paciente.
          </p>
        </div>

        <!-- envio -->
        <div class="cv-sub p-4 space-y-3">
          <p class="cv-label !mb-0">Envio</p>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Modo</label
              >
              <div class="cv-seg cv-seg-sm cv-green">
                <button
                  class="cv-seg-item"
                  :class="form.mode !== 'live' ? 'cv-seg-on' : ''"
                  title="Só lista quem receberia"
                  @click="
                    form.mode = 'shadow';
                    touch();
                  "
                >
                  🕶️ Sombra
                </button>
                <button
                  class="cv-seg-item"
                  :class="form.mode === 'live' ? 'cv-seg-on' : ''"
                  title="Manda de verdade — desligue o N8N"
                  @click="
                    form.mode = 'live';
                    touch();
                  "
                >
                  🟢 Ao vivo
                </button>
              </div>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Hora do envio</label
              >
              <select
                v-model.number="form.hour"
                class="cv-input w-full text-sm"
                style="margin-bottom: 0"
                @change="touch"
              >
                <option v-for="h in 24" :key="'h' + h" :value="h - 1">
                  {{ String(h - 1).padStart(2, '0') }}h
                </option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Intervalo mínimo (dias)</label
              >
              <input
                v-model.number="form.min_interval_days"
                type="number"
                min="7"
                max="365"
                class="cv-input w-full text-sm"
                style="margin-bottom: 0"
                @input="touch"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Caixa do WhatsApp</label
              >
              <select
                v-model.number="form.inbox_id"
                class="cv-input w-full text-sm"
                style="margin-bottom: 0"
                @change="onInbox"
              >
                <option :value="null">Escolha…</option>
                <option
                  v-for="i in whatsappInboxes"
                  :key="'ib' + i.id"
                  :value="i.id"
                >
                  {{ i.name }}
                </option>
              </select>
            </div>
          </div>
          <div v-if="form.inbox_id" class="space-y-1.5">
            <label class="text-xs font-medium text-n-slate-11 block"
              >Mensagem modelo da Meta (com os botões de nota)</label
            >
            <select
              v-model="form.tplName"
              class="cv-input w-full sm:w-96 text-sm"
              style="margin-bottom: 0"
              @change="onPickTemplate"
            >
              <option value="">— escolha —</option>
              <option
                v-if="
                  form.tplName && !templates.some(t => t.name === form.tplName)
                "
                :value="form.tplName"
              >
                {{ form.tplName }} (salva)
              </option>
              <option
                v-for="t in templates"
                :key="t.name + t.language"
                :value="t.name"
              >
                {{ t.name }} ({{ t.language }})
              </option>
            </select>
            <template v-if="form.tplName">
              <p
                class="text-[11px] text-n-slate-10 whitespace-pre-wrap bg-n-alpha-1 rounded-lg px-2 py-1.5 max-h-40 overflow-auto"
              >
                {{ body || 'prévia indisponível' }}
              </p>
              <div v-if="buttons.length" class="flex flex-wrap gap-1">
                <span v-for="b in buttons" :key="b" class="cv-chip">{{
                  b
                }}</span>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                <input
                  v-for="token in tokens"
                  :key="'v' + token"
                  v-model="form.vars[token]"
                  class="cv-input !h-8 text-xs font-mono"
                  style="margin-bottom: 0"
                  :placeholder="`{{${token}}} — ex.: {{nome}}`"
                  @input="touch"
                />
              </div>
              <p class="text-[10px] text-n-slate-9">
                Variáveis: <code v-pre>{{ nome }}</code> primeiro nome ·
                <code v-pre>{{ procedimento }}</code> ·
                <code v-pre>{{ data_cirurgia }}</code> ·
                <code v-pre>{{ dias }}</code> dias desde a cirurgia ·
                <code v-pre>{{ contact.name }}</code
                >. Os botões do modelo precisam dizer a faixa ("9 a 10", "7 a
                8"…) — é ela que o sistema lê.
              </p>
            </template>
          </div>
        </div>

        <!-- quando, por tipo de cirurgia -->
        <div class="cv-sub p-4 space-y-2">
          <div class="flex items-center gap-2">
            <p class="cv-label !mb-0 flex-1">
              Quando enviar, por tipo de cirurgia
            </p>
            <button class="cv-chip cv-chip-lg" @click="addRule">
              <span class="i-lucide-plus text-[10px]" /> Novo tipo
            </button>
          </div>
          <div
            v-for="rule in form.rules"
            :key="rule.uid"
            class="grid grid-cols-12 gap-2 items-center"
          >
            <button
              class="cv-switch col-span-1"
              :class="rule.enabled ? 'cv-switch-on' : ''"
              :title="rule.enabled ? 'Desligar este tipo' : 'Ligar este tipo'"
              @click="
                rule.enabled = !rule.enabled;
                touch();
              "
            />
            <input
              v-model="rule.label"
              class="cv-input col-span-3 !h-8 text-xs"
              style="margin-bottom: 0"
              placeholder="Nome (ex.: Catarata)"
              @input="touch"
            />
            <div class="col-span-3 flex items-center gap-1">
              <input
                v-model.number="rule.days_after"
                type="number"
                min="1"
                max="365"
                class="cv-input !h-8 text-xs w-16"
                style="margin-bottom: 0"
                @input="touch"
              />
              <span class="text-[11px] text-n-slate-10">dias depois</span>
            </div>
            <input
              v-model="rule.keywordsText"
              class="cv-input col-span-4 !h-8 text-xs"
              style="margin-bottom: 0"
              placeholder="palavras do procedimento (vazio = todas as outras)"
              @input="touch"
            />
            <button
              class="col-span-1 text-n-slate-9 hover:text-red-600"
              title="Tirar este tipo"
              @click="removeRule(rule)"
            >
              <span class="i-lucide-trash-2 text-sm" />
            </button>
          </div>
          <p class="text-[10px] text-n-slate-9">
            O tipo sai das palavras do procedimento na Agenda (ex.: "faco",
            "catarata", "lio" = Catarata; "lasik", "prk" = Refrativa). O tipo
            SEM palavras pega todas as outras cirurgias{{
              hasCatchAll
                ? ''
                : ' — hoje não há nenhum: cirurgia que não casar com nenhuma palavra não recebe'
            }}.
          </p>
        </div>

        <!-- links -->
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Link de avaliação no Google (nota 9–10)</label
            >
            <input
              v-model="form.google_review_url"
              class="cv-input w-full text-sm"
              style="margin-bottom: 0"
              placeholder="https://g.page/r/…/review"
              @input="touch"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Formulário de relato (notas baixas)</label
            >
            <input
              v-model="form.complaint_form_url"
              class="cv-input w-full text-sm"
              style="margin-bottom: 0"
              placeholder="https://forms.gle/…"
              @input="touch"
            />
          </div>
        </div>

        <!-- última rodada + respostas -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-2">
          <div
            class="rounded-lg bg-n-alpha-1 p-2.5 text-[11px] text-n-slate-11 space-y-0.5"
          >
            <p class="font-semibold">
              Última rodada
              {{
                state.last_run_at
                  ? `(${state.mode === 'live' ? 'ao vivo' : 'sombra'}) · ${fmtDate(state.last_run_at)}`
                  : '— ainda não rodou'
              }}
            </p>
            <p
              v-for="e in (state.sent || []).slice(0, 30)"
              :key="'s' + e.task_id"
            >
              ✓ {{ e.name }} · {{ e.rule }} · cirurgia {{ e.surgery }} · …{{
                e.phone_tail
              }}
            </p>
            <p
              v-for="e in (state.skipped || []).slice(0, 30)"
              :key="'k' + e.task_id"
              class="text-amber-700 dark:text-amber-400"
            >
              ↷ {{ e.name }} · {{ e.rule || '—' }} · cirurgia {{ e.surgery }} —
              {{ e.why }}
            </p>
          </div>
          <div
            class="rounded-lg bg-n-alpha-1 p-2.5 text-[11px] text-n-slate-11 space-y-1"
          >
            <p class="font-semibold">Respostas recentes</p>
            <div class="flex flex-wrap gap-1">
              <span
                v-for="(meta, band) in BAND_META"
                :key="band"
                class="cv-chip"
                :style="{ '--cv-rgb': '0 0 0', color: meta.color }"
                >{{ meta.label }}: <b>{{ bandCounts[band] }}</b></span
              >
            </div>
            <p v-for="a in answers.slice(0, 20)" :key="a.at + a.contact_id">
              <span
                class="font-bold"
                :style="{ color: BAND_META[a.band]?.color }"
                >{{ BAND_META[a.band]?.label }}</span
              >
              · {{ a.name }} · {{ fmtDate(a.at) }}
            </p>
            <p v-if="!answers.length" class="text-n-slate-9">
              Ninguém respondeu ainda.
            </p>
          </div>
        </div>

        <div v-if="isAdmin" class="flex items-center gap-2 flex-wrap pt-1">
          <button
            class="cv-btn"
            :disabled="saving || !dirty"
            @click="saveClick"
          >
            <Spinner v-if="saving" :size="14" />
            <span v-else class="i-lucide-save text-sm" /> Salvar pesquisa
          </button>
          <button
            v-if="dirty"
            class="cv-btn cv-btn-ghost"
            :disabled="saving"
            @click="discard"
          >
            Descartar
          </button>
          <span v-if="problem" class="text-[11px] text-amber-700"
            >⚠️ {{ problem }}</span
          >
        </div>
      </div>
    </div>
  </div>
</template>
