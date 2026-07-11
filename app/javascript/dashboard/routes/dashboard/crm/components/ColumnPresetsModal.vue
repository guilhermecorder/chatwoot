<script setup>
import { ref } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  stages: { type: Array, required: true }, // stages do pipeline selecionado
  presets: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

// cópia editável — [{ name, stage_ids }]
const localPresets = ref(props.presets.map(p => ({
  name: p.name,
  stage_ids: [...(p.stage_ids ?? [])],
})));

const isSaving = ref(false);

const addPreset = () => {
  localPresets.value.push({ name: '', stage_ids: [] });
};

const removePreset = idx => {
  localPresets.value.splice(idx, 1);
};

const toggleStage = (preset, stageId) => {
  const i = preset.stage_ids.indexOf(stageId);
  if (i === -1) preset.stage_ids.push(stageId);
  else preset.stage_ids.splice(i, 1);
};

const save = async () => {
  const cleaned = localPresets.value
    .map(p => ({ name: p.name.trim(), stage_ids: p.stage_ids }))
    .filter(p => p.name && p.stage_ids.length);
  isSaving.value = true;
  try {
    await store.dispatch('crm/updateSettings', { column_presets: cleaned });
    useAlert(t('CRM.PRESETS.SAVED'));
    emit('saved');
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-xl max-h-[85vh] flex flex-col">
      <!-- Header -->
      <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
        <div>
          <h2 class="text-base font-semibold text-n-slate-12">{{ $t('CRM.PRESETS.TITLE') }}</h2>
          <p class="text-xs text-n-slate-10 mt-0.5">{{ $t('CRM.PRESETS.SUBTITLE') }}</p>
        </div>
        <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="emit('close')" />
      </div>

      <!-- Body -->
      <div class="flex-1 overflow-y-auto p-5 space-y-4">
        <div v-if="!localPresets.length" class="text-center py-6 text-n-slate-10">
          <span class="i-lucide-layout-template text-3xl mb-2 block mx-auto" />
          <p class="text-sm">{{ $t('CRM.PRESETS.EMPTY') }}</p>
        </div>

        <div
          v-for="(preset, idx) in localPresets"
          :key="idx"
          class="border border-n-weak rounded-xl p-3.5 space-y-2.5"
        >
          <div class="flex items-center gap-2">
            <input
              v-model="preset.name"
              class="flex-1 border border-n-weak rounded-lg px-3 py-1.5 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              :placeholder="$t('CRM.PRESETS.NAME_PLACEHOLDER')"
            />
            <button
              class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-base flex-shrink-0"
              :title="$t('CRM.PRESETS.REMOVE')"
              @click="removePreset(idx)"
            />
          </div>

          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="stage in stages"
              :key="stage.id"
              class="flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full border transition-colors"
              :class="preset.stage_ids.includes(stage.id)
                ? 'bg-n-brand/10 border-n-brand text-n-brand font-medium'
                : 'border-n-weak text-n-slate-10 hover:bg-n-alpha-1'"
              @click="toggleStage(preset, stage.id)"
            >
              <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: stage.color }" />
              {{ stage.name }}
            </button>
          </div>
        </div>

        <button
          class="w-full border-2 border-dashed border-n-weak rounded-xl py-2.5 text-sm text-n-slate-10 hover:border-n-brand hover:text-n-brand transition-colors flex items-center justify-center gap-1"
          @click="addPreset"
        >
          <span class="i-lucide-plus" />
          {{ $t('CRM.PRESETS.ADD') }}
        </button>
      </div>

      <!-- Footer -->
      <div class="flex gap-2 px-5 py-4 border-t border-n-weak flex-shrink-0">
        <button
          class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
          :disabled="isSaving"
          @click="save"
        >
          {{ isSaving ? $t('CRM.MODAL.SAVING') : $t('CRM.MODAL.SAVE') }}
        </button>
        <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="emit('close')">
          {{ $t('CRM.CANCEL') }}
        </button>
      </div>
    </div>
  </div>
</template>
