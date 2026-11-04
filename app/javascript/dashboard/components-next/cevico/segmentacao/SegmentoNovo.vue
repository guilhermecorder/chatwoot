<script setup>
// 🧪 item 383: SEGMENTO NOVO — em 4 passos: de onde vem a base (colunas +
// peneira), tipo e tamanho (teste com até 5 mensagens × escala com uma),
// as mensagens (modelos aprovados da Meta, A–E) e o ritmo de envio. Antes
// de reservar, "Calcular quem entra" mostra a peneira regra a regra e a
// frase por extenso do que vai acontecer. Reservar NÃO manda nada: só
// separa as pessoas (o envio começa no cartão do segmento, com "Iniciar").
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import {
  NAME_VAR, buildVariant, variantTokens, variantVar, setVariantVar, variantMissingVar, previewParts,
  stepSize, perDay, paceSentence, fmtInt, people,
} from './segmentacaoHelpers';

const props = defineProps({
  base: { type: Object, default: null }, // { stages, inboxes, defaults, steps, max_variants }
  canEdit: { type: Boolean, default: false },
});
const emit = defineEmits(['created', 'update:stageIds']);

const KEYS = ['A', 'B', 'C', 'D', 'E'];
const SIZE_PRESETS = [100, 200, 300, 500, 1000];
const PER_HOUR_PRESETS = [60, 120, 150, 300];
const CAP_PRESETS = [100, 300, 500, 1000];
const QUIET_OPTIONS = [
  { value: 0, label: 'não tirar' },
  { value: 12, label: '12 h' },
  { value: 24, label: '24 h' },
  { value: 48, label: '48 h' },
];
const CAMPAIGN_OPTIONS = [
  { value: 0, label: 'não tirar' },
  { value: 15, label: '15 dias' },
  { value: 30, label: '30 dias' },
  { value: 60, label: '60 dias' },
  { value: 90, label: '90 dias' },
];
const PROCEDURES = [
  { key: 'todas', label: 'Todas as frentes' },
  { key: 'refrativa', label: 'Refrativa' },
  { key: 'lentes', label: 'Lentes' },
  { key: 'catarata', label: 'Catarata' },
];
const ORDERS = [
  { key: 'random', label: 'Sorteio', hint: 'aleatório — o jeito certo de testar' },
  { key: 'recent', label: 'Mais recentes', hint: 'quem se moveu de coluna há menos tempo' },
  { key: 'oldest', label: 'Mais antigos', hint: 'quem está parado há mais tempo' },
];
const HOURS_FROM = Array.from({ length: 16 }, (_, i) => i + 6);
const HOURS_TO = Array.from({ length: 16 }, (_, i) => i + 7);

const clone = v => JSON.parse(JSON.stringify(v));
const name = ref('');
const kind = ref('teste');
const source = ref({ stage_ids: [], procedure: 'todas', size: 100, order: 'random', min_age_days: 3, quiet_hours: 24,
  skip_future_appointment: true, exclude_campaign_days: 30 });
const pace = ref({ per_hour: 150, step_minutes: 60, hour_from: 9, hour_to: 18, weekdays_only: true, daily_cap: 1000,
  inbox_daily_cap: 300, default_inbox_id: 0, route_by_origin: true });
// uma vaga por mensagem: { data: variante montada (ou null) }
const slots = ref([{ data: null }, { data: null }]);
const preview = ref(null);
const previewDirty = ref(true);
const busy = ref('');
const confirming = ref(false);


const touch = () => {
  previewDirty.value = true;
  confirming.value = false;
};
const stages = computed(() => props.base?.stages || []);
const inboxes = computed(() => props.base?.inboxes || []);
const maxVariants = computed(() => Number(props.base?.max_variants || 5));
const stepOptions = computed(() => props.base?.steps || [2, 5, 10, 15, 30, 60]);
// os padrões do servidor entram UMA vez (a base recarrega depois de cada reserva; o que
// você já digitou no formulário não pode voltar ao padrão sem você perceber)
let defaultsApplied = false;
watch(
  () => props.base,
  b => {
    if (!b || defaultsApplied) return;
    defaultsApplied = true;
    source.value = { ...source.value, ...clone(b.defaults?.source || {}), stage_ids: source.value.stage_ids };
    pace.value = { ...pace.value, ...clone(b.defaults?.pace || {}) };
    if (!inboxes.value.some(i => i.id === pace.value.default_inbox_id)) pace.value.default_inbox_id = inboxes.value[0]?.id || 0;
  },
  { immediate: true }
);
const stageName = id => stages.value.find(s => s.stage_id === id)?.name || `coluna ${id}`;
const stageOn = id => source.value.stage_ids.includes(id);
const toggleStage = id => {
  const ids = source.value.stage_ids;
  source.value.stage_ids = ids.includes(id) ? ids.filter(x => x !== id) : [...ids, id];
  emit('update:stageIds', source.value.stage_ids);
  touch();
};
// o bloco "Sua base" chama isto ao clicar numa coluna
const addStage = id => {
  if (!stageOn(id)) toggleStage(id);
};
defineExpose({ addStage });

