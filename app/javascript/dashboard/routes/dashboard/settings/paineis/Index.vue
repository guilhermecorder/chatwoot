<script setup>
// 🧑‍💼 Configurações → Painéis (pedido 20/08)
// O admin define o RESPONSÁVEL de cada painel do Meu Painel — o 1º nome
// aparece na pílula ("Cirurgias · Elizangela"). Trocou a pessoa da função?
// Troca aqui e o sistema inteiro acompanha, sem nome preso no código.
// (Diferente da engrenagem do Meu Painel, que define qual painel cada
// LOGIN enxerga — aqui é quem RESPONDE pelo tema.)
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const agents = useMapGetter('agents/getAgents');
const crmSettings = useMapGetter('crm/getSettings');

const PANELS = [
  {
    key: 'agendamento',
    label: 'Agendamento',
    desc: 'do lead ao agendamento — 1ª resposta, orçamento, marcação',
    icon: 'i-lucide-calendar-check',
    grad: 'linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)',
  },
  {
    key: 'conducao',
    label: 'Condução',
    desc: 'do agendamento à indicação — confirmação, comparecimento, conferência',
    icon: 'i-lucide-route',
    grad: 'linear-gradient(135deg, #0F766E 0%, #2DD4BF 100%)',
  },
  {
    key: 'cirurgia',
    label: 'Cirurgias',
    desc: 'fechamento e pós-operatório — indicações, agendamento cirúrgico',
    icon: 'i-lucide-heart-pulse',
    grad: 'linear-gradient(135deg, #9D174D 0%, #F472B6 100%)',
  },
];

const owners = ref({}); // { painel => user_id }
const savingKey = ref('');

const ownerName = key => {
  const uid = owners.value[key];
  const agent = (agents.value || []).find(a => a.id === uid);
  return agent ? agent.available_name || agent.name : '';
};
const firstName = key => (ownerName(key) || '').split(' ')[0] || '';

const loadFromSettings = () => {
  const fromServer = crmSettings.value?.panel_owners || {};
  const map = {};
  Object.keys(fromServer).forEach(k => {
    map[k] = fromServer[k]?.user_id;
  });
  owners.value = map;
};

const pick = async (panelKey, userId) => {
  const previous = { ...owners.value };
  if (userId) owners.value = { ...owners.value, [panelKey]: userId };
  else {
    const next = { ...owners.value };
    delete next[panelKey];
    owners.value = next;
  }
  savingKey.value = panelKey;
  try {
    await CrmAPI.updatePanelOwners(owners.value);
    await store.dispatch('crm/fetchSettings');
    useAlert('Salvo! O nome já aparece no Meu Painel.');
  } catch {
    owners.value = previous;
    useAlert('Não consegui salvar — tenta de novo.');
  } finally {
    savingKey.value = '';
  }
};

const sortedAgents = computed(() =>
  [...(agents.value || [])].sort((a, b) =>
    (a.available_name || a.name || '').localeCompare(b.available_name || b.name || '', 'pt-BR')
  )
);

onMounted(async () => {
  if (!(agents.value || []).length) await store.dispatch('agents/get').catch(() => {});
  if (!crmSettings.value) await store.dispatch('crm/fetchSettings').catch(() => {});
  loadFromSettings();
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-3xl mx-auto w-full p-4 sm:p-8">
      <!-- Header -->
      <div class="flex items-center gap-3 flex-wrap mb-2">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #152C61, #0F5FA6)">
          <span class="i-lucide-layout-dashboard text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Painéis</h1>
          <p class="text-xs text-n-slate-10">quem responde por cada painel do Meu Painel</p>
        </div>
      </div>
      <p class="text-xs text-n-slate-10 mb-6 max-w-xl">
        O primeiro nome da pessoa aparece na pílula do painel — ex.:
        <b class="text-n-slate-12">Cirurgias · Elizangela</b>. Alguém saiu ou trocou de função?
        Ajusta aqui e pronto. <b>Isto não muda acessos</b> — quem vê qual painel continua
        na engrenagem do Meu Painel.
      </p>

      <!-- Um card por painel -->
      <div class="space-y-4">
        <div
          v-for="p in PANELS"
          :key="p.key"
          class="bg-n-solid-2 border border-n-weak rounded-2xl p-5"
        >
          <div class="flex items-center gap-3 mb-1 flex-wrap">
            <span class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" :style="{ background: p.grad }">
              <span class="text-white text-base" :class="p.icon" />
            </span>
            <div class="flex-1 min-w-[180px]">
              <p class="text-sm font-bold text-n-slate-12">
                {{ p.label }}<template v-if="firstName(p.key)"> · {{ firstName(p.key) }}</template>
              </p>
              <p class="text-[11px] text-n-slate-10">{{ p.desc }}</p>
            </div>
            <span v-if="savingKey === p.key" class="i-lucide-loader-circle animate-spin text-sm text-n-brand" />
          </div>

          <!-- Responsável em botões em linha -->
          <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mt-3 mb-1.5">Pessoa responsável</p>
          <div class="flex items-center gap-1.5 flex-wrap">
            <button
              class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors"
              :class="!owners[p.key]
                ? 'text-white border-transparent'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
              :style="!owners[p.key] ? { background: '#64748B' } : {}"
              @click="pick(p.key, null)"
            >
              Sem responsável
            </button>
            <button
              v-for="a in sortedAgents"
              :key="a.id"
              class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors"
              :class="owners[p.key] === a.id
                ? 'text-white border-transparent'
                : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
              :style="owners[p.key] === a.id ? { background: p.grad } : {}"
              @click="pick(p.key, a.id)"
            >
              {{ a.available_name || a.name }}
            </button>
          </div>
        </div>
      </div>

      <p class="text-[11px] text-n-slate-9 mt-5">
        💡 Os painéis Médicos e Gestor não têm responsável fixo — Médicos mostra a agenda
        de cada médico e Gestor é a visão do dono.
      </p>
    </div>
  </div>
</template>
