import CrmAPI from 'dashboard/api/crm';

const state = {
  // 🔔 item 346: contador do menu "Notificações" (alertas para conferir)
  appointmentAlertsCount: 0,
  pipelines: [],
  contacts: [],
  contactsMeta: { total: 0, shown: 0, scope: 'recent' },
  settings: {
    n8n_base_url: '',
    n8n_api_key_configured: false,
    n8n_workflows: [],
    n8n_workflows_fetched_at: null,
    column_presets: [],
    agent_permissions: {},
  },
  uiFlags: {
    isFetchingPipelines: false,
    isFetchingContacts: false,
    isCreating: false,
  },
};

const getters = {
  getPipelines: s => s.pipelines,
  getContacts: s => s.contacts,
  getContactsMeta: s => s.contactsMeta,
  getContactsByStage: s => stageId =>
    s.contacts.filter(c => c.stage_id === stageId),
  getUIFlags: s => s.uiFlags,
  getSettings: s => s.settings,
  // 🔐 rodada 334: { admin, me: { 'crm': 'edit', … }, units, role_id, catalog }
  getAccess: s => s.settings.access || null,
  // 🏢 identidade da empresa (ramo, vocabulário, unidades, módulos)
  getCompany: s => s.settings.company || null,
  getN8nWorkflows: s => s.settings.n8n_workflows || [],
  // avisos ativos do Radar de Oportunidades (badge no "Meu Painel")
  getRadarAlertCount: s => s.settings.ai?.opportunity_alerts_count || 0,
  getAppointmentAlertsCount: s => s.appointmentAlertsCount || 0,
};

// nº da última carga do board pedida (ver fetchContacts)
let contactsRequestSeq = 0;
// nº da última carga COM spinner — só ela desliga o spinner (uma resposta
// velha descartada não pode apagar o spinner de uma carga nova ainda no ar)
let loudRequestSeq = 0;

