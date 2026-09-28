import { frontendURL } from '../../../helper/URLHelper';
import BusinessBoardPage from './BusinessBoardPage.vue';

export default {
  routes: [
    {
      // 👑 Painel do empresário (27/09): ambiente próprio, no topo do menu (só admin)
      path: frontendURL('accounts/:accountId/empresario'),
      name: 'cevico_business',
      meta: { permissions: ['administrator'] },
      component: BusinessBoardPage,
    },
  ],
};
