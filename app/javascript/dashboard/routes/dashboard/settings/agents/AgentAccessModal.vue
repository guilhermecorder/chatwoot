<script setup>
// 🔐 rodada 334 — o escudo de Configurações → Equipe abre a ÁRVORE de
// acessos da pessoa (ver × editar por tela). Mesma interface de antes
// (prop `agent`, emit `close`); por dentro usa o AccessTreeEditor:
//   • papel da pessoa (a árvore do papel vale por baixo);
//   • marcação própria por cima (só o que for diferente do papel);
//   • unidades (lojas) que ela pode ver — vazio = todas;
//   • perfis rápidos = copiar a árvore de um papel como marcação própria;
//   • Salvar / Voltar ao padrão (apaga a marcação própria).
// O modal fica fora de qualquer .cv-page, então ele mesmo veste a pele do
// kit (cv-page + cv-blue) para os tokens --cv-* existirem.
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import AccessTreeEditor from 'dashboard/components-next/cevico/access/AccessTreeEditor.vue';
import {
  summarize,
  effectiveMap,
  LEVEL_LABELS,
} from 'dashboard/helper/cevicoAccessTree';

const props = defineProps({
  agent: { type: Object, required: true },
});
const emit = defineEmits(['close']);

const store = useStore();
const isTargetAdmin = computed(() => props.agent.role === 'administrator');
const firstName = computed(() => String(props.agent.name || '').split(' ')[0]);

const isLoading = ref(true);
const isSaving = ref(false);
const data = ref(null); // payload do access_admin
const record = ref(null); // o registro desta pessoa dentro do payload

const roleId = ref('');
const tree = ref({});
const units = ref([]);

const hydrate = payload => {
  data.value = payload;
  record.value =
    (payload?.users || []).find(
      u => String(u.user_id) === String(props.agent.id)
    ) || null;
  roleId.value = record.value?.role_id || '';
  tree.value = { ...(record.value?.tree || {}) };
  units.value = [...(record.value?.units || [])];
};

onMounted(async () => {
  try {
    const { data: payload } = await CrmAPI.getAccessAdmin();
    hydrate(payload);
  } catch {
    useAlert('Não consegui carregar os acessos.');
  } finally {
    isLoading.value = false;
  }
});

const catalog = computed(() => data.value?.catalog || []);
const roles = computed(() => data.value?.roles || []);
const companyUnits = computed(() => data.value?.units || []);
const roleTree = computed(
  () => roles.value.find(r => String(r.id) === roleId.value)?.tree || {}
);
// resumo do que VAI valer com o que está na tela agora
const preview = computed(() =>
  summarize(
    effectiveMap({
      catalog: catalog.value,
      explicit: tree.value,
      roleTree: roleTree.value,
      admin: isTargetAdmin.value,
    })
  )
);
const LEVEL_LIST = ['view', 'edit', 'none'];

const toggleUnit = key => {
  const idx = units.value.indexOf(key);
  if (idx === -1) units.value.push(key);
  else units.value.splice(idx, 1);
};
// perfil rápido: a árvore do papel vira marcação própria (ajustável)
const applyRole = role => {
  tree.value = { ...(role.tree || {}) };
};

