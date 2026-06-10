import { frontendURL } from '../../../helper/URLHelper';
import CrmBoard from './CrmBoard.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/crm'),
      name: 'crm_board',
      meta: { permissions: ['administrator', 'agent'] },
      component: CrmBoard,
    },
  ],
};
