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
    return axios.post(`${this.url}/pipelines/${pipelineId}/stages`, { stage: data });
  }

  updateStage(pipelineId, stageId, data) {
    return axios.put(`${this.url}/pipelines/${pipelineId}/stages/${stageId}`, { stage: data });
  }

  deleteStage(pipelineId, stageId) {
    return axios.delete(`${this.url}/pipelines/${pipelineId}/stages/${stageId}`);
  }

  reorderStages(pipelineId, stageIds) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/stages/reorder`, { stage_ids: stageIds });
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

  sendCampaign(id) {
    return axios.post(`${this.url}/campaigns/${id}/send_now`);
  }

  getCampaignResults(id) {
    return axios.get(`${this.url}/campaigns/${id}/results`);
  }

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

  updateFollowupBot(id, data) {
    return axios.put(`${this.url}/followup_bots/${id}`, { followup_bot: data });
  }

  deleteFollowupBot(id) {
    return axios.delete(`${this.url}/followup_bots/${id}`);
  }

  getTrafficReport(params) {
    return axios.get(`${this.url}/traffic_report`, { params });
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

  testAi() {
    return axios.post(`${this.url}/settings/test_ai`);
  }

  getAiUsage() {
    return axios.get(`${this.url}/settings/ai_usage`);
  }

  updateAgendaWindows(windows) {
    return axios.post(`${this.url}/settings/update_agenda`, { windows });
  }

  // médicos com a agenda fechada (item 76)
  updateClosedDoctors(closedDoctors) {
    return axios.post(`${this.url}/settings/update_agenda`, { closed_doctors: closedDoctors });
  }

  // etiquetas + resposta de formulário das consultas do dia (item 76)
  getAgendaDayDetails(taskIds) {
    return axios.get(`${this.url.replace(/crm$/, 'tasks')}/agenda_details`, { params: { ids: taskIds.join(',') } });
  }

  updateAgendaBlocked(blocked) {
    return axios.post(`${this.url}/settings/update_agenda`, { blocked });
  }

  updateAgendaBlockedDays(blockedDays) {
    return axios.post(`${this.url}/settings/update_agenda`, { blocked_days: blockedDays });
  }

  // locais de cirurgia (clínicas parceiras — IOP etc.) do trilho de cirurgias
  updateSurgeryLocations(surgeryLocations) {
    return axios.post(`${this.url}/settings/update_agenda`, { surgery_locations: surgeryLocations });
  }

  // janelas da sala cirúrgica (clínica + dia + horário + bloco)
  updateSurgeryWindows(surgeryWindows) {
    return axios.post(`${this.url}/settings/update_agenda`, { surgery_windows: surgeryWindows });
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

  // tabela de preços oficial (Espaço do Paciente + prompts da IA) — admin
  updatePriceTable(items) {
    return axios.post(`${this.url}/settings/update_price_table`, { items });
  }

  // qual versão do Meu Painel cada agente vê — admin
  updatePanelAssignments(panelAssignments) {
    return axios.post(`${this.url}/settings/update_agenda`, { panel_assignments: panelAssignments });
  }

  // metas mensais por painel — os cards mudam de cor contra a meta
  updatePanelGoals(panelGoals) {
    return axios.post(`${this.url}/settings/update_agenda`, { panel_goals: panelGoals });
  }

  // conferência do dia → colunas do CRM (compareceu/faltou/cirurgia indicada)
  updateAttendanceStages(attendanceStages) {
    return axios.post(`${this.url}/settings/update_agenda`, { attendance_stages: attendanceStages });
  }

  // responsáveis pela conferência do dia (consultas/cirurgias) + prazo
  updateAttendanceOwners(attendanceOwners) {
    return axios.post(`${this.url}/settings/update_agenda`, { attendance_owners: attendanceOwners });
  }

  // preencher a Agenda com o histórico de confirmações das conversas
  agendaBackfill(params) {
    return axios.post(`${this.url}/settings/agenda_backfill`, params);
  }

  // colunas onde o Secretário da Agenda atua (sincroniza as automações)
  syncSchedulerStages(stageIds) {
    return axios.post(`${this.url}/settings/sync_scheduler_stages`, { stage_ids: stageIds });
  }

  // colunas de atuação de qualquer agente de coluna (conversation/closing/nps)
  syncAgentStages(agent, stageIds) {
    return axios.post(`${this.url}/settings/sync_agent_stages`, { agent, stage_ids: stageIds });
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

  previewAudience(audience) {
    return axios.post(`${this.url}/campaigns/preview_audience`, { audience });
  }

  getWhatsappTemplates(inboxId) {
    return axios.get(`${this.url}/campaigns/templates`, { params: { inbox_id: inboxId } });
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
    return axios.put(`${this.url}/pipelines/${pipelineId}/contacts/${id}`, data);
  }

  removeContact(pipelineId, id) {
    return axios.delete(`${this.url}/pipelines/${pipelineId}/contacts/${id}`);
  }

  getContactHistory(pipelineId, contactId) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/contacts/${contactId}/history`);
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

  // ── Google Sheets (planilha de cirurgias) ─────────────────────────
  updateSheets(data) {
    return axios.post(`${this.url}/settings/update_sheets`, data);
  }

  testSheets() {
    return axios.post(`${this.url}/settings/test_sheets`);
  }

  // ── Meu Painel ────────────────────────────────────────────────────
  getHome(params = {}) {
    return axios.get(`${this.url}/home`, { params });
  }

  // ── Dashboard de Campanhas ────────────────────────────────────────
  getCampaignsDashboard(params = {}) {
    return axios.get(`${this.url}/campaigns_dashboard`, { params });
  }

  // ── Dashboard ─────────────────────────────────────────────────────
  getDashboard(pipelineId, params = {}) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/dashboard`, { params });
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
  getPatient(contactId) {
    return axios.get(`${this.url}/patients/${contactId}`);
  }

  // sexo/nascimento do paciente (muda o tema dopamine da página)
  updatePatientProfile(contactId, profile) {
    return axios.post(`${this.url}/patients/${contactId}/update_profile`, profile);
  }

  getClinicalNotes(contactId) {
    return axios.get(`${this.url}/patients/${contactId}/clinical_notes`);
  }

  // fotos vão junto → FormData (multipart)
  createClinicalNote(contactId, formData) {
    return axios.post(`${this.url}/patients/${contactId}/clinical_notes`, formData);
  }

  updateClinicalNote(contactId, noteId, formData) {
    return axios.put(`${this.url}/patients/${contactId}/clinical_notes/${noteId}`, formData);
  }

  deleteClinicalNote(contactId, noteId) {
    return axios.delete(`${this.url}/patients/${contactId}/clinical_notes/${noteId}`);
  }

  updateClinicalAccess(clinicalAccess) {
    return axios.post(`${this.url}/settings/update_agenda`, { clinical_access: clinicalAccess });
  }

  // Mentor do Time: gera o feedback semanal agora (últimos 7 dias, admin)
  runMentor() {
    return axios.post(`${this.url}/settings/run_mentor`);
  }

  // ── PÁGINAS PRO: análise, funis, comentários ──────────────────────
  getPagesDashboard() {
    return axios.get(`${this.url}/pages_dashboard`);
  }

  // 🌪 Montador de Funis (item 60): fontes de captação por funil
  saveFunnelSources(payload) {
    return axios.post(`${this.url}/pages_dashboard/save_funnel_sources`, payload);
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
    return axios.post(`${this.url}/pages/${pageId}/delete_comment`, { comment_id: commentId });
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
    return axios.post(`${this.url}/people/save_goals`, { user_id: userId, goals });
  }

  // testes arquivados (disc v2 / 4 temperamentos) + espaço de vida
  saveAssessment(kind, scores, answers = []) {
    return axios.post(`${this.url}/people/save_assessment`, { kind, scores, answers });
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
    return axios.post(`${this.url}/goal_plans/add_note`, { month, text, about_user_id: aboutUserId, period });
  }

  deleteGoalNote(month, noteId, period) {
    return axios.post(`${this.url}/goal_plans/delete_note`, { month, note_id: noteId, period });
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
  getGoogleDashboard() {
    return axios.get(`${this.url}/google_dashboard`);
  }

  // ── Gestão Financeira (só admin) ───────────────────────────────────
  getFinance(params) {
    return axios.get(`${this.url}/finance`, { params });
  }

  createFinanceEntry(payload) {
    return axios.post(`${this.url}/finance/create_entry`, payload);
  }

  updateFinanceEntry(entryId, payload) {
    return axios.post(`${this.url}/finance/update_entry`, { entry_id: entryId, ...payload });
  }

  deleteFinanceEntry(entryId) {
    return axios.post(`${this.url}/finance/delete_entry`, { entry_id: entryId });
  }

  compareFinanceMonths(monthA, monthB) {
    return axios.get(`${this.url}/finance/compare`, { params: { month_a: monthA, month_b: monthB } });
  }

  // ── OftalmoFácil (conexão nativa) ───────────────────────────────────
  updateOftalmofacil(payload) {
    return axios.post(`${this.url}/settings/update_oftalmofacil`, payload);
  }

  // ── Dashboard dos agentes de IA (só admin) ──────────────────────────
  getAiDashboard(preset) {
    return axios.get(`${this.url}/ai_dashboard`, { params: { preset } });
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
    return axios.post(`${this.url}/stock/update_item`, { item_id: itemId, ...payload });
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
    return axios.post(`${this.url}/stock/update_order`, { order_id: orderId, status });
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
    return axios.post(`${this.url}/strategy/update_pillar`, { pillar_id: pillarId, ...data });
  }

  deleteStrategyPillar(pillarId) {
    return axios.post(`${this.url}/strategy/delete_pillar`, { pillar_id: pillarId });
  }

  createStrategyItem(pillarId, data) {
    return axios.post(`${this.url}/strategy/create_item`, { pillar_id: pillarId, ...data });
  }

  updateStrategyItem(itemId, data) {
    return axios.post(`${this.url}/strategy/update_item`, { item_id: itemId, ...data });
  }

  deleteStrategyItem(itemId) {
    return axios.post(`${this.url}/strategy/delete_item`, { item_id: itemId });
  }

  // 🏭 Desenho do Processo (item 59)
  saveStrategyProcesses(processes) {
    return axios.post(`${this.url}/strategy/save_processes`, { processes });
  }

  // 🧭 Painel do Empresário (quadro de gestão do dono — só admin)
  saveBusinessBoard(business) {
    return axios.post(`${this.url}/strategy/save_business_board`, { business });
  }

  // ── Automations ───────────────────────────────────────────────────
  getAutomations(pipelineId, stageId) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations`);
  }

  createAutomation(pipelineId, stageId, data) {
    return axios.post(`${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations`, { automation: data });
  }

  updateAutomation(pipelineId, stageId, id, data) {
    return axios.put(`${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations/${id}`, { automation: data });
  }

  deleteAutomation(pipelineId, stageId, id) {
    return axios.delete(`${this.url}/pipelines/${pipelineId}/stages/${stageId}/automations/${id}`);
  }
}

export default new CrmAPI();