const save = async () => {
  isSaving.value = true;
  try {
    await store.dispatch('crm/updateAgentAccess', {
      userId: props.agent.id,
      tree: tree.value,
      roleId: roleId.value || '',
      units: units.value,
    });
    useAlert(`Acessos de ${firstName.value} salvos!`);
    emit('close');
  } catch {
    useAlert('Não foi possível salvar os acessos.');
  } finally {
    isSaving.value = false;
  }
};
const reset = async () => {
  isSaving.value = true;
  try {
    const payload = await store.dispatch('crm/updateAgentAccess', {
      userId: props.agent.id,
      reset: true,
    });
    hydrate(payload);
    useAlert(
      `${firstName.value} voltou ao padrão (o papel, se tiver, continua).`
    );
  } catch {
    useAlert('Não foi possível voltar ao padrão.');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="cv-page cv-overlay">
    <div class="cv-blue flex flex-col max-h-[88vh]">
      <!-- cabeçalho na cor do kit -->
      <div class="cv-modal-head flex items-center gap-3 flex-wrap">
        <span
          class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
        >
          <span class="i-lucide-shield-check text-base" />
        </span>
        <div class="flex-1 min-w-0">
          <p class="text-[11px] opacity-85">Acessos de</p>
          <h2 class="text-base font-bold leading-tight">{{ agent.name }}</h2>
        </div>
        <span
          v-for="lvl in LEVEL_LIST"
          v-show="!isLoading"
          :key="lvl"
          class="cv-glass-chip"
          :title="`${preview[lvl]} telas em ${LEVEL_LABELS[lvl]}`"
        >
          {{ LEVEL_LABELS[lvl] }} <b>{{ preview[lvl] }}</b>
        </span>
      </div>

      <div class="px-5 pt-4 pb-2 overflow-y-auto flex flex-col gap-4">
        <p v-if="isTargetAdmin" class="text-sm text-n-slate-11">
          {{ firstName }} é <strong>administrador(a)</strong> e tem acesso a
          tudo — não há o que configurar aqui.
        </p>

        <template v-else-if="!isLoading">
          <p class="text-xs text-n-slate-10">
            o papel vale por baixo; a marcação própria só onde {{ firstName }}
            for diferente do papel. Marcar uma área vale para tudo dentro dela.
          </p>
          <p
            v-if="record?.legacy"
            class="cv-block cv-strip cv-amber px-4 py-2 text-xs text-n-slate-11"
          >
            <span class="i-lucide-history text-xs" /> ainda usa o modelo antigo
            (convertido na hora). Ao salvar, passa para a árvore nova.
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="cv-label">Papel</span>
              <select v-model="roleId" class="cv-input !mb-0">
                <option value="">sem papel (padrão do sistema)</option>
                <option v-for="role in roles" :key="role.id" :value="role.id">
                  {{ role.name }}
                </option>
              </select>
            </label>
            <div v-if="companyUnits.length">
              <p class="cv-label mb-1.5">Unidades (nenhuma = todas)</p>
              <div class="flex flex-wrap gap-2">
                <label
                  v-for="u in companyUnits"
                  :key="u.key"
                  class="cv-chip cv-chip-lg cursor-pointer"
                >
                  <input
                    type="checkbox"
                    class="accent-current"
                    :checked="units.includes(u.key)"
                    @change="toggleUnit(u.key)"
                  />
                  {{ u.label }}
                </label>
              </div>
            </div>
          </div>

          <div v-if="roles.length" class="flex items-center gap-1.5 flex-wrap">
            <span class="cv-label">Perfis rápidos:</span>
            <button
              v-for="role in roles"
              :key="role.id"
              type="button"
              class="cv-chip"
              :title="`copia a árvore de “${role.name}” como marcação própria (dá para ajustar depois)`"
              @click="applyRole(role)"
            >
              <span class="i-lucide-wand-sparkles text-[10px]" />
              {{ role.name }}
            </button>
          </div>

          <AccessTreeEditor
            v-model="tree"
            :catalog="catalog"
            :role-tree="roleTree"
          />
        </template>

        <p v-else class="text-xs text-n-slate-10 py-6 text-center">
          carregando…
        </p>
      </div>

      <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
        <template v-if="!isTargetAdmin && !isLoading">
          <button
            class="cv-btn"
            type="button"
            :disabled="isSaving"
            @click="save"
          >
            {{ isSaving ? 'Salvando…' : 'Salvar acessos' }}
          </button>
          <button
            class="cv-btn cv-btn-ghost"
            type="button"
            :disabled="isSaving"
            title="apaga a marcação própria; o papel continua"
            @click="reset"
          >
            <span class="i-lucide-rotate-ccw text-xs" /> Voltar ao padrão
          </button>
        </template>
        <button
          class="cv-btn cv-btn-ghost ml-auto"
          type="button"
          @click="emit('close')"
        >
          {{ isTargetAdmin ? 'Fechar' : 'Cancelar' }}
        </button>
      </div>
    </div>
  </div>
</template>
