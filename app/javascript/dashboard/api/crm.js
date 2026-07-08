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

  getTrafficReport(params) {
    return axios.get(`${this.url}/traffic_report`, { params });
  }

  previewAudience(audience) {
    return axios.post(`${this.url}/campaigns/preview_audience`, { audience });
  }

  getWhatsappTemplates(inboxId) {
    return axios.get(`${this.url}/campaigns/templates`, { params: { inbox_id: inboxId } });
  }

  // ── Contacts ──────────────────────────────────────────────────────
  getContacts(pipelineId) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/contacts`);
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

  // ── Dashboard ─────────────────────────────────────────────────────
  getDashboard(pipelineId, period = 30) {
    return axios.get(`${this.url}/pipelines/${pipelineId}/dashboard`, { params: { period } });
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
