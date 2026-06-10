import CrmAPI from 'dashboard/api/crm';

const state = {
  pipelines: [],
  contacts: [],
  uiFlags: {
    isFetchingPipelines: false,
    isFetchingContacts: false,
    isCreating: false,
  },
};

const getters = {
  getPipelines: s => s.pipelines,
  getContacts: s => s.contacts,
  getContactsByStage: s => stageId => s.contacts.filter(c => c.stage_id === stageId),
  getUIFlags: s => s.uiFlags,
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

  async fetchContacts({ commit }, pipelineId) {
    commit('setUIFlag', { isFetchingContacts: true });
    try {
      const { data } = await CrmAPI.getContacts(pipelineId);
      commit('setContacts', data);
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
  setContacts(s, data) { s.contacts = data; },
  addContact(s, c) { s.contacts.push(c); },
  editContact(s, c) {
    const idx = s.contacts.findIndex(x => x.id === c.id);
    if (idx !== -1) s.contacts.splice(idx, 1, c);
  },
  deleteContact(s, id) { s.contacts = s.contacts.filter(c => c.id !== id); },
};

export default { namespaced: true, state, getters, actions, mutations };
