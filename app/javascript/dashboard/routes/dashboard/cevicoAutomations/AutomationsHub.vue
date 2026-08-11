<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TemplatesPicker from 'dashboard/components/widgets/conversation/WhatsappTemplates/TemplatesPicker.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import FollowupBotModal from 'dashboard/routes/dashboard/crm/components/FollowupBotModal.vue';
import DataTreatmentTools from 'dashboard/routes/dashboard/crm/components/DataTreatmentTools.vue';
import AiAgentsDashboard from './AiAgentsDashboard.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import CrmAPI from 'dashboard/api/crm';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { accountId } = useAccount();
const { isAdmin } = useAdmin();

const inboxes = useMapGetter('inboxes/getInboxes');
// caixas de WhatsApp (Colheitadeira envia por uma delas)
const whatsappInboxes = computed(() =>
  inboxes.value.filter(i => i.channel_type === 'Channel::Whatsapp')
);
const settings = useMapGetter('crm/getSettings');
const accountLabels = useMapGetter('labels/getLabels');
const teamAgents = useMapGetter('agents/getAgents');
const currentUserId = useMapGetter('getCurrentUserID');

const TABS = ['robos', 'regras', 'agentes', 'painel_ia', 'programacao', 'resultados', 'tratamento'];

// atendente concedido só vê as abas da área dele: robôs/resultados =
// Automações; tratamento = Tratamento de dados; o resto é de admin
const myGrants = computed(() => {
  const perms = settings.value?.agent_permissions ?? {};
  return perms.grants?.[String(currentUserId.value)] ?? [];
});
const canSee = capability =>
  isAdmin.value || myGrants.value.includes(capability);
const visibleTabs = computed(() =>
  TABS.filter(tab => {
    if (['robos', 'resultados'].includes(tab)) return canSee('automations');
    if (tab === 'tratamento') return canSee('data_tools');
    return isAdmin.value; // regras, agentes de IA, programação
  })
);
const activeTab = ref(TABS.includes(route.query.tab) ? route.query.tab : 'robos');

// os itens do menu lateral apontam para a MESMA rota com ?tab= diferente —
// sem este watch, clicar neles não trocava a aba (a página não remonta)
watch(
  () => route.query.tab,
  tab => {
    if (TABS.includes(tab)) activeTab.value = tab;
  }
);

// garante que atendente concedido nunca fica numa aba que não é dele
watch(
  visibleTabs,
  tabs => {
    if (tabs.length && !tabs.includes(activeTab.value)) {
      activeTab.value = tabs[0];
    }
  },
  { immediate: true }
);

