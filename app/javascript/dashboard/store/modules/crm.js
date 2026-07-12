import CrmAPI from 'dashboard/api/crm';

const state = {
  pipelines: [],
  contacts: [],
  contactsMeta: { total: 0, shown: 0, scope: 'recent' },
  settings: {
    n8n_base_url:             '',
    n8n_api_key_configured:   false,
    n8n_workflows:            [],
    n8n_workflows_fetched_at: null,
    column_presets:           [],
    agent_permissions:        {},
  },
  uiFlags: {
    isFetchingPipelines: false,
    isFetchingContacts: false,
    isCreating: false,
  },
};

const getters = {
  getPipelines:    s => s.pipelines,
  getContacts:     s => s.contacts,
  getContactsMeta: s => s.contactsMeta,
  getContactsByStage: s => stageId => s.contacts.filter(c => c.stage_id === stageId),
  getUIFlags:      s => s.uiFlags,
  getSettings:     s => s.settings,
  getN8nWorkflows: s => s.settings.n8n_workflows || [],
};

const actions = {
  async fetchPipelines({ commit }) {
    commit('setUIFlag', { isFetchingPipelines: true });
    try {
      const { data } = await CrmAPI.getPipelines();
      commit('setPipelines', data);
    } finally {
      commit('setUIFlag', { isFetchingPipelines: false });
    }
  },

  async createPipeline({ commit }, pipelineData) {
    const { data } = await CrmAPI.createPipeline(pipelineData);
    commit('addPipeline', data);
    return data;
  },

  async updatePipeline({ commit }, { id, ...pipelineData }) {
    const { data } = await CrmAPI.updatePipeline(id, pipelineData);
    commit('editPipeline', data);
    return data;
  },

  async deletePipeline({ commit }, id) {
    await CrmAPI.deletePipeline(id);
    commit('removePipeline', id);
  },

  async createStage({ commit }, { pipelineId, ...stageData }) {
    const { data } = await CrmAPI.createStage(pipelineId, stageData);
    commit('addStage', { pipelineId, stage: data });
    return data;
  },

  async updateStage({ commit }, { pipelineId, id, ...stageData }) {
    const { data } = await CrmAPI.updateStage(pipelineId, id, stageData);
    commit('editStage', { pipelineId, stage: data });
    return data;
  },

  async deleteStage({ commit }, { pipelineId, stageId }) {
    await CrmAPI.deleteStage(pipelineId, stageId);
    commit('removeStage', { pipelineId, stageId });
  },

  async reorderStages({ commit }, { pipelineId, stageIds }) {
    const { data } = await CrmAPI.reorderStages(pipelineId, stageIds);
    commit('setStages', { pipelineId, stages: data });
  },

  // ── Campanhas (sem estado no store — dados vivem na página) ────────
  async fetchCampaigns() {
    const { data } = await CrmAPI.getCampaigns();
    return data;
  },
  async fetchCampaign(_, id) {
    const { data } = await CrmAPI.getCampaign(id);
    return data;
  },
  async createCampaign(_, campaignData) {
    const { data } = await CrmAPI.createCampaign(campaignData);
    return data;
  },
  async deleteCampaign(_, id) {
    await CrmAPI.deleteCampaign(id);
  },
  async sendCampaign(_, id) {
    const { data } = await CrmAPI.sendCampaign(id);
    return data;
  },
  async fetchCampaignResults(_, id) {
    const { data } = await CrmAPI.getCampaignResults(id);
    return data;
  },
  async scheduleCampaign(_, { id, scheduledAt }) {
    const { data } = await CrmAPI.scheduleCampaign(id, scheduledAt);
    return data;
  },
  async fetchMessageAutomations() {
    const { data } = await CrmAPI.getMessageAutomations();
    return data;
  },
  async fetchFollowupBots(_, params = {}) {
    const { data } = await CrmAPI.getFollowupBots(params);
    return data;
  },
  async createFollowupBot(_, payload) {
    const { data } = await CrmAPI.createFollowupBot(payload);
    return data;
  },
  async updateFollowupBot(_, { id, ...payload }) {
    const { data } = await CrmAPI.updateFollowupBot(id, payload);
    return data;
  },
  async deleteFollowupBot(_, id) {
    await CrmAPI.deleteFollowupBot(id);
  },
  async createMessageAutomation(_, automationData) {
    const { data } = await CrmAPI.createMessageAutomation(automationData);
    return data;
  },
  async updateMessageAutomation(_, { id, ...automationData }) {
    const { data } = await CrmAPI.updateMessageAutomation(id, automationData);
    return data;
  },
  async deleteMessageAutomation(_, id) {
    await CrmAPI.deleteMessageAutomation(id);
  },
  async previewEligible(_, id) {
    const { data } = await CrmAPI.previewEligible(id);
    return data;
  },
  async previewRetroLabel(_, payload) {
    const { data } = await CrmAPI.previewRetroLabel(payload);
    return data;
  },
  async applyRetroLabel(_, payload) {
    const { data } = await CrmAPI.applyRetroLabel(payload);
    return data;
  },
  async previewLabelReplace(_, payload) {
    const { data } = await CrmAPI.previewLabelReplace(payload);
    return data;
  },
  async applyLabelReplace(_, payload) {
    const { data } = await CrmAPI.applyLabelReplace(payload);
    return data;
  },
  async previewLabelRemove(_, payload) {
    const { data } = await CrmAPI.previewLabelRemove(payload);
    return data;
  },
  async applyLabelRemove(_, payload) {
    const { data } = await CrmAPI.applyLabelRemove(payload);
    return data;
  },
  async previewContactUnification() {
    const { data } = await CrmAPI.previewContactUnification();
    return data;
  },
  async applyContactUnification() {
    const { data } = await CrmAPI.applyContactUnification();
    return data;
  },
  async previewAudience(_, audience) {
    const { data } = await CrmAPI.previewAudience(audience);
    return data;
  },
  async fetchWhatsappTemplates(_, inboxId) {
    const { data } = await CrmAPI.getWhatsappTemplates(inboxId);
    return data;
  },

  async fetchContacts({ commit }, payload) {
    const pipelineId = typeof payload === 'object' ? payload.pipelineId : payload;
    const scope = typeof payload === 'object' ? payload.scope : undefined;
    commit('setUIFlag', { isFetchingContacts: true });
    try {
      const { data } = await CrmAPI.getContacts(
        pipelineId,
        scope ? { scope } : {}
      );
      // formato novo { payload, meta }; aceita o antigo (array) por segurança
      commit('setContacts', data.payload ?? data);
      if (data.meta) commit('setContactsMeta', data.meta);
    } finally {
      commit('setUIFlag', { isFetchingContacts: false });
    }
  },

  async addContact({ commit }, { pipelineId, ...contactData }) {
    const { data } = await CrmAPI.addContact(pipelineId, contactData);
    commit('addContact', data);
    return data;
  },

  async moveContact({ commit }, { pipelineId, id, stageId }) {
    const { data } = await CrmAPI.updateContact(pipelineId, id, { stage_id: stageId });
    commit('editContact', data);
    return data;
  },

  async updateContact({ commit }, { pipelineId, id, ...contactData }) {
    const { data } = await CrmAPI.updateContact(pipelineId, id, contactData);
    commit('editContact', data);
    return data;
  },

  async removeContact({ commit }, { pipelineId, id }) {
    await CrmAPI.removeContact(pipelineId, id);
    commit('deleteContact', id);
  },

  async fetchContactHistory(_, { pipelineId, contactId }) {
    const { data } = await CrmAPI.getContactHistory(pipelineId, contactId);
    return data;
  },

  async fetchDashboard(_, { pipelineId, period }) {
    const { data } = await CrmAPI.getDashboard(pipelineId, period);
    return data;
  },

  async triggerLabelChange(_, { pipelineId, contactId, added, removed }) {
    if (!added.length && !removed.length) return;
    await CrmAPI.triggerLabelChange(pipelineId, contactId, { added, removed });
  },

  async detectCardValue({ commit }, { pipelineId, id }) {
    const { data } = await CrmAPI.detectCardValue(pipelineId, id);
    if (data.updated) commit('patchContactValue', { id, value: data.value });
    return data;
  },

  async detectValuesBulk(_, { pipelineId, onlyEmpty }) {
    const { data } = await CrmAPI.detectValuesBulk(pipelineId, onlyEmpty);
    return data;
  },

  // ── Settings / Integrations ──────────────────────────────────────
  async fetchSettings({ commit }) {
    const { data } = await CrmAPI.getSettings();
    commit('setSettings', data);
    return data;
  },

  async updateSettings({ commit }, params) {
    const { data } = await CrmAPI.updateSettings(params);
    commit('setSettings', data);
    return data;
  },

  async testN8n() {
    const { data } = await CrmAPI.testN8n();
    return data;
  },

  async fetchN8nWorkflows({ commit }) {
    const { data } = await CrmAPI.fetchN8nWorkflows();
    if (data.success) commit('setN8nWorkflows', data.workflows);
    return data;
  },

  async updateMetaAds({ commit }, params) {
    const { data } = await CrmAPI.updateMetaAds(params);
    commit('setSettings', { meta_ads: data });
    return data;
  },
  async testMetaAds() {
    const { data } = await CrmAPI.testMetaAds();
    return data;
  },

  async updateGoogleAds({ commit }, params) {
    const { data } = await CrmAPI.updateGoogleAds(params);
    commit('setSettings', { google_ads: data });
    return data;
  },
  async testGoogleAds() {
    const { data } = await CrmAPI.testGoogleAds();
    return data;
  },

  // ── Automations ──────────────────────────────────────────────────
  async fetchAutomations(_, { pipelineId, stageId }) {
    const { data } = await CrmAPI.getAutomations(pipelineId, stageId);
    return data;
  },

  async createAutomation(_, { pipelineId, stageId, ...automationData }) {
    const { data } = await CrmAPI.createAutomation(pipelineId, stageId, automationData);
    return data;
  },

  async updateAutomation(_, { pipelineId, stageId, id, ...automationData }) {
    const { data } = await CrmAPI.updateAutomation(pipelineId, stageId, id, automationData);
    return data;
  },

  async deleteAutomation(_, { pipelineId, stageId, id }) {
    await CrmAPI.deleteAutomation(pipelineId, stageId, id);
  },
};

