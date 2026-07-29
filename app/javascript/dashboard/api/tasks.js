/* global axios */
import ApiClient from './ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  // solicitação/ajuda dentro da tarefa (executor ↔ criador)
  comment(id, text) {
    return axios.post(`${this.url}/${id}/comment`, { text });
  }

  // anexos da tarefa (imagem/PDF/documento)
  addAttachments(id, files) {
    const formData = new FormData();
    files.forEach(file => formData.append('files[]', file));
    return axios.post(`${this.url}/${id}/attachments`, formData);
  }

  deleteAttachment(id, attachmentId) {
    return axios.delete(`${this.url}/${id}/attachments/${attachmentId}`);
  }
}

export default new TasksAPI();
