<script setup>
// TRATAMENTO DE DADOS UNIFICADO (item 70): todas as ferramentas de
// limpeza e enriquecimento da base num componente só, montado dentro de
// Automações → Tratamento de dados (a casa oficial). Duas famílias:
// IDENTIFICAÇÃO TRADICIONAL (filtros e etiquetas em massa, com prévia
// antes de aplicar) e COM INTELIGÊNCIA (detecção de valores nas
// conversas). Extraído da Campanha WhatsApp, mesma lógica testada.
import { ref, computed, onMounted, watch } from 'vue';
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
  // colunas onde a regra atua (pedido 22/07) — vazio = funil inteiro
  stage_ids: [],
});

const toggleRetroStage = id => {
  const idx = retro.value.stage_ids.indexOf(id);
  if (idx >= 0) retro.value.stage_ids.splice(idx, 1);
  else retro.value.stage_ids.push(id);
  retroPreview.value = null; // filtro mudou = prévia antiga não vale mais
};

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
  stage_ids: retro.value.stage_ids.length ? retro.value.stage_ids : undefined,
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
    retro.value.stage_ids = [];
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

// ── Cirurgias feitas FORA do sistema ────────────────────────────────
// Pacientes que operaram fora do CRM e o card nunca chegou na coluna
// "Cirurgia Realizada" (os funis ficam mentindo). Cola a lista de
// telefones, o sistema casa com os contatos e coloca todo mundo na coluna.
const showSurgeryPanel = ref(false);
const surgeryList = ref('');
const surgeryStageId = ref('');
const surgeryLabel = ref('cirurgia_externa');
const surgerySetValue = ref(true);
const surgeryOverwriteValue = ref(false);
const surgeryPreview = ref(null);
const isSurgeryLoading = ref(false);
const isSurgeryApplying = ref(false);

// pré-seleciona a coluna "Cirurgia Realizada" assim que os funis chegam
// (senão a primeira com "cirurgia" no nome que não seja de indicação)
watch(
  allStages,
  stages => {
    if (surgeryStageId.value || !stages.length) return;
    const target =
      stages.find(s => /cirurgia realizada/i.test(s.name)) ||
      stages.find(s => /cirurgia/i.test(s.name) && !/indica/i.test(s.name));
    if (target) surgeryStageId.value = target.id;
  },
  { immediate: true }
);

const surgeryLineCount = computed(
  () => surgeryList.value.split('\n').filter(l => l.trim()).length
);

const surgeryPayload = () => ({
  list: surgeryList.value,
  target_stage_id: surgeryStageId.value,
  label: surgeryLabel.value.trim(),
  set_value: surgerySetValue.value,
  overwrite_value: surgerySetValue.value && surgeryOverwriteValue.value,
});

const previewSurgery = async () => {
  if (!surgeryList.value.trim() || !surgeryStageId.value) return;
  isSurgeryLoading.value = true;
  surgeryPreview.value = null;
  try {
    const { data } = await CrmAPI.previewExternalSurgeries(surgeryPayload());
    surgeryPreview.value = data;
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Erro ao ler a lista.');
  } finally {
    isSurgeryLoading.value = false;
  }
};

const applySurgery = async () => {
  if (!surgeryPreview.value?.matched || isSurgeryApplying.value) return;
  isSurgeryApplying.value = true;
  try {
    await CrmAPI.applyExternalSurgeries(surgeryPayload());
    useAlert(
      'Aplicando em segundo plano — os pacientes chegarão na coluna em alguns minutos.'
    );
    surgeryPreview.value = null;
    surgeryList.value = '';
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Erro ao aplicar.');
  } finally {
    isSurgeryApplying.value = false;
  }
};

// ── 📄 Planilha de fechamento (item 132): o sistema ENTENDE o .xlsx ──
// uma aba por mês, casa por NOME, retrodata a cirurgia pra data real
const sheetFile = ref(null);
const sheetPreview = ref(null);
const sheetResult = ref(null);
const isSheetLoading = ref(false);
const isSheetApplying = ref(false);
const sheetCreateMissing = ref(true);
const sheetOverwriteValue = ref(false);

