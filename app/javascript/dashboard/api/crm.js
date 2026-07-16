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

  // qual versão do Meu Painel cada agente vê — admin
  updatePanelAssignments(panelAssignments) {
    return axios.post(`${this.url}/settings/update_agenda`, { panel_assignments: panelAssignments });
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
