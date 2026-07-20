<script setup>
// TRATAMENTO DE DADOS UNIFICADO (item 70): todas as ferramentas de
// limpeza e enriquecimento da base num componente só, montado dentro de
// Automações → Tratamento de dados (a casa oficial). Duas famílias:
// IDENTIFICAÇÃO TRADICIONAL (filtros e etiquetas em massa, com prévia
// antes de aplicar) e COM INTELIGÊNCIA (detecção de valores nas
// conversas). Extraído da Campanha WhatsApp, mesma lógica testada.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();

// ── dados de apoio (buscados aqui mesmo — o componente é autônomo) ──
const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');
const pipelines = useMapGetter('crm/getPipelines');

const allStages = computed(() =>
  pipelines.value.flatMap(p =>
    (p.stages ?? []).map(s => ({ ...s, pipeline_name: p.name }))
  )
);

onMounted(() => {
  Promise.all([
    store.dispatch('crm/fetchPipelines'),
    store.dispatch('labels/get'),
    store.dispatch('inboxes/get'),
  ]);
});

// ── Etiquetar e/ou MOVER por conteúdo (retroativo) ──────────────────
const retro = ref({
  term: '',
  labelChoice: '',
  newLabel: '',
  target_stage_id: '',
  period_from: '',
  period_to: '',
  apply_to_contact: true,
});

const retroLabel = computed(() =>
  retro.value.labelChoice === '__nova__'
    ? retro.value.newLabel.trim()
    : retro.value.labelChoice
);
const retroPreview = ref(null);
const isRetroLoading = ref(false);
const isRetroApplying = ref(false);
const showRetroPanel = ref(false);

const retroPayload = () => ({
  term: retro.value.term.trim(),
  label: retroLabel.value,
  target_stage_id: retro.value.target_stage_id || undefined,
  period_from: retro.value.period_from,
  period_to: retro.value.period_to,
  apply_to_contact: retro.value.apply_to_contact,
});

// precisa de pelo menos uma ação: etiqueta ou coluna
const retroHasAction = computed(
  () => !!retroLabel.value || !!retro.value.target_stage_id
);

const previewRetro = async () => {
  if (!retro.value.term.trim()) return;
  isRetroLoading.value = true;
  retroPreview.value = null;
  try {
    retroPreview.value = await store.dispatch('crm/previewRetroLabel', retroPayload());
  } catch {
    useAlert('Erro ao calcular as conversas');
  } finally {
    isRetroLoading.value = false;
  }
};

const applyRetro = async () => {
  if (!retro.value.term.trim() || !retroHasAction.value) return;
  isRetroApplying.value = true;
  try {
    await store.dispatch('crm/applyRetroLabel', retroPayload());
    useAlert(
      'Processando em segundo plano — em alguns minutos as conversas estarão organizadas.'
    );
    retroPreview.value = null;
    retro.value.term = '';
    retro.value.labelChoice = '';
    retro.value.newLabel = '';
    retro.value.target_stage_id = '';
  } catch {
    useAlert('Erro ao aplicar');
  } finally {
    isRetroApplying.value = false;
  }
};

// ── Mover e etiquetar em LOTE (coluna/valor/caixa/etiqueta) ─────────
const showBatchPanel = ref(false);
const batch = ref({
  stage_id: '',
  value_filter: '',
  inbox_id: '',
  label: '',
  target_stage_id: '',
  addLabelChoice: '',
  newAddLabel: '',
});
const batchPreview = ref(null);
const isBatchLoading = ref(false);
const isBatchApplying = ref(false);

const batchAddLabel = computed(() =>
  batch.value.addLabelChoice === '__nova__'
    ? batch.value.newAddLabel.trim()
    : batch.value.addLabelChoice
);

const batchHasFilter = computed(
  () =>
    !!batch.value.stage_id ||
    !!batch.value.value_filter ||
    !!batch.value.inbox_id ||
    !!batch.value.label
);
const batchHasAction = computed(
  () => !!batch.value.target_stage_id || !!batchAddLabel.value
);

const batchPayload = () => ({
  stage_id: batch.value.stage_id || undefined,
  value_filter: batch.value.value_filter || undefined,
  inbox_id: batch.value.inbox_id || undefined,
  label: batch.value.label || undefined,
  target_stage_id: batch.value.target_stage_id || undefined,
  add_label: batchAddLabel.value || undefined,
});

