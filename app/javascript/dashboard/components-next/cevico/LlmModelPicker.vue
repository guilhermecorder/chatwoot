<script setup>
// 🧠 LIBERDADE DE MODELO (22/11/2026): seletor ÚNICO de modelo de IA, usado
// em todo agente. Mostra os 3 fornecedores oficiais — Anthropic (Claude),
// OpenAI (ChatGPT) e Google (Gemini) — com os recomendados (com preço), os que
// a chave de cada um enxerga ("Buscar todos os modelos") e "Outro modelo" para
// digitar qualquer id. Fornecedor sem chave aparece, mas travado, com o aviso
// de onde salvar a chave (CRM → Integrações).
import { computed, ref, watch } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import { sharedLlmCatalog as shared } from './llmCatalog';

const props = defineProps({
  modelValue: { type: String, default: '' },
  // settings.ai.llm_catalog (lista guardada; a completa vem do botão)
  catalog: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  // texto da opção vazia (ex.: "⭐ Recomendado — Sonnet 5"); null = sem opção vazia
  emptyLabel: { type: String, default: null },
  // aviso curto embaixo quando o modelo não é do Claude
  engineNote: { type: Boolean, default: true },
  selectClass: { type: String, default: 'cv-input w-full text-sm' },
});
const emit = defineEmits(['update:modelValue']);

// `shared` = lista completa compartilhada por todos os seletores (1 busca só)
const fullCatalog = computed(() => shared.value || props.catalog || []);
const loading = ref(false);
const loadError = ref('');
const testing = ref(false);
const testResult = ref(null);

const CUSTOM = '__outro__';
const allValues = computed(() =>
  fullCatalog.value.flatMap(p => (p.models || []).map(m => m.value))
);
const customMode = ref(false);
const customText = ref('');

const syncFromValue = v => {
  const known = !v || allValues.value.includes(v);
  customMode.value = !known;
  if (!known) customText.value = v;
};
watch(() => props.modelValue, syncFromValue, { immediate: true });
watch(allValues, () => syncFromValue(props.modelValue));

const selectValue = computed(() =>
  customMode.value ? CUSTOM : props.modelValue || ''
);

const onSelect = event => {
  const v = event.target.value;
  testResult.value = null;
  if (v === CUSTOM) {
    customMode.value = true;
    customText.value = '';
    return;
  }
  customMode.value = false;
  emit('update:modelValue', v);
};

const onCustom = () => {
  testResult.value = null;
  emit('update:modelValue', customText.value.trim());
};

const providerOf = id => {
  const v = String(id || '').trim();
  const prefix = v.includes(':') ? v.split(':')[0] : '';
  if (['anthropic', 'openai', 'google'].includes(prefix)) return prefix;
  const hit = fullCatalog.value.find(p =>
    (p.models || []).some(m => m.value === v)
  );
  if (hit) return hit.id;
  if (/^claude/i.test(v)) return 'anthropic';
  if (/^(gpt|chatgpt|o\d|codex)/i.test(v)) return 'openai';
  if (/^(gemini|gemma|learnlm)/i.test(v)) return 'google';
  return null;
};

const current = computed(() => {
  const id = providerOf(props.modelValue);
  return fullCatalog.value.find(p => p.id === id) || null;
});

const groupLabel = p =>
  p.key_set ? p.label : `${p.label} — falta a chave em CRM → Integrações`;

const money = n =>
  n == null ? '' : `US$ ${Number(n).toLocaleString('pt-BR')}`;
const optionLabel = m => {
  const parts = [m.label];
  if (m.hint) parts.push(m.hint);
  if (m.price_in != null)
    parts.push(`${money(m.price_in)} / ${money(m.price_out)} por milhão`);
  return parts.join(' — ');
};

const recommendedOf = p => (p.models || []).filter(m => m.recommended);
const othersOf = p => (p.models || []).filter(m => !m.recommended);