// ── Agentes de IA internos (editar prompt / pausar) ──
// O Radar perene é configurado por VIGIAS: cada vigia = coluna + painel do
// atendente que recebe os avisos (null = todos) + janela de tempo própria.
const aiAgents = ref({
  conversation: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  form: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  scheduler: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  opportunity: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', watchers: [], wait_minutes: 10, response_goal_minutes: 15 },
  mentor: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  comments: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', page_access_token: '', fb_page_id: '', ig_user_id: '', page_token_set: false },
  closing: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  nps: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  sales: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '' },
  instagram: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', inbox_ids: [] },
  copywriter: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', references: '' },
  pagebuilder: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', references: '', max_tokens: '' },
  harvest: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', mode: 'organize', monthly_size: '', cold_days: '', daily_cap: '', day_of_month: '', inbox_id: null, require_approval: true, message_preview: '', template_params: null, stage_ids: [] },
  manager: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', drop_pct: '' },
  auditor: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', daily_cap: '' },
  creative: { enabled: false, prompt: '', model: '', effort: '', has_draft: false, default_prompt: '', winners_count: '', variations_count: '' },
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
// registro de atividade do Atendente Instagram (respondeu/agendou/pausou)
const instagramEvents = () => settings.value?.ai?.instagram_events || [];
const INSTAGRAM_EVENT_LABELS = {
  respondeu: '💬 respondeu',
  agendou: '📅 agendou e pausou',
  horario_invalido: '⚠️ horário não validou (tarefa criada)',
  teto_diario: '🛑 teto diário — pausado',
  erro: '❌ erro',
};
// painel de situação do Atendente Instagram (números dos últimos registros)
const instagramStats = () => {
  const evs = instagramEvents();
  return {
    replied: evs.filter(e => e.type === 'respondeu').length,
    scheduled: evs.filter(e => e.type === 'agendou').length,
    errors: evs.filter(e => e.type === 'erro' || e.type === 'horario_invalido').length,
  };
};
const instagramInboxNames = agent =>
  (agent.inbox_ids || [])
    .map(id => inboxes.value.find(i => i.id === id)?.name)
    .filter(Boolean);
const isGeneratingInsights = ref(false);
// Mentor do Time pontual: gera o feedback dos últimos 7 dias agora
const isRunningMentor = ref(false);
const runMentorNow = async () => {
  if (isRunningMentor.value) return;
  isRunningMentor.value = true;
  try {
    const { data } = await CrmAPI.runMentor();
    useAlert(data.message || 'Mentor iniciado! Veja o Meu Painel em alguns minutos.');
    setTimeout(() => { isRunningMentor.value = false; }, 90000);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao iniciar o Mentor.');
    isRunningMentor.value = false;
  }
};

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

// ── 🌾 OPERAÇÃO DA COLHEITA (Colheitadeira da Base) ──
// A prévia é gerada em segundo plano (~1-2 min) — a tela avisa e fica
// repollando o status a cada 15s até a lista ficar pronta.
const harvest = ref(null); // estado da colheita do mês (GET harvest_status)
const harvestActing = ref(''); // qual botão está trabalhando agora
const harvestGenerating = ref(false);
const showHarvestTable = ref(false);
let harvestPollTimer = null;
let harvestPollTicks = 0;

const loadHarvestStatus = async () => {
  try {
    const { data } = await CrmAPI.getHarvestStatus();
    harvest.value = data;
  } catch {
    // silencioso — o card mostra "sem colheita ainda"
  }
};

const stopHarvestPolling = () => {
  clearInterval(harvestPollTimer);
  harvestPollTimer = null;
};

const startHarvestPolling = (baseGeneratedAt, baseError) => {
  stopHarvestPolling();
  harvestPollTicks = 0;
  harvestPollTimer = setInterval(async () => {
    harvestPollTicks += 1;
    await loadHarvestStatus();
    const h = harvest.value;
    const ready =
      h?.status === 'preview' && h?.generated_at && h.generated_at !== baseGeneratedAt;
    const failed = h?.last_error && h.last_error !== baseError;
    if (ready || failed || harvestPollTicks > 24) {
      harvestGenerating.value = false;
      stopHarvestPolling();
      if (ready) {
        showHarvestTable.value = true;
        useAlert('🌾 Prévia da colheita pronta — revise a lista e aprove quando quiser.');
      } else if (failed) {
        useAlert(`⚠️ A prévia não saiu: ${h.last_error}`);
      }
    }
  }, 15000);
};

const runHarvestPreview = async () => {
  if (harvestActing.value || harvestGenerating.value) return;
  harvestActing.value = 'preview';
  const baseGeneratedAt = harvest.value?.generated_at || null;
  const baseError = harvest.value?.last_error || null;
  try {
    await CrmAPI.harvestPreview();
    harvestGenerating.value = true;
    useAlert('🌾 Gerando a prévia — leva uns 2 minutos, a lista aparece aqui sozinha.');
    startHarvestPolling(baseGeneratedAt, baseError);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao gerar a prévia da colheita.');
  } finally {
    harvestActing.value = '';
  }
};

const refreshHarvestPreview = async () => {
  if (harvestActing.value) return;
  harvestActing.value = 'refresh';
  await loadHarvestStatus();
  showHarvestTable.value = true;
  harvestActing.value = '';
};

// ação simples da colheita: aprovar / pausar / retomar / enviar lote
const harvestAction = async (name, fn, okMessage) => {
  if (harvestActing.value) return;
  harvestActing.value = name;
  try {
    const { data } = await fn();
    if (data?.error) {
      useAlert(`⚠️ ${data.error}`);
    } else {
      useAlert(okMessage);
      await loadHarvestStatus();
    }
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro na operação da colheita.');
  } finally {
    harvestActing.value = '';
  }
};

const approveHarvest = () =>
  harvestAction(
    'approve',
    () => CrmAPI.harvestApprove(),
    aiAgents.value.harvest.mode === 'send'
      ? '✅ Colheita aprovada — os envios começam aos poucos, dentro do teto diário.'
      : '✅ Colheita aprovada — a IA etiqueta os leads escolhidos; filtre pela etiqueta no CRM.'
  );
const pauseHarvest = () =>
  harvestAction('pause', () => CrmAPI.harvestPause(), '⏸ Colheita pausada — nada sai até você retomar.');
const resumeHarvest = () =>
  harvestAction('resume', () => CrmAPI.harvestResume(), '▶️ Colheita retomada — os envios continuam de onde pararam.');
const harvestSendNow = () =>
  harvestAction('send_now', () => CrmAPI.harvestSendNow(), '📤 Lote de hoje disparado — os envios saem em alguns minutos.');

const skipHarvestLead = async lead => {
  try {
    await CrmAPI.harvestSkipLead(lead.contact_id);
    lead.skipped = true;
    const st = harvest.value?.stats;
    if (st) {
      st.skipped = (st.skipped || 0) + 1;
      st.pending = Math.max(0, (st.pending || 0) - 1);
    }
    useAlert(`${lead.name || 'Lead'} pulado — não recebe a mensagem desta colheita.`);
  } catch {
    useAlert('Erro ao pular o lead.');
  }
};

// status do mês em linguagem humana
const HARVEST_STATUS_INFO = {
  preview: { label: 'Prévia pronta — revise a lista e aprove para começar', class: 'bg-amber-500/15 text-amber-600' },
  approved: { label: 'Aprovada — enviando aos poucos, dentro do teto diário', class: 'bg-green-500/15 text-green-600' },
  paused: { label: 'Pausada — nada sai até você retomar', class: 'bg-n-alpha-2 text-n-slate-10' },
  done: { label: 'Concluída — colheita do mês encerrada 🎉', class: 'bg-sky-500/15 text-sky-600' },
};
const harvestStatusInfo = () =>
  HARVEST_STATUS_INFO[harvest.value?.status] || {
    label: 'Nenhuma colheita neste mês ainda — gere a prévia quando quiser.',
    class: 'bg-n-alpha-2 text-n-slate-11',
  };
const harvestMonthLabel = () => {
  const mk = harvest.value?.month_key;
  if (!mk) return '';
  return new Date(`${mk}-01T12:00:00`).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' });
};
// modo organize: quantos leads já ganharam a etiqueta oportunidade_AAAA_MM
const harvestOrganizedCount = () =>
  harvest.value?.organized_count ??
  harvest.value?.stats?.organized ??
  harvest.value?.stats?.sent ??
  0;
const fmtBrl = v => (v ? `R$ ${Number(v).toLocaleString('pt-BR')}` : '—');
// pílula do score: verde ≥70, âmbar ≥40, cinza <40
const scoreClass = score => {
  if (Number(score) >= 70) return 'bg-green-500/15 text-green-600';
  if (Number(score) >= 40) return 'bg-amber-500/15 text-amber-600';
  return 'bg-n-alpha-2 text-n-slate-10';
};

// escolher a mensagem modelo da colheita (mesmo fluxo do robô de follow-up)
const showHarvestTemplatePicker = ref(false);
const harvestPickerTemplate = ref(null);
const harvestPickerInboxId = computed(
  () => aiAgents.value.harvest.inbox_id ?? whatsappInboxes.value[0]?.id
);
const openHarvestTemplatePicker = () => {
  harvestPickerTemplate.value = null;
  showHarvestTemplatePicker.value = true;
};
const closeHarvestTemplatePicker = () => {
  showHarvestTemplatePicker.value = false;
  harvestPickerTemplate.value = null;
};
const useHarvestTemplate = payload => {
  aiAgents.value.harvest.template_params = payload.templateParams;
  aiAgents.value.harvest.message_preview = payload.message;
  closeHarvestTemplatePicker();
};

// ── 📊 Gestor Autônomo: estado + rodar agora ──
const managerState = () => settings.value?.ai?.manager_state || null;
// chip do desvio: "Taxa de comparecimento −38%"
const managerFindingLabel = f =>
  `${f.label || f.indicator} ${Number(f.deviation_pct) < 0 ? '−' : '+'}${Math.abs(Math.round(f.deviation_pct || 0))}%`;
const isRunningManager = ref(false);
const runManagerNow = async () => {
  if (isRunningManager.value) return;
  isRunningManager.value = true;
  try {
    const { data } = await CrmAPI.runManager();
    useAlert(data.message || '📊 Gestor rodando! O briefing aparece aqui em ~30 segundos.');
    setTimeout(async () => {
      await store.dispatch('crm/fetchSettings');
      isRunningManager.value = false;
    }, 30000);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao rodar o Gestor.');
    isRunningManager.value = false;
  }
};

// ── 🎓 Auditor de Conversas: qualidade do time ──
// O resumo (ranking + falhas) é carregado LAZY: só quando o card expande
// pela primeira vez. "Auditar agora" re-audita ontem em segundo plano
// (~1-2 min) — a tela repolla o resumo a cada 20s por até 5 minutos.
const auditorSummary = ref(null);
const auditorDays = ref(7);
const loadingAuditorSummary = ref(false);
const isRunningAuditor = ref(false);
let auditorPollTimer = null;
let auditorPollTicks = 0;

// último dia auditado (vem no GET settings, bloco auditor_last)
const auditorLast = () => settings.value?.ai?.auditor_last || null;

const loadAuditorSummary = async () => {
  loadingAuditorSummary.value = true;
  try {
    const { data } = await CrmAPI.getAuditorSummary(auditorDays.value);
    auditorSummary.value = data;
  } catch {
    // silencioso — a seção mostra "nenhuma auditoria ainda"
  } finally {
    loadingAuditorSummary.value = false;
  }
};

const stopAuditorPolling = () => {
  clearInterval(auditorPollTimer);
  auditorPollTimer = null;
};

const runAuditorNow = async () => {
  if (isRunningAuditor.value) return;
  isRunningAuditor.value = true;
  const baseRunAt = auditorSummary.value?.last_run_at || null;
  try {
    await CrmAPI.runAuditor();
    useAlert('🎓 Auditando as conversas de ontem — leva ~2 minutos, o ranking atualiza aqui sozinho.');
    stopAuditorPolling();
    auditorPollTicks = 0;
    auditorPollTimer = setInterval(async () => {
      auditorPollTicks += 1;
      await loadAuditorSummary();
      const done =
        auditorSummary.value?.last_run_at &&
        auditorSummary.value.last_run_at !== baseRunAt;
      if (done || auditorPollTicks >= 15) {
        stopAuditorPolling();
        isRunningAuditor.value = false;
        if (done) {
          useAlert('🎓 Auditoria concluída — ranking atualizado.');
          // atualiza o "último dia auditado" (auditor_last vem do settings)
          store.dispatch('crm/fetchSettings').catch(() => {});
        }
      }
    }, 20000);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao iniciar a auditoria.');
    isRunningAuditor.value = false;
  }
};

const setAuditorDays = d => {
  if (auditorDays.value === d) return;
  auditorDays.value = d;
  loadAuditorSummary();
};

// pílula da média: verde ≥8, âmbar ≥6, vermelho <6 (uma casa decimal)
const auditorAvgClass = avg => {
  if (Number(avg) >= 8) return 'bg-green-500/15 text-green-600';
  if (Number(avg) >= 6) return 'bg-amber-500/15 text-amber-600';
  return 'bg-red-500/10 text-red-500';
};
const fmtAvg = avg => Number(avg || 0).toFixed(1).replace('.', ',');
// "Atendente 0" = conversas sem atendente humano (robô/fluxo)
const auditorRowName = row =>
  row.user_id === 0 || row.name === 'Atendente 0'
    ? 'Sem atendente (robô/fluxo)'
    : row.name;

// ── 🎨 Criativo Perpétuo: criativos da semana ──
// O estado (vencedores + variações + despensa) é carregado LAZY: só quando
// o card expande pela primeira vez. "Gerar agora" roda em segundo plano
// (~1-2 min) — a tela repolla o estado a cada 20s por até 5 minutos.
const creativeState = ref(null);
const loadingCreative = ref(false);
const isRunningCreative = ref(false);
const reviewingCreative = ref('');
let creativePollTimer = null;
let creativePollTicks = 0;

// resumo da última geração (vem no GET settings, bloco creative_last)
const creativeLast = () => settings.value?.ai?.creative_last || null;

const loadCreativeState = async () => {
  loadingCreative.value = true;
  try {
    const { data } = await CrmAPI.getCreativeState();
    creativeState.value = data;
  } catch {
    // silencioso — a seção mostra "nenhum criativo ainda"
  } finally {
    loadingCreative.value = false;
  }
};

const stopCreativePolling = () => {
  clearInterval(creativePollTimer);
  creativePollTimer = null;
};

const runCreativeNow = async () => {
  if (isRunningCreative.value) return;
  isRunningCreative.value = true;
  const baseGeneratedAt = creativeState.value?.generated_at || null;
  try {
    await CrmAPI.runCreative();
    useAlert('🎨 Gerando os criativos da semana — leva ~2 minutos, eles aparecem aqui sozinhos.');
    stopCreativePolling();
    creativePollTicks = 0;
    creativePollTimer = setInterval(async () => {
      creativePollTicks += 1;
      await loadCreativeState();
      const done =
        creativeState.value?.generated_at &&
        creativeState.value.generated_at !== baseGeneratedAt;
      if (done || creativePollTicks >= 15) {
        stopCreativePolling();
        isRunningCreative.value = false;
        if (done) {
          useAlert('🎨 Criativos da semana prontos — revise e aprove os que quiser usar.');
          // atualiza o resumo do topo (creative_last vem do settings)
          store.dispatch('crm/fetchSettings').catch(() => {});
        }
      }
    }, 20000);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao gerar os criativos.');
    isRunningCreative.value = false;
  }
};

// aprovar/recusar UMA variação — atualiza o estado local com a resposta
const reviewCreativeVariation = async (wi, vi, status) => {
  if (reviewingCreative.value) return;
  reviewingCreative.value = `${wi}-${vi}`;
  try {
    const { data } = await CrmAPI.reviewCreative(wi, vi, status);
    if (data?.error) {
      useAlert(`⚠️ ${data.error}`);
    } else {
      const variation = creativeState.value?.winners?.[wi]?.variations?.[vi];
      if (variation) {
        variation.status = data?.status || status;
        // aprovada entra na despensa na hora (o servidor grava no approved_log)
        if (variation.status === 'approved' && creativeState.value) {
          creativeState.value.approved_log = [
            ...(creativeState.value.approved_log || []),
            {
              week_key: creativeState.value.week_key,
              source: creativeState.value.winners[wi]?.name,
              kind: creativeState.value.winners[wi]?.kind,
              gancho: variation.gancho,
              texto: variation.texto,
              cta: variation.cta,
              approved_at: new Date().toISOString(),
            },
          ];
        }
      }
      useAlert(
        status === 'approved'
          ? '✓ Variação aprovada — guardada na despensa do Estúdio Criativo.'
          : 'Variação recusada — ela fica esmaecida e fora da despensa.'
      );
    }
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao registrar a revisão.');
  } finally {
    reviewingCreative.value = '';
  }
};

// copiar a variação pronta (gancho + texto + CTA) p/ o Gerenciador/Estúdio
const copyCreativeVariation = async v => {
  await navigator.clipboard.writeText([v.gancho, '', v.texto, '', v.cta].filter(Boolean).join('\n'));
  useAlert('Criativo copiado! 📋 Cole no Gerenciador de Anúncios ou no Estúdio.');
};

// semana em dd/mm (week_key vem como data da segunda-feira)
const fmtWeekKey = wk => {
  if (!wk) return '';
  const d = new Date(`${wk}T12:00:00`);
  if (Number.isNaN(d.getTime())) return wk;
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
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
// ✍️ ESTÚDIO DO COPYWRITER: conteúdo multi-formato com estrutura escolhida
const STUDIO_MODALITIES = [
  { key: 'carrossel', label: 'Carrossel' },
  { key: 'reels', label: 'Roteiro de Reels' },
  { key: 'post', label: 'Post / Descrição' },
  { key: 'anuncio', label: 'Anúncio' },
];
const STUDIO_STRUCTURES = [
  { key: 'auto', label: 'Automática' },
  { key: 'kishotenketsu', label: 'Kishōtenketsu' },
  { key: 'storytelling', label: 'Storytelling' },
  { key: 'jornada_heroi', label: 'Jornada do Herói' },
  { key: 'noticia', label: 'Notícia' },
  { key: 'perguntas_respostas', label: 'Perguntas e Respostas' },
  { key: 'dialogo', label: 'Diálogo' },
];
const studio = ref({ modality: 'carrossel', structure: 'auto', briefing: '', form_id: '', generating: false, result: null });
const studioForms = ref([]);
const loadStudioForms = async () => {
  try {
    const { data } = await CrmAPI.getForms();
    studioForms.value = (data || []).filter(f => f.has_insight);
  } catch {
    studioForms.value = [];
  }
};
const generateStudio = async () => {
  if (!studio.value.briefing.trim()) {
    useAlert('Escreva o briefing do conteúdo.');
    return;
  }
  studio.value.generating = true;
  studio.value.result = null;
  try {
    const { data } = await CrmAPI.generateCopyContent({
      briefing: studio.value.briefing,
      modality: studio.value.modality,
      structure: studio.value.structure,
      form_id: studio.value.form_id || undefined,
    });
    studio.value.result = data;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui gerar o conteúdo.');
  } finally {
    studio.value.generating = false;
  }
};
const copyStudioResult = async () => {
  const r = studio.value.result;
  if (!r) return;
  const parts = [r.titulo, '', ...(r.blocos || []).map(b => `${b.rotulo}\n${b.texto}`)];
  if (r.legenda) parts.push('', `LEGENDA:\n${r.legenda}`);
  if (r.hashtags) parts.push('', r.hashtags);
  await navigator.clipboard.writeText(parts.join('\n'));
  useAlert('Conteúdo copiado! 📋');
};
const savingRefs = ref(false);
const saveCopyReferences = async () => {
  savingRefs.value = true;
  try {
    await CrmAPI.updateAi({ agents: { copywriter: { references: aiAgents.value.copywriter.references || '' } } });
    useAlert('Referências salvas — o Copywriter segue esse estilo em tudo.');
  } catch {
    useAlert('Erro ao salvar as referências.');
  } finally {
    savingRefs.value = false;
  }
};

// Construtor PRO (23/07): referências de estilo + teto de resposta
const savingBuilderPro = ref(false);
const saveBuilderPro = async () => {
  savingBuilderPro.value = true;
  try {
    const tokens = parseInt(aiAgents.value.pagebuilder.max_tokens, 10);
    await CrmAPI.updateAi({
      agents: {
        pagebuilder: {
          references: aiAgents.value.pagebuilder.references || '',
          max_tokens: Number.isFinite(tokens) && tokens >= 1000 ? tokens : '',
        },
      },
    });
    useAlert('Construtor ajustado — as próximas montagens seguem essas rédeas. 🏗️');
  } catch {
    useAlert('Erro ao salvar os ajustes do Construtor.');
  } finally {
    savingBuilderPro.value = false;
  }
};

// SANFONA dos agentes: cabeçalho sempre visível, corpo desce ao clicar
// (são muitos agentes — assim dá para navegar pela página com controle)
const expandedAgents = ref({});
const toggleAgentExpand = key => {
  const next = !expandedAgents.value[key];
  expandedAgents.value = { ...expandedAgents.value, [key]: next };
  // 🎓 Auditor: carrega o resumo de qualidade ao expandir pela 1ª vez (lazy)
  if (key === 'auditor' && next && !auditorSummary.value && !loadingAuditorSummary.value) {
    loadAuditorSummary();
  }
  // 🎨 Criativo: carrega os criativos da semana ao expandir pela 1ª vez (lazy)
  if (key === 'creative' && next && !creativeState.value && !loadingCreative.value) {
    loadCreativeState();
  }
};

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
    snap.response_goal_minutes = a.response_goal_minutes;
  }
  if (key === 'instagram') snap.inbox_ids = [...(a.inbox_ids || [])];
  if (key === 'comments') {
    snap.fb_page_id = a.fb_page_id;
    snap.ig_user_id = a.ig_user_id;
  }
  if (key === 'harvest') {
    snap.mode = a.mode;
    snap.monthly_size = a.monthly_size;
    snap.cold_days = a.cold_days;
    snap.daily_cap = a.daily_cap;
    snap.day_of_month = a.day_of_month;
    snap.inbox_id = a.inbox_id;
    snap.require_approval = a.require_approval;
    snap.message_preview = a.message_preview;
    snap.template_params = a.template_params ? JSON.parse(JSON.stringify(a.template_params)) : null;
    snap.stage_ids = [...(a.stage_ids || [])];
  }
  if (key === 'manager') snap.drop_pct = a.drop_pct;
  if (key === 'auditor') snap.daily_cap = a.daily_cap;
  if (key === 'creative') {
    snap.winners_count = a.winners_count;
    snap.variations_count = a.variations_count;
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
      a.response_goal_minutes = snap.response_goal_minutes;
    }
    if (key === 'instagram') a.inbox_ids = [...(snap.inbox_ids || [])];
    if (key === 'comments') {
      a.fb_page_id = snap.fb_page_id;
      a.ig_user_id = snap.ig_user_id;
      a.page_access_token = '';
    }
    if (key === 'harvest') {
      a.mode = snap.mode || 'organize';
      a.monthly_size = snap.monthly_size;
      a.cold_days = snap.cold_days;
      a.daily_cap = snap.daily_cap;
      a.day_of_month = snap.day_of_month;
      a.inbox_id = snap.inbox_id;
      a.require_approval = snap.require_approval;
      a.message_preview = snap.message_preview;
      a.template_params = snap.template_params ? JSON.parse(JSON.stringify(snap.template_params)) : null;
      a.stage_ids = [...(snap.stage_ids || [])];
    }
    if (key === 'manager') a.drop_pct = snap.drop_pct;
    if (key === 'auditor') a.daily_cap = snap.daily_cap;
    if (key === 'creative') {
      a.winners_count = snap.winners_count;
      a.variations_count = snap.variations_count;
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
    fields.response_goal_minutes = Number(a.response_goal_minutes) || 15;
  }
  if (key === 'instagram') {
    fields.inbox_ids = (a.inbox_ids || []).map(Number);
  }
  if (key === 'comments') {
    fields.fb_page_id = (a.fb_page_id || '').trim();
    fields.ig_user_id = (a.ig_user_id || '').trim();
    // token só viaja quando digitado (nunca volta preenchido do servidor)
    if ((a.page_access_token || '').trim()) fields.page_access_token = a.page_access_token.trim();
  }
  if (key === 'harvest') {
    fields.mode = a.mode === 'send' ? 'send' : 'organize';
    fields.monthly_size = Number(a.monthly_size) || 300;
    fields.cold_days = Number(a.cold_days) || 60;
    fields.daily_cap = Number(a.daily_cap) || 50;
    fields.day_of_month = Math.min(28, Math.max(1, Number(a.day_of_month) || 1));
    fields.inbox_id = a.inbox_id || null;
    fields.require_approval = a.require_approval !== false;
    fields.message_preview = a.message_preview || '';
    fields.template_params = a.template_params || null;
    fields.stage_ids = (a.stage_ids || []).map(Number);
  }
  if (key === 'manager') {
    fields.drop_pct = Number(a.drop_pct) || 25;
  }
  if (key === 'auditor') {
    fields.daily_cap = Number(a.daily_cap) || 150;
  }
  if (key === 'creative') {
    fields.winners_count = Number(a.winners_count) || 3;
    fields.variations_count = Number(a.variations_count) || 3;
  }
  return fields;
};

