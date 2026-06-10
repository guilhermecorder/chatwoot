<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import draggable from 'vuedraggable';
import ContactCard from './ContactCard.vue';
import StageEditModal from './StageEditModal.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  contacts: { type: Array, default: () => [] },
  pipelineId: { type: Number, required: true },
  editMode: { type: Boolean, default: false },
  allStages: { type: Array, default: () => [] },
});

const emit = defineEmits(['cardClick', 'stageDrop', 'addContact']);

const store = useStore();
const { t } = useI18n();

// Edit modal
const showEditModal = ref(false);

// Delete flow
const showDeleteConfirm = ref(false);
const moveToStageId = ref('');
const isDeleting = ref(false);

const otherStages = computed(() =>
  props.allStages.filter(s => s.id !== props.stage.id)
);

const hasCards = computed(() => props.contacts.length > 0);

const localContacts = computed({
  get: () => props.contacts,
  set: (val) => emit('stageDrop', { stageId: props.stage.id, contacts: val }),
});

const totalValue = computed(() =>
  props.contacts.reduce((sum, c) => sum + (Number(c.value) || 0), 0)
);

const confirmDelete = () => {
  moveToStageId.value = otherStages.value[0]?.id ?? '';
  showDeleteConfirm.value = true;
};

const cancelDelete = () => {
  showDeleteConfirm.value = false;
  moveToStageId.value = '';
};

const deleteStage = async () => {
  isDeleting.value = true;
  try {
    if (hasCards.value && moveToStageId.value) {
      for (const contact of props.contacts) {
        await store.dispatch('crm/moveContact', {
          pipelineId: props.pipelineId,
          id: contact.id,
          stageId: Number(moveToStageId.value),
        });
      }
    }
    await store.dispatch('crm/deleteStage', {
      pipelineId: props.pipelineId,
      stageId: props.stage.id,
    });
    useAlert(t('CRM.SUCCESS.STAGE_DELETED'));
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isDeleting.value = false;
    showDeleteConfirm.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col bg-n-alpha-1 rounded-xl min-w-64 w-64 flex-shrink-0 h-full">

    <!-- Header -->
    <div class="px-3 py-2.5 border-b border-n-weak">

      <!-- Delete confirmation -->
      <div v-if="showDeleteConfirm" class="space-y-2">
        <!-- Has cards: show move-to selector -->
        <template v-if="hasCards">
          <p class="text-xs text-n-slate-11">
            {{ $t('CRM.DELETE_STAGE_HAS_CARDS', { count: contacts.length }) }}
          </p>
          <select
            v-model="moveToStageId"
            class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
          >
            <option v-for="s in otherStages" :key="s.id" :value="s.id">{{ s.name }}</option>
          </select>
          <div class="flex gap-2">
            <button
              class="flex-1 bg-red-500 text-white rounded-lg py-1.5 text-xs disabled:opacity-50"
              :disabled="isDeleting || !moveToStageId"
              @click="deleteStage"
            >
              {{ isDeleting ? '...' : $t('CRM.DELETE_MOVE_AND_DELETE') }}
            </button>
            <button
              class="flex-1 border border-n-weak rounded-lg py-1.5 text-xs text-n-slate-11"
              @click="cancelDelete"
            >
              {{ $t('CRM.CANCEL') }}
            </button>
          </div>
        </template>

        <!-- No cards: simple confirmation -->
        <template v-else>
          <p class="text-xs text-n-slate-11">{{ $t('CRM.DELETE_STAGE_CONFIRM') }}</p>
          <div class="flex gap-2">
            <button
              class="flex-1 bg-red-500 text-white rounded-lg py-1.5 text-xs disabled:opacity-50"
              :disabled="isDeleting"
              @click="deleteStage"
            >
              {{ isDeleting ? '...' : $t('CRM.DELETE_STAGE') }}
            </button>
            <button
              class="flex-1 border border-n-weak rounded-lg py-1.5 text-xs text-n-slate-11"
              @click="cancelDelete"
            >
              {{ $t('CRM.CANCEL') }}
            </button>
          </div>
        </template>
      </div>

      <!-- Normal header -->
      <div v-else class="space-y-2">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2 min-w-0">
            <span
              class="w-2.5 h-2.5 rounded-full flex-shrink-0"
              :style="{ backgroundColor: stage.color }"
            />
            <span class="text-sm font-semibold text-n-slate-12 truncate">{{ stage.name }}</span>
            <span class="text-xs text-n-slate-10 bg-n-alpha-2 rounded px-1.5 py-0.5 flex-shrink-0">
              {{ contacts.length }}
            </span>
          </div>
          <!-- Edit mode actions -->
          <div v-if="editMode" class="flex items-center gap-1 flex-shrink-0 ml-1">
            <button
              class="text-n-slate-10 hover:text-n-slate-12 i-lucide-pencil text-sm"
              @click="showEditModal = true"
            />
            <button
              class="text-n-slate-10 hover:text-red-500 i-lucide-trash-2 text-sm"
              @click="confirmDelete"
            />
          </div>
        </div>
        <p v-if="totalValue > 0" class="text-sm font-semibold text-green-600 text-center">
          R$ {{ totalValue.toLocaleString('pt-BR', { maximumFractionDigits: 0 }) }}
        </p>
      </div>
    </div>

    <!-- Cards -->
    <div
      class="column-cards-scroll p-2"
      style="flex:1;overflow-y:scroll;min-height:0;scrollbar-width:thin;scrollbar-color:rgba(148,163,184,0.35) transparent;"
    >
      <draggable
        v-model="localContacts"
        group="crm-contacts"
        item-key="id"
        :animation="150"
        ghost-class="opacity-40"
        class="min-h-12"
      >
        <template #item="{ element }">
          <ContactCard
            :contact="element"
            @click="emit('cardClick', element)"
          />
        </template>
      </draggable>
    </div>

    <!-- Footer: Add contact (always visible) -->
    <div class="px-2 pb-2">
      <button
        class="w-full flex items-center justify-center gap-1 text-xs text-n-slate-10 hover:text-n-brand py-1.5 rounded-lg hover:bg-n-alpha-1 transition-colors"
        @click="emit('addContact', stage.id)"
      >
        <span class="i-lucide-plus text-sm" />
        {{ $t('CRM.ADD_CONTACT') }}
      </button>
    </div>

  </div>

  <!-- Stage edit modal (teleported outside column) -->
  <StageEditModal
    :stage="showEditModal ? stage : null"
    :pipeline-id="pipelineId"
    @close="showEditModal = false"
    @saved="showEditModal = false"
  />
</template>