const fetchAll = async () => {
  loading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.llmModels(true);
    shared.value = data.providers || [];
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Não consegui buscar a lista agora.';
  } finally {
    loading.value = false;
  }
};

const testModel = async () => {
  if (!props.modelValue) return;
  testing.value = true;
  testResult.value = null;
  try {
    const { data } = await CrmAPI.testLlm(props.modelValue);
    testResult.value = data;
  } catch (e) {
    testResult.value = {
      success: false,
      message: e?.response?.data?.message || 'Falha ao testar o modelo.',
    };
  } finally {
    testing.value = false;
  }
};

const unknownProvider = computed(
  () => customMode.value && customText.value && !providerOf(customText.value)
);
const missingKey = computed(
  () => !!props.modelValue && current.value && !current.value.key_set
);
</script>

<template>
  <div class="llm-picker">
    <select
      :value="selectValue"
      :disabled="disabled"
      :class="selectClass"
      class="disabled:cursor-not-allowed"
      @change="onSelect"
    >
      <option v-if="emptyLabel !== null" value="">{{ emptyLabel }}</option>
      <optgroup v-for="p in fullCatalog" :key="p.id" :label="groupLabel(p)">
        <option
          v-for="m in recommendedOf(p)"
          :key="m.value"
          :value="m.value"
          :disabled="!p.key_set && modelValue !== m.value"
        >
          {{ optionLabel(m) }}
        </option>
        <option
          v-for="m in othersOf(p)"
          :key="m.value"
          :value="m.value"
          :disabled="!p.key_set && modelValue !== m.value"
        >
          {{ m.label }}
        </option>
      </optgroup>
      <option :value="CUSTOM">Outro modelo (digitar o id)…</option>
    </select>

    <input
      v-if="customMode"
      v-model="customText"
      :disabled="disabled"
      type="text"
      class="cv-input w-full text-sm mt-1.5 font-mono"
      placeholder="ex.: gpt-6.2-sol · gemini-4-neon · claude-opus-5-5 · openai:meu-modelo"
      @change="onCustom"
      @blur="onCustom"
    />

    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1.5 text-[11px]">
      <button
        type="button"
        class="text-n-blue-11 hover:underline disabled:opacity-50"
        :disabled="loading"
        @click="fetchAll"
      >
        {{ loading ? 'Buscando…' : 'Buscar todos os modelos da conta' }}
      </button>
      <button
        v-if="modelValue && !disabled"
        type="button"
        class="text-n-blue-11 hover:underline disabled:opacity-50"
        :disabled="testing"
        @click="testModel"
      >
        {{ testing ? 'Testando…' : 'Testar este modelo' }}
      </button>
      <span v-if="current" class="text-n-slate-10">{{ current.label }}</span>
    </div>

    <p v-if="loadError" class="text-[11px] mt-1 text-red-500">
      {{ loadError }}
    </p>
    <p v-if="unknownProvider" class="text-[11px] mt-1 text-red-500">
      Não reconheci o fornecedor. Comece com claude-, gpt- ou gemini-, ou use
      "openai:", "google:" ou "anthropic:" na frente.
    </p>
    <p v-else-if="missingKey" class="text-[11px] mt-1 text-red-500">
      Falta a chave do {{ current.label }} em CRM → Integrações. Sem ela o
      agente continua no Claude.
    </p>
    <p
      v-else-if="engineNote && current && current.id !== 'anthropic'"
      class="text-[11px] mt-1 text-n-slate-10"
    >
      Mesmo prompt, ferramentas e travas; só muda quem pensa. Nos atendentes, se
      o {{ current.label }} falhar numa conversa real, o Claude responde no
      lugar e fica anotado.
    </p>
    <p
      v-if="testResult"
      class="text-[11px] mt-1"
      :class="testResult.success ? 'text-n-teal-11' : 'text-red-500'"
    >
      {{ testResult.message }}
    </p>
  </div>
</template>
