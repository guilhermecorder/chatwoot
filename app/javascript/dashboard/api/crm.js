/* global axios */
import ApiClient from './ApiClient';

class CrmAPI extends ApiClient {
  constructor() {
    super('crm', { accountScoped: true });
  }

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
}

export default new CrmAPI();
