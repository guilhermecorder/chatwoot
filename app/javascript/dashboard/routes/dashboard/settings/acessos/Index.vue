<script setup>
// 🔐 rodada 334 — Configurações → ACESSOS E PAPÉIS (só administradores).
// Quem vê e quem edita o quê, em árvore (filhos herdam do pai):
//   1. Papéis  → perfis reutilizáveis (Vendedor da loja, Recepção…), cada
//                um com a sua árvore e as suas unidades
//   2. Pessoas → cada login com o seu papel, a marcação própria por cima
//                (Abrir árvore), as unidades e o resumo Ver/Editar
//   3. Mapa    → a árvore inteira só-leitura, com o padrão de um atendente
//                sem configuração, para o admin entender o que existe
// Os dois endpoints de gravação devolvem o payload inteiro do admin — a
// tela se atualiza com a resposta, sem chamada extra.
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import AccessTreeEditor from 'dashboard/components-next/cevico/access/AccessTreeEditor.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import {
  effectiveMap,
  summarize,
  LEVEL_LABELS,
} from 'dashboard/helper/cevicoAccessTree';

const store = useStore();
const pal = useCevicoPalette({
  scope: 'settings:acessos',
  blocks: [
    { id: 'papeis', label: 'Papéis', icon: 'i-lucide-id-card' },
    { id: 'pessoas', label: 'Pessoas', icon: 'i-lucide-users' },
    { id: 'mapa', label: 'Mapa do sistema', icon: 'i-lucide-map' },
  ],
});
const { cvVars, blockVars } = pal;

const isLoading = ref(true);
const isSaving = ref(false);
const data = ref(null); // { roles, users, catalog, units, levels }

