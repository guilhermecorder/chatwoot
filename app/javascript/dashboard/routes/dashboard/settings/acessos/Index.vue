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
// 🧭 item 336: PRIMEIRA tela no Guia arejado (CvCabecalho + CvBloco, 60-30-10,
// um resumo em texto por pessoa em vez de pílulas, linhas de 52px).
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import CvCabecalho from 'dashboard/components-next/cevico/guia/CvCabecalho.vue';
import CvBloco from 'dashboard/components-next/cevico/guia/CvBloco.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import AccessTreeEditor from 'dashboard/components-next/cevico/access/AccessTreeEditor.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { effectiveMap, summarize } from 'dashboard/helper/cevicoAccessTree';

const store = useStore();
const pal = useCevicoPalette({
  scope: 'settings:acessos',
  blocks: [
    { id: 'papeis', label: 'Papéis', icon: 'i-lucide-id-card' },
    { id: 'pessoas', label: 'Pessoas', icon: 'i-lucide-users' },
    { id: 'mapa', label: 'Mapa do sistema', icon: 'i-lucide-map' },
  ],
});
const { cvVars } = pal;

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

// ══ 🧭 0. O QUE CADA ADMINISTRADOR VÊ (11/11 · só o DONO da conta) ══
// O dono deixa outro administrador só com o essencial e libera aos poucos.
const souDono = computed(() =>
  (data.value?.owner_ids || []).includes(Number(store.getters.getCurrentUserID))
);
const adminsDaTriagem = computed(() =>
  users.value.filter(u => u.admin && !u.owner)
);
const areas = computed(() =>
  catalog.value.map(n => ({
    key: n.key,
    label: n.label,
    filhos: (n.children || []).map(c => ({ key: c.key, label: c.label })),
  }))
);
// 11/11 (pedido do Guilherme): a Central do cliente ('pacientes') entra no
// essencial — quem vende precisa abrir a página do cliente
// textos do bloco da triagem (fora do template, como pede o eslint do projeto)
const TRIAGEM_TXT = {
  limitado: 'vê só o que você liberou',
  tudo: 'vê tudo',
  liberarTudo: 'Liberar tudo',
  essencial: 'Mostrar só o essencial',
  dentroDe: 'Dentro de',
  dicaAparece: 'Aparece para a pessoa. Clique para esconder.',
  dicaEscondido: 'Escondido. Clique para liberar.',
};
const TRIAGEM_PADRAO = [
  'inicio',
  'conversas',
  'crm',
  'tarefas',
  'agenda',
  'pacientes',
];
// dentro das áreas liberadas, o que NÃO é do dia a dia começa escondido
const TRIAGEM_ESCONDE = [
  'crm.funis',
  'crm.campanhas',
  'crm.jornada',
  'crm.formularios',
  'crm.fontes',
  'agenda.configuracao',
];
const salvarTriagem = async (user, body, okMessage) => {
  isSaving.value = true;
  try {
    const { data: payload } = await CrmAPI.updateAdminLimits({
      userId: user.user_id,
      ...body,
    });
    apply(payload);
    if (okMessage) useAlert(okMessage);
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar.');
  } finally {
    isSaving.value = false;
  }
};
const chavesDoCatalogo = computed(() =>
  areas.value.flatMap(a => [a.key, ...a.filhos.map(f => f.key)])
);
const ligarTriagem = user =>
  salvarTriagem(
    user,
    {
      liberados: TRIAGEM_PADRAO.filter(k => chavesDoCatalogo.value.includes(k)),
      escondidos: TRIAGEM_ESCONDE.filter(k =>
        chavesDoCatalogo.value.includes(k)
      ),
    },
    `${String(user.name || '').split(' ')[0]} agora vê só o essencial.`
  );
const liberarTudo = user =>
  salvarTriagem(
    user,
    { liberarTudo: true },
    `${String(user.name || '').split(' ')[0]} voltou a ver tudo.`
  );
