<script setup>
// Barra de ações rápidas da janelinha de conversa: etiquetas do contato
// (chips com ✕ + "+ etiqueta") e mover o card de coluna — sem sair do chat.
// Usada pelo CRM (card completo) e pelo Radar do Meu Painel (só contato:
// sem card conhecido o select de coluna some e as etiquetas vêm da API).
import { ref, computed, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { onClickOutside } from '@vueuse/core';

const props = defineProps({
  // card do CRM (contact_json) OU contato avulso do Radar ({ contact_id, ... })
  contact: { type: Object, required: true },
  pipelineId: { type: Number, default: null },
  stages: { type: Array, default: () => [] },
});

const { t } = useI18n();
const store = useStore();

// card conhecido = veio do board (tem id do card + funil + colunas)
const hasCard = computed(
  () =>
    !!props.pipelineId && props.stages.length > 0 && props.contact.id != null
);
const contactId = computed(() => props.contact.contact_id);

// ── Etiquetas ──────────────────────────────────────────────
// Cópia local: o patch no store troca o objeto do card, então a prop
// congela — a barra mantém o estado vivo e o board recebe o patch.
const labels = ref(hasCard.value ? [...(props.contact.labels ?? [])] : []);
const isSavingLabels = ref(false);

const accountLabels = useMapGetter('labels/getLabels');
const fetchedLabels = computed(() =>
  store.getters['contactLabels/getContactLabels'](contactId.value)
);
// Radar não conhece as etiquetas do contato — busca e sincroniza
watch(fetchedLabels, list => {
  if (!hasCard.value && !isSavingLabels.value) labels.value = [...list];
});

const availableLabels = computed(() =>
  accountLabels.value.filter(l => !labels.value.includes(l.title))
);
const labelColor = title =>
  accountLabels.value.find(l => l.title === title)?.color ?? '#6B7280';

const showLabelMenu = ref(false);
const labelMenuWrap = ref(null);
onClickOutside(labelMenuWrap, () => {
  showLabelMenu.value = false;
});

const saveLabels = async next => {
  if (isSavingLabels.value) return;
  const previous = [...labels.value];
  const added = next.filter(l => !previous.includes(l));
  const removed = previous.filter(l => !next.includes(l));
  labels.value = next; // otimista — reverte se falhar
  isSavingLabels.value = true;
  try {
    await store.dispatch('contactLabels/update', {
      contactId: contactId.value,
      labels: next,
    });
    if (hasCard.value) {
      // board reflete na hora + automações label_added/label_removed
      store.commit('crm/patchContact', {
        id: props.contact.id,
        data: { labels: [...next] },
      });
      store
        .dispatch('crm/triggerLabelChange', {
          pipelineId: props.pipelineId,
          contactId: props.contact.id,
          added,
          removed,
        })
        .catch(() => {});
    }
  } catch {
    labels.value = previous;
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isSavingLabels.value = false;
  }
};

const addLabel = title => {
  showLabelMenu.value = false;
  if (!labels.value.includes(title)) saveLabels([...labels.value, title]);
};
const removeLabel = title => saveLabels(labels.value.filter(l => l !== title));

// ── Mover de coluna ────────────────────────────────────────
const stageId = ref(props.contact.stage_id ?? null);
const isMoving = ref(false);

const moveToStage = async value => {
  const next = Number(value);
  if (!next || next === Number(stageId.value) || isMoving.value) return;
  const previous = stageId.value;
  stageId.value = next;
  isMoving.value = true;
  try {
    await store.dispatch('crm/moveContact', {
      pipelineId: props.pipelineId,
      id: props.contact.id,
      stageId: next,
    });
    const stage = props.stages.find(s => Number(s.id) === next);
    useAlert(
      stage
        ? t('CRM.CHAT.CARD_MOVED_TO', { stage: stage.name })
        : t('CRM.CHAT.CARD_MOVED')
    );
  } catch {
    stageId.value = previous;
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isMoving.value = false;
  }
};

onMounted(() => {
  if (!accountLabels.value.length) store.dispatch('labels/get').catch(() => {});
  if (!hasCard.value && contactId.value) {
    store.dispatch('contactLabels/get', contactId.value).catch(() => {});
  }
});
</script>

<template>
  <div
    class="flex items-center gap-1.5 flex-wrap px-4 py-1.5 border-b border-n-weak bg-n-alpha-1 flex-shrink-0"
  >
    <!-- Coluna (só com card do CRM conhecido) -->
    <select
      v-if="hasCard"
      :value="stageId"
      :disabled="isMoving"
      class="h-7 max-w-[45%] text-[11px] rounded-lg border border-n-weak bg-n-solid-2 text-n-slate-12 px-1.5 disabled:opacity-60"
      :title="$t('CRM.MODAL.STAGE')"
      @change="moveToStage($event.target.value)"
    >
      <option v-for="s in stages" :key="s.id" :value="s.id">
        {{ s.name }}
      </option>
    </select>

    <!-- Chips das etiquetas atuais -->
    <span
      v-for="label in labels"
      :key="label"
      class="flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded-full border border-n-weak bg-n-solid-2 text-n-slate-11 max-w-[45%]"
    >
      <span
        class="w-1.5 h-1.5 rounded-full flex-shrink-0"
        :style="{ backgroundColor: labelColor(label) }"
      />
      <span class="truncate">{{ label }}</span>
      <button
        class="i-lucide-x text-[10px] text-n-slate-9 hover:text-red-500 flex-shrink-0 disabled:opacity-50"
        :disabled="isSavingLabels"
        :title="$t('CRM.CHAT.REMOVE_LABEL')"
        @click="removeLabel(label)"
      />
    </span>

    <!-- + etiqueta -->
    <div ref="labelMenuWrap" class="relative">
      <button
        class="flex items-center gap-0.5 text-[11px] px-1.5 py-0.5 rounded-full border border-dashed border-n-weak text-n-slate-10 hover:text-n-brand hover:border-n-brand transition-colors disabled:opacity-50"
        :disabled="isSavingLabels || !availableLabels.length"
        @click="showLabelMenu = !showLabelMenu"
      >
        <span class="i-lucide-plus text-[10px]" />
        {{ $t('CRM.CHAT.ADD_LABEL') }}
      </button>
      <div
        v-if="showLabelMenu"
        class="absolute left-0 top-full mt-1 z-30 min-w-40 max-h-48 overflow-y-auto bg-n-solid-1 border border-n-weak rounded-lg shadow-lg py-1"
      >
        <button
          v-for="l in availableLabels"
          :key="l.id"
          class="w-full flex items-center gap-1.5 text-[11px] px-2.5 py-1.5 text-left text-n-slate-11 hover:bg-n-alpha-1"
          @click="addLabel(l.title)"
        >
          <span
            class="w-1.5 h-1.5 rounded-full flex-shrink-0"
            :style="{ backgroundColor: l.color ?? '#6B7280' }"
          />
          <span class="truncate">{{ l.title }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
