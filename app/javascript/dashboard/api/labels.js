/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

class LabelsAPI extends CacheEnabledApiClient {
  constructor() {
    super('labels', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'label';
  }

  // ordem definida pelo admin na tela de Etiquetas (vale p/ o time inteiro)
  reorder(orderedIds) {
    return axios.post(`${this.url}/reorder`, { ordered_ids: orderedIds });
  }
}

export default new LabelsAPI();