// ── tipo ────────────────────────────────────────────────────────────────
const setKind = k => {
  kind.value = k;
  if (k === 'escala') slots.value = slots.value.slice(0, 1);
  else if (slots.value.length < 2) slots.value.push({ data: null });
  touch();
};
const kindCards = [
  { key: 'teste', icon: 'i-lucide-flask-conical', title: 'Teste de mensagens',
    text: 'Até 5 mensagens, sorteio equilibrado: cada pessoa recebe UMA. Você compara as taxas e descobre a vencedora.' },
  { key: 'escala', icon: 'i-lucide-rocket', title: 'Escala',
    text: 'Uma mensagem só (a vencedora) para um lote maior — pode ser a base inteira — no ritmo que você escolher.' },
];

// ── mensagens ───────────────────────────────────────────────────────────
const defaultInbox = computed(() => inboxes.value.find(i => i.id === pace.value.default_inbox_id) || inboxes.value[0] || null);
const templates = computed(() => defaultInbox.value?.templates || []);
const slotKey = i => KEYS[i];
const tokenLabel = token => `{{${token}}}`;
const slotLabel = i => `Mensagem ${KEYS[i]}`;
const addSlot = () => {
  if (slots.value.length >= maxVariants.value || kind.value === 'escala') return;
  slots.value.push({ data: null });
  touch();
};
const removeSlot = i => {
  if (slots.value.length <= 1) return;
  slots.value.splice(i, 1);
  touch();
};
const setTemplate = (i, tplName) => {
  const tpl = templates.value.find(t => t.name === tplName);
  slots.value[i].data = tpl ? buildVariant(tpl, slotLabel(i)) : null;
  touch();
};
const setVar = (i, token, value) => {
  setVariantVar(slots.value[i].data, token, value);
  touch();
};
const filledSlots = computed(() => slots.value.filter(s => s.data && !variantMissingVar(s.data)));
const variantsPayload = computed(() => slots.value.map((s, i) => ({ ...(s.data || {}), label: slotLabel(i) })).filter(v => v.template_params));

// ── ritmo ───────────────────────────────────────────────────────────────
const paceText = computed(() => paceSentence(pace.value));
const paceDay = computed(() => perDay(pace.value));

// ── prontidão ───────────────────────────────────────────────────────────
const readyHint = computed(() => {
  if (!props.canEdit) return 'Só quem edita campanhas cria segmentos.';
  if (!source.value.stage_ids.length) return 'Escolha pelo menos uma coluna.';
  if (!inboxes.value.length) return 'Nenhuma caixa WhatsApp oficial com modelos aprovados.';
  if (slots.value.some(s => !s.data)) return 'Escolha o modelo de cada mensagem.';
  if (filledSlots.value.length !== slots.value.length) return 'Preencha todas as variáveis das mensagens.';
  if (Number(source.value.size) > 0 && Number(source.value.size) < slots.value.length) return 'O tamanho precisa ser maior que o número de mensagens.';
  return '';
});
const canCalc = computed(() => props.canEdit && source.value.stage_ids.length > 0);
const canReserve = computed(() => !readyHint.value && preview.value && !previewDirty.value && preview.value.will_take > 0);