// caixas do Atendente Instagram: pílulas de seleção no card
const toggleInstagramInbox = id => {
  const list = aiAgents.value.instagram.inbox_ids || [];
  const idx = list.indexOf(id);
  if (idx === -1) list.push(id);
  else list.splice(idx, 1);
  aiAgents.value.instagram.inbox_ids = [...list];
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
    gradient: 'linear-gradient(135deg, #059669, #4ADE80)',
    color: '#059669',
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
  instagram: {
    title: 'Atendente Direct & Messenger',
    icon: 'i-lucide-instagram',
    gradient: 'linear-gradient(135deg, #C2185B, #7C3AED)',
    color: '#C2185B',
    tag: 'Atendimento ao vivo',
    description: 'FALA com o paciente nas caixas escolhidas — Instagram Direct E Facebook Messenger — seguindo o script CEVICO (sondagem → autoridade → orçamento → agendamento). Agenda SOZINHO na Agenda interna oferecendo só horários livres, captura o telefone e avisa que a confirmação oficial vai pelo WhatsApp. PAUSA quando um humano responde na conversa; humano manda 👍 para reativar; a confirmação de agendamento (😊) pausa sozinha.',
    triggers: [
      { icon: 'i-lucide-instagram', label: 'Mensagem recebida nas caixas escolhidas abaixo (espera ~12s e junta mensagens picadas)' },
      { icon: 'i-lucide-calendar-check', label: 'Agenda direto na Agenda interna (só horários livres reais)' },
      { icon: 'i-lucide-message-circle', label: 'Confirmações oficiais e lembretes seguem pelo WhatsApp' },
      { icon: 'i-lucide-pause', label: 'Humano respondeu = pausa · 👍 = reativa · urgência = chama humano' },
    ],
    suggestion: 'Conversa ao vivo — Sonnet no esforço médio equilibra qualidade e custo.',
  },
  copywriter: {
    title: 'Copywriter',
    icon: 'i-lucide-pen-line',
    gradient: 'linear-gradient(135deg, #7C3AED, #D4AF37)',
    color: '#7C3AED',
    tag: 'Marketing',
    description: 'Escreve a copy da casa em VÁRIOS FORMATOS: páginas, carrosséis, roteiros de reels, posts e anúncios — com estruturas validadas (kishōtenketsu, storytelling, jornada do herói, notícia, P&R, diálogo) e as SUAS referências de estilo. Pode usar os INSIGHTS reais dos formulários (dores/desejos/objeções do público).',
    triggers: [
      { icon: 'i-lucide-sparkles', label: 'Botão "Gerar página com IA" no editor de Páginas' },
      { icon: 'i-lucide-pen-line', label: 'Estúdio de conteúdo aqui embaixo (carrossel, reels, post, anúncio)' },
      { icon: 'i-lucide-clipboard-list', label: 'Opcional: insights de um formulário alimentam a copy' },
      { icon: 'i-lucide-shield', label: 'Nada vai ao ar sozinho — você revisa e publica' },
    ],
    suggestion: 'Copy é fino — Opus no esforço alto escreve os melhores textos.',
  },
  pagebuilder: {
    title: 'Construtor de Páginas',
    icon: 'i-lucide-layout-template',
    gradient: 'linear-gradient(135deg, #0F5FA6, #D4AF37)',
    color: '#0F5FA6',
    tag: 'Marketing',
    description: 'Recebe uma COPY PRONTA (do Copywriter, sua ou do time) e MONTA a página no editor: distribui o texto em seções, escolhe os efeitos visuais e gera o SEO — sem reescrever o conteúdo. É a dupla do Copywriter: um escreve, o outro constrói.',
    triggers: [
      { icon: 'i-lucide-layout-template', label: 'Modo "Montar de copy pronta" no editor de Páginas' },
      { icon: 'i-lucide-shield', label: 'Publicar continua sendo decisão humana (admin)' },
    ],
    suggestion: 'Montagem estruturada — Sonnet no esforço médio resolve bem.',
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
  comments: {
    title: 'Respondedor de Comentários',
    icon: 'i-lucide-message-square-reply',
    gradient: 'linear-gradient(135deg, #7C3AED, #DB2777)',
    color: '#7C3AED',
    tag: 'Atendimento ao vivo',
    description: 'Responde os COMENTÁRIOS públicos dos posts e anúncios do Instagram e Facebook: agradece elogios, tira dúvidas leves e convida pro direct/WhatsApp — sem falar preço nem dado clínico em público. Reclamação séria ou urgência = marca pro humano e fica quieto. Corrige o gargalo de atendimento dos comentários.',
    triggers: [
      { icon: 'i-lucide-clock', label: 'Varre os comentários novos a cada 5 minutos' },
      { icon: 'i-lucide-message-square-reply', label: 'Responde em público no tom CEVICO (curto e caloroso)' },
      { icon: 'i-lucide-hand', label: 'Caso delicado → não responde e marca pro humano' },
      { icon: 'i-lucide-key-round', label: 'Precisa do token da Página da Meta (cole aqui embaixo)' },
    ],
    suggestion: 'Comentário público é a vitrine — Sonnet no esforço médio.',
  },
  mentor: {
    title: 'Mentor do Time',
    icon: 'i-lucide-graduation-cap',
    gradient: 'linear-gradient(135deg, #C2410C, #FB923C)',
    color: '#C2410C',
    tag: 'Evolução do time',
    description: 'Capta os dados de uso da semana de CADA pessoa (tempo de resposta, conversas resolvidas, mensagens, tarefas) e entrega um feedback individual no Meu Painel: o ponto forte, O PONTO FRACO exato a corrigir e 2-3 soluções simples que geram grande resultado. Compara com a mediana do time sem expor ninguém.',
    triggers: [
      { icon: 'i-lucide-calendar-check', label: 'Toda segunda de manhã, analisando a semana que acabou' },
      { icon: 'i-lucide-house', label: 'Feedback individual no Meu Painel de cada pessoa' },
      { icon: 'i-lucide-eye', label: 'Admin vê o feedback do time inteiro' },
      { icon: 'i-lucide-shield', label: 'Nunca fala com paciente — só lê números de uso' },
    ],
    suggestion: 'Feedback humano e fino, 1x por semana — Sonnet no esforço alto.',
  },
  harvest: {
    title: 'Colheitadeira da Base',
    icon: 'i-lucide-wheat',
    gradient: 'linear-gradient(135deg, #CA8A04, #FACC15)',
    color: '#CA8A04',
    tag: 'Reativação',
    description: 'Pontua a base fria todo mês e reativa os leads mais propensos, um a um, com aprovação sua. A IA escreve um gancho pessoal para cada paciente e os envios saem aos poucos, dentro do teto diário — anti-bloqueio.',
    triggers: [
      { icon: 'i-lucide-calendar-clock', label: 'Todo mês, no dia escolhido, gera a prévia da colheita' },
      { icon: 'i-lucide-list-checks', label: 'Você revisa a lista e aprova antes de qualquer envio' },
      { icon: 'i-lucide-message-circle', label: 'Envia pelo WhatsApp com gancho pessoal por lead' },
      { icon: 'i-lucide-shield', label: 'Teto de envios por dia — menos é mais seguro' },
    ],
    suggestion: 'Pontuar a base e escrever ganchos — Sonnet no esforço médio equilibra bem.',
  },
  manager: {
    title: 'Gestor Autônomo',
    icon: 'i-lucide-gauge',
    gradient: 'linear-gradient(135deg, #0F5FA6, #3B82F6)',
    color: '#0F5FA6',
    tag: 'Gestão',
    description: 'Lê o funil todos os dias contra a média de 12 semanas, abre tarefas nos desvios e escreve o briefing do dia. Você abre o Meu Painel e já sabe onde o processo está vazando — sem planilha.',
    triggers: [
      { icon: 'i-lucide-clock', label: 'Roda todos os dias, sozinho, de manhã' },
      { icon: 'i-lucide-trending-down', label: 'Compara cada indicador com a média de 12 semanas' },
      { icon: 'i-lucide-list-checks', label: 'Desvio encontrado → abre tarefa para o time agir' },
      { icon: 'i-lucide-house', label: 'Briefing do dia no Meu Painel (admin)' },
    ],
    suggestion: 'Leitura fina de números todo dia — Sonnet no esforço alto escreve o melhor briefing.',
  },
  auditor: {
    title: 'Auditor de Conversas',
    icon: 'i-lucide-clipboard-check',
    gradient: 'linear-gradient(135deg, #0F766E, #2DD4BF)',
    color: '#0F766E',
    tag: 'Evolução do time',
    description: 'Dá nota 0-10 nas conversas de ontem contra o script — coaching contínuo por atendente. Todo dia audita o atendimento da véspera e monta o ranking do time com as falhas mais comuns.',
    triggers: [
      { icon: 'i-lucide-clock', label: 'Roda todo dia, sozinho, auditando as conversas de ontem' },
      { icon: 'i-lucide-list-checks', label: 'Nota 0-10 por conversa contra o script da clínica' },
      { icon: 'i-lucide-trophy', label: 'Ranking por atendente + falhas mais comuns do time' },
      { icon: 'i-lucide-shield', label: 'Nunca fala com o paciente — só lê e avalia' },
    ],
    suggestion: 'Avaliar contra o script é leitura fina — Sonnet no esforço médio equilibra qualidade e custo.',
  },
  creative: {
    title: 'Criativo Perpétuo',
    icon: 'i-lucide-wand-sparkles',
    gradient: 'linear-gradient(135deg, #9D174D, #DB2777)',
    color: '#DB2777',
    tag: 'Marketing',
    description: 'Toda semana encontra os termos do Google e os anúncios do Meta que mais viraram cirurgia — na jornada real do banco — e escreve variações de copy prontas para os próximos anúncios. Você só aprova; as aprovadas ficam guardadas para o Estúdio Criativo.',
    triggers: [
      { icon: 'i-lucide-calendar-clock', label: 'Toda segunda 08:30 gera as variações da semana' },
      { icon: 'i-lucide-trophy', label: 'Vencedores reais: o que mais virou consulta e cirurgia (90 dias)' },
      { icon: 'i-lucide-list-checks', label: 'Você aprova ou recusa cada variação — nada vai ao ar sozinho' },
      { icon: 'i-lucide-copy', label: 'Aprovou? Copia e cola no Gerenciador de Anúncios / Estúdio' },
    ],
    suggestion: 'Copy é fino — Sonnet no esforço alto escreve as melhores variações.',
  },
};

// ── Seções da aba "agentes": os 16 agentes agrupados por área ──
// (são muitos — o agrupamento dá o mapa; card/sanfona continuam os mesmos)
const AGENT_GROUPS = [
  { title: 'Atendimento ao paciente', icon: '🗣️', keys: ['conversation', 'scheduler', 'instagram', 'comments', 'nps'] },
  { title: 'Vendas e fechamento', icon: '💰', keys: ['sales', 'closing', 'opportunity', 'form'] },
  { title: 'Marketing e aquisição', icon: '📣', keys: ['copywriter', 'pagebuilder', 'creative', 'harvest'] },
  { title: 'Gestão e evolução do time', icon: '📈', keys: ['manager', 'auditor', 'mentor'] },
];
// agente novo que ainda não entrou em nenhum grupo cai em "Outros" (à prova
// de futuro — nada some da tela)
const agentGroups = computed(() => {
  const known = AGENT_GROUPS.flatMap(g => g.keys);
  const groups = AGENT_GROUPS.map(g => ({
    ...g,
    keys: g.keys.filter(k => aiAgents.value[k]),
  }));
  const leftovers = Object.keys(aiAgents.value).filter(k => !known.includes(k));
  if (leftovers.length) groups.push({ title: 'Outros', icon: '🧩', keys: leftovers });
  return groups.filter(g => g.keys.length);
});
// mesmo formato do v-for original — (agent, key) — só que restrito ao grupo
const groupAgents = group =>
  Object.fromEntries(group.keys.map(k => [k, aiAgents.value[k]]));

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
  const harvestDraft = a.harvest?.draft || null;
  const managerDraft = a.manager?.draft || null;
  const auditorDraft = a.auditor?.draft || null;
  const creativeDraft = a.creative?.draft || null;
  aiAgents.value = {
    conversation: load('conversation'),
    form: load('form'),
    scheduler: load('scheduler'),
    closing: load('closing'),
    nps: load('nps'),
    sales: load('sales'),
    copywriter: { ...load('copywriter'), references: a.copywriter?.references || '' },
    pagebuilder: {
      ...load('pagebuilder'),
      references: a.pagebuilder?.references || '',
      max_tokens: a.pagebuilder?.max_tokens || '',
    },
    instagram: {
      ...load('instagram'),
      inbox_ids: [...(a.instagram?.inbox_ids || [])],
    },
    opportunity: {
      ...load('opportunity'),
      watchers: oppDraft?.watchers?.length
        ? oppDraft.watchers
        : (a.opportunity?.watchers?.length ? a.opportunity.watchers : legacyWatchers),
      wait_minutes: (oppDraft?.wait_minutes || a.opportunity?.wait_minutes) || 10,
      response_goal_minutes: (oppDraft?.response_goal_minutes || a.opportunity?.response_goal_minutes) || 15,
    },
    mentor: load('mentor'),
    comments: {
      ...load('comments'),
      page_access_token: '',
      fb_page_id: a.comments?.fb_page_id || '',
      ig_user_id: a.comments?.ig_user_id || '',
      page_token_set: a.comments?.page_token_set === true,
    },
    harvest: {
      ...load('harvest'),
      // null/vazio = organize (novo padrão): a IA etiqueta em vez de enviar
      mode: (harvestDraft?.mode ?? a.harvest?.mode) || 'organize',
      monthly_size: (harvestDraft?.monthly_size ?? a.harvest?.monthly_size) ?? '',
      cold_days: (harvestDraft?.cold_days ?? a.harvest?.cold_days) ?? '',
      daily_cap: (harvestDraft?.daily_cap ?? a.harvest?.daily_cap) ?? '',
      day_of_month: (harvestDraft?.day_of_month ?? a.harvest?.day_of_month) ?? '',
      inbox_id: (harvestDraft?.inbox_id ?? a.harvest?.inbox_id) ?? null,
      require_approval: (harvestDraft?.require_approval ?? a.harvest?.require_approval) !== false,
      message_preview: (harvestDraft?.message_preview ?? a.harvest?.message_preview) || '',
      template_params: (harvestDraft?.template_params ?? a.harvest?.template_params) || null,
      stage_ids: [...((harvestDraft?.stage_ids ?? a.harvest?.stage_ids) || [])],
    },
    manager: {
      ...load('manager'),
      drop_pct: (managerDraft?.drop_pct ?? a.manager?.drop_pct) ?? '',
    },
    auditor: {
      ...load('auditor'),
      daily_cap: (auditorDraft?.daily_cap ?? a.auditor?.daily_cap) ?? '',
    },
    creative: {
      ...load('creative'),
      winners_count: (creativeDraft?.winners_count ?? a.creative?.winners_count) ?? '',
      variations_count: (creativeDraft?.variations_count ?? a.creative?.variations_count) ?? '',
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
  // relatório de gastos + colunas para o Radar + colheita do mês (em paralelo)
  loadStages().catch(() => {});
  loadHarvestStatus();
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

// ── Resultados das automações — régua de período PADRÃO CEVICO (06/08) ──
const resultsPeriod = ref({ preset: 'today', from: '', to: '' });
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
    const { data } = await CrmAPI.getAutomationsDashboard({
      preset: resultsPeriod.value.preset,
      ...(resultsPeriod.value.preset === 'custom'
        ? { from: resultsPeriod.value.from, to: resultsPeriod.value.to }
        : {}),
    });
    resultsData.value = data;
  } catch {
    resultsData.value = null;
    useAlert('Erro ao carregar os resultados das automações.');
  } finally {
    loadingResults.value = false;
  }
};

watch(resultsPeriod, loadResults, { deep: true });

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

// ── Regras da caixa de entrada (Automation nativa do Chatwoot) ──
// A aba mostra e liga/desliga as regras; criar/editar continua no editor
// completo nativo (condições e ações complexas ficam lá).
const nativeRules = useMapGetter('automations/getAutomations');
const loadingNativeRules = ref(false);
const loadNativeRules = async () => {
  loadingNativeRules.value = true;
  await store.dispatch('automations/get');
  loadingNativeRules.value = false;
};
const toggleNativeRule = async rule => {
  try {
    await store.dispatch('automations/update', { ...rule, active: !rule.active });
  } catch {
    useAlert('Erro ao atualizar a regra');
  }
};
const openNativeEditor = () =>
  router.push({ name: 'automation_list', params: { accountId: accountId.value } });
const RULE_EVENT_LABELS = {
  conversation_created: 'Conversa criada',
  conversation_updated: 'Conversa atualizada',
  conversation_opened: 'Conversa reaberta',
  message_created: 'Mensagem criada',
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
  momento_perdido: 'cutucada vencida há horas — descartada (anti-rajada)',
  pausado_para_paciente: 'follow-up pausado para o paciente (trava da atendente)',
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
  loadStudioForms();
  if (!inboxes.value.length) store.dispatch('inboxes/get');
  if (!accountLabels.value.length) store.dispatch('labels/get');
  if (!teamAgents.value.length) store.dispatch('agents/get');
  loadBots();
  loadReguas(); // aparecem no painel panorâmico (Modo Programação)
  loadNativeRules(); // aba "Regras da caixa de entrada"
  await loadAgents();
  aiConfigured.value = !!settings.value?.ai?.configured;
  loadColumnAutomations();
});