const apply = payload => {
  if (payload && Array.isArray(payload.users)) data.value = payload;
};
const load = async () => {
  try {
    const { data: payload } = await CrmAPI.getAccessAdmin();
    apply(payload);
  } catch {
    useAlert('Não consegui carregar os acessos.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const catalog = computed(() => data.value?.catalog || []);
const roles = computed(() => data.value?.roles || []);
const companyUnits = computed(() => data.value?.units || []);
const users = computed(() =>
  [...(data.value?.users || [])].sort((a, b) => {
    if (a.admin !== b.admin) return a.admin ? -1 : 1;
    return String(a.name || '').localeCompare(String(b.name || ''), 'pt-BR');
  })
);

const roleById = id => roles.value.find(r => String(r.id) === String(id));
const peopleOfRole = id =>
  users.value.filter(u => !u.admin && String(u.role_id) === String(id));
const unitLabel = key =>
  companyUnits.value.find(u => u.key === key)?.label || key;
const firstName = name => String(name || '').split(' ')[0];

// resumo Ver/Editar de um papel (a árvore dele, sem pessoa por cima)
const roleSummary = role =>
  summarize(
    effectiveMap({
      catalog: catalog.value,
      explicit: role.tree || {},
      roleTree: {},
      admin: false,
    })
  );
const personSummary = user =>
  user.admin
    ? summarize(
        effectiveMap({ catalog: catalog.value, explicit: {}, admin: true })
      )
    : summarize(user.effective || {});
const hasOwnMarks = user => Object.keys(user.tree || {}).length > 0;

// ══ 1. PAPÉIS ══════════════════════════════════════════════════════════
const roleForm = ref(null); // { id?, name, hint, tree, units, title }
const openNewRole = () => {
  roleForm.value = {
    name: '',
    hint: '',
    tree: {},
    units: [],
    title: 'Novo papel',
  };
};
const openEditRole = role => {
  roleForm.value = {
    id: role.id,
    name: role.name,
    hint: role.hint || '',
    tree: { ...(role.tree || {}) },
    units: [...(role.units || [])],
    title: `Editar · ${role.name}`,
  };
};
const duplicateRole = role => {
  roleForm.value = {
    name: `${role.name} (cópia)`,
    hint: role.hint || '',
    tree: { ...(role.tree || {}) },
    units: [...(role.units || [])],
    title: `Duplicar · ${role.name}`,
  };
};
const toggleUnit = (list, key) => {
  const idx = list.indexOf(key);
  if (idx === -1) list.push(key);
  else list.splice(idx, 1);
};
const saveRoles = async (list, okMessage) => {
  isSaving.value = true;
  try {
    const payload = await store.dispatch('crm/updateAccessRoles', list);
    apply(payload);
    useAlert(okMessage);
    return true;
  } catch {
    useAlert('Não consegui salvar os papéis.');
    return false;
  } finally {
    isSaving.value = false;
  }
};
const saveRole = async () => {
  const form = roleForm.value;
  if (!form?.name?.trim()) {
    useAlert('Dê um nome ao papel.');
    return;
  }
  const item = {
    id: form.id,
    name: form.name.trim(),
    hint: form.hint.trim(),
    tree: form.tree,
    units: form.units,
  };
  const list = form.id
    ? roles.value.map(r => (r.id === form.id ? item : r))
    : [...roles.value, item];
  const ok = await saveRoles(
    list,
    'Papel salvo! Quem usa esse papel já tem os acessos novos.'
  );
  if (ok) roleForm.value = null;
};
const roleToDelete = ref(null);
const confirmDeleteRole = async () => {
  const role = roleToDelete.value;
  if (!role) return;
  const list = roles.value.filter(r => r.id !== role.id);
  if (await saveRoles(list, `Papel “${role.name}” apagado.`)) {
    roleToDelete.value = null;
  }
};

// ══ 2. PESSOAS ═════════════════════════════════════════════════════════
const VIEW_KEY = 'cevico:acessos:pessoas-view';
const readView = () => {
  try {
    return localStorage.getItem(VIEW_KEY) === 'cards' ? 'cards' : 'lista';
  } catch {
    return 'lista';
  }
};
const peopleView = ref(readView());
const setPeopleView = mode => {
  peopleView.value = mode;
  try {
    localStorage.setItem(VIEW_KEY, mode);
  } catch {
    // sem localStorage (navegação privada): só não lembra a escolha
  }
};
const personSearch = ref('');
const filteredUsers = computed(() => {
  const q = personSearch.value.trim().toLowerCase();
  if (!q) return users.value;
  return users.value.filter(
    u =>
      String(u.name || '')
        .toLowerCase()
        .includes(q) ||
      String(u.email || '')
        .toLowerCase()
        .includes(q)
  );
});

const savePerson = async (payload, okMessage) => {
  isSaving.value = true;
  try {
    const result = await store.dispatch('crm/updateAgentAccess', payload);
    apply(result);
    useAlert(okMessage);
    return true;
  } catch {
    useAlert('Não consegui salvar os acessos dessa pessoa.');
    return false;
  } finally {
    isSaving.value = false;
  }
};
// troca de papel direto na lista
const changeRole = (user, roleId) =>
  savePerson(
    { userId: user.user_id, roleId: roleId || '' },
    roleId
      ? `${firstName(user.name)} agora é ${roleById(roleId)?.name}.`
      : `${firstName(user.name)} ficou sem papel (volta ao padrão).`
  );

const personForm = ref(null); // { userId, name, roleId, tree, units }
const openPerson = user => {
  personForm.value = {
    userId: user.user_id,
    name: user.name,
    email: user.email,
    legacy: user.legacy,
    roleId: user.role_id || '',
    tree: { ...(user.tree || {}) },
    units: [...(user.units || [])],
  };
};
const personRoleTree = computed(
  () => roleById(personForm.value?.roleId)?.tree || {}
);
const savePersonForm = async () => {
  const form = personForm.value;
  const ok = await savePerson(
    {
      userId: form.userId,
      tree: form.tree,
      roleId: form.roleId || '',
      units: form.units,
    },
    `Acessos de ${firstName(form.name)} salvos!`
  );
  if (ok) personForm.value = null;
};
const resetPersonForm = async () => {
  const form = personForm.value;
  const ok = await savePerson(
    { userId: form.userId, reset: true },
    `${firstName(form.name)} voltou ao padrão (o papel, se tiver, continua).`
  );
  if (ok) personForm.value = null;
};
// aplicar a árvore de um papel como marcação própria da pessoa
const applyRoleAsOwn = role => {
  if (!personForm.value) return;
  personForm.value.tree = { ...(role.tree || {}) };
};

const LEVEL_LIST = ['view', 'edit', 'none'];
</script>

<template>
  <div class="cv-page cv-overlay cv-acessos" :style="cvVars">
    <CevicoHero
      :pal="pal"
      title="Acessos e papéis"
      subtitle="quem vê e quem edita o quê · marcar uma área vale para tudo dentro dela (os filhos herdam do pai)"
      icon="i-lucide-shield-check"
    />

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ 1. PAPÉIS ══ -->
      <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('papeis')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"
            ><span class="i-lucide-id-card text-base"
          /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Papéis
          </h2>
          <button
            class="cv-btn cv-btn-sm ml-auto"
            type="button"
            @click="openNewRole"
          >
            <span class="i-lucide-plus text-xs" /> Novo papel
          </button>
        </div>
        <p class="text-xs text-n-slate-10 mb-6">
          um papel é um conjunto de acessos com nome (Recepção, Vendedor da
          loja, Médico…). A pessoa recebe o papel e, se precisar, uma marcação
          própria por cima.
        </p>

        <p v-if="!roles.length" class="cv-sub p-5 text-sm text-n-slate-10">
          Nenhum papel ainda. Crie o primeiro — ou deixe as pessoas no padrão do
          sistema e ajuste cada uma em “Abrir árvore”.
        </p>
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5"
        >
          <div
            v-for="role in roles"
            :key="role.id"
            class="cv-sub cv-sub-hover p-5 flex flex-col gap-3"
          >
            <div class="flex items-start gap-2">
              <div class="min-w-0 flex-1">
                <h3 class="text-base font-bold text-n-slate-12 leading-tight">
                  {{ role.name }}
                </h3>
                <p v-if="role.hint" class="text-[11px] text-n-slate-10 mt-0.5">
                  {{ role.hint }}
                </p>
              </div>
              <span
                class="cv-chip"
                :title="
                  peopleOfRole(role.id)
                    .map(u => u.name)
                    .join(', ') || 'ninguém ainda'
                "
              >
                <span class="i-lucide-users text-[10px]" />
                {{ peopleOfRole(role.id).length }}
              </span>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-for="lvl in LEVEL_LIST"
                :key="lvl"
                class="cv-acc-pill cv-acc-pill-sm"
                :class="`cv-acc-${lvl}`"
              >
                {{ LEVEL_LABELS[lvl] }} <b>{{ roleSummary(role)[lvl] }}</b>
              </span>
            </div>
            <div v-if="companyUnits.length" class="flex flex-wrap gap-1.5">
              <span
                v-if="!(role.units || []).length"
                class="cv-tag cv-tag-ghost"
              >
                <span class="i-lucide-store text-[10px]" /> todas as unidades
              </span>
              <span v-for="u in role.units" :key="u" class="cv-tag cv-tag-unit">
                <span class="i-lucide-store text-[10px]" /> {{ unitLabel(u) }}
              </span>
            </div>
            <div class="flex flex-wrap gap-1.5 mt-auto pt-1">
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                type="button"
                @click="openEditRole(role)"
              >
                <span class="i-lucide-pencil text-xs" /> Editar
              </button>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                type="button"
                @click="duplicateRole(role)"
              >
                <span class="i-lucide-copy text-xs" /> Duplicar
              </button>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm cv-btn-danger ml-auto"
                type="button"
                @click="roleToDelete = role"
              >
                <span class="i-lucide-trash-2 text-xs" /> Apagar
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ 2. PESSOAS ══ -->
      <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('pessoas')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-users text-base" /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Pessoas
          </h2>
          <span class="cv-chip">{{ users.length }}</span>
          <div class="cv-seg cv-seg-sm ml-auto">
            <button
              type="button"
              class="cv-seg-item"
              :class="{ 'cv-seg-on': peopleView === 'lista' }"
              @click="setPeopleView('lista')"
            >
              <span class="i-lucide-list text-xs" /> Lista
            </button>
            <button
              type="button"
              class="cv-seg-item"
              :class="{ 'cv-seg-on': peopleView === 'cards' }"
              @click="setPeopleView('cards')"
            >
              <span class="i-lucide-layout-grid text-xs" /> Cards
            </button>
          </div>
        </div>
        <p class="text-xs text-n-slate-10 mb-5">
          cada login com o seu papel e, se precisar, a marcação própria por cima
          (“Abrir árvore”). Administradores têm tudo.
        </p>
        <label class="cv-acessos-search mb-5">
          <span class="i-lucide-search text-sm opacity-60" />
          <input
            v-model="personSearch"
            type="search"
            class="cv-input"
            placeholder="Buscar pessoa…"
            aria-label="Buscar pessoa"
          />
        </label>

        <!-- LISTA -->
        <div v-if="peopleView === 'lista'" class="flex flex-col gap-2">
          <div
            v-for="user in filteredUsers"
            :key="user.user_id"
            class="cv-sub p-3 sm:p-4 cv-acessos-row"
          >
            <div class="min-w-0 cv-acessos-who">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-sm font-bold text-n-slate-12">{{
                  user.name
                }}</span>
                <span v-if="user.admin" class="cv-tag cv-tag-admin">
                  <span class="i-lucide-crown text-[10px]" /> administrador(a)
                </span>
                <span
                  v-if="user.legacy"
                  class="cv-tag cv-tag-ghost"
                  title="ainda usa as concessões do modelo antigo, convertidas na hora; salvar a árvore passa para o modelo novo"
                >
                  <span class="i-lucide-history text-[10px]" /> convertido do
                  modelo antigo
                </span>
                <span
                  v-if="!user.admin && hasOwnMarks(user)"
                  class="cv-tag cv-tag-ghost"
                  title="tem marcação própria por cima do papel"
                >
                  <span class="i-lucide-pen-line text-[10px]" /> marcação
                  própria
                </span>
              </div>
              <p class="text-[11px] text-n-slate-10 truncate">
                {{ user.email }}
              </p>
            </div>
            <div class="cv-acessos-role">
              <span
                v-if="user.admin"
                class="text-[11px] text-n-slate-10"
                title="administrador(a): tudo liberado"
              >
                tudo liberado
              </span>
              <select
                v-else
                class="cv-input cv-acessos-select"
                :value="user.role_id || ''"
                :disabled="isSaving"
                aria-label="Papel"
                @change="changeRole(user, $event.target.value)"
              >
                <option value="">sem papel (padrão)</option>
                <option v-for="role in roles" :key="role.id" :value="role.id">
                  {{ role.name }}
                </option>
              </select>
            </div>
            <div class="flex flex-wrap gap-1.5 cv-acessos-sum">
              <span
                v-for="lvl in LEVEL_LIST"
                :key="lvl"
                class="cv-acc-pill cv-acc-pill-sm"
                :class="`cv-acc-${lvl}`"
              >
                {{ LEVEL_LABELS[lvl] }} <b>{{ personSummary(user)[lvl] }}</b>
              </span>
            </div>
            <div
              v-if="companyUnits.length"
              class="flex flex-wrap gap-1 cv-acessos-units"
            >
              <span
                v-if="user.admin || !(user.units || []).length"
                class="cv-tag cv-tag-ghost"
                >todas as unidades</span
              >
              <span
                v-for="u in user.admin ? [] : user.units"
                :key="u"
                class="cv-tag cv-tag-unit"
                >{{ unitLabel(u) }}</span
              >
            </div>
            <div class="cv-acessos-act">
              <button
                v-if="!user.admin"
                class="cv-btn cv-btn-ghost cv-btn-sm"
                type="button"
                @click="openPerson(user)"
              >
                <span class="i-lucide-network text-xs" /> Abrir árvore
              </button>
            </div>
          </div>
          <p
            v-if="!filteredUsers.length"
            class="text-xs text-n-slate-10 py-4 text-center"
          >
            ninguém com “{{ personSearch }}”.
          </p>
        </div>

        <!-- CARDS -->
        <div
          v-else
          class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5"
        >
          <div
            v-for="user in filteredUsers"
            :key="user.user_id"
            class="cv-sub cv-sub-hover p-5 flex flex-col gap-3"
          >
            <div class="flex items-start gap-2">
              <div class="min-w-0 flex-1">
                <h3 class="text-base font-bold text-n-slate-12 leading-tight">
                  {{ user.name }}
                </h3>
                <p class="text-[11px] text-n-slate-10 truncate">
                  {{ user.email }}
                </p>
              </div>
              <span v-if="user.admin" class="cv-tag cv-tag-admin">
                <span class="i-lucide-crown text-[10px]" /> admin
              </span>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-if="user.legacy"
                class="cv-tag cv-tag-ghost"
                title="ainda usa as concessões do modelo antigo, convertidas na hora"
              >
                <span class="i-lucide-history text-[10px]" /> modelo antigo
              </span>
              <span
                v-if="!user.admin && hasOwnMarks(user)"
                class="cv-tag cv-tag-ghost"
                ><span class="i-lucide-pen-line text-[10px]" /> marcação
                própria</span
              >
              <span
                v-for="lvl in LEVEL_LIST"
                :key="lvl"
                class="cv-acc-pill cv-acc-pill-sm"
                :class="`cv-acc-${lvl}`"
              >
                {{ LEVEL_LABELS[lvl] }} <b>{{ personSummary(user)[lvl] }}</b>
              </span>
            </div>
            <div>
              <p class="cv-label mb-1">Papel</p>
              <span
                v-if="user.admin"
                class="text-xs text-n-slate-10"
                title="administrador(a): tudo liberado"
              >
                administrador(a) — tudo liberado
              </span>
              <select
                v-else
                class="cv-input w-full"
                :value="user.role_id || ''"
                :disabled="isSaving"
                aria-label="Papel"
                @change="changeRole(user, $event.target.value)"
              >
                <option value="">sem papel (padrão)</option>
                <option v-for="role in roles" :key="role.id" :value="role.id">
                  {{ role.name }}
                </option>
              </select>
            </div>
            <div v-if="companyUnits.length">
              <p class="cv-label mb-1">Unidades</p>
              <div class="flex flex-wrap gap-1">
                <span
                  v-if="user.admin || !(user.units || []).length"
                  class="cv-tag cv-tag-ghost"
                  >todas</span
                >
                <span
                  v-for="u in user.admin ? [] : user.units"
                  :key="u"
                  class="cv-tag cv-tag-unit"
                  >{{ unitLabel(u) }}</span
                >
              </div>
            </div>
            <button
              v-if="!user.admin"
              class="cv-btn cv-btn-ghost cv-btn-sm mt-auto self-start"
              type="button"
              @click="openPerson(user)"
            >
              <span class="i-lucide-network text-xs" /> Abrir árvore
            </button>
          </div>
          <p
            v-if="!filteredUsers.length"
            class="text-xs text-n-slate-10 py-4 text-center col-span-full"
          >
            ninguém com “{{ personSearch }}”.
          </p>
        </div>
      </div>

      <!-- ══ 3. MAPA DO SISTEMA ══ -->
      <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('mapa')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon"><span class="i-lucide-map text-base" /></span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Mapa do sistema
          </h2>
        </div>
        <p class="text-xs text-n-slate-10 mb-6">
          tudo o que existe, em árvore, com o nível que um atendente SEM
          configuração tem em cada tela. Só leitura — para entender o que dá
          para liberar.
        </p>
        <AccessTreeEditor
          :catalog="catalog"
          :model-value="{}"
          readonly
          start-expanded
        />
      </div>
    </template>

    <!-- ══ modal: papel (novo / editar / duplicar) ══ -->
    <div
      v-if="roleForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-2 sm:p-4"
      @click.self="roleForm = null"
    >
      <div
        class="cv-modal w-full max-w-3xl flex flex-col max-h-[94vh]"
        :style="blockVars('papeis')"
      >
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-id-card text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-[11px] opacity-85">Papéis</p>
            <h2 class="text-base font-bold leading-tight">
              {{ roleForm.title }}
            </h2>
          </div>
          <button
            class="cv-glass-btn cv-iconbtn flex-shrink-0"
            type="button"
            aria-label="Fechar"
            @click="roleForm = null"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>
        <div class="p-4 sm:p-5 overflow-y-auto flex flex-col gap-4">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="cv-label">Nome</span>
              <input
                v-model="roleForm.name"
                class="cv-input"
                maxlength="60"
                placeholder="ex.: Recepção"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span class="cv-label">Dica (opcional)</span>
              <input
                v-model="roleForm.hint"
                class="cv-input"
                maxlength="200"
                placeholder="ex.: agenda, confirmação e conversas"
              />
            </label>
          </div>
          <div v-if="companyUnits.length">
            <p class="cv-label mb-1.5">Unidades (nenhuma marcada = todas)</p>
            <div class="flex flex-wrap gap-2">
              <label
                v-for="u in companyUnits"
                :key="u.key"
                class="cv-chip cv-chip-lg cursor-pointer"
              >
                <input
                  type="checkbox"
                  class="accent-current"
                  :checked="roleForm.units.includes(u.key)"
                  @change="toggleUnit(roleForm.units, u.key)"
                />
                {{ u.label }}
              </label>
            </div>
          </div>
          <AccessTreeEditor v-model="roleForm.tree" :catalog="catalog" />
        </div>
        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <button
            class="cv-btn"
            type="button"
            :disabled="isSaving"
            @click="saveRole"
          >
            {{ isSaving ? 'Salvando…' : 'Salvar papel' }}
          </button>
          <button
            class="cv-btn cv-btn-ghost"
            type="button"
            @click="roleForm = null"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>

    <!-- ══ modal: apagar papel ══ -->
    <div
      v-if="roleToDelete"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="roleToDelete = null"
    >
      <div
        class="cv-modal w-full max-w-md flex flex-col"
        :style="blockVars('papeis')"
      >
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-trash-2 text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-[11px] opacity-85">Papéis</p>
            <h2 class="text-base font-bold leading-tight">
              Apagar “{{ roleToDelete.name }}”?
            </h2>
          </div>
        </div>
        <div class="p-5 text-sm text-n-slate-11">
          <p>
            <b>{{ peopleOfRole(roleToDelete.id).length }}</b>
            {{
              peopleOfRole(roleToDelete.id).length === 1
                ? 'pessoa usa'
                : 'pessoas usam'
            }}
            este papel. Quem usa volta ao padrão do sistema (a marcação própria
            de cada um continua valendo).
          </p>
        </div>
        <div class="cv-modal-foot flex items-center gap-2">
          <button
            class="cv-btn cv-btn-ghost cv-btn-danger-on"
            type="button"
            :disabled="isSaving"
            @click="confirmDeleteRole"
          >
            {{ isSaving ? 'Apagando…' : 'Apagar papel' }}
          </button>
          <button
            class="cv-btn cv-btn-ghost"
            type="button"
            @click="roleToDelete = null"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>

    <!-- ══ modal: árvore da pessoa ══ -->
    <div
      v-if="personForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-2 sm:p-4"
      @click.self="personForm = null"
    >
      <div
        class="cv-modal w-full max-w-3xl flex flex-col max-h-[94vh]"
        :style="blockVars('pessoas')"
      >
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-network text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-[11px] opacity-85">Acessos de</p>
            <h2 class="text-base font-bold leading-tight">
              {{ personForm.name }}
            </h2>
          </div>
          <button
            class="cv-glass-btn cv-iconbtn flex-shrink-0"
            type="button"
            aria-label="Fechar"
            @click="personForm = null"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>
        <div class="p-4 sm:p-5 overflow-y-auto flex flex-col gap-4">
          <p
            v-if="personForm.legacy"
            class="cv-block cv-strip cv-amber px-4 py-2 text-xs text-n-slate-11"
          >
            <span class="i-lucide-history text-xs" /> ainda usa o modelo antigo
            (convertido na hora). Ao salvar, passa para a árvore nova.
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="flex flex-col gap-1">
              <span class="cv-label">Papel</span>
              <select v-model="personForm.roleId" class="cv-input">
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
                    :checked="personForm.units.includes(u.key)"
                    @change="toggleUnit(personForm.units, u.key)"
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
              @click="applyRoleAsOwn(role)"
            >
              <span class="i-lucide-wand-sparkles text-[10px]" />
              {{ role.name }}
            </button>
          </div>
          <AccessTreeEditor
            v-model="personForm.tree"
            :catalog="catalog"
            :role-tree="personRoleTree"
          />
        </div>
        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <button
            class="cv-btn"
            type="button"
            :disabled="isSaving"
            @click="savePersonForm"
          >
            {{ isSaving ? 'Salvando…' : 'Salvar acessos' }}
          </button>
          <button
            class="cv-btn cv-btn-ghost"
            type="button"
            :disabled="isSaving"
            title="apaga a marcação própria; o papel continua"
            @click="resetPersonForm"
          >
            <span class="i-lucide-rotate-ccw text-xs" /> Voltar ao padrão
          </button>
          <button
            class="cv-btn cv-btn-ghost ml-auto"
            type="button"
            @click="personForm = null"
          >
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style lang="scss">
/* 🔐 rodada 334 — Acessos e papéis */
.cv-page .cv-acessos-search {
  position: relative;
  display: flex;
  align-items: center;
  max-width: 360px;
}
.cv-page .cv-acessos-search > span {
  position: absolute;
  left: 11px;
  pointer-events: none;
}
.cv-page .cv-acessos-search .cv-input {
  width: 100%;
  padding-left: 32px;
  margin-bottom: 0;
}
.cv-page .cv-acessos-select {
  height: 32px;
  font-size: 12px;
  margin-bottom: 0;
  max-width: 220px;
}
.cv-page select.cv-input {
  margin-bottom: 0;
}
/* linha da lista de pessoas: quem · papel · resumo · unidades · ação */
.cv-page .cv-acessos-row {
  display: grid;
  grid-template-columns: minmax(180px, 1.4fr) minmax(160px, 1fr) auto auto auto;
  align-items: center;
  gap: 8px 14px;
}
@media (max-width: 1100px) {
  .cv-page .cv-acessos-row {
    grid-template-columns: 1fr 1fr;
  }
  .cv-page .cv-acessos-who {
    grid-column: 1 / -1;
  }
}
@media (max-width: 640px) {
  .cv-page .cv-acessos-row {
    grid-template-columns: 1fr;
  }
}
</style>
