/* global axios */
import ApiClient from './ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }
}

export default new TasksAPI();