const baseSentence = computed(() => {
  const s = source.value;
  if (!s.stage_ids.length) return '';
  const bits = [`pessoas de ${s.stage_ids.map(stageName).join(', ')}`];
  if (s.procedure !== 'todas') bits.push(`só ${PROCEDURES.find(p => p.key === s.procedure)?.label.toLowerCase()}`);
  if (Number(s.min_age_days) > 0) bits.push(`que chegaram há ${s.min_age_days}+ dias`);
  if (Number(s.quiet_hours) > 0) bits.push(`sem conversa nas últimas ${s.quiet_hours} h`);
  if (s.skip_future_appointment) bits.push('sem consulta marcada');
  if (Number(s.exclude_campaign_days) > 0) bits.push(`sem campanha nos últimos ${s.exclude_campaign_days} dias`);
  bits.push('fora de outros segmentos');
  return bits.join(' · ');
});
const reserveSentence = computed(() => {
  const p = preview.value;
  if (!p) return '';
  const n = p.will_take;
  const order = ORDERS.find(o => o.key === source.value.order)?.label.toLowerCase();
  const per = slots.value.length > 1 ? `, ${fmtInt(Math.floor(n / slots.value.length))} para cada uma das ${slots.value.length} mensagens` : '';
  return `De ${fmtInt(p.base_total)} pessoas com telefone, ${fmtInt(p.eligible)} podem receber. Vou reservar ${fmtInt(n)} (${order})${per}. Nada sai agora: o envio começa no cartão do segmento.`;
});

// ── ações ───────────────────────────────────────────────────────────────
const fail = (err, fallback) => useAlert(err?.response?.data?.error || fallback);
const calculate = async () => {
  busy.value = 'calc';
  try {
    const { data } = await CrmAPI.previewSegment(source.value);
    preview.value = data;
    previewDirty.value = false;
  } catch (err) {
    fail(err, 'Não deu para calcular a base.');
  } finally {
    busy.value = '';
  }
};
const reserve = async () => {
  busy.value = 'reserve';
  try {
    const { data } = await CrmAPI.createSegment({
      name: name.value, kind: kind.value, source: source.value, variants: variantsPayload.value, pace: pace.value,
    });
    useAlert(`Segmento “${data.name}” reservado com ${people(data.reserved)}.`);
    emit('created', data);
    name.value = '';
    preview.value = null;
    previewDirty.value = true;
    confirming.value = false;
  } catch (err) {
    fail(err, 'Não deu para reservar o segmento.');
  } finally {
    busy.value = '';
  }
};
</script>