const previewBatch = async () => {
  if (!batchHasFilter.value) return;
  isBatchLoading.value = true;
  batchPreview.value = null;
  try {
    const { data } = await CrmAPI.previewBatchUpdate(batchPayload());
    batchPreview.value = data;
  } catch {
    useAlert('Erro ao calcular os cards.');
  } finally {
    isBatchLoading.value = false;
  }
};

const applyBatch = async () => {
  if (!batchHasFilter.value || !batchHasAction.value) return;
  isBatchApplying.value = true;
  try {
    await CrmAPI.applyBatchUpdate(batchPayload());
    useAlert('Processando em segundo plano — os cards serão movidos/etiquetados em alguns minutos.');
    batchPreview.value = null;
    batch.value = {
      stage_id: '',
      value_filter: '',
      inbox_id: '',
      label: '',
      target_stage_id: '',
      addLabelChoice: '',
      newAddLabel: '',
    };
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Erro ao aplicar.');
  } finally {
    isBatchApplying.value = false;
  }
};

// ── Preencher valores pelo orçamento (identificação com IA) ─────────
const showValuePanel = ref(false);
const valueOnlyEmpty = ref(true);
const isValueRunning = ref(false);

const runBulkValues = async () => {
  if (isValueRunning.value || !pipelines.value.length) return;
  isValueRunning.value = true;
  try {
    await Promise.all(
      pipelines.value.map(p =>
        store.dispatch('crm/detectValuesBulk', { pipelineId: p.id, onlyEmpty: valueOnlyEmpty.value })
      )
    );
    useAlert('Processando em segundo plano — os valores aparecem em instantes.');
    showValuePanel.value = false;
  } catch {
    useAlert('Erro ao iniciar o preenchimento de valores');
  } finally {
    isValueRunning.value = false;
  }
};

// ── Substituir etiquetas ────────────────────────────────────────────
const showReplacePanel = ref(false);
const replaceFrom = ref('');
const replaceTo = ref('');
const replacePreview = ref(null);
const isReplaceLoading = ref(false);
const isReplaceApplying = ref(false);
const showReplaceConfirm = ref(false);

const replaceLabelOptions = computed(() => (labels.value || []).map(l => l.title));

const previewReplace = async () => {
  if (!replaceFrom.value || !replaceTo.value || replaceFrom.value === replaceTo.value) return;
  isReplaceLoading.value = true;
  replacePreview.value = null;
  showReplaceConfirm.value = false;
  try {
    replacePreview.value = await store.dispatch('crm/previewLabelReplace', {
      from: replaceFrom.value,
      to: replaceTo.value,
    });
  } catch {
    useAlert('Erro ao calcular a substituição');
  } finally {
    isReplaceLoading.value = false;
  }
};

const applyReplace = async () => {
  isReplaceApplying.value = true;
  try {
    await store.dispatch('crm/applyLabelReplace', { from: replaceFrom.value, to: replaceTo.value });
    useAlert('Substituição em andamento — as etiquetas serão trocadas em segundo plano.');
    replacePreview.value = null;
    showReplaceConfirm.value = false;
    replaceFrom.value = '';
    replaceTo.value = '';
  } catch {
    useAlert('Erro ao iniciar a substituição');
  } finally {
    isReplaceApplying.value = false;
  }
};

// ── Remover etiqueta em massa ───────────────────────────────────────
const showRemovePanel = ref(false);
const removeLabel = ref('');
const removeStageId = ref('');
const removePreview = ref(null);
const isRemoveLoading = ref(false);
const isRemoveApplying = ref(false);
const showRemoveConfirm = ref(false);

const previewRemove = async () => {
  if (!removeLabel.value) return;
  isRemoveLoading.value = true;
  removePreview.value = null;
  showRemoveConfirm.value = false;
  try {
    removePreview.value = await store.dispatch('crm/previewLabelRemove', {
      label: removeLabel.value,
      stage_id: removeStageId.value || undefined,
    });
  } catch {
    useAlert('Erro ao calcular');
  } finally {
    isRemoveLoading.value = false;
  }
};

