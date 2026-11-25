<script setup>
// 🧑‍🏫 CONSULTOR SUPERIOR (item 414, 24/11): o motor principal do atendente (o
// barato) responde a tudo; em situações que o SISTEMA reconhece (chamou a
// equipe sem urgência, ia agendar em horário que não validou, resposta vazia
// ou sem pergunta), a resposta é segurada e um motor mais forte diz qual deve
// ser a resposta final. Em "sombra" nada muda para o paciente: só fica o
// registro do que o consultor teria feito. Desligado = tudo como antes.
// Salva na hora (não passa pelo rascunho/publicar do cartão).
import { ref, computed, watch, onMounted } from 'vue';
import LlmModelPicker from 'dashboard/components-next/cevico/LlmModelPicker.vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  agentKey: { type: String, required: true },
  claudeModels: { type: Array, default: () => [] },
  openaiModels: { type: Array, default: () => [] },
  // settings.ai.llm_catalog (Claude, ChatGPT, Gemini)
  llmCatalog: { type: Array, default: () => [] },
  // caixas de WhatsApp em que este agente lê ({ id, name })
  inboxes: { type: Array, default: () => [] },
  // muda quando o cartão é publicado ou o motor por coluna é salvo
  refreshKey: { type: [String, Number], default: '' },
});

const ON_GRADIENT = 'linear-gradient(135deg, #059669, #34D399)';
const SHADOW_GRADIENT = 'linear-gradient(135deg, #475569, #94a3b8)';
const MODES = [
  {
    key: 'sombra',
    label: 'Sombra',
    hint: 'só registra o que ele faria; o paciente recebe a resposta do principal',
  },
  {
    key: 'ativo',
    label: 'Ativo',
    hint: 'vale a resposta do consultor',
  },
];
const TRIGGER_HELP = {
  chamar_humano:
    'O principal quis passar para a equipe e não é urgência clínica. O consultor confere se o Roteiro pede mesmo a equipe.',
  vaga_invalida:
    'O principal ia confirmar um horário que não está livre na Agenda (ou veio sem dia e hora).',
  sem_pergunta:
    'A resposta veio vazia, ou sem nenhuma pergunta numa etapa em que o Roteiro conduz com pergunta.',
};
const TRIGGER_TITLE = {
  chamar_humano: 'Chamou a equipe sem urgência',
  vaga_invalida: 'Horário que não validou',
  sem_pergunta: 'Resposta vazia ou sem pergunta',
};
const STAGE_LABEL = {
  recepcao: 'recepção',
  sondagem: 'sondagem',
  autoridade: 'autoridade',
  orcamento: 'orçamento',
  objecoes: 'objeções',
  agendamento: 'agendamento',
  pos_agendamento: 'pós-agendamento',
  reagendamento: 'reagendamento',
  pos_consulta: 'pós-consulta',
  pos_cirurgico: 'pós-cirúrgico',
  encerramento: 'encerramento',
};
const EFFORT_LABEL = {
  low: 'Pouco',
  medium: 'Médio',
  high: 'Bastante',
  xhigh: 'Muito',
  max: 'O máximo',
};

const loading = ref(true);
const saving = ref(false);
const data = ref(null);
const form = ref(null);
const showRecent = ref(false);
const openItem = ref(null);

const shortLabel = label => String(label || '').split(' — ')[0];
const modelLabel = id => {
  const found =
    props.claudeModels.find(m => m.value === id) ||
    props.openaiModels.find(m => m.value === id) ||
    props.llmCatalog.flatMap(p => p.models || []).find(m => m.value === id);
  return found ? shortLabel(found.label) : id || 'não escolhido';
};

const clone = value => JSON.parse(JSON.stringify(value || {}));
const apply = payload => {
  data.value = payload;
  form.value = clone(payload.config);
};

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAiConsultant(props.agentKey);
    apply(payload);
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

const dirty = computed(
  () =>
    !!data.value &&
    JSON.stringify(data.value.config) !== JSON.stringify(form.value)
);
const enabled = computed(() => !!data.value?.config?.enabled);
const savedMode = computed(() => data.value?.config?.mode || 'sombra');
const statusChip = computed(() => {
  if (!enabled.value) return { label: 'desligado', style: {} };
  if (!data.value?.ready)
    return { label: 'ligado, mas sem a chave do modelo', style: {} };
  return savedMode.value === 'ativo'
    ? { label: 'ativo', style: { background: ON_GRADIENT }, on: true }
    : { label: 'em sombra', style: { background: SHADOW_GRADIENT }, on: true };
});

