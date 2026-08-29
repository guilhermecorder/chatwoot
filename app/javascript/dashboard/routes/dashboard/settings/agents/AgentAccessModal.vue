<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  agent: { type: Object, required: true },
});

const emit = defineEmits(['close']);

const store = useStore();

// ── Menu do dia a dia (só visual — o admin liga/desliga por pessoa) ──
const DAY_ITEMS = [
  { key: 'crm',          label: 'CRM (funil de leads)' },
  { key: 'conversation', label: 'Conversas' },
  { key: 'agenda',       label: 'Agenda' },
  { key: 'goals',        label: 'Metas (acompanhar o mês)' },
  { key: 'canned',       label: 'Respostas prontas' },
  { key: 'tasks',        label: 'Tarefas' },
  { key: 'people',       label: 'Pessoas (DISC e desenvolvimento)' },
  { key: 'academy',      label: 'Academia CEVICO' },
];
// padrão combinado 17/07: Meu Painel | CRM | Conversas | Agenda | Metas |
// Respostas prontas (Meu Painel e Conteúdos aparecem sempre)
const DAY_DEFAULT = ['crm', 'conversation', 'agenda', 'goals', 'canned'];

// ── Áreas administrativas (CONCESSÃO — vale de verdade, na API também) ──
const GRANT_ITEMS = [
  { key: 'reports',    label: 'Relatórios',            hint: 'dashboards CEVICO (CRM, Médicos, Agentes, Agenda, Anúncios…)' },
  { key: 'campaigns',  label: 'Campanha WhatsApp',     hint: 'mensagens em massa e o painel de resultados' },
  { key: 'automations', label: 'Automações',           hint: 'robôs de follow-up e resultados das automações' },
  { key: 'data_tools', label: 'Tratamento de dados',   hint: 'etiquetas retroativas, mover em lote, unificar contatos' },
  { key: 'settings',   label: 'Integrações & config.', hint: 'integrações do CRM e configurações sensíveis' },
  { key: 'finance',    label: 'Financeiro',            hint: 'livro caixa da clínica — receitas, custos, margem' },
  { key: 'strategy',   label: 'Estratégia',            hint: 'painel estratégico por pilares' },
  { key: 'pages',      label: 'Análise de Páginas',    hint: 'análise de funis e testes A/B (rascunhos já são do time)' },
  { key: 'health',     label: 'Saúde (HUB)',           hint: 'mundo pessoal de treino/dieta/corpo — cada pessoa vê só os próprios registros' },
];

// ── Perfis rápidos (preenchem os checkboxes; dá para ajustar depois) ──
const PRESETS = [
  {
    key: 'standard',
    label: 'Atendimento (padrão)',
    hint: 'responde mensagens, agenda, acompanha metas',
    menu: [...DAY_DEFAULT],
    grants: [],
  },
  {
    key: 'agenda',
    label: 'Agenda & Conferência',
    hint: 'vive na agenda: conferência de consultas e cirurgias',
    menu: ['agenda', 'conversation', 'goals', 'canned', 'tasks'],
    grants: [],
  },
  {
    key: 'doctor',
    label: 'Médico(a)',
    hint: 'agenda própria, metas e dashboards',
    menu: ['agenda', 'goals'],
    grants: ['reports'],
  },
];

// ── Relatórios ESPECÍFICOS (item 62): a seção "Relatórios" abre e o
// admin escolhe QUAIS dashboards — lista vazia = todos os concedíveis ──
const REPORT_ITEMS = [
  { key: 'crm_dashboard', label: 'Dashboard CRM' },
  { key: 'campaigns_dashboard', label: 'Dashboard Campanhas' },
  { key: 'traffic_funnel', label: 'Funil de Tráfego' },
  { key: 'doctors', label: 'Dashboard dos Médicos' },
  { key: 'agents_dashboard', label: 'Dashboard dos Agentes' },
  { key: 'agenda_dashboard', label: 'Dashboard da Agenda' },
  { key: 'ads', label: 'Anúncios (Meta)' },
  { key: 'google', label: 'Google (Ads + GA4)' },
  { key: 'whatsapp_health', label: 'Saúde do WhatsApp' },
];

const isTargetAdmin = computed(() => props.agent.role === 'administrator');

const crmSettings = useMapGetter('crm/getSettings');