const applyRemove = async () => {
  isRemoveApplying.value = true;
  try {
    await store.dispatch('crm/applyLabelRemove', {
      label: removeLabel.value,
      stage_id: removeStageId.value || undefined,
    });
    useAlert('Remoção em andamento — as etiquetas serão removidas em segundo plano.');
    removePreview.value = null;
    showRemoveConfirm.value = false;
    removeLabel.value = '';
    removeStageId.value = '';
  } catch {
    useAlert('Erro ao iniciar a remoção');
  } finally {
    isRemoveApplying.value = false;
  }
};

// ── Unificação de contatos duplicados ───────────────────────────────
const showUnifyPanel = ref(false);
const unifyPreview = ref(null);
const isUnifyLoading = ref(false);
const isUnifyApplying = ref(false);
const showUnifyConfirm = ref(false);

const previewUnify = async () => {
  isUnifyLoading.value = true;
  unifyPreview.value = null;
  showUnifyConfirm.value = false;
  try {
    unifyPreview.value = await store.dispatch('crm/previewContactUnification');
  } catch {
    useAlert('Erro ao calcular os duplicados');
  } finally {
    isUnifyLoading.value = false;
  }
};

const applyUnify = async () => {
  isUnifyApplying.value = true;
  try {
    await store.dispatch('crm/applyContactUnification');
    useAlert('Unificação em andamento — os contatos serão mesclados em segundo plano.');
    unifyPreview.value = null;
    showUnifyConfirm.value = false;
  } catch {
    useAlert('Erro ao iniciar a unificação');
  } finally {
    isUnifyApplying.value = false;
  }
};
</script>

