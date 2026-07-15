<script setup>
import { ref, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  stage: { type: Object, default: null },
  pipelineId: { type: Number, required: true },
});

const emit = defineEmits(['close', 'saved']);

const store = useStore();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const activeSection = ref('general');
const isSaving = ref(false);

const form = ref({ name: '', color: '#6B7280', description: '', main_inbox_ids: [] });

watch(() => props.stage, (s) => {
  if (!s) return;
  form.value = {
    name: s.name ?? '',
    color: s.color ?? '#6B7280',
    description: s.description ?? '',
    main_inbox_ids: [...(s.main_inbox_ids ?? [])],
  };
  if (!inboxes.value.length) store.dispatch('inboxes/get');
}, { immediate: true });

const toggleMainInbox = id => {
  const idx = form.value.main_inbox_ids.indexOf(id);
  if (idx >= 0) form.value.main_inbox_ids.splice(idx, 1);
  else form.value.main_inbox_ids.push(id);
};

const save = async () => {
  if (!form.value.name.trim() || !props.stage) return;
  isSaving.value = true;
  try {
    await store.dispatch('crm/updateStage', {
      pipelineId: props.pipelineId,
      id: props.stage.id,
      name: form.value.name,
      color: form.value.color,
      description: form.value.description,
      settings: { main_inbox_ids: form.value.main_inbox_ids },
    });
    useAlert(t('CRM.SUCCESS.STAGE_RENAMED'));
    emit('saved');
    emit('close');
  } catch {
    useAlert(t('CRM.ERROR.GENERIC'));
  } finally {
    isSaving.value = false;
  }
};

const sections = [
  { key: 'general',     icon: 'i-lucide-pencil',    label: 'Geral' },
  { key: 'settings',    icon: 'i-lucide-settings-2', label: 'Configurações' },
  { key: 'automations', icon: 'i-lucide-zap',        label: 'Automações' },
];
</script>

