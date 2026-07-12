<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  agent: { type: Object, required: true },
});

const emit = defineEmits(['close']);

const store = useStore();

// seções do sistema que o admin pode bloquear por agente
const FEATURES = [
  { key: 'inbox',         label: 'Caixa de entrada' },
  { key: 'conversation',  label: 'Conversas' },
  { key: 'crm',           label: 'CRM (funil de leads)' },
  { key: 'crm_campaigns', label: 'Campanha WhatsApp (mensagens em massa)' },
  { key: 'tasks',         label: 'Tarefas' },
  { key: 'agenda',        label: 'Agenda' },
  { key: 'reports',       label: 'Relatórios (dashboards)' },
  { key: 'academy',       label: 'Academia CEVICO' },
  { key: 'companies',     label: 'Empresas' },
  { key: 'captain',       label: 'Captain (IA)' },
  { key: 'settings',      label: 'Configurações' },
];

const crmSettings = useMapGetter('crm/getSettings');

const blocked = ref([]);
const isSaving = ref(false);

onMounted(async () => {
  if (!Object.keys(crmSettings.value.agent_permissions ?? {}).length) {
    await store.dispatch('crm/fetchSettings').catch(() => {});
  }
  blocked.value = [
    ...(crmSettings.value.agent_permissions?.[String(props.agent.id)] ?? []),
  ];
});

const toggle = key => {
  const idx = blocked.value.indexOf(key);
  if (idx === -1) blocked.value.push(key);
  else blocked.value.splice(idx, 1);
};

const blockedCount = computed(() => blocked.value.length);

const save = async () => {
  isSaving.value = true;
  try {
    const perms = { ...(crmSettings.value.agent_permissions ?? {}) };
    if (blocked.value.length) perms[String(props.agent.id)] = blocked.value;
    else delete perms[String(props.agent.id)];
    await store.dispatch('crm/updateSettings', { agent_permissions: perms });
    useAlert('Acessos atualizados!');
    emit('close');
  } catch {
    useAlert('Não foi possível salvar os acessos.');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col">
    <div class="px-8 pt-8 pb-4">
      <h2 class="text-base font-semibold text-n-slate-12">
        Acessos de {{ agent.name }}
      </h2>
      <p class="text-sm text-n-slate-10 mt-1">
        Desmarque as seções que {{ agent.name.split(' ')[0] }} <strong>não</strong> deve acessar.
        As seções bloqueadas somem do menu dela(e).
      </p>
    </div>

    <div class="px-8 space-y-1">
      <label
        v-for="feature in FEATURES"
        :key="feature.key"
        class="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-n-alpha-1 cursor-pointer"
      >
        <input
          type="checkbox"
          class="rounded accent-n-brand"
          :checked="!blocked.includes(feature.key)"
          @change="toggle(feature.key)"
        />
        <span class="text-sm text-n-slate-12">{{ feature.label }}</span>
        <span
          v-if="blocked.includes(feature.key)"
          class="text-[10px] font-medium text-red-500 bg-red-500/10 rounded-full px-2 py-0.5 ml-auto"
        >bloqueado</span>
      </label>
    </div>

    <div class="flex items-center gap-2 px-8 py-6">
      <button
        class="bg-n-brand text-white rounded-lg px-4 py-2 text-sm font-medium disabled:opacity-50"
        :disabled="isSaving"
        @click="save"
      >
        {{ isSaving ? 'Salvando...' : 'Salvar acessos' }}
      </button>
      <button
        class="border border-n-weak rounded-lg px-4 py-2 text-sm text-n-slate-11"
        @click="emit('close')"
      >
        Cancelar
      </button>
      <span v-if="blockedCount" class="text-xs text-n-slate-10 ml-auto">
        {{ blockedCount }} seção(ões) bloqueada(s)
      </span>
    </div>
  </div>
</template>
