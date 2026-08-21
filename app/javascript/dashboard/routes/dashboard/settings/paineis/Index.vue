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
const aiUserId = ref(null); // login que o Atendimento IA usa
const savingKey = ref('');

// 🎯 métricas do "Meu desempenho" por pessoa (item 139) — o admin propõe
// o painel individual de cada função; vazio = padrão do sistema
const METRIC_OPTIONS = [
  { key: 'touched', label: 'Conversas em que atuou', hint: 'mandou mensagem, independente de quem está atribuído' },
  { key: 'assigned', label: 'Conversas atribuídas', hint: 'conversas em que ela é a responsável' },
  { key: 'messages', label: 'Mensagens enviadas', hint: 'volume de mensagens no período' },
  { key: 'reply_commercial', label: 'Resposta média (08–17h)', hint: 'velocidade no horário comercial + % dentro da meta' },
  { key: 'first_response', label: '1ª resposta', hint: 'quanto o paciente esperou pela primeira resposta' },
  { key: 'resolved', label: 'Resolvidas', hint: 'conversas finalizadas por ela' },
  { key: 'appointments', label: 'Consultas agendadas', hint: 'consultas registradas por ela na Agenda' },
  { key: 'surgeries_created', label: 'Cirurgias agendadas', hint: 'cirurgias registradas por ela (papel do fechamento)' },
  { key: 'surgeries_closed', label: 'Cirurgias fechadas + R$', hint: 'cards dela que viraram Cirurgia Realizada no período' },
  { key: 'attendance', label: 'Comparecimento (clínica)', hint: 'presença nas consultas do período — de quem confirma' },
  { key: 'days_worked', label: 'Dias trabalhados', hint: 'dias com pelo menos 1 mensagem enviada' },
];
const DEFAULT_METRICS = ['touched', 'reply_commercial', 'days_worked', 'resolved', 'appointments', 'surgeries_closed'];
const metricsCfg = ref({}); // { user_id => [chaves] }
const selPersonId = ref(null);

const personMetrics = uid => metricsCfg.value[String(uid)] || [];
const metricActive = (uid, key) => {
  const own = personMetrics(uid);
  return own.length ? own.includes(key) : DEFAULT_METRICS.includes(key);
};
const saveMetrics = async () => {
  savingKey.value = 'metrics';
  try {
    await CrmAPI.updatePerformanceMetrics(metricsCfg.value);
    await store.dispatch('crm/fetchSettings');
    useAlert('Salvo! O painel da pessoa já reflete as métricas.');
  } catch {
    useAlert('Não consegui salvar — tenta de novo.');
  } finally {
    savingKey.value = '';
  }
};
const toggleMetric = (uid, key) => {
  const id = String(uid);
  // 1º clique numa pessoa sem config própria: parte do padrão
  const current = metricsCfg.value[id]?.length ? [...metricsCfg.value[id]] : [...DEFAULT_METRICS];
  const idx = current.indexOf(key);
  if (idx >= 0) current.splice(idx, 1);
  else current.push(key);
  if (!current.length) return; // nunca deixa zerar
  metricsCfg.value = { ...metricsCfg.value, [id]: current };
  saveMetrics();
};
const resetMetrics = uid => {
  const next = { ...metricsCfg.value };
  delete next[String(uid)];
  metricsCfg.value = next;
  saveMetrics();
};

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
  aiUserId.value = crmSettings.value?.ai_user_id || null;
  metricsCfg.value = { ...(crmSettings.value?.performance_metrics || {}) };
  if (!selPersonId.value && sortedAgents.value.length) selPersonId.value = sortedAgents.value[0].id;
};