<template>
  <div
    v-if="stage"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('close')"
  >
    <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-lg flex flex-col max-h-[85vh]">

      <!-- Header -->
      <div class="flex items-center justify-between px-5 pt-5 pb-4 border-b border-n-weak flex-shrink-0">
        <div class="flex items-center gap-2.5">
          <span
            class="w-3 h-3 rounded-full flex-shrink-0"
            :style="{ backgroundColor: form.color }"
          />
          <h2 class="text-base font-semibold text-n-slate-12">
            {{ stage.name }}
          </h2>
        </div>
        <button
          class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl"
          @click="emit('close')"
        />
      </div>

      <!-- Section nav -->
      <div class="flex border-b border-n-weak flex-shrink-0 px-5">
        <button
          v-for="sec in sections"
          :key="sec.key"
          class="flex items-center gap-1.5 py-3 px-1 mr-5 text-sm font-medium border-b-2 transition-colors"
          :class="activeSection === sec.key
            ? 'border-n-brand text-n-brand'
            : 'border-transparent text-n-slate-10 hover:text-n-slate-12'"
          @click="activeSection = sec.key"
        >
          <span :class="sec.icon" class="text-sm" />
          {{ sec.label }}
        </button>
      </div>

      <!-- Scrollable body -->
      <div class="flex-1 overflow-y-auto p-5 space-y-5">

        <!-- ── Geral ── -->
        <template v-if="activeSection === 'general'">
          <!-- Name -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              {{ $t('CRM.STAGE_NAME') }}
            </label>
            <input
              v-model="form.name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand"
              @keyup.enter="save"
            />
          </div>

          <!-- Color -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              {{ $t('CRM.STAGE_COLOR') }}
            </label>
            <div class="flex items-center gap-3">
              <input
                v-model="form.color"
                type="color"
                class="w-9 h-9 rounded-lg cursor-pointer border border-n-weak bg-n-solid-2"
              />
              <span class="text-sm text-n-slate-10 font-mono">{{ form.color }}</span>
            </div>
          </div>

          <!-- Description -->
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              {{ $t('CRM.STAGE_DESCRIPTION') }}
            </label>
            <textarea
              v-model="form.description"
              rows="3"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 focus:outline-none focus:border-n-brand resize-none"
              :placeholder="$t('CRM.STAGE_DESCRIPTION_PLACEHOLDER')"
            />
          </div>
        </template>

        <!-- ── Configurações ── -->
        <template v-else-if="activeSection === 'settings'">
          <div class="space-y-4">
            <!-- Caixas de entrada PRINCIPAIS desta coluna -->
            <div>
              <p class="text-sm font-medium text-n-slate-12 mb-1">
                📥 Caixas de entrada principais desta coluna
              </p>
              <p class="text-xs text-n-slate-10 mb-2.5 leading-relaxed">
                Marque o(s) número(s)/canal(is) que atendem os pacientes NESTA etapa.
                O balão do card abre a conversa dessas caixas primeiro, e o
                "Iniciar conversa" já vem com a caixa certa. Sem marcação = usa a
                conversa mais recente, como hoje.
              </p>
              <div class="space-y-1.5 max-h-44 overflow-y-auto pr-1">
                <label
                  v-for="inbox in inboxes"
                  :key="inbox.id"
                  class="flex items-center gap-2.5 px-3 py-2 rounded-lg border cursor-pointer transition-colors"
                  :class="form.main_inbox_ids.includes(inbox.id)
                    ? 'border-n-brand/60 bg-n-brand/5'
                    : 'border-n-weak hover:bg-n-alpha-1'"
                >
                  <input
                    type="checkbox"
                    class="rounded"
                    :checked="form.main_inbox_ids.includes(inbox.id)"
                    @change="toggleMainInbox(inbox.id)"
                  />
                  <span class="text-sm text-n-slate-12 truncate">{{ inbox.name }}</span>
                  <span
                    v-if="form.main_inbox_ids.includes(inbox.id)"
                    class="ml-auto text-[10px] font-semibold text-n-brand flex-shrink-0"
                  >principal</span>
                </label>
                <p v-if="!inboxes.length" class="text-xs text-n-slate-9">Carregando caixas…</p>
              </div>
            </div>
            <div class="border-t border-n-weak" />

            <!-- Coming soon badge -->
            <div class="flex items-center gap-2 text-xs text-n-slate-9 bg-n-alpha-1 rounded-lg px-3 py-2">
              <span class="i-lucide-clock-4 text-sm" />
              <span>As configurações abaixo serão salvas em versões futuras.</span>
            </div>

            <!-- Allow drag -->
            <label class="flex items-center justify-between py-2 cursor-pointer">
              <div>
                <p class="text-sm text-n-slate-12">{{ $t('CRM.SETTINGS_ALLOW_DRAG') }}</p>
              </div>
              <div class="w-10 h-5 bg-n-brand rounded-full flex-shrink-0 opacity-60 cursor-not-allowed" />
            </label>
            <div class="border-t border-n-weak" />

            <!-- Show counter -->
            <label class="flex items-center justify-between py-2 cursor-pointer">
              <div>
                <p class="text-sm text-n-slate-12">{{ $t('CRM.SETTINGS_SHOW_COUNTER') }}</p>
              </div>
              <div class="w-10 h-5 bg-n-brand rounded-full flex-shrink-0 opacity-60 cursor-not-allowed" />
            </label>
            <div class="border-t border-n-weak" />

            <!-- Max cards -->
            <div class="py-2">
              <p class="text-sm text-n-slate-12 mb-2">{{ $t('CRM.SETTINGS_MAX_CARDS') }}</p>
              <input
                type="number"
                min="0"
                class="w-32 border border-n-weak rounded-lg px-3 py-1.5 text-sm bg-n-solid-2 text-n-slate-10 cursor-not-allowed"
                :placeholder="$t('CRM.SETTINGS_MAX_CARDS_PLACEHOLDER')"
                disabled
              />
              <span class="ml-2 text-xs text-n-slate-9 bg-n-alpha-2 px-1.5 py-0.5 rounded">
                {{ $t('CRM.COMING_SOON') }}
              </span>
            </div>
          </div>
        </template>

        <!-- ── Automações ── -->
        <template v-else-if="activeSection === 'automations'">
          <div class="flex flex-col items-center justify-center py-10 text-center">
            <div class="w-14 h-14 rounded-2xl bg-n-brand/10 flex items-center justify-center mb-4">
              <span class="i-lucide-zap text-2xl text-n-brand" />
            </div>
            <h3 class="text-sm font-semibold text-n-slate-12 mb-2">
              {{ $t('CRM.STAGE_AUTOMATIONS') }}
            </h3>
            <p class="text-xs text-n-slate-10 max-w-xs leading-relaxed mb-5">
              {{ $t('CRM.STAGE_AUTOMATIONS_SOON') }}
            </p>

            <!-- Exemplos de gatilhos / ações (visual) -->
            <div class="w-full space-y-2 text-left">
              <p class="text-xs font-medium text-n-slate-10 uppercase tracking-wide mb-1">Gatilhos futuros</p>
              <div
                v-for="trigger in ['Quando o card entrar nesta coluna', 'Quando o card sair desta coluna', 'Quando permanecer X dias nesta coluna']"
                :key="trigger"
                class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-alpha-1 opacity-50"
              >
                <span class="i-lucide-play text-xs text-n-slate-10" />
                <span class="text-xs text-n-slate-11">{{ trigger }}</span>
                <span class="ml-auto text-[10px] bg-n-alpha-2 text-n-slate-9 px-1.5 py-0.5 rounded">Em breve</span>
              </div>

              <p class="text-xs font-medium text-n-slate-10 uppercase tracking-wide mt-4 mb-1">Ações futuras</p>
              <div
                v-for="action in ['Aplicar etiqueta', 'Alterar responsável', 'Enviar mensagem automática', 'Disparar webhook']"
                :key="action"
                class="flex items-center gap-2 px-3 py-2 rounded-lg bg-n-alpha-1 opacity-50"
              >
                <span class="i-lucide-arrow-right text-xs text-n-slate-10" />
                <span class="text-xs text-n-slate-11">{{ action }}</span>
                <span class="ml-auto text-[10px] bg-n-alpha-2 text-n-slate-9 px-1.5 py-0.5 rounded">Em breve</span>
              </div>
            </div>
          </div>
        </template>

      </div>

      <!-- Footer (abas com campos salvos de verdade) -->
      <div v-if="['general', 'settings'].includes(activeSection)" class="flex gap-2 px-5 py-4 border-t border-n-weak flex-shrink-0">
        <button
          class="flex-1 bg-n-brand text-white rounded-lg py-2 text-sm font-medium hover:bg-n-brand/90 transition-colors disabled:opacity-50"
          :disabled="isSaving || !form.name.trim()"
          @click="save"
        >
          {{ isSaving ? $t('CRM.MODAL.SAVING') : $t('CRM.SAVE') }}
        </button>
        <button
          class="px-4 py-2 border border-n-weak rounded-lg text-sm text-n-slate-11 hover:bg-n-alpha-1 transition-colors"
          @click="emit('close')"
        >
          {{ $t('CRM.CANCEL') }}
        </button>
      </div>

    </div>
  </div>
</template>
