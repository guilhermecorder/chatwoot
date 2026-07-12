<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  bot: { type: Object, default: null },       // editar
  stageId: { type: Number, default: null },    // robô por coluna (modo programação)
  pipelineId: { type: Number, default: null },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxes = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::Whatsapp')
);

const isStageBot = computed(() => !!props.stageId);
const isSaving = ref(false);

const form = ref({
  name: '',
  inbox_id: null,
  active: true,
  steps: [{ delay_hours: 3, message: 'Oi, pode falar?' }],
});

onMounted(() => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  if (props.bot) {
    form.value = {
      name: props.bot.name,
      inbox_id: props.bot.inbox_id,
      active: props.bot.active,
      steps: props.bot.steps.length ? props.bot.steps.map(s => ({ ...s })) : [{ delay_hours: 3, message: '' }],
    };
  } else if (!isStageBot.value) {
    form.value.inbox_id = whatsappInboxes.value[0]?.id ?? null;
  }
});

const addStep = () => {
  const last = form.value.steps[form.value.steps.length - 1];
  form.value.steps.push({ delay_hours: (last?.delay_hours ?? 0) + 7, message: '' });
};
const removeStep = i => form.value.steps.splice(i, 1);

const canSave = computed(
  () =>
    form.value.name?.trim() &&
    (isStageBot.value || form.value.inbox_id) &&
    form.value.steps?.length &&
    form.value.steps.every(s => s.message?.trim() && Number(s.delay_hours) >= 0)
);

const save = async () => {
  if (!canSave.value || isSaving.value) return;
  isSaving.value = true;
  try {
    const payload = {
      name: form.value.name.trim(),
      active: form.value.active,
      steps: form.value.steps.map(s => ({ delay_hours: Number(s.delay_hours), message: s.message.trim() })),
    };
    if (isStageBot.value) {
      payload.stage_id = props.stageId;
      payload.pipeline_id = props.pipelineId;
    } else {
      payload.inbox_id = form.value.inbox_id;
    }
    if (props.bot) {
      await store.dispatch('crm/updateFollowupBot', { id: props.bot.id, ...payload });
    } else {
      await store.dispatch('crm/createFollowupBot', payload);
    }
    useAlert('Robô salvo!');
    emit('saved');
  } catch {
    useAlert('Erro ao salvar o robô');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div
    class="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] flex flex-col">
      <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
        <h2 class="text-base font-semibold text-n-slate-12">{{ bot ? 'Editar robô' : 'Novo robô de follow-up' }}</h2>
        <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="emit('close')" />
      </div>

      <div class="flex-1 overflow-y-auto p-5 space-y-4">
        <div>
          <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome do robô</label>
          <input
            v-model="form.name"
            class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
            placeholder="Ex.: Cutucada pós-orçamento"
          />
        </div>

        <div v-if="isStageBot" class="bg-n-brand/5 border border-n-brand/20 rounded-lg px-3 py-2 text-xs text-n-slate-11">
          <span class="i-lucide-info text-n-brand" />
          Este robô roda para os cards <strong>desta coluna</strong>. As cutucadas saem na caixa da própria conversa do paciente.
        </div>
        <div v-else>
          <label class="text-xs font-medium text-n-slate-11 block mb-1">Caixa de entrada (WhatsApp)</label>
          <select
            v-model="form.inbox_id"
            class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
          >
            <option v-for="i in whatsappInboxes" :key="i.id" :value="i.id">{{ i.name }}</option>
          </select>
        </div>

        <div>
          <div class="flex items-center justify-between mb-2">
            <label class="text-xs font-medium text-n-slate-11">Cadência de cutucadas</label>
            <button class="text-xs text-n-brand hover:underline flex items-center gap-1" @click="addStep">
              <span class="i-lucide-plus text-xs" /> Adicionar etapa
            </button>
          </div>
          <div class="space-y-2">
            <div v-for="(step, i) in form.steps" :key="i" class="flex items-start gap-2">
              <div class="flex items-center gap-1 flex-shrink-0">
                <input
                  v-model.number="step.delay_hours"
                  type="number"
                  min="0"
                  step="1"
                  class="w-16 border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                />
                <span class="text-xs text-n-slate-10">h</span>
              </div>
              <input
                v-model="step.message"
                class="flex-1 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder='Ex.: [nome], no seu tempo ok?'
              />
              <button
                v-if="form.steps.length > 1"
                class="text-n-slate-9 hover:text-red-500 i-lucide-x text-base mt-2.5 flex-shrink-0"
                @click="removeStep(i)"
              />
            </div>
          </div>
          <p class="text-[11px] text-n-slate-9 mt-2">
            Use <code class="bg-n-alpha-2 px-1 rounded">[nome]</code> para o primeiro nome do paciente.
            O tempo conta a partir da sua última mensagem sem resposta; para sozinho se o paciente responder.
          </p>
        </div>

        <label class="flex items-center gap-2 text-sm text-n-slate-11 cursor-pointer">
          <input v-model="form.active" type="checkbox" class="rounded accent-n-brand" />
          Ativo
        </label>
      </div>

      <div class="px-5 py-4 border-t border-n-weak flex-shrink-0 flex gap-2">
        <button
          class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium disabled:opacity-50"
          :disabled="!canSave || isSaving"
          @click="save"
        >{{ isSaving ? 'Salvando...' : 'Salvar robô' }}</button>
        <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="emit('close')">
          Cancelar
        </button>
      </div>
    </div>
  </div>
</template>
