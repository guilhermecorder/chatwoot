<script setup>
import { ref, watch, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import FollowupBotModal from 'dashboard/routes/dashboard/crm/components/FollowupBotModal.vue';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();

const inboxes = useMapGetter('inboxes/getInboxes');
const settings = useMapGetter('crm/getSettings');
const accountLabels = useMapGetter('labels/getLabels');
const teamAgents = useMapGetter('agents/getAgents');

const TABS = ['robos', 'agentes', 'programacao', 'tratamento'];
const activeTab = ref(TABS.includes(route.query.tab) ? route.query.tab : 'robos');

// os itens do menu lateral apontam para a MESMA rota com ?tab= diferente —
// sem este watch, clicar neles não trocava a aba (a página não remonta)
watch(
  () => route.query.tab,
  tab => {
    if (TABS.includes(tab)) activeTab.value = tab;
  }
);

// ── Agentes de IA internos (editar prompt / pausar) ──
// O Radar perene é configurado por VIGIAS: cada vigia = coluna + painel do
// atendente que recebe os avisos (null = todos) + janela de tempo própria.
const aiAgents = ref({
  conversation: { enabled: true, prompt: '', model: '', effort: '', default_prompt: '' },
  form: { enabled: true, prompt: '', model: '', effort: '', default_prompt: '' },
  scheduler: { enabled: true, prompt: '', model: '', effort: '', default_prompt: '' },
  opportunity: { enabled: true, prompt: '', model: '', effort: '', default_prompt: '', watchers: [], wait_minutes: 10 },
});

const LOOKBACK_OPTIONS = [
  { value: 6, label: 'últimas 6 horas' },
  { value: 12, label: 'últimas 12 horas' },
  { value: 24, label: 'últimas 24 horas' },
  { value: 48, label: 'últimas 48 horas' },
];

const addWatcher = () => {
  aiAgents.value.opportunity.watchers.push({ stage_id: '', user_id: null, lookback_hours: 24 });
};
const removeWatcher = idx => {
  aiAgents.value.opportunity.watchers.splice(idx, 1);
};

// Radar PONTUAL: varredura única (coluna + atendente + etiqueta + período),
// roda uma vez e NÃO fica ativa — diferente do Radar perene acima
const showSweepModal = ref(false);
const sweep = ref({ stage_id: '', user_id: null, label: '', since_hours: 24 });
const isSweeping = ref(false);
const runSweep = async () => {
  isSweeping.value = true;
  try {
    const { data } = await CrmAPI.radarScan({
      stage_ids: sweep.value.stage_id ? [sweep.value.stage_id] : [],
      label: sweep.value.label,
      since_hours: sweep.value.since_hours,
      user_id: sweep.value.user_id || null,
    });
    useAlert(data.message || 'Radar pontual iniciado!');
    showSweepModal.value = false;
  } catch {
    useAlert('Erro ao iniciar o radar pontual.');
  } finally {
    isSweeping.value = false;
  }
};

const radarLastRun = () => settings.value?.ai?.opportunity_last_run || null;
const isSavingAgents = ref(false);

// ── Interruptor DEFINITIVO do agente ──
// Liga/desliga NA HORA (grava direto no banco, sem depender do botão
// "Salvar agentes"). Desligado = o agente não roda por nenhum caminho:
// botão da conversa, automação de coluna ou cron do Radar.
const togglingAgent = ref('');
const toggleAgent = async key => {
  if (togglingAgent.value) return;
  const agent = aiAgents.value[key];
  const next = !agent.enabled;
  togglingAgent.value = key;
  try {
    await CrmAPI.updateAi({ agents: { [key]: { enabled: next } } });
    agent.enabled = next;
    useAlert(
      next
        ? `✅ ${AGENT_META[key].title} LIGADO — já está valendo.`
        : `⏹ ${AGENT_META[key].title} DESLIGADO — parou em todos os caminhos.`
    );
  } catch {
    useAlert('Erro ao mudar o interruptor do agente.');
  } finally {
    togglingAgent.value = '';
  }
};

// uso/custo dos agentes (relatório)
const aiUsage = ref(null);
const usageByAgent = key =>
  (aiUsage.value?.by_agent || []).find(r => r.key === key) || null;
const fmtUsd = v => `US$ ${(v || 0).toFixed(2)}`;
const fmtTokens = v => (v >= 1000 ? `${(v / 1000).toFixed(1)}k` : String(v || 0));

const AGENT_META = {
  conversation: {
    title: 'Analista de Conversas',
    icon: 'i-lucide-message-square-text',
    gradient: 'linear-gradient(135deg, #0F5FA6, #7C3AED)',
    color: '#0F5FA6',
    tag: 'Atendimento',
    description: 'Lê a conversa e devolve o indicador de interesse do paciente (alto/médio/baixo/perdido), um resumo e o próximo passo sugerido para a atendente.',
    triggers: [
      { icon: 'i-lucide-mouse-pointer-click', label: 'Botão "Analisar com IA" no painel da conversa' },
      { icon: 'i-lucide-zap', label: 'Ação de coluna "Analisar com IA"' },
      { icon: 'i-lucide-rocket', label: 'Resultado aparece no balão do CRM' },
    ],
    suggestion: 'Tarefa exigente — Opus ou Sonnet dão a melhor leitura de interesse.',
  },
  form: {
    title: 'Analista de Formulários',
    icon: 'i-lucide-clipboard-list',
    gradient: 'linear-gradient(135deg, #5B21B6, #7C3AED)',
    color: '#7C3AED',
    tag: 'Marketing',
    description: 'Lê todas as respostas de um formulário e sintetiza dores, desejos, objeções e recomendações práticas de marketing e atendimento.',
    triggers: [
      { icon: 'i-lucide-sparkles', label: 'Botão "Gerar insights com IA" na página Formulários' },
    ],
    suggestion: 'Analisa muitas respostas de uma vez — vale usar esforço alto.',
  },
  scheduler: {
    title: 'Agente de Agendamento',
    icon: 'i-lucide-calendar-plus',
    gradient: 'linear-gradient(135deg, #B8860B, #D4A017)',
    color: '#B8860B',
    tag: 'Agenda',
    description: 'Extrai da conversa o nome, telefone, problema, dia, hora, médico e unidade da consulta confirmada e cria o compromisso na Agenda.',
    triggers: [
      { icon: 'i-lucide-zap', label: 'Ação de coluna "Agendar consulta (IA)"' },
      { icon: 'i-lucide-calendar-days', label: 'Cria o compromisso na Agenda' },
      { icon: 'i-lucide-list-checks', label: 'Sem dia/hora → tarefa "⚠️ Confirmar consulta"' },
    ],
    suggestion: 'Extração estruturada — Sonnet no esforço médio resolve bem e custa menos.',
  },
  opportunity: {
    title: 'Radar de Oportunidades',
    icon: 'i-lucide-radar',
    gradient: 'linear-gradient(135deg, #DC2626, #F59E0B)',
    color: '#DC2626',
    tag: 'Não perder venda',
    description: 'Audita as colunas vigiadas e encontra pacientes QUENTES parados sem atendimento (ex.: quer agendar e ninguém respondeu). Cria o aviso no Meu Painel com nome, motivo e o que a atendente deve fazer.',
    triggers: [
      { icon: 'i-lucide-clock', label: 'Auditoria automática a cada 10 minutos' },
      { icon: 'i-lucide-house', label: 'Aviso vermelho no Meu Painel do atendente escolhido' },
      { icon: 'i-lucide-columns-3', label: 'Cada coluna vigiada com atendente e janela próprios' },
      { icon: 'i-lucide-scan-search', label: 'Radar pontual: varredura única que não fica ativa' },
    ],
    suggestion: 'Classificação simples e frequente — Haiku mantém o custo baixinho.',
  },
};

// opções de modelo/esforço por agente ('' = usa o RECOMENDADO do agente)
const AGENT_MODELS = [
  { value: 'claude-opus-4-8', label: 'Opus 4.8 — melhor análise' },
  { value: 'claude-sonnet-5', label: 'Sonnet 5 — equilíbrio' },
  { value: 'claude-haiku-4-5', label: 'Haiku 4.5 — mais barato e rápido' },
];
const AGENT_EFFORTS = [
  { value: 'low', label: 'Baixo — rápido e econômico' },
  { value: 'medium', label: 'Médio — equilíbrio' },
  { value: 'high', label: 'Alto' },
  { value: 'max', label: 'Máximo — melhor análise possível' },
];

const MODEL_SHORT = {
  'claude-opus-4-8': 'Opus 4.8',
  'claude-sonnet-5': 'Sonnet 5',
  'claude-haiku-4-5': 'Haiku 4.5',
};
const EFFORT_SHORT = { low: 'baixo', medium: 'médio', high: 'alto', xhigh: 'muito alto', max: 'máximo' };

// recomendação do sistema para cada agente (vem do backend)
const recommendedFor = key => settings.value?.ai?.agents?.[key] || {};

const recommendedModelLabel = key => {
  const m = recommendedFor(key).recommended_model;
  return `Recomendado — ${MODEL_SHORT[m] || 'padrão'}`;
};
const recommendedEffortLabel = key => {
  const rec = recommendedFor(key);
  if ((rec.recommended_model || '').includes('haiku') && !rec.recommended_effort)
    return 'Recomendado — não se aplica (Haiku)';
  return `Recomendado — ${EFFORT_SHORT[rec.recommended_effort] || 'alto'}`;
};

// o que o agente vai usar de verdade (escolha própria > recomendado > global)
const resolvedModel = (key, agent) => {
  const m = agent.model || recommendedFor(key).recommended_model ||
    settings.value?.ai?.model || 'claude-opus-4-8';
  return MODEL_SHORT[m] || m;
};
const resolvedEffort = (key, agent) => {
  const m = agent.model || recommendedFor(key).recommended_model ||
    settings.value?.ai?.model || '';
  if (m.includes('haiku')) return 'não se aplica (Haiku)';
  const e = agent.effort || recommendedFor(key).recommended_effort ||
    settings.value?.ai?.effort || 'high';
  return EFFORT_SHORT[e] || e;
};

// colunas de todos os funis (para o Radar escolher o que vigiar)
const allStages = ref([]);
const loadStages = async () => {
  await store.dispatch('crm/fetchPipelines');
  const pipelines = store.getters['crm/getPipelines'] || [];
  allStages.value = pipelines.flatMap(p =>
    (p.stages || []).map(s => ({ id: s.id, name: s.name, pipeline: p.name }))
  );
};

const loadAgents = async () => {
  await store.dispatch('crm/fetchSettings');
  const a = settings.value?.ai?.agents || {};
  const load = key => ({
    // opt-in: agente só aparece LIGADO se foi ligado de propósito
    enabled: a[key]?.enabled === true,
    prompt: a[key]?.prompt || '',
    model: a[key]?.model || '',
    effort: a[key]?.effort || '',
    default_prompt: a[key]?.default_prompt || '',
  });
  // compat: config antiga (stage_ids soltos) vira vigia sem direcionamento
  const legacyWatchers = (a.opportunity?.stage_ids || []).map(id => ({
    stage_id: id,
    user_id: null,
    lookback_hours: a.opportunity?.lookback_hours || 24,
  }));
  aiAgents.value = {
    conversation: load('conversation'),
    form: load('form'),
    scheduler: load('scheduler'),
    opportunity: {
      ...load('opportunity'),
      watchers: a.opportunity?.watchers?.length ? a.opportunity.watchers : legacyWatchers,
      wait_minutes: a.opportunity?.wait_minutes || 10,
    },
  };
  // relatório de gastos + colunas para o Radar (em paralelo)
  loadStages().catch(() => {});
  CrmAPI.getAiUsage()
    .then(({ data }) => { aiUsage.value = data; })
    .catch(() => {});
};

const saveAgents = async () => {
  isSavingAgents.value = true;
  try {
    const pack = agent => ({
      enabled: agent.enabled,
      prompt: agent.prompt.trim(),
      model: agent.model,
      effort: agent.effort,
    });
    await CrmAPI.updateAi({
      agents: {
        conversation: pack(aiAgents.value.conversation),
        form: pack(aiAgents.value.form),
        scheduler: pack(aiAgents.value.scheduler),
        opportunity: {
          ...pack(aiAgents.value.opportunity),
          // só vigias com coluna escolhida valem
          watchers: aiAgents.value.opportunity.watchers
            .filter(w => w.stage_id)
            .map(w => ({
              stage_id: Number(w.stage_id),
              user_id: w.user_id || null,
              lookback_hours: Number(w.lookback_hours) || 24,
            })),
          wait_minutes: Number(aiAgents.value.opportunity.wait_minutes) || 10,
        },
      },
    });
    useAlert('Agentes de IA salvos!');
  } catch {
    useAlert('Erro ao salvar os agentes.');
  } finally {
    isSavingAgents.value = false;
  }
};

const aiConfigured = ref(false);

// ── Modo Programação: todas as automações de coluna num lugar ──
const columnAutomations = ref([]);
const loadingColumnAutomations = ref(false);

const loadColumnAutomations = async () => {
  loadingColumnAutomations.value = true;
  try {
    await store.dispatch('crm/fetchPipelines');
    const pipelines = store.getters['crm/getPipelines'] || [];
    const all = [];
    for (const p of pipelines) {
      for (const s of p.stages || []) {
        // eslint-disable-next-line no-await-in-loop
        const { data } = await CrmAPI.getAutomations(p.id, s.id);
        (data || [])
          .filter(a => a.action_type) // só automações de coluna (não réguas)
          .forEach(a => all.push({ ...a, stage_name: s.name, pipeline_name: p.name }));
      }
    }
    columnAutomations.value = all;
  } catch {
    columnAutomations.value = [];
  } finally {
    loadingColumnAutomations.value = false;
  }
};

const ACTION_LABELS = {
  webhook: 'Disparar webhook',
  n8n_flow: 'Acionar fluxo n8n',
  apply_label: 'Aplicar etiqueta',
  move_card: 'Mover para coluna',
  log_timeline: 'Registrar na timeline',
  notify_team: 'Notificar equipe',
  meta_ads_event: 'Evento Meta Ads',
  google_ads_conversion: 'Conversão Google Ads',
  send_form: 'Enviar formulário',
  ai_analyze: 'Agente de IA: Analista de Conversas',
  schedule_appointment: 'Agente de IA: Agendamento',
};

const openProgrammingMode = () => {
  window.location.href = `/app/accounts/${accountId.value}/crm?programming=1`;
};

// ── Tratamento de dados (atalhos conectados) ──
const TREATMENT_TOOLS = [
  { icon: 'i-lucide-tag', title: 'Etiqueta retroativa', desc: 'Aplica etiqueta e move para coluna quem já mencionou um termo nas mensagens (busca em massa no histórico).' },
  { icon: 'i-lucide-replace', title: 'Substituir / remover etiqueta', desc: 'Troca ou limpa etiquetas em massa em toda a base.' },
  { icon: 'i-lucide-circle-dollar-sign', title: 'Valor pelo orçamento', desc: 'Detecta valores de orçamento nas conversas e preenche o valor do card.' },
  { icon: 'i-lucide-user-check', title: 'Unificar contatos duplicados', desc: 'Mescla contatos com mesmo telefone/e-mail (com prévia antes de aplicar).' },
];

const openTreatment = () => {
  router.push({
    name: 'crm_campaigns',
    params: { accountId: accountId.value },
    query: { tab: 'automations' },
  });
};

// ── Réguas de mensagem (mesmo motor da Campanha WhatsApp) ──
const automations = ref([]);
const loadingReguas = ref(true);

const loadReguas = async () => {
  loadingReguas.value = true;
  try {
    automations.value = await store.dispatch('crm/fetchMessageAutomations');
  } catch {
    useAlert('Erro ao carregar réguas');
  } finally {
    loadingReguas.value = false;
  }
};

const toggleRegua = async a => {
  try {
    await store.dispatch('crm/updateMessageAutomation', { id: a.id, active: !a.active });
    a.active = !a.active;
  } catch {
    useAlert('Erro ao atualizar');
  }
};

const deleteRegua = async a => {
  try {
    await store.dispatch('crm/deleteMessageAutomation', a.id);
    automations.value = automations.value.filter(x => x.id !== a.id);
    useAlert('Régua excluída');
  } catch {
    useAlert('Erro ao excluir');
  }
};

const goToCampaign = () => {
  router.push({ name: 'crm_campaigns', params: { accountId: accountId.value } });
};

// ── Robôs de follow-up ──
const bots = ref([]);
const loadingBots = ref(true);

const loadBots = async () => {
  loadingBots.value = true;
  try {
    bots.value = await store.dispatch('crm/fetchFollowupBots');
  } catch {
    useAlert('Erro ao carregar robôs');
  } finally {
    loadingBots.value = false;
  }
};

const showBotModal = ref(false);
const editingBot = ref(null);

const openCreateBot = () => { editingBot.value = null; showBotModal.value = true; };
const openEditBot = bot => { editingBot.value = bot; showBotModal.value = true; };
const onBotSaved = async () => { showBotModal.value = false; editingBot.value = null; await loadBots(); };

const toggleBot = async bot => {
  try {
    const data = await store.dispatch('crm/updateFollowupBot', { id: bot.id, active: !bot.active });
    bot.active = data.active;
  } catch {
    useAlert('Erro ao atualizar');
  }
};

const deleteBotConfirmId = ref(null);
const deleteBot = async bot => {
  try {
    await store.dispatch('crm/deleteFollowupBot', bot.id);
    bots.value = bots.value.filter(b => b.id !== bot.id);
    deleteBotConfirmId.value = null;
    useAlert('Robô excluído');
  } catch {
    useAlert('Erro ao excluir');
  }
};

const delayLabel = step => {
  const hours = step.delay_value != null
    ? Number(step.delay_value) * (step.delay_unit === 'days' ? 24 : 1)
    : Number(step.delay_hours);
  if (hours < 1) return `${Math.round(hours * 60)}min`;
  if (hours < 24) return `${hours}h`;
  return `${Math.round(hours / 24)}d`;
};

onMounted(async () => {
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  if (!accountLabels.value.length) store.dispatch('labels/get');
  if (!teamAgents.value.length) store.dispatch('agents/get');
  loadBots();
  loadReguas(); // aparecem no painel panorâmico (Modo Programação)
  await loadAgents();
  aiConfigured.value = !!settings.value?.ai?.configured;
  loadColumnAutomations();
});
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Header -->
    <div class="px-6 py-4 border-b border-n-weak flex-shrink-0">
      <h1 class="text-lg font-semibold text-n-slate-12">Automações</h1>
      <p class="text-xs text-n-slate-10 mt-0.5">
        Tudo que trabalha sozinho no sistema: réguas, robôs, agentes de IA, automações de coluna e tratamento de dados.
      </p>
      <!-- Tabs -->
      <div class="flex gap-1 mt-3 flex-wrap">
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors"
          :class="activeTab === 'robos' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'robos'"
        >🤖 Robôs de follow-up</button>
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'agentes' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'agentes' ? { background: 'linear-gradient(135deg, #7C3AED, #5B21B6)' } : {}"
          @click="activeTab = 'agentes'"
        ><span class="i-lucide-sparkles text-xs" />Agentes de IA</button>
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors"
          :class="activeTab === 'programacao' ? 'bg-yellow-500 text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'programacao'"
        >⚡ Modo Programação</button>
        <button
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors"
          :class="activeTab === 'tratamento' ? 'bg-n-brand text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          @click="activeTab = 'tratamento'"
        >Tratamento de dados</button>
      </div>
    </div>

    <div class="flex-1 overflow-y-auto p-6">
      <!-- ══ ROBÔS ══ -->
      <div v-if="activeTab === 'robos'" class="max-w-3xl">
        <div class="flex items-center justify-between mb-4">
          <p class="text-sm text-n-slate-11">
            Cutucadas simples para reabrir a conversa quando o paciente some. Ex.: 3h "oi, pode falar?",
            10h "[nome], no seu tempo ok?". Para sozinho se o paciente responder.
          </p>
          <button
            class="text-sm px-3 py-2 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 flex items-center gap-1.5 flex-shrink-0"
            @click="openCreateBot"
          >
            <span class="i-lucide-plus text-sm" />
            Novo robô
          </button>
        </div>

        <div v-if="loadingBots" class="flex justify-center py-10"><Spinner :size="28" class="text-n-brand" /></div>
        <div v-else-if="!bots.length" class="text-center py-12 text-n-slate-10">
          <span class="i-lucide-bot text-4xl mb-2 block mx-auto" />
          <p class="text-sm">Nenhum robô criado ainda.</p>
        </div>
        <div v-else class="space-y-3">
          <div v-for="bot in bots" :key="bot.id" class="p-4 bg-n-solid-2 border border-n-weak rounded-xl">
            <div class="flex items-center gap-2 mb-2">
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="bot.active ? 'bg-green-500' : 'bg-n-slate-9'" />
              <p class="text-sm font-semibold text-n-slate-12 flex-1 truncate">{{ bot.name }}</p>
              <span class="text-xs text-n-slate-10">{{ bot.inbox_name || '🔁 Caixa automática' }}</span>
              <button
                class="text-xs px-2 py-1 rounded-lg border border-n-weak ml-1"
                :class="bot.active ? 'text-yellow-600' : 'text-green-600'"
                @click="toggleBot(bot)"
              >{{ bot.active ? 'Pausar' : 'Ativar' }}</button>
              <button class="text-n-slate-9 hover:text-n-brand i-lucide-pencil text-sm" @click="openEditBot(bot)" />
              <button
                v-if="deleteBotConfirmId !== bot.id"
                class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm"
                @click="deleteBotConfirmId = bot.id"
              />
              <button v-else class="text-xs text-red-500" @click="deleteBot(bot)">Confirmar</button>
            </div>
            <div class="flex flex-wrap gap-1.5">
              <span
                v-for="(s, i) in bot.steps"
                :key="i"
                class="text-[11px] bg-n-alpha-2 text-n-slate-11 rounded-full px-2 py-0.5"
              >
                {{ delayLabel(s) }}: {{ s.template_params ? `📋 ${s.template_params.name}` : `"${s.message}"` }}
              </span>
            </div>
          </div>
        </div>
      </div>
      <!-- ══ AGENTES DE IA ══ -->
      <div v-else-if="activeTab === 'agentes'" class="max-w-3xl space-y-5">
        <div v-if="!aiConfigured" class="rounded-xl border-2 p-4 text-sm text-n-slate-11" style="border-color: rgba(212,160,23,0.4); background: rgba(212,160,23,0.08)">
          ⚠️ A Claude ainda não está conectada — configure a chave da API em
          <button class="text-n-brand font-medium hover:underline" @click="router.push({ name: 'crm_integrations', params: { accountId } })">Integrações → Claude</button>.
          Os agentes ficam prontos, mas só funcionam com a chave.
        </div>

        <!-- 💰 Relatório de gastos com os agentes -->
        <div v-if="aiUsage" class="rounded-2xl border-2 border-n-weak bg-n-solid-2 p-5">
          <div class="flex items-center gap-2 mb-4">
            <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #65A30D, #84CC16)">
              <span class="i-lucide-wallet text-white text-base" />
            </span>
            <div>
              <p class="text-sm font-bold text-n-slate-12">Gasto com os agentes de IA</p>
              <p class="text-[11px] text-n-slate-10">custo estimado pelas tabelas da Anthropic (US$)</p>
            </div>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #0F5FA6, #0B4A82)">
              <p class="text-[11px] font-medium text-white/80">Hoje</p>
              <p class="text-lg font-bold leading-tight">{{ fmtUsd(aiUsage.periods?.today?.cost_usd) }}</p>
              <p class="text-[10px] text-white/70">{{ aiUsage.periods?.today?.calls || 0 }} análise(s)</p>
            </div>
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
              <p class="text-[11px] font-medium text-white/80">7 dias</p>
              <p class="text-lg font-bold leading-tight">{{ fmtUsd(aiUsage.periods?.last7?.cost_usd) }}</p>
              <p class="text-[10px] text-white/70">{{ aiUsage.periods?.last7?.calls || 0 }} análise(s)</p>
            </div>
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
              <p class="text-[11px] font-medium text-white/80">30 dias</p>
              <p class="text-lg font-bold leading-tight">{{ fmtUsd(aiUsage.periods?.last30?.cost_usd) }}</p>
              <p class="text-[10px] text-white/70">{{ aiUsage.periods?.last30?.calls || 0 }} análise(s)</p>
            </div>
            <div class="rounded-xl px-4 py-3 bg-n-solid-1 border border-n-weak">
              <p class="text-[11px] font-medium text-n-slate-10">Desde o início</p>
              <p class="text-lg font-bold leading-tight text-n-slate-12">{{ fmtUsd(aiUsage.periods?.all?.cost_usd) }}</p>
              <p class="text-[10px] text-n-slate-9">{{ aiUsage.periods?.all?.calls || 0 }} análise(s)</p>
            </div>
          </div>

          <div v-if="aiUsage.by_agent?.length" class="space-y-1.5">
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">Por agente (30 dias)</p>
            <div
              v-for="row in aiUsage.by_agent"
              :key="row.key"
              class="flex items-center gap-2 text-xs text-n-slate-11 flex-wrap"
            >
              <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: AGENT_META[row.key]?.color || '#94A3B8' }" />
              <span class="font-medium text-n-slate-12 w-48 truncate">{{ AGENT_META[row.key]?.title || row.key }}</span>
              <span>{{ row.calls }} análise(s)</span>
              <span class="text-n-slate-9">· {{ fmtTokens(row.input_tokens) }} tokens entrada · {{ fmtTokens(row.output_tokens) }} saída</span>
              <span class="ml-auto font-semibold text-n-slate-12">{{ fmtUsd(row.cost_usd) }}</span>
            </div>
          </div>
          <p v-else class="text-xs text-n-slate-10">Nenhuma análise registrada ainda — os custos aparecem aqui conforme os agentes rodarem.</p>
        </div>

        <div
          v-for="(agent, key) in aiAgents"
          :key="key"
          class="rounded-2xl border-2 bg-n-solid-2 overflow-hidden"
          :style="{ borderColor: AGENT_META[key].color + '40' }"
        >
          <!-- Faixa superior colorida -->
          <div class="h-1.5 w-full" :style="{ background: AGENT_META[key].gradient }" />

          <div class="p-5">
            <!-- Cabeçalho -->
            <div class="flex items-start gap-3 mb-3">
              <span class="w-11 h-11 rounded-xl flex items-center justify-center flex-shrink-0 shadow" :style="{ background: AGENT_META[key].gradient }">
                <span :class="AGENT_META[key].icon" class="text-white text-lg" />
              </span>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 flex-wrap">
                  <p class="text-sm font-bold text-n-slate-12">{{ AGENT_META[key].title }}</p>
                  <span
                    class="text-[10px] px-2 py-0.5 rounded-full font-semibold"
                    :style="{ backgroundColor: AGENT_META[key].color + '1A', color: AGENT_META[key].color }"
                  >
                    {{ AGENT_META[key].tag }}
                  </span>
                  <span
                    class="text-[10px] px-2 py-0.5 rounded-full font-medium"
                    :class="agent.enabled ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-10'"
                  >
                    ● {{ agent.enabled ? 'Ligado' : 'Desligado' }}
                  </span>
                </div>
                <p class="text-xs text-n-slate-10 mt-1">{{ AGENT_META[key].description }}</p>
              </div>
              <!-- INTERRUPTOR definitivo: grava na hora, sem "Salvar" -->
              <div class="flex flex-col items-end gap-1 flex-shrink-0">
                <button
                  class="relative w-14 h-7 rounded-full transition-colors disabled:opacity-50"
                  :class="agent.enabled ? 'bg-green-500' : 'bg-n-alpha-3'"
                  :title="agent.enabled
                    ? 'Desligar este agente agora (para tudo: botões, automações e cron)'
                    : 'Ligar este agente agora'"
                  :disabled="togglingAgent === key"
                  @click="toggleAgent(key)"
                >
                  <span
                    class="absolute top-0.5 w-6 h-6 rounded-full bg-white shadow transition-all flex items-center justify-center"
                    :class="agent.enabled ? 'left-7' : 'left-0.5'"
                  >
                    <span
                      :class="togglingAgent === key ? 'i-lucide-loader-2 animate-spin' : (agent.enabled ? 'i-lucide-check' : 'i-lucide-power')"
                      class="text-[11px]"
                      :style="{ color: agent.enabled ? '#16A34A' : '#94A3B8' }"
                    />
                  </span>
                </button>
                <span class="text-[9px] text-n-slate-9">vale na hora</span>
              </div>
            </div>

            <!-- Onde se aplica -->
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Onde se aplica</p>
            <div class="flex flex-wrap gap-1.5 mb-4">
              <span
                v-for="(t, i) in AGENT_META[key].triggers"
                :key="i"
                class="flex items-center gap-1 text-[11px] px-2 py-1 rounded-lg bg-n-alpha-1 text-n-slate-11 border border-n-weak"
              >
                <span :class="t.icon" class="text-xs" :style="{ color: AGENT_META[key].color }" />
                {{ t.label }}
              </span>
            </div>

            <!-- Modelo + Esforço (vazio = recomendado pelo sistema) -->
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-2">
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Modelo de IA</label>
                <select
                  v-model="agent.model"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                >
                  <option value="">⭐ {{ recommendedModelLabel(key) }}</option>
                  <option v-for="m in AGENT_MODELS" :key="m.value" :value="m.value">{{ m.label }}</option>
                </select>
              </div>
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
                  Esforço <span class="text-n-slate-9 font-normal">(quanto pensa)</span>
                </label>
                <select
                  v-model="agent.effort"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
                >
                  <option value="">⭐ {{ recommendedEffortLabel(key) }}</option>
                  <option v-for="e in AGENT_EFFORTS" :key="e.value" :value="e.value">{{ e.label }}</option>
                </select>
              </div>
            </div>

            <!-- Em uso + dica + uso 30d -->
            <div class="flex items-center gap-2 flex-wrap mb-4">
              <span class="text-[11px] px-2 py-1 rounded-lg font-medium text-white" :style="{ background: AGENT_META[key].gradient }">
                Em uso: {{ resolvedModel(key, agent) }} · esforço {{ resolvedEffort(key, agent) }}
              </span>
              <span
                v-if="usageByAgent(key)"
                class="text-[11px] px-2 py-1 rounded-lg bg-n-alpha-1 border border-n-weak text-n-slate-11"
              >
                30 dias: {{ usageByAgent(key).calls }} análise(s) · {{ fmtUsd(usageByAgent(key).cost_usd) }}
              </span>
              <span class="text-[11px] text-n-slate-9 flex items-center gap-1">
                <span class="i-lucide-lightbulb text-xs" />
                {{ AGENT_META[key].suggestion }}
              </span>
            </div>

            <!-- Config específica do Radar de Oportunidades (perene) -->
            <div v-if="key === 'opportunity'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <!-- O que ele monitora, direto ao ponto -->
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" style="background: linear-gradient(135deg, #DC2626, #F59E0B)">
                <p>
                  📡 Monitora só o movimento <b>novo</b> de cada coluna vigiada (espera > {{ agent.wait_minutes }} min)
                  · avisa no <b>Meu Painel</b> do atendente escolhido · <b>nunca fala com o paciente</b>.
                </p>
                <p v-if="radarLastRun()" class="text-white/80 mt-0.5">
                  Última rodada: {{ radarLastRun().candidates }} no filtro · {{ radarLastRun().analyzed }} analisados ·
                  {{ radarLastRun().new_alerts }} novos avisos
                </p>
              </div>

              <div class="flex items-center gap-2 flex-wrap text-xs text-n-slate-11">
                Avisar quando o paciente esperar mais de
                <input
                  v-model.number="agent.wait_minutes"
                  type="number"
                  min="1"
                  class="w-16 border border-n-weak rounded-lg px-2 py-1 text-sm bg-n-solid-2 text-n-slate-12"
                />
                min sem resposta
              </div>

              <!-- Vigias: coluna + painel do atendente + janela de tempo -->
              <div>
                <p class="text-xs font-medium text-n-slate-11 mb-1.5">
                  Colunas vigiadas
                  <span class="text-n-slate-9 font-normal">(cada coluna com seu atendente e janela — sem vigia o Radar fica desligado)</span>
                </p>
                <div v-if="!allStages.length" class="text-xs text-n-slate-9">Carregando colunas…</div>
                <template v-else>
                  <div v-if="!agent.watchers.length" class="text-xs text-n-slate-9 mb-2">
                    Nenhuma coluna vigiada ainda — adicione a primeira abaixo.
                  </div>
                  <div v-else class="space-y-2 mb-2">
                    <div
                      v-for="(w, wi) in agent.watchers"
                      :key="wi"
                      class="flex flex-col sm:flex-row sm:items-end gap-2 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2.5"
                    >
                      <div class="flex-1 min-w-0">
                        <label class="text-[10px] font-medium text-n-slate-9 block mb-0.5 flex items-center gap-1">
                          <span class="i-lucide-columns-3 text-[10px]" style="color: #DC2626" /> Coluna vigiada
                        </label>
                        <select
                          v-model="w.stage_id"
                          class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
                        >
                          <option value="" disabled>Escolha a coluna…</option>
                          <option v-for="s in allStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                        </select>
                      </div>
                      <div class="flex-1 min-w-0">
                        <label class="text-[10px] font-medium text-n-slate-9 block mb-0.5">Avisar no painel de</label>
                        <select
                          v-model="w.user_id"
                          class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
                        >
                          <option :value="null">👥 Todos os atendentes</option>
                          <option v-for="ag in teamAgents" :key="ag.id" :value="ag.id">{{ ag.available_name || ag.name }}</option>
                        </select>
                      </div>
                      <div class="flex-1 min-w-0">
                        <label class="text-[10px] font-medium text-n-slate-9 block mb-0.5">Olhando o movimento das</label>
                        <select
                          v-model.number="w.lookback_hours"
                          class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12"
                        >
                          <option v-for="o in LOOKBACK_OPTIONS" :key="o.value" :value="o.value">{{ o.label }}</option>
                        </select>
                      </div>
                      <button
                        class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm flex-shrink-0 self-end sm:self-auto sm:mb-2"
                        title="Remover esta vigia"
                        @click="removeWatcher(wi)"
                      />
                    </div>
                  </div>
                  <button
                    class="flex items-center gap-1 text-xs font-medium px-2.5 py-1.5 rounded-lg border border-dashed transition-colors hover:bg-n-alpha-1"
                    style="border-color: rgba(220,38,38,0.5); color: #DC2626"
                    @click="addWatcher"
                  >
                    <span class="i-lucide-plus text-xs" />
                    Vigiar outra coluna
                  </button>
                </template>
              </div>

              <!-- Radar pontual: roda uma vez, não fica ativo -->
              <div class="border-t border-n-weak pt-3 flex items-center gap-2 flex-wrap">
                <button
                  class="flex items-center gap-1.5 text-xs font-semibold text-white px-3 py-2 rounded-lg hover:opacity-90"
                  style="background: linear-gradient(135deg, #DC2626, #F59E0B)"
                  @click="showSweepModal = true"
                >
                  <span class="i-lucide-scan-search text-xs" />
                  Radar pontual…
                </button>
                <span class="text-[11px] text-n-slate-9">
                  varre AGORA a coluna que você escolher e avisa o atendente escolhido — roda uma vez, não fica ativo
                </span>
              </div>
            </div>

            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Prompt do agente <span class="text-n-slate-9 font-normal">(vazio = usa o prompt padrão abaixo)</span>
            </label>
            <textarea
              v-model="agent.prompt"
              rows="4"
              class="w-full border border-n-weak rounded-xl px-3 py-2.5 text-xs bg-n-solid-1 text-n-slate-12 font-mono leading-relaxed"
              :placeholder="agent.default_prompt"
            />
          </div>
        </div>

        <button
          class="w-full text-white rounded-xl py-2.5 text-sm font-bold hover:opacity-90 disabled:opacity-50 shadow"
          style="background: linear-gradient(135deg, #7C3AED, #5B21B6)"
          :disabled="isSavingAgents"
          @click="saveAgents"
        >
          {{ isSavingAgents ? 'Salvando…' : 'Salvar agentes' }}
        </button>
      </div>

      <!-- ══ MODO PROGRAMAÇÃO — painel panorâmico de automações ══ -->
      <div v-else-if="activeTab === 'programacao'" class="max-w-3xl space-y-6">
        <div class="flex items-center justify-between flex-wrap gap-2">
          <p class="text-sm text-n-slate-11">
            Painel panorâmico: <b>tudo</b> que trabalha sozinho no sistema, num lugar só — agentes de IA,
            robôs, réguas e automações de coluna, com a situação de cada um.
          </p>
          <button
            class="text-sm px-3 py-2 rounded-lg bg-yellow-500 text-white hover:bg-yellow-600 flex items-center gap-1.5 flex-shrink-0 font-medium"
            @click="openProgrammingMode"
          >
            ⚡ Abrir Modo Programação no CRM
          </button>
        </div>

        <!-- ✨ Agentes de IA -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide flex items-center gap-1.5">
              <span class="i-lucide-sparkles text-sm" style="color: #7C3AED" />
              Agentes de IA <span class="text-n-slate-9 font-normal normal-case">({{ Object.keys(aiAgents).length }})</span>
            </p>
            <button class="text-xs font-medium text-n-brand hover:underline" @click="activeTab = 'agentes'">configurar →</button>
          </div>
          <div class="grid sm:grid-cols-2 gap-2">
            <button
              v-for="(agent, key) in aiAgents"
              :key="key"
              class="text-left flex items-start gap-2.5 p-3 bg-n-solid-2 border border-n-weak rounded-xl hover:border-n-brand/50 transition-colors"
              @click="activeTab = 'agentes'"
            >
              <span class="w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0" :style="{ background: AGENT_META[key].gradient }">
                <span :class="AGENT_META[key].icon" class="text-white text-sm" />
              </span>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-1.5 flex-wrap">
                  <p class="text-sm font-semibold text-n-slate-12 truncate">{{ AGENT_META[key].title }}</p>
                  <span
                    class="text-[9px] px-1.5 py-0.5 rounded-full font-medium flex-shrink-0"
                    :class="agent.enabled ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-10'"
                  >● {{ agent.enabled ? 'Ligado' : 'Desligado' }}</span>
                </div>
                <p class="text-[11px] text-n-slate-10 truncate">
                  {{ resolvedModel(key, agent) }}<template v-if="key === 'opportunity'"> · {{ agent.watchers.length }} coluna(s) vigiada(s)</template>
                </p>
              </div>
            </button>
          </div>
        </div>

        <!-- 🤖 Robôs de follow-up -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide flex items-center gap-1.5">
              <span class="i-lucide-bot text-sm" style="color: #0F5FA6" />
              Robôs de follow-up <span class="text-n-slate-9 font-normal normal-case">({{ bots.length }})</span>
            </p>
            <button class="text-xs font-medium text-n-brand hover:underline" @click="activeTab = 'robos'">gerenciar →</button>
          </div>
          <p v-if="!bots.length" class="text-xs text-n-slate-9 pl-1">Nenhum robô criado.</p>
          <div v-else class="space-y-1.5">
            <button
              v-for="bot in bots"
              :key="bot.id"
              class="w-full text-left flex items-center gap-3 px-3 py-2 bg-n-solid-2 border border-n-weak rounded-xl hover:border-n-brand/50 transition-colors"
              @click="activeTab = 'robos'"
            >
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="bot.active ? 'bg-green-500' : 'bg-n-slate-9'" />
              <p class="text-sm font-medium text-n-slate-12 flex-1 truncate">{{ bot.name }}</p>
              <span class="text-[11px] text-n-slate-10 flex-shrink-0">{{ (bot.steps || []).length }} cutucada(s)</span>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full flex-shrink-0"
                :class="bot.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >{{ bot.active ? 'Ativo' : 'Pausado' }}</span>
            </button>
          </div>
        </div>

        <!-- 📣 Réguas de mensagem -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide flex items-center gap-1.5">
              <span class="i-lucide-megaphone text-sm" style="color: #B8860B" />
              Réguas de mensagem <span class="text-n-slate-9 font-normal normal-case">({{ automations.length }})</span>
            </p>
            <button class="text-xs font-medium text-n-brand hover:underline" @click="goToCampaign">abrir Campanha WhatsApp →</button>
          </div>
          <div v-if="loadingReguas" class="flex justify-center py-4"><Spinner :size="20" class="text-n-brand" /></div>
          <p v-else-if="!automations.length" class="text-xs text-n-slate-9 pl-1">Nenhuma régua criada.</p>
          <div v-else class="space-y-1.5">
            <button
              v-for="a in automations"
              :key="a.id"
              class="w-full text-left flex items-center gap-3 px-3 py-2 bg-n-solid-2 border border-n-weak rounded-xl hover:border-n-brand/50 transition-colors"
              @click="goToCampaign"
            >
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="a.active ? 'bg-green-500' : 'bg-n-slate-9'" />
              <p class="text-sm font-medium text-n-slate-12 flex-1 truncate">{{ a.name }}</p>
              <span v-if="a.trigger_label" class="text-[11px] text-n-slate-10 flex-shrink-0 truncate max-w-32">🏷 {{ a.trigger_label }}</span>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full flex-shrink-0"
                :class="a.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >{{ a.active ? 'Ativa' : 'Pausada' }}</span>
            </button>
          </div>
        </div>

        <!-- ⚡ Automações de coluna -->
        <div>
          <div class="flex items-center justify-between mb-2">
            <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide flex items-center gap-1.5">
              <span class="i-lucide-zap text-sm" style="color: #EAB308" />
              Automações de coluna <span class="text-n-slate-9 font-normal normal-case">({{ columnAutomations.length }})</span>
            </p>
            <button class="text-xs font-medium text-n-brand hover:underline" @click="openProgrammingMode">criar/editar no CRM →</button>
          </div>
          <div v-if="loadingColumnAutomations" class="flex justify-center py-6"><Spinner :size="24" class="text-n-brand" /></div>
          <p v-else-if="!columnAutomations.length" class="text-xs text-n-slate-9 pl-1">Nenhuma automação de coluna ainda.</p>
          <div v-else class="space-y-1.5">
            <div
              v-for="a in columnAutomations"
              :key="a.id"
              class="flex items-center gap-3 px-3 py-2 bg-n-solid-2 border border-n-weak rounded-xl"
            >
              <span class="w-2 h-2 rounded-full flex-shrink-0" :class="a.active ? 'bg-green-500' : 'bg-n-slate-9'" />
              <div class="flex-1 min-w-0">
                <p class="text-sm font-medium text-n-slate-12 truncate">{{ a.name }}</p>
                <p class="text-xs text-n-slate-10 truncate">
                  Coluna "{{ a.stage_name }}" · {{ ACTION_LABELS[a.action_type] || a.action_type }}
                </p>
              </div>
              <span
                class="text-[10px] px-2 py-0.5 rounded-full flex-shrink-0"
                :class="a.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-9'"
              >{{ a.active ? 'Ativa' : 'Pausada' }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ TRATAMENTO DE DADOS ══ -->
      <div v-else-if="activeTab === 'tratamento'" class="max-w-3xl">
        <div class="flex items-center justify-between mb-4 flex-wrap gap-2">
          <p class="text-sm text-n-slate-11">
            Ferramentas de limpeza e enriquecimento em massa da base — rodam com prévia antes de aplicar.
          </p>
          <button
            class="text-sm px-3 py-2 rounded-lg bg-n-brand text-white hover:bg-n-brand/90 flex items-center gap-1.5 flex-shrink-0"
            @click="openTreatment"
          >
            <span class="i-lucide-external-link text-sm" />
            Abrir Tratamento de dados
          </button>
        </div>
        <div class="grid sm:grid-cols-2 gap-4">
          <button
            v-for="tool in TREATMENT_TOOLS"
            :key="tool.title"
            class="text-left rounded-2xl border-2 border-n-weak bg-n-solid-2 p-4 hover:border-n-brand transition-colors"
            @click="openTreatment"
          >
            <span :class="tool.icon" class="text-xl mb-2 block" style="color: #0F5FA6" />
            <p class="text-sm font-bold text-n-slate-12 mb-1">{{ tool.title }}</p>
            <p class="text-xs text-n-slate-10 leading-relaxed">{{ tool.desc }}</p>
          </button>
        </div>
      </div>
    </div>

    <!-- Modal robô (componente compartilhado) -->
    <FollowupBotModal
      v-if="showBotModal"
      :bot="editingBot"
      @close="showBotModal = false"
      @saved="onBotSaved"
    />
    <!-- Janela isolada: Radar PONTUAL (roda uma vez, não fica ativo) -->
    <div
      v-if="showSweepModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showSweepModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #DC2626, #F59E0B)" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-scan-search" style="color: #DC2626" />
            Radar pontual
            <span class="text-[10px] px-2 py-0.5 rounded-full font-semibold bg-n-alpha-2 text-n-slate-11">roda uma vez</span>
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showSweepModal = false" />
        </div>
        <div class="p-5 space-y-4">
          <p class="text-xs text-n-slate-10">
            Varre AGORA os leads aguardando resposta no recorte escolhido e cria
            os avisos no <b>Meu Painel</b> do atendente escolhido, em alguns
            minutos. Diferente do Radar perene, <b>não fica ativo</b> — é uma
            auditoria única. Nada é enviado ao paciente.
          </p>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Coluna</label>
            <select v-model="sweep.stage_id" class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12">
              <option value="">Colunas vigiadas (padrão)</option>
              <option v-for="s in allStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
            </select>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Enviar os avisos para o painel de</label>
            <select v-model="sweep.user_id" class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12">
              <option :value="null">👥 Todos os atendentes</option>
              <option v-for="ag in teamAgents" :key="ag.id" :value="ag.id">{{ ag.available_name || ag.name }}</option>
            </select>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Etiqueta <span class="text-n-slate-9 font-normal">(opcional)</span></label>
            <select v-model="sweep.label" class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12">
              <option value="">Qualquer etiqueta</option>
              <option v-for="l in accountLabels" :key="l.id" :value="l.title">{{ l.title }}</option>
            </select>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Período (mensagens aguardando das…)</label>
            <select v-model.number="sweep.since_hours" class="w-full border border-n-weak rounded-lg px-2 py-2 text-sm bg-n-solid-2 text-n-slate-12">
              <option :value="6">últimas 6 horas</option>
              <option :value="24">últimas 24 horas</option>
              <option :value="72">últimos 3 dias</option>
              <option :value="168">últimos 7 dias</option>
            </select>
          </div>
        </div>
        <div class="px-5 py-4 border-t border-n-weak flex gap-2">
          <button
            class="flex-1 flex items-center justify-center gap-1.5 text-sm font-semibold text-white py-2 rounded-lg disabled:opacity-50"
            style="background: linear-gradient(135deg, #DC2626, #F59E0B)"
            :disabled="isSweeping"
            @click="runSweep"
          >
            <span :class="isSweeping ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-scan-search'" class="text-sm" />
            {{ isSweeping ? 'Iniciando…' : 'Varrer agora' }}
          </button>
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showSweepModal = false">
            Fechar
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
