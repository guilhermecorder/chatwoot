<script setup>
// 🔔 ITEM 346 (16/10): NOTIFICAÇÕES SOBRE AGENDAMENTOS. Pedido dele: "criar
// um ambiente de notificações sobre agendamentos, e colocar lá todos os
// agendamentos com divergência de dados, para conferência e ajuste manual".
// Nada é corrigido sozinho: cada alerta traz os botões do caso dele.
// Admin vê tudo; o atendente vê os seus (responsável pelo card ou consulta).
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { frontendURL } from 'dashboard/helper/URLHelper';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import PatientSuggest from 'dashboard/components-next/cevico/PatientSuggest.vue';

const route = useRoute();
const router = useRouter();
const { canEdit } = useCevicoAccess();
const editable = computed(() => canEdit('agenda.notificacoes'));

const pal = useCevicoPalette({
  scope: 'crm:notificacoes',
  blocks: [
    { id: 'resumo', label: 'Resumo', icon: 'i-lucide-gauge' },
    { id: 'lista', label: 'Para conferir', icon: 'i-lucide-list-checks' },
  ],
});
const pageStyle = computed(() => pal.cvVars.value);

const items = ref([]);
const isLoading = ref(true);
const loadError = ref('');
const busyKey = ref('');
const filter = ref('todos');
const view = ref('cards');

// 4 grupos do resumo (o que cada um quer dizer, por extenso)
const GROUPS = [
  {
    key: 'duplicado',
    label: 'Possível duplicado',
    hint: 'mesmo celular (com ou sem 9), mesmo CPF ou mesmo nome completo',
    icon: 'i-lucide-copy',
    color: '#D97706',
    kinds: ['possivel_duplicado', 'cpf_diferente'],
  },
  {
    key: 'nome',
    label: 'Nome que não bate',
    hint: 'outro nome no mesmo celular ou duas pessoas no mesmo cadastro',
    icon: 'i-lucide-users-round',
    color: '#7C3AED',
    kinds: ['nome_diferente', 'duas_pessoas'],
  },
  {
    key: 'outro',
    label: 'Consulta no cadastro de outra pessoa',
    hint: 'o nome da consulta não é o do paciente ligado a ela',
    icon: 'i-lucide-calendar-x',
    color: '#DC2626',
    kinds: ['consulta_outro_nome'],
  },
  {
    key: 'sem',
    label: 'Consulta sem cadastro',
    hint: 'consulta que não está ligada a nenhum paciente',
    icon: 'i-lucide-user-round-x',
    color: '#0F5FA6',
    kinds: ['consulta_sem_cadastro'],
  },
];
const groupOf = item => GROUPS.find(g => g.kinds.includes(item.kind));
const counts = computed(() =>
  Object.fromEntries(
    GROUPS.map(g => [
      g.key,
      items.value.filter(i => g.kinds.includes(i.kind)).length,
    ])
  )
);
const shown = computed(() => {
  if (filter.value === 'todos') return items.value;
  const group = GROUPS.find(g => g.key === filter.value);
  return items.value.filter(i => group.kinds.includes(i.kind));
});

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.getAppointmentAlerts();
    items.value = data?.payload || [];
  } catch (e) {
    loadError.value = 'Não consegui carregar as notificações. Tente de novo.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const run = async (item, action, payload, okText) => {
  busyKey.value = item.key;
  try {
    await CrmAPI.appointmentAlertAction(action, payload);
    useAlert(okText);
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não deu certo. Tente de novo.');
  } finally {
    busyKey.value = '';
  }
};

const openPatient = id =>
  router.push(frontendURL(`accounts/${route.params.accountId}/patient/${id}`));

// ── ações de cada caso ─────────────────────────────────────────────────
const merge = (item, keep, drop) => {
  // eslint-disable-next-line no-alert
  const ok = window.confirm(
    `Juntar os dois cadastros?\n\nFica: ${keep.name} (${keep.phone_number || 'sem telefone'})\nSai: ${drop.name} (${drop.phone_number || 'sem telefone'})\n\nConsultas, card e conversas do que sai passam para o que fica. Não dá para desfazer.`
  );
  if (!ok) return;
  run(
    item,
    'merge',
    { keep_id: keep.id, drop_id: drop.id },
    'Cadastros juntados ✓'
  );
};
const notSame = item =>
  run(
    item,
    'not_same',
    { one_id: item.contact.id, other_id: item.other.id },
    'Marcado: são pessoas diferentes ✓'
  );