const pickAi = async userId => {
  const previous = aiUserId.value;
  aiUserId.value = userId;
  savingKey.value = 'ai';
  try {
    await CrmAPI.updateAiUser(userId);
    await store.dispatch('crm/fetchSettings');
    useAlert('Salvo! O robô aparece no bloco "Meu desempenho" do Meu Painel.');
  } catch {
    aiUserId.value = previous;
    useAlert('Não consegui salvar — tenta de novo.');
  } finally {
    savingKey.value = '';
  }
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

      <!-- 🤖 Atendimento IA (item 138): qual login o robô usa pra responder -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mt-4">
        <div class="flex items-center gap-3 mb-1 flex-wrap">
          <span class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #334155, #64748B)">
            <span class="i-lucide-bot text-white text-base" />
          </span>
          <div class="flex-1 min-w-[180px]">
            <p class="text-sm font-bold text-n-slate-12">Atendimento IA</p>
            <p class="text-[11px] text-n-slate-10">
              qual login o robô usa pra responder — as métricas dele aparecem como referência
              no bloco "Meu desempenho" do Meu Painel de cada pessoa
            </p>
          </div>
          <span v-if="savingKey === 'ai'" class="i-lucide-loader-circle animate-spin text-sm text-n-brand" />
        </div>
        <div class="flex items-center gap-1.5 flex-wrap mt-3">
          <button
            class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors"
            :class="!aiUserId ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="!aiUserId ? { background: '#64748B' } : {}"
            @click="pickAi(null)"
          >
            Nenhum
          </button>
          <button
            v-for="a in sortedAgents"
            :key="a.id"
            class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors"
            :class="aiUserId === a.id ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="aiUserId === a.id ? { background: 'linear-gradient(135deg, #334155, #64748B)' } : {}"
            @click="pickAi(a.id)"
          >
            {{ a.available_name || a.name }}
          </button>
        </div>
      </div>

      <!-- 🎯 Métricas do "Meu desempenho" por pessoa (item 139) -->
      <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mt-4">
        <div class="flex items-center gap-3 mb-1 flex-wrap">
          <span class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #0F5FA6, #7C3AED)">
            <span class="i-lucide-target text-white text-base" />
          </span>
          <div class="flex-1 min-w-[180px]">
            <p class="text-sm font-bold text-n-slate-12">Métricas do "Meu desempenho"</p>
            <p class="text-[11px] text-n-slate-10">
              cada função tem seu painel: escolha a pessoa e marque o que faz sentido pro
              trabalho dela — ex.: quem agenda cirurgia vê "Cirurgias agendadas"; quem
              confirma consulta vê "Comparecimento"
            </p>
          </div>
          <span v-if="savingKey === 'metrics'" class="i-lucide-loader-circle animate-spin text-sm text-n-brand" />
        </div>

        <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mt-3 mb-1.5">Pessoa</p>
        <div class="flex items-center gap-1.5 flex-wrap mb-3">
          <button
            v-for="a in sortedAgents"
            :key="a.id"
            class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors"
            :class="selPersonId === a.id ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
            :style="selPersonId === a.id ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="selPersonId = a.id"
          >
            {{ a.available_name || a.name }}<template v-if="personMetrics(a.id).length"> ·⚙️</template>
          </button>
        </div>

        <template v-if="selPersonId">
          <div class="flex items-center gap-1.5 mb-1.5 flex-wrap">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide flex-1">Métricas desta pessoa (clique liga/desliga)</p>
            <button
              v-if="personMetrics(selPersonId).length"
              class="text-[10px] px-2 py-0.5 rounded-full border border-n-weak text-n-slate-10 hover:bg-n-alpha-1"
              @click="resetMetrics(selPersonId)"
            >
              voltar ao padrão
            </button>
            <span v-else class="text-[10px] text-n-slate-9">usando o padrão do sistema</span>
          </div>
          <div class="flex items-center gap-1.5 flex-wrap">
            <button
              v-for="m in METRIC_OPTIONS"
              :key="m.key"
              class="h-8 px-3 rounded-lg text-xs font-medium border transition-colors"
              :class="metricActive(selPersonId, m.key) ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
              :style="metricActive(selPersonId, m.key) ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
              :title="m.hint"
              @click="toggleMetric(selPersonId, m.key)"
            >
              {{ m.label }}
            </button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>