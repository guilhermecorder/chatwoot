<script setup>
// 📣 item 381 (03/11): PLANO DE ENVIO EM FATIAS da Reativação de fim de ano.
// Em vez de mandar para todo mundo de uma vez, o plano manda X mensagens por
// dia, divididas por coluna do CRM em porcentagem, pela caixa por onde cada
// pessoa chegou, só no horário de atendimento, até a base inteira ter
// recebido. Cada pessoa recebe uma vez. Quem edita campanhas configura,
// ativa, pausa e manda a fatia da hora; o resto do time vê o progresso.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';

defineProps({
  canEdit: { type: Boolean, default: false },
});

const store = useStore();
const pipelines = useMapGetter('crm/getPipelines');

const NAME_VAR = '{{contact.name}}';
const FRENTES = [
  { key: 'padrao', label: 'Modelo padrão (refrativa)', required: true },
  { key: 'lentes', label: 'Lentes', required: false },
  { key: 'catarata', label: 'Catarata', required: false },
];
// as 6 colunas da campanha, na ordem de prioridade (item 380)
const SUGGESTED = [
  { key: 'nao_fechou', label: 'Não Fechou Ainda', share: 30 },
  { key: 'indicacao', label: 'Indicação de Cirurgia', share: 20 },
  { key: 'nao_foi', label: 'Não Foi a Consulta', share: 15 },
  { key: 'desmarcou', label: 'Desmarcou a Consulta', share: 10 },
  { key: 'orcamento', label: 'Envio de Orçamento', share: 15 },
  { key: 'novos', label: 'Novos Contatos', share: 10 },
];
const CAP_PRESETS = [100, 200, 300, 500];
const HOURS_FROM = Array.from({ length: 16 }, (_, i) => i + 6); // 6h…21h
const HOURS_TO = Array.from({ length: 16 }, (_, i) => i + 7); // 7h…22h
const STATUS = {
  none: { label: 'Sem plano', tone: 'cv-slate', icon: 'i-lucide-circle-dashed' },
  draft: { label: 'Rascunho', tone: 'cv-slate', icon: 'i-lucide-pencil-line' },
  processing: { label: 'Ativo', tone: 'cv-green', icon: 'i-lucide-play' },
  paused: { label: 'Pausado', tone: 'cv-amber', icon: 'i-lucide-pause' },
  completed: { label: 'Concluído', tone: 'cv-blue', icon: 'i-lucide-check' },
};

const payload = ref(null); // o GET inteiro (status, stats, simulação salva…)
const plan = ref(null); // a configuração em edição
const savedJson = ref(''); // para saber se há alteração não salva
const simulation = ref(null); // a última simulação (salva ou da tela)
const simulatedDirty = ref(false); // a simulação é do que está na tela?
const isLoading = ref(true);
const busy = ref(''); // 'simulate' | 'save' | 'activate' | 'pause' | 'run'
const confirming = ref(''); // 'activate' | 'run'

