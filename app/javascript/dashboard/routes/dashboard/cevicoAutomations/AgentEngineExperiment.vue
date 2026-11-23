<script setup>
// 🧪 TESTE A/B DE MOTOR (item 400, 22/11): o mesmo atendente e o mesmo Roteiro
// em duas variantes. A = o modelo do cartão; B = outro modelo (Claude ou
// ChatGPT). Cada caixa em que o agente lê fica em A, em B ou em sorteio meio a
// meio por conversa. O placar compara conversão e custo por atendimento.
// Salva na hora (não passa pelo rascunho/publicar do cartão).
import { ref, computed, watch, onMounted } from 'vue';
import LlmModelPicker from 'dashboard/components-next/cevico/LlmModelPicker.vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  agentKey: { type: String, required: true },
  // caixas de WhatsApp em que o agente lê: [{ id, name }]
  inboxes: { type: Array, default: () => [] },
  claudeModels: { type: Array, default: () => [] },
  openaiModels: { type: Array, default: () => [] },
  // 🧠 22/11: settings.ai.llm_catalog (Claude, ChatGPT, Gemini)
  llmCatalog: { type: Array, default: () => [] },
});

const MODES = [
  { key: 'a', label: 'A' },
  { key: 'b', label: 'B' },
  { key: 'split', label: 'Sorteio' },
];

const ON_GRADIENT = 'linear-gradient(135deg, #059669, #34D399)';

const loading = ref(true);
const saving = ref(false);
const data = ref(null);
const enabled = ref(false);
const modelB = ref('');
const modes = ref({});

const shortLabel = label => String(label || '').split(' — ')[0];
const modelLabel = id => {
  const found =
    props.claudeModels.find(m => m.value === id) ||
    props.openaiModels.find(m => m.value === id) ||
    props.llmCatalog.flatMap(p => p.models || []).find(m => m.value === id);
  return found ? shortLabel(found.label) : id || 'não escolhido';
};

const apply = payload => {
  data.value = payload;
  enabled.value = payload.config.enabled === true;
  modelB.value = payload.config.model_b || '';
  modes.value = { ...(payload.config.inboxes || {}) };
};

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAiExperiment(props.agentKey);
    apply(payload);
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

const modeOf = id => modes.value[String(id)] || 'a';
const setMode = (id, mode) => {
  const next = { ...modes.value };
  if (mode === 'a') delete next[String(id)];
  else next[String(id)] = mode;
  modes.value = next;
};

const save = async ({ reset = false, turnOn = null } = {}) => {
  if (saving.value) return;
  saving.value = true;
  try {
    const { data: payload } = await CrmAPI.saveAiExperiment({
      agent: props.agentKey,
      enabled: turnOn === null ? enabled.value : turnOn,
      model_b: modelB.value,
      inboxes: modes.value,
      reset,
    });
    apply(payload);
    if (reset) useAlert('Placar zerado: o teste começa de novo agora');
    else useAlert(enabled.value ? 'Teste A/B salvo e ligado' : 'Teste salvo');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o teste');
  } finally {
    saving.value = false;
  }
};

const toggle = () => save({ turnOn: !enabled.value });
const resetScore = () => {
  // eslint-disable-next-line no-alert
  if (window.confirm('Zerar o placar e começar o teste de novo?'))
    save({ reset: true });
};

const dirty = computed(() => {
  const cfg = data.value?.config;
  if (!cfg) return false;
  return (
    (cfg.model_b || '') !== modelB.value ||
    JSON.stringify(cfg.inboxes || {}) !== JSON.stringify(modes.value)
  );
});

const arms = computed(() => data.value?.report?.arms || []);
const armOf = key => arms.value.find(a => a.arm === key) || {};
const hasScore = computed(() =>
  arms.value.some(a => a.conversas > 0 || a.custo_usd > 0)
);
const shadowOnly = computed(
  () => hasScore.value && arms.value.every(a => !a.respostas && a.sombras > 0)
);

const rate = computed(() => Number(data.value?.usd_brl) || 0);
const money = usd => {
  if (usd === null || usd === undefined) return '—';
  if (rate.value) {
    return (usd * rate.value).toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
      minimumFractionDigits: 2,
      maximumFractionDigits: usd * rate.value < 1 ? 3 : 2,
    });
  }
  const digits = usd < 1 ? 4 : 2;
  return `US$ ${Number(usd).toLocaleString('pt-BR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })}`;
};
const pct = value =>
  value === null || value === undefined
    ? '—'
    : `${String(value).replace('.', ',')}%`;