// não deixa repoll nenhum rodando depois de sair da tela
// (colheita + auditor + criativo)
onUnmounted(() => {
  stopHarvestPolling();
  stopAuditorPolling();
  stopCreativePolling();
});
</script>

<template>
  <div class="bg-n-surface-1 flex flex-col h-full w-full">
    <!-- Header (item 70: medalhão + abas coloridas, mesma linguagem da
         Campanha WhatsApp — cada aba tem a sua cor) -->
    <div class="px-6 py-4 border-b border-n-weak flex-shrink-0">
      <div class="flex items-center gap-3">
        <span class="w-10 h-10 rounded-2xl flex items-center justify-center flex-shrink-0 shadow-sm" style="background: linear-gradient(135deg, #5B21B6, #7C3AED)">
          <span class="i-lucide-workflow text-white text-lg" />
        </span>
        <div>
          <h1 class="text-lg font-semibold text-n-slate-12">Automações</h1>
          <p class="text-xs text-n-slate-10 mt-0.5">
            Tudo que trabalha sozinho no sistema: réguas, robôs, agentes de IA, automações de coluna e tratamento de dados.
          </p>
        </div>
      </div>
      <!-- Tabs (atendente concedido só vê as abas da área dele) -->
      <div class="flex gap-1 mt-3 flex-wrap">
        <button
          v-if="visibleTabs.includes('robos')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'robos' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'robos' ? { background: 'linear-gradient(135deg, #0F5FA6, #3B82F6)' } : {}"
          @click="activeTab = 'robos'"
        ><span class="i-lucide-bot text-xs" />Robôs de follow-up</button>
        <button
          v-if="visibleTabs.includes('regras')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'regras' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'regras' ? { background: 'linear-gradient(135deg, #0E7490, #22D3EE)' } : {}"
          @click="activeTab = 'regras'"
        ><span class="i-lucide-repeat text-xs" />Regras da caixa de entrada</button>
        <button
          v-if="visibleTabs.includes('agentes')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'agentes' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'agentes' ? { background: 'linear-gradient(135deg, #7C3AED, #5B21B6)' } : {}"
          @click="activeTab = 'agentes'"
        ><span class="i-lucide-sparkles text-xs" />Agentes de IA</button>
        <button
          v-if="visibleTabs.includes('painel_ia')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'painel_ia' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'painel_ia' ? { background: 'linear-gradient(135deg, #9D174D, #DB2777)' } : {}"
          @click="activeTab = 'painel_ia'"
        ><span class="i-lucide-activity text-xs" />Painel dos agentes</button>
        <button
          v-if="visibleTabs.includes('programacao')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'programacao' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'programacao' ? { background: 'linear-gradient(135deg, #D97706, #F59E0B)' } : {}"
          @click="activeTab = 'programacao'"
        ><span class="i-lucide-zap text-xs" />Modo Programação</button>
        <button
          v-if="visibleTabs.includes('resultados')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'resultados' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'resultados' ? { background: 'linear-gradient(135deg, #65A30D, #84CC16)' } : {}"
          @click="activeTab = 'resultados'"
        ><span class="i-lucide-bar-chart-3 text-xs" />Resultados</button>
        <button
          v-if="visibleTabs.includes('tratamento')"
          class="px-3 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'tratamento' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'tratamento' ? { background: 'linear-gradient(135deg, #0F766E, #14B8A6)' } : {}"
          @click="activeTab = 'tratamento'"
        ><span class="i-lucide-database text-xs" />Tratamento de dados</button>
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
                  <template v-else-if="bot.activity.last_run.status === 'fora_do_expediente'">fora do expediente 08h–20h (não envia de madrugada)</template>
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
                <span>{{ ev.type === 'sent' ? '✉️' : (ev.type === 'skipped' ? '⏭️' : '⚠️') }}</span>
                <span class="text-n-slate-9 flex-shrink-0">{{ fmtLogDate(ev.at) }}</span>
                <span class="text-n-slate-11 truncate">{{ ev.contact || 'Contato' }} · conversa #{{ ev.conversation_id }}</span>
                <span class="text-n-slate-10 truncate">{{ ev.type === 'error' ? `erro: ${ev.note}` : ev.note }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
      <!-- ══ AGENTES DE IA ══ -->
      <!-- ══ REGRAS DA CAIXA DE ENTRADA (Automation nativa) ══ -->
      <div v-else-if="activeTab === 'regras'" class="max-w-3xl">
        <div class="flex items-start justify-between gap-3 mb-4 flex-wrap">
          <p class="text-sm text-n-slate-11 flex-1 min-w-[240px]">
            Regras que rodam nas conversas da caixa de entrada: quando uma conversa é criada ou uma
            mensagem chega, aplicam etiqueta, atribuem time/atendente, mudam prioridade... Ligue e
            desligue por aqui; criar e editar é no editor completo.
          </p>
          <button
            class="px-3 py-1.5 text-sm font-medium rounded-lg bg-n-brand text-white hover:opacity-90 transition-opacity flex items-center gap-1.5"
            @click="openNativeEditor"
          >
            <span class="i-lucide-external-link text-xs" />
            Abrir editor completo
          </button>
        </div>

        <div v-if="loadingNativeRules" class="flex justify-center py-10"><Spinner /></div>
        <p v-else-if="!nativeRules.length" class="text-sm text-n-slate-10 border border-dashed border-n-weak rounded-xl p-6 text-center">
          Nenhuma regra criada ainda — use o editor completo para criar a primeira.
        </p>
        <div v-else class="space-y-2">
          <div
            v-for="rule in nativeRules"
            :key="rule.id"
            class="border border-n-weak rounded-xl p-3 flex items-center gap-3 bg-n-solid-2"
          >
            <span
              class="w-2 h-2 rounded-full flex-shrink-0"
              :class="rule.active ? 'bg-green-500' : 'bg-n-slate-7'"
            />
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">{{ rule.name }}</p>
              <p class="text-[11px] text-n-slate-10 truncate">
                {{ RULE_EVENT_LABELS[rule.event_name] || rule.event_name }}
                <template v-if="rule.description"> · {{ rule.description }}</template>
              </p>
            </div>
            <span
              class="text-[10px] font-semibold px-2 py-0.5 rounded-full flex-shrink-0"
              :class="rule.active ? 'bg-green-500/15 text-green-600 dark:text-green-400' : 'bg-n-alpha-1 text-n-slate-10'"
            >
              {{ rule.active ? 'Ativa' : 'Desligada' }}
            </span>
            <button
              class="text-xs font-medium px-2.5 py-1 rounded-lg border border-n-weak hover:bg-n-alpha-1 transition-colors flex-shrink-0"
              @click="toggleNativeRule(rule)"
            >
              {{ rule.active ? 'Desligar' : 'Ligar' }}
            </button>
          </div>
        </div>
      </div>

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

        <template v-for="group in agentGroups" :key="group.title">
        <!-- Cabeçalho da seção (mesmo padrão dos cabeçalhos do hub) -->
        <p class="text-xs font-bold text-n-slate-11 uppercase tracking-wide flex items-center gap-1.5 pt-1">
          <span class="text-sm">{{ group.icon }}</span>
          {{ group.title }}
          <span class="text-n-slate-9 font-normal normal-case">({{ group.keys.length }})</span>
        </p>
        <div
          v-for="(agent, key) in groupAgents(group)"
          :key="key"
          class="rounded-2xl border-2 bg-n-solid-2 overflow-hidden"
          :style="{ borderColor: AGENT_META[key].color + '40' }"
        >
          <!-- Faixa superior colorida -->
          <div class="h-1.5 w-full" :style="{ background: AGENT_META[key].gradient }" />

          <div class="p-5">
            <!-- Cabeçalho (clique = desce/recolhe o agente completo) -->
            <div class="flex items-start gap-3 cursor-pointer select-none" :class="expandedAgents[key] ? 'mb-3' : ''" @click="toggleAgentExpand(key)">
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
                <p class="text-xs text-n-slate-10 mt-1" :class="expandedAgents[key] ? '' : 'line-clamp-2'">{{ AGENT_META[key].description }}</p>
              </div>
              <!-- INTERRUPTOR definitivo: grava na hora, sem "Salvar" -->
              <div class="flex flex-col items-end gap-1 flex-shrink-0" @click.stop>
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
              <span
                class="i-lucide-chevron-down text-n-slate-9 text-lg mt-2 flex-shrink-0 transition-transform duration-200"
                :class="expandedAgents[key] ? 'rotate-180' : ''"
              />
            </div>

            <!-- corpo completo do agente: desce com animação leve -->
            <div v-if="expandedAgents[key]" class="cevico-agent-body">

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

            <!-- Config específica do Atendente Instagram (respondedor) -->
            <div v-if="key === 'instagram'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <!-- 🎛 Painel de situação: a configuração dele, num relance -->
              <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <div class="rounded-lg px-3 py-2" :class="agent.enabled ? 'bg-green-500/10' : 'bg-n-alpha-1'">
                  <p class="text-[10px] text-n-slate-10">Situação</p>
                  <p class="text-sm font-bold" :class="agent.enabled ? 'text-green-600 dark:text-green-400' : 'text-n-slate-11'">
                    {{ agent.enabled ? '● Atendendo' : '○ Desligado' }}
                  </p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Caixas em que atende</p>
                  <p class="text-sm font-bold text-n-slate-12 truncate" :title="instagramInboxNames(agent).join(', ')">
                    {{ instagramInboxNames(agent).length ? instagramInboxNames(agent).join(', ') : 'nenhuma' }}
                  </p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Respostas <span class="text-n-slate-9">(últ. registros)</span></p>
                  <p class="text-sm font-bold text-n-slate-12">💬 {{ instagramStats().replied }}</p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Agendamentos / avisos</p>
                  <p class="text-sm font-bold text-n-slate-12">
                    📅 {{ instagramStats().scheduled }}
                    <span v-if="instagramStats().errors" class="text-amber-500">· ⚠️ {{ instagramStats().errors }}</span>
                  </p>
                </div>
              </div>
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" style="background: linear-gradient(135deg, #C2185B, #7C3AED)">
                ⚠️ Este agente FALA COM O PACIENTE nas caixas abaixo. Ele agenda só na Agenda interna,
                nunca inventa valores/horários, e as confirmações oficiais vão pelo WhatsApp.
                Se um humano responder na conversa, ele PAUSA na hora — 👍 do atendimento reativa.
              </div>
              <div>
                <p class="text-xs font-medium text-n-slate-11 mb-1.5">Caixas de entrada em que ele atende <span class="text-n-slate-9 font-normal">(nenhuma marcada = desligado na prática)</span></p>
                <div class="flex flex-wrap gap-1.5">
                  <button
                    v-for="ib in inboxes"
                    :key="ib.id"
                    class="text-xs px-2.5 py-1 rounded-full border transition-colors disabled:opacity-60"
                    :class="(agent.inbox_ids || []).includes(ib.id)
                      ? 'text-white border-transparent'
                      : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                    :style="(agent.inbox_ids || []).includes(ib.id) ? { background: 'linear-gradient(135deg, #C2185B, #7C3AED)' } : {}"
                    :disabled="!editingAgent[key]"
                    @click="toggleInstagramInbox(ib.id)"
                  >
                    {{ ib.name }}
                  </button>
                  <p v-if="!inboxes.length" class="text-[11px] text-n-slate-10">Nenhuma caixa de entrada na conta ainda.</p>
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">Escolha a caixa do Instagram quando ela for conectada (Configurações → Caixas de Entrada). Salve e publique para valer.</p>
              </div>
              <!-- 📒 Registro de atividade -->
              <div v-if="instagramEvents().length">
                <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">📒 Registro de atividade</p>
                <div class="max-h-40 overflow-y-auto space-y-1">
                  <p v-for="(ev, i) in instagramEvents()" :key="i" class="text-[11px] text-n-slate-11">
                    <span class="text-n-slate-9">{{ new Date(ev.at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) }}</span>
                    · #{{ ev.conversation_id }} {{ ev.contact }} — {{ INSTAGRAM_EVENT_LABELS[ev.type] || ev.type }}
                    <span v-if="ev.note" class="text-n-slate-9">({{ ev.note }})</span>
                  </p>
                </div>
              </div>
            </div>

            <!-- Config específica do Radar de Oportunidades (perene) -->
            <div v-if="key === 'opportunity'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <!-- O que ele monitora, direto ao ponto -->
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" style="background: linear-gradient(135deg, #059669, #4ADE80)">
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
                  class="border border-n-weak rounded-lg px-2 py-1 text-sm bg-n-solid-2 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                  style="width: 4.5rem"
                />
                min sem resposta
              </div>

              <!-- Meta de tempo de atendimento: vira o relatório pessoal
                   de cada atendente no Meu Painel -->
              <div class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2.5">
                <div class="flex items-center gap-2 flex-wrap text-xs text-n-slate-11">
                  <span class="i-lucide-target text-sm" style="color: #059669" />
                  <b class="text-n-slate-12">Meta de tempo de atendimento:</b>
                  responder o paciente em até
                  <input
                    v-model.number="agent.response_goal_minutes"
                    type="number"
                    min="1"
                    :disabled="!editingAgent[key]"
                    class="border border-n-weak rounded-lg px-2 py-1 text-sm bg-n-solid-1 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                    style="width: 4.5rem"
                  />
                  minutos
                </div>
                <p class="text-[11px] text-n-slate-9 mt-1">
                  Cada atendente acompanha a própria meta no <b>Meu Painel</b>: tempo médio de resposta,
                  % das respostas dentro da meta e o selo de meta batida. Admin vê a quebra por atendente.
                </p>
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
                  style="background: linear-gradient(135deg, #059669, #4ADE80)"
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

            <!-- Respondedor de Comentários: conexão da Meta + registro -->
            <div v-if="key === 'comments'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" style="background: linear-gradient(135deg, #7C3AED, #DB2777)">
                <p>
                  Responde os <b>comentários públicos</b> dos posts e anúncios a cada 5 min ·
                  sem preço/dado clínico em público · caso sério = <b>marca pro humano</b>.
                  Precisa do <b>token da Página</b> (app da Meta — o mesmo caminho do canal Instagram).
                </p>
              </div>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">ID da Página do Facebook (opcional)</span>
                  <input
                    v-model="agent.fb_page_id"
                    type="text"
                    :disabled="!editingAgent[key]"
                    placeholder="ex.: 1234567890"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">ID da conta Instagram Business (opcional)</span>
                  <input
                    v-model="agent.ig_user_id"
                    type="text"
                    :disabled="!editingAgent[key]"
                    placeholder="ex.: 17841400000000"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
              </div>
              <label class="block">
                <span class="text-[10px] font-medium text-n-slate-9">
                  Token de acesso da Página {{ agent.page_token_set ? '— já conectado ✓ (cole um novo só pra trocar)' : '' }}
                </span>
                <input
                  v-model="agent.page_access_token"
                  type="password"
                  :disabled="!editingAgent[key]"
                  :placeholder="agent.page_token_set ? '••••••••••••' : 'cole o Page Access Token da Meta'"
                  class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                />
              </label>
              <!-- registro de atividade (aparência nativa) -->
              <div v-if="(settings?.ai?.comments_events || []).length">
                <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1">Últimos comentários tratados</p>
                <div class="space-y-1 max-h-44 overflow-y-auto">
                  <div v-for="(ev, ei) in settings.ai.comments_events" :key="ei" class="rounded-lg bg-n-alpha-1 px-2.5 py-1.5 text-[11px]">
                    <div class="flex items-center gap-1.5 flex-wrap">
                      <span :class="ev.platform === 'instagram' ? 'i-lucide-instagram' : 'i-lucide-facebook'" class="text-[11px] text-n-slate-9" />
                      <b class="text-n-slate-12">@{{ ev.author }}</b>
                      <span
                        class="text-[9px] font-bold px-1.5 rounded-full uppercase"
                        :style="ev.status === 'respondido'
                          ? 'background: rgba(16,185,129,0.15); color: #047857'
                          : ev.status === 'humano'
                            ? 'background: rgba(245,158,11,0.15); color: #B45309'
                            : 'background: rgba(100,116,139,0.15); color: #64748B'"
                      >
                        {{ ev.status }}
                      </span>
                    </div>
                    <p class="text-n-slate-10 mt-0.5">“{{ ev.comment }}”</p>
                    <p v-if="ev.reply && ev.status === 'respondido'" class="text-n-slate-11 mt-0.5">↳ {{ ev.reply }}</p>
                  </div>
                </div>
              </div>
            </div>

            <!-- Mentor do Time: como funciona + gerar agora -->
            <div v-if="key === 'mentor'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-2">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" style="background: linear-gradient(135deg, #C2410C, #FB923C)">
                <p>
                  Toda <b>segunda de manhã</b> ele lê a semana de cada pessoa e deixa o feedback no
                  <b>Meu Painel</b> dela: ponto forte, o ponto fraco a corrigir e soluções simples ·
                  compara com a <b>mediana do time</b> sem expor ninguém · <b>nunca fala com o paciente</b>.
                </p>
              </div>
              <div class="flex items-center gap-2 flex-wrap">
                <p class="text-xs font-medium text-n-slate-11 flex-1">
                  Primeira rodada ou teste
                  <span class="text-n-slate-9 font-normal">(analisa os últimos 7 dias agora, sem esperar segunda)</span>
                </p>
                <button
                  class="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50"
                  :style="{ background: AGENT_META.mentor.gradient }"
                  :disabled="isRunningMentor || !agent.enabled"
                  :title="agent.enabled ? '' : 'Ligue o Mentor no interruptor acima primeiro'"
                  @click="runMentorNow"
                >
                  {{ isRunningMentor ? 'Gerando… (1-2 min)' : 'Gerar feedback agora' }}
                </button>
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

            <!-- 🏗️ CONSTRUTOR PRO: referências de estilo + teto de resposta -->
            <div v-if="key === 'pagebuilder'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
                <span class="i-lucide-ruler text-xs" style="color: #d4af37" /> Construtor PRO
                <span class="font-normal text-n-slate-9">— rédeas da montagem: estilo e tamanho da resposta</span>
              </p>
              <div>
                <p class="text-[11px] font-medium text-n-slate-11 mb-1">
                  Referências de estilo
                  <span class="text-n-slate-9 font-normal">(cole exemplos de páginas que você admira, diretrizes de marca, o que nunca pode faltar — o Construtor se inspira nelas em TODA montagem)</span>
                </p>
                <textarea
                  v-model="aiAgents.pagebuilder.references"
                  rows="3"
                  class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
                  placeholder="Ex: hero curto e emocional · benefícios sempre em cards · fechar com FAQ + CTA dourado · tom calmo, público 55+, letra grande…"
                />
              </div>
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-[11px] text-n-slate-10">Teto de resposta (tokens):</span>
                <input
                  v-model="aiAgents.pagebuilder.max_tokens"
                  type="number"
                  min="1000"
                  max="60000"
                  step="1000"
                  placeholder="30000"
                  class="w-24 h-8 border border-n-weak rounded-lg px-2 text-xs bg-n-solid-2 text-n-slate-12"
                  style="width: 6.5rem"
                />
                <span class="text-[10px] text-n-slate-9">vazio = padrão (30.000). Página grande truncada? Aumente. Custo alto? Diminua.</span>
              </div>
              <button
                class="text-[11px] font-semibold px-3 py-1.5 rounded-lg disabled:opacity-50"
                style="background: linear-gradient(135deg, #d4af37, #f4de8e); color: #072a4c"
                :disabled="savingBuilderPro"
                @click="saveBuilderPro"
              >
                {{ savingBuilderPro ? 'Salvando…' : 'Salvar rédeas do Construtor' }}
              </button>
            </div>

            <!-- ✍️ ESTÚDIO DO COPYWRITER: referências + conteúdo multi-formato -->
            <div v-if="key === 'copywriter'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <p class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5">
                <span class="i-lucide-pen-line text-xs" style="color: #7C3AED" /> Estúdio de conteúdo
                <span class="font-normal text-n-slate-9">— escolha o formato e a estrutura; o resultado é seu para copiar</span>
              </p>

              <!-- referências da casa: o agente segue esse estilo em TUDO -->
              <div>
                <p class="text-[11px] font-medium text-n-slate-11 mb-1">
                  Suas estruturas e referências de copywriting
                  <span class="text-n-slate-9 font-normal">(cole exemplos que você gosta, frases da casa, regras de estilo — vale para páginas e para o Estúdio)</span>
                </p>
                <textarea
                  v-model="aiAgents.copywriter.references"
                  rows="3"
                  class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
                  placeholder="Ex: sempre abrir com pergunta que toca a dor · nunca usar 'agende já' · exemplo de copy aprovada: ..."
                />
                <button
                  class="text-[11px] font-semibold text-white px-3 py-1.5 rounded-lg mt-1 disabled:opacity-50"
                  style="background: linear-gradient(135deg, #7C3AED, #5B21B6)"
                  :disabled="savingRefs"
                  @click="saveCopyReferences"
                >
                  {{ savingRefs ? 'Salvando…' : 'Salvar referências' }}
                </button>
              </div>

              <!-- formato: botões em linha -->
              <div class="flex items-center gap-1.5 flex-wrap">
                <span class="text-[11px] text-n-slate-10">Formato:</span>
                <button
                  v-for="m in STUDIO_MODALITIES"
                  :key="m.key"
                  class="px-2.5 h-7 rounded-full border text-[11px] font-medium transition-colors"
                  :class="studio.modality === m.key ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                  :style="studio.modality === m.key ? { background: AGENT_META.copywriter.gradient } : {}"
                  @click="studio.modality = m.key"
                >
                  {{ m.label }}
                </button>
                <span class="text-[10px] text-n-slate-9">· páginas são no editor de Páginas</span>
              </div>

              <!-- estrutura narrativa: botões em linha -->
              <div class="flex items-center gap-1.5 flex-wrap">
                <span class="text-[11px] text-n-slate-10">Estrutura:</span>
                <button
                  v-for="st in STUDIO_STRUCTURES"
                  :key="st.key"
                  class="px-2.5 h-7 rounded-full border text-[11px] font-medium transition-colors"
                  :class="studio.structure === st.key ? 'border-n-brand bg-n-brand/10 text-n-brand' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                  @click="studio.structure = st.key"
                >
                  {{ st.label }}
                </button>
              </div>

              <textarea
                v-model="studio.briefing"
                rows="3"
                class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
                placeholder="Briefing: assunto, objetivo e o que não pode faltar. Ex: carrossel sobre os 5 mitos da cirurgia de catarata, tom acolhedor, CTA para avaliação."
              />
              <div class="flex items-center gap-2 flex-wrap">
                <select v-model="studio.form_id" class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12 max-w-[240px]">
                  <option value="">Sem insights de formulário</option>
                  <option v-for="f in studioForms" :key="f.id" :value="f.id">Usar insights de: {{ f.name }}</option>
                </select>
                <button
                  class="ml-auto px-3 h-8 rounded-lg text-[11px] font-bold text-white flex items-center gap-1.5 disabled:opacity-60"
                  :style="{ background: AGENT_META.copywriter.gradient }"
                  :disabled="studio.generating"
                  @click="generateStudio"
                >
                  <span :class="studio.generating ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-sparkles'" class="text-xs" />
                  {{ studio.generating ? 'Escrevendo…' : 'Gerar conteúdo' }}
                </button>
              </div>

              <!-- resultado -->
              <div v-if="studio.result" class="rounded-lg bg-n-alpha-1 p-3 space-y-2">
                <div class="flex items-center gap-2">
                  <p class="text-xs font-bold text-n-slate-12 flex-1">{{ studio.result.titulo }}</p>
                  <button class="text-[11px] font-medium text-n-brand hover:underline flex items-center gap-1" @click="copyStudioResult">
                    <span class="i-lucide-copy text-[10px]" /> Copiar tudo
                  </button>
                </div>
                <div v-for="(b, bi) in studio.result.blocos" :key="bi" class="rounded-md bg-n-solid-2 border border-n-weak px-2.5 py-2">
                  <p class="text-[10px] font-bold text-n-slate-9 uppercase tracking-wide">{{ b.rotulo }}</p>
                  <p class="text-[11px] text-n-slate-11 whitespace-pre-wrap leading-relaxed">{{ b.texto }}</p>
                </div>
                <p v-if="studio.result.legenda" class="text-[11px] text-n-slate-11 whitespace-pre-wrap"><b>Legenda:</b> {{ studio.result.legenda }}</p>
                <p v-if="studio.result.hashtags" class="text-[11px] text-n-slate-10">{{ studio.result.hashtags }}</p>
              </div>
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

            <!-- 🌾 Config da Colheitadeira da Base -->
            <div v-if="key === 'harvest'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" :style="{ background: AGENT_META.harvest.gradient }">
                🌾 Todo mês ele pontua a base fria, escolhe os leads mais propensos e manda a
                mensagem modelo com um <b>gancho pessoal</b> escrito pela IA — um a um, dentro do
                teto diário. Com a caixinha marcada, <b>nada sai sem a sua aprovação</b>.
              </div>

              <!-- Modo de trabalho: organizar (etiqueta no CRM) × enviar (mensagem) -->
              <div>
                <p class="text-xs font-medium text-n-slate-11 mb-1.5">O que ele faz com os leads aprovados</p>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-2" role="radiogroup">
                  <button
                    role="radio"
                    :aria-checked="agent.mode !== 'send'"
                    class="text-left rounded-xl border-2 p-3 transition-colors disabled:cursor-not-allowed"
                    :class="agent.mode !== 'send' ? '' : 'border-n-weak hover:bg-n-alpha-1'"
                    :style="agent.mode !== 'send' ? { borderColor: AGENT_META.harvest.color, background: AGENT_META.harvest.color + '14' } : {}"
                    :disabled="!editingAgent[key]"
                    @click="agent.mode = 'organize'"
                  >
                    <p class="text-xs font-bold text-n-slate-12">
                      🗂️ Organizar oportunidades <span class="font-normal text-n-slate-9">(recomendado)</span>
                    </p>
                    <p class="text-[11px] text-n-slate-10 mt-0.5 leading-relaxed">
                      a IA escolhe e etiqueta os melhores leads frios como oportunidade_AAAA_MM —
                      nenhuma mensagem sai; o time trabalha a lista no CRM filtrando pela etiqueta
                    </p>
                  </button>
                  <button
                    role="radio"
                    :aria-checked="agent.mode === 'send'"
                    class="text-left rounded-xl border-2 p-3 transition-colors disabled:cursor-not-allowed"
                    :class="agent.mode === 'send' ? '' : 'border-n-weak hover:bg-n-alpha-1'"
                    :style="agent.mode === 'send' ? { borderColor: AGENT_META.harvest.color, background: AGENT_META.harvest.color + '14' } : {}"
                    :disabled="!editingAgent[key]"
                    @click="agent.mode = 'send'"
                  >
                    <p class="text-xs font-bold text-n-slate-12">📤 Enviar mensagem modelo</p>
                    <p class="text-[11px] text-n-slate-10 mt-0.5 leading-relaxed">
                      envia a mensagem modelo aprovada com gancho pessoal, respeitando o teto diário
                    </p>
                  </button>
                </div>
              </div>

              <div class="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">Quantos leads por mês</span>
                  <input
                    v-model.number="agent.monthly_size"
                    type="number"
                    min="1"
                    placeholder="300"
                    :disabled="!editingAgent[key]"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">Frio há pelo menos (dias)</span>
                  <input
                    v-model.number="agent.cold_days"
                    type="number"
                    min="1"
                    placeholder="60"
                    :disabled="!editingAgent[key]"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
                <label v-if="agent.mode === 'send'" class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">Teto de envios por dia</span>
                  <input
                    v-model.number="agent.daily_cap"
                    type="number"
                    min="1"
                    placeholder="50"
                    :disabled="!editingAgent[key]"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                  <span class="text-[10px] text-n-slate-9 block mt-0.5">anti-bloqueio: menos é mais seguro</span>
                </label>
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">Dia do mês que a colheita gera a prévia</span>
                  <input
                    v-model.number="agent.day_of_month"
                    type="number"
                    min="1"
                    max="28"
                    placeholder="1"
                    :disabled="!editingAgent[key]"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
              </div>

              <div v-if="agent.mode === 'send'">
                <label class="text-xs font-medium text-n-slate-11 block mb-1.5">Caixa de WhatsApp que envia</label>
                <select
                  v-model="agent.inbox_id"
                  :disabled="!editingAgent[key]"
                  class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                >
                  <option :value="null" disabled>Escolha a caixa…</option>
                  <option v-for="ib in whatsappInboxes" :key="ib.id" :value="ib.id">{{ ib.name }}</option>
                </select>
                <p v-if="!whatsappInboxes.length" class="text-[11px] text-n-slate-10 mt-1">
                  Nenhuma caixa de WhatsApp na conta ainda (Configurações → Caixas de Entrada).
                </p>
              </div>

              <div v-if="agent.mode === 'send'">
                <p class="text-xs font-medium text-n-slate-11 mb-1.5">
                  Mensagem modelo <span class="text-n-slate-9 font-normal">(template aprovado pela Meta — sem ele a colheita não envia)</span>
                </p>
                <div class="flex items-center gap-2">
                  <div class="flex-1 min-w-0">
                    <p v-if="agent.template_params" class="text-xs text-n-slate-12 truncate">
                      📋 {{ agent.template_params.name }}
                      <span v-if="agent.message_preview" class="text-n-slate-9">— "{{ agent.message_preview.slice(0, 60) }}…"</span>
                    </p>
                    <p v-else class="text-xs text-amber-600">Nenhum modelo escolhido ainda.</p>
                  </div>
                  <button
                    class="text-xs px-2.5 py-1.5 rounded-lg border border-n-brand text-n-brand hover:bg-n-brand/10 flex-shrink-0 disabled:opacity-60"
                    :disabled="!editingAgent[key]"
                    :title="editingAgent[key] ? '' : 'Clique em Editar lá embaixo para trocar o modelo'"
                    @click="openHarvestTemplatePicker"
                  >
                    {{ agent.template_params ? 'Trocar modelo' : 'Escolher modelo' }}
                  </button>
                </div>
                <p class="text-[10px] text-n-slate-9 mt-1">
                  💡 Use <code class="bg-n-alpha-2 px-1 rounded">[gancho]</code> numa variável do modelo —
                  a IA escreve um gancho pessoal para cada paciente;
                  <code class="bg-n-alpha-2 px-1 rounded">[procedimento]</code> também funciona.
                </p>
              </div>

              <label class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer">
                <input
                  v-model="agent.require_approval"
                  type="checkbox"
                  class="rounded accent-n-brand"
                  :disabled="!editingAgent[key]"
                />
                Exigir minha aprovação antes de enviar
                <span class="text-n-slate-9">(recomendado — a prévia espera o seu ok)</span>
              </label>
            </div>

            <!-- 🌾 OPERAÇÃO DA COLHEITA: o mês em andamento -->
            <div v-if="key === 'harvest'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">
                Operação da colheita<template v-if="harvestMonthLabel()"> · {{ harvestMonthLabel() }}</template>
              </p>

              <!-- status do mês em linguagem humana -->
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-[11px] font-semibold px-2.5 py-1 rounded-full" :class="harvestStatusInfo().class">
                  {{ harvestStatusInfo().label }}
                </span>
                <span v-if="harvest?.approved_at" class="text-[10px] text-n-slate-9">
                  aprovada<template v-if="harvest.approved_by"> por {{ harvest.approved_by }}</template> · {{ fmtLogDate(harvest.approved_at) }}
                </span>
              </div>

              <!-- modo organize: a lista virou etiqueta — ambiente de trabalho no CRM -->
              <div
                v-if="harvest?.organized_label"
                class="rounded-lg bg-green-500/10 border border-green-500/30 px-3 py-2 text-[11px] text-green-700 dark:text-green-400"
              >
                ✅ {{ harvestOrganizedCount() }} lead(s) etiquetado(s) como
                <b>{{ harvest.organized_label }}</b> — filtre por essa etiqueta no CRM para trabalhar a lista.
              </div>

              <div
                v-if="harvestGenerating"
                class="rounded-lg bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-[11px] text-amber-700 dark:text-amber-400"
              >
                ⏳ Gerando a prévia… leva uns 2 minutos — esta tela atualiza sozinha a cada 15 segundos.
              </div>
              <div
                v-if="harvest?.last_error"
                class="rounded-lg bg-red-500/10 border border-red-500/30 px-3 py-2 text-[11px] text-red-600 dark:text-red-400"
              >
                ⚠️ {{ harvest.last_error }}
              </div>

              <!-- números do mês -->
              <div v-if="harvest?.stats" class="grid grid-cols-3 sm:grid-cols-5 gap-2">
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Base fria</p>
                  <p class="text-sm font-bold text-n-slate-12">{{ harvest.stats.pool ?? 0 }}</p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Planejados</p>
                  <p class="text-sm font-bold text-n-slate-12">{{ harvest.stats.planned ?? 0 }}</p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-green-500/10">
                  <p class="text-[10px] text-n-slate-10">Enviados</p>
                  <p class="text-sm font-bold text-green-600 dark:text-green-400">{{ harvest.stats.sent ?? 0 }}</p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Responderam</p>
                  <p class="text-sm font-bold text-n-slate-12">{{ harvest.stats.replied ?? 0 }}</p>
                </div>
                <div class="rounded-lg px-3 py-2 bg-n-alpha-1">
                  <p class="text-[10px] text-n-slate-10">Pendentes</p>
                  <p class="text-sm font-bold text-n-slate-12">{{ harvest.stats.pending ?? 0 }}</p>
                </div>
              </div>
              <p v-if="harvest?.stats?.skipped" class="text-[10px] text-n-slate-9">
                {{ harvest.stats.skipped }} lead(s) pulado(s) por você neste mês.
              </p>

              <!-- botões conforme o status -->
              <div class="flex items-center gap-2 flex-wrap">
                <button
                  v-if="!harvest?.status || ['preview', 'done'].includes(harvest.status)"
                  class="flex items-center gap-1.5 text-xs font-semibold text-white px-3 py-2 rounded-lg hover:opacity-90 disabled:opacity-50"
                  :style="{ background: AGENT_META.harvest.gradient }"
                  :disabled="harvestGenerating || harvestActing === 'preview'"
                  @click="runHarvestPreview"
                >
                  <span :class="harvestGenerating || harvestActing === 'preview' ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-sparkles'" class="text-xs" />
                  {{ harvestGenerating ? 'Gerando… (~2 min)' : 'Gerar prévia agora' }}
                </button>
                <button
                  v-if="harvest?.selected?.length"
                  class="flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
                  :disabled="harvestActing === 'refresh'"
                  @click="refreshHarvestPreview"
                >
                  <span :class="harvestActing === 'refresh' ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-eye'" class="text-xs" />
                  Ver/atualizar prévia
                </button>
                <button
                  v-if="harvest?.status === 'preview'"
                  class="flex items-center gap-1.5 text-xs font-semibold text-white px-3 py-2 rounded-lg hover:opacity-90 disabled:opacity-50 shadow"
                  style="background: linear-gradient(135deg, #059669, #34D399)"
                  :disabled="!!harvestActing"
                  @click="approveHarvest"
                >
                  <span :class="harvestActing === 'approve' ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-check'" class="text-xs" />
                  {{ agent.mode === 'send' ? 'Aprovar e começar' : 'Aprovar e etiquetar' }}
                </button>
                <button
                  v-if="harvest?.status === 'approved'"
                  class="text-xs font-medium px-3 py-2 rounded-lg border border-n-weak text-yellow-600 hover:bg-n-alpha-1 disabled:opacity-50"
                  :disabled="!!harvestActing"
                  @click="pauseHarvest"
                >
                  ⏸ Pausar
                </button>
                <button
                  v-if="harvest?.status === 'paused'"
                  class="text-xs font-medium px-3 py-2 rounded-lg border border-n-weak text-green-600 hover:bg-n-alpha-1 disabled:opacity-50"
                  :disabled="!!harvestActing"
                  @click="resumeHarvest"
                >
                  ▶️ Retomar
                </button>
                <button
                  v-if="harvest?.status === 'approved'"
                  class="flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-lg border border-n-brand text-n-brand hover:bg-n-brand/10 disabled:opacity-50"
                  :disabled="!!harvestActing"
                  title="Dispara o lote de hoje agora, respeitando o teto diário"
                  @click="harvestSendNow"
                >
                  <span :class="harvestActing === 'send_now' ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-send'" class="text-xs" />
                  Enviar lote agora
                </button>
              </div>

              <!-- prévia: a lista dos escolhidos do mês -->
              <div v-if="showHarvestTable && harvest?.selected?.length" class="space-y-1 max-h-80 overflow-y-auto pr-1">
                <div
                  v-for="lead in harvest.selected"
                  :key="lead.contact_id"
                  class="flex items-center gap-2 flex-wrap text-[11px] rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1.5"
                  :class="lead.skipped ? 'opacity-50' : ''"
                >
                  <span v-if="lead.sent_at" class="text-green-600 font-bold flex-shrink-0" title="Mensagem já enviada">✓</span>
                  <span class="font-semibold text-n-slate-12 truncate max-w-[150px]">{{ lead.name }}</span>
                  <span v-if="lead.stage_name" class="text-[10px] px-1.5 py-0.5 rounded bg-n-alpha-1 text-n-slate-10 whitespace-nowrap">{{ lead.stage_name }}</span>
                  <span v-if="lead.procedure" class="text-[10px] px-1.5 py-0.5 rounded bg-n-alpha-1 text-n-slate-10 whitespace-nowrap">{{ lead.procedure }}</span>
                  <span v-if="lead.value" class="text-n-slate-11 whitespace-nowrap">{{ fmtBrl(lead.value) }}</span>
                  <span class="text-n-slate-10 whitespace-nowrap">frio há {{ lead.cold_days }}d</span>
                  <span class="text-[10px] font-bold px-1.5 py-0.5 rounded-full flex-shrink-0" :class="scoreClass(lead.score)">{{ lead.score }}</span>
                  <span v-if="lead.hook" class="italic text-n-slate-10 basis-full sm:basis-auto sm:flex-1 truncate" :title="lead.hook">“{{ lead.hook }}”</span>
                  <span v-if="lead.skipped" class="text-[10px] text-n-slate-9 ml-auto">pulado</span>
                  <button
                    v-else-if="!lead.sent_at"
                    class="text-n-slate-9 hover:text-red-500 i-lucide-x text-sm flex-shrink-0 ml-auto"
                    title="Pular este lead (não recebe a mensagem desta colheita)"
                    @click="skipHarvestLead(lead)"
                  />
                </div>
              </div>
            </div>

            <!-- 📊 Config + estado do Gestor Autônomo -->
            <div v-if="key === 'manager'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" :style="{ background: AGENT_META.manager.gradient }">
                📊 Todo dia ele compara o funil com a <b>média das últimas 12 semanas</b>. Caiu além
                da sensibilidade? Ele <b>abre uma tarefa</b> para o time e escreve o <b>briefing do
                dia</b> no Meu Painel. <b>Nunca fala com o paciente</b> — só lê números.
              </div>

              <div class="flex items-center gap-2 flex-wrap text-xs text-n-slate-11">
                Sensibilidade: avisar quando cair mais de
                <input
                  v-model.number="agent.drop_pct"
                  type="number"
                  min="1"
                  max="90"
                  placeholder="25"
                  :disabled="!editingAgent[key]"
                  class="border border-n-weak rounded-lg px-2 py-1 text-sm bg-n-solid-2 text-n-slate-12 disabled:opacity-70 disabled:cursor-not-allowed"
                  style="width: 4.5rem"
                />
                % vs a média
              </div>

              <!-- último briefing + desvios encontrados -->
              <div v-if="managerState()" class="border-t border-n-weak pt-3 space-y-2">
                <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">
                  Última rodada<template v-if="managerState().last_run_at"> · {{ fmtLogDate(managerState().last_run_at) }}</template>
                </p>
                <div v-if="managerState().brief" class="rounded-lg bg-n-alpha-1 p-3">
                  <p class="text-xs text-n-slate-11 leading-relaxed whitespace-pre-wrap">{{ managerState().brief }}</p>
                </div>
                <div v-if="(managerState().findings || []).length" class="flex flex-wrap gap-1.5">
                  <span
                    v-for="(f, fi) in managerState().findings"
                    :key="fi"
                    class="text-[11px] font-medium px-2 py-0.5 rounded-full bg-red-500/10 text-red-600 dark:text-red-400 border border-red-500/25"
                    :title="f.window ? `janela: ${f.window}` : ''"
                  >
                    {{ managerFindingLabel(f) }}
                  </span>
                </div>
                <p class="text-[11px] text-n-slate-10">abriu {{ managerState().tasks_opened || 0 }} tarefa(s)</p>
              </div>

              <div class="flex items-center gap-2 flex-wrap border-t border-n-weak pt-3">
                <button
                  class="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50"
                  :style="{ background: AGENT_META.manager.gradient }"
                  :disabled="isRunningManager || !agent.enabled"
                  :title="agent.enabled ? '' : 'Ligue o Gestor no interruptor acima primeiro'"
                  @click="runManagerNow"
                >
                  {{ isRunningManager ? 'Rodando… (~30 s)' : 'Rodar agora' }}
                </button>
                <span class="text-[11px] text-n-slate-9">lê o funil agora e atualiza o briefing do dia</span>
              </div>
            </div>

            <!-- 🎓 Config do Auditor de Conversas -->
            <div v-if="key === 'auditor'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" :style="{ background: AGENT_META.auditor.gradient }">
                🎓 Todo dia ele relê as conversas de <b>ontem</b> e dá <b>nota 0-10</b> contra o
                script da clínica, apontando o que faltou em cada uma. O ranking por atendente
                vira <b>coaching contínuo</b> — e ele <b>nunca fala com o paciente</b>.
              </div>

              <label class="block sm:w-64">
                <span class="text-[10px] font-medium text-n-slate-9">Teto de conversas auditadas por dia</span>
                <input
                  v-model.number="agent.daily_cap"
                  type="number"
                  min="1"
                  placeholder="150"
                  :disabled="!editingAgent[key]"
                  class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                />
                <span class="text-[10px] text-n-slate-9 block mt-0.5">controla o custo da auditoria diária</span>
              </label>
            </div>

            <!-- 🎓 QUALIDADE DO TIME: ranking + falhas mais comuns -->
            <div v-if="key === 'auditor'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">Qualidade do time</p>

              <div class="flex items-center gap-2 flex-wrap">
                <button
                  class="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50"
                  :style="{ background: AGENT_META.auditor.gradient }"
                  :disabled="isRunningAuditor || !agent.enabled"
                  :title="agent.enabled ? 'Re-audita as conversas de ontem (~2 min)' : 'Ligue o Auditor no interruptor acima primeiro'"
                  @click="runAuditorNow"
                >
                  {{ isRunningAuditor ? 'Auditando… (~2 min)' : 'Auditar agora' }}
                </button>
                <span v-if="auditorLast()?.days_done" class="text-[11px] text-n-slate-10">
                  último dia auditado: <b class="text-n-slate-12">{{ fmtDay(auditorLast().days_done) }}</b>
                  <template v-if="auditorLast()?.last_run_at"> · rodou {{ fmtLogDate(auditorLast().last_run_at) }}</template>
                </span>
                <span v-else class="text-[11px] text-n-slate-10">nenhuma auditoria ainda — o primeiro ranking sai depois da primeira rodada</span>
              </div>

              <div
                v-if="isRunningAuditor"
                class="rounded-lg bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-[11px] text-amber-700 dark:text-amber-400"
              >
                ⏳ Auditando… leva ~2 minutos — o ranking abaixo atualiza aqui sozinho a cada 20 segundos.
              </div>

              <!-- janela de análise: 7 / 14 / 30 dias -->
              <div class="flex items-center gap-1.5 flex-wrap">
                <span class="text-[11px] text-n-slate-10">Janela:</span>
                <button
                  v-for="d in [7, 14, 30]"
                  :key="d"
                  class="text-[11px] font-medium px-2.5 py-1 rounded-lg border transition-colors"
                  :class="auditorDays === d ? 'text-white border-transparent shadow-sm' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                  :style="auditorDays === d ? { background: AGENT_META.auditor.gradient } : {}"
                  @click="setAuditorDays(d)"
                >
                  {{ d }} dias
                </button>
                <span v-if="auditorSummary" class="text-[11px] text-n-slate-9 ml-auto">
                  {{ auditorSummary.audited_total || 0 }} conversa(s) auditada(s) no período
                </span>
              </div>

              <div v-if="loadingAuditorSummary && !auditorSummary" class="flex items-center gap-2 text-xs text-n-slate-10 py-2">
                <Spinner :size="16" class="text-n-brand" /> Carregando a qualidade do time…
              </div>

              <template v-else-if="auditorSummary">
                <!-- ranking por atendente (já vem ordenado pela média) -->
                <div v-if="(auditorSummary.ranking || []).length" class="space-y-1.5">
                  <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">Ranking por atendente</p>
                  <div
                    v-for="row in auditorSummary.ranking"
                    :key="row.user_id"
                    class="rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1.5"
                  >
                    <div class="flex items-center gap-2 flex-wrap text-xs">
                      <span class="font-semibold text-n-slate-12 truncate max-w-[180px]">{{ auditorRowName(row) }}</span>
                      <span class="text-n-slate-10 whitespace-nowrap">{{ row.audited }} auditada(s)</span>
                      <span
                        class="text-[11px] font-bold px-2 py-0.5 rounded-full ml-auto flex-shrink-0"
                        :class="auditorAvgClass(row.avg)"
                        title="média das notas 0-10 no período"
                      >
                        {{ fmtAvg(row.avg) }}
                      </span>
                    </div>
                    <div v-if="(row.top_gaps || []).length" class="flex flex-wrap gap-1 mt-1">
                      <span
                        v-for="(gap, gi) in row.top_gaps"
                        :key="gi"
                        class="text-[10px] px-1.5 py-0.5 rounded-full bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/25"
                      >
                        {{ gap }}
                      </span>
                    </div>
                  </div>
                </div>
                <p v-else class="text-xs text-n-slate-10">
                  Nenhuma conversa auditada no período ainda — o ranking aparece depois da primeira auditoria.
                </p>

                <!-- falhas mais comuns do time -->
                <div v-if="(auditorSummary.team_gaps || []).length" class="space-y-1 border-t border-n-weak pt-2">
                  <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">Falhas mais comuns do time</p>
                  <p v-for="(g, gi) in auditorSummary.team_gaps" :key="gi" class="text-xs text-n-slate-11">
                    <span class="font-medium text-amber-700 dark:text-amber-400">{{ g.gap }}</span>
                    <span class="text-n-slate-9"> · {{ g.count }}×</span>
                  </p>
                </div>
              </template>
            </div>

            <!-- 🎨 Config do Criativo Perpétuo -->
            <div v-if="key === 'creative'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <div class="rounded-lg px-3 py-2 text-[11px] text-white" :style="{ background: AGENT_META.creative.gradient }">
                🎨 Toda <b>segunda 08:30</b> ele encontra os <b>vencedores da semana</b> — os termos
                do Google e os anúncios do Meta que mais viraram <b>consulta e cirurgia</b> na
                jornada real do banco (últimos 90 dias) — e escreve variações de copy prontas.
                <b>Nada vai ao ar sozinho</b>: você aprova, copia e cola no Gerenciador de Anúncios.
              </div>

              <div class="grid grid-cols-2 gap-2 sm:w-96">
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">Vencedores por semana</span>
                  <input
                    v-model.number="agent.winners_count"
                    type="number"
                    min="1"
                    placeholder="3"
                    :disabled="!editingAgent[key]"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
                <label class="block">
                  <span class="text-[10px] font-medium text-n-slate-9">Variações por vencedor</span>
                  <input
                    v-model.number="agent.variations_count"
                    type="number"
                    min="1"
                    placeholder="3"
                    :disabled="!editingAgent[key]"
                    class="mt-0.5 w-full h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 disabled:opacity-60"
                  />
                </label>
              </div>
            </div>

            <!-- 🎨 CRIATIVOS DA SEMANA: vencedores + variações p/ aprovar -->
            <div v-if="key === 'creative'" class="rounded-xl border border-n-weak bg-n-solid-1 p-3.5 mb-4 space-y-3">
              <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide">
                Criativos da semana<template v-if="creativeState?.week_key"> · semana de {{ fmtWeekKey(creativeState.week_key) }}</template>
              </p>

              <div class="flex items-center gap-2 flex-wrap">
                <button
                  class="text-xs font-semibold px-3 py-1.5 rounded-lg text-white disabled:opacity-50"
                  :style="{ background: AGENT_META.creative.gradient }"
                  :disabled="isRunningCreative || !agent.enabled"
                  :title="agent.enabled ? 'Gera os vencedores + variações da semana agora (~2 min)' : 'Ligue o Criativo no interruptor acima primeiro'"
                  @click="runCreativeNow"
                >
                  {{ isRunningCreative ? 'Gerando… (~2 min)' : 'Gerar agora' }}
                </button>
                <span v-if="creativeState?.generated_at" class="text-[11px] text-n-slate-10">
                  gerado {{ fmtLogDate(creativeState.generated_at) }}
                </span>
                <span v-else-if="creativeLast()?.generated_at" class="text-[11px] text-n-slate-10">
                  última geração {{ fmtLogDate(creativeLast().generated_at) }}
                </span>
                <span
                  class="text-[11px] font-medium px-2 py-0.5 rounded-full bg-green-500/15 text-green-600 ml-auto cursor-help"
                  title="aprovadas ficam guardadas para o Estúdio Criativo"
                >
                  📦 {{ (creativeState?.approved_log || []).length }} aprovada(s) na despensa
                </span>
              </div>

              <div
                v-if="isRunningCreative"
                class="rounded-lg bg-amber-500/10 border border-amber-500/30 px-3 py-2 text-[11px] text-amber-700 dark:text-amber-400"
              >
                ⏳ Gerando as variações… leva ~2 minutos — esta tela atualiza sozinha a cada 20 segundos.
              </div>

              <div v-if="loadingCreative && !creativeState" class="flex items-center gap-2 text-xs text-n-slate-10 py-2">
                <Spinner :size="16" class="text-n-brand" /> Carregando os criativos da semana…
              </div>

              <template v-else-if="(creativeState?.winners || []).length">
                <div
                  v-for="(w, wi) in creativeState.winners"
                  :key="wi"
                  class="rounded-lg border border-n-weak bg-n-solid-2 p-3 space-y-2"
                >
                  <!-- cabeçalho do vencedor -->
                  <div class="flex items-center gap-2 flex-wrap">
                    <span class="text-sm flex-shrink-0">🥇</span>
                    <p class="text-xs font-bold text-n-slate-12 truncate max-w-[240px]" :title="w.name">{{ w.name }}</p>
                    <span
                      class="text-[10px] px-1.5 py-0.5 rounded-full font-semibold flex-shrink-0"
                      :style="{ backgroundColor: AGENT_META.creative.color + '1A', color: AGENT_META.creative.color }"
                    >
                      {{ w.kind_label }}
                    </span>
                  </div>

                  <!-- jornada real em pílulas -->
                  <div class="flex items-center gap-1 flex-wrap text-[10px] font-medium">
                    <span class="px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11">{{ w.stats?.leads ?? 0 }} leads</span>
                    <span class="text-n-slate-9">→</span>
                    <span class="px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11">{{ w.stats?.booked ?? 0 }} consultas</span>
                    <span class="text-n-slate-9">→</span>
                    <span class="px-1.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11">{{ w.stats?.attended ?? 0 }} compareceram</span>
                    <span class="text-n-slate-9">→</span>
                    <span class="px-1.5 py-0.5 rounded-full bg-green-500/15 text-green-600">{{ w.stats?.surgeries ?? 0 }} cirurgias</span>
                    <span v-if="w.stats?.revenue" class="text-n-slate-10">· {{ fmtBrl(w.stats.revenue) }}</span>
                  </div>

                  <!-- variações: cartõezinhos p/ aprovar/recusar/copiar -->
                  <div class="space-y-2">
                    <div
                      v-for="(v, vi) in w.variations"
                      :key="vi"
                      class="rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 space-y-1.5"
                      :class="v.status === 'rejected' ? 'opacity-50' : ''"
                    >
                      <div class="flex items-center gap-1.5 flex-wrap">
                        <span
                          v-if="v.angulo"
                          class="text-[10px] px-1.5 py-0.5 rounded-full font-semibold bg-n-alpha-2 text-n-slate-11"
                        >
                          {{ v.angulo }}
                        </span>
                        <span
                          v-if="v.status === 'approved'"
                          class="text-[10px] px-1.5 py-0.5 rounded-full font-semibold bg-green-500/15 text-green-600"
                          :title="v.reviewed_by ? `aprovada por ${v.reviewed_by}` : ''"
                        >
                          ✓ aprovada
                        </span>
                        <span
                          v-else-if="v.status === 'rejected'"
                          class="text-[10px] px-1.5 py-0.5 rounded-full font-semibold bg-n-alpha-2 text-n-slate-10"
                        >
                          ✗ recusada
                        </span>
                        <button
                          class="text-[11px] font-medium text-n-brand hover:underline flex items-center gap-1 ml-auto flex-shrink-0"
                          title="Copia gancho + texto + CTA — cole no Gerenciador de Anúncios ou no Estúdio"
                          @click="copyCreativeVariation(v)"
                        >
                          <span class="i-lucide-copy text-[10px]" /> 📋 Copiar
                        </button>
                      </div>
                      <p class="text-xs font-bold text-n-slate-12">{{ v.gancho }}</p>
                      <p class="text-[11px] text-n-slate-11 leading-relaxed" style="white-space: pre-line">{{ v.texto }}</p>
                      <p v-if="v.cta" class="text-[11px] text-n-slate-10"><b>CTA:</b> {{ v.cta }}</p>
                      <div v-if="v.status === 'pending'" class="flex items-center gap-2 pt-1">
                        <button
                          class="text-[11px] font-semibold text-white px-2.5 py-1 rounded-lg hover:opacity-90 disabled:opacity-50"
                          style="background: linear-gradient(135deg, #059669, #34D399)"
                          :disabled="reviewingCreative === `${wi}-${vi}`"
                          @click="reviewCreativeVariation(wi, vi, 'approved')"
                        >
                          ✓ Aprovar
                        </button>
                        <button
                          class="text-[11px] font-medium px-2.5 py-1 rounded-lg border border-n-weak text-n-slate-10 hover:bg-n-alpha-1 disabled:opacity-50"
                          :disabled="reviewingCreative === `${wi}-${vi}`"
                          @click="reviewCreativeVariation(wi, vi, 'rejected')"
                        >
                          ✗ Recusar
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </template>
              <p v-else-if="!loadingCreative && !isRunningCreative" class="text-xs text-n-slate-10">
                Nenhum criativo nesta semana ainda — toda segunda 08:30 ele gera sozinho, ou clique em "Gerar agora".
              </p>
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
        </template>
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

        <!-- Régua de período padrão CEVICO -->
        <PeriodRuler v-model="resultsPeriod" />

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

      <!-- ══ PAINEL DOS AGENTES DE IA (item 85, só admin) ══ -->
      <AiAgentsDashboard v-else-if="activeTab === 'painel_ia'" />

      <!-- ══ TRATAMENTO DE DADOS UNIFICADO (item 70) ══ -->
      <div v-else-if="activeTab === 'tratamento'" class="max-w-3xl">
        <p class="text-sm text-n-slate-11 mb-4">
          A casa de TODAS as ferramentas para tratar a base: identificação
          tradicional (filtros, etiquetas, unificação — sempre com prévia
          antes de aplicar) e identificação com inteligência.
        </p>
        <DataTreatmentTools />

        <!-- extras com IA que já moram no hub (só admin: mexem no Radar e na Agenda) -->
        <div v-if="isAdmin" class="grid sm:grid-cols-2 gap-4 mt-2 mb-6">
          <button
            class="text-left rounded-2xl border border-n-weak bg-n-solid-2 p-4 hover:border-n-brand transition-colors flex items-start gap-3"
            @click="showSweepModal = true"
          >
            <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #DC2626, #F59E0B)">
              <span class="i-lucide-scan-search text-white text-base" />
            </span>
            <span>
              <p class="text-sm font-bold text-n-slate-12 mb-1">Radar pontual</p>
              <p class="text-xs text-n-slate-10 leading-relaxed">
                Varredura ÚNICA por leads aguardando resposta (coluna + etiqueta +
                período) → avisos no Meu Painel. Não fica ativa.
              </p>
            </span>
          </button>
          <button
            class="text-left rounded-2xl border border-n-weak bg-n-solid-2 p-4 hover:border-n-brand transition-colors flex items-start gap-3"
            @click="showBackfillModal = true"
          >
            <span class="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style="background: linear-gradient(135deg, #B8860B, #D4A017)">
              <span class="i-lucide-calendar-search text-white text-base" />
            </span>
            <span>
              <p class="text-sm font-bold text-n-slate-12 mb-1">Preencher a Agenda com o histórico</p>
              <p class="text-xs text-n-slate-10 leading-relaxed">
                O Agente de Agendamento lê as confirmações antigas e registra as
                consultas na Agenda — sem duplicar, nada vai ao paciente.
              </p>
            </span>
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
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #059669, #4ADE80)" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-scan-search" style="color: #059669" />
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

    <!-- Janela: escolher a mensagem modelo da Colheitadeira -->
    <div
      v-if="showHarvestTemplatePicker"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="closeHarvestTemplatePicker"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-xl max-h-[92vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" :style="{ background: AGENT_META.harvest.gradient }" />
        <div class="flex items-center justify-between px-5 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-wheat" style="color: #CA8A04" />
            {{ harvestPickerTemplate ? 'Preencher variáveis do modelo' : 'Escolher mensagem modelo' }}
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="closeHarvestTemplatePicker" />
        </div>
        <div class="flex-1 overflow-y-auto p-5 space-y-3">
          <p class="text-[11px] text-n-slate-10">
            💡 Escreva <code class="bg-n-alpha-2 px-1 rounded">[gancho]</code> numa variável do corpo —
            a IA troca por um gancho pessoal para cada paciente;
            <code class="bg-n-alpha-2 px-1 rounded">[procedimento]</code> também funciona.
            O <code class="bg-n-alpha-2 px-1 rounded">{{ '\{\{contact.first_name\}\}' }}</code> vira o nome do paciente.
          </p>
          <WhatsAppTemplateParser
            v-if="harvestPickerTemplate"
            :template="harvestPickerTemplate"
            @send-message="useHarvestTemplate"
            @reset-template="harvestPickerTemplate = null"
          >
            <template #actions="{ sendMessage, resetTemplate, disabled }">
              <footer class="flex gap-2 justify-end">
                <button class="px-3 py-1.5 text-sm border border-n-weak rounded-lg text-n-slate-11" @click="resetTemplate">
                  Trocar modelo
                </button>
                <button
                  class="px-4 py-1.5 text-sm bg-n-brand text-white rounded-lg disabled:opacity-50"
                  :disabled="disabled"
                  @click="sendMessage"
                >
                  Usar este modelo
                </button>
              </footer>
            </template>
          </WhatsAppTemplateParser>
          <TemplatesPicker
            v-else
            :inbox-id="harvestPickerInboxId"
            @on-select="harvestPickerTemplate = $event"
          />
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

<style scoped>
/* sanfona dos agentes: aparição suave e leve */
.cevico-agent-body { animation: agentReveal 0.28s ease; }
@keyframes agentReveal { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: none; } }
</style>
