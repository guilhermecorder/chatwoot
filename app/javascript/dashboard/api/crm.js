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