const persist = async (config, message) => {
  if (saving.value) return false;
  saving.value = true;
  try {
    const { data: payload } = await CrmAPI.saveAiConsultant({
      agent: props.agentKey,
      consultor: config,
    });
    apply(payload);
    useAlert(message);
    return true;
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o consultor');
    return false;
  } finally {
    saving.value = false;
  }
};

const save = () =>
  persist(form.value, 'Consultor salvo: já vale para a próxima resposta');

// o interruptor salva na hora, junto com o que estiver na tela
const toggle = () => {
  const next = { ...form.value, enabled: !enabled.value };
  return persist(
    next,
    next.enabled
      ? `Consultor ligado em modo ${next.mode === 'ativo' ? 'ativo' : 'sombra'}`
      : 'Consultor desligado: o atendente voltou a responder sozinho'
  );
};

const setTrigger = (key, value) => {
  form.value = {
    ...form.value,
    triggers: { ...form.value.triggers, [key]: value },
  };
};
const inboxOn = id => (form.value?.inbox_ids || []).includes(id);
const toggleInbox = id => {
  const list = form.value.inbox_ids || [];
  form.value = {
    ...form.value,
    inbox_ids: inboxOn(id) ? list.filter(i => i !== id) : [...list, id],
  };
};
const stageOn = stage => (form.value?.question_stages || []).includes(stage);
const toggleStage = stage => {
  const list = form.value.question_stages || [];
  form.value = {
    ...form.value,
    question_stages: stageOn(stage)
      ? list.filter(s => s !== stage)
      : [...list, stage],
  };
};

// ── contador ──
const rate = computed(() => Number(data.value?.usd_brl) || 0);
const money = usd => {
  // valor pequeno (uma consulta custa centavos) ganha uma casa a mais
  const value = rate.value ? usd * rate.value : Number(usd);
  const digits = Math.abs(value) > 0 && Math.abs(value) < 1 ? 3 : 2;
  if (rate.value) {
    return value.toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
      minimumFractionDigits: 2,
      maximumFractionDigits: digits,
    });
  }
  return `US$ ${value.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: digits,
  })}`;
};
const stats = computed(() => data.value?.stats || null);
const total = computed(() => stats.value?.total || {});
const today = computed(() => stats.value?.today || {});
const answered = computed(
  () =>
    (total.value.consultas || 0) +
    (total.value.testes || 0) -
    (total.value.falhas || 0)
);
const hasStats = computed(
  () => (total.value.consultas || 0) + (total.value.testes || 0) > 0
);
const pairs = (bag, labels) =>
  Object.entries(bag || {})
    .sort((a, b) => b[1] - a[1])
    .map(([key, count]) => ({ key, count, label: labels?.[key] || key }));
const triggerRows = computed(() =>
  pairs(total.value.gatilhos, data.value?.trigger_labels)
);
const effectRows = computed(() =>
  pairs(total.value.efeitos, data.value?.effect_labels)
);
const recent = computed(() => data.value?.recent || []);

const fmtWhen = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const flagsOf = snap => {
  if (!snap) return [];
  const flags = [];
  if (snap.agendar)
    flags.push(
      `agendaria ${snap.agendamento?.dia || ''} ${snap.agendamento?.hora || ''}`.trim()
    );
  if (snap.chamar_humano) flags.push('chamaria a equipe');
  if (snap.cancelar) flags.push('cancelaria');
  if (snap.pausar) flags.push('encerraria');
  return flags;
};
const textOf = snap => {
  if (!snap) return '';
  if (snap.erro) return `(${snap.erro})`;
  return (snap.mensagens || []).join('\n') || '(sem mensagem)';
};

onMounted(load);
watch(() => [props.agentKey, props.refreshKey], load);
</script>

