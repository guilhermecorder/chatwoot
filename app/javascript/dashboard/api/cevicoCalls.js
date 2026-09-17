/* global axios */
// 📞 API das CHAMADAS NATIVAS de WhatsApp (item 167) — `crm/calls`.
// Contrato: docs/CHAMADAS_NATIVAS.md §2 (CallsController).
import ApiClient from './ApiClient';

class CevicoCallsAPI extends ApiClient {
  constructor() {
    super('crm/calls', { accountScoped: true });
  }

  // preset= | since= | until= | status= | direction= | user_id= | contact_id= | page= | limit=
  list(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  accept(id, sdpAnswer) {
    return axios.post(`${this.url}/${id}/accept`, { sdp_answer: sdpAnswer });
  }

  reject(id) {
    return axios.post(`${this.url}/${id}/reject`);
  }

  hangup(id) {
    return axios.post(`${this.url}/${id}/hangup`);
  }

  // multipart { recording, duration }
  uploadRecording(id, formData) {
    return axios.post(`${this.url}/${id}/recording`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  transcribe(id) {
    return axios.post(`${this.url}/${id}/transcribe`);
  }

  dashboard(params = {}) {
    return axios.get(`${this.url}/dashboard`, { params });
  }

  initiate(contactId, sdpOffer) {
    return axios.post(`${this.url}/initiate`, {
      contact_id: contactId,
      sdp_offer: sdpOffer,
    });
  }

  requestPermission(contactId) {
    return axios.post(`${this.url}/request_permission`, {
      contact_id: contactId,
    });
  }

  permissionStatus(contactId) {
    return axios.get(`${this.url}/permission_status`, {
      params: { contact_id: contactId },
    });
  }
}

export default new CevicoCallsAPI();