const alternarArea = (user, key) => {
  const set = new Set(user.liberados || []);
  if (set.has(key)) set.delete(key);
  else set.add(key);
  salvarTriagem(user, {
    liberados: [...set],
    escondidos: user.escondidos || [],
  });
};
const areaLiberada = (user, key) => (user.liberados || []).includes(key);
// item de dentro de uma área liberada: aparece, a não ser que esteja escondido
const filhoVisivel = (user, key) => !(user.escondidos || []).includes(key);
const alternarFilho = (user, key) => {
  const set = new Set(user.escondidos || []);
  if (set.has(key)) set.delete(key);
  else set.add(key);
  salvarTriagem(user, {
    liberados: user.liberados || [],
    escondidos: [...set],
  });
};
const areasComFilhos = user =>
  areas.value.filter(a => a.filhos.length && areaLiberada(user, a.key));

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

// 🧭 o resumo vira UMA frase ("Edita 12 · Vê 8"), não três pílulas
const resumoTexto = sum => `Edita ${sum.edit || 0} · Vê ${sum.view || 0}`;
const pessoasTexto = n => {
  if (n === 0) return 'ninguém ainda';
  return n === 1 ? '1 pessoa' : `${n} pessoas`;
};
const unidadesTexto = units =>
  !(units || []).length
    ? 'Todas as unidades'
    : units.map(unitLabel).join(' · ');

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
    'Papel salvo. Quem usa esse papel já tem os acessos novos.'
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
    `Acessos de ${firstName(form.name)} salvos.`
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
</script>