const onSheetFile = event => {
  sheetFile.value = event.target.files?.[0] ?? null;
  sheetPreview.value = null;
  sheetResult.value = null;
};

const previewSheet = async () => {
  if (!sheetFile.value || !surgeryStageId.value || isSheetLoading.value) return;
  isSheetLoading.value = true;
  sheetPreview.value = null;
  try {
    const formData = new FormData();
    formData.append('file', sheetFile.value);
    formData.append('target_stage_id', surgeryStageId.value);
    const { data } = await CrmAPI.previewClosingSheet(formData);
    sheetPreview.value = data;
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Não consegui ler a planilha.');
  } finally {
    isSheetLoading.value = false;
  }
};

const applySheet = async () => {
  if (!sheetPreview.value?.token || isSheetApplying.value) return;
  isSheetApplying.value = true;
  try {
    const { data } = await CrmAPI.applyClosingSheet({
      token: sheetPreview.value.token,
      target_stage_id: surgeryStageId.value,
      label: surgeryLabel.value,
      set_value: true,
      overwrite_value: sheetOverwriteValue.value,
      create_missing: sheetCreateMissing.value,
    });
    sheetResult.value = data;
    sheetPreview.value = null;
    sheetFile.value = null;
    useAlert(
      `Importação do histórico iniciada: ${data.matched} pacientes casados + ${data.to_create} criados da planilha.`
    );
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Erro ao importar a planilha.');
  } finally {
    isSheetApplying.value = false;
  }
};

const sheetMonthsRange = computed(() => {
  const months = sheetPreview.value?.months ?? [];
  if (!months.length) return '';
  const fmt = m =>
    /^\d{4}-\d{2}$/.test(m.month)
      ? `${m.month.slice(5)}/${m.month.slice(2, 4)}`
      : m.month;
  return `${fmt(months[0])} → ${fmt(months[months.length - 1])}`;
});

// ── ↩️ Desfazer a última importação (item 133) ──
const importStatus = ref(null);
const isUndoing = ref(false);

const loadImportStatus = async () => {
  try {
    const { data } = await CrmAPI.getImportStatus();
    importStatus.value = data;
  } catch {
    importStatus.value = null;
  }
};

watch(showSurgeryPanel, open => {
  if (open) loadImportStatus();
});