const dayMenu = ref([...DAY_DEFAULT]);
const grants = ref([]);
const reportKeys = ref([]); // [] = todos os relatórios
const isSaving = ref(false);

onMounted(async () => {
  if (!Object.keys(crmSettings.value.agent_permissions ?? {}).length) {
    await store.dispatch('crm/fetchSettings').catch(() => {});
  }
  const perms = crmSettings.value.agent_permissions ?? {};
  const uid = String(props.agent.id);
  grants.value = [...(perms.grants?.[uid] ?? [])];
  reportKeys.value = [...(perms.report_keys?.[uid] ?? [])];
  if (perms.menu?.[uid]) {
    dayMenu.value = [...perms.menu[uid]];
  } else {
    // legado (lista de bloqueio antiga): padrão menos o que era bloqueado
    const legacyBlocked = perms[uid] ?? [];
    dayMenu.value = DAY_DEFAULT.filter(key => !legacyBlocked.includes(key));
  }
});

const toggle = (list, key) => {
  const idx = list.indexOf(key);
  if (idx === -1) list.push(key);
  else list.splice(idx, 1);
};

// relatório marcado? (lista vazia = todos marcados)
const reportChecked = key =>
  reportKeys.value.length === 0 || reportKeys.value.includes(key);
const toggleReport = key => {
  if (reportKeys.value.length === 0) {
    // estava em "todos": materializa a lista completa sem este
    reportKeys.value = REPORT_ITEMS.map(r => r.key).filter(k => k !== key);
  } else {
    toggle(reportKeys.value, key);
    // marcou todos de volta → volta ao modo "todos" (lista vazia)
    if (reportKeys.value.length === REPORT_ITEMS.length) reportKeys.value = [];
  }
};
const selectAllReports = () => {
  reportKeys.value = []; // vazio = todos
};
// selecionar tudo (agilizar): menu completo + todas as áreas
const selectAllMenu = () => {
  dayMenu.value = DAY_ITEMS.map(i => i.key);
};
const selectAllGrants = () => {
  grants.value = GRANT_ITEMS.map(i => i.key);
};

const applyPreset = preset => {
  dayMenu.value = [...preset.menu];
  grants.value = [...preset.grants];
};

const activePreset = computed(() => {
  const same = (a, b) =>
    a.length === b.length && [...a].sort().join() === [...b].sort().join();
  return (
    PRESETS.find(
      p => same(p.menu, dayMenu.value) && same(p.grants, grants.value)
    )?.key ?? null
  );
});