<template>
  <div class="cv-page cv-overlay cvg-page cv-acessos" :style="cvVars">
    <CvCabecalho
      :pal="pal"
      title="Acessos e papéis"
      subtitle="Quem vê e quem edita o quê. Marcar uma área vale para tudo dentro dela: os filhos herdam do pai."
      icon="i-lucide-shield-check"
    >
      <template #acoes>
        <button
          class="cvg-btn cvg-btn--principal"
          type="button"
          @click="openNewRole"
        >
          <span class="i-lucide-plus text-base" /> Novo papel
        </button>
      </template>
    </CvCabecalho>

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ 🧭 0. O QUE CADA ADMINISTRADOR VÊ (só o dono da conta) ══ -->
      <CvBloco
        v-if="souDono && adminsDaTriagem.length"
        titulo="O que cada administrador vê"
        subtitulo="Você é o dono da conta. Deixe outro administrador só com o essencial e vá liberando aos poucos: clique numa área para mostrar ou esconder."
        tom="dia"
        icon="i-lucide-eye"
      >
        <div class="cvg-lista">
          <div
            v-for="user in adminsDaTriagem"
            :key="`tri-${user.user_id}`"
            class="cv-triagem-linha"
          >
            <div class="flex items-center gap-2 flex-wrap">
              <b>{{ user.name }}</b>
              <span v-if="user.liberados" class="cvg-chip cvg-chip--apoio">
                <span class="i-lucide-eye-off text-xs" />
                {{ TRIAGEM_TXT.limitado }}
              </span>
              <span v-else class="cvg-chip">
                <span class="i-lucide-eye text-xs" /> {{ TRIAGEM_TXT.tudo }}
              </span>
              <span class="flex-1" />
              <button
                v-if="user.liberados"
                type="button"
                class="cvg-btn cvg-btn--sm"
                :disabled="isSaving"
                @click="liberarTudo(user)"
              >
                <span class="i-lucide-unlock text-sm" />
                {{ TRIAGEM_TXT.liberarTudo }}
              </button>
              <button
                v-else
                type="button"
                class="cvg-btn cvg-btn--principal cvg-btn--sm"
                :disabled="isSaving"
                @click="ligarTriagem(user)"
              >
                <span class="i-lucide-filter text-sm" />
                {{ TRIAGEM_TXT.essencial }}
              </button>
            </div>
            <div v-if="user.liberados" class="cv-triagem-areas">
              <button
                v-for="area in areas"
                :key="`tri-${user.user_id}-${area.key}`"
                type="button"
                class="cv-triagem-area"
                :class="
                  areaLiberada(user, area.key) ? 'cv-triagem-area--on' : ''
                "
                :aria-pressed="areaLiberada(user, area.key) ? 'true' : 'false'"
                :disabled="isSaving"
                :title="
                  areaLiberada(user, area.key)
                    ? TRIAGEM_TXT.dicaAparece
                    : TRIAGEM_TXT.dicaEscondido
                "
                @click="alternarArea(user, area.key)"
              >
                <span
                  :class="
                    areaLiberada(user, area.key)
                      ? 'i-lucide-check'
                      : 'i-lucide-plus'
                  "
                  class="text-xs"
                />
                {{ area.label }}
              </button>
            </div>
            <div
              v-for="area in areasComFilhos(user)"
              :key="`trif-${user.user_id}-${area.key}`"
              class="cv-triagem-dentro"
            >
              <span class="cv-triagem-dentro-titulo">
                {{ TRIAGEM_TXT.dentroDe }} {{ area.label }}
              </span>
              <button
                v-for="filho in area.filhos"
                :key="`trif-${user.user_id}-${filho.key}`"
                type="button"
                class="cv-triagem-area cv-triagem-area--sub"
                :class="
                  filhoVisivel(user, filho.key) ? 'cv-triagem-area--on' : ''
                "
                :aria-pressed="filhoVisivel(user, filho.key) ? 'true' : 'false'"
                :disabled="isSaving"
                @click="alternarFilho(user, filho.key)"
              >
                <span
                  :class="
                    filhoVisivel(user, filho.key)
                      ? 'i-lucide-check'
                      : 'i-lucide-plus'
                  "
                  class="text-xs"
                />
                {{ filho.label }}
              </button>
            </div>
          </div>
        </div>
      </CvBloco>

      <!-- ══ 1. PAPÉIS (60%: a cor do dia) ══ -->
      <CvBloco
        titulo="Papéis"
        subtitulo="Um papel é um conjunto de acessos com nome: Recepção, Vendedor da loja, Médico. A pessoa recebe o papel e, se precisar, uma marcação própria por cima."
        tom="dia"
        icon="i-lucide-id-card"
      >
        <template #acoes>
          <span class="cvg-chip cvg-chip--dia">
            {{ roles.length }} {{ roles.length === 1 ? 'papel' : 'papéis' }}
          </span>
        </template>

        <p v-if="!roles.length" class="cvg-vazio">
          Nenhum papel ainda. Crie o primeiro ou deixe as pessoas no padrão do
          sistema e ajuste cada uma em “Abrir árvore”.
        </p>
        <div v-else class="cvg-cards">
          <div v-for="role in roles" :key="role.id" class="cvg-card">
            <div class="min-w-0">
              <h3 class="cvg-card-titulo">{{ role.name }}</h3>
              <p v-if="role.hint" class="cvg-corpo cvg-texto-2">
                {{ role.hint }}
              </p>
            </div>
            <p class="cvg-comparacao cvg-texto-2">
              {{ resumoTexto(roleSummary(role)) }} ·
              <span
                :title="
                  peopleOfRole(role.id)
                    .map(u => u.name)
                    .join(', ')
                "
              >
                {{ pessoasTexto(peopleOfRole(role.id).length) }}
              </span>
            </p>
            <p v-if="companyUnits.length" class="cvg-legenda">
              <span class="i-lucide-store text-xs" />
              {{ unidadesTexto(role.units) }}
            </p>
            <div class="cvg-card-pe">
              <button
                class="cvg-btn cvg-btn--sm"
                type="button"
                @click="openEditRole(role)"
              >
                Editar
              </button>
              <button
                class="cvg-btn cvg-btn--ghost cvg-btn--sm"
                type="button"
                @click="duplicateRole(role)"
              >
                Duplicar
              </button>
              <button
                class="cvg-btn cvg-btn--ghost cvg-btn--sm cvg-btn--problema ml-auto"
                type="button"
                @click="roleToDelete = role"
              >
                Apagar
              </button>
            </div>
          </div>
        </div>
      </CvBloco>

      <!-- ══ 2. PESSOAS (30%: o apoio) ══ -->
      <CvBloco
        titulo="Pessoas"
        subtitulo="Cada login com o seu papel e, se precisar, a marcação própria por cima. Administradores têm tudo."
        tom="apoio"
        icon="i-lucide-users"
      >
        <template #acoes>
          <label class="cvg-busca">
            <span class="i-lucide-search text-base" />
            <input
              v-model="personSearch"
              type="search"
              class="cvg-campo cvg-campo--sm"
              placeholder="Buscar pessoa"
              aria-label="Buscar pessoa"
            />
          </label>
          <div class="cvg-chave" role="group" aria-label="Visualização">
            <button
              type="button"
              :aria-pressed="peopleView === 'lista' ? 'true' : 'false'"
              @click="setPeopleView('lista')"
            >
              <span class="i-lucide-list text-sm" /> Lista
            </button>
            <button
              type="button"
              :aria-pressed="peopleView === 'cards' ? 'true' : 'false'"
              @click="setPeopleView('cards')"
            >
              <span class="i-lucide-layout-grid text-sm" /> Cards
            </button>
          </div>
        </template>

        <!-- LISTA -->
        <div v-if="peopleView === 'lista'" class="cvg-lista">
          <div
            v-for="user in filteredUsers"
            :key="user.user_id"
            class="cvg-linha cv-acessos-row"
          >
            <div class="cvg-linha-quem">
              <span class="flex items-center gap-2 flex-wrap">
                <b>{{ user.name }}</b>
                <span v-if="user.admin" class="cvg-chip cvg-chip--dia">
                  <span class="i-lucide-crown text-xs" /> administrador(a)
                </span>
                <span
                  v-else-if="hasOwnMarks(user)"
                  class="cvg-chip cvg-chip--apoio"
                  title="tem marcação própria por cima do papel"
                >
                  <span class="i-lucide-pen-line text-xs" /> marcação própria
                </span>
                <span
                  v-if="user.legacy"
                  class="cvg-chip"
                  title="ainda usa as concessões do modelo antigo, convertidas na hora; salvar a árvore passa para o modelo novo"
                >
                  <span class="i-lucide-history text-xs" /> modelo antigo
                </span>
              </span>
              <span class="cvg-legenda truncate">
                {{ user.email
                }}<template v-if="companyUnits.length">
                  ·
                  {{
                    user.admin ? 'Todas as unidades' : unidadesTexto(user.units)
                  }}
                </template>
              </span>
            </div>
            <div>
              <span v-if="user.admin" class="cvg-corpo cvg-texto-3">
                tudo liberado
              </span>
              <select
                v-else
                class="cvg-campo cvg-campo--sm"
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
            <span class="cvg-comparacao cvg-texto-2 whitespace-nowrap">
              {{ resumoTexto(personSummary(user)) }}
            </span>
            <div class="text-right">
              <button
                v-if="!user.admin"
                class="cvg-btn cvg-btn--ghost cvg-btn--sm"
                type="button"
                @click="openPerson(user)"
              >
                Abrir árvore ›
              </button>
            </div>
          </div>
          <p v-if="!filteredUsers.length" class="cvg-vazio">
            Ninguém com “{{ personSearch }}”.
          </p>
        </div>

        <!-- CARDS -->
        <div v-else class="cvg-cards">
          <div
            v-for="user in filteredUsers"
            :key="user.user_id"
            class="cvg-card"
          >
            <div class="min-w-0">
              <h3 class="cvg-card-titulo">{{ user.name }}</h3>
              <p class="cvg-legenda truncate">{{ user.email }}</p>
            </div>
            <div class="flex flex-wrap gap-2">
              <span v-if="user.admin" class="cvg-chip cvg-chip--dia">
                <span class="i-lucide-crown text-xs" /> administrador(a)
              </span>
              <span
                v-else-if="hasOwnMarks(user)"
                class="cvg-chip cvg-chip--apoio"
                title="tem marcação própria por cima do papel"
              >
                <span class="i-lucide-pen-line text-xs" /> marcação própria
              </span>
              <span
                v-if="user.legacy"
                class="cvg-chip"
                title="convertido do modelo antigo"
              >
                <span class="i-lucide-history text-xs" /> modelo antigo
              </span>
            </div>
            <p class="cvg-comparacao cvg-texto-2">
              {{ resumoTexto(personSummary(user)) }}
            </p>
            <label v-if="!user.admin" class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Papel</span>
              <select
                class="cvg-campo cvg-campo--sm"
                :value="user.role_id || ''"
                :disabled="isSaving"
                @change="changeRole(user, $event.target.value)"
              >
                <option value="">sem papel (padrão)</option>
                <option v-for="role in roles" :key="role.id" :value="role.id">
                  {{ role.name }}
                </option>
              </select>
            </label>
            <p v-if="companyUnits.length" class="cvg-legenda">
              <span class="i-lucide-store text-xs" />
              {{ user.admin ? 'Todas as unidades' : unidadesTexto(user.units) }}
            </p>
            <div class="cvg-card-pe">
              <button
                v-if="!user.admin"
                class="cvg-btn cvg-btn--sm"
                type="button"
                @click="openPerson(user)"
              >
                Abrir árvore ›
              </button>
            </div>
          </div>
          <p v-if="!filteredUsers.length" class="cvg-vazio col-span-full">
            Ninguém com “{{ personSearch }}”.
          </p>
        </div>
      </CvBloco>

      <!-- ══ 3. MAPA DO SISTEMA (neutro) ══ -->
      <CvBloco
        titulo="Mapa do sistema"
        subtitulo="Tudo o que existe, em árvore, com o nível que um atendente sem configuração tem em cada tela. Só leitura, para entender o que dá para liberar."
        icon="i-lucide-map"
      >
        <AccessTreeEditor
          :catalog="catalog"
          :model-value="{}"
          readonly
          start-expanded
        />
      </CvBloco>
    </template>

    <!-- ══ modal: papel (novo / editar / duplicar) ══ -->
    <div
      v-if="roleForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-2 sm:p-4"
      @click.self="roleForm = null"
    >
      <div class="cv-modal w-full max-w-3xl flex flex-col max-h-[94vh]">
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-id-card text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-xs opacity-85">Papéis</p>
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
        <div class="p-4 sm:p-6 overflow-y-auto flex flex-col gap-5">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Nome</span>
              <input
                v-model="roleForm.name"
                class="cvg-campo"
                maxlength="60"
                placeholder="Recepção"
              />
            </label>
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Dica (opcional)</span>
              <input
                v-model="roleForm.hint"
                class="cvg-campo"
                maxlength="200"
                placeholder="agenda, confirmação e conversas"
              />
            </label>
          </div>
          <div v-if="companyUnits.length" class="cvg-campo-rotulo">
            <span class="cvg-rotulo">Unidades (nenhuma marcada = todas)</span>
            <div class="flex flex-wrap gap-2">
              <label
                v-for="u in companyUnits"
                :key="u.key"
                class="cvg-chip cvg-chip--marcavel"
              >
                <input
                  type="checkbox"
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
            class="cvg-btn cvg-btn--principal"
            type="button"
            :disabled="isSaving"
            @click="saveRole"
          >
            {{ isSaving ? 'Salvando…' : 'Salvar papel' }}
          </button>
          <button
            class="cvg-btn cvg-btn--ghost"
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
      <div class="cv-modal w-full max-w-md flex flex-col">
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-trash-2 text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-xs opacity-85">Papéis</p>
            <h2 class="text-base font-bold leading-tight">
              Apagar “{{ roleToDelete.name }}”?
            </h2>
          </div>
        </div>
        <div class="p-6 cvg-corpo">
          <p>
            <b>{{ peopleOfRole(roleToDelete.id).length }}</b>
            {{
              peopleOfRole(roleToDelete.id).length === 1
                ? 'pessoa usa'
                : 'pessoas usam'
            }}
            este papel. Quem usa volta ao padrão do sistema; a marcação própria
            de cada um continua valendo.
          </p>
        </div>
        <div class="cv-modal-foot flex items-center gap-2">
          <button
            class="cvg-btn cvg-btn--ghost cvg-btn--problema"
            type="button"
            :disabled="isSaving"
            @click="confirmDeleteRole"
          >
            {{ isSaving ? 'Apagando…' : 'Apagar papel' }}
          </button>
          <button
            class="cvg-btn cvg-btn--ghost"
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
      <div class="cv-modal w-full max-w-3xl flex flex-col max-h-[94vh]">
        <div class="cv-modal-head flex items-center gap-3">
          <span
            class="cv-glass w-10 h-10 flex items-center justify-center flex-shrink-0"
          >
            <span class="i-lucide-network text-base" />
          </span>
          <div class="flex-1 min-w-0">
            <p class="text-xs opacity-85">Acessos de</p>
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
        <div class="p-4 sm:p-6 overflow-y-auto flex flex-col gap-5">
          <p
            v-if="personForm.legacy"
            class="cvg-chip cvg-chip--atencao self-start"
          >
            <span class="i-lucide-history text-xs" /> ainda usa o modelo antigo;
            ao salvar, passa para a árvore nova
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <label class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Papel</span>
              <select v-model="personForm.roleId" class="cvg-campo">
                <option value="">sem papel (padrão do sistema)</option>
                <option v-for="role in roles" :key="role.id" :value="role.id">
                  {{ role.name }}
                </option>
              </select>
            </label>
            <div v-if="companyUnits.length" class="cvg-campo-rotulo">
              <span class="cvg-rotulo">Unidades (nenhuma = todas)</span>
              <div class="flex flex-wrap gap-2">
                <label
                  v-for="u in companyUnits"
                  :key="u.key"
                  class="cvg-chip cvg-chip--marcavel"
                >
                  <input
                    type="checkbox"
                    :checked="personForm.units.includes(u.key)"
                    @change="toggleUnit(personForm.units, u.key)"
                  />
                  {{ u.label }}
                </label>
              </div>
            </div>
          </div>
          <div v-if="roles.length" class="flex items-center gap-2 flex-wrap">
            <span class="cvg-rotulo">Perfis rápidos</span>
            <button
              v-for="role in roles"
              :key="role.id"
              type="button"
              class="cvg-chip cvg-chip--marcavel"
              :title="`copia a árvore de “${role.name}” como marcação própria (dá para ajustar depois)`"
              @click="applyRoleAsOwn(role)"
            >
              <span class="i-lucide-wand-sparkles text-xs" />
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
            class="cvg-btn cvg-btn--principal"
            type="button"
            :disabled="isSaving"
            @click="savePersonForm"
          >
            {{ isSaving ? 'Salvando…' : 'Salvar acessos' }}
          </button>
          <button
            class="cvg-btn cvg-btn--ghost"
            type="button"
            :disabled="isSaving"
            title="apaga a marcação própria; o papel continua"
            @click="resetPersonForm"
          >
            <span class="i-lucide-rotate-ccw text-sm" /> Voltar ao padrão
          </button>
          <button
            class="cvg-btn cvg-btn--ghost ml-auto"
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
/* 🧭 11/11: o que cada administrador vê — linha da pessoa + áreas de clicar (retas, sem cor cheia) */
.cv-page .cv-triagem-linha {
  padding: 14px 4px;
  border-bottom: 1px solid var(--g-linha, rgb(127 127 127 / 0.18));
}
.cv-page .cv-triagem-linha:last-child {
  border-bottom: 0;
}
.cv-page .cv-triagem-areas {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 12px;
}
.cv-page .cv-triagem-area {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  padding: 0 12px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  border: 1px dashed rgb(127 127 127 / 0.45);
  color: inherit;
  opacity: 0.6;
  background: transparent;
  transition:
    opacity 0.15s,
    background 0.15s,
    border-color 0.15s;
}
.cv-page .cv-triagem-area:hover {
  opacity: 0.9;
}
.cv-page .cv-triagem-area--on {
  opacity: 1;
  border: 1px solid rgb(var(--cv-rgb) / 0.55);
  background: rgb(var(--cv-rgb) / 0.14);
}
.cv-page .cv-triagem-area:disabled {
  cursor: progress;
}
.cv-page .cv-triagem-dentro {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
  margin-top: 10px;
  padding-left: 12px;
  border-left: 2px solid rgb(var(--cv-rgb) / 0.35);
}
.cv-page .cv-triagem-dentro-titulo {
  font-size: 12px;
  font-weight: 700;
  opacity: 0.7;
  margin-right: 4px;
}
.cv-page .cv-triagem-area--sub {
  height: 28px;
  padding: 0 10px;
  font-size: 12px;
  border-radius: 8px;
}
/* 🔐 Acessos e papéis — linha da lista de pessoas (guia arejado):
   quem · papel · resumo · ação */
.cv-page .cv-acessos-row {
  grid-template-columns: minmax(220px, 1.6fr) minmax(180px, 1fr) auto auto;
}
.cv-page .cv-acessos-row select.cvg-campo {
  max-width: 240px;
}
@media (max-width: 1000px) {
  .cv-page .cv-acessos-row {
    grid-template-columns: 1fr auto;
  }
  .cv-page .cv-acessos-row .cvg-linha-quem {
    grid-column: 1 / -1;
  }
}
@media (max-width: 640px) {
  .cv-page .cv-acessos-row {
    grid-template-columns: 1fr;
  }
  .cv-page .cv-acessos-row .text-right {
    text-align: left;
  }
}
</style>