<template>
  <div class="cv-sub p-4 mb-4 space-y-3" data-test="consultor-superior">
    <div class="flex items-start gap-3">
      <div class="min-w-0 flex-1">
        <p class="text-sm font-bold text-n-slate-12">
          🧑‍🏫 Consultor superior
          <span
            v-if="data"
            class="cv-chip ml-1 align-middle"
            :class="statusChip.on ? 'cv-chip-on' : ''"
            :style="statusChip.style"
            >{{ statusChip.label }}</span
          >
        </p>
        <p class="text-[11px] text-n-slate-10 mt-0.5">
          O motor barato continua atendendo. Só nas situações marcadas abaixo o
          sistema segura a resposta e pede a segunda opinião de um motor mais
          forte. Urgência clínica nunca espera o consultor.
        </p>
      </div>
      <button
        class="cv-switch cv-switch-lg flex-shrink-0"
        :class="enabled ? 'cv-switch-on' : ''"
        :title="enabled ? 'Desligar o consultor' : 'Ligar o consultor'"
        :disabled="saving || loading || !data"
        :aria-pressed="enabled"
        @click="toggle"
      />
    </div>

    <p v-if="loading" class="text-[11px] text-n-slate-10">Carregando…</p>
    <p v-else-if="!data" class="text-[11px] text-red-500">
      Não consegui carregar o consultor deste agente.
    </p>

    <template v-else>
      <!-- quem é o consultor e o que a resposta dele vale -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <div class="cv-stat px-3 py-2 space-y-1.5">
          <p class="text-[10px] text-n-slate-10">Quem é o consultor</p>
          <LlmModelPicker
            :model-value="form.model || ''"
            :catalog="llmCatalog"
            :disabled="saving"
            :engine-note="false"
            empty-label="Escolha o modelo do consultor"
            @update:model-value="value => (form = { ...form, model: value })"
          />
          <p class="text-[10px] text-n-slate-9">
            {{
              data.staged
                ? 'Ele só entra onde o motor da coluna é outro: coluna que já usa este modelo responde direto.'
                : `O atendente responde com ${modelLabel(data.default_model)}. Escolha aqui um modelo mais forte que ele.`
            }}
          </p>
        </div>
        <div class="cv-stat px-3 py-2 space-y-1.5">
          <p class="text-[10px] text-n-slate-10">O que a resposta dele vale</p>
          <div class="cv-seg cv-seg-sm">
            <button
              v-for="mode in MODES"
              :key="mode.key"
              class="cv-seg-item"
              :class="{ 'cv-seg-on': form.mode === mode.key }"
              :disabled="saving"
              :title="mode.hint"
              @click="form = { ...form, mode: mode.key }"
            >
              {{ mode.label }}
            </button>
          </div>
          <p class="text-[10px] text-n-slate-9">
            {{
              form.mode === 'ativo'
                ? 'Ativo: quando o consultor muda a resposta, é a dele que vale. Se ele falhar ou demorar, vale a do principal.'
                : 'Sombra: o paciente recebe a resposta do principal, como hoje. O que o consultor faria fica anotado para você comparar.'
            }}
          </p>
        </div>
      </div>

      <!-- em quais caixas -->
      <div v-if="inboxes.length > 1">
        <p class="text-xs font-medium text-n-slate-11 mb-1">
          Em quais caixas
          <span class="text-n-slate-9 font-normal"
            >(nenhuma marcada = em todas as que este agente lê)</span
          >
        </p>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="inbox in inboxes"
            :key="inbox.id"
            class="cv-chip"
            :class="inboxOn(inbox.id) ? 'cv-chip-on' : ''"
            :style="inboxOn(inbox.id) ? { background: ON_GRADIENT } : {}"
            :disabled="saving"
            @click="toggleInbox(inbox.id)"
          >
            {{ inbox.name }}
          </button>
        </div>
      </div>

      <!-- gatilhos -->
      <div>
        <p class="text-xs font-medium text-n-slate-11 mb-1.5">
          Quando o sistema pede a segunda opinião
        </p>
        <div class="space-y-1.5">
          <div
            v-for="(label, key) in data.triggers"
            :key="key"
            class="flex items-start gap-3"
          >
            <button
              class="cv-switch flex-shrink-0 mt-0.5"
              :class="form.triggers[key] ? 'cv-switch-on' : ''"
              :disabled="saving"
              :aria-pressed="!!form.triggers[key]"
              :title="label"
              @click="setTrigger(key, !form.triggers[key])"
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm text-n-slate-12">
                {{ TRIGGER_TITLE[key] || label }}
              </p>
              <p class="text-[11px] text-n-slate-10">
                {{ TRIGGER_HELP[key] }}
              </p>
              <div
                v-if="key === 'sem_pergunta' && form.triggers[key]"
                class="mt-1.5"
              >
                <p class="text-[10px] text-n-slate-9 mb-1">
                  Etapas em que toda resposta precisa de uma pergunta
                </p>
                <div class="flex flex-wrap gap-1.5">
                  <button
                    v-for="stage in data.stages"
                    :key="stage"
                    class="cv-chip"
                    :class="stageOn(stage) ? 'cv-chip-on' : ''"
                    :style="stageOn(stage) ? { background: ON_GRADIENT } : {}"
                    :disabled="saving"
                    @click="toggleStage(stage)"
                  >
                    {{ STAGE_LABEL[stage] || stage }}
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- ferramenta opcional -->
          <div class="flex items-start gap-3">
            <button
              class="cv-switch flex-shrink-0 mt-0.5"
              :class="form.tool ? 'cv-switch-on' : ''"
              :disabled="saving"
              :aria-pressed="!!form.tool"
              title="O principal pode pedir orientação"
              @click="form = { ...form, tool: !form.tool }"
            />
            <div class="min-w-0 flex-1">
              <p class="text-sm text-n-slate-12">
                O principal pode pedir orientação
                <span class="text-[10px] text-n-slate-9 font-normal"
                  >(opcional)</span
                >
              </p>
              <p class="text-[11px] text-n-slate-10">
                O motor barato ganha um botão para perguntar ao consultor quando
                estiver em dúvida. A orientação volta para ele, e quem escreve
                ao paciente continua sendo ele.
                {{
                  form.tool && form.mode !== 'ativo'
                    ? 'Só passa a valer no modo Ativo.'
                    : ''
                }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <!-- limites -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <label class="block">
          <span class="text-[10px] text-n-slate-10 block mb-0.5"
            >Teto de consultas por dia</span
          >
          <input
            v-model.number="form.daily_cap"
            type="number"
            min="1"
            :max="data.limits.cap_max"
            class="cv-input w-full text-sm"
            :disabled="saving"
          />
        </label>
        <label class="block">
          <span class="text-[10px] text-n-slate-10 block mb-0.5"
            >Espera no máximo (segundos)</span
          >
          <input
            v-model.number="form.timeout"
            type="number"
            :min="data.limits.timeout_min"
            :max="data.limits.timeout_max"
            class="cv-input w-full text-sm"
            :disabled="saving"
          />
        </label>
        <label class="block">
          <span class="text-[10px] text-n-slate-10 block mb-0.5"
            >Quanto ele pensa</span
          >
          <select
            v-model="form.effort"
            class="cv-input w-full text-sm"
            :disabled="saving"
          >
            <option
              v-for="effort in data.efforts"
              :key="effort"
              :value="effort"
            >
              {{ EFFORT_LABEL[effort] || effort }}
            </option>
          </select>
        </label>
      </div>
      <p class="text-[11px] text-n-slate-10">
        Passou do teto do dia, ou o consultor falhou ou demorou: vale a resposta
        do principal. Se o principal já remarcou, cancelou ou confirmou algo na
        Agenda naquela resposta, o consultor não entra. O consultor não mexe na
        Agenda: só confere horários.
      </p>

      <div class="flex flex-wrap items-center gap-2">
        <button
          class="cv-btn cv-btn-sm"
          :disabled="saving || !dirty"
          @click="save"
        >
          {{ saving ? 'Salvando…' : 'Salvar consultor' }}
        </button>
        <span v-if="dirty" class="text-[11px] text-n-slate-10">
          Há mudança sem salvar
        </span>
      </div>

      <!-- contador -->
      <div v-if="hasStats">
        <p class="text-xs font-medium text-n-slate-11 mb-1.5">
          O que o consultor fez
          <span class="text-n-slate-9 font-normal"
            >(últimos {{ stats.span }} dias)</span
          >
        </p>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Consultas hoje</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ today.consultas || 0 }} de {{ stats.cap }}
            </p>
            <p class="text-[10px] text-n-slate-9">
              {{
                today.barradas
                  ? `${today.barradas} barradas pelo teto`
                  : 'dentro do teto'
              }}
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Consultas em pacientes</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ total.consultas || 0 }}
            </p>
            <p class="text-[10px] text-n-slate-9">
              + {{ total.testes || 0 }} no 🧪 teste
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Mudou a resposta</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ total.mudou || 0 }} de {{ answered }}
            </p>
            <p class="text-[10px] text-n-slate-9">
              {{ total.aplicadas || 0 }} valeram ·
              {{ total.falhas || 0 }} falhas
            </p>
          </div>
          <div class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10">Custo do consultor</p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ money(total.custo_usd || 0) }}
            </p>
            <p class="text-[10px] text-n-slate-9">
              {{
                answered
                  ? `${money((total.custo_usd || 0) / answered)} por consulta`
                  : '—'
              }}
            </p>
          </div>
        </div>
        <div
          v-if="triggerRows.length || effectRows.length"
          class="flex flex-wrap gap-1.5 mt-2"
        >
          <span
            v-for="row in triggerRows"
            :key="`g-${row.key}`"
            class="cv-chip cv-chip-wrap"
            title="Por que foi consultado"
            >{{ row.count }}× {{ row.label }}</span
          >
          <span
            v-for="row in effectRows"
            :key="`e-${row.key}`"
            class="cv-chip cv-chip-wrap cv-green"
            title="O que o consultor concluiu"
            >{{ row.count }}× {{ row.label }}</span
          >
        </div>
      </div>
      <p v-else-if="enabled" class="text-[11px] text-n-slate-10">
        Ainda sem consultas. O contador aparece aqui assim que o primeiro
        gatilho acontecer (dá para provocar um no 🧪 Testar agente).
      </p>

      <!-- últimas consultas: o que o principal ia fazer × o que saiu -->
      <div v-if="recent.length">
        <button
          class="cv-btn cv-btn-ghost cv-btn-sm"
          :aria-expanded="showRecent"
          @click="showRecent = !showRecent"
        >
          <span
            :class="
              showRecent ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
            class="text-xs"
          />
          {{ showRecent ? 'Esconder' : 'Ver' }}
          {{
            recent.length === 1
              ? 'a última consulta'
              : `as últimas ${recent.length} consultas`
          }}
        </button>
        <div v-if="showRecent" class="space-y-1.5 mt-2">
          <div v-for="item in recent" :key="item.id" class="cv-stat px-3 py-2">
            <button
              class="w-full text-left"
              @click="openItem = openItem === item.id ? null : item.id"
            >
              <p class="text-[10px] text-n-slate-9">
                {{ fmtWhen(item.at) }} · conversa #{{ item.conversation_id }}
                <template v-if="item.contact"> · {{ item.contact }}</template>
                <template v-if="item.record.teste"> · 🧪 teste</template>
              </p>
              <p class="text-xs text-n-slate-12 break-words">
                {{ item.headline }}
              </p>
            </button>
            <div
              v-if="openItem === item.id"
              class="grid grid-cols-1 sm:grid-cols-2 gap-2 mt-2"
            >
              <template v-if="item.record.duvida">
                <div>
                  <p class="text-[10px] text-n-slate-10">Dúvida do principal</p>
                  <p class="text-xs text-n-slate-12 whitespace-pre-wrap">
                    {{ item.record.duvida }}
                  </p>
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-10">
                    Orientação do consultor
                  </p>
                  <p class="text-xs text-n-slate-12 whitespace-pre-wrap">
                    {{ item.record.orientacao || item.record.erro || '—' }}
                  </p>
                </div>
              </template>
              <template v-else>
                <div>
                  <p class="text-[10px] text-n-slate-10">
                    O principal ({{ modelLabel(item.record.principal) }}) ia
                    responder
                  </p>
                  <p class="text-xs text-n-slate-12 whitespace-pre-wrap">
                    {{ textOf(item.record.antes) }}
                  </p>
                  <span
                    v-for="flag in flagsOf(item.record.antes)"
                    :key="flag"
                    class="cv-chip cv-amber mt-1 mr-1"
                    >{{ flag }}</span
                  >
                </div>
                <div>
                  <p class="text-[10px] text-n-slate-10">
                    O consultor ({{ modelLabel(item.record.modelo) }})
                    {{ item.record.aplicado ? 'respondeu' : 'responderia' }}
                  </p>
                  <p class="text-xs text-n-slate-12 whitespace-pre-wrap">
                    {{
                      item.record.depois
                        ? textOf(item.record.depois)
                        : item.record.erro || '—'
                    }}
                  </p>
                  <span
                    v-for="flag in flagsOf(item.record.depois)"
                    :key="flag"
                    class="cv-chip cv-green mt-1 mr-1"
                    >{{ flag }}</span
                  >
                </div>
              </template>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
