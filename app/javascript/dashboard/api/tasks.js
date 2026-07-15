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
}

export default new TasksAPI();