<template>
  <div class="max-w-3xl">
    <!-- ══ IDENTIFICAÇÃO TRADICIONAL ══ -->
    <p class="text-[11px] font-bold text-n-slate-9 uppercase tracking-wide mb-2 flex items-center gap-1.5">
      <span class="i-lucide-filter text-xs" />
      Identificação tradicional — filtros e etiquetas em massa, sempre com prévia
    </p>

    <!-- Etiquetar e/ou MOVER por conteúdo -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showRetroPanel = !showRetroPanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
          <span class="i-lucide-tag text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">Etiquetar e/ou MOVER por conteúdo</p>
          <p class="text-xs text-n-slate-10">
            Se a conversa contém X, ou Y, ou Z (separe por vírgula) → aplica etiqueta e/ou move o card
            de coluna. A etiqueta é opcional: dá para SÓ mover. Ex: "quero agendar, pode marcar" → coluna Agendamento
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showRetroPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showRetroPanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <div class="flex flex-wrap gap-3">
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">A conversa contém o texto</label>
            <input
              v-model="retro.term"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              placeholder='Ex: 3900  ou  orçamento, orcamento, valor'
              @input="retroPreview = null"
            />
            <p class="text-[11px] text-n-slate-9 mt-1">
              Ignora acentos e maiúsculas. Separe alternativas por vírgula; use
              "aspas" para uma frase exata ser tratada como uma peça só.
            </p>
          </div>
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Recebe a etiqueta <span class="text-n-slate-9">(opcional)</span>
            </label>
            <select
              v-model="retro.labelChoice"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
            >
              <option value="">Sem etiqueta</option>
              <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
              <option value="__nova__">➕ Criar nova etiqueta…</option>
            </select>
            <input
              v-if="retro.labelChoice === '__nova__'"
              v-model="retro.newLabel"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 mt-2"
              placeholder="nome-da-nova-etiqueta"
            />
          </div>
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              E move para a coluna do CRM <span class="text-n-slate-9">(opcional)</span>
            </label>
            <select
              v-model="retro.target_stage_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
            >
              <option value="">Não mover</option>
              <option v-for="s in allStages" :key="s.id" :value="s.id">
                {{ s.pipeline_name }} › {{ s.name }}
              </option>
            </select>
          </div>
        </div>
        <p class="text-xs text-n-slate-9 -mt-1">
          Escolha uma etiqueta, uma coluna, ou as duas. Ex: conversa contém "orçamento" →
          coluna "Envio de Orçamento".
        </p>

        <div class="flex flex-wrap items-center gap-3">
          <label class="text-xs text-n-slate-10">Período (opcional):</label>
          <input
            v-model="retro.period_from"
            type="date"
            class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
            @change="retroPreview = null"
          />
          <span class="text-xs text-n-slate-10">até</span>
          <input
            v-model="retro.period_to"
            type="date"
            class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
            @change="retroPreview = null"
          />
          <label class="flex items-center gap-1.5 text-xs text-n-slate-11 ml-2 cursor-pointer">
            <input v-model="retro.apply_to_contact" type="checkbox" class="rounded" />
            Etiquetar também o contato (para usar em campanhas)
          </label>
        </div>

        <div class="flex flex-wrap items-center gap-3 pt-1">
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
            :disabled="!retro.term.trim() || isRetroLoading"
            @click="previewRetro"
          >
            <span class="i-lucide-search" />
            {{ isRetroLoading ? 'Buscando…' : 'Calcular conversas' }}
          </button>

          <span v-if="retroPreview" class="text-sm text-n-slate-12">
            <b>{{ retroPreview.conversations }}</b> conversa(s) ·
            <b>{{ retroPreview.contacts }}</b> contato(s)
            <span v-if="retroPreview.sample?.length" class="text-xs text-n-slate-9">
              (ex: {{ retroPreview.sample.map(s => s.contact_name).filter(Boolean).slice(0, 3).join(', ') }})
            </span>
          </span>

          <div class="flex-1" />
          <button
            class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            :disabled="!retro.term.trim() || !retroHasAction || !retroPreview || isRetroApplying"
            @click="applyRetro"
          >
            <span class="i-lucide-wand-2" />
            {{ isRetroApplying ? 'Aplicando…' : 'Aplicar' }}
          </button>
        </div>
        <p v-if="retroPreview && !retroHasAction" class="text-xs text-amber-600">
          Escolha uma etiqueta e/ou uma coluna de destino para aplicar.
        </p>
      </div>
    </div>

    <!-- Mover e etiquetar em LOTE -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showBatchPanel = !showBatchPanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #0F5FA6, #3B82F6)">
          <span class="i-lucide-move text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">Mover e etiquetar em LOTE</p>
          <p class="text-xs text-n-slate-10">
            Filtre os cards por coluna, valor, caixa de entrada ou etiqueta → mova todos para outra
            coluna e/ou adicione uma etiqueta (nunca duplica). Ex: cards COM valor em "Novos Contatos"
            → coluna "Envio de Orçamento"; caixa GOOGLE → etiqueta "consulta_google".
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showBatchPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showBatchPanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <p class="text-[11px] font-semibold text-n-slate-9 uppercase tracking-wide">1 · Quais cards? (combine os filtros que quiser)</p>
        <div class="flex flex-wrap gap-3">
          <div class="flex-1 min-w-44">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Estão na coluna</label>
            <select
              v-model="batch.stage_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="batchPreview = null"
            >
              <option value="">Qualquer coluna</option>
              <option v-for="s in allStages" :key="s.id" :value="s.id">
                {{ s.pipeline_name }} › {{ s.name }}
              </option>
            </select>
          </div>
          <div class="flex-1 min-w-44">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Valor no card</label>
            <select
              v-model="batch.value_filter"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="batchPreview = null"
            >
              <option value="">Tanto faz</option>
              <option value="with">COM valor (R$ &gt; 0)</option>
              <option value="without">SEM valor</option>
            </select>
          </div>
          <div class="flex-1 min-w-44">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Chegou pela caixa de entrada</label>
            <select
              v-model="batch.inbox_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="batchPreview = null"
            >
              <option value="">Qualquer caixa</option>
              <option v-for="i in inboxes" :key="i.id" :value="i.id">{{ i.name }}</option>
            </select>
          </div>
          <div class="flex-1 min-w-44">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Contato TEM a etiqueta</label>
            <select
              v-model="batch.label"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="batchPreview = null"
            >
              <option value="">Qualquer etiqueta</option>
              <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
            </select>
          </div>
        </div>

        <p class="text-[11px] font-semibold text-n-slate-9 uppercase tracking-wide pt-1">2 · O que fazer com eles?</p>
        <div class="flex flex-wrap gap-3">
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Mover para a coluna <span class="text-n-slate-9">(opcional)</span>
            </label>
            <select
              v-model="batch.target_stage_id"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
            >
              <option value="">Não mover</option>
              <option v-for="s in allStages" :key="s.id" :value="s.id">
                {{ s.pipeline_name }} › {{ s.name }}
              </option>
            </select>
          </div>
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Adicionar a etiqueta <span class="text-n-slate-9">(opcional — quem já tem, mantém)</span>
            </label>
            <select
              v-model="batch.addLabelChoice"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
            >
              <option value="">Não etiquetar</option>
              <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
              <option value="__nova__">➕ Criar nova etiqueta…</option>
            </select>
            <input
              v-if="batch.addLabelChoice === '__nova__'"
              v-model="batch.newAddLabel"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 mt-2"
              placeholder="nome-da-nova-etiqueta"
            />
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3 pt-1">
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
            :disabled="!batchHasFilter || isBatchLoading"
            @click="previewBatch"
          >
            <span class="i-lucide-search" />
            {{ isBatchLoading ? 'Calculando…' : 'Calcular cards' }}
          </button>

          <span v-if="batchPreview" class="text-sm text-n-slate-12">
            <b>{{ batchPreview.cards }}</b> card(s)
            <span v-if="batchPreview.sample?.length" class="text-xs text-n-slate-9">
              (ex: {{ batchPreview.sample.map(s => s.name).filter(Boolean).slice(0, 3).join(', ') }})
            </span>
          </span>

          <div class="flex-1" />
          <button
            class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
            style="background: linear-gradient(135deg, #0F5FA6, #3B82F6)"
            :disabled="!batchHasFilter || !batchHasAction || !batchPreview || isBatchApplying"
            @click="applyBatch"
          >
            <span class="i-lucide-wand-2" />
            {{ isBatchApplying ? 'Aplicando…' : 'Aplicar no lote' }}
          </button>
        </div>
        <p v-if="!batchHasFilter" class="text-xs text-n-slate-9">
          Escolha pelo menos um filtro — sem filtro o lote não roda (proteção contra mexer na base inteira sem querer).
        </p>
        <p v-else-if="batchPreview && !batchHasAction" class="text-xs text-amber-600">
          Escolha uma coluna de destino e/ou uma etiqueta para aplicar.
        </p>
      </div>
    </div>

    <!-- Substituir etiquetas -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showReplacePanel = !showReplacePanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
          <span class="i-lucide-replace text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">Substituir etiquetas</p>
          <p class="text-xs text-n-slate-10">
            Troca uma etiqueta por outra em todo mundo. Ex.: "refrativa" → "orçamento-refrativa".
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showReplacePanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showReplacePanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <div class="flex flex-wrap items-end gap-3">
          <div class="flex-1 min-w-40">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Etiqueta atual (será removida)</label>
            <input
              v-model="replaceFrom"
              list="treat-replace-from-list"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              placeholder="ex: refrativa"
              @input="replacePreview = null"
            />
            <datalist id="treat-replace-from-list">
              <option v-for="l in replaceLabelOptions" :key="l" :value="l" />
            </datalist>
          </div>
          <span class="i-lucide-arrow-right text-n-slate-9 pb-2.5" />
          <div class="flex-1 min-w-40">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Nova etiqueta (será adicionada)</label>
            <input
              v-model="replaceTo"
              list="treat-replace-to-list"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              placeholder="ex: orçamento-refrativa"
              @input="replacePreview = null"
            />
            <datalist id="treat-replace-to-list">
              <option v-for="l in replaceLabelOptions" :key="l" :value="l" />
            </datalist>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
            :disabled="!replaceFrom || !replaceTo || replaceFrom === replaceTo || isReplaceLoading"
            @click="previewReplace"
          >
            <span class="i-lucide-search" />
            {{ isReplaceLoading ? 'Calculando…' : 'Calcular' }}
          </button>
          <span v-if="replacePreview" class="text-sm text-n-slate-12">
            <b>{{ replacePreview.contacts }}</b> contato(s) ·
            <b>{{ replacePreview.conversations }}</b> conversa(s)
          </span>
        </div>

        <div v-if="replacePreview && (replacePreview.contacts > 0 || replacePreview.conversations > 0)" class="flex items-center gap-3">
          <template v-if="!showReplaceConfirm">
            <button
              class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #5B21B6, #7C3AED)"
              @click="showReplaceConfirm = true"
            >
              <span class="i-lucide-replace" />
              Substituir etiqueta
            </button>
          </template>
          <template v-else>
            <span class="text-xs text-amber-600 font-medium">Confirma trocar "{{ replaceFrom }}" por "{{ replaceTo }}"?</span>
            <button
              class="text-xs px-3 py-1.5 rounded-lg bg-amber-600 text-white disabled:opacity-50"
              :disabled="isReplaceApplying"
              @click="applyReplace"
            >{{ isReplaceApplying ? 'Iniciando…' : 'Sim, substituir' }}</button>
            <button class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11" @click="showReplaceConfirm = false">Cancelar</button>
          </template>
        </div>
        <p v-if="replacePreview && replacePreview.contacts === 0 && replacePreview.conversations === 0" class="text-xs text-n-slate-9">
          Ninguém com a etiqueta "{{ replaceFrom }}".
        </p>
      </div>
    </div>

    <!-- Remover etiqueta em massa -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showRemovePanel = !showRemovePanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #DC2626, #F87171)">
          <span class="i-lucide-tag-off text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">Remover etiqueta em massa</p>
          <p class="text-xs text-n-slate-10">
            Remove uma etiqueta de todo mundo que a tem — opcionalmente só de quem está numa coluna do CRM.
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showRemovePanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showRemovePanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <div class="flex flex-wrap items-end gap-3">
          <div class="flex-1 min-w-40">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Etiqueta a remover</label>
            <select
              v-model="removeLabel"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="removePreview = null"
            >
              <option value="">Escolha a etiqueta…</option>
              <option v-for="l in labels" :key="l.id" :value="l.title">{{ l.title }}</option>
            </select>
          </div>
          <div class="flex-1 min-w-40">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Só de quem está na coluna <span class="text-n-slate-9">(opcional)</span>
            </label>
            <select
              v-model="removeStageId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="removePreview = null"
            >
              <option value="">Todas as pessoas</option>
              <option v-for="s in allStages" :key="s.id" :value="s.id">
                {{ s.pipeline_name }} › {{ s.name }}
              </option>
            </select>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
            :disabled="!removeLabel || isRemoveLoading"
            @click="previewRemove"
          >
            <span class="i-lucide-search" />
            {{ isRemoveLoading ? 'Calculando…' : 'Calcular' }}
          </button>
          <span v-if="removePreview" class="text-sm text-n-slate-12">
            <b>{{ removePreview.contacts }}</b> contato(s) perderão a etiqueta
            <span v-if="removePreview.sample?.length" class="text-xs text-n-slate-9">
              (ex: {{ removePreview.sample.map(s => s.name).filter(Boolean).slice(0, 3).join(', ') }})
            </span>
          </span>
        </div>

        <div v-if="removePreview && removePreview.contacts > 0" class="flex items-center gap-3">
          <template v-if="!showRemoveConfirm">
            <button
              class="text-xs px-4 py-2 rounded-lg bg-red-500 text-white hover:opacity-90 flex items-center gap-1.5"
              @click="showRemoveConfirm = true"
            >
              <span class="i-lucide-tag-off" />
              Remover etiqueta
            </button>
          </template>
          <template v-else>
            <span class="text-xs text-amber-600 font-medium">Confirma remover "{{ removeLabel }}" de {{ removePreview.contacts }} contato(s)?</span>
            <button
              class="text-xs px-3 py-1.5 rounded-lg bg-red-600 text-white disabled:opacity-50"
              :disabled="isRemoveApplying"
              @click="applyRemove"
            >{{ isRemoveApplying ? 'Iniciando…' : 'Sim, remover' }}</button>
            <button class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11" @click="showRemoveConfirm = false">Cancelar</button>
          </template>
        </div>
        <p v-if="removePreview && removePreview.contacts === 0" class="text-xs text-n-slate-9">
          Ninguém encontrado com esse critério.
        </p>
      </div>
    </div>

    <!-- Unificar contatos duplicados -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showUnifyPanel = !showUnifyPanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #0F766E, #14B8A6)">
          <span class="i-lucide-merge text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">Unificar contatos duplicados</p>
          <p class="text-xs text-n-slate-10">
            Mescla contatos com o mesmo telefone ou e-mail (ex: chamou pelo Instagram e pelo WhatsApp).
            Conversas, etiquetas e notas são preservadas no contato unificado.
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showUnifyPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showUnifyPanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <div class="flex flex-wrap items-center gap-3">
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
            :disabled="isUnifyLoading"
            @click="previewUnify"
          >
            <span class="i-lucide-search" />
            {{ isUnifyLoading ? 'Calculando…' : 'Calcular duplicados' }}
          </button>

          <span v-if="unifyPreview" class="text-sm text-n-slate-12">
            <b>{{ unifyPreview.groups }}</b> grupo(s) de duplicados ·
            <b>{{ unifyPreview.contacts_to_merge }}</b> contato(s) serão mesclados
          </span>
        </div>

        <!-- Exemplos -->
        <div v-if="unifyPreview?.examples?.length" class="bg-n-alpha-1 rounded-lg p-3 space-y-1 max-h-48 overflow-y-auto">
          <p class="text-[11px] text-n-slate-9 mb-1">Exemplos do que será unificado:</p>
          <div
            v-for="(ex, i) in unifyPreview.examples"
            :key="i"
            class="text-xs text-n-slate-11 flex items-center gap-2"
          >
            <span class="i-lucide-users text-[11px] text-n-slate-9 flex-shrink-0" />
            <span class="truncate">
              {{ ex.names.join(' + ') }}
              <span class="text-n-slate-9">({{ ex.phone_number || ex.email }} · {{ ex.duplicates }} contatos → 1)</span>
            </span>
          </div>
        </div>

        <div v-if="unifyPreview && unifyPreview.contacts_to_merge > 0" class="flex items-center gap-3">
          <template v-if="!showUnifyConfirm">
            <button
              class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5"
              style="background: linear-gradient(135deg, #0F766E, #14B8A6)"
              @click="showUnifyConfirm = true"
            >
              <span class="i-lucide-merge" />
              Unificar contatos
            </button>
          </template>
          <template v-else>
            <span class="text-xs text-amber-600 font-medium">
              ⚠ A mesclagem não pode ser desfeita. Confirma?
            </span>
            <button
              class="text-xs px-3 py-1.5 rounded-lg bg-amber-600 text-white disabled:opacity-50"
              :disabled="isUnifyApplying"
              @click="applyUnify"
            >
              {{ isUnifyApplying ? 'Iniciando…' : 'Sim, unificar' }}
            </button>
            <button
              class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11"
              @click="showUnifyConfirm = false"
            >
              Cancelar
            </button>
          </template>
        </div>

        <p v-if="unifyPreview && unifyPreview.contacts_to_merge === 0" class="text-xs text-green-600">
          ✓ Nenhum duplicado por telefone/e-mail encontrado.
        </p>
        <p class="text-[11px] text-n-slate-9">
          Contatos sem telefone (ex: só Instagram) não são unificados automaticamente —
          use o botão "Mesclar" no card do CRM para esses casos.
        </p>
      </div>
    </div>

    <!-- ══ IDENTIFICAÇÃO COM INTELIGÊNCIA ══ -->
    <p class="text-[11px] font-bold text-n-slate-9 uppercase tracking-wide mb-2 mt-6 flex items-center gap-1.5">
      <span class="i-lucide-sparkles text-xs" />
      Identificação com inteligência — o sistema lê as conversas e preenche sozinho
    </p>

    <!-- Preencher valores pelo orçamento -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showValuePanel = !showValuePanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #059669, #34D399)">
          <span class="i-lucide-badge-dollar-sign text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">Preencher valores pelo orçamento</p>
          <p class="text-xs text-n-slate-10">
            Varre as conversas de cada card procurando o maior R$ mencionado e preenche o valor.
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showValuePanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showValuePanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <label class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer">
          <input v-model="valueOnlyEmpty" type="checkbox" class="rounded accent-n-brand" />
          Só cards sem valor (recomendado)
        </label>
        <button
          class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
          style="background: linear-gradient(135deg, #059669, #34D399)"
          :disabled="isValueRunning"
          @click="runBulkValues"
        >
          <span :class="isValueRunning ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-wand-2'" />
          Preencher valores
        </button>
      </div>
    </div>
  </div>
</template>
