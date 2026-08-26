import { frontendURL } from '../../../helper/URLHelper';
import HubPage from './HubPage.vue';

export default {
  routes: [
    {
      // Porta de entrada do HUB: mundos Negócios (1) · Saúde (2) · futuro (3)
      path: frontendURL('accounts/:accountId/hub'),
      name: 'hub_home',
      meta: { permissions: ['administrator', 'agent'] },
      component: HubPage,
    },
  ],
};
