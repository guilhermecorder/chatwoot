/* global axios */
// 🗺️ Mensagens da jornada (item 168): regras + envios (Fila de hoje)
import ApiClient from './ApiClient';

class CevicoJourneyAPI extends ApiClient {
  constructor() {
    super('crm/journey_messages', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  create(journeyMessage) {
    return axios.post(this.url, { journey_message: journeyMessage });
  }

  update(id, journeyMessage) {
    return axios.patch(`${this.url}/${id}`, {
      journey_message: journeyMessage,
    });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  preview(journeyMessage, contactId = null) {
    return axios.post(`${this.url}/preview`, {
      journey_message: journeyMessage,
      contact_id: contactId,
    });
  }

  testSend(id, phone) {
    return axios.post(`${this.url}/${id}/test_send`, { phone });
  }

  planNow(id) {
    return axios.post(`${this.url}/${id}/plan_now`);
  }

  // mapa: lembretes, follow-up, réguas, automações, campanhas e agentes por etapa (item 173)
  map() {
    return axios.get(`${this.url}/map`);
  }

  settings() {
    return axios.get(`${this.url}/settings`);
  }

  updateSettings(payload) {
    return axios.post(`${this.url}/update_settings`, payload);
  }

  // ── envios ──
  get sendsUrl() {
    return this.url.replace('journey_messages', 'journey_sends');
  }

  sends(params = {}) {
    return axios.get(this.sendsUrl, { params });
  }

  queue(date = null) {
    return axios.get(`${this.sendsUrl}/queue`, {
      params: date ? { date } : {},
    });
  }

  approve(id) {
    return axios.post(`${this.sendsUrl}/${id}/approve`);
  }

  skip(id) {
    return axios.post(`${this.sendsUrl}/${id}/skip`);
  }

  retry(id) {
    return axios.post(`${this.sendsUrl}/${id}/retry`);
  }

  approveAll(params = {}) {
    return axios.post(`${this.sendsUrl}/approve_all`, params);
  }
}

export default new CevicoJourneyAPI();
