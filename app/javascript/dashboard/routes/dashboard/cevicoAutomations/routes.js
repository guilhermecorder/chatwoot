import { frontendURL } from '../../../helper/URLHelper';
import AutomationsHub from './AutomationsHub.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/cevico-automations'),
      name: 'cevico_automations',
      meta: { permissions: ['administrator'] },
      component: AutomationsHub,
    },
  ],
};
