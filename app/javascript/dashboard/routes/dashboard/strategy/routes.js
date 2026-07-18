import { frontendURL } from '../../../helper/URLHelper';
import StrategyBoard from './StrategyBoard.vue';

export default {
  routes: [
    {
      // Painel Estratégico CEVICO: a empresa por pilares (só admin)
      path: frontendURL('accounts/:accountId/strategy'),
      name: 'cevico_strategy',
      meta: { permissions: ['administrator', 'agent'] },
      component: StrategyBoard,
    },
  ],
};
