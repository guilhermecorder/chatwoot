/* global axios */
// Central de Criativos (item 172): anúncios da Meta lidos como gancho / corpo /
// CTA, com métricas diárias e a jornada do CRM. Backend: crm/creatives.
import ApiClient from './ApiClient';

class CevicoCreativesAPI extends ApiClient {
  constructor() {
    super('crm/creatives', { accountScoped: true });
  }

  list(params) {
    return axios.get(this.url, { params });
  }

  show(adId, params) {
    return axios.get(`${this.url}/${adId}`, { params });
  }

  assets(params) {
    return axios.get(`${this.url}/assets`, { params });
  }

  history(params) {
    return axios.get(`${this.url}/history`, { params });
  }

  sync(params = {}) {
    return axios.post(`${this.url}/sync`, params);
  }

  syncStatus() {
    return axios.get(`${this.url}/sync_status`);
  }

  // carga completa (até 37 meses, em janelas) — só admin, roda em segundo plano
  loadHistory() {
    return axios.post(`${this.url}/load_history`);
  }

  // CSV do que está guardado aqui (período escolhido ou tudo com all=1)
  // 🎬 item 181: transcrição dos vídeos (todos os pendentes / um anúncio)
  transcribeVideos() {
    return axios.post(`${this.url}/transcribe_videos`);
  }

  transcribeVideo(adId) {
    return axios.post(`${this.url}/${adId}/transcribe`);
  }

  exportCsv(params) {
    return axios.get(`${this.url}/export`, { params, responseType: 'blob' });
  }
}

export default new CevicoCreativesAPI();