const undoImport = async () => {
  if (!importStatus.value?.undoable || isUndoing.value) return;
  isUndoing.value = true;
  try {
    await CrmAPI.undoLastImport(importStatus.value.id);
    useAlert('Desfazendo em segundo plano — tudo volta ao estado anterior em alguns minutos.');
    importStatus.value = null;
    sheetResult.value = null;
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Erro ao desfazer.');
  } finally {
    isUndoing.value = false;
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

        <!-- pedido 22/07: a regra pode valer SÓ para quem está em colunas
             escolhidas (o card atual do contato) — clicou, acendeu -->
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1">
            Atuar só em quem está nestas colunas
            <span class="text-n-slate-9">(opcional — nada marcado = funil inteiro)</span>
          </label>
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="s in allStages"
              :key="s.id"
              class="text-[11px] px-2.5 py-1 rounded-full border transition-colors"
              :class="retro.stage_ids.includes(s.id)
                ? 'text-white border-transparent font-semibold'
                : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
              :style="retro.stage_ids.includes(s.id) ? { background: s.color || '#B8860B' } : {}"
              :title="`${s.pipeline_name} › ${s.name}`"
              @click="toggleRetroStage(s.id)"
            >
              {{ s.name }}
            </button>
          </div>
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

    <!-- Cirurgias feitas fora do sistema -->
    <div class="mb-4 bg-n-solid-2 border border-n-weak rounded-2xl overflow-hidden">
      <button
        class="w-full flex items-center gap-3 p-4 text-left hover:bg-n-alpha-1 transition-colors"
        @click="showSurgeryPanel = !showSurgeryPanel"
      >
        <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #BE123C, #15803D)">
          <span class="i-lucide-stethoscope text-white text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-n-slate-12">🏥 Cirurgias feitas fora do sistema</p>
          <p class="text-xs text-n-slate-10">
            Pacientes que operaram por fora e o card nunca chegou em "Cirurgia Realizada".
            Cole a lista de telefones → o sistema encontra cada contato e coloca o card na
            coluna certa, com valor e etiqueta se você quiser. Os funis param de mentir.
          </p>
        </div>
        <span
          class="text-n-slate-10 flex-shrink-0"
          :class="showSurgeryPanel ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        />
      </button>

      <div v-if="showSurgeryPanel" class="px-4 pb-4 space-y-3 border-t border-n-weak pt-4">
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1">Lista de pacientes (um telefone por linha)</label>
          <textarea
            v-model="surgeryList"
            rows="8"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 font-mono"
            placeholder="Aceita 3 formatos (pode misturar):&#10;&#10;11987654321&#10;11987654321;3900&#10;11987654321;3.900,00;15/03/2026&#10;&#10;Só o telefone é obrigatório. Valor e data separados por ; ou colados direto do Excel."
            @input="surgeryPreview = null"
          />
          <p class="text-[11px] text-n-slate-9 mt-1">
            {{ surgeryLineCount }} linha(s) — máximo 3000 por vez. Pode colar de uma planilha:
            o telefone casa com ou sem o 55 do Brasil e com ou sem o 9 na frente.
          </p>
        </div>

        <div class="flex flex-wrap gap-3">
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Colocar todo mundo na coluna</label>
            <select
              v-model="surgeryStageId"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              @change="surgeryPreview = null"
            >
              <option value="">Escolha a coluna…</option>
              <option v-for="s in allStages" :key="s.id" :value="s.id">
                {{ s.pipeline_name }} › {{ s.name }}
              </option>
            </select>
          </div>
          <div class="flex-1 min-w-48">
            <label class="text-xs font-medium text-n-slate-11 block mb-1">
              Etiqueta no contato <span class="text-n-slate-9">(opcional — apague para não etiquetar)</span>
            </label>
            <input
              v-model="surgeryLabel"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
              placeholder="cirurgia_externa"
              @input="surgeryPreview = null"
            />
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-4">
          <label class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer">
            <input
              v-model="surgerySetValue"
              type="checkbox"
              class="rounded"
              @change="surgeryPreview = null"
            />
            Preencher o valor do card com o valor da lista
          </label>
          <label
            v-if="surgerySetValue"
            class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer"
          >
            <input
              v-model="surgeryOverwriteValue"
              type="checkbox"
              class="rounded"
              @change="surgeryPreview = null"
            />
            Sobrescrever valor que o card já tem
          </label>
        </div>

        <!-- Prévia: o retrato antes de aplicar -->
        <div v-if="surgeryPreview" class="bg-n-alpha-1 rounded-lg p-3 space-y-2">
          <p class="text-sm text-n-slate-12">
            <b>{{ surgeryPreview.total_lines }}</b> linha(s) lida(s) ·
            <b class="text-green-600">{{ surgeryPreview.matched }}</b> paciente(s) encontrado(s) ·
            <b>{{ surgeryPreview.already_in_target }}</b> já na coluna "{{ surgeryPreview.target_stage?.name }}"
          </p>
          <p v-if="surgeryPreview.matched_sample?.length" class="text-xs text-n-slate-9">
            Ex: {{ surgeryPreview.matched_sample.join(', ') }}
          </p>
          <div v-if="surgeryPreview.ambiguous_count" class="space-y-0.5">
            <p class="text-xs text-amber-600 font-medium">
              {{ surgeryPreview.ambiguous_count }} telefone(s) com MAIS DE UM contato — esses não
              serão aplicados (resolva antes com "Unificar contatos duplicados"):
            </p>
            <p
              v-for="(a, i) in surgeryPreview.ambiguous"
              :key="i"
              class="text-[11px] text-n-slate-10"
            >
              {{ a.phone }} → {{ a.names.join(' / ') }}
            </p>
          </div>
          <div v-if="surgeryPreview.unmatched_count">
            <p class="text-xs text-n-slate-10 font-medium">
              {{ surgeryPreview.unmatched_count }} telefone(s) sem contato no sistema (não serão aplicados):
            </p>
            <p class="text-[11px] text-n-slate-9 break-all">
              {{ surgeryPreview.unmatched.join(', ') }}<span v-if="surgeryPreview.unmatched_count > surgeryPreview.unmatched.length">…</span>
            </p>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3 pt-1">
          <button
            class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
            :disabled="!surgeryList.trim() || !surgeryStageId || isSurgeryLoading"
            @click="previewSurgery"
          >
            <span class="i-lucide-search" />
            {{ isSurgeryLoading ? 'Lendo a lista…' : 'Prévia' }}
          </button>

          <div class="flex-1" />
          <button
            class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
            style="background: linear-gradient(135deg, #DC2626, #16A34A)"
            :disabled="!surgeryPreview || !surgeryPreview.matched || isSurgeryApplying"
            @click="applySurgery"
          >
            <span class="i-lucide-wand-2" />
            {{ isSurgeryApplying ? 'Aplicando…' : 'Aplicar' }}
          </button>
        </div>
        <p v-if="surgeryPreview && !surgeryPreview.matched" class="text-xs text-amber-600">
          Nenhum telefone da lista casou com um contato — confira o formato dos números.
        </p>
        <p v-else-if="!surgeryPreview" class="text-xs text-n-slate-9">
          Primeiro a Prévia (não mexe em nada), depois o Aplicar.
        </p>

        <!-- 📄 PLANILHA DE FECHAMENTO (item 132): o sistema entende o .xlsx -->
        <div class="border-t border-n-weak pt-3 mt-3 space-y-3">
          <p class="text-xs font-semibold text-n-slate-12 flex items-center gap-1.5">
            <span class="i-lucide-file-spreadsheet text-sm" style="color: #15803D" />
            Ou envie a planilha de fechamento (.xlsx) — o sistema entende sozinho
          </p>
          <p class="text-[11px] text-n-slate-9">
            Uma aba por mês (Status · Data · Paciente · Procedimento · valor total). O sistema lê TODAS as
            abas, ignora duplicadas/canceladas, casa cada paciente pelo NOME e coloca o card na coluna
            escolhida acima com o valor e a <b>data real da cirurgia</b> — os dashboards passam a contar
            cada mês no mês certo.
          </p>

          <div class="flex flex-wrap items-center gap-3">
            <input
              type="file"
              accept=".xlsx"
              class="text-xs text-n-slate-11 file:mr-2 file:px-3 file:py-1.5 file:rounded-lg file:border-0 file:text-xs file:font-medium file:bg-n-alpha-2 file:text-n-slate-12 file:cursor-pointer"
              @change="onSheetFile"
            />
            <button
              class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1 disabled:opacity-50"
              :disabled="!sheetFile || !surgeryStageId || isSheetLoading"
              @click="previewSheet"
            >
              <span class="i-lucide-scan-search" />
              {{ isSheetLoading ? 'Lendo a planilha…' : 'Ler planilha' }}
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-4">
            <label class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer">
              <input v-model="sheetCreateMissing" type="checkbox" class="rounded" />
              Criar paciente que não existe no sistema (recomendado — o histórico entra inteiro)
            </label>
            <label class="flex items-center gap-1.5 text-xs text-n-slate-11 cursor-pointer">
              <input v-model="sheetOverwriteValue" type="checkbox" class="rounded" />
              Sobrescrever valor que o card já tem
            </label>
          </div>

          <!-- prévia da planilha -->
          <div v-if="sheetPreview" class="bg-n-alpha-1 rounded-lg p-3 space-y-2">
            <p class="text-sm text-n-slate-12">
              <b>{{ sheetPreview.sheets }}</b> meses lidos ({{ sheetMonthsRange }}) ·
              <b>{{ sheetPreview.total_rows }}</b> cirurgias válidas ·
              <b class="text-green-600">R$ {{ Number(sheetPreview.total_value).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}</b>
            </p>
            <p class="text-xs text-n-slate-10">
              <b class="text-green-600">{{ sheetPreview.matched }}</b> casaram pelo nome
              <template v-if="sheetPreview.matched_sample?.length"> (ex: {{ sheetPreview.matched_sample.slice(0, 3).join(', ') }})</template> ·
              <b>{{ sheetPreview.unmatched_count }}</b> não existem no sistema
              <template v-if="sheetCreateMissing"> → <b class="text-sky-600">serão criados</b></template>
              <template v-else> → ficarão de fora</template> ·
              <b>{{ sheetPreview.already_in_target }}</b> já na coluna
            </p>
            <p v-if="sheetPreview.ambiguous_count" class="text-xs text-amber-600">
              {{ sheetPreview.ambiguous_count }} nome(s) com MAIS DE UM contato (ficam de fora — resolva com
              "Unificar contatos duplicados"): {{ sheetPreview.ambiguous.slice(0, 5).join(' · ') }}
            </p>
            <p class="text-[11px] text-n-slate-9">
              Ignoradas da planilha: {{ sheetPreview.skipped?.duplicada || 0 }} duplicadas ·
              {{ sheetPreview.skipped?.cancelada || 0 }} canceladas · {{ sheetPreview.skipped?.sem_valor || 0 }} sem valor
            </p>
            <button
              class="text-xs px-4 py-2 rounded-lg text-white hover:opacity-90 flex items-center gap-1.5 disabled:opacity-50"
              style="background: linear-gradient(135deg, #15803D, #16A34A)"
              :disabled="isSheetApplying"
              @click="applySheet"
            >
              <span class="i-lucide-database-zap" />
              {{ isSheetApplying ? 'Importando…' : 'Importar histórico completo' }}
            </button>
          </div>
          <p v-else-if="sheetResult" class="text-xs text-green-600">
            ✅ Importação em andamento: {{ sheetResult.matched }} casados + {{ sheetResult.to_create }} criados.
            Em alguns minutos os dashboards refletem o histórico — confira no PRO MAX com "Este ano".
          </p>

          <!-- ↩️ botão VOLTAR: desfaz a última importação inteira -->
          <div
            v-if="importStatus?.undoable"
            class="flex flex-wrap items-center gap-3 rounded-lg p-3 border"
            style="background: rgba(217, 119, 6, 0.06); border-color: rgba(217, 119, 6, 0.3)"
          >
            <span class="i-lucide-undo-2 text-lg flex-shrink-0" style="color: #B45309" />
            <div class="flex-1 min-w-0">
              <p class="text-xs font-semibold text-n-slate-12">
                Última importação: {{ importStatus.entries }} mudança(s) em "{{ importStatus.stage_name }}"
                <template v-if="importStatus.created_contacts"> · {{ importStatus.created_contacts }} paciente(s) criado(s)</template>
              </p>
              <p class="text-[11px] text-n-slate-9">
                Se bagunçou, desfaz TUDO: cards voltam pra coluna/valor/data de antes e os pacientes criados são removidos.
              </p>
            </div>
            <button
              class="text-xs px-3 py-1.5 rounded-lg border font-medium hover:opacity-80 disabled:opacity-50 flex items-center gap-1"
              style="border-color: #B45309; color: #B45309"
              :disabled="isUndoing"
              @click="undoImport"
            >
              <span class="i-lucide-undo-2" />
              {{ isUndoing ? 'Desfazendo…' : 'Desfazer importação' }}
            </button>
          </div>
        </div>
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
