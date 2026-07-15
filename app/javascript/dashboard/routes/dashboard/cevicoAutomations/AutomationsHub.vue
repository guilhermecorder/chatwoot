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

const TABS = ['robos', 'agentes', 'programacao', 'resultados', 'tratamento'];
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
  conversation: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  form: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  scheduler: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  opportunity: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', watchers: [], wait_minutes: 10 },
  closing: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  nps: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  sales: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
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

// ── Colunas onde o Secretário da Agenda ATUA ──
// Cada coluna marcada ganha (por baixo) uma automação "card entrou →
// anotar na Agenda", criada/removida automaticamente pelo endpoint de sync.
const schedulerStageIds = ref([]);
const isSavingSchedulerStages = ref(false);

const toggleSchedulerStage = id => {
  const idx = schedulerStageIds.value.indexOf(id);
  if (idx >= 0) schedulerStageIds.value.splice(idx, 1);
  else schedulerStageIds.value.push(id);
};

const saveSchedulerStages = async () => {
  isSavingSchedulerStages.value = true;
  try {
    const { data } = await CrmAPI.syncSchedulerStages(schedulerStageIds.value);
    schedulerStageIds.value = data.scheduler_stage_ids || [];
    useAlert('Colunas do Secretário salvas — já está valendo (com o agente LIGADO).');
  } catch {
    useAlert('Erro ao salvar as colunas do Secretário.');
  } finally {
    isSavingSchedulerStages.value = false;
  }
};

// colunas de atuação dos DEMAIS agentes de coluna (Analista, Monitor de
// Fechamento, NPS) — mesma mecânica do Secretário, endpoint genérico
const STAGE_AGENTS = ['conversation', 'closing', 'nps'];
const agentStageIds = ref({ conversation: [], closing: [], nps: [] });
const savingAgentStages = ref('');
const toggleAgentStage = (agent, id) => {
  const list = agentStageIds.value[agent];
  const idx = list.indexOf(id);
  if (idx >= 0) list.splice(idx, 1);
  else list.push(id);
};
const saveAgentStages = async agent => {
  savingAgentStages.value = agent;
  try {
    const { data } = await CrmAPI.syncAgentStages(agent, agentStageIds.value[agent]);
    agentStageIds.value[agent] = data.stage_ids || [];
    useAlert(`Colunas de ${AGENT_META[agent].title} salvas — valendo com o agente LIGADO.`);
  } catch {
    useAlert('Erro ao salvar as colunas.');
  } finally {
    savingAgentStages.value = '';
  }
};

// 💼 insights comerciais do Consultor Comercial (gestão)
const salesInsights = () => settings.value?.ai?.sales_insights || null;
const isGeneratingInsights = ref(false);
const generateSalesInsights = async () => {
  if (isGeneratingInsights.value) return;
  isGeneratingInsights.value = true;
  try {
    const { data } = await CrmAPI.generateSalesInsights();
    useAlert(data.message || 'Análise iniciada!');
    setTimeout(async () => {
      await store.dispatch('crm/fetchSettings');
      isGeneratingInsights.value = false;
    }, 90000);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao iniciar a análise.');
    isGeneratingInsights.value = false;
  }
};

// registro de atividade do Secretário (últimas leituras — entender os números)
const schedulerLog = () => settings.value?.scheduler_log || [];
const showSchedulerLog = ref(false);
const SCHEDULER_OUTCOMES = {
  created: { label: 'criada', class: 'bg-green-500/15 text-green-600' },
  rescheduled: { label: 'reagendada', class: 'bg-amber-500/15 text-amber-600' },
  already: { label: 'já existia', class: 'bg-n-alpha-2 text-n-slate-10' },
  skipped: { label: 'sem dia/hora', class: 'bg-red-500/10 text-red-500' },
};
const fmtLogDate = iso =>
  iso ? new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) : '—';

// ── Preencher a Agenda com o histórico (Agente de Agendamento) ──
// Varre conversas com confirmação de agendamento e registra as consultas na
// Agenda do sistema — "duplica" a agenda do Google SEM mexer no bot do N8N.
const showBackfillModal = ref(false);
const backfill = ref({ since_days: 90, limit: 100 });
const isBackfilling = ref(false);
const backfillLastRun = () => settings.value?.agenda_backfill_last_run || null;

const runBackfill = async () => {
  isBackfilling.value = true;
  try {
    const { data } = await CrmAPI.agendaBackfill({
      since_days: backfill.value.since_days,
      limit: backfill.value.limit,
    });
    useAlert(data.message || 'Preenchimento iniciado!');
    showBackfillModal.value = false;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao iniciar o preenchimento.');
  } finally {
    isBackfilling.value = false;
  }
};

// ── Editar | Salvar (rascunho) | Publicar por agente ──
// Os cards abrem TRAVADOS (leitura). Editar destrava; Salvar guarda um
// RASCUNHO que NÃO muda o agente no ar; Publicar é o que passa a valer.
const editingAgent = ref({});
const savingAgent = ref('');
// valores carregados por agente (para o Descartar voltar atrás)
const loadedValues = ref({});

const snapshotAgent = key => {
  const a = aiAgents.value[key];
  const snap = { prompt: a.prompt, model: a.model, effort: a.effort };
  if (key === 'opportunity') {
    snap.watchers = JSON.parse(JSON.stringify(a.watchers || []));
    snap.wait_minutes = a.wait_minutes;
  }
  return snap;
};