const withRate = (count, percent) =>
  percent === null || percent === undefined
    ? `${count ?? 0}`
    : `${count} (${pct(percent)})`;

const ROWS = [
  { label: 'Conversas atendidas', value: a => a.conversas ?? 0 },
  { label: 'Respostas enviadas', value: a => a.respostas ?? 0 },
  {
    label: 'Com horário marcado',
    hint: 'a pessoa ganhou horário na Agenda depois de entrar no teste (pela IA ou pela equipe)',
    value: a => withRate(a.com_consulta, a.taxa_consulta),
    strong: true,
  },
  {
    label: 'Agendou pela própria IA',
    value: a => withRate(a.agendou, a.taxa_agendou),
  },
  { label: 'Chamou a equipe', value: a => a.humano ?? 0 },
  {
    label: 'Custo por conversa',
    value: a => money(a.custo_por_conversa_usd),
    strong: true,
  },
  {
    label: 'Custo por horário marcado',
    value: a => money(a.custo_por_consulta_usd),
  },
  { label: 'Custo total', value: a => money(a.custo_usd) },
  {
    label: 'Falhas / Claude cobriu',
    hint: 'chamadas com erro · vezes em que o motor falhou e o Claude respondeu no lugar',
    value: a => `${a.erros ?? 0} / ${a.reservas ?? 0}`,
  },
];

const verdictText = computed(() => {
  const v = data.value?.report?.verdict;
  if (!v || !hasScore.value) return '';
  if (v.status === 'cedo')
    return `Ainda é cedo para concluir: faltam ${v.missing} conversas na variante com menos atendimentos (mínimo de ${data.value.report.min_sample} em cada).`;
  if (v.status === 'empate')
    return 'Com esta amostra, não há diferença confiável de conversão entre as duas: decida pelo custo.';
  return `A variante ${v.status.toUpperCase()} está convertendo mais, com uma diferença que o acaso dificilmente explica (95% de confiança).`;
});

const startedLabel = computed(() => {
  const at = data.value?.report?.started_at;
  return at ? new Date(at).toLocaleDateString('pt-BR') : '';
});

onMounted(load);
watch(() => props.agentKey, load);
</script>