// ── carregar ────────────────────────────────────────────────────────────
const clone = v => JSON.parse(JSON.stringify(v));
const applyPayload = res => {
  payload.value = res;
  plan.value = clone(res.config || {});
  if (!Array.isArray(plan.value.slices)) plan.value.slices = [];
  plan.value.slices.forEach(s => {
    if (!s.templates || typeof s.templates !== 'object') s.templates = {};
  });
  // caixa padrão 0 (ainda sem escolha) = a primeira caixa WhatsApp oficial
  const boxes = res.inboxes || [];
  if (!boxes.some(i => i.id === plan.value.default_inbox_id)) {
    plan.value.default_inbox_id = boxes[0]?.id || 0;
  }
  savedJson.value = JSON.stringify(plan.value);
  simulation.value = res.simulation || null;
  simulatedDirty.value = false;
};
const load = async () => {
  isLoading.value = true;
  try {
    const { data: res } = await CrmAPI.getReactivationPlan();
    applyPayload(res);
    if (!(pipelines.value || []).length) {
      await store.dispatch('crm/fetchPipelines').catch(() => {});
    }
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para carregar o plano de envio.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

// ── estado do plano ─────────────────────────────────────────────────────
const exists = computed(() => Boolean(payload.value?.exists));
const status = computed(() => (exists.value ? payload.value?.status || 'draft' : 'none'));
const statusMeta = computed(() => STATUS[status.value] || STATUS.none);
const isActive = computed(() => status.value === 'processing');
const stats = computed(() => payload.value?.stats || {});
const inboxes = computed(() => payload.value?.inboxes || []);
const inboxName = id => inboxes.value.find(i => String(i.id) === String(id))?.name || `caixa ${id}`;
const isDirty = computed(() => plan.value && JSON.stringify(plan.value) !== savedJson.value);
const touch = () => {
  simulatedDirty.value = true;
};

// ── colunas do funil da casa (o que tem "Orçamento") ────────────────────
const allStages = computed(() =>
  (pipelines.value || []).flatMap(p =>
    (p.stages ?? []).map(s => ({ ...s, pipeline_name: p.name, pipeline_id: p.id }))
  )
);
const homeStages = computed(() => {
  const home = allStages.value.find(s => /or[çc]amento/i.test(s.name))?.pipeline_id;
  return home ? allStages.value.filter(s => s.pipeline_id === home) : allStages.value;
});
const stageName = id => allStages.value.find(s => s.id === Number(id))?.name || '';
const findStageByName = label => {
  const wanted = label.trim().toLowerCase();
  return (
    homeStages.value.find(s => s.name.trim().toLowerCase() === wanted) ||
    homeStages.value.find(s => s.name.toLowerCase().includes(wanted))
  );
};

// ── fatias ──────────────────────────────────────────────────────────────
const slices = computed(() => plan.value?.slices || []);
const shareSum = computed(() => slices.value.reduce((acc, s) => acc + (Number(s.share) || 0), 0));
const suggestSlices = () => {
  plan.value.slices = SUGGESTED.map(sug => {
    const current = slices.value.find(s => s.key === sug.key);
    return {
      key: sug.key,
      stage_id: findStageByName(sug.label)?.id || current?.stage_id || 0,
      share: sug.share,
      templates: current?.templates || {},
      label: sug.label,
    };
  });
  touch();
};
const addSlice = () => {
  plan.value.slices.push({
    key: `f${Date.now().toString(36)}`,
    stage_id: 0,
    share: 0,
    templates: {},
  });
  touch();
};
const removeSlice = idx => {
  plan.value.slices.splice(idx, 1);
  touch();
};
const sliceSim = slice => (simulation.value?.slices || []).find(r => r.key === slice.key) || null;
const sliceLabel = slice => {
  const sug = SUGGESTED.find(s => s.key === slice.key);
  return sug?.label || slice.label || stageName(slice.stage_id) || 'Fatia';
};

// ── modelos da caixa padrão ─────────────────────────────────────────────
const defaultInbox = computed(() =>
  inboxes.value.find(i => String(i.id) === String(plan.value?.default_inbox_id)) || inboxes.value[0] || null
);
const templates = computed(() => defaultInbox.value?.templates || []);
const templateBody = tpl => tpl?.components?.find(c => c.type === 'BODY')?.text || '';
const tokensOf = text => {
  const out = [];
  const re = /\{\{\s*(\d+)\s*\}\}/g;
  let m = re.exec(text);
  while (m !== null) {
    if (!out.includes(m[1])) out.push(m[1]);
    m = re.exec(text);
  }
  return out;
};
const tokenLabel = token => `{{${token}}}`;
const tplName = (slice, frente) => slice.templates?.[frente]?.template_params?.name || '';
const tplObj = (slice, frente) => templates.value.find(t => t.name === tplName(slice, frente)) || null;
const tplTokens = (slice, frente) => tokensOf(slice.templates?.[frente]?.message_preview || '');
const tplVar = (slice, frente, token) =>
  slice.templates?.[frente]?.template_params?.processed_params?.body?.[token] ?? '';
// igual ao buildTemplateParams do CrmCampaigns.vue
const setTemplate = (slice, frente, name) => {
  const tpl = templates.value.find(t => t.name === name);
  if (!tpl) {
    const next = { ...slice.templates };
    delete next[frente];
    slice.templates = next;
    touch();
    return;
  }
  const body = templateBody(tpl);
  const vars = {};
  tokensOf(body).forEach((token, i) => {
    vars[token] = i === 0 ? NAME_VAR : '';
  });
  slice.templates = {
    ...slice.templates,
    [frente]: {
      template_params: {
        name: tpl.name,
        namespace: tpl.namespace ?? '',
        language: tpl.language,
        category: tpl.category,
        processed_params: { body: vars },
      },
      message_preview: body,
    },
  };
  touch();
};
const setVar = (slice, frente, token, value) => {
  const t = slice.templates?.[frente];
  if (!t) return;
  t.template_params.processed_params.body = {
    ...(t.template_params.processed_params.body || {}),
    [token]: value,
  };
  touch();
};
const tplMissingVar = (slice, frente) =>
  Boolean(slice.templates?.[frente]) &&
  tplTokens(slice, frente).some(token => !String(tplVar(slice, frente, token)).trim());
// prévia: {{n}} vira o valor digitado; {{contact.name}} vira o chip "nome"
const previewParts = (slice, frente) => {
  const t = slice.templates?.[frente];
  if (!t) return [];
  const text = String(t.message_preview || '').replace(/\{\{\s*(\d+)\s*\}\}/g, (full, token) => {
    const v = String(tplVar(slice, frente, token) || '');
    return v.trim() ? v : full;
  });
  return text
    .split(/(\{\{contact\.name\}\})/g)
    .filter(Boolean)
    .map((part, i) => ({ key: i, chip: part === NAME_VAR, text: part === NAME_VAR ? '{{nome}}' : part }));
};

// ── prontidão ───────────────────────────────────────────────────────────
const readySlices = computed(() =>
  slices.value.filter(s => Number(s.stage_id) > 0 && Number(s.share) > 0 && s.templates?.padrao)
);
const canActivate = computed(
  () => exists.value && !isDirty.value && shareSum.value === 100 && readySlices.value.length > 0
);
const activateHint = computed(() => {
  if (!exists.value) return 'Salve o plano antes de ativar.';
  if (isDirty.value) return 'Salve as alterações antes de ativar.';
  if (shareSum.value !== 100) return 'As porcentagens precisam somar 100.';
  if (!readySlices.value.length) return 'Defina pelo menos uma fatia com coluna, porcentagem e modelo padrão.';
  return '';
});

// ── números do cabeçalho ────────────────────────────────────────────────
const sentToday = computed(() => Number(payload.value?.sent_today || 0));
const dailyCap = computed(() => Number(payload.value?.config?.daily_cap || 0));
const totalSent = computed(() => Number(stats.value.sent || 0));
const totalPlanned = computed(() => totalSent.value + Number(payload.value?.simulation?.total_pool || 0));
const pct = (a, b) => (b > 0 ? Math.min(100, Math.round((a / b) * 100)) : 0);
const spHour = () =>
  Number(new Date().toLocaleString('en-US', { timeZone: 'America/Sao_Paulo', hour: 'numeric', hour12: false })) % 24;
// quanto sai se mandar a fatia de 1 hora agora: o que falta no dia / horas que faltam
const runNowEstimate = computed(() => {
  const cfg = payload.value?.config || {};
  const remaining = Math.max(Number(cfg.daily_cap || 0) - sentToday.value, 0);
  const hoursLeft = Math.max(Number(cfg.hour_to || 0) - spHour(), 1);
  return Math.ceil(remaining / hoursLeft);
});
const formatWhen = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};
const formatDay = ymd => {
  const [, m, d] = String(ymd).split('-');
  return d && m ? `${d}/${m}` : ymd;
};
const warnings = computed(() => (stats.value.warnings || []).filter(Boolean));
const lastDays = computed(() =>
  Object.entries(stats.value.days || {})
    .sort(([a], [b]) => (a < b ? 1 : -1))
    .slice(0, 7)
    .map(([day, d]) => ({
      day,
      sent: Number(d?.sent || 0),
      inboxes: Object.entries(d?.inboxes || {}).map(([id, n]) => ({ id, name: inboxName(id), n: Number(n) })),
    }))
);
const simSummary = computed(() => {
  if (!simulation.value) return '';
  const total = Number(simulation.value.total_pool || 0);
  const days = simulation.value.days_max_slice || simulation.value.days_total;
  const people = `${total} ${total === 1 ? 'pessoa' : 'pessoas'} ao todo`;
  return days ? `${people} · ~${days} ${days === 1 ? 'dia útil' : 'dias úteis'} para acabar` : people;
});
const ritmoSentence = computed(() => {
  const c = payload.value?.config;
  if (!c) return '';
  const bits = [`${c.daily_cap} por dia`, `${c.hour_from}h–${c.hour_to}h`];
  bits.push(c.weekdays_only ? 'só dias úteis' : 'todos os dias');
  if (c.route_by_origin) bits.push('pela caixa de origem');
  return bits.join(' · ');
});

// ── ações ───────────────────────────────────────────────────────────────
const fail = (err, fallback) => useAlert(err?.response?.data?.error || fallback);
const simulate = async () => {
  busy.value = 'simulate';
  try {
    const { data: res } = await CrmAPI.simulateReactivationPlan(plan.value);
    simulation.value = res;
    simulatedDirty.value = false;
  } catch (err) {
    fail(err, 'Não deu para simular.');
  } finally {
    busy.value = '';
  }
};
const save = async () => {
  busy.value = 'save';
  try {
    const { data: res } = await CrmAPI.saveReactivationPlan(plan.value);
    applyPayload(res);
    useAlert('Plano salvo.');
  } catch (err) {
    fail(err, 'Não deu para salvar o plano.');
  } finally {
    busy.value = '';
  }
};
const activate = async () => {
  busy.value = 'activate';
  confirming.value = '';
  try {
    const { data: res } = await CrmAPI.activateReactivationPlan();
    applyPayload(res);
    useAlert('Plano ativo: o robô começa na próxima hora cheia dentro do horário.');
  } catch (err) {
    fail(err, 'Não deu para ativar.');
  } finally {
    busy.value = '';
  }
};
const pause = async () => {
  busy.value = 'pause';
  try {
    const { data: res } = await CrmAPI.pauseReactivationPlan();
    applyPayload(res);
    useAlert('Plano pausado.');
  } catch (err) {
    fail(err, 'Não deu para pausar.');
  } finally {
    busy.value = '';
  }
};
const runNow = async () => {
  busy.value = 'run';
  confirming.value = '';
  try {
    const { data: res } = await CrmAPI.runReactivationPlanNow();
    applyPayload(res);
    const n = Number(res.sent_now || 0);
    useAlert(n ? `${n} ${n === 1 ? 'mensagem enviada' : 'mensagens enviadas'} agora.` : 'Nada saiu agora — veja o motivo no cabeçalho.');
  } catch (err) {
    fail(err, 'Não deu para mandar agora.');
  } finally {
    busy.value = '';
  }
};
</script>

<template>
  <section class="cv-block p-6 sm:p-10 mb-12 plano">
    <!-- cabeçalho -->
    <div class="flex items-start gap-4 flex-wrap">
      <span class="cv-icon cv-icon-lg">
        <span class="i-lucide-calendar-clock text-lg" />
      </span>
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2 flex-wrap mb-1">
          <span class="plano-status" :class="statusMeta.tone">
            <span :class="statusMeta.icon" class="text-xs" />
            {{ statusMeta.label }}
          </span>
          <span v-if="payload?.window_now" class="cv-chip">
            <span class="i-lucide-clock text-xs" />
            {{ payload.window_now }}
          </span>
          <span v-if="canEdit && isDirty" class="cv-chip cv-amber">
            <span class="i-lucide-pencil text-xs" />
            alterações não salvas
          </span>
        </div>
        <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight">
          Plano de envio em fatias
        </h2>
        <p class="text-sm text-n-slate-11 mt-1 leading-relaxed">
          Em vez de mandar para todo mundo de uma vez, o plano manda X mensagens por dia,
          divididas por coluna do CRM em porcentagem, pela caixa por onde cada pessoa chegou,
          só no horário de atendimento, até a base inteira ter recebido. Cada pessoa recebe uma vez.
        </p>
        <p v-if="!canEdit && ritmoSentence" class="text-xs text-n-slate-10 mt-1">{{ ritmoSentence }}</p>
      </div>
    </div>

    <div v-if="isLoading" class="mt-6 text-sm text-n-slate-10">Carregando o plano…</div>

    <template v-else>
      <!-- números do dia -->
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mt-8">
        <div class="cv-stat p-3">
          <p class="cv-label">Hoje</p>
          <p class="text-2xl font-bold text-n-slate-12 tabular-nums leading-tight">
            {{ sentToday }}
            <span class="text-sm font-semibold text-n-slate-10">de {{ dailyCap }}</span>
          </p>
          <div class="plano-bar mt-2"><span :style="{ width: `${pct(sentToday, dailyCap)}%` }" /></div>
          <p class="text-[11px] text-n-slate-10 mt-1">enviadas no dia</p>
        </div>
        <div class="cv-stat p-3">
          <p class="cv-label">No plano</p>
          <p class="text-2xl font-bold text-n-slate-12 tabular-nums leading-tight">
            {{ totalSent }}
            <span class="text-sm font-semibold text-n-slate-10">de {{ totalPlanned }}</span>
          </p>
          <div class="plano-bar mt-2"><span :style="{ width: `${pct(totalSent, totalPlanned)}%` }" /></div>
          <p class="text-[11px] text-n-slate-10 mt-1">pessoas que já receberam</p>
        </div>
        <div class="cv-stat p-3">
          <p class="cv-label">Última rodada</p>
          <p class="text-base font-bold text-n-slate-12 leading-tight mt-1">
            {{ stats.last_run_at ? formatWhen(stats.last_run_at) : '—' }}
          </p>
          <p class="text-[11px] text-n-slate-10 mt-1">
            <template v-if="stats.last_run_at">{{ stats.last_run_sent || 0 }} enviada(s)</template>
            <template v-else>ainda não rodou</template>
          </p>
        </div>
        <div class="cv-stat p-3">
          <p class="cv-label">Última conferência</p>
          <p class="text-base font-bold text-n-slate-12 leading-tight mt-1">
            {{ stats.last_check_at ? formatWhen(stats.last_check_at) : '—' }}
          </p>
          <p class="text-[11px] mt-1" :class="stats.last_skip ? 'text-amber-700 dark:text-amber-300' : 'text-n-slate-10'">
            {{ stats.last_skip ? `pulou: ${stats.last_skip}` : 'o robô passa de hora em hora' }}
          </p>
        </div>
      </div>

      <!-- avisos -->
      <div v-if="stats.last_error || warnings.length" class="mt-3 space-y-1">
        <p v-if="stats.last_error" class="plano-note plano-note-red">
          <span class="i-lucide-triangle-alert text-sm flex-shrink-0" />
          {{ stats.last_error }}
        </p>
        <p v-for="(w, i) in warnings" :key="i" class="plano-note plano-note-amber">
          <span class="i-lucide-info text-sm flex-shrink-0" />
          {{ w }}
        </p>
      </div>

      <!-- ═══ quem edita: a configuração ═══ -->
      <template v-if="canEdit && plan">
        <!-- ritmo -->
        <div class="cv-sub p-6 mt-8">
          <div class="flex items-center gap-2 mb-4">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-gauge text-sm" /></span>
            <h3 class="text-sm font-bold text-n-slate-12">Ritmo</h3>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
            <div>
              <p class="cv-label mb-1">Mensagens por dia</p>
              <input
                v-model.number="plan.daily_cap"
                type="number"
                min="10"
                max="2000"
                class="cv-input w-full"
                @input="touch"
              />
              <div class="flex gap-1 mt-1.5 flex-wrap">
                <button
                  v-for="n in CAP_PRESETS"
                  :key="n"
                  class="cv-chip"
                  :class="{ 'cv-chip-on': plan.daily_cap === n }"
                  @click="plan.daily_cap = n; touch()"
                >
                  {{ n }}
                </button>
              </div>
            </div>
            <div>
              <p class="cv-label mb-1">Horário</p>
              <div class="flex items-center gap-2">
                <span class="text-xs text-n-slate-11">das</span>
                <select v-model.number="plan.hour_from" class="cv-input flex-1" @change="touch">
                  <option v-for="h in HOURS_FROM" :key="h" :value="h">{{ h }}h</option>
                </select>
                <span class="text-xs text-n-slate-11">até</span>
                <select v-model.number="plan.hour_to" class="cv-input flex-1" @change="touch">
                  <option v-for="h in HOURS_TO" :key="h" :value="h" :disabled="h <= plan.hour_from">{{ h }}h</option>
                </select>
              </div>
              <label class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer select-none mt-2">
                <input v-model="plan.weekdays_only" type="checkbox" class="rounded border-n-weak" @change="touch" />
                só dias úteis
              </label>
            </div>
            <div>
              <p class="cv-label mb-1">Teto por caixa por dia</p>
              <input
                v-model.number="plan.inbox_daily_cap"
                type="number"
                min="1"
                max="5000"
                class="cv-input w-full"
                @input="touch"
              />
              <p class="text-[11px] text-n-slate-10 mt-1">cada número do WhatsApp manda no máximo isto por dia</p>
            </div>
            <div>
              <p class="cv-label mb-1">Ordem</p>
              <select v-model="plan.order" class="cv-input w-full" @change="touch">
                <option value="recent">mais recentes primeiro</option>
                <option value="oldest">mais antigos primeiro</option>
              </select>
              <div class="flex items-center gap-2 text-xs text-n-slate-11 mt-2 flex-wrap">
                pausar a hora se houver mais de
                <input
                  v-model.number="plan.max_open_conversations"
                  type="number"
                  min="0"
                  max="100000"
                  class="cv-input !h-8 w-20 text-xs"
                  @input="touch"
                />
                conversas abertas <span class="text-n-slate-10">(0 = ignora)</span>
              </div>
            </div>
          </div>

          <p class="cv-label mt-5 mb-2">Fica de fora</p>
          <div class="flex flex-col sm:flex-row sm:flex-wrap gap-x-6 gap-y-2">
            <div class="flex items-center gap-2 text-xs text-n-slate-11">
              quem conversou com a clínica nas últimas
              <input
                v-model.number="plan.quiet_hours"
                type="number"
                min="0"
                max="720"
                class="cv-input !h-8 w-16 text-xs"
                @input="touch"
              />
              horas
            </div>
            <div class="flex items-center gap-2 text-xs text-n-slate-11">
              quem chegou há menos de
              <input
                v-model.number="plan.min_age_days"
                type="number"
                min="0"
                max="365"
                class="cv-input !h-8 w-16 text-xs"
                @input="touch"
              />
              dias
            </div>
            <label class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer select-none">
              <input v-model="plan.skip_future_appointment" type="checkbox" class="rounded border-n-weak" @change="touch" />
              quem já tem consulta ou cirurgia marcada
            </label>
          </div>
        </div>

        <!-- caixas -->
        <div class="cv-sub p-6 mt-6">
          <div class="flex items-center gap-2 mb-4">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-inbox text-sm" /></span>
            <h3 class="text-sm font-bold text-n-slate-12">Caixas</h3>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 items-start">
            <div>
              <p class="cv-label mb-1">Caixa padrão</p>
              <select v-model.number="plan.default_inbox_id" class="cv-input w-full" @change="touch">
                <option v-if="!inboxes.length" :value="0">nenhuma caixa WhatsApp oficial</option>
                <option v-for="i in inboxes" :key="i.id" :value="i.id">
                  {{ i.name }} · {{ i.templates.length }} modelo(s) aprovado(s)
                </option>
              </select>
            </div>
            <div class="md:pt-5">
              <label class="flex items-start gap-2 text-xs text-n-slate-11 cursor-pointer select-none">
                <input v-model="plan.route_by_origin" type="checkbox" class="rounded border-n-weak mt-0.5" @change="touch" />
                <span>Mandar pela caixa por onde a pessoa chegou (Instagram manda para quem veio do Instagram)</span>
              </label>
              <p class="text-[11px] text-n-slate-10 mt-2 leading-relaxed">
                O modelo precisa existir aprovado em cada caixa; quando não existir, vai pela caixa padrão.
              </p>
            </div>
          </div>
        </div>

        <!-- fatias -->
        <div class="cv-sub p-6 mt-6">
          <div class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-pie-chart text-sm" /></span>
            <h3 class="text-sm font-bold text-n-slate-12">Fatias</h3>
            <span
              class="cv-chip tabular-nums"
              :class="shareSum === 100 ? 'cv-green' : 'cv-red'"
              :title="shareSum === 100 ? 'As fatias somam 100%' : 'As fatias precisam somar 100%'"
            >
              <span :class="shareSum === 100 ? 'i-lucide-check' : 'i-lucide-alert-circle'" class="text-xs" />
              soma {{ shareSum }}%
            </span>
            <span v-if="simSummary" class="cv-chip" :class="{ 'opacity-60': simulatedDirty }">
              <span class="i-lucide-users text-xs" />
              {{ simSummary }}{{ simulatedDirty ? ' (simule de novo)' : '' }}
            </span>
            <div class="ml-auto flex gap-2 flex-wrap">
              <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="suggestSlices">
                <span class="i-lucide-wand-sparkles text-sm" />
                Sugerir fatias
              </button>
              <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="addSlice">
                <span class="i-lucide-plus text-sm" />
                fatia
              </button>
            </div>
          </div>
          <p v-if="!homeStages.length" class="plano-note plano-note-amber mb-3">
            <span class="i-lucide-info text-sm flex-shrink-0" />
            Nenhuma coluna do funil carregada ainda.
          </p>

          <p v-if="!slices.length" class="text-sm text-n-slate-10 py-4 text-center">
            Nenhuma fatia ainda. Clique em “Sugerir fatias” para começar com as 6 colunas da campanha.
          </p>

          <div v-else class="space-y-3">
            <article
              v-for="(slice, idx) in slices"
              :key="slice.key"
              class="plano-fatia"
            >
              <!-- linha 1: prioridade, coluna, %, números -->
              <div class="flex items-center gap-2 flex-wrap">
                <span class="plano-prio">{{ idx + 1 }}</span>
                <select
                  :value="slice.stage_id || 0"
                  class="cv-input !h-9 min-w-0 flex-1 basis-48"
                  :class="{ 'plano-input-warn': !slice.stage_id }"
                  @change="slice.stage_id = Number($event.target.value); touch()"
                >
                  <option :value="0">— escolha a coluna —</option>
                  <option v-for="s in homeStages" :key="s.id" :value="s.id">{{ s.name }}</option>
                </select>
                <div class="flex items-center gap-1">
                  <input
                    v-model.number="slice.share"
                    type="number"
                    min="0"
                    max="100"
                    class="cv-input !h-9 w-20 text-right tabular-nums"
                    @input="touch"
                  />
                  <span class="text-sm text-n-slate-11">%</span>
                </div>
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger cv-iconbtn"
                  title="Remover esta fatia"
                  @click="removeSlice(idx)"
                >
                  <span class="i-lucide-x text-sm" />
                </button>
              </div>
              <p v-if="!slice.stage_id" class="plano-note plano-note-amber mt-2">
                <span class="i-lucide-info text-sm flex-shrink-0" />
                Coluna “{{ sliceLabel(slice) }}” não encontrada no funil: escolha uma ou remova a fatia.
              </p>

              <!-- números da fatia -->
              <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-3" :class="{ 'opacity-60': simulatedDirty }">
                <div class="plano-num">
                  <b>{{ sliceSim(slice)?.pool ?? '—' }}</b>
                  <span>pessoas hoje</span>
                </div>
                <div class="plano-num">
                  <b>{{ sliceSim(slice)?.per_day ?? '—' }}</b>
                  <span>por dia</span>
                </div>
                <div class="plano-num">
                  <b>{{ sliceSim(slice)?.days ?? '—' }}</b>
                  <span>dias para acabar</span>
                </div>
                <div class="plano-num">
                  <b>{{ sliceSim(slice)?.sent ?? 0 }}</b>
                  <span>já enviadas</span>
                </div>
              </div>

              <!-- modelos -->
              <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mt-4">
                <div v-for="f in FRENTES" :key="f.key" class="min-w-0">
                  <p class="cv-label mb-1">
                    {{ f.label }}
                    <span v-if="f.required" class="text-red-600">*</span>
                    <span v-else class="normal-case tracking-normal opacity-70">(opcional)</span>
                  </p>
                  <select
                    :value="tplName(slice, f.key)"
                    class="cv-input !h-9 w-full"
                    :class="{ 'plano-input-warn': f.required && !tplName(slice, f.key) }"
                    :disabled="!templates.length"
                    @change="setTemplate(slice, f.key, $event.target.value)"
                  >
                    <option value="">{{ f.required ? '— escolha o modelo —' : '— usa o padrão —' }}</option>
                    <option v-for="t in templates" :key="t.name" :value="t.name">
                      {{ t.name }} ({{ t.language }})
                    </option>
                  </select>
                  <template v-if="slice.templates?.[f.key]">
                    <p v-if="!tplObj(slice, f.key)" class="plano-note plano-note-amber mt-1">
                      <span class="i-lucide-info text-sm flex-shrink-0" />
                      este modelo não está aprovado na caixa padrão
                    </p>
                    <div v-for="token in tplTokens(slice, f.key)" :key="token" class="flex items-center gap-2 mt-1.5">
                      <span class="cv-chip font-mono flex-shrink-0">{{ tokenLabel(token) }}</span>
                      <input
                        :value="tplVar(slice, f.key, token)"
                        class="cv-input !h-8 w-full text-xs font-mono"
                        :placeholder="token === '1' ? NAME_VAR : 'texto fixo'"
                        @input="setVar(slice, f.key, token, $event.target.value)"
                      />
                    </div>
                    <p v-if="tplMissingVar(slice, f.key)" class="text-[11px] text-red-600 mt-1">
                      preencha todas as variáveis do modelo
                    </p>
                    <div class="plano-bubble mt-2">
                      <!-- numa linha só de propósito: o balão é pre-wrap -->
                      <span v-for="part in previewParts(slice, f.key)" :key="part.key" :class="part.chip ? 'plano-var' : ''">{{ part.text }}</span>
                    </div>
                  </template>
                </div>
              </div>
            </article>
          </div>
        </div>

        <!-- botões -->
        <div class="flex items-center gap-2 flex-wrap mt-5">
          <button class="cv-btn cv-btn-ghost" :disabled="busy !== ''" @click="simulate">
            <span class="i-lucide-calculator text-sm" />
            {{ busy === 'simulate' ? 'Simulando…' : 'Simular' }}
          </button>
          <button class="cv-btn" :disabled="busy !== '' || !inboxes.length" @click="save">
            <span class="i-lucide-save text-sm" />
            {{ busy === 'save' ? 'Salvando…' : 'Salvar plano' }}
          </button>

          <template v-if="isActive">
            <button class="cv-btn cv-btn-ghost cv-amber" :disabled="busy !== ''" @click="pause">
              <span class="i-lucide-pause text-sm" />
              {{ busy === 'pause' ? 'Pausando…' : 'Pausar' }}
            </button>
            <template v-if="confirming === 'run'">
              <span class="text-xs text-n-slate-11">
                Vai sair até ~{{ runNowEstimate }} {{ runNowEstimate === 1 ? 'mensagem' : 'mensagens' }} agora.
              </span>
              <button class="cv-btn cv-btn-sm" :disabled="busy !== ''" @click="runNow">
                {{ busy === 'run' ? 'Mandando…' : 'Sim, mandar' }}
              </button>
              <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="confirming = ''">Não</button>
            </template>
            <button v-else class="cv-btn cv-btn-ghost" :disabled="busy !== ''" @click="confirming = 'run'">
              <span class="i-lucide-send text-sm" />
              Mandar a fatia de 1 hora agora
            </button>
          </template>

          <template v-else>
            <template v-if="confirming === 'activate'">
              <span class="text-xs text-n-slate-11">
                O robô começa na próxima hora cheia dentro do horário.
              </span>
              <button class="cv-btn cv-btn-sm cv-green" :disabled="busy !== ''" @click="activate">
                {{ busy === 'activate' ? 'Ativando…' : status === 'paused' ? 'Sim, retomar' : 'Sim, ativar' }}
              </button>
              <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="confirming = ''">Não</button>
            </template>
            <button
              v-else
              class="cv-btn cv-green"
              :disabled="busy !== '' || !canActivate"
              :title="activateHint"
              @click="confirming = 'activate'"
            >
              <span :class="status === 'paused' ? 'i-lucide-play' : 'i-lucide-rocket'" class="text-sm" />
              {{ status === 'paused' ? 'Retomar' : 'Ativar' }}
            </button>
            <span v-if="activateHint && confirming !== 'activate'" class="text-[11px] text-n-slate-10">
              {{ activateHint }}
            </span>
          </template>
        </div>
      </template>

      <!-- ═══ progresso (todo mundo vê) ═══ -->
      <div v-if="exists" class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-8">
        <div class="cv-sub p-4">
          <div class="flex items-center gap-2 mb-4">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-list-checks text-sm" /></span>
            <h3 class="text-sm font-bold text-n-slate-12">Por fatia</h3>
          </div>
          <p v-if="!(payload.simulation?.slices || []).length" class="text-xs text-n-slate-10">
            Nenhuma fatia salva ainda.
          </p>
          <div v-for="(row, i) in payload.simulation?.slices || []" :key="row.key" class="mb-3 last:mb-0">
            <div class="flex items-center gap-2 text-xs flex-wrap">
              <span class="plano-prio plano-prio-sm">{{ i + 1 }}</span>
              <span class="font-semibold text-n-slate-12 truncate">{{ row.stage_name || 'coluna removida' }}</span>
              <span class="text-n-slate-10">{{ row.share }}%</span>
              <span class="ml-auto tabular-nums text-n-slate-11">
                {{ row.sent }} de {{ row.sent + row.pool }}
                <span class="text-n-slate-10">· {{ pct(row.sent, row.sent + row.pool) }}%</span>
              </span>
            </div>
            <div class="plano-bar mt-1.5"><span :style="{ width: `${pct(row.sent, row.sent + row.pool)}%` }" /></div>
          </div>
        </div>

        <div class="cv-sub p-4">
          <div class="flex items-center gap-2 mb-4">
            <span class="cv-icon cv-icon-sm"><span class="i-lucide-calendar-days text-sm" /></span>
            <h3 class="text-sm font-bold text-n-slate-12">Por dia</h3>
            <span class="text-[11px] text-n-slate-10">últimos 7 dias com envio</span>
          </div>
          <p v-if="!lastDays.length" class="text-xs text-n-slate-10">Nenhum envio ainda.</p>
          <div v-for="d in lastDays" :key="d.day" class="mb-3 last:mb-0">
            <div class="flex items-center gap-2 text-xs flex-wrap">
              <span class="font-semibold text-n-slate-12 tabular-nums">{{ formatDay(d.day) }}</span>
              <span class="text-n-slate-10 truncate">
                <template v-for="(ib, j) in d.inboxes" :key="ib.id">{{ j ? ' · ' : '' }}{{ ib.name }} {{ ib.n }}</template>
              </span>
              <span class="ml-auto tabular-nums text-n-slate-11">{{ d.sent }} de {{ dailyCap }}</span>
            </div>
            <div class="plano-bar mt-1.5"><span :style="{ width: `${pct(d.sent, dailyCap)}%` }" /></div>
          </div>
        </div>
      </div>
    </template>
  </section>
</template>

<style scoped>
/* chip de status: a mesma peça do botão do kit, parada e no tom do estado */
.plano-status {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  height: 26px;
  padding: 0 11px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 800;
  letter-spacing: 0.02em;
  text-transform: uppercase;
  color: #fff;
  background: var(--cv-grad);
  border: 1px solid rgba(255, 255, 255, 0.35);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.4),
    0 6px 14px -6px rgb(var(--cv-deep-rgb) / 0.7);
}
/* número da prioridade */
.plano-prio {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 800;
  color: #fff;
  background: var(--cv-grad);
  border: 1px solid rgba(255, 255, 255, 0.35);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.4),
    0 6px 14px -6px rgb(var(--cv-deep-rgb) / 0.7);
  flex-shrink: 0;
}
.plano-prio-sm {
  width: 20px;
  height: 20px;
  font-size: 10px;
}
/* cartão de uma fatia */
.plano-fatia {
  padding: 12px;
  border-radius: 14px;
  background: rgb(var(--cv-rgb) / 0.05);
  border: 1px solid rgb(var(--cv-rgb) / 0.18);
}
.dark .plano-fatia {
  background: rgba(255, 255, 255, 0.03);
  border-color: rgb(var(--cv-rgb) / 0.3);
}
.plano-num {
  display: flex;
  flex-direction: column;
  padding: 6px 10px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.55);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
}
.dark .plano-num {
  background: rgba(255, 255, 255, 0.04);
}
.plano-num b {
  font-size: 16px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
}
.plano-num span {
  font-size: 10px;
  opacity: 0.7;
}
/* barra de progresso no tom do bloco */
.plano-bar {
  height: 8px;
  border-radius: 9999px;
  background: rgb(var(--cv-rgb) / 0.14);
  overflow: hidden;
}
.plano-bar > span {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: var(--cv-grad);
  transition: width 0.4s ease;
}
/* campo que precisa de atenção */
.plano-input-warn {
  border-color: rgba(217, 119, 6, 0.6) !important;
}
/* avisos em texto */
.plano-note {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 10px;
  font-size: 11px;
  line-height: 1.4;
}
.plano-note-amber {
  color: #92400e;
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.35);
}
.plano-note-red {
  color: #991b1b;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.35);
}
.dark .plano-note-amber {
  color: #fcd34d;
}
.dark .plano-note-red {
  color: #fca5a5;
}
/* balão de prévia com cara de WhatsApp */
.plano-bubble {
  padding: 8px 10px;
  border-radius: 12px;
  border-top-left-radius: 4px;
  font-size: 12px;
  line-height: 1.5;
  color: #111b21;
  background: #dcf8c6;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.dark .plano-bubble {
  color: #e9edef;
  background: #005c4b;
}
.plano-var {
  display: inline-block;
  padding: 0 6px;
  border-radius: 9999px;
  font-size: 10px;
  font-weight: 700;
  line-height: 16px;
  color: #065f46;
  background: rgba(5, 150, 105, 0.16);
  border: 1px solid rgba(5, 150, 105, 0.35);
}
.dark .plano-var {
  color: #a7f3d0;
  background: rgba(16, 185, 129, 0.22);
  border-color: rgba(16, 185, 129, 0.45);
}
</style>