<template>
  <div>
    <div class="flex items-start gap-4 mb-6 flex-wrap">
      <span class="cv-icon cv-icon-lg"><span class="i-lucide-scissors text-xl" /></span>
      <div class="min-w-0 flex-1">
        <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight">2. Segmento novo</h2>
        <p class="text-sm text-n-slate-11 mt-1">
          Separe um pedaço da base para testar mensagens (ou para escalar a vencedora). Reservar não manda nada.
        </p>
      </div>
    </div>

    <!-- 2.1 de onde vem a base -->
    <section id="seg-novo-base" class="novo-sub">
      <h3 class="novo-sub-title"><span class="novo-step">1</span> De onde vem a base</h3>
      <p class="cv-label mb-2">Colunas do CRM</p>
      <div class="flex flex-wrap gap-2 mb-4">
        <button
          v-for="s in stages"
          :key="s.stage_id"
          class="cv-chip"
          :class="{ 'cv-chip-on': stageOn(s.stage_id) }"
          :disabled="!canEdit"
          @click="toggleStage(s.stage_id)"
        >
          <span :class="stageOn(s.stage_id) ? 'i-lucide-check' : 'i-lucide-plus'" class="text-xs" />
          {{ s.name }} <span class="opacity-70 tabular-nums">· {{ fmtInt(s.eligible) }}</span>
        </button>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <p class="cv-label mb-2">Frente (pelo procedimento do card)</p>
          <div class="cv-seg cv-seg-sm flex-wrap">
            <button
              v-for="p in PROCEDURES"
              :key="p.key"
              class="cv-seg-item"
              :class="{ 'cv-seg-on': source.procedure === p.key }"
              :disabled="!canEdit"
              @click="source.procedure = p.key; touch()"
            >
              {{ p.label }}
            </button>
          </div>
        </div>
        <div>
          <p class="cv-label mb-2">Peneira</p>
          <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-n-slate-11">
            <label class="flex items-center gap-1.5">
              chegou há
              <input v-model.number="source.min_age_days" type="number" min="0" max="365" class="cv-input !h-8 w-16 text-right" :disabled="!canEdit" @input="touch" />
              + dias
            </label>
            <label class="flex items-center gap-1.5">
              conversou nas últimas
              <select v-model.number="source.quiet_hours" class="cv-input !h-8 !w-auto" :disabled="!canEdit" @change="touch">
                <option v-for="o in QUIET_OPTIONS" :key="o.value" :value="o.value">{{ o.label }}</option>
              </select>
            </label>
            <label class="flex items-center gap-1.5">
              recebeu campanha há menos de
              <select v-model.number="source.exclude_campaign_days" class="cv-input !h-8 !w-auto" :disabled="!canEdit" @change="touch">
                <option v-for="o in CAMPAIGN_OPTIONS" :key="o.value" :value="o.value">{{ o.label }}</option>
              </select>
            </label>
            <label class="flex items-center gap-2 cursor-pointer select-none">
              <input v-model="source.skip_future_appointment" type="checkbox" class="rounded border-n-weak" :disabled="!canEdit" @change="touch" />
              tirar quem tem consulta ou cirurgia marcada
            </label>
          </div>
        </div>
      </div>
      <p v-if="baseSentence" class="novo-sentence mt-4"><span class="i-lucide-quote text-sm flex-shrink-0" />{{ baseSentence }}</p>
    </section>

    <!-- 2.2 tipo e tamanho -->
    <section id="seg-novo-tipo" class="novo-sub">
      <h3 class="novo-sub-title"><span class="novo-step">2</span> Tipo e tamanho</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-4">
        <button
          v-for="k in kindCards"
          :key="k.key"
          class="novo-opt text-left"
          :class="{ 'novo-opt-on': kind === k.key }"
          :disabled="!canEdit"
          @click="setKind(k.key)"
        >
          <span class="cv-icon cv-icon-sm flex-shrink-0"><span :class="k.icon" class="text-sm" /></span>
          <span>
            <b class="block text-sm text-n-slate-12">{{ k.title }}</b>
            <span class="text-xs text-n-slate-11">{{ k.text }}</span>
          </span>
        </button>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <p class="cv-label mb-2">Quantas pessoas</p>
          <div class="flex flex-wrap items-center gap-2">
            <button
              v-for="n in SIZE_PRESETS"
              :key="n"
              class="cv-chip"
              :class="{ 'cv-chip-on': Number(source.size) === n }"
              :disabled="!canEdit"
              @click="source.size = n; touch()"
            >
              {{ fmtInt(n) }}
            </button>
            <button class="cv-chip" :class="{ 'cv-chip-on': Number(source.size) === 0 }" :disabled="!canEdit" @click="source.size = 0; touch()">
              todas que podem
            </button>
            <input v-model.number="source.size" type="number" min="0" max="50000" class="cv-input !h-8 w-24 text-right" :disabled="!canEdit" @input="touch" />
          </div>
          <p v-if="kind === 'teste' && Number(source.size) > 0" class="text-[11px] text-n-slate-10 mt-2">
            {{ fmtInt(Math.floor(Number(source.size) / slots.length)) }} pessoas por mensagem ({{ slots.length }} mensagens).
          </p>
        </div>
        <div>
          <p class="cv-label mb-2">Em que ordem entram</p>
          <div class="cv-seg cv-seg-sm flex-wrap">
            <button
              v-for="o in ORDERS"
              :key="o.key"
              class="cv-seg-item"
              :class="{ 'cv-seg-on': source.order === o.key }"
              :title="o.hint"
              :disabled="!canEdit"
              @click="source.order = o.key; touch()"
            >
              {{ o.label }}
            </button>
          </div>
          <p class="text-[11px] text-n-slate-10 mt-2">{{ ORDERS.find(o => o.key === source.order)?.hint }}.</p>
        </div>
      </div>
    </section>

    <!-- 2.3 mensagens -->
    <section id="seg-novo-mensagens" class="novo-sub">
      <h3 class="novo-sub-title"><span class="novo-step">3</span> {{ kind === 'escala' ? 'A mensagem' : 'As mensagens para testar' }}</h3>
      <div class="flex flex-wrap items-center gap-3 mb-4">
        <label class="flex items-center gap-2 text-xs text-n-slate-11">
          Caixa padrão (os modelos vêm dela)
          <select v-model.number="pace.default_inbox_id" class="cv-input !h-8 !w-auto" :disabled="!canEdit" @change="touch">
            <option v-for="i in inboxes" :key="i.id" :value="i.id">{{ i.name }} · {{ i.templates.length }} modelos</option>
          </select>
        </label>
        <span v-if="!templates.length" class="novo-note novo-note-amber"><span class="i-lucide-info text-sm" /> Esta caixa não tem modelo aprovado — crie na Meta e “Buscar novos templates”.</span>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <article v-for="(slot, i) in slots" :key="i" class="novo-msg">
          <div class="flex items-center gap-2 mb-2">
            <span class="novo-key" :style="{ background: `var(--vc-${slotKey(i)})` }">{{ slotKey(i) }}</span>
            <b class="text-sm text-n-slate-12">{{ slotLabel(i) }}</b>
            <div class="flex-1" />
            <button v-if="slots.length > 1 && canEdit" class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger cv-iconbtn" title="Tirar esta mensagem" @click="removeSlot(i)">
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <select
            :value="slot.data?.template_params?.name || ''"
            class="cv-input !h-9 w-full"
            :disabled="!canEdit || !templates.length"
            @change="setTemplate(i, $event.target.value)"
          >
            <option value="">— escolha o modelo —</option>
            <option v-for="t in templates" :key="t.name" :value="t.name">{{ t.name }} ({{ t.language }})</option>
          </select>
          <template v-if="slot.data">
            <div v-for="token in variantTokens(slot.data)" :key="token" class="flex items-center gap-2 mt-1.5">
              <span class="cv-chip font-mono flex-shrink-0">{{ tokenLabel(token) }}</span>
              <input
                :value="variantVar(slot.data, token)"
                class="cv-input !h-8 w-full text-xs font-mono"
                :placeholder="token === '1' ? NAME_VAR : 'texto fixo'"
                :disabled="!canEdit"
                @input="setVar(i, token, $event.target.value)"
              />
            </div>
            <p v-if="variantMissingVar(slot.data)" class="text-[11px] text-red-600 mt-1">preencha todas as variáveis do modelo</p>
            <div class="novo-bubble mt-2">
              <!-- numa linha só de propósito: o balão é pre-wrap -->
              <span v-for="part in previewParts(slot.data)" :key="part.key" :class="part.chip ? 'novo-var' : ''">{{ part.text }}</span>
            </div>
          </template>
        </article>
        <button
          v-if="kind === 'teste' && slots.length < maxVariants && canEdit"
          class="novo-msg novo-msg-add"
          @click="addSlot"
        >
          <span class="i-lucide-plus text-lg" />
          <span class="text-sm">mais uma mensagem ({{ slotKey(slots.length) }})</span>
        </button>
      </div>
    </section>

    <!-- 2.4 ritmo -->
    <section id="seg-novo-ritmo" class="novo-sub">
      <h3 class="novo-sub-title"><span class="novo-step">4</span> Ritmo de envio</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <p class="cv-label mb-2">Quantas por hora</p>
          <div class="flex flex-wrap items-center gap-2">
            <button v-for="n in PER_HOUR_PRESETS" :key="n" class="cv-chip" :class="{ 'cv-chip-on': Number(pace.per_hour) === n }" :disabled="!canEdit" @click="pace.per_hour = n; touch()">{{ n }}</button>
            <input v-model.number="pace.per_hour" type="number" min="1" max="5000" class="cv-input !h-8 w-20 text-right" :disabled="!canEdit" @input="touch" />
          </div>
        </div>
        <div>
          <p class="cv-label mb-2">De quanto em quanto tempo sai uma leva</p>
          <div class="flex flex-wrap items-center gap-2">
            <button v-for="m in stepOptions" :key="m" class="cv-chip" :class="{ 'cv-chip-on': Number(pace.step_minutes) === m }" :disabled="!canEdit" @click="pace.step_minutes = m; touch()">{{ m }} min</button>
          </div>
          <p class="text-[11px] text-n-slate-10 mt-2">= {{ fmtInt(stepSize(pace)) }} pessoas por leva.</p>
        </div>
        <div>
          <p class="cv-label mb-2">Janela e dias</p>
          <div class="flex flex-wrap items-center gap-2 text-xs text-n-slate-11">
            das
            <select v-model.number="pace.hour_from" class="cv-input !h-8 !w-auto" :disabled="!canEdit" @change="touch"><option v-for="h in HOURS_FROM" :key="h" :value="h">{{ h }}h</option></select>
            às
            <select v-model.number="pace.hour_to" class="cv-input !h-8 !w-auto" :disabled="!canEdit" @change="touch"><option v-for="h in HOURS_TO" :key="h" :value="h">{{ h }}h</option></select>
            <label class="flex items-center gap-2 cursor-pointer select-none ml-2">
              <input v-model="pace.weekdays_only" type="checkbox" class="rounded border-n-weak" :disabled="!canEdit" @change="touch" />
              só dias úteis
            </label>
          </div>
        </div>
        <div>
          <p class="cv-label mb-2">Teto por dia</p>
          <div class="flex flex-wrap items-center gap-2">
            <button v-for="n in CAP_PRESETS" :key="n" class="cv-chip" :class="{ 'cv-chip-on': Number(pace.daily_cap) === n }" :disabled="!canEdit" @click="pace.daily_cap = n; touch()">{{ fmtInt(n) }}</button>
            <button class="cv-chip" :class="{ 'cv-chip-on': Number(pace.daily_cap) === 0 }" :disabled="!canEdit" @click="pace.daily_cap = 0; touch()">sem teto</button>
          </div>
          <label class="flex items-center gap-2 text-xs text-n-slate-11 mt-3">
            e no máximo
            <input v-model.number="pace.inbox_daily_cap" type="number" min="1" max="5000" class="cv-input !h-8 w-20 text-right" :disabled="!canEdit" @input="touch" />
            por caixa por dia (regra dos ~1000 contatos/mês por número)
          </label>
          <label class="flex items-center gap-2 text-xs text-n-slate-11 mt-3 cursor-pointer select-none">
            <input v-model="pace.route_by_origin" type="checkbox" class="rounded border-n-weak" :disabled="!canEdit" @change="touch" />
            mandar pela caixa por onde a pessoa chegou (senão, pela caixa padrão)
          </label>
        </div>
      </div>
      <p class="novo-sentence mt-4">
        <span class="i-lucide-timer text-sm flex-shrink-0" />
        {{ paceText }} → até {{ fmtInt(paceDay) }} por dia.
      </p>
    </section>

    <!-- calcular + reservar -->
    <section id="seg-novo-calcular" class="novo-sub novo-sub-last">
      <div class="flex flex-wrap items-center gap-3 mb-4">
        <input v-model="name" class="cv-input !h-9 flex-1 min-w-[200px]" placeholder="Nome do segmento (ex.: Teste 1 · Orçamento · 5 mensagens)" :disabled="!canEdit" />
        <button class="cv-btn cv-btn-ghost" :disabled="!canCalc || busy !== ''" @click="calculate">
          <span class="i-lucide-calculator text-sm" />
          {{ busy === 'calc' ? 'Calculando…' : 'Calcular quem entra' }}
        </button>
      </div>

      <div v-if="preview" class="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-4" :class="{ 'opacity-60': previewDirty }">
        <div class="novo-peneira">
          <p class="cv-label mb-2">A peneira, regra a regra</p>
          <div class="novo-row"><span>Com telefone nas colunas escolhidas</span><b>{{ fmtInt(preview.base_total) }}</b></div>
          <div v-for="r in preview.removed" :key="r.key" class="novo-row novo-row-minus" :class="{ 'opacity-50': !r.count }">
            <span>− {{ r.label }}</span><b>{{ fmtInt(r.count) }}</b>
          </div>
          <div class="novo-row novo-row-total"><span>Podem receber</span><b>{{ fmtInt(preview.eligible) }}</b></div>
          <div class="novo-row novo-row-take"><span>Vão ser reservadas</span><b>{{ fmtInt(preview.will_take) }}</b></div>
        </div>
        <div>
          <p class="cv-label mb-2">Por coluna</p>
          <div v-for="s in preview.by_stage" :key="s.stage_id" class="novo-row">
            <span>{{ s.name }}</span><b class="font-normal text-n-slate-11"><span class="text-n-slate-12 font-bold">{{ fmtInt(s.eligible) }}</span> de {{ fmtInt(s.total) }}</b>
          </div>
          <p v-if="previewDirty" class="novo-note novo-note-amber mt-3"><span class="i-lucide-info text-sm" /> Você mudou algo: calcule de novo antes de reservar.</p>
        </div>
      </div>
      <p v-if="preview && !previewDirty" class="novo-sentence mb-4"><span class="i-lucide-quote text-sm flex-shrink-0" />{{ reserveSentence }}</p>

      <div class="flex flex-wrap items-center gap-3">
        <template v-if="confirming">
          <span class="text-xs text-n-slate-11">Reservar {{ people(preview?.will_take || 0) }} neste segmento? Nada é enviado agora.</span>
          <button class="cv-btn" :disabled="busy !== ''" @click="reserve">
            <span class="i-lucide-lock text-sm" />
            {{ busy === 'reserve' ? 'Reservando…' : 'Sim, reservar' }}
          </button>
          <button class="cv-btn cv-btn-ghost" :disabled="busy !== ''" @click="confirming = false">Voltar</button>
        </template>
        <template v-else>
          <button class="cv-btn" :disabled="!canReserve || busy !== ''" :title="readyHint" @click="confirming = true">
            <span class="i-lucide-lock text-sm" />
            Reservar segmento
          </button>
          <span v-if="readyHint" class="text-xs text-n-slate-10">{{ readyHint }}</span>
          <span v-else-if="previewDirty" class="text-xs text-n-slate-10">Calcule quem entra antes de reservar.</span>
        </template>
      </div>
    </section>
  </div>
