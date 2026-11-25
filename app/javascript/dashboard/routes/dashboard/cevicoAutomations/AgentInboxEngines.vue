<script setup>
// 📥 MOTOR POR CAIXA (item 416, 25/11): uma caixa de entrada com motor,
// esforço e Roteiro PRÓPRIOS neste atendente, sem mexer nas outras caixas.
// Vence o teste A/B e o motor por coluna (só nesta caixa). Salva na hora.
import { ref, computed, watch, onMounted } from 'vue';
import LlmModelPicker from 'dashboard/components-next/cevico/LlmModelPicker.vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  agentKey: { type: String, required: true },
  // settings.ai.llm_catalog (Claude, ChatGPT, Gemini)
  llmCatalog: { type: Array, default: () => [] },
  // muda quando o cartão é publicado (caixas novas): recarrega a lista
  refreshKey: { type: [String, Number], default: '' },
});

const EFFORTS = [
  { value: 'low', label: 'Baixo' },
  { value: 'medium', label: 'Médio' },
  { value: 'high', label: 'Alto' },
  { value: 'xhigh', label: 'Muito alto' },
  { value: 'max', label: 'Máximo' },
];
const SCRIPTS = [
  { value: 'v1', label: 'Roteiro 1 (oficial)' },
  { value: 'v2', label: 'Roteiro 2 (prompt novo)' },
];

const loading = ref(true);
const saving = ref(false);
const data = ref(null);
const choices = ref({});
const adding = ref('');

const clean = raw =>
  Object.fromEntries(
    Object.entries(raw || {})
      .map(([id, entry]) => [
        id,
        Object.fromEntries(
          Object.entries(entry || {}).filter(([, value]) => value)
        ),
      ])
      .filter(([, entry]) => Object.keys(entry).length)
  );

const apply = payload => {
  data.value = payload;
  choices.value = JSON.parse(JSON.stringify(payload.inbox_engines || {}));
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

const inboxes = computed(() => data.value?.inboxes || []);
const inboxName = id =>
  inboxes.value.find(inbox => inbox.id === id)?.name || `Caixa ${id}`;
const rows = computed(() =>
  inboxes.value.filter(inbox => choices.value[inbox.id])
);
const free = computed(() =>
  inboxes.value.filter(inbox => !choices.value[inbox.id])
);
const custom = computed(() => Object.keys(clean(choices.value)).length);
const dirty = computed(
  () =>
    JSON.stringify(clean(data.value?.inbox_engines)) !==
    JSON.stringify(clean(choices.value))
);
const effortCard = computed(() => {
  const found = EFFORTS.find(e => e.value === data.value?.default_effort);
  return found ? found.label.toLowerCase() : 'o padrão';
});

const setField = (id, field, value) => {
  choices.value = {
    ...choices.value,
    [id]: { ...(choices.value[id] || {}), [field]: value || null },
  };
};
const addInbox = id => {
  if (!id) return;
  choices.value = { ...choices.value, [id]: {} };
  adding.value = '';
};
const removeInbox = id => {
  const next = { ...choices.value };
  delete next[id];
  choices.value = next;
};

const save = async () => {
  if (saving.value) return;
  saving.value = true;
  try {
    const { data: payload } = await CrmAPI.saveAiStageModels({
      agent: props.agentKey,
      part: 'inbox',
      inbox_engines: clean(choices.value),
    });
    apply(payload);
    useAlert('Motor por caixa salvo: já vale para a próxima resposta');
  } catch (e) {
    useAlert(
      e?.response?.data?.error || 'Não consegui salvar o motor da caixa'
    );
  } finally {
    saving.value = false;
  }
};

onMounted(load);
watch(() => [props.agentKey, props.refreshKey], load);
</script>

<template>
  <div class="cv-sub p-4 mb-4 space-y-3">
    <div>
      <p class="text-sm font-bold text-n-slate-12">
        📥 Motor por caixa
        <span v-if="custom" class="cv-chip cv-chip-on ml-1 align-middle">
          {{ custom }} {{ custom === 1 ? 'caixa' : 'caixas' }} com motor próprio
        </span>
      </p>
      <p class="text-[11px] text-n-slate-10 mt-0.5">
        Para testar uma caixa de entrada com outra IA, outro esforço ou outro
        Roteiro sem mexer nas outras. Nesta caixa, vale o que está aqui no lugar
        do teste A/B e do motor por coluna.
      </p>
    </div>

    <p v-if="loading" class="text-[11px] text-n-slate-10">Carregando…</p>
    <p v-else-if="!data" class="text-[11px] text-red-500">
      Não consegui carregar as caixas deste agente.
    </p>

    <template v-else>
      <div
        v-for="inbox in rows"
        :key="inbox.id"
        class="cv-stat px-3 py-3 space-y-2"
      >
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm font-medium text-n-slate-12 min-w-0 truncate">
            {{ inboxName(inbox.id) }}
          </span>
          <button
            class="cv-btn cv-btn-sm cv-btn-ghost flex-shrink-0"
            :disabled="saving"
            @click="removeInbox(inbox.id)"
          >
            Tirar
          </button>
        </div>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
          <label class="block min-w-0">
            <span class="text-[10px] text-n-slate-10">Motor</span>
            <LlmModelPicker
              :model-value="choices[inbox.id]?.model || ''"
              :catalog="llmCatalog"
              :disabled="saving"
              :engine-note="false"
              empty-label="O de sempre (teste, coluna ou cartão)"
              @update:model-value="value => setField(inbox.id, 'model', value)"
            />
          </label>
          <label class="block min-w-0">
            <span class="text-[10px] text-n-slate-10">Esforço</span>
            <select
              class="cv-input w-full text-sm inbox-effort"
              :value="choices[inbox.id]?.effort || ''"
              :disabled="saving"
              @change="setField(inbox.id, 'effort', $event.target.value)"
            >
              <option value="">O do cartão ({{ effortCard }})</option>
              <option v-for="e in EFFORTS" :key="e.value" :value="e.value">
                {{ e.label }}
              </option>
            </select>
          </label>
          <label class="block min-w-0">
            <span class="text-[10px] text-n-slate-10">Roteiro</span>
            <select
              class="cv-input w-full text-sm inbox-script"
              :value="choices[inbox.id]?.script || ''"
              :disabled="saving"
              @change="setField(inbox.id, 'script', $event.target.value)"
            >
              <option value="">O de sempre (teste ou oficial)</option>
              <option v-for="s in SCRIPTS" :key="s.value" :value="s.value">
                {{ s.label }}
              </option>
            </select>
          </label>
        </div>
      </div>

      <div v-if="free.length" class="w-full sm:w-72">
        <select
          v-model="adding"
          class="cv-input w-full text-sm inbox-add"
          :disabled="saving"
          @change="addInbox(adding)"
        >
          <option value="">+ Dar motor próprio a uma caixa…</option>
          <option v-for="inbox in free" :key="inbox.id" :value="inbox.id">
            {{ inbox.name }}
          </option>
        </select>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button
          class="cv-btn cv-btn-sm inbox-save"
          :disabled="saving || !dirty"
          @click="save"
        >
          {{ saving ? 'Salvando…' : 'Salvar caixas' }}
        </button>
        <span v-if="dirty" class="text-[11px] text-n-slate-10">
          Há mudança sem salvar
        </span>
      </div>
    </template>
  </div>
</template>