const startEdit = key => {
  loadedValues.value[key] = snapshotAgent(key);
  editingAgent.value = { ...editingAgent.value, [key]: true };
};

const discardEdit = key => {
  const snap = loadedValues.value[key];
  if (snap) {
    const a = aiAgents.value[key];
    a.prompt = snap.prompt;
    a.model = snap.model;
    a.effort = snap.effort;
    if (key === 'opportunity') {
      a.watchers = JSON.parse(JSON.stringify(snap.watchers || []));
      a.wait_minutes = snap.wait_minutes;
    }
  }
  editingAgent.value = { ...editingAgent.value, [key]: false };
};

// monta os campos de config do agente (sem o enabled — esse é do interruptor)
const packAgentFields = key => {
  const a = aiAgents.value[key];
  const fields = { prompt: (a.prompt || '').trim(), model: a.model, effort: a.effort };
  if (key === 'opportunity') {
    fields.watchers = (a.watchers || [])
      .filter(w => w.stage_id)
      .map(w => ({
        stage_id: Number(w.stage_id),
        user_id: w.user_id || null,
        lookback_hours: Number(w.lookback_hours) || 24,
      }));
    fields.wait_minutes = Number(a.wait_minutes) || 10;
  }
  return fields;
};

// SALVAR = rascunho: guarda no banco mas o agente continua usando a
// configuração publicada
const saveAgentDraft = async key => {
  savingAgent.value = key;
  try {
    await CrmAPI.updateAi({ agents: { [key]: { draft: packAgentFields(key) } } });
    aiAgents.value[key].has_draft = true;
    editingAgent.value = { ...editingAgent.value, [key]: false };
    useAlert(`💾 Rascunho de ${AGENT_META[key].title} salvo — ainda NÃO está valendo. Publique quando quiser aplicar.`);
  } catch {
    useAlert('Erro ao salvar o rascunho.');
  } finally {
    savingAgent.value = '';
  }
};