const reviewed = item =>
  run(
    item,
    'reviewed',
    item.task
      ? { task_id: item.task.id }
      : {
          contact_id: item.contact.id,
          type: item.kind,
          other_id: item.other?.id,
        },
    'Conferido ✓'
  );

// corrigir o nome (duas pessoas no cadastro): sugere a 1ª pessoa do nome
const renameDraft = ref({});
const firstPerson = name =>
  String(name || '')
    .split(/\s+e\s+/i)[0]
    .trim();
const draftFor = item => {
  if (renameDraft.value[item.key] === undefined)
    renameDraft.value[item.key] = firstPerson(item.contact.name);
  return renameDraft.value[item.key];
};
const rename = item =>
  run(
    item,
    'rename',
    { contact_id: item.contact.id, name: renameDraft.value[item.key] },
    'Nome corrigido ✓'
  );

// mover a consulta: para alguém do cadastro (busca) ou paciente novo
const moveOpen = ref('');
const moveQuery = ref({});
const moveFocus = ref('');
// setas/Enter/Esc na busca do paciente certo (uma lista por cartão)
const moveSuggestRefs = {};
const onMoveKey = (item, e) => {
  if (e.key === 'Escape') {
    moveFocus.value = '';
    return;
  }
  moveSuggestRefs[item.key]?.onKey(e);
};
const newPatient = ref({});
const openMove = item => {
  moveOpen.value = moveOpen.value === item.key ? '' : item.key;
  moveQuery.value[item.key] = item.task?.patient || '';
  newPatient.value[item.key] = {
    name: item.task?.patient || '',
    phone: '',
  };
};
const moveTo = (item, patient) =>
  run(
    item,
    'move_task',
    { task_id: item.task.id, contact_id: patient.id },
    `Consulta movida para ${patient.name} ✓`
  );
const moveToNew = item => {
  const p = newPatient.value[item.key] || {};
  run(
    item,
    'move_task',
    { task_id: item.task.id, name: p.name, phone: p.phone },
    `Consulta movida para ${p.name} ✓`
  );
};