const mutations = {
  setUIFlag(s, flags) { s.uiFlags = { ...s.uiFlags, ...flags }; },
  setPipelines(s, data) { s.pipelines = data; },
  addPipeline(s, p) { s.pipelines.push(p); },
  editPipeline(s, p) {
    const idx = s.pipelines.findIndex(x => x.id === p.id);
    if (idx !== -1) s.pipelines.splice(idx, 1, p);
  },
  removePipeline(s, id) { s.pipelines = s.pipelines.filter(p => p.id !== id); },
  addStage(s, { pipelineId, stage }) {
    const p = s.pipelines.find(x => x.id === pipelineId);
    if (p) p.stages.push(stage);
  },
  editStage(s, { pipelineId, stage }) {
    const p = s.pipelines.find(x => x.id === pipelineId);
    if (!p) return;
    const idx = p.stages.findIndex(x => x.id === stage.id);
    if (idx !== -1) p.stages.splice(idx, 1, stage);
  },
  removeStage(s, { pipelineId, stageId }) {
    const p = s.pipelines.find(x => x.id === pipelineId);
    if (p) p.stages = p.stages.filter(x => x.id !== stageId);
  },
  setStages(s, { pipelineId, stages }) {
    const p = s.pipelines.find(x => x.id === pipelineId);
    if (p) p.stages = stages;
  },
  setSettings(s, data) { s.settings = { ...s.settings, ...data }; },
  setN8nWorkflows(s, workflows) { s.settings.n8n_workflows = workflows; },
  setContacts(s, data) { s.contacts = data; },
  setContactsMeta(s, meta) { s.contactsMeta = meta; },
  addContact(s, c) { s.contacts.push(c); },
  editContact(s, c) {
    const idx = s.contacts.findIndex(x => x.id === c.id);
    if (idx !== -1) s.contacts.splice(idx, 1, c);
  },
  deleteContact(s, id) { s.contacts = s.contacts.filter(c => c.id !== id); },
  // Atualiza dados da última conversa de um card sem refetch do board
  patchContactConversation(s, { id, data }) {
    const c = s.contacts.find(x => x.id === id);
    if (c?.last_conversation) c.last_conversation = { ...c.last_conversation, ...data };
  },
  patchContactValue(s, { id, value }) {
    const c = s.contacts.find(x => x.id === id);
    if (c) c.value = value;
  },
  // Merge raso de campos do card (ex.: labels após salvar) sem refetch
  patchContact(s, { id, data }) {
    const idx = s.contacts.findIndex(x => x.id === id);
    if (idx !== -1) s.contacts.splice(idx, 1, { ...s.contacts[idx], ...data });
  },
};

export default { namespaced: true, state, getters, actions, mutations };
