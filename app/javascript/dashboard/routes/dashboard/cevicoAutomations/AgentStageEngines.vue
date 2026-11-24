<script setup>
// 🧭 MOTOR POR COLUNA DO CRM (23/11): o mesmo atendente e o mesmo Roteiro, mas
// o modelo de IA que responde muda conforme a coluna em que o card do paciente
// está (ex.: recepção em "Novos Contatos" com um modelo barato; a partir de
// "Envio de Orçamento", o Claude). Coluna sem escolha = o modelo do cartão.
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
  // muda quando o cartão é publicado (colunas novas): recarrega a lista
  refreshKey: { type: [String, Number], default: '' },
});

const loading = ref(true);
const saving = ref(false);
const data = ref(null);
const choices = ref({});

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
  choices.value = { ...(payload.stage_models || {}) };
};

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAiStageModels(props.agentKey);
    apply(payload);
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

const setChoice = (slot, model) => {
  const next = { ...choices.value };
  if (model) next[slot] = model;
  else delete next[slot];
  choices.value = next;
};

const stages = computed(() => data.value?.stages || []);
const custom = computed(() => Object.keys(choices.value).length);
const dirty = computed(
  () =>
    JSON.stringify(data.value?.stage_models || {}) !==
    JSON.stringify(choices.value)
);

const save = async () => {
  if (saving.value) return;
  saving.value = true;
  try {
    const { data: payload } = await CrmAPI.saveAiStageModels({
      agent: props.agentKey,
      stage_models: choices.value,
    });
    apply(payload);
    useAlert('Motor por coluna salvo: já vale para a próxima resposta');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar o motor');
  } finally {
    saving.value = false;
  }
};

const rate = computed(() => Number(data.value?.usd_brl) || 0);
const money = usd => {
  if (rate.value) {
    return (usd * rate.value).toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    });
  }
  return `US$ ${Number(usd).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
};
const usage = computed(() => data.value?.usage_7d || []);
const perCall = row => (row.calls ? money(row.cost_usd / row.calls) : '—');

onMounted(load);
watch(() => [props.agentKey, props.refreshKey], load);
</script>

<template>
  <div class="cv-sub p-4 mb-4 space-y-3">
    <div>
      <p class="text-sm font-bold text-n-slate-12">
        🧭 Motor por coluna do CRM
        <span v-if="custom" class="cv-chip cv-chip-on ml-1 align-middle">
          {{ custom }} {{ custom === 1 ? 'coluna' : 'colunas' }} com motor
          próprio
        </span>
      </p>
      <p class="text-[11px] text-n-slate-10 mt-0.5">
        O mesmo atendente e o mesmo Roteiro. Só muda qual IA responde em cada
        coluna: um modelo barato na recepção e um mais forte depois do
        orçamento, por exemplo.
      </p>
    </div>

    <p v-if="loading" class="text-[11px] text-n-slate-10">Carregando…</p>
    <p v-else-if="!data" class="text-[11px] text-red-500">
      Não consegui carregar as colunas deste agente.
    </p>

    <template v-else>
      <p v-if="!stages.length" class="text-[11px] text-n-slate-10">
        Este agente ainda não lê nenhuma coluna: marque as colunas dele abaixo e
        publique.
      </p>
      <div class="space-y-2">
        <div
          v-for="stage in stages"
          :key="stage.slot"
          class="flex flex-wrap items-center gap-x-3 gap-y-1"
        >
          <span class="text-sm text-n-slate-12 min-w-0 flex-1 basis-40">
            {{ stage.name }}
          </span>
          <div class="w-full sm:w-72 flex-shrink-0">
            <LlmModelPicker
              :model-value="choices[stage.slot] || ''"
              :catalog="llmCatalog"
              :disabled="saving"
              :engine-note="false"
              :empty-label="`O do cartão (${modelLabel(data.default_model)})`"
              @update:model-value="value => setChoice(stage.slot, value)"
            />
          </div>
        </div>
      </div>

      <p class="text-[11px] text-n-slate-10">
        Vale a coluna em que o card está na hora da resposta. Se o motor de uma
        coluna falhar, outro responde no lugar. Com o Teste A/B ligado, a
        conversa que cair na variante B usa o modelo da variante B.
      </p>

      <div class="flex flex-wrap items-center gap-2">
        <button
          class="cv-btn cv-btn-sm"
          :disabled="saving || !dirty"
          @click="save"
        >
          {{ saving ? 'Salvando…' : 'Salvar motores' }}
        </button>
        <span v-if="dirty" class="text-[11px] text-n-slate-10">
          Há mudança sem salvar
        </span>
      </div>

      <div v-if="usage.length">
        <p class="text-xs font-medium text-n-slate-11 mb-1.5">
          Gasto deste atendente por modelo
          <span class="text-n-slate-9 font-normal">(últimos 7 dias)</span>
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
          <div v-for="row in usage" :key="row.model" class="cv-stat px-3 py-2">
            <p class="text-[10px] text-n-slate-10 truncate">
              {{ modelLabel(row.model) }}
            </p>
            <p class="text-sm font-bold text-n-slate-12">
              {{ money(row.cost_usd) }}
            </p>
            <p class="text-[10px] text-n-slate-9">
              {{ row.calls.toLocaleString('pt-BR') }} chamadas ·
              {{ perCall(row) }} cada
            </p>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