const fmtWhen = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  return `${d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`;
};
const personLine = p =>
  [
    p.phone_number || 'sem telefone',
    p.stage,
    p.conversations ? `${p.conversations} conversa(s)` : 'sem conversa',
    p.origin === 'oftalmofacil' ? 'veio do OftalmoFácil' : null,
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Notificações sobre agendamentos"
        subtitle="Cadastros e consultas com dados que não batem. Nada é corrigido sozinho: confira cada caso e ajuste aqui mesmo."
        icon="i-lucide-bell-ring"
        :palette="false"
      >
        <template #chips>
          <span class="cv-glass-chip">
            <span class="i-lucide-bell text-xs" />
            {{ items.length }} para conferir
          </span>
        </template>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading && !items.length" variant="dashboard" />

      <template v-else>
        <div
          v-if="loadError"
          class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3"
        >
          <p class="text-xs text-n-slate-11 flex-1">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="load">Tentar de novo</button>
        </div>

        <!-- bloco 1 · resumo -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <h2 class="cv-ag-block-title">Resumo</h2>
          <span class="cv-ag-block-sub text-xs text-n-slate-11">
            clique num cartão para ver só aquele tipo
          </span>
          <div
            class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 mt-4"
          >
            <button
              v-for="g in GROUPS"
              :key="g.key"
              class="cv-sub cv-sub-hover p-4 text-left flex flex-col gap-1.5 transition-all"
              :class="filter === g.key ? 'ring-2' : ''"
              :style="{ '--tw-ring-color': g.color }"
              @click="filter = filter === g.key ? 'todos' : g.key"
            >
              <span class="flex items-center gap-2">
                <span
                  class="w-8 h-8 rounded-xl grid place-items-center text-white"
                  :style="{ background: g.color }"
                >
                  <span :class="g.icon" class="text-sm" />
                </span>
                <span class="text-3xl font-extrabold text-n-slate-12">
                  {{ counts[g.key] }}
                </span>
              </span>
              <span class="font-semibold text-[13px] text-n-slate-12">
                {{ g.label }}
              </span>
              <span class="text-[11px] text-n-slate-10 leading-snug">
                {{ g.hint }}
              </span>
            </button>
          </div>
        </section>

        <!-- bloco 2 · para conferir -->
        <section class="cv-ag-block p-5 sm:p-7 mb-8">
          <div class="flex items-center gap-3 flex-wrap mb-4">
            <div>
              <h2 class="cv-ag-block-title">Para conferir</h2>
              <span class="text-xs text-n-slate-11">
                {{ shown.length }} caso(s){{
                  filter === 'todos'
                    ? ''
                    : ` · ${GROUPS.find(g => g.key === filter).label}`
                }}
              </span>
            </div>
            <button
              v-if="filter !== 'todos'"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              @click="filter = 'todos'"
            >
              <span class="i-lucide-x text-xs" /> ver todos
            </button>
            <div class="cv-seg ml-auto">
              <button
                class="cv-seg-item"
                :class="view === 'list' ? 'cv-seg-on' : ''"
                @click="view = 'list'"
              >
                <span class="i-lucide-list text-sm" /> Lista
              </button>
              <button
                class="cv-seg-item"
                :class="view === 'cards' ? 'cv-seg-on' : ''"
                @click="view = 'cards'"
              >
                <span class="i-lucide-layout-grid text-sm" /> Cards
              </button>
            </div>
          </div>

          <div
            v-if="!shown.length"
            class="cv-sub p-8 text-center text-n-slate-10"
          >
            <span class="i-lucide-badge-check text-3xl block mx-auto mb-2" />
            <p class="text-sm">Nada para conferir aqui. Tudo batendo ✓</p>
          </div>

          <div
            v-else
            :class="
              view === 'cards'
                ? 'grid grid-cols-1 lg:grid-cols-2 gap-4'
                : 'flex flex-col gap-2'
            "
          >
            <article
              v-for="item in shown"
              :key="item.key"
              class="cv-sub p-4 flex flex-col gap-3 border-l-4"
              :class="
                busyKey === item.key ? 'opacity-50 pointer-events-none' : ''
              "
              :style="{ borderLeftColor: groupOf(item)?.color }"
            >
              <!-- o que é -->
              <header class="flex items-start gap-2.5">
                <span
                  class="w-7 h-7 rounded-lg grid place-items-center text-white flex-shrink-0"
                  :style="{ background: groupOf(item)?.color }"
                >
                  <span :class="groupOf(item)?.icon" class="text-xs" />
                </span>
                <div class="min-w-0 flex-1">
                  <p class="font-bold text-[14px] text-n-slate-12">
                    {{ item.title }}
                  </p>
                  <p class="text-[12px] text-n-slate-11 mt-0.5">
                    {{ item.detail }}
                  </p>
                </div>
                <span
                  v-if="item.task?.due_at"
                  class="text-[11px] font-semibold text-n-slate-11 whitespace-nowrap"
                >
                  {{ fmtWhen(item.task.due_at) }}
                </span>
              </header>

              <!-- quem -->
              <div
                v-if="view === 'cards' || item.other"
                class="grid gap-2"
                :class="item.other ? 'sm:grid-cols-2' : ''"
              >
                <div
                  v-for="p in [item.contact, item.other].filter(Boolean)"
                  :key="p.id"
                  class="rounded-xl bg-n-alpha-1 p-3 flex flex-col gap-1.5"
                >
                  <button
                    class="text-left font-semibold text-[13px] text-n-slate-12 hover:underline"
                    title="Abrir o Espaço do Paciente"
                    @click="openPatient(p.id)"
                  >
                    {{ p.name || 'Sem nome' }}
                    <span class="i-lucide-arrow-up-right text-xs" />
                  </button>
                  <span class="text-[11px] text-n-slate-11">
                    {{ personLine(p) }}
                  </span>
                  <button
                    v-if="editable && item.other && item.group === 'cadastro'"
                    class="cv-btn cv-btn-sm w-fit"
                    @click="
                      merge(
                        item,
                        p,
                        p.id === item.contact.id ? item.other : item.contact
                      )
                    "
                  >
                    <span class="i-lucide-merge text-xs" /> Juntar · fica este
                  </button>
                </div>
              </div>
              <p
                v-if="item.next_appointment"
                class="text-[11px] text-n-slate-10"
              >
                Próximo agendamento: {{ item.next_appointment.title }} ·
                {{ fmtWhen(item.next_appointment.due_at) }}
              </p>

              <!-- duas pessoas: corrigir o nome -->
              <div
                v-if="editable && item.kind === 'duas_pessoas'"
                class="flex items-center gap-2 flex-wrap"
              >
                <input
                  :value="draftFor(item)"
                  class="cv-input flex-1 min-w-[12rem] !h-8 text-xs"
                  placeholder="Nome certo deste cadastro"
                  @input="renameDraft[item.key] = $event.target.value"
                />
                <button class="cv-btn cv-btn-sm" @click="rename(item)">
                  Corrigir o nome
                </button>
              </div>
              <p
                v-if="item.kind === 'duas_pessoas'"
                class="text-[11px] text-n-slate-10"
              >
                Dica: a consulta da outra pessoa aparece abaixo como "Consulta
                com o nome de outra pessoa" — mova para o cadastro dela.
              </p>

              <!-- consulta: mover para o paciente certo -->
              <div v-if="editable && item.task && moveOpen === item.key">
                <div class="relative">
                  <span class="cv-label block mb-1">
                    Mover para alguém do cadastro
                  </span>
                  <input
                    v-model="moveQuery[item.key]"
                    class="cv-input w-full !h-8 text-xs"
                    placeholder="Nome ou telefone do paciente certo…"
                    autocomplete="off"
                    @focus="moveFocus = item.key"
                    @blur="moveFocus = ''"
                    @keydown="onMoveKey(item, $event)"
                  />
                  <PatientSuggest
                    :ref="el => (moveSuggestRefs[item.key] = el)"
                    :query="moveQuery[item.key] || ''"
                    :active="moveFocus === item.key"
                    :exclude-id="item.contact?.id"
                    action="pick"
                    @pick="p => moveTo(item, p)"
                  />
                </div>
                <span class="cv-label block mt-3 mb-1">
                  …ou criar o paciente (nome + telefone)
                </span>
                <div class="flex items-center gap-2 flex-wrap">
                  <input
                    v-model="newPatient[item.key].name"
                    class="cv-input flex-1 min-w-[10rem] !h-8 text-xs"
                    placeholder="Nome completo"
                  />
                  <input
                    v-model="newPatient[item.key].phone"
                    class="cv-input w-40 !h-8 text-xs"
                    placeholder="(11) 98888-7777"
                  />
                  <button
                    class="cv-btn cv-btn-sm"
                    :disabled="!newPatient[item.key].name"
                    @click="moveToNew(item)"
                  >
                    Criar e mover
                  </button>
                </div>
              </div>

              <!-- botões -->
              <footer class="flex items-center gap-2 flex-wrap">
                <button
                  v-if="editable && item.task"
                  class="cv-btn cv-btn-sm"
                  @click="openMove(item)"
                >
                  <span class="i-lucide-arrow-right-left text-xs" />
                  {{
                    item.kind === 'consulta_sem_cadastro'
                      ? 'Ligar a um paciente'
                      : 'Mover a consulta'
                  }}
                </button>
                <button
                  v-if="editable && item.other"
                  class="cv-btn cv-btn-ghost cv-btn-sm"
                  @click="notSame(item)"
                >
                  <span class="i-lucide-users-round text-xs" /> São pessoas
                  diferentes
                </button>
                <button
                  v-if="item.contact && view === 'list' && !item.other"
                  class="cv-btn cv-btn-ghost cv-btn-sm"
                  @click="openPatient(item.contact.id)"
                >
                  <span class="i-lucide-user-round text-xs" /> Abrir paciente
                </button>
                <button
                  v-if="editable"
                  class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
                  title="Está certo assim: tira da lista sem mudar nada"
                  @click="reviewed(item)"
                >
                  <span class="i-lucide-check text-xs" /> Conferido
                </button>
              </footer>
            </article>
          </div>
        </section>
      </template>
    </div>
  </div>
</template>
