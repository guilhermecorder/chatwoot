/* global axios */
// 🤖📞 API das CAMPANHAS DE LIGAÇÃO da assistente virtual (item 169) —
// `crm/call_campaigns`. Contrato: docs/AGENTE_LIGACAO.md §3
// (CallCampaignsController). O corpo vai embrulhado em `call_campaign`.
import ApiClient from './ApiClient';

class CevicoCallCampaignsAPI extends ApiClient {
  constructor() {
    super('crm/call_campaigns', { accountScoped: true });
  }

  // → { call_campaigns: [...] } (cada uma já com `progress` e `outcomes`)
  list() {
    return axios.get(this.url);
  }

  // → campanha + contacts[] + meta{ total, page } (50 por página)
  show(id, params = {}) {
    return axios.get(`${this.url}/${id}`, { params });
  }

  create(callCampaign) {
    return axios.post(this.url, { call_campaign: callCampaign });
  }

  update(id, callCampaign) {
    return axios.patch(`${this.url}/${id}`, { call_campaign: callCampaign });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // resolve o público, enfileira os contatos e começa a discar
  start(id) {
    return axios.post(`${this.url}/${id}/start`);
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  // → { count, sample } (mesmas chaves de público da Campanha WhatsApp)
  previewAudience(audience) {
    return axios.post(`${this.url}/preview_audience`, { audience });
  }
}

export default new CevicoCallCampaignsAPI();
