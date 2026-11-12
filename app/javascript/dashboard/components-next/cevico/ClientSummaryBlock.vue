<script setup>
// 📝 11/11/2026 (LIFE, pedido do Guilherme): RESUMO DO CLIENTE na Central do
// cliente — a ficha com o que ele contou (conta de luz, consumo que vai
// aumentar, telhado…). O atendente de IA preenche durante a conversa
// (ferramenta anotar_cliente); aqui a equipe lê, corrige e completa.
// Os campos são os que a empresa escolheu (Crm::ClientSummary).
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  // { enabled, fields: [{ key, label, hint, value, at, by }], filled }
  summary: { type: Object, required: true },
  contactId: { type: [Number, String], required: true },
  canEdit: { type: Boolean, default: false },
});
const emit = defineEmits(['saved']);

const TXT = {
  title: 'Resumo do cliente',
  subtitle: 'O que ele contou, para ninguém precisar perguntar de novo',
  edit: 'Completar',
  save: 'Salvar',
  cancel: 'Cancelar',
  empty: 'ainda não informado',
  nothing:
    'Nada anotado ainda. O atendente preenche durante a conversa; você também pode completar por aqui.',
  saved: 'Resumo do cliente salvo.',
  error: 'Não consegui salvar o resumo agora.',
};

const editing = ref(false);
const saving = ref(false);
const draft = ref({});

const fields = computed(() => props.summary?.fields || []);
const filled = computed(() => fields.value.filter(f => f.value));

const whoWhen = field => {
  if (!field.at) return '';
  const day = new Date(field.at).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
  });
  return field.by ? `${field.by} · ${day}` : day;
};

const startEdit = () => {
  draft.value = Object.fromEntries(
    fields.value.map(f => [f.key, f.value || ''])
  );
  editing.value = true;
};

const save = async () => {
  if (saving.value) return;
  saving.value = true;
  try {
    const { data } = await CrmAPI.updatePatientProfile(props.contactId, {
      ficha: draft.value,
    });
    emit('saved', data.client_summary);
    editing.value = false;
    useAlert(TXT.saved);
  } catch (error) {
    useAlert(error?.response?.data?.error || TXT.error);
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="cv-block p-5 sm:p-6">
    <div class="flex items-center gap-3 mb-4 flex-wrap">
      <span class="cv-icon">
        <span class="i-lucide-clipboard-list text-base" />
      </span>
      <div class="min-w-0 flex-1">
        <h2 class="text-sm font-bold text-n-slate-12 leading-tight">
          {{ TXT.title }}
        </h2>
        <p class="text-[11px] text-n-slate-10 mt-0.5">{{ TXT.subtitle }}</p>
      </div>
      <button
        v-if="canEdit && !editing"
        class="cv-btn cv-btn-ghost cv-btn-sm"
        @click="startEdit"
      >
        <span class="i-lucide-pencil text-xs" />
        {{ TXT.edit }}
      </button>
    </div>

    <!-- leitura -->
    <template v-if="!editing">
      <p v-if="!filled.length" class="text-xs text-n-slate-10 leading-relaxed">
        {{ TXT.nothing }}
      </p>
      <dl v-else class="cs-grid">
        <div v-for="field in filled" :key="field.key" class="cs-item">
          <dt>{{ field.label }}</dt>
          <dd>{{ field.value }}</dd>
          <small v-if="whoWhen(field)">{{ whoWhen(field) }}</small>
        </div>
      </dl>
    </template>

    <!-- edição: todos os campos da empresa -->
    <form v-else class="cs-form" @submit.prevent="save">
      <label v-for="field in fields" :key="field.key" class="cs-row">
        <span class="cs-row-label">{{ field.label }}</span>
        <input
          v-model="draft[field.key]"
          type="text"
          maxlength="200"
          class="cv-input w-full text-sm"
          :placeholder="field.hint || TXT.empty"
        />
      </label>
      <div class="flex items-center gap-2 mt-1">
        <button type="submit" class="cv-btn cv-btn-sm" :disabled="saving">
          <span
            class="text-xs"
            :class="
              saving ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-check'
            "
          />
          {{ TXT.save }}
        </button>
        <button
          type="button"
          class="cv-btn cv-btn-ghost cv-btn-sm"
          @click="editing = false"
        >
          {{ TXT.cancel }}
        </button>
      </div>
    </form>
  </div>
</template>

<style scoped>
.cs-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
  margin: 0;
}
@media (min-width: 640px) {
  .cs-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (min-width: 1024px) {
  .cs-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}
.cs-item {
  padding: 10px 12px;
  border-radius: 12px;
  border-left: 3px solid #ea580c;
  background: rgba(100, 116, 139, 0.08);
}
.cs-item dt {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  color: #64748b;
}
.cs-item dd {
  margin: 2px 0 0;
  font-size: 15px;
  font-weight: 600;
  line-height: 1.35;
  color: #0f172a;
  overflow-wrap: anywhere;
}
.cs-item small {
  display: block;
  margin-top: 3px;
  font-size: 10.5px;
  color: #64748b;
}
:global(.dark .cs-item) {
  background: rgba(255, 255, 255, 0.05);
}
:global(.dark .cs-item dt),
:global(.dark .cs-item small) {
  color: rgba(255, 255, 255, 0.6);
}
:global(.dark .cs-item dd) {
  color: #fff;
}
.cs-form {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.cs-row {
  display: grid;
  grid-template-columns: 1fr;
  gap: 4px;
  align-items: center;
}
@media (min-width: 640px) {
  .cs-row {
    grid-template-columns: 220px 1fr;
    gap: 12px;
  }
}
.cs-row-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  color: #64748b;
}
:global(.dark .cs-row-label) {
  color: rgba(255, 255, 255, 0.65);
}
</style>