// PUBLICAR = aplica de verdade (e limpa o rascunho)
const publishAgent = async key => {
  savingAgent.value = key;
  try {
    await CrmAPI.updateAi({ agents: { [key]: { ...packAgentFields(key), draft: {} } } });
    aiAgents.value[key].has_draft = false;
    editingAgent.value = { ...editingAgent.value, [key]: false };
    loadedValues.value[key] = snapshotAgent(key);
    useAlert(`🚀 ${AGENT_META[key].title} publicado — vale a partir das próximas análises.`);
  } catch {
    useAlert('Erro ao publicar o agente.');
  } finally {
    savingAgent.value = '';
  }
};

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
    description: 'Lê a conversa e devolve, numa análise só: indicador de interesse (alto/médio/baixo/perdido), resumo, próximo passo, a ETAPA DO SCRIPT CEVICO em que o paciente está e 2-3 FRASES PRONTAS para a atendente copiar e usar.',
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
    title: 'Secretário da Agenda',
    icon: 'i-lucide-calendar-plus',
    gradient: 'linear-gradient(135deg, #B8860B, #D4A017)',
    color: '#B8860B',
    tag: 'Agenda',
    description: 'Lê a conversa e ANOTA a consulta na Agenda do sistema: nome, telefone, dia, hora, médico, unidade, valor e observações. Entende reagendamento (atualiza a consulta existente). NUNCA fala com o paciente — quem conversa é o Atendente IA (N8N).',
    triggers: [
      { icon: 'i-lucide-zap', label: 'Card entra nas colunas escolhidas abaixo' },
      { icon: 'i-lucide-calendar-days', label: 'Anota/reagenda na Agenda do sistema' },
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
  closing: {
    title: 'Monitor de Fechamento',
    icon: 'i-lucide-hand-coins',
    gradient: 'linear-gradient(135deg, #065F46, #10B981)',
    color: '#065F46',
    tag: 'Cirurgias',
    description: 'Lê a conversa quando o card entra na coluna escolhida e registra o FECHAMENTO da cirurgia: valor fechado, forma de pagamento e data combinada. Preenche o valor do card (se vazio) e o 💰 aparece na Agenda de Cirurgias — visível só para admin.',
    triggers: [
      { icon: 'i-lucide-zap', label: 'Ação de coluna "Adicionar agente de IA" → Monitor de Fechamento' },
      { icon: 'i-lucide-wallet', label: 'Valor + forma de pagamento gravados no contato' },
      { icon: 'i-lucide-calendar-days', label: 'Valor visível na conferência da Agenda de Cirurgias (admin)' },
    ],
    suggestion: 'Extração estruturada — Sonnet no esforço médio.',
  },
  sales: {
    title: 'Consultor Comercial',
    icon: 'i-lucide-handshake',
    gradient: 'linear-gradient(135deg, #065F46, #34D399)',
    color: '#047857',
    tag: 'Fechamento',
    description: 'Dois papéis: AO VIVO, o botão "💼 Ajuda com objeção" no painel da conversa identifica o que está travando o paciente e sugere respostas prontas no tom CEVICO para a vendedora. Para a GESTÃO, analisa as conversas que geraram fechamento de cirurgia e produz insights comerciais (o que funciona, objeções vencidas, recomendações).',
    triggers: [
      { icon: 'i-lucide-handshake', label: 'Botão "💼 Ajuda com objeção" no painel da conversa' },
      { icon: 'i-lucide-lightbulb', label: 'Botão "Gerar insights comerciais" abaixo (gestão)' },
      { icon: 'i-lucide-shield', label: 'Nunca fala com o paciente — quem decide e envia é a vendedora' },
    ],
    suggestion: 'Leitura fina de vendas — Opus no esforço alto vale o custo.',
  },
  nps: {
    title: 'Agente de NPS',
    icon: 'i-lucide-smile',
    gradient: 'linear-gradient(135deg, #0D9488, #2DD4BF)',
    color: '#0D9488',
    tag: 'Satisfação',
    description: 'Lê a conversa do pós-operatório e identifica a NOTA (0-10) que o paciente deu. Etiqueta o contato com a faixa (nps-9-10 / nps-7-8 / nps-0-6) — o Dashboard CRM e o painel do Gestor mostram a % de satisfação a partir daí.',
    triggers: [
      { icon: 'i-lucide-zap', label: 'Ação de coluna "Adicionar agente de IA" → Agente de NPS (ex.: coluna Pós-Operatório)' },
      { icon: 'i-lucide-tags', label: 'Etiquetas nps-9-10 / nps-7-8 / nps-0-6 no contato' },
      { icon: 'i-lucide-bar-chart-3', label: 'Bloco "Satisfação (NPS)" no Dashboard CRM' },
    ],
    suggestion: 'Ler uma nota é simples — Haiku resolve baratinho.',
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
  // se há rascunho salvo, os CAMPOS mostram o rascunho (continuar de onde
  // parou); o agente no ar continua usando a config publicada até Publicar
  const load = key => {
    const draft = a[key]?.draft || null;
    return {
      // opt-in: agente só aparece LIGADO se foi ligado de propósito
      enabled: a[key]?.enabled === true,
      prompt: (draft ? draft.prompt : a[key]?.prompt) || '',
      model: (draft ? draft.model : a[key]?.model) || '',
      effort: (draft ? draft.effort : a[key]?.effort) || '',
      has_draft: !!draft,
      default_prompt: a[key]?.default_prompt || '',
    };
  };
  // compat: config antiga (stage_ids soltos) vira vigia sem direcionamento
  const legacyWatchers = (a.opportunity?.stage_ids || []).map(id => ({
    stage_id: id,
    user_id: null,
    lookback_hours: a.opportunity?.lookback_hours || 24,
  }));
  const oppDraft = a.opportunity?.draft || null;
  aiAgents.value = {
    conversation: load('conversation'),
    form: load('form'),
    scheduler: load('scheduler'),
    closing: load('closing'),
    nps: load('nps'),
    sales: load('sales'),
    opportunity: {
      ...load('opportunity'),
      watchers: oppDraft?.watchers?.length
        ? oppDraft.watchers
        : (a.opportunity?.watchers?.length ? a.opportunity.watchers : legacyWatchers),
      wait_minutes: (oppDraft?.wait_minutes || a.opportunity?.wait_minutes) || 10,
    },
  };
  Object.keys(aiAgents.value).forEach(key => {
    loadedValues.value[key] = snapshotAgent(key);
  });
  schedulerStageIds.value = [...(settings.value?.scheduler_stage_ids || [])];
  const saved = settings.value?.agent_stage_ids || {};
  STAGE_AGENTS.forEach(a => {
    agentStageIds.value[a] = [...(saved[a] || [])];
  });
  // relatório de gastos + colunas para o Radar (em paralelo)
  loadStages().catch(() => {});
  CrmAPI.getAiUsage()
    .then(({ data }) => { aiUsage.value = data; })
    .catch(() => {});
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
  schedule_appointment: 'IA: Secretário da Agenda',
  set_value: 'Adicionar preço no card',
};

const openProgrammingMode = () => {
  window.location.href = `/app/accounts/${accountId.value}/crm?programming=1`;
};

// ── Resultados das automações (dashboard com presets de período) ──
const RESULT_PERIODS = [
  { key: 'today', label: 'Hoje' },
  { key: 'yesterday', label: 'Ontem' },
  { key: 'week', label: 'Essa semana' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
];
const resultsPeriod = ref('today');
const resultsData = ref(null);
const loadingResults = ref(false);

const TRIGGER_LABELS = {
  card_entered: 'Card entrou na coluna',
  card_left: 'Card saiu da coluna',
  card_stalled: 'Card parado por X tempo',
  label_added: 'Etiqueta adicionada',
  label_removed: 'Etiqueta removida',
  message_created: 'Mensagem criada',
  value_added: 'Valor adicionado no card',
};

const loadResults = async () => {
  loadingResults.value = true;
  try {
    const { data } = await CrmAPI.getAutomationsDashboard({ preset: resultsPeriod.value });
    resultsData.value = data;
  } catch {
    resultsData.value = null;
    useAlert('Erro ao carregar os resultados das automações.');
  } finally {
    loadingResults.value = false;
  }
};

const setResultsPeriod = key => {
  resultsPeriod.value = key;
  loadResults();
};

// carrega quando a aba abre pela primeira vez
watch(activeTab, tab => {
  if (tab === 'resultados' && !resultsData.value && !loadingResults.value) loadResults();
});

const maxTimelineFired = () =>
  Math.max(1, ...(resultsData.value?.timeline || []).map(d => d.fired));

const fmtDay = iso => {
  const [, m, d] = iso.split('-');
  return `${d}/${m}`;
};

const fmtLastFired = iso => {
  if (!iso) return 'nunca no período';
  return new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
  });
};