</template>

<style scoped>
.novo-sub {
  --vc-A: #2563eb;
  --vc-B: #7c3aed;
  --vc-C: #059669;
  --vc-D: #d97706;
  --vc-E: #db2777;
  padding: 20px 0 24px;
  border-top: 1px solid rgb(var(--cv-rgb) / 0.14);
}
.novo-sub-last {
  border-bottom: 0;
}
.novo-sub-title {
  display: flex;
  align-items: center;
  gap: 10px;
  font-size: 15px;
  font-weight: 800;
  letter-spacing: -0.01em;
  margin-bottom: 14px;
}
.novo-step {
  width: 26px;
  height: 26px;
  border-radius: 9px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 800;
  color: #fff;
  background: var(--cv-grad);
}
.novo-opt {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px 14px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.45);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
}
.novo-opt-on {
  border-color: rgb(var(--cv-rgb) / 0.55);
  background: rgb(var(--cv-rgb) / 0.08);
}
.dark .novo-opt {
  background: rgba(255, 255, 255, 0.03);
}
.novo-msg {
  padding: 14px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.5);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  min-width: 0;
}
.dark .novo-msg {
  background: rgba(255, 255, 255, 0.03);
}
.novo-msg-add {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 6px;
  border-style: dashed;
  color: rgb(var(--cv-rgb));
  min-height: 120px;
}
.novo-key {
  width: 26px;
  height: 26px;
  border-radius: 9px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 800;
  color: #fff;
}
.novo-sentence {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 14px;
  border-radius: 14px;
  font-size: 13px;
  line-height: 1.5;
  background: rgb(var(--cv-rgb) / 0.08);
  border: 1px solid rgb(var(--cv-rgb) / 0.18);
}
.novo-note {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 10px;
  font-size: 11px;
}
.novo-note-amber {
  color: #92400e;
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.35);
}
.dark .novo-note-amber {
  color: #fcd34d;
}
.novo-peneira {
  padding: 12px 14px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.45);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
}
.dark .novo-peneira {
  background: rgba(255, 255, 255, 0.03);
}
.novo-row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  font-size: 12px;
  padding: 4px 0;
  border-bottom: 1px dashed rgb(var(--cv-rgb) / 0.14);
}
.novo-row b {
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.novo-row-minus {
  color: #991b1b;
}
.dark .novo-row-minus {
  color: #fca5a5;
}
.novo-row-total {
  font-weight: 700;
  border-bottom: 0;
  margin-top: 4px;
}
.novo-row-take {
  font-weight: 800;
  border-bottom: 0;
  color: rgb(var(--cv-rgb));
  font-size: 13px;
}
.novo-bubble {
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
.dark .novo-bubble {
  color: #e9edef;
  background: #005c4b;
}
.novo-var {
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
.dark .novo-var {
  color: #a7f3d0;
  background: rgba(16, 185, 129, 0.22);
  border-color: rgba(16, 185, 129, 0.45);
}
</style>
