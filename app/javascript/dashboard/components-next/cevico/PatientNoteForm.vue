<script setup>
// 📝 PatientNoteForm (item 211, 23/09): escrever uma NOTA sobre um paciente —
// busca a pessoa pelo nome/telefone, escreve o recado e salva. Usado no
// ambiente Tarefas (modal) e no Meu Painel (inline). A nota é a mesma do
// contato (Note): aparece na ficha, no Espaço do Paciente e na conversa.
import { ref, computed, nextTick, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import { createContactSearcher } from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper';

const props = defineProps({
  // paciente já escolhido (ex.: vindo de um cartão) — pula a busca
  contact: { type: Object, default: null },
  compact: { type: Boolean, default: false },
  autofocus: { type: Boolean, default: true },
});
const emit = defineEmits(['saved', 'cancel']);

const searchContacts = createContactSearcher();
const q = ref('');
const results = ref([]);
const searching = ref(false);
const searched = ref(false);
const chosen = ref(props.contact ? { ...props.contact } : null);
const content = ref('');
const isSaving = ref(false);
const searchEl = ref(null);
const textEl = ref(null);
let timer = null;

const runSearch = async () => {
  const term = q.value.trim();
  if (term.length < 2) {
    results.value = [];
    searched.value = false;
    return;
  }
  searching.value = true;
  try {
    const list = await searchContacts(term, { reachableOnly: false });
    if (list === null) return; // busca cancelada por outra mais nova
    results.value = (list || []).slice(0, 8);
    searched.value = true;
  } catch {
    results.value = [];
  } finally {
    searching.value = false;
  }
};
const onType = () => {
  clearTimeout(timer);
  timer = setTimeout(runSearch, 300);
};
const pick = c => {
  chosen.value = { id: c.id, name: c.name, phone: c.phoneNumber || c.phone_number || '' };
  results.value = [];
  q.value = '';
  nextTick(() => textEl.value?.focus());
};
const clearChosen = () => {
  chosen.value = null;
  nextTick(() => searchEl.value?.focus());
};
const canSave = computed(() => Boolean(chosen.value?.id) && content.value.trim().length > 0);
const save = async () => {
  if (!canSave.value || isSaving.value) return;
  isSaving.value = true;
  try {
    const { data } = await CrmAPI.createPatientNote(chosen.value.id, content.value.trim());
    useAlert(`Nota de ${chosen.value.name} salva.`);
    content.value = '';
    if (!props.contact) chosen.value = null;
    emit('saved', data);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui salvar a nota.');
  } finally {
    isSaving.value = false;
  }
};
onMounted(() => {
  if (!props.autofocus) return;
  nextTick(() => (chosen.value ? textEl.value : searchEl.value)?.focus());
});
</script>

<template>
  <div class="flex flex-col gap-2.5">
    <!-- 1) quem é o paciente -->
    <div v-if="!chosen" class="relative">
      <span class="cv-label block mb-1">Paciente</span>
      <div class="relative">
        <span class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-9" />
        <input
          ref="searchEl"
          v-model="q"
          class="cv-input w-full !pl-9"
          placeholder="Nome ou telefone do paciente…"
          @input="onType"
          @keydown.enter.prevent="results.length && pick(results[0])"
        />
      </div>
      <div
        v-if="q.trim().length >= 2"
        class="cv-pop absolute left-0 right-0 top-full mt-1 z-20 max-h-64 overflow-y-auto p-1.5"
      >
        <p v-if="searching" class="text-xs text-n-slate-9 px-2 py-2">Procurando…</p>
        <p v-else-if="searched && !results.length" class="text-xs text-n-slate-9 px-2 py-2">
          Ninguém com esse nome ou telefone.
        </p>
        <button
          v-for="c in results"
          :key="c.id"
          type="button"
          class="w-full text-left flex items-center gap-2.5 px-2.5 py-2 rounded-xl hover:bg-n-alpha-1"
          @click="pick(c)"
        >
          <span class="cv-icon cv-icon-sm"><span class="i-lucide-user-round text-xs" /></span>
          <span class="min-w-0">
            <span class="block text-sm font-semibold text-n-slate-12 truncate">{{ c.name || 'Sem nome' }}</span>
            <span class="block text-[11px] text-n-slate-9 truncate">{{ c.phoneNumber || c.phone_number || c.email || 'sem telefone' }}</span>
          </span>
        </button>
      </div>
    </div>
    <div v-else class="flex items-center gap-2 flex-wrap">
      <span class="cv-label">Paciente</span>
      <span class="cv-chip cv-chip-lg">
        <span class="i-lucide-user-round text-xs" />
        {{ chosen.name }}
        <span v-if="chosen.phone" class="opacity-70 font-normal">· {{ chosen.phone }}</span>
      </span>
      <button v-if="!contact" type="button" class="text-[11px] text-n-slate-9 hover:text-n-slate-12 hover:underline" @click="clearChosen">
        trocar
      </button>
    </div>

    <!-- 2) o recado -->
    <div>
      <span v-if="!compact" class="cv-label block mb-1">Nota</span>
      <textarea
        ref="textEl"
        v-model="content"
        :rows="compact ? 2 : 3"
        class="cv-input w-full resize-none"
        placeholder="Ex.: pediu para ligar semana que vem; prefere de manhã…"
        @keydown.meta.enter="save"
        @keydown.ctrl.enter="save"
      />
    </div>

    <div class="flex items-center gap-2">
      <button type="button" class="cv-btn" :class="compact ? 'cv-btn-sm' : ''" :disabled="!canSave || isSaving" @click="save">
        <span :class="isSaving ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-check'" class="text-xs" />
        {{ isSaving ? 'Salvando…' : 'Salvar nota' }}
      </button>
      <button v-if="$attrs.onCancel" type="button" class="cv-btn cv-btn-ghost" :class="compact ? 'cv-btn-sm' : ''" @click="emit('cancel')">
        Cancelar
      </button>
      <span class="text-[10px] text-n-slate-9 ml-auto hidden sm:inline">a nota vai para a ficha e o Espaço do Paciente</span>
    </div>
  </div>
</template>