// ── Tratamento de dados (atalhos conectados) ──
const TREATMENT_TOOLS = [
  { icon: 'i-lucide-move', title: 'Mover e etiquetar em LOTE', desc: 'Filtre cards por coluna, valor, caixa de entrada ou etiqueta → mova todos de coluna e/ou adicione etiqueta (nunca duplica). Ex: COM valor em Novos Contatos → Envio de Orçamento.' },
  { icon: 'i-lucide-tag', title: 'Etiquetar e/ou mover por conteúdo', desc: 'Se a conversa contém X, ou Y, ou Z → aplica etiqueta e/ou MOVE o card de coluna (etiqueta opcional — dá para só mover). Busca em massa no histórico.' },
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

// registro de atividade do robô — mostra por que ele está (ou não) enviando
const expandedBotLog = ref(null);
const REASON_LABELS = {
  aguardando_prazo: 'aguardando o prazo da cutucada',
  paciente_falou_ultimo: 'paciente falou por último (vez do atendimento)',
  cadencia_completa: 'já recebeu todas as cutucadas',
  etiquetas: 'barrado pelo filtro de etiquetas',
  erro: 'erro ao enviar',
};
const reasonLine = run =>
  Object.entries(run?.reasons || {})
    .map(([k, v]) => `${v} ${REASON_LABELS[k] || k}`)
    .join(' · ');
// por que o robô pode estar parado — aviso bem visível no card
const botWarning = bot => {
  if (bot.window_status === 'janela_encerrada')
    return `⏸ A data "para em" já passou (${fmtLogDate(bot.ends_at)}) — o robô NÃO está enviando nada. Edite o robô e limpe ou estenda a janela.`;
  if (bot.window_status === 'ainda_nao_comecou')
    return `⏳ A janela "começa em" ainda não chegou (${fmtLogDate(bot.starts_at)}) — o robô só envia a partir dela.`;
  return '';
};

// unidade correta por etapa: minutos ÷ 60, dias × 24 (igual ao backend)
const delayLabel = step => {
  let hours;
  if (step.delay_value != null) {
    const v = Number(step.delay_value);
    if (step.delay_unit === 'days') hours = v * 24;
    else if (step.delay_unit === 'minutes') hours = v / 60;
    else hours = v;
  } else {
    hours = Number(step.delay_hours);
  }
  if (hours < 1) return `${Math.round(hours * 60)}min`;
  if (hours < 24) return `${Math.round(hours * 10) / 10}h`;
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
          :class="activeTab === 'resultados' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'resultados' ? { background: 'linear-gradient(135deg, #65A30D, #84CC16)' } : {}"
          @click="activeTab = 'resultados'"
        >📊 Resultados</button>
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

            <!-- aviso quando a janela parou o robô (causa silenciosa nº 1) -->
            <div
              v-if="bot.active && botWarning(bot)"
              class="mt-2 text-xs rounded-lg px-3 py-2 font-medium"
              style="background: rgba(217, 119, 6, 0.1); color: #b45309; border: 1px solid rgba(217, 119, 6, 0.35)"
            >
              {{ botWarning(bot) }}
            </div>

            <!-- última rodada + registro de atividade -->
            <div class="mt-2 flex items-center gap-2 flex-wrap text-[11px] text-n-slate-10">
              <template v-if="bot.activity?.last_run">
                <span>
                  Última rodada {{ fmtLogDate(bot.activity.last_run.at) }} ·
                  <template v-if="bot.activity.last_run.status === 'fora_da_janela'">fora da janela (não enviou)</template>
                  <template v-else>
                    {{ bot.activity.last_run.candidates }} conversa(s) na mira ·
                    <b :class="bot.activity.last_run.sent ? 'text-green-600' : ''">{{ bot.activity.last_run.sent }} enviada(s)</b>
                  </template>
                </span>
                <span v-if="reasonLine(bot.activity.last_run)" class="text-n-slate-9">{{ reasonLine(bot.activity.last_run) }}</span>
              </template>
              <span v-else>Sem rodadas registradas ainda (o registro começa após esta atualização).</span>
              <button
                v-if="bot.activity?.events?.length"
                class="text-n-brand font-medium hover:underline"
                @click="expandedBotLog = expandedBotLog === bot.id ? null : bot.id"
              >
                📒 Registro de atividade ({{ bot.activity.events.length }})
              </button>
            </div>
            <div v-if="expandedBotLog === bot.id && bot.activity?.events?.length" class="mt-2 rounded-lg bg-n-alpha-1 divide-y divide-n-weak">
              <div v-for="(ev, i) in bot.activity.events" :key="i" class="px-3 py-1.5 text-[11px] flex items-center gap-2">
                <span>{{ ev.type === 'sent' ? '✉️' : '⚠️' }}</span>
                <span class="text-n-slate-9 flex-shrink-0">{{ fmtLogDate(ev.at) }}</span>
                <span class="text-n-slate-11 truncate">{{ ev.contact || 'Contato' }} · conversa #{{ ev.conversation_id }}</span>
                <span class="text-n-slate-10 truncate">{{ ev.type === 'sent' ? ev.note : `erro: ${ev.note}` }}</span>
              </div>
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
                  <span
                    v-if="agent.has_draft"
                    class="text-[10px] px-2 py-0.5 rounded-full font-medium bg-amber-500/15 text-amber-600"
                    title="Existe um rascunho salvo que ainda NÃO está valendo — clique em Publicar para aplicar"
                  >
                    📝 Rascunho não publicado
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
                <span class="text-[9px] text-n-slate-9">salva na hora</span>
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
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-2" :class="!editingAgent[key] ? 'opacity-70' : ''">
              <div>
                <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Modelo de IA</label>
                <select
                  v-model="agent.model"
                  :disabled="!editingAgent[key]"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 disabled:cursor-not-allowed"
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
                  :disabled="!editingAgent[key]"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 disabled:cursor-not-allowed"
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
                  :disabled="!editingAgent[key]"
                  class="w-16 border border-n-weak rounded-lg px-2 py-1 text-sm bg-n-solid-2 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
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
                          :disabled="!editingAgent[key]"
                          class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                        >
                          <option value="" disabled>Escolha a coluna…</option>
                          <option v-for="s in allStages" :key="s.id" :value="s.id">{{ s.name }} ({{ s.pipeline }})</option>
                        </select>
                      </div>
                      <div class="flex-1 min-w-0">
                        <label class="text-[10px] font-medium text-n-slate-9 block mb-0.5">Avisar no painel de</label>
                        <select
                          v-model="w.user_id"
                          :disabled="!editingAgent[key]"
                          class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                        >
                          <option :value="null">👥 Todos os atendentes</option>
                          <option v-for="ag in teamAgents" :key="ag.id" :value="ag.id">{{ ag.available_name || ag.name }}</option>
                        </select>
                      </div>
                      <div class="flex-1 min-w-0">
                        <label class="text-[10px] font-medium text-n-slate-9 block mb-0.5">Olhando o movimento das</label>
                        <select
                          v-model.number="w.lookback_hours"
                          :disabled="!editingAgent[key]"
                          class="w-full border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-1 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                        >
                          <option v-for="o in LOOKBACK_OPTIONS" :key="o.value" :value="o.value">{{ o.label }}</option>
                        </select>
                      </div>
                      <button
                        v-if="editingAgent[key]"
                        class="text-n-slate-9 hover:text-red-500 i-lucide-trash-2 text-sm flex-shrink-0 self-end sm:self-auto sm:mb-2"
                        title="Remover esta vigia"
                        @click="removeWatcher(wi)"
                      />
                    </div>
                  </div>
                  <button
                    v-if="editingAgent[key]"
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

            <!-- Consultor Comercial: insights p/ a gestão -->
            <div v-if="key === 'sales'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-2">
              <div class="flex items-center gap-2 flex-wrap">
                <p class="text-xs font-medium text-n-slate-11 flex-1">
                  💡 Insights comerciais
                  <span class="text-n-slate-9 font-normal">(analisa as conversas que FECHARAM cirurgia — alimentadas pelo Monitor de Fechamento)</span>
                </p>
                <button
                  class="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50"
                  :style="{ background: AGENT_META.sales.gradient }"
                  :disabled="isGeneratingInsights"
                  @click="generateSalesInsights"
                >
                  {{ isGeneratingInsights ? 'Analisando… (1-2 min)' : 'Gerar insights comerciais' }}
                </button>
              </div>
              <div v-if="salesInsights()?.text" class="rounded-lg bg-n-alpha-1 p-3 max-h-72 overflow-y-auto">
                <p class="text-[10px] text-n-slate-9 mb-1.5">
                  {{ salesInsights().conversations }} conversa(s) analisada(s) · {{ fmtLogDate(salesInsights().generated_at) }}
                </p>
                <pre class="text-[11px] text-n-slate-11 whitespace-pre-wrap font-sans leading-relaxed">{{ salesInsights().text }}</pre>
              </div>
              <p v-else-if="salesInsights()?.error" class="text-[11px] text-amber-600">⚠️ {{ salesInsights().error }}</p>
            </div>

            <!-- Colunas de atuação (Analista / Monitor de Fechamento / NPS) -->
            <div v-if="STAGE_AGENTS.includes(key)" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-2">
              <p class="text-xs font-medium text-n-slate-11">
                Colunas de atuação
                <span class="text-n-slate-9 font-normal">
                  (card entrou na coluna → o agente lê a conversa
                  <template v-if="key === 'closing'">; sugestão: as colunas de "Indicação de Cirurgia"</template>
                  <template v-else-if="key === 'nps'">; sugestão: a coluna de Pós-Operatório</template>)
                </span>
              </p>
              <div v-if="!allStages.length" class="text-xs text-n-slate-9">Carregando colunas…</div>
              <div v-else class="flex flex-wrap gap-1.5">
                <button
                  v-for="st in allStages"
                  :key="st.id"
                  class="text-[11px] font-medium px-2.5 py-1 rounded-full border transition-colors"
                  :class="agentStageIds[key].includes(st.id)
                    ? 'text-white border-transparent'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                  :style="agentStageIds[key].includes(st.id) ? { background: AGENT_META[key].gradient } : {}"
                  @click="toggleAgentStage(key, st.id)"
                >
                  {{ st.name }}
                </button>
              </div>
              <button
                class="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50"
                :style="{ background: AGENT_META[key].gradient }"
                :disabled="savingAgentStages === key"
                @click="saveAgentStages(key)"
              >
                {{ savingAgentStages === key ? 'Salvando…' : 'Salvar colunas de atuação' }}
              </button>
            </div>

            <!-- Config do Secretário da Agenda -->
            <div v-if="key === 'scheduler'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
                📥 Anota consultas na Agenda do sistema lendo as conversas — <b>nunca fala com o
                paciente</b> (quem conversa é o Atendente IA do N8N). Roda quando um card ENTRA nas
                colunas escolhidas abaixo; reagendamentos atualizam a consulta existente.
              </div>

              <!-- Colunas onde o Secretário atua -->
              <div>
                <p class="text-xs font-medium text-n-slate-11 mb-1.5">
                  Colunas onde o Secretário atua
                  <span class="text-n-slate-9 font-normal">(card entrou → lê a conversa e anota na Agenda; nenhuma marcada = só manual)</span>
                </p>
                <div v-if="!allStages.length" class="text-xs text-n-slate-9">Carregando colunas…</div>
                <div v-else class="flex flex-wrap gap-1.5">
                  <button
                    v-for="s in allStages"
                    :key="s.id"
                    class="text-[11px] font-medium px-2.5 py-1 rounded-lg border transition-colors"
                    :class="schedulerStageIds.includes(s.id)
                      ? 'text-white border-transparent'
                      : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                    :style="schedulerStageIds.includes(s.id) ? { background: 'linear-gradient(135deg, #B8860B, #D4A017)' } : {}"
                    @click="toggleSchedulerStage(s.id)"
                  >
                    {{ s.name }}
                  </button>
                </div>
                <button
                  class="mt-2 text-xs font-semibold text-white px-3 py-1.5 rounded-lg hover:opacity-90 disabled:opacity-50"
                  style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                  :disabled="isSavingSchedulerStages"
                  @click="saveSchedulerStages"
                >
                  {{ isSavingSchedulerStages ? 'Salvando…' : 'Salvar colunas de atuação' }}
                </button>
              </div>

              <!-- Preencher com o histórico -->
              <div class="flex items-center gap-2 flex-wrap border-t border-n-weak pt-3">
                <button
                  class="flex items-center gap-1.5 text-xs font-semibold text-white px-3 py-2 rounded-lg hover:opacity-90"
                  style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                  @click="showBackfillModal = true"
                >
                  <span class="i-lucide-calendar-search text-xs" />
                  Preencher agenda com o histórico…
                </button>
                <span v-if="backfillLastRun()" class="text-[11px] text-n-slate-10">
                  Última varredura: {{ backfillLastRun().scanned }} conversas ·
                  {{ backfillLastRun().created || 0 }} criadas · {{ backfillLastRun().rescheduled || 0 }} reagendadas ·
                  {{ backfillLastRun().already || 0 }} já existiam
                </span>
              </div>

              <!-- Registro de atividade: cada leitura vira uma linha -->
              <div class="border-t border-n-weak pt-3">
                <button
                  class="flex items-center gap-1.5 text-xs font-medium text-n-slate-11 hover:text-n-brand"
                  @click="showSchedulerLog = !showSchedulerLog"
                >
                  <span :class="showSchedulerLog ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'" class="text-xs" />
                  📒 Registro de atividade ({{ schedulerLog().length }} última(s) leitura(s))
                </button>
                <div v-if="showSchedulerLog" class="mt-2 space-y-1 max-h-56 overflow-y-auto pr-1">
                  <p v-if="!schedulerLog().length" class="text-xs text-n-slate-9">
                    Nenhuma leitura ainda — as linhas aparecem aqui conforme o Secretário trabalhar.
                  </p>
                  <div
                    v-for="(entry, i) in schedulerLog()"
                    :key="i"
                    class="flex items-center gap-2 text-[11px] text-n-slate-11 rounded-lg bg-n-solid-2 border border-n-weak px-2.5 py-1.5 flex-wrap"
                  >
                    <span class="text-n-slate-9">{{ fmtLogDate(entry.at) }}</span>
                    <span class="font-medium text-n-slate-12 truncate max-w-[160px]">{{ entry.name }}</span>
                    <span v-if="entry.when" class="text-n-slate-10">→ consulta {{ fmtLogDate(entry.when) }}</span>
                    <span
                      class="text-[10px] px-1.5 py-0.5 rounded-full font-semibold ml-auto"
                      :class="(SCHEDULER_OUTCOMES[entry.outcome] || {}).class"
                    >
                      {{ (SCHEDULER_OUTCOMES[entry.outcome] || {}).label || entry.outcome }}
                    </span>
                  </div>
                </div>
              </div>
            </div>

            <label class="text-xs font-medium text-n-slate-11 block mb-1.5">
              Prompt do agente <span class="text-n-slate-9 font-normal">(vazio = usa o prompt padrão abaixo)</span>
            </label>
            <textarea
              v-model="agent.prompt"
              rows="4"
              :disabled="!editingAgent[key]"
              class="w-full border border-n-weak rounded-xl px-3 py-2.5 text-xs bg-n-solid-1 text-n-slate-12 font-mono leading-relaxed disabled:opacity-70 disabled:cursor-not-allowed"
              :placeholder="agent.default_prompt"
            />

            <!-- EDITAR | SALVAR (rascunho) | PUBLICAR -->
            <div class="flex items-center gap-2 flex-wrap mt-3 pt-3 border-t border-n-weak">
              <button
                v-if="!editingAgent[key]"
                class="flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-brand transition-colors"
                @click="startEdit(key)"
              >
                <span class="i-lucide-pencil text-xs" />
                Editar
              </button>
              <template v-else>
                <button
                  class="flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg border border-amber-500/50 text-amber-600 hover:bg-amber-500/10 transition-colors disabled:opacity-50"
                  :disabled="savingAgent === key"
                  title="Guarda as mudanças SEM aplicar — o agente continua como está até você publicar"
                  @click="saveAgentDraft(key)"
                >
                  <span :class="savingAgent === key ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-save'" class="text-xs" />
                  Salvar rascunho
                </button>
                <button
                  class="flex items-center gap-1.5 text-xs font-semibold text-white px-3 py-2 rounded-lg hover:opacity-90 disabled:opacity-50 shadow"
                  :style="{ background: AGENT_META[key].gradient }"
                  :disabled="savingAgent === key"
                  title="Aplica de verdade — vale nas próximas análises"
                  @click="publishAgent(key)"
                >
                  <span :class="savingAgent === key ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-rocket'" class="text-xs" />
                  Publicar
                </button>
                <button
                  class="text-xs text-n-slate-9 hover:text-n-slate-11 px-2 py-2"
                  :disabled="savingAgent === key"
                  @click="discardEdit(key)"
                >
                  Descartar mudanças
                </button>
              </template>
              <button
                v-if="!editingAgent[key] && agent.has_draft"
                class="flex items-center gap-1.5 text-xs font-semibold text-white px-3 py-2 rounded-lg hover:opacity-90 disabled:opacity-50 shadow"
                :style="{ background: AGENT_META[key].gradient }"
                :disabled="savingAgent === key"
                title="Publica o rascunho salvo — vale nas próximas análises"
                @click="publishAgent(key)"
              >
                <span :class="savingAgent === key ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-rocket'" class="text-xs" />
                Publicar rascunho
              </button>
              <span class="text-[10px] text-n-slate-9 ml-auto">
                Salvar = guarda sem aplicar · Publicar = passa a valer · interruptor liga/desliga na hora
              </span>
            </div>
          </div>
        </div>
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
      <!-- ══ RESULTADOS — dashboard das automações de coluna ══ -->
      <div v-else-if="activeTab === 'resultados'" class="max-w-3xl space-y-5">
        <p class="text-sm text-n-slate-11">
          Quantas vezes cada automação de coluna trabalhou no período — disparos, falhas e
          pacientes alcançados. Réguas de mensagem têm resultados na Campanha WhatsApp.
        </p>

        <!-- Presets de período (mesmos do Meu Painel) -->
        <div class="flex items-center bg-n-solid-2 border border-n-weak rounded-xl p-0.5 gap-0.5 w-fit max-w-full overflow-x-auto">
          <button
            v-for="p in RESULT_PERIODS"
            :key="p.key"
            class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
            :class="resultsPeriod === p.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="resultsPeriod === p.key ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="setResultsPeriod(p.key)"
          >
            {{ p.label }}
          </button>
        </div>

        <div v-if="loadingResults" class="flex items-center gap-2 text-sm text-n-slate-10 py-8">
          <Spinner class="w-4 h-4" /> Carregando resultados…
        </div>

        <template v-else-if="resultsData">
          <!-- KPIs -->
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #0F5FA6, #0B4A82)">
              <p class="text-[11px] font-medium text-white/80">Disparos</p>
              <p class="text-xl font-bold leading-tight">{{ resultsData.totals.fired }}</p>
            </div>
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
              <p class="text-[11px] font-medium text-white/80">Pacientes alcançados</p>
              <p class="text-xl font-bold leading-tight">{{ resultsData.totals.contacts }}</p>
            </div>
            <div class="rounded-xl px-4 py-3 text-white shadow" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
              <p class="text-[11px] font-medium text-white/80">Automações ativas</p>
              <p class="text-xl font-bold leading-tight">{{ resultsData.totals.active_automations }}</p>
            </div>
            <div
              class="rounded-xl px-4 py-3 shadow"
              :class="resultsData.totals.failed ? 'text-white' : 'bg-n-solid-1 border border-n-weak'"
              :style="resultsData.totals.failed ? { background: 'linear-gradient(135deg, #DC2626, #F59E0B)' } : {}"
            >
              <p class="text-[11px] font-medium" :class="resultsData.totals.failed ? 'text-white/80' : 'text-n-slate-10'">Falhas</p>
              <p class="text-xl font-bold leading-tight" :class="resultsData.totals.failed ? '' : 'text-n-slate-12'">{{ resultsData.totals.failed }}</p>
            </div>
          </div>

          <!-- Disparos por dia -->
          <div v-if="resultsData.timeline.length > 1" class="rounded-2xl border-2 border-n-weak bg-n-solid-2 p-4">
            <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-3">Disparos por dia</p>
            <div class="flex items-end gap-1 h-24 overflow-x-auto">
              <div
                v-for="d in resultsData.timeline"
                :key="d.date"
                class="flex flex-col items-center gap-1 flex-1 min-w-[22px]"
                :title="`${fmtDay(d.date)}: ${d.fired} disparo(s)`"
              >
                <span class="text-[9px] text-n-slate-10 leading-none">{{ d.fired || '' }}</span>
                <div
                  class="w-full rounded-t-md"
                  :style="{
                    height: `${Math.max(d.fired ? 8 : 2, (d.fired / maxTimelineFired()) * 64)}px`,
                    background: d.fired ? 'linear-gradient(180deg, #7C3AED, #0F5FA6)' : 'rgba(148,163,184,0.25)',
                  }"
                />
                <span class="text-[8px] text-n-slate-9 leading-none whitespace-nowrap">{{ fmtDay(d.date) }}</span>
              </div>
            </div>
          </div>

          <!-- Ranking por automação -->
          <div class="rounded-2xl border-2 border-n-weak bg-n-solid-2 p-4">
            <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide mb-3">Automação por automação</p>
            <div v-if="!resultsData.automations.length" class="text-sm text-n-slate-10 py-4">
              Nenhuma automação com movimento no período.
            </div>
            <div v-else class="space-y-2">
              <div
                v-for="a in resultsData.automations"
                :key="a.id"
                class="rounded-xl border border-n-weak bg-n-solid-1 px-3.5 py-2.5"
              >
                <div class="flex items-center gap-2 flex-wrap">
                  <span class="w-2 h-2 rounded-full flex-shrink-0" :style="{ backgroundColor: a.stage_color || '#94A3B8' }" />
                  <p class="text-sm font-semibold text-n-slate-12 truncate">{{ a.name }}</p>
                  <span
                    class="text-[10px] px-1.5 py-0.5 rounded-full font-medium flex-shrink-0"
                    :class="a.active ? 'bg-green-500/15 text-green-600' : 'bg-n-alpha-2 text-n-slate-10'"
                  >{{ a.active ? 'Ativa' : 'Pausada' }}</span>
                  <span class="ml-auto text-sm font-bold text-n-slate-12 flex-shrink-0">{{ a.fired }}×</span>
                </div>
                <div class="flex items-center gap-2 flex-wrap text-[11px] text-n-slate-10 mt-1">
                  <span>{{ a.stage_name }}</span>
                  <span>· {{ TRIGGER_LABELS[a.trigger_type] || a.trigger_type }} → {{ ACTION_LABELS[a.action_type] || a.action_type }}</span>
                  <span>· {{ a.contacts }} paciente(s)</span>
                  <span v-if="a.failed" class="text-red-500 font-medium">· {{ a.failed }} falha(s)</span>
                  <span class="ml-auto">último: {{ fmtLastFired(a.last_fired_at) }}</span>
                </div>
              </div>
            </div>
          </div>
        </template>
      </div>

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

    <!-- Modal: preencher a Agenda com o histórico -->
    <div
      v-if="showBackfillModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showBackfillModal = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
        <div class="h-1.5 w-full" style="background: linear-gradient(135deg, #B8860B, #D4A017)" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-calendar-search" style="color: #B8860B" />
            Preencher agenda com o histórico
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showBackfillModal = false" />
        </div>
        <div class="p-5 space-y-4">
          <p class="text-xs text-n-slate-11 leading-relaxed">
            O Agente de Agendamento vai ler as conversas com <b>confirmação de agendamento</b>
            (ex.: "Consulta confirmada" do bot) e registrar cada consulta na Agenda do sistema —
            criando as novas e <b>reagendando</b> as que mudaram de horário. Nada é enviado ao paciente.
          </p>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Olhar as conversas dos últimos</label>
              <select v-model.number="backfill.since_days" class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12">
                <option :value="7">7 dias</option>
                <option :value="30">30 dias</option>
                <option :value="90">90 dias</option>
                <option :value="180">180 dias</option>
              </select>
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Teto de conversas</label>
              <select v-model.number="backfill.limit" class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12">
                <option :value="50">50</option>
                <option :value="100">100</option>
                <option :value="200">200</option>
                <option :value="300">300 (máximo)</option>
              </select>
            </div>
          </div>
          <div class="rounded-lg bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-[11px] text-amber-700 dark:text-amber-400">
            ⚠️ Cada conversa = 1 análise de IA (Sonnet ≈ US$ 0,01–0,02 cada). O Agente de Agendamento
            precisa estar <b>LIGADO</b> e com a chave configurada. Rodar de novo não duplica consultas.
          </div>
        </div>
        <div class="flex gap-2 px-5 pb-5">
          <button
            class="flex-1 flex items-center justify-center gap-1.5 text-white rounded-lg py-2 text-sm font-semibold disabled:opacity-50"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            :disabled="isBackfilling"
            @click="runBackfill"
          >
            <span :class="isBackfilling ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-play'" class="text-sm" />
            {{ isBackfilling ? 'Iniciando…' : 'Começar a preencher' }}
          </button>
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showBackfillModal = false">
            Fechar
          </button>
        </div>
      </div>
    </div>

  </div>
</template>