<template>
  <div class="cv-sub p-4 mb-4 space-y-3">
    <div class="flex items-start gap-3">
      <div class="min-w-0 flex-1">
        <p class="text-sm font-bold text-n-slate-12">
          🧪 Teste A/B de motor
          <span
            v-if="enabled"
            class="cv-chip cv-chip-on ml-1 align-middle"
            :style="{ background: ON_GRADIENT }"
            >ligado</span
          >
        </p>
        <p class="text-[11px] text-n-slate-10 mt-0.5">
          O mesmo atendente e o mesmo Roteiro em duas variantes. Só muda o
          motor. O placar compara conversão e custo.
        </p>
      </div>
      <button
        class="cv-switch cv-switch-lg flex-shrink-0"
        :class="enabled ? 'cv-switch-on' : ''"
        :title="enabled ? 'Desligar o teste' : 'Ligar o teste'"
        :disabled="saving || loading || !data"
        :aria-pressed="enabled"
        @click="toggle"
      />
    </div>

    <p v-if="loading" class="text-[11px] text-n-slate-10">Carregando…</p>
    <p v-else-if="!data" class="text-[11px] text-red-500">
      Não consegui carregar o teste deste agente.
    </p>

    <template v-else>
      <!-- as duas variantes -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <div class="cv-stat px-3 py-2">
          <p class="text-[10px] text-n-slate-10">Variante A (a de hoje)</p>
          <p class="text-sm font-bold text-n-slate-12">
            {{ modelLabel(data.model_a) }}
          </p>
          <p class="text-[10px] text-n-slate-9">
            É o "Modelo de IA" deste cartão
          </p>
        </div>
        <div class="cv-stat px-3 py-2">
          <p class="text-[10px] text-n-slate-10 mb-1">Variante B</p>
          <!-- 🧠 22/11: variante B pode ser Claude, ChatGPT ou Gemini -->
          <LlmModelPicker
            v-model="modelB"
            :catalog="llmCatalog"
            :disabled="saving"
            :engine-note="false"
            empty-label="Escolha o modelo…"
          />
        </div>
      </div>

      <!-- modo de cada caixa -->
      <div>
        <p class="text-xs font-medium text-n-slate-11 mb-1.5">
          Quem atende em cada caixa
          <span class="text-n-slate-9 font-normal"
            >(Sorteio = meio a meio por conversa; a conversa fica na mesma
            variante até o fim)</span
          >
        </p>
        <p v-if="!inboxes.length" class="text-[11px] text-n-slate-10">
          Este agente ainda não lê nenhuma caixa: marque as caixas dele abaixo e
          publique.
        </p>
        <div class="space-y-1.5">
          <div
            v-for="ib in inboxes"
            :key="ib.id"
            class="flex flex-wrap items-center gap-x-3 gap-y-1"
          >
            <span class="text-sm text-n-slate-12 min-w-0 flex-1 basis-40">
              {{ ib.name }}
            </span>
            <div class="cv-seg cv-seg-sm flex-shrink-0">
              <button
                v-for="m in MODES"
                :key="m.key"
                class="cv-seg-item"
                :class="{ 'cv-seg-on': modeOf(ib.id) === m.key }"
                :disabled="saving"
                @click="setMode(ib.id, m.key)"
              >
                {{ m.label }}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button
          class="cv-btn cv-btn-sm"
          :disabled="saving || !dirty"
          @click="save()"
        >
          {{ saving ? 'Salvando…' : 'Salvar teste' }}
        </button>
        <button
          v-if="hasScore"
          class="cv-btn cv-btn-ghost cv-btn-sm"
          :disabled="saving"
          @click="resetScore"
        >
          Zerar placar
        </button>
        <button
          class="cv-btn cv-btn-ghost cv-btn-sm"
          :disabled="loading"
          @click="load"
        >
          Atualizar
        </button>
        <span v-if="dirty" class="text-[11px] text-amber-600">
          Há mudanças não salvas
        </span>
      </div>

      <!-- placar -->
      <div v-if="hasScore" class="pt-1">
        <p class="text-xs font-medium text-n-slate-11 mb-1.5">
          Placar desde {{ startedLabel }}
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="text-[11px] text-n-slate-10 text-left">
                <th class="font-medium py-1 pr-2" />
                <th class="font-medium py-1 px-2 text-right">
                  A · {{ modelLabel(armOf('a').model || data.model_a) }}
                </th>
                <th class="font-medium py-1 pl-2 text-right">
                  B · {{ modelLabel(armOf('b').model || modelB) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in ROWS"
                :key="row.label"
                class="border-t border-n-weak"
              >
                <td
                  class="py-1.5 pr-2 text-n-slate-11 text-xs"
                  :title="row.hint"
                >
                  {{ row.label }}
                </td>
                <td
                  class="py-1.5 px-2 text-right tabular-nums whitespace-nowrap text-n-slate-12"
                  :class="row.strong ? 'font-bold' : ''"
                >
                  {{ row.value(armOf('a')) }}
                </td>
                <td
                  class="py-1.5 pl-2 text-right tabular-nums whitespace-nowrap text-n-slate-12"
                  :class="row.strong ? 'font-bold' : ''"
                >
                  {{ row.value(armOf('b')) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-if="verdictText" class="text-[11px] text-n-slate-11 mt-2">
          {{ verdictText }}
        </p>
        <p v-if="shadowOnly" class="text-[11px] text-n-slate-10 mt-1">
          O agente está em sombra: nada foi enviado ao cliente, então o que
          vale comparar por enquanto é o custo e a leitura das respostas na tela
          Sombra.
        </p>
        <p v-if="data.report.mixed" class="text-[11px] text-n-slate-10 mt-1">
          {{ data.report.mixed }} conversa(s) viram os dois motores (a caixa
          mudou de variante no meio) e ficaram fora do placar.
        </p>
        <p v-if="!rate" class="text-[11px] text-n-slate-10 mt-1">
          Sem a cotação do dólar de hoje: custos em US$.
        </p>
      </div>
      <p v-else-if="enabled" class="text-[11px] text-n-slate-10">
        Teste ligado. O placar aparece depois do primeiro atendimento numa caixa
        do teste.
      </p>
    </template>
  </div>
</template>
