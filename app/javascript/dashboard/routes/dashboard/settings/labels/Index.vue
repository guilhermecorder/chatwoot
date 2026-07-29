<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { picoSearch } from '@scmmishra/pico-search';

import draggable from 'vuedraggable';
import AddLabel from './AddLabel.vue';
import EditLabel from './EditLabel.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTableCell } from 'dashboard/components-next/table';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();

const loading = ref({});
const showAddPopup = ref(false);
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const selectedLabel = ref({});
const searchQuery = ref('');

const records = computed(() => getters['labels/getLabels'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, [
    { name: 'title', weight: 4 },
    'description',
  ]);
});
const uiFlags = computed(() => getters['labels/getUIFlags'].value);

// reordenar (setinhas) só faz sentido na lista completa, sem busca ativa
const canReorder = computed(() => !searchQuery.value.trim());
const isFirst = label => records.value[0]?.id === label.id;
const isLast = label =>
  records.value[records.value.length - 1]?.id === label.id;

const moveLabel = async (label, delta) => {
  const ids = records.value.map(record => record.id);
  const index = ids.indexOf(label.id);
  const target = index + delta;
  if (index < 0 || target < 0 || target >= ids.length) return;
  [ids[index], ids[target]] = [ids[target], ids[index]];
  try {
    await store.dispatch('labels/reorder', ids);
  } catch (error) {
    useAlert(t('LABEL_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

// v-model do arrasto: soltar a linha = gravar a ordem (mesma rota das setinhas)
const draggableRecords = computed({
  get: () => filteredRecords.value,
  set: async list => {
    if (!canReorder.value) return;
    try {
      await store.dispatch(
        'labels/reorder',
        list.map(label => label.id)
      );
    } catch (error) {
      useAlert(t('LABEL_MGMT.EDIT.API.ERROR_MESSAGE'));
    }
  },
});

const deleteMessage = computed(() => ` ${selectedLabel.value.title}?`);

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  selectedLabel.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedLabel.value = response;
};
const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteLabel = async id => {
  try {
    await store.dispatch('labels/delete', id);
    useAlert(t('LABEL_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('LABEL_MGMT.DELETE.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  } finally {
    loading.value[selectedLabel.value.id] = false;
  }
};

const confirmDeletion = () => {
  loading.value[selectedLabel.value.id] = true;
  closeDeletePopup();
  deleteLabel(selectedLabel.value.id);
};

const tableHeaders = computed(() => {
  return [
    t('LABEL_MGMT.LIST.TABLE_HEADER.NAME'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.DESCRIPTION'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.COLOR'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.ACTION'),
  ];
});

onBeforeMount(() => {
  store.dispatch('labels/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('LABEL_MGMT.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="$t('LABEL_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('LABEL_MGMT.HEADER')"
        :description="$t('LABEL_MGMT.DESCRIPTION')"
        :link-text="$t('LABEL_MGMT.LEARN_MORE')"
        :search-placeholder="$t('LABEL_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="labels"
      >
        <template v-if="records?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('LABEL_MGMT.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('LABEL_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <p class="mb-3 text-body-sm text-n-slate-11">
        {{ $t('LABEL_MGMT.LIST.REORDER_HINT') }}
      </p>
      <div class="w-full">
        <table class="min-w-full table-auto divide-y divide-n-weak">
          <thead v-if="filteredRecords.length" class="border-t border-n-weak">
            <tr>
              <th
                v-for="(header, index) in tableHeaders"
                :key="index"
                class="py-4 ltr:pr-4 rtl:pl-4 text-start text-heading-3 text-n-slate-12 capitalize"
              >
                {{ header }}
              </th>
            </tr>
          </thead>
          <draggable
            v-if="filteredRecords.length"
            v-model="draggableRecords"
            tag="tbody"
            item-key="id"
            handle=".label-grip"
            :animation="150"
            :disabled="!canReorder"
            ghost-class="opacity-40"
            class="divide-y divide-n-weak text-n-slate-11"
          >
            <template #item="{ element: label }">
              <tr>
                <BaseTableCell>
                  <div class="flex items-center gap-2">
                    <span
                      v-if="canReorder"
                      v-tooltip.top="$t('LABEL_MGMT.LIST.REORDER_DRAG')"
                      class="label-grip cursor-grab active:cursor-grabbing text-n-slate-10 select-none text-base leading-none"
                    >
                      ⠿
                    </span>
                    <span class="text-body-main text-n-slate-12">
                      {{ label.title }}
                    </span>
                  </div>
                </BaseTableCell>

                <BaseTableCell>
                  <span class="text-body-main text-n-slate-11">
                    {{ label.description }}
                  </span>
                </BaseTableCell>

                <BaseTableCell>
                  <div class="flex items-center">
                    <span
                      class="w-4 h-4 ltr:mr-2 rtl:ml-2 border border-solid rounded border-n-weak"
                      :style="{ backgroundColor: label.color }"
                    />
                    <span class="text-body-main text-n-slate-12">
                      {{ label.color }}
                    </span>
                  </div>
                </BaseTableCell>

                <BaseTableCell align="end">
                  <div class="flex gap-3 justify-end flex-shrink-0">
                    <Button
                      v-if="canReorder"
                      v-tooltip.top="$t('LABEL_MGMT.LIST.REORDER_UP')"
                      icon="i-lucide-arrow-up"
                      slate
                      sm
                      :disabled="isFirst(label)"
                      @click="moveLabel(label, -1)"
                    />
                    <Button
                      v-if="canReorder"
                      v-tooltip.top="$t('LABEL_MGMT.LIST.REORDER_DOWN')"
                      icon="i-lucide-arrow-down"
                      slate
                      sm
                      :disabled="isLast(label)"
                      @click="moveLabel(label, 1)"
                    />
                    <Button
                      v-tooltip.top="$t('LABEL_MGMT.FORM.EDIT')"
                      icon="i-woot-edit-pen"
                      slate
                      sm
                      :is-loading="loading[label.id]"
                      @click="openEditPopup(label)"
                    />
                    <Button
                      v-tooltip.top="$t('LABEL_MGMT.FORM.DELETE')"
                      icon="i-woot-bin"
                      slate
                      sm
                      class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                      :is-loading="loading[label.id]"
                      @click="openDeletePopup(label)"
                    />
                  </div>
                </BaseTableCell>
              </tr>
            </template>
          </draggable>
          <tbody v-else class="divide-y divide-n-weak text-n-slate-11">
            <tr>
              <td
                :colspan="tableHeaders.length"
                class="py-20 text-center text-body-main !text-base text-n-slate-11"
              >
                {{
                  searchQuery
                    ? $t('LABEL_MGMT.NO_RESULTS')
                    : $t('LABEL_MGMT.LIST.404')
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddLabel @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditLabel :selected-response="selectedLabel" @close="hideEditPopup" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('LABEL_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="$t('LABEL_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="$t('LABEL_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