const actions = {
  async fetchAppointmentAlertsCount({ commit }) {
    try {
      const { data } = await CrmAPI.getAppointmentAlertsCount();
      commit('setAppointmentAlertsCount', data?.count || 0);
    } catch {
      // sem acesso ao nó agenda.notificacoes: o contador só não aparece
    }
  },
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

  // 🧹 auditoria 12/10 (#288): o servidor move TODOS os cards e apaga a
  // coluna de uma vez; aqui só refletimos o resultado nos cards carregados
  async deleteStageMovingTo(
    { commit },
    { pipelineId, stageId, targetStageId }
  ) {
    const { data } = await CrmAPI.deleteStageMovingTo(
      pipelineId,
      stageId,
      targetStageId
    );
    commit('moveStageContacts', { stageId, targetStageId });
    commit('removeStage', { pipelineId, stageId });
    return data;
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
  // inboxId ou { inboxId, all: true } (item 314: todos os status, para o card
  // de Confirmação dizer "existe mas não está aprovado")
  async fetchWhatsappTemplates(_, payload) {
    const inboxId = typeof payload === 'object' ? payload.inboxId : payload;
    const all = typeof payload === 'object' && payload.all === true;
    const { data } = await CrmAPI.getWhatsappTemplates(inboxId, all);
    return data;
  },

  async fetchContacts({ commit }, payload) {
    // 🫁 #323: busca no servidor dispara uma consulta por termo; se uma
    // resposta antiga chegar depois da nova, ela é descartada (só vale a última)
    contactsRequestSeq += 1;
    const seq = contactsRequestSeq;
    const pipelineId =
      typeof payload === 'object' ? payload.pipelineId : payload;
    const scope = typeof payload === 'object' ? payload.scope : undefined;
    const days = typeof payload === 'object' ? payload.days : undefined;
    const dateFrom = typeof payload === 'object' ? payload.dateFrom : undefined;
    const dateTo = typeof payload === 'object' ? payload.dateTo : undefined;
    const dateMode = typeof payload === 'object' ? payload.dateMode : undefined;
    const perStage = typeof payload === 'object' ? payload.perStage : undefined;
    const q = typeof payload === 'object' ? payload.q : undefined;
    // silent: completa em background sem spinner (board continua usável)
    const silent = typeof payload === 'object' ? payload.silent : false;
    if (!silent) {
      loudRequestSeq = seq;
      commit('setUIFlag', { isFetchingContacts: true });
    }
    try {
      const params = {};
      if (scope) params.scope = scope;
      if (days) params.days = days;
      if (dateFrom) params.date_from = dateFrom;
      if (dateTo) params.date_to = dateTo;
      if (dateMode) params.date_mode = dateMode;
      if (perStage) params.per_stage = perStage;
      if (q) params.q = q;
      const { data } = await CrmAPI.getContacts(pipelineId, params);
      if (seq !== contactsRequestSeq) return;
      // formato novo { payload, meta }; aceita o antigo (array) por segurança
      commit('setContacts', data.payload ?? data);
      if (data.meta) commit('setContactsMeta', data.meta);
    } finally {
      if (!silent && seq === loudRequestSeq) {
        commit('setUIFlag', { isFetchingContacts: false });
      }
    }
  },

  // Próxima página de UMA coluna (scope=period) — anexa sem substituir o board
  async fetchMoreStage(
    { commit, state: storeState },
    { pipelineId, stageId, offset, limit, dateFrom, dateTo, dateMode, range, q }
  ) {
    const params = { scope: 'stage_page', stage_id: stageId, offset, limit };
    // range=all: próxima página do "Carregar todos" (base toda, sem datas)
    if (range) params.range = range;
    if (q) params.q = q;
    if (dateFrom) params.date_from = dateFrom;
    if (dateTo) params.date_to = dateTo;
    if (dateMode) params.date_mode = dateMode;
    // 🫁 #323: se o board foi recarregado no meio (outra busca, outro
    // período), esta página é de um board velho — descarta
    const boardSeq = contactsRequestSeq;
    const { data } = await CrmAPI.getContacts(pipelineId, params);
    const sameSearch =
      !range || (storeState?.contactsMeta?.q || '') === (q || '');
    if (boardSeq !== contactsRequestSeq || !sameSearch) return {};
    commit('appendContacts', data.payload ?? []);
    return data.meta ?? {};
  },

  async addContact({ commit }, { pipelineId, ...contactData }) {
    const { data } = await CrmAPI.addContact(pipelineId, contactData);
    commit('addContact', data);
    return data;
  },

  async moveContact({ commit }, { pipelineId, id, stageId }) {
    const { data } = await CrmAPI.updateContact(pipelineId, id, {
      stage_id: stageId,
    });
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

  async fetchDashboard(_, { pipelineId, period, preset, from, to, inboxIds }) {
    const params = {};
    if (preset) params.preset = preset;
    else if (period) params.period = period;
    // régua padrão: preset 'custom' viaja com as datas escolhidas
    if (preset === 'custom' && from && to) {
      params.from = from;
      params.to = to;
    }
    if (inboxIds?.length) params.inbox_ids = inboxIds;
    const { data } = await CrmAPI.getDashboard(pipelineId, params);
    return data;
  },

  async updateInboxInvestments(_, { investments, captureInboxIds }) {
    const { data } = await CrmAPI.updateInboxInvestments(
      investments,
      captureInboxIds
    );
    return data;
  },

  async triggerLabelChange(_, { pipelineId, contactId, added, removed }) {
    if (!added.length && !removed.length) return;
    await CrmAPI.triggerLabelChange(pipelineId, contactId, { added, removed });
  },

  async startConversation({ commit }, { pipelineId, id, inboxId }) {
    const { data } = await CrmAPI.startConversation(pipelineId, id, inboxId);
    commit('editContact', data); // card volta completo, com a conversa criada
    return data;
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

  // acessos por atendente (admin): concessões + menu do dia a dia
  async updateAgentGrants({ dispatch }, payload) {
    const { data } = await CrmAPI.updateAgentGrants(payload);
    await dispatch('fetchSettings');
    return data;
  },

  // 🔐 rodada 334: acessos em árvore — gravar e recarregar as settings
  // (o `access.me` de quem está logado vem junto)
  async updateAgentAccess({ dispatch }, payload) {
    const { data } = await CrmAPI.updateAgentAccess(payload);
    await dispatch('fetchSettings');
    return data;
  },

  async updateAccessRoles({ dispatch }, roles) {
    const { data } = await CrmAPI.updateAccessRoles(roles);
    await dispatch('fetchSettings');
    return data;
  },

  // 🏢 Identidade da empresa
  async updateCompany({ dispatch }, company) {
    const { data } = await CrmAPI.updateCompany(company);
    await dispatch('fetchSettings');
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
  // 🎯 item 371: prepara o Google Ads (ações + variáveis) e devolve o estado novo
  async prepareGoogleAds({ commit }) {
    const { data } = await CrmAPI.prepareGoogleAds();
    if (data.google_ads) commit('setSettings', { google_ads: data.google_ads });
    return data;
  },
  async testGoogleAdsApi() {
    const { data } = await CrmAPI.testGoogleAdsApi();
    return data;
  },

  // 📞 Ligações (WhatsApp) — item 167: o backend devolve a config `calls`
  // já com os defaults preenchidos; guardamos em settings.calls
  async updateCalls({ commit }, params) {
    const { data } = await CrmAPI.updateCalls(params);
    commit('setSettings', { calls: data?.calls || data });
    return data;
  },
  async enableCallsAtMeta({ commit, state: s }, inboxId = null) {
    const { data } = await CrmAPI.enableCallsAtMeta(inboxId);
    if (data?.meta) {
      // estado da Meta é POR CAIXA (várias caixas, 18/09)
      const calls = s.settings.calls || {};
      const inboxes = (calls.inboxes || []).map(c =>
        Number(c.inbox_id) === Number(data.inbox_id)
          ? { ...c, meta: data.meta }
          : c
      );
      commit('setSettings', {
        calls: { ...calls, inboxes, meta: inboxes[0]?.meta || calls.meta },
      });
    }
    return data;
  },
  async callsMetaStatus(_, inboxId = null) {
    const { data } = await CrmAPI.callsMetaStatus(inboxId);
    return data;
  },

  // 🤖📞 Agente de Ligação (ElevenLabs) — item 169: o backend devolve a
  // config `voice` sem segredos e com defaults; guardamos em settings.voice
  async updateVoice({ commit }, params) {
    const { data } = await CrmAPI.updateVoice(params);
    commit('setSettings', { voice: data?.voice || data });
    return data;
  },
  async testVoice() {
    const { data } = await CrmAPI.testVoice();
    return data;
  },
  async syncVoice({ commit }) {
    const { data } = await CrmAPI.syncVoice();
    if (data?.voice) commit('setSettings', { voice: data.voice });
    return data;
  },
  async voiceWhatsappAccounts() {
    const { data } = await CrmAPI.voiceWhatsappAccounts();
    return data;
  },
  async voiceVoices(_, params) {
    const { data } = await CrmAPI.voiceVoices(params);
    return data;
  },
  async voiceState() {
    const { data } = await CrmAPI.voiceState();
    return data;
  },

  // 🗺️ Mapa de Fluxos — item 170 (sem cache: o estado é ao vivo)
  async fetchFlows() {
    const { data } = await CrmAPI.getFlows();
    return data;
  },
  async fetchFlow(_, key) {
    const { data } = await CrmAPI.getFlow(key);
    return data;
  },

  // ── Automations ──────────────────────────────────────────────────
  async fetchAutomations(_, { pipelineId, stageId }) {
    const { data } = await CrmAPI.getAutomations(pipelineId, stageId);
    return data;
  },

  async createAutomation(_, { pipelineId, stageId, ...automationData }) {
    const { data } = await CrmAPI.createAutomation(
      pipelineId,
      stageId,
      automationData
    );
    return data;
  },

  async updateAutomation(_, { pipelineId, stageId, id, ...automationData }) {
    const { data } = await CrmAPI.updateAutomation(
      pipelineId,
      stageId,
      id,
      automationData
    );
    return data;
  },

  async deleteAutomation(_, { pipelineId, stageId, id }) {
    await CrmAPI.deleteAutomation(pipelineId, stageId, id);
  },
};

const mutations = {
  setAppointmentAlertsCount(s, count) {
    s.appointmentAlertsCount = count;
  },
  setUIFlag(s, flags) {
    s.uiFlags = { ...s.uiFlags, ...flags };
  },
  setPipelines(s, data) {
    s.pipelines = data;
  },
  addPipeline(s, p) {
    s.pipelines.push(p);
  },
  editPipeline(s, p) {
    const idx = s.pipelines.findIndex(x => x.id === p.id);
    if (idx !== -1) s.pipelines.splice(idx, 1, p);
  },
  removePipeline(s, id) {
    s.pipelines = s.pipelines.filter(p => p.id !== id);
  },
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
  // cards carregados da coluna apagada passam para a coluna de destino; a
  // contagem real (stage_counts) acompanha
  moveStageContacts(s, { stageId, targetStageId }) {
    s.contacts = s.contacts.map(c =>
      c.stage_id === stageId ? { ...c, stage_id: targetStageId } : c
    );
    const counts = s.contactsMeta?.stage_counts;
    if (counts) {
      const moved = counts[stageId] ?? counts[String(stageId)] ?? 0;
      const current =
        counts[targetStageId] ?? counts[String(targetStageId)] ?? 0;
      const next = { ...counts, [targetStageId]: current + moved };
      delete next[stageId];
      delete next[String(stageId)];
      s.contactsMeta = { ...s.contactsMeta, stage_counts: next };
    }
    // a soma de valor por coluna (stage_values) acompanha também
    const values = s.contactsMeta?.stage_values;
    if (values) {
      const movedValue = values[stageId] ?? values[String(stageId)] ?? 0;
      const currentValue =
        values[targetStageId] ?? values[String(targetStageId)] ?? 0;
      const nextValues = {
        ...values,
        [targetStageId]: Number(currentValue) + Number(movedValue),
      };
      delete nextValues[stageId];
      delete nextValues[String(stageId)];
      s.contactsMeta = { ...s.contactsMeta, stage_values: nextValues };
    }
  },
  setStages(s, { pipelineId, stages }) {
    const p = s.pipelines.find(x => x.id === pipelineId);
    if (p) p.stages = stages;
  },
  setSettings(s, data) {
    s.settings = { ...s.settings, ...data };
  },
  setN8nWorkflows(s, workflows) {
    s.settings.n8n_workflows = workflows;
  },
  setContacts(s, data) {
    s.contacts = data;
  },
  setContactsMeta(s, meta) {
    s.contactsMeta = meta;
  },
  appendContacts(s, list) {
    const seen = new Set(s.contacts.map(c => c.id));
    list.forEach(c => {
      if (!seen.has(c.id)) s.contacts.push(c);
    });
  },
  addContact(s, c) {
    s.contacts.push(c);
  },
  editContact(s, c) {
    const idx = s.contacts.findIndex(x => x.id === c.id);
    if (idx !== -1) s.contacts.splice(idx, 1, c);
  },
  deleteContact(s, id) {
    s.contacts = s.contacts.filter(c => c.id !== id);
  },
  // Atualiza dados da última conversa de um card sem refetch do board
  patchContactConversation(s, { id, data }) {
    const c = s.contacts.find(x => x.id === id);
    if (c?.last_conversation)
      c.last_conversation = { ...c.last_conversation, ...data };
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
