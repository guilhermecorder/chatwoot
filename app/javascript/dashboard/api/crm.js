/* global axios */
import ApiClient from './ApiClient';

class CrmAPI extends ApiClient {
  constructor() {
    super('crm', { accountScoped: true });
  }

  // ── Pipelines ─────────────────────────────────────────────────────
  getPipelines() {
    return axios.get(`${this.url}/pipelines`);
  }

  createPipeline(data) {
    return axios.post(`${this.url}/pipelines`, { pipeline: data });
  }

  updatePipeline(id, data) {
    return axios.put(`${this.url}/pipelines/${id}`, { pipeline: data });
  }

  deletePipeline(id) {
    return axios.delete(`${this.url}/pipelines/${id}`);
  }

  // ── Stages ────────────────────────────────────────────────────────
  createStage(pipelineId, data) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/stages`, {
      stage: data,
    });
  }

  updateStage(pipelineId, stageId, data) {
    return axios.put(`${this.url}/pipelines/${pipelineId}/stages/${stageId}`, {
      stage: data,
    });
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(
      `${this.url}/pipelines/${pipelineId}/stages/${stageId}`
    );
  }

  // 🧹 auditoria 12/10 (#288): apaga a coluna movendo TODOS os cards para a
  // coluna de destino numa só operação no servidor (transação)
  deleteStageMovingTo(pipelineId, stageId, targetStageId) {
    return axios.delete(
      `${this.url}/pipelines/${pipelineId}/stages/${stageId}/destroy_moving_to`,
      { params: { target_stage_id: targetStageId } }
    );
  }

  reorderStages(pipelineId, stageIds) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/stages/reorder`, {
      stage_ids: stageIds,
    });
  }

  // ── Campanhas (mensagens em massa) ────────────────────────────────
  getCampaigns() {
    return axios.get(`${this.url}/campaigns`);
  }

  getCampaign(id) {
    return axios.get(`${this.url}/campaigns/${id}`);
  }

  createCampaign(data) {
    return axios.post(`${this.url}/campaigns`, { campaign: data });
  }

  deleteCampaign(id) {
    return axios.delete(`${this.url}/campaigns/${id}`);
  }

  // 🚦 R3 da auditoria (#415): ignoreSchedule=true só depois que a pessoa
  // confirmou no modal que quer ignorar o horário agendado
  sendCampaign(id, { ignoreSchedule = false } = {}) {
    return axios.post(`${this.url}/campaigns/${id}/send_now`, {
      ignore_schedule: ignoreSchedule ? 1 : 0,
    });
  }

  // ⏸ R3 da auditoria (#415): pausa o envio / cancela o agendamento
  pauseCampaign(id) {
    return axios.post(`${this.url}/campaigns/${id}/pause`);
  }

  getCampaignResults(id) {
    return axios.get(`${this.url}/campaigns/${id}/results`);
  }

  // 🕐 R3 da auditoria (CONTRATO-0/#411): manda o valor do datetime-local
  // ("2026-10-08T08:00", sem fuso) e o SERVIDOR lê como hora de São Paulo
  scheduleCampaign(id, scheduledAt) {
    return axios.post(`${this.url}/campaigns/${id}/schedule`, {
      scheduled_at: scheduledAt,
    });
  }

  // ── Réguas de mensagens (automações) ──────────────────────────────
  getMessageAutomations() {
    return axios.get(`${this.url}/message_automations`);
  }

  createMessageAutomation(data) {
    return axios.post(`${this.url}/message_automations`, { automation: data });
  }

  updateMessageAutomation(id, data) {
    return axios.put(`${this.url}/message_automations/${id}`, {
      automation: data,
    });
  }

  deleteMessageAutomation(id) {
    return axios.delete(`${this.url}/message_automations/${id}`);
  }

  previewEligible(id) {
    return axios.get(`${this.url}/message_automations/${id}/preview_eligible`);
  }

  // ── Robôs de follow-up ────────────────────────────────────────────
  getFollowupBots(params = {}) {
    return axios.get(`${this.url}/followup_bots`, { params });
  }

  createFollowupBot(data) {
    return axios.post(`${this.url}/followup_bots`, { followup_bot: data });
  }

  // item 315: exemplo da cutucada escrita pela IA (nada é enviado)
  previewFollowupAi(data) {
    return axios.post(`${this.url}/followup_bots/ai_preview`, data);
  }

  updateFollowupBot(id, data) {
    return axios.put(`${this.url}/followup_bots/${id}`, { followup_bot: data });
  }

  deleteFollowupBot(id) {
    return axios.delete(`${this.url}/followup_bots/${id}`);
  }

  // 🧠 follow-up inteligente (13/10): leitura da conversa, lead frio, fim de
  // semana e reativação de quem adiou + resultado por coluna do CRM
  getFollowupSmart() {
    return axios.get(`${this.url}/followup_bots/smart`);
  }

  updateFollowupSmart(data) {
    return axios.put(`${this.url}/followup_bots/smart`, {
      followup_smart: data,
    });
  }

  getFollowupResults(params = {}) {
    return axios.get(`${this.url}/followup_bots/results`, { params });
  }

  getTrafficReport(params) {
    return axios.get(`${this.url}/traffic_report`, { params });
  }

  // ── 📈 Estúdio PRO MAX (item 129) ─────────────────────────────────
  // séries diárias do período (o estúdio agrega em semana/mês e faz candles)
  getProSeries(pipelineId, params = {}) {
    return axios.get(
      `${this.url}/pipelines/${pipelineId}/dashboard/pro_series`,
      { params }
    );
  }

  // 🟥 lista de resgate de UM motivo de perda (item 145)
  getLossContacts(pipelineId, params = {}) {
    return axios.get(
      `${this.url}/pipelines/${pipelineId}/dashboard/loss_contacts`,
      { params }
    );
  }

  // histórico de AÇÕES DA EMPRESA (marcadores da linha do tempo) — admin
  updateCompanyActions(companyActions) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      company_actions: companyActions,
    });
  }

  // ── Relatório de anúncios (Meta, atribuição CTWA) ─────────────────
  getAdsReport(params) {
    return axios.get(`${this.url}/ads_report`, { params });
  }

  backfillAdAttribution() {
    return axios.post(`${this.url}/ads_report/backfill`);
  }

  // ── Resumo da conversa (painel lateral) + análise de IA ───────────
  getConversationSummary(conversationId) {
    return axios.get(`${this.url}/conversation_summary`, {
      params: { conversation_id: conversationId },
    });
  }

  analyzeConversation(conversationId) {
    return axios.post(`${this.url}/conversation_summary/analyze`, {
      conversation_id: conversationId,
    });
  }

  // Consultor Comercial ao vivo: objeção + respostas prontas p/ a vendedora
  salesHelp(conversationId) {
    return axios.post(`${this.url}/conversation_summary/sales_help`, {
      conversation_id: conversationId,
    });
  }

  // TRAVA individual do follow-up: pausa/reativa as cutucadas p/ este paciente
  toggleFollowupPause(conversationId, paused) {
    return axios.post(`${this.url}/conversation_summary/toggle_followup`, {
      conversation_id: conversationId,
      paused,
    });
  }

  // 🤖 item 212: só o estado do Atendente IA nesta conversa (chavinha do topo)
  getResponderState(conversationId) {
    return axios.get(`${this.url}/conversation_summary/responder`, {
      params: { conversation_id: conversationId },
    });
  }

  // 🤖 item 207: liga/desliga o Atendente IA do WhatsApp para ESTA conversa
  toggleResponder(conversationId, paused) {
    return axios.post(`${this.url}/conversation_summary/toggle_responder`, {
      conversation_id: conversationId,
      paused,
    });
  }

  // chave de emergência: pausa/religa o robô inteiro (aberta às atendentes)
  toggleFollowupBot(botId) {
    return axios.post(`${this.url}/followup_bots/${botId}/toggle`);
  }

  // Consultor Comercial: gerar insights das conversas fechadas (gestão)
  generateSalesInsights() {
    return axios.post(`${this.url}/settings/sales_insights`);
  }

  updateAi(data) {
    return axios.post(`${this.url}/settings/update_ai`, data);
  }

  // 🕶️ rodada 188: tela Sombra do Atendente de Agendamento (o que a IA teria
  // respondido × o que foi respondido de verdade) + 👍/👎 do admin
  getAiShadow(params = {}) {
    return axios.get(`${this.url}/settings/ai_shadow`, { params });
  }

  // 🧪 simulador: conversar com o agente como paciente (caixa interna, sem envio)
  // item 298: conversa mais recente do paciente para o popup ({ contact_id } ou { phone })
  patientChat(params) {
    return axios.get(`${this.url}/patient_chat`, { params });
  }

  simulateAgent(payload) {
    return axios.post(`${this.url}/settings/ai_simulate`, payload);
  }

  // 🎙️ rodada 195: Agente de Ligação — roda a seleção de leads não
  // responsivos AGORA, em sombra (nada é discado) e devolve a lista de quem
  // ele ligaria hoje (botão "Ver quem ligaria hoje" no card)
  voiceShadowRun() {
    return axios.post(`${this.url}/settings/voice_shadow_run`);
  }

  rateAiShadow(messageId, rating, note) {
    return axios.post(`${this.url}/settings/ai_shadow_rate`, {
      message_id: messageId,
      rating,
      note,
    });
  }

  testAi() {
    return axios.post(`${this.url}/settings/test_ai`);
  }

  // ✍️ rodada 191: Orientações dos atendentes (o admin ensina o agente a
  // partir de uma resposta ruim; "Aplicar" escreve a regra no Roteiro ou nos
  // Passos da etapa, guardando uma versão antes)
  agentGuidances(params = {}) {
    return axios.get(`${this.url}/agent_guidances`, { params });
  }

  createAgentGuidance(payload) {
    return axios.post(`${this.url}/agent_guidances`, payload);
  }

  updateAgentGuidance(id, payload) {
    return axios.put(`${this.url}/agent_guidances/${id}`, payload);
  }

  applyAgentGuidance(id) {
    return axios.post(`${this.url}/agent_guidances/${id}/apply`);
  }

  ignoreAgentGuidance(id) {
    return axios.post(`${this.url}/agent_guidances/${id}/ignore`);
  }

  reopenAgentGuidance(id) {
    return axios.post(`${this.url}/agent_guidances/${id}/reopen`);
  }

  deleteAgentGuidance(id) {
    return axios.delete(`${this.url}/agent_guidances/${id}`);
  }

  // 🕘 versões do Roteiro / dos Passos (rodada 191): histórico e "Voltar para esta"
  scriptVersions() {
    return axios.get(`${this.url}/script_versions`);
  }

  restoreScriptVersion(id) {
    return axios.post(`${this.url}/script_versions/${id}/restore`);
  }

  getAiUsage(params = {}) {
    return axios.get(`${this.url}/settings/ai_usage`, { params });
  }

  updateAgendaWindows(windows) {
    return axios.post(`${this.url}/settings/update_agenda`, { windows });
  }

  // 💰 item 324: valores pré-configurados por tipo de atendimento (só admin)
  updateAppointmentPrices(prices) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      appointment_prices: prices,
    });
  }

  // 🗂️ item 307: regras da agenda para a IA + o que ela recebe agora
  // ⏱️ item 367: teto de avaliações por hora em cada unidade
  updateAgendaHourly(hourly) {
    return axios.post(`${this.url}/settings/update_agenda`, { hourly_evaluations: hourly });
  }

  updateAgendaAiRules(aiRules) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      ai_rules: aiRules,
    });
  }

  getAgendaAiPreview() {
    return axios.get(`${this.url}/settings/agenda_ai_preview`);
  }

  // 🕐 horário de envio dos robôs de follow-up (Automações → Robôs, item 147)
  updateFollowupHours(hours) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      followup_hours: hours,
    });
  }

  // 🚦 ritmo de envio por número (item 345): { per_window, minutes }
  updateFollowupPace(pace) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      followup_pace: pace,
    });
  }

  // 🏷️ etiquetas que encerram o follow-up de todos os robôs (rodada 158)
  updateFollowupStopLabels(labels) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      followup_stop_labels: labels,
    });
  }

  // 📅 lembretes do dia da consulta D-1/D-0 (Automações → Robôs, item 156)
  updateAppointmentReminders(reminders) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      appointment_reminders: reminders,
    });
  }

  // 📊 item 256: pesquisa de satisfação pós-cirurgia (NPS)
  saveNpsSurvey(survey) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      nps_survey: survey,
    });
  }

  // 📅 item 253: agente "Confirmação de consulta" (Agentes de IA) — lembretes
  // (dN = N dias antes) e/ou o interruptor geral; manda só o que vier
  // 🔁 item 343: taskAssigneeId = quem recebe as tarefas (id, 'retorno_team' ou null)
  saveAppointmentConfirmation({ reminders, enabled, taskAssigneeId } = {}) {
    const body = {};
    if (reminders !== undefined) body.appointment_reminders = reminders;
    if (enabled !== undefined) body.appointment_confirmation = { enabled };
    if (taskAssigneeId !== undefined) {
      body.appointment_confirmation = {
        ...(body.appointment_confirmation || {}),
        task_assignee_id: taskAssigneeId,
      };
    }
    return axios.post(`${this.url}/settings/update_agenda`, body);
  }

  // 🖐️ item 320: envio manual do lembrete — sem taskId = o lembrete inteiro
  // para quem falta; com taskId = este paciente (envia/reenvia)
  runAppointmentReminder(regua, taskId = null) {
    return axios.post(`${this.url}/appointment_reminders/run`, {
      regua,
      task_id: taskId,
    });
  }

  // 📅 ambiente Agendamentos (item 200): cada consulta marcada, remarcada ou
  // cancelada no período (preset/from/to, mode, kind, unit, inbox_id, q)
  // 🏥 item 229: ambiente Oftalmofácil (espelho do hub, só leitura)
  oftalmofacilOverview(params) {
    return axios.get(`${this.url}/oftalmofacil/overview`, { params });
  }

  oftalmofacilItems(params) {
    return axios.get(`${this.url}/oftalmofacil/items`, { params });
  }

  oftalmofacilPatients(params) {
    return axios.get(`${this.url}/oftalmofacil/patients`, { params });
  }

  oftalmofacilItem(id) {
    return axios.get(`${this.url}/oftalmofacil/items/${id}`);
  }

  // 👯 ponta 2 e 🗂️ ponta 3 (22/10)
  oftalmofacilMatching() {
    return axios.get(`${this.url}/oftalmofacil/matching`);
  }

  oftalmofacilSurgeryCards() {
    return axios.get(`${this.url}/oftalmofacil/surgery_cards`);
  }

  // 🔎 item 249: conferência de um dia (hub × Agenda) e trazer o que faltou
  oftalmofacilDayCheck(params) {
    return axios.get(`${this.url}/oftalmofacil/day_check`, { params });
  }

  oftalmofacilReconcileDay(date) {
    return axios.post(`${this.url}/oftalmofacil/reconcile_day`, { date });
  }

  appointmentsFeed(params) {
    return axios.get(`${this.url}/appointments/feed`, { params });
  }

  // item 277: quem entrou na coluna Agendamento de Consulta (caixa de origem, como foi, lista)
  appointmentsStageEntries(params) {
    return axios.get(`${this.url}/appointments/stage_entries`, { params });
  }

  // ajustes do que acontece ao confirmar uma consulta (etiquetas + coluna
  // do CRM ao marcar/remarcar/cancelar) — só admin
  updateAgendaBooking(booking) {
    return axios.post(`${this.url}/settings/update_agenda`, { booking });
  }

  // 🏥 OftalmoFácil (item 157): testar a conexão só-leitura + sincronizar agora
  testOftalmofacil() {
    return axios.post(`${this.url}/settings/test_oftalmofacil`);
  }

  syncOftalmofacil(full = false) {
    return axios.post(`${this.url}/settings/sync_oftalmofacil`, { full });
  }

  // 💰 Lucratividade das cirurgias (Financeiro, item 157)
  getProfitability(params = {}) {
    return axios.get(`${this.url}/finance/profitability`, { params });
  }

  // responsável por painel do Meu Painel (Configurações → Painéis)
  // 🧹 item 214: lista de Conversas limpa (sem coluna/etiquetas) para atendentes
  // modos: full (tudo) · no_stage (só sem a coluna) · clean (sem coluna e etiquetas)
  updateListClean(mode) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      list_clean_mode: mode,
      list_clean_for_agents: mode === 'clean',
    });
  }

  // 🎨 item 212: cor de cada pessoa ({user_id: '#hex'}; sem entrada = automática)
  updatePersonColors(personColors) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      person_colors: personColors,
    });
  }

  updatePanelOwners(panelOwners) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      panel_owners: panelOwners,
    });
  }

  // qual login o Atendimento IA usa (bloco "Meu desempenho")
  updateAiUser(userId) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      ai_user_id: userId,
    });
  }

  // tema (família de cores) por painel do Meu Painel (item 140)
  updatePanelThemes(panelThemes) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      panel_themes: panelThemes,
    });
  }

  // métricas individuais do "Meu desempenho" por pessoa (item 139)
  updatePerformanceMetrics(performanceMetrics) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      performance_metrics: performanceMetrics,
    });
  }

  // médicos com a agenda fechada (item 76) — item 366: porta da equipe
  updateClosedDoctors(closedDoctors) {
    return axios.post(`${this.url}/settings/update_agenda_locks`, {
      closed_doctors: closedDoctors,
    });
  }

  // etiquetas + resposta de formulário das consultas do dia (item 76)
  getAgendaDayDetails(taskIds) {
    return axios.get(`${this.url.replace(/crm$/, 'tasks')}/agenda_details`, {
      params: { ids: taskIds.join(',') },
    });
  }

  // cadeado de UM horário — item 366: porta da equipe (nó agenda.bloqueios)
  updateAgendaBlocked(blocked) {
    return axios.post(`${this.url}/settings/update_agenda_locks`, { blocked });
  }

  // item 267: rota própria, liberada para a equipe inteira (não só admin)
  updateAgendaBlockedDays(blockedDays) {
    return axios.post(`${this.url}/settings/update_blocked_days`, {
      blocked_days: blockedDays,
    });
  }

  // locais de cirurgia (clínicas parceiras — IOP etc.) do trilho de cirurgias
  updateSurgeryLocations(surgeryLocations) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      surgery_locations: surgeryLocations,
    });
  }

  // 🔬 janela de exames (unidade + dia + horário + bloco) — 23/09
  updateExamWindows(examWindows) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      exam_windows: examWindows,
    });
  }

  // janelas da sala cirúrgica (clínica + dia + horário + bloco)
  updateSurgeryWindows(surgeryWindows) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      surgery_windows: surgeryWindows,
    });
  }

  // tema visual dos ambientes (Santorini, Flor del Mar...) — admin
  updateTheme(theme) {
    return axios.post(`${this.url}/settings/update_agenda`, { theme });
  }

  // acessos de UM atendente (admin): áreas concedidas + menu do dia a dia.
  // Merge por usuário no servidor — nunca clobbera os demais.
  updateAgentGrants({ userId, grants, menu, reportKeys }) {
    return axios.post(`${this.url}/settings/update_agent_grants`, {
      user_id: userId,
      grants,
      menu,
      report_keys: reportKeys,
    });
  }

  // 🔐 rodada 334: acessos em árvore (ver × editar), papéis, unidades, empresa
  getAccessAdmin() {
    return axios.get(`${this.url}/settings/access_admin`);
  }

  // { userId, tree: { 'crm': 'edit' }, roleId, units: [], reset }
  updateAgentAccess({ userId, tree, roleId, units, reset }) {
    const body = { user_id: userId };
    if (tree !== undefined) body.tree = tree;
    if (roleId !== undefined) body.role_id = roleId;
    if (units !== undefined) body.units = units;
    if (reset) body.reset = true;
    return axios.post(`${this.url}/settings/update_agent_access`, body);
  }

  // a lista inteira de papéis: [{ id?, name, hint, tree, units }]
  updateAccessRoles(roles) {
    return axios.post(`${this.url}/settings/update_access_roles`, { roles });
  }

  // 🏢 Identidade da empresa (só admin)
  updateCompany(company) {
    return axios.post(`${this.url}/settings/update_company`, { company });
  }

  // tabela de preços oficial (Espaço do Paciente + prompts da IA) — admin
  updatePriceTable(items) {
    return axios.post(`${this.url}/settings/update_price_table`, { items });
  }

  // investimento por caixa + portas de entrada (ROI/CAC do Dashboard) — admin
  updateInboxInvestments(investments, captureInboxIds) {
    const payload = { investments };
    if (captureInboxIds) payload.capture_inbox_ids = captureInboxIds;
    return axios.post(`${this.url}/settings/update_inbox_investments`, payload);
  }

  // qual versão do Meu Painel cada agente vê — admin
  // 🧑‍🤝‍🧑 painéis por pessoa (rodada 160): [{id, name, base, user_ids}]
  updatePanelVariants(panelVariants) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      panel_variants: panelVariants,
    });
  }

  updatePanelAssignments(panelAssignments) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      panel_assignments: panelAssignments,
    });
  }

  // painéis do Construtor salvos por CONTA (aparecem no Meu Painel) — admin
  updateCustomPanels(customPanels) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      custom_panels: customPanels,
    });
  }

  // painel PRINCIPAL da conta (padrão do Meu Painel; '' volta ao de fábrica) — admin
  updateMainPanel(mainPanel) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      main_panel: mainPanel,
    });
  }

  // metas mensais por painel — os cards mudam de cor contra a meta
  updatePanelGoals(panelGoals) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      panel_goals: panelGoals,
    });
  }

  // conferência do dia → colunas do CRM (compareceu/faltou/cirurgia indicada)
  updateAttendanceStages(attendanceStages) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      attendance_stages: attendanceStages,
    });
  }

  // responsáveis pela conferência do dia (consultas/cirurgias) + prazo
  updateAttendanceOwners(attendanceOwners) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      attendance_owners: attendanceOwners,
    });
  }

  // 🔁 item 343: Equipe dos retornos (ids; só administrador)
  updateRetornoTeam(userIds) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      retorno_team_user_ids: userIds,
    });
  }

  // 27/09: papel e responsabilidades de cada pessoa (Mentor do Time)
  updateTeamRoles(teamRoles) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      team_roles: teamRoles,
    });
  }

  // preencher a Agenda com o histórico de confirmações das conversas
  agendaBackfill(params) {
    return axios.post(`${this.url}/settings/agenda_backfill`, params);
  }

  // colunas onde o Secretário da Agenda atua (sincroniza as automações)
  syncSchedulerStages(stageIds) {
    return axios.post(`${this.url}/settings/sync_scheduler_stages`, {
      stage_ids: stageIds,
    });
  }

  // colunas de atuação de qualquer agente de coluna (conversation/closing/nps)
  syncAgentStages(agent, stageIds) {
    return axios.post(`${this.url}/settings/sync_agent_stages`, {
      agent,
      stage_ids: stageIds,
    });
  }

  radarScan(params) {
    return axios.post(`${this.url}/settings/radar_scan`, params);
  }

  // ── Formulários (pré-operatório etc.) ─────────────────────────────
  getForms() {
    return axios.get(`${this.url}/forms`);
  }

  createForm(data) {
    return axios.post(`${this.url}/forms`, data);
  }

  updateForm(id, data) {
    return axios.put(`${this.url}/forms/${id}`, data);
  }

  deleteForm(id) {
    return axios.delete(`${this.url}/forms/${id}`);
  }

  getFormSummary(id, params = {}) {
    return axios.get(`${this.url}/forms/${id}/summary`, { params });
  }

  generateFormInsights(id) {
    return axios.post(`${this.url}/forms/${id}/generate_insights`);
  }

  getFormPreviewLink(id) {
    return axios.get(`${this.url}/forms/${id}/preview_link`);
  }

  // ── Tratamento de dados (etiqueta retroativa) ─────────────────────
  previewRetroLabel(data) {
    return axios.post(`${this.url}/retro_labels/preview`, data);
  }

  applyRetroLabel(data) {
    return axios.post(`${this.url}/retro_labels/apply`, data);
  }

  // Radar: "Atender agora" remove o aviso da fila oficial (-1 p/ todos)
  radarAttend(conversationId) {
    return axios.post(`${this.url}/radar/attend`, {
      conversation_id: conversationId,
    });
  }

  // mover o card do CRM direto da conversa
  moveConversationStage(conversationId, stageId) {
    return axios.post(`${this.url}/conversation_summary/move_stage`, {
      conversation_id: conversationId,
      stage_id: stageId,
    });
  }

  // dashboard de resultados das automações de coluna
  getAutomationsDashboard(params = {}) {
    return axios.get(`${this.url}/automations_dashboard`, { params });
  }

  // dashboard dos médicos (conversão consulta→cirurgia, NPS, clínicas)
  getDoctorsDashboard(params = {}) {
    return axios.get(`${this.url}/doctors_dashboard`, { params });
  }

  // 🩺 Ambiente do médico (item 104): perfis de gestão — só admin
  saveDoctorProfiles(profiles) {
    return axios.post(`${this.url}/doctors_dashboard/save_profiles`, {
      profiles,
    });
  }

  // dashboard dos agentes (equipe humana: atendimento + resposta ao Radar)
  getAgentsDashboard(params = {}) {
    return axios.get(`${this.url}/agents_dashboard`, { params });
  }

  // dashboard da agenda (comparecimento, modalidades, médicos, cirurgias)
  getAgendaDashboard(params = {}) {
    return axios.get(`${this.url}/agenda_dashboard`, { params });
  }

  // mover e etiquetar cards em lote (coluna/valor/caixa/etiqueta)
  previewBatchUpdate(data) {
    return axios.post(`${this.url}/batch_updates/preview`, data);
  }

  applyBatchUpdate(data) {
    return axios.post(`${this.url}/batch_updates/apply`, data);
  }

  // cirurgias feitas FORA do sistema (lista de telefones → coluna do CRM)
  previewExternalSurgeries(data) {
    return axios.post(`${this.url}/external_surgeries/preview`, data);
  }

  applyExternalSurgeries(data) {
    return axios.post(`${this.url}/external_surgeries/apply`, data);
  }

  // 📄 planilha de fechamento (item 132): upload .xlsx → prévia por NOME → importar
  previewClosingSheet(formData) {
    return axios.post(
      `${this.url}/external_surgeries/preview_sheet`,
      formData,
      {
        headers: { 'Content-Type': 'multipart/form-data' },
      }
    );
  }

  applyClosingSheet(data) {
    return axios.post(`${this.url}/external_surgeries/apply_sheet`, data);
  }

  // 🤖 IA acha "mesma pessoa escrita diferente" nos não-casados (item 154)
  aiMatchClosingSheet(data) {
    return axios.post(`${this.url}/external_surgeries/ai_match_sheet`, data);
  }

  // ↩️ desfazer a última importação de cirurgias (item 133)
  getImportStatus() {
    return axios.get(`${this.url}/external_surgeries/import_status`);
  }

  undoLastImport(id) {
    return axios.post(`${this.url}/external_surgeries/undo_last`, { id });
  }

  previewLabelReplace(data) {
    return axios.post(`${this.url}/label_replacements/preview`, data);
  }

  applyLabelReplace(data) {
    return axios.post(`${this.url}/label_replacements/apply`, data);
  }

  previewLabelRemove(data) {
    return axios.post(`${this.url}/label_removals/preview`, data);
  }

  applyLabelRemove(data) {
    return axios.post(`${this.url}/label_removals/apply`, data);
  }

  // ── Unificação de contatos duplicados ─────────────────────────────
  previewContactUnification() {
    return axios.post(`${this.url}/contact_unification/preview`);
  }

  applyContactUnification() {
    return axios.post(`${this.url}/contact_unification/apply`);
  }

  // category (marketing | utility | authentication) = tarifa usada no custo estimado
  previewAudience(audience, category = 'marketing') {
    return axios.post(`${this.url}/campaigns/preview_audience`, {
      audience,
      category,
    });
  }

  getWhatsappTemplates(inboxId, all = false) {
    return axios.get(`${this.url}/campaigns/templates`, {
      params: all ? { inbox_id: inboxId, all: 1 } : { inbox_id: inboxId },
    });
  }

  // ── Contacts ──────────────────────────────────────────────────────
  getContacts(pipelineId, params = {}) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/contacts`, {
      params,
    });
  }

  addContact(pipelineId, data) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/contacts`, data);
  }

  updateContact(pipelineId, id, data) {
    return axios.put(
      `${this.url}/pipelines/${pipelineId}/contacts/${id}`,
      data
    );
  }

  removeContact(pipelineId, id) {
    return axios.delete(`${this.url}/pipelines/${pipelineId}/contacts/${id}`);
  }

  getContactHistory(pipelineId, contactId) {
    return axios.get(
      `${this.url}/pipelines/${pipelineId}/contacts/${contactId}/history`
    );
  }

  triggerLabelChange(pipelineId, contactId, { added, removed }) {
    return axios.post(
      `${this.url}/pipelines/${pipelineId}/contacts/${contactId}/trigger_label_change`,
      { added, removed }
    );
  }

  startConversation(pipelineId, contactId, inboxId) {
    return axios.post(
      `${this.url}/pipelines/${pipelineId}/contacts/${contactId}/start_conversation`,
      { inbox_id: inboxId }
    );
  }

  detectCardValue(pipelineId, contactId) {
    return axios.post(
      `${this.url}/pipelines/${pipelineId}/contacts/${contactId}/detect_value`
    );
  }

  detectValuesBulk(pipelineId, onlyEmpty = true) {
    return axios.post(
      `${this.url}/pipelines/${pipelineId}/contacts/detect_values_bulk`,
      { only_empty: onlyEmpty }
    );
  }

  // ── Settings / n8n ────────────────────────────────────────────────
  getSettings() {
    return axios.get(`${this.url}/settings`);
  }

  updateSettings(data) {
    return axios.patch(`${this.url}/settings`, data);
  }

  testN8n() {
    return axios.post(`${this.url}/settings/test_n8n`);
  }

  fetchN8nWorkflows() {
    return axios.post(`${this.url}/settings/fetch_workflows`);
  }

  // ── Meta Ads ──────────────────────────────────────────────────────
  updateMetaAds(data) {
    return axios.post(`${this.url}/settings/update_meta_ads`, data);
  }

  testMetaAds() {
    return axios.post(`${this.url}/settings/test_meta_ads`);
  }

  // ── Google Ads ────────────────────────────────────────────────────
  updateGoogleAds(data) {
    return axios.post(`${this.url}/settings/update_google_ads`, data);
  }

  testGoogleAds() {
    return axios.post(`${this.url}/settings/test_google_ads`);
  }

  // 🔎 16/10: Search Console (mesma conta de serviço do GA4)
  testSearchConsole() {
    return axios.post(`${this.url}/settings/test_search_console`);
  }

  // ── Google Sheets (planilha de cirurgias) ─────────────────────────
  updateSheets(data) {
    return axios.post(`${this.url}/settings/update_sheets`, data);
  }

  testSheets() {
    return axios.post(`${this.url}/settings/test_sheets`);
  }

  // ── 📞 Ligações (WhatsApp) — item 167 ─────────────────────────────
  updateCalls(data) {
    return axios.post(`${this.url}/settings/update_calls`, data);
  }

  enableCallsAtMeta(inboxId = null) {
    return axios.post(`${this.url}/settings/enable_calls_at_meta`, {
      inbox_id: inboxId,
    });
  }

  callsMetaStatus(inboxId = null) {
    return axios.get(`${this.url}/settings/calls_meta_status`, {
      params: inboxId ? { inbox_id: inboxId } : {},
    });
  }

  // ── 🤖📞 Agente de Ligação (ElevenLabs) — item 169 ────────────────
  updateVoice(data) {
    return axios.post(`${this.url}/settings/update_voice`, data);
  }

  testVoice() {
    return axios.post(`${this.url}/settings/test_voice`);
  }

  syncVoice() {
    return axios.post(`${this.url}/settings/sync_voice`);
  }

  voiceWhatsappAccounts() {
    return axios.get(`${this.url}/settings/voice_whatsapp_accounts`);
  }

  voiceVoices(params = {}) {
    return axios.get(`${this.url}/settings/voice_voices`, { params });
  }

  voiceState() {
    return axios.get(`${this.url}/settings/voice_state`);
  }

  // ── 🗺️ Mapa de Fluxos dos agentes — item 170 ──────────────────────
  getFlows() {
    return axios.get(`${this.url}/flows`);
  }

  getFlow(key) {
    return axios.get(`${this.url}/flows/${key}`);
  }

  // ── Meu Painel ────────────────────────────────────────────────────
  // cesto de indicadores c/ série + período anterior (item 141)
  getKpiBag(params = {}) {
    return axios.get(`${this.url}/home/kpis`, { params });
  }

  // 🌪️ item 271: funil de aquisição por turma (90 dias) + da porta pra dentro
  getAcquisitionFunnel(params = {}) {
    return axios.get(`${this.url}/funnels/acquisition`, { params });
  }

  getClinicFunnel(params = {}) {
    return axios.get(`${this.url}/funnels/clinic`, { params });
  }

  // ordem + ocultos + cores da fileira de indicadores por painel (itens 142/143)
  updateKpiLayout(kpiLayout) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      kpi_layout: kpiLayout,
    });
  }

  // ordem dos BLOCOS do Meu Painel por painel (item 143)
  updateBlockLayout(blockLayout) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      block_layout: blockLayout,
    });
  }

  // 🍎🍊 paletas do Meu Painel por painel (rodada 162): modo do painel (cor
  // do dia / fixa / salada) + paleta por bloco — {painel => {mode, key, blocks}}
  updatePanelPalettes(panelPalettes) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      panel_palettes: panelPalettes,
    });
  }

  // cards de indicador criados pelo admin no "+" do Meu Painel (item 141)
  updateCustomKpis(customKpis) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      custom_kpis: customKpis,
    });
  }

  // 🔒 Rodada 4 (#351): só o que mudou nos cards ({ upsert, remove,
  // remove_prefix }) — o servidor mescla pelo id em cima da lista do banco,
  // então dois admins criando/apagando cards ao mesmo tempo não se apagam
  patchCustomKpis(patch) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      custom_kpis_patch: patch,
    });
  }

  getHome(params = {}) {
    return axios.get(`${this.url}/home`, { params });
  }

  // 🧭 item 337: visão geral do Meu Painel (14 perguntas)
  getOverview(params = {}) {
    return axios.get(`${this.url}/home/overview`, { params });
  }

  // 🎂 item 331: informar o aniversário (dia, mês, ano opcional); clear = apagar
  saveBirthday(payload) {
    return axios.post(`${this.url}/home/birthday`, payload);
  }

  // ── Dashboard de Campanhas ────────────────────────────────────────
  getCampaignsDashboard(params = {}) {
    return axios.get(`${this.url}/campaigns_dashboard`, { params });
  }

  // ── Dashboard ─────────────────────────────────────────────────────
  getDashboard(pipelineId, params = {}) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/dashboard`, {
      params,
    });
  }

  // ── Páginas CEVICO ────────────────────────────────────────────────
  getPages() {
    return axios.get(`${this.url}/pages`);
  }

  createPage(data) {
    return axios.post(`${this.url}/pages`, data);
  }

  updatePage(id, data) {
    return axios.put(`${this.url}/pages/${id}`, data);
  }

  deletePage(id) {
    return axios.delete(`${this.url}/pages/${id}`);
  }

  // agente copywriter escreve a página inteira em seções
  generatePage(data) {
    return axios.post(`${this.url}/pages/generate`, data);
  }

  // item 111: geração em segundo plano — agenda e consulta o status
  generatePageStart(data) {
    return axios.post(`${this.url}/pages/generate_start`, data);
  }

  generatePageStatus(jobId) {
    return axios.get(`${this.url}/pages/generate_status`, {
      params: { job_id: jobId },
    });
  }

  // imagem de seção (editor de retoques)
  uploadPageImage(file) {
    const formData = new FormData();
    formData.append('image', file);
    return axios.post(`${this.url}/pages/upload_image`, formData);
  }

  // Estúdio do Copywriter: carrossel, roteiro de reels, post, anúncio
  generateCopyContent(data) {
    return axios.post(`${this.url}/settings/copywriter_content`, data);
  }

  testGemini() {
    return axios.post(`${this.url}/settings/test_gemini`);
  }

  // popup de prioridade máxima do Radar + pausa manual (com registro)
  radarPing() {
    return axios.get(`${this.url}/home/radar_ping`);
  }

  toggleRadar() {
    return axios.post(`${this.url}/home/toggle_radar`);
  }

  // feedback de bugs do time → card 🐞 no board do admin
  reportBug(data) {
    return axios.post(`${this.url}/bug_reports`, data);
  }

  // Configurações → Domínio (público das páginas/formulários)
  getPublicDomain() {
    return axios.get(`${this.url}/settings/public_domain`);
  }

  updatePublicDomain(host) {
    return axios.post(`${this.url}/settings/update_public_domain`, { host });
  }

  checkPublicDomain(host) {
    return axios.post(`${this.url}/settings/check_public_domain`, { host });
  }

  // ── Central do Paciente ───────────────────────────────────────────
  // 🔎 item 346: busca que puxa o paciente (nome sem acento, telefone com/sem 9)
  searchPatients(q, { signal, limit } = {}) {
    return axios.get(`${this.url}/patients/search`, {
      params: { q, limit },
      signal,
    });
  }

  // 🔔 item 346: Notificações sobre agendamentos (divergências para conferir)
  getAppointmentAlerts() {
    return axios.get(`${this.url}/appointment_alerts`);
  }

  getAppointmentAlertsCount() {
    return axios.get(`${this.url}/appointment_alerts/count`);
  }

  appointmentAlertAction(action, data) {
    return axios.post(`${this.url}/appointment_alerts/${action}`, data);
  }

  patientPhoneOwner(phone) {
    return axios.get(`${this.url}/patients/phone_owner`, { params: { phone } });
  }

  getPatient(contactId) {
    return axios.get(`${this.url}/patients/${contactId}`);
  }

  // sexo/nascimento do paciente (muda o tema dopamine da página)
  updatePatientProfile(contactId, profile) {
    return axios.post(
      `${this.url}/patients/${contactId}/update_profile`,
      profile
    );
  }

  getClinicalNotes(contactId) {
    return axios.get(`${this.url}/patients/${contactId}/clinical_notes`);
  }

  // fotos vão junto → FormData (multipart)
  createClinicalNote(contactId, formData) {
    return axios.post(
      `${this.url}/patients/${contactId}/clinical_notes`,
      formData
    );
  }

  updateClinicalNote(contactId, noteId, formData) {
    return axios.put(
      `${this.url}/patients/${contactId}/clinical_notes/${noteId}`,
      formData
    );
  }

  deleteClinicalNote(contactId, noteId) {
    return axios.delete(
      `${this.url}/patients/${contactId}/clinical_notes/${noteId}`
    );
  }

  updateClinicalAccess(clinicalAccess) {
    return axios.post(`${this.url}/settings/update_agenda`, {
      clinical_access: clinicalAccess,
    });
  }

  // Mentor do Time: gera o feedback semanal agora (últimos 7 dias, admin)
  runMentor() {
    return axios.post(`${this.url}/settings/run_mentor`);
  }

  // ── 🌾 Colheitadeira da Base (reativação mensal da base fria) ─────
  getHarvestStatus() {
    return axios.get(`${this.url}/settings/harvest_status`);
  }

  // gera a prévia do mês em segundo plano (~1-2 min; repollar o status)
  harvestPreview() {
    return axios.post(`${this.url}/settings/harvest_preview`);
  }

  harvestApprove() {
    return axios.post(`${this.url}/settings/harvest_approve`);
  }

  harvestPause() {
    return axios.post(`${this.url}/settings/harvest_pause`);
  }

  harvestResume() {
    return axios.post(`${this.url}/settings/harvest_resume`);
  }

  // tira UM lead da colheita do mês (ele não recebe a mensagem)
  harvestSkipLead(contactId) {
    return axios.post(`${this.url}/settings/harvest_skip_lead`, {
      contact_id: contactId,
    });
  }

  // dispara o lote de hoje agora (só com a colheita aprovada)
  harvestSendNow() {
    return axios.post(`${this.url}/settings/harvest_send_now`);
  }

  // 📊 Gestor Autônomo: lê o funil agora e atualiza o briefing do dia
  runManager() {
    return axios.post(`${this.url}/settings/run_manager`);
  }

  // 🎓 Auditor de Conversas: re-audita as conversas de ontem (~1-2 min)
  runAuditor() {
    return axios.post(`${this.url}/settings/run_auditor`);
  }

  // ranking por atendente + falhas mais comuns do time (janela em dias)
  // item 321: params = { preset, from, to } da régua padrão
  getAuditorSummary(params = { preset: 'last7' }) {
    return axios.get(`${this.url}/settings/auditor_summary`, { params });
  }

  // 🎨 Criativo Perpétuo: gera as variações da semana agora (~1-2 min)
  runCreative() {
    return axios.post(`${this.url}/settings/run_creative`);
  }

  // vencedores da semana + variações + despensa de aprovadas
  getCreativeState() {
    return axios.get(`${this.url}/settings/creative_state`);
  }

  // aprova/recusa UMA variação (pelos índices do vencedor e da variação)
  reviewCreative(winnerIndex, variationIndex, status) {
    return axios.post(`${this.url}/settings/creative_review`, {
      winner_index: winnerIndex,
      variation_index: variationIndex,
      status,
    });
  }

  // ── PÁGINAS PRO: análise, funis, comentários ──────────────────────
  getPagesDashboard() {
    return axios.get(`${this.url}/pages_dashboard`);
  }

  // 📈 Resultados de tráfego: origem → visitas → leads → agendou → cirurgia
  getPagesReport(params = {}) {
    return axios.get(`${this.url}/pages_report`, { params });
  }

  // 💡 item 329: coleção de insights das páginas (guardar / mudar situação /
  // apagar) e sugestões da IA para uma página no período da régua
  savePageInsight(payload) {
    return axios.post(`${this.url}/pages_report/save_insight`, payload);
  }

  removePageInsight(id) {
    return axios.post(`${this.url}/pages_report/remove_insight`, { id });
  }

  getPageAiSuggestions(params = {}) {
    return axios.post(`${this.url}/pages_report/ai_suggestions`, params);
  }

  // 🔎 16/10: pede ao Google uma foto nova do Search Console (roda no Sidekiq)
  refreshSearchConsole() {
    return axios.post(`${this.url}/pages_report/search_console_refresh`);
  }

  // 🚪 Porta de entrada (hub) na raiz do domínio dedicado
  updatePublicHub(payload) {
    return axios.post(`${this.url}/settings/update_public_hub`, payload);
  }

  // 📊 Rastreamento central (item 117): Pixel da Meta + GA4 nas páginas
  updatePublicTracking(payload) {
    return axios.post(`${this.url}/settings/update_public_tracking`, payload);
  }

  // 🌪 Montador de Funis (item 60): fontes de captação por funil
  saveFunnelSources(payload) {
    return axios.post(
      `${this.url}/pages_dashboard/save_funnel_sources`,
      payload
    );
  }

  // 📝 notas dos pacientes (item 211): lista da clínica, criar, apagar
  patientNotes(params = {}) {
    return axios.get(`${this.url}/patient_notes`, { params });
  }

  createPatientNote(contactId, content) {
    return axios.post(`${this.url}/patient_notes`, {
      contact_id: contactId,
      content,
    });
  }

  deletePatientNote(id) {
    return axios.delete(`${this.url}/patient_notes/${id}`);
  }

  // item 95: renovar os ambientes (concluídos → coluna oculta)
  archiveDoneTasks() {
    return axios.post(`${this.url.replace(/crm$/, 'tasks')}/archive_done`);
  }

  archivePublishedContent() {
    return axios.post(`${this.url}/content_items/archive_published`);
  }

  addPageComment(pageId, text) {
    return axios.post(`${this.url}/pages/${pageId}/add_comment`, { text });
  }

  deletePageComment(pageId, commentId) {
    return axios.post(`${this.url}/pages/${pageId}/delete_comment`, {
      comment_id: commentId,
    });
  }

  // ── Planejamento de conteúdos (workflow de marketing) ─────────────
  getContentItems() {
    return axios.get(`${this.url}/content_items`);
  }

  createContentItem(data) {
    // envelope content_item: o "format" solto colidia com o format da rota
    return axios.post(`${this.url}/content_items`, { content_item: data });
  }

  updateContentItem(id, data) {
    return axios.put(`${this.url}/content_items/${id}`, { content_item: data });
  }

  deleteContentItem(id) {
    return axios.delete(`${this.url}/content_items/${id}`);
  }

  // ── Ambiente Pessoas (DISC + desenvolvimento + feedbacks) ─────────
  getPeople() {
    return axios.get(`${this.url}/people`);
  }

  saveDisc(scores) {
    return axios.post(`${this.url}/people/save_disc`, { scores });
  }

  savePersonGoals(userId, goals) {
    return axios.post(`${this.url}/people/save_goals`, {
      user_id: userId,
      goals,
    });
  }

  // testes arquivados (disc v2 / 4 temperamentos) + espaço de vida
  saveAssessment(kind, scores, answers = []) {
    return axios.post(`${this.url}/people/save_assessment`, {
      kind,
      scores,
      answers,
    });
  }

  saveLife(payload) {
    return axios.post(`${this.url}/people/save_life`, payload);
  }

  // ── Painel de Metas (multi-período: period = day/week/weekend/month/quarter/year) ──
  getGoalPlans(month, period) {
    return axios.get(`${this.url}/goal_plans`, { params: { month, period } });
  }

  upsertGoalPlan(payload) {
    return axios.post(`${this.url}/goal_plans/upsert`, payload);
  }

  addGoalNote(month, text, aboutUserId, period) {
    return axios.post(`${this.url}/goal_plans/add_note`, {
      month,
      text,
      about_user_id: aboutUserId,
      period,
    });
  }

  deleteGoalNote(month, noteId, period) {
    return axios.post(`${this.url}/goal_plans/delete_note`, {
      month,
      note_id: noteId,
      period,
    });
  }

  updateRoutinesTools(payload) {
    return axios.post(`${this.url}/goal_plans/update_routines`, payload);
  }

  // ── Ferramentas de Fechamento (script + mapa de objeções) ─────────
  getClosingTools() {
    return axios.get(`${this.url}/closing_tools`);
  }

  updateClosingScript(script) {
    return axios.post(`${this.url}/closing_tools/update_script`, { script });
  }

  generateObjectionMap() {
    return axios.post(`${this.url}/closing_tools/generate_map`);
  }

  // ── Dashboard Google (Ads + GA4) ───────────────────────────────────
  getGoogleDashboard(params = {}) {
    return axios.get(`${this.url}/google_dashboard`, { params });
  }

  // ── Gestão Financeira (só admin) ───────────────────────────────────
  getFinance(params) {
    return axios.get(`${this.url}/finance`, { params });
  }

  createFinanceEntry(payload) {
    return axios.post(`${this.url}/finance/create_entry`, payload);
  }

  updateFinanceEntry(entryId, payload) {
    return axios.post(`${this.url}/finance/update_entry`, {
      entry_id: entryId,
      ...payload,
    });
  }

  deleteFinanceEntry(entryId) {
    return axios.post(`${this.url}/finance/delete_entry`, {
      entry_id: entryId,
    });
  }

  compareFinanceMonths(monthA, monthB) {
    return axios.get(`${this.url}/finance/compare`, {
      params: { month_a: monthA, month_b: monthB },
    });
  }

  // ── OftalmoFácil (conexão nativa) ───────────────────────────────────
  updateOftalmofacil(payload) {
    return axios.post(`${this.url}/settings/update_oftalmofacil`, payload);
  }

  // ── Dashboard dos agentes de IA (só admin) ──────────────────────────
  // aceita { preset, from, to } (régua padrão) ou string legada de preset
  getAiDashboard(params = {}) {
    const query = typeof params === 'string' ? { preset: params } : params;
    return axios.get(`${this.url}/ai_dashboard`, { params: query });
  }

  // ── 💸 Gasto do WhatsApp (item 303, só admin) ────────────────────────
  getWhatsappSpend(params = {}) {
    return axios.get(`${this.url}/whatsapp_spend`, { params });
  }

  saveWhatsappRates(payload) {
    return axios.post(`${this.url}/whatsapp_spend/rates`, payload);
  }

  syncWhatsappSpend(days = 35) {
    return axios.post(`${this.url}/whatsapp_spend/sync`, { days });
  }

  // ── 🚦 Saúde do WhatsApp (16/10): números, modelos, quem não quer receber ──
  getWhatsappHealth() {
    return axios.get(`${this.url}/whatsapp_health`);
  }

  saveWhatsappHealthSettings(payload) {
    return axios.post(`${this.url}/whatsapp_health/settings`, payload);
  }

  unmarkWhatsappSignal(contactId, key) {
    return axios.post(`${this.url}/whatsapp_health/unmark`, {
      contact_id: contactId,
      key,
    });
  }

  confirmWhatsappSignal(contactId, key) {
    return axios.post(`${this.url}/whatsapp_health/confirm`, {
      contact_id: contactId,
      key,
    });
  }

  scanWhatsappHealth() {
    return axios.post(`${this.url}/whatsapp_health/scan`);
  }

  // ── 🏷️ Fontes de pacientes (item 322; só admin) ───
  getSources() {
    return axios.get(`${this.url}/sources`);
  }

  createSource(payload) {
    return axios.post(`${this.url}/sources`, payload);
  }

  updateSource(id, payload) {
    return axios.patch(`${this.url}/sources/${id}`, payload);
  }

  // apply: false = prévia do que seria carimbado; true = grava
  // 🧩 item 344: pré-definição das colunas do funil do Oftalmofácil
  getFunnelPreset() {
    return axios.get(`${this.url}/sources/funnel_preset`);
  }

  applyFunnelPreset() {
    return axios.post(`${this.url}/sources/funnel_preset`);
  }

  backfillSources(apply = false) {
    return axios.post(`${this.url}/sources/backfill`, { apply });
  }

  // ── 💰 Financeiro & CAC (item 318; admin ou concessão Financeiro) ───
  getAcquisitionCost(params = {}) {
    return axios.get(`${this.url}/acquisition_cost`, { params });
  }

  // 📈 custo por fonte ao longo do tempo + faturamento × etapas do CRM (19/10)
  getAcquisitionTimeline(params = {}) {
    return axios.get(`${this.url}/acquisition_cost/timeline`, { params });
  }

  // ── 📄 Agente de Páginas (item 353): placar, pódio, linha do tempo e fila ──
  getPageAgent(params = {}) {
    return axios.get(`${this.url}/page_agent`, { params });
  }

  getPageTimeline(pageId, days = 90) {
    return axios.get(`${this.url}/page_agent/timeline`, {
      params: { page_id: pageId, days },
    });
  }

  getPageActionSteps(id) {
    return axios.get(`${this.url}/page_agent/steps`, { params: { id } });
  }

  decidePageAction(id, decision) {
    return axios.post(`${this.url}/page_agent/decide`, { id, decision });
  }

  manualPageAction(id) {
    return axios.post(`${this.url}/page_agent/manual`, { id });
  }

  runPageAgent() {
    return axios.post(`${this.url}/page_agent/run`);
  }

  // ── 🎯 Agente de Campanhas (item 352): Meta + Google, nossa média,
  // recomendações (aprovar → aplicar → aprender), parâmetros e ficha de subida
  getCampaignAgent(params = {}) {
    return axios.get(`${this.url}/campaign_agent`, { params });
  }

  saveCampaignAgentParams(payload) {
    return axios.post(`${this.url}/campaign_agent/params`, { params: payload });
  }

  decideCampaignAction(id, decision) {
    return axios.post(`${this.url}/campaign_agent/decide`, { id, decision });
  }

  applyCampaignAction(id) {
    return axios.post(`${this.url}/campaign_agent/apply`, { id });
  }

  manualCampaignAction(id) {
    return axios.post(`${this.url}/campaign_agent/manual`, { id });
  }

  runCampaignAgent() {
    return axios.post(`${this.url}/campaign_agent/run`);
  }

  saveCampaignBrief(brief) {
    return axios.post(`${this.url}/campaign_agent/brief`, { brief });
  }

  launchCampaignBrief(id) {
    return axios.post(`${this.url}/campaign_agent/launch`, { id });
  }

  removeCampaignBrief(id) {
    return axios.post(`${this.url}/campaign_agent/remove_brief`, { id });
  }

  // ── Ferramentas da Academia (time lê; admin escreve) ────────────────
  getTeamTools() {
    return axios.get(`${this.url}/team_tools`);
  }

  createTeamTool(payload) {
    return axios.post(`${this.url}/team_tools`, payload);
  }

  updateTeamTool(toolId, payload) {
    return axios.patch(`${this.url}/team_tools/${toolId}`, payload);
  }

  deleteTeamTool(toolId) {
    return axios.delete(`${this.url}/team_tools/${toolId}`);
  }

  // ── Estoque (dashboard/CRUD = área financeira; lookup/pedido = time) ─
  getStock() {
    return axios.get(`${this.url}/stock`);
  }

  createStockItem(payload) {
    return axios.post(`${this.url}/stock/create_item`, payload);
  }

  updateStockItem(itemId, payload) {
    return axios.post(`${this.url}/stock/update_item`, {
      item_id: itemId,
      ...payload,
    });
  }

  deleteStockItem(itemId) {
    return axios.post(`${this.url}/stock/delete_item`, { item_id: itemId });
  }

  lookupStock(q) {
    return axios.get(`${this.url}/stock/lookup`, { params: { q } });
  }

  createStockOrder(payload) {
    return axios.post(`${this.url}/stock/create_order`, payload);
  }

  updateStockOrder(orderId, status) {
    return axios.post(`${this.url}/stock/update_order`, {
      order_id: orderId,
      status,
    });
  }

  deleteStockOrder(orderId) {
    return axios.post(`${this.url}/stock/delete_order`, { order_id: orderId });
  }

  // ── Painel Estratégico (pilares do negócio, só admin) ─────────────
  getStrategyBoard() {
    return axios.get(`${this.url}/strategy`);
  }

  createStrategyPillar(data) {
    return axios.post(`${this.url}/strategy/create_pillar`, data);
  }

  updateStrategyPillar(pillarId, data) {
    return axios.post(`${this.url}/strategy/update_pillar`, {
      pillar_id: pillarId,
      ...data,
    });
  }

  deleteStrategyPillar(pillarId) {
    return axios.post(`${this.url}/strategy/delete_pillar`, {
      pillar_id: pillarId,
    });
  }

  createStrategyItem(pillarId, data) {
    return axios.post(`${this.url}/strategy/create_item`, {
      pillar_id: pillarId,
      ...data,
    });
  }

  updateStrategyItem(itemId, data) {
    return axios.post(`${this.url}/strategy/update_item`, {
      item_id: itemId,
      ...data,
    });
  }

  deleteStrategyItem(itemId) {
    return axios.post(`${this.url}/strategy/delete_item`, { item_id: itemId });
  }

  // 🏭 Desenho do Processo (item 59)
  saveStrategyProcesses(processes) {
    return axios.post(`${this.url}/strategy/save_processes`, { processes });
  }

  // 🧭 Painel do Empresário (quadro de gestão do dono — só admin)
  // (Rodada 4, #414) `version` = updated_at do quadro carregado; 409 se já mudou
  saveBusinessBoard(business, version = null) {
    return axios.post(`${this.url}/strategy/save_business_board`, {
      business,
      version,
    });
  }

  // ── Automations ───────────────────────────────────────────────────
  getAutomations(pipelineId, stageId) {
    return axios.get(
      `${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations`
    );
  }

  createAutomation(pipelineId, stageId, data) {
    return axios.post(
      `${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations`,
      { automation: data }
    );
  }

  updateAutomation(pipelineId, stageId, id, data) {
    return axios.put(
      `${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations/${id}`,
      { automation: data }
    );
  }

  deleteAutomation(pipelineId, stageId, id) {
    return axios.delete(
      `${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations/${id}`
    );
  }

  // ── 🏢 Meus negócios (21/10): lançador do dono ────────────────────
  getNegocios() {
    return axios.get(`${this.url}/negocios`);
  }

  loginNegocio(chave) {
    return axios.post(`${this.url}/negocios/${chave}/login`);
  }
}

export default new CrmAPI();