const save = async () => {
  isSaving.value = true;
  try {
    await store.dispatch('crm/updateAgentGrants', {
      userId: props.agent.id,
      grants: grants.value,
      menu: dayMenu.value,
      reportKeys: grants.value.includes('reports') ? reportKeys.value : [],
    });
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
  <div class="flex flex-col max-h-[85vh]">
    <div class="px-8 pt-8 pb-4 flex-shrink-0">
      <h2 class="text-base font-semibold text-n-slate-12">
        Acessos de {{ agent.name }}
      </h2>
      <p v-if="isTargetAdmin" class="text-sm text-n-slate-10 mt-1">
        {{ agent.name.split(' ')[0] }} é <strong>administrador(a)</strong> e
        tem acesso a tudo — não há o que configurar aqui.
      </p>
      <p v-else class="text-sm text-n-slate-10 mt-1">
        Marque o que {{ agent.name.split(' ')[0] }} <strong>pode</strong> ver e
        acessar. Meu Painel e Conteúdos (rascunhos) aparecem para todo o time.
      </p>
    </div>

    <div v-if="!isTargetAdmin" class="px-8 overflow-y-auto space-y-5">
      <!-- perfis rápidos -->
      <div>
        <p class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10 mb-2">
          Perfis rápidos
        </p>
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="preset in PRESETS"
            :key="preset.key"
            class="px-3 py-1.5 rounded-full text-xs font-medium border transition-colors"
            :class="
              activePreset === preset.key
                ? 'bg-n-brand text-white border-n-brand'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
            "
            :title="preset.hint"
            @click="applyPreset(preset)"
          >
            {{ preset.label }}
          </button>
        </div>
      </div>

      <!-- menu do dia a dia -->
      <div class="bg-n-alpha-1 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center justify-between mb-1">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10">
            Menu do dia a dia
          </p>
          <button
            class="text-[11px] font-medium text-n-slate-10 hover:text-n-slate-12 border border-n-weak rounded-full px-2 py-0.5 transition-colors"
            @click="selectAllMenu"
          >
            marcar tudo
          </button>
        </div>
        <p class="text-xs text-n-slate-9 mb-2">
          o que aparece no menu lateral dela(e)
        </p>
        <div class="space-y-0.5">
          <label
            v-for="item in DAY_ITEMS"
            :key="item.key"
            class="flex items-center gap-3 px-3 py-1.5 rounded-lg hover:bg-n-alpha-1 cursor-pointer"
          >
            <input
              type="checkbox"
              class="rounded accent-n-brand"
              :checked="dayMenu.includes(item.key)"
              @change="toggle(dayMenu, item.key)"
            />
            <span class="text-sm text-n-slate-12">{{ item.label }}</span>
          </label>
        </div>
      </div>

      <!-- áreas administrativas -->
      <div class="bg-n-alpha-1 border border-n-weak rounded-2xl p-4">
        <div class="flex items-center justify-between mb-1">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-10">
            Áreas administrativas
          </p>
          <button
            class="text-[11px] font-medium text-n-slate-10 hover:text-n-slate-12 border border-n-weak rounded-full px-2 py-0.5 transition-colors"
            @click="selectAllGrants"
          >
            conceder tudo
          </button>
        </div>
        <p class="text-xs text-n-slate-9 mb-2">
          concessões de verdade: liberam a tela E os dados — use com critério
        </p>
        <div class="space-y-0.5">
          <div v-for="item in GRANT_ITEMS" :key="item.key">
            <label
              class="flex items-start gap-3 px-3 py-1.5 rounded-lg hover:bg-n-alpha-2 cursor-pointer"
            >
              <input
                type="checkbox"
                class="rounded accent-n-brand mt-0.5"
                :checked="grants.includes(item.key)"
                @change="toggle(grants, item.key)"
              />
              <span class="flex flex-col">
                <span class="text-sm text-n-slate-12 flex items-center gap-2">
                  {{ item.label }}
                  <span
                    v-if="grants.includes(item.key)"
                    class="text-[10px] font-medium text-green-600 bg-green-600/10 rounded-full px-2 py-0.5"
                  >concedido</span>
                </span>
                <span class="text-[11px] text-n-slate-9">{{ item.hint }}</span>
              </span>
            </label>

            <!-- item 62: Relatórios ABRE — escolher quais dashboards -->
            <div
              v-if="item.key === 'reports' && grants.includes('reports')"
              class="ml-8 mt-1 mb-2 bg-n-solid-1 border border-n-weak rounded-xl p-3"
            >
              <div class="flex items-center justify-between mb-1.5">
                <p class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-10">
                  Quais relatórios?
                </p>
                <button
                  class="text-[10px] font-medium border rounded-full px-2 py-0.5 transition-colors"
                  :class="reportKeys.length === 0
                    ? 'border-green-600/40 text-green-700 bg-green-600/10'
                    : 'border-n-weak text-n-slate-10 hover:text-n-slate-12'"
                  @click="selectAllReports"
                >
                  {{ reportKeys.length === 0 ? 'todos ✓' : 'selecionar todos' }}
                </button>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-0.5">
                <label
                  v-for="r in REPORT_ITEMS"
                  :key="r.key"
                  class="flex items-center gap-2 px-2 py-1 rounded-lg hover:bg-n-alpha-1 cursor-pointer"
                >
                  <input
                    type="checkbox"
                    class="rounded accent-n-brand"
                    :checked="reportChecked(r.key)"
                    @change="toggleReport(r.key)"
                  />
                  <span class="text-xs text-n-slate-12">{{ r.label }}</span>
                </label>
              </div>
              <p class="text-[10px] text-n-slate-9 mt-1.5">
                desmarcados somem do menu dela(e); "todos" acompanha relatórios novos automaticamente
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="flex items-center gap-2 px-8 py-6 flex-shrink-0">
      <button
        v-if="!isTargetAdmin"
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
        {{ isTargetAdmin ? 'Fechar' : 'Cancelar' }}
      </button>
      <span
        v-if="!isTargetAdmin && grants.length"
        class="text-xs text-n-slate-10 ml-auto"
      >
        {{ grants.length }} área(s) concedida(s)
      </span>
    </div>
  </div>
</template>
