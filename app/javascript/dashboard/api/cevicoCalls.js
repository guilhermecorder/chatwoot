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

  // ── item 176: ambiente Chamadas ──
  // números do período + comparação + ao vivo + perdidas de hoje sem retorno
  overview(params = {}) {
    return axios.get(`${this.url}/overview`, { params });
  }

  // só o que está tocando/em atendimento agora
  live() {
    return axios.get(this.url, { params: { live: 1 } });
  }

  // perdida que alguém já retornou por fora (ligação/mensagem)
  markReturned(id, note = '') {
    return axios.post(`${this.url}/${id}/returned`, { note });
  }

  // CSV do histórico com os mesmos filtros da lista (blob para download)
  exportCsv(params = {}) {
    return axios.get(`${this.url}/export`, { params, responseType: 'blob' });
  }

  // inboxId (opcional): a caixa da conversa aberta — com várias caixas
  // configuradas, a ligação sai por ela; sem isso o backend escolhe
  initiate(contactId, sdpOffer, inboxId = null) {
    return axios.post(`${this.url}/initiate`, {
      contact_id: contactId,
      sdp_offer: sdpOffer,
      inbox_id: inboxId,
    });
  }

  requestPermission(contactId, inboxId = null) {
    return axios.post(`${this.url}/request_permission`, {
      contact_id: contactId,
      inbox_id: inboxId,
    });
  }

  permissionStatus(contactId, inboxId = null) {
    return axios.get(`${this.url}/permission_status`, {
      params: { contact_id: contactId, inbox_id: inboxId || undefined },
    });
  }
}

export default new CevicoCallsAPI();
