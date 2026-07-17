import { frontendURL } from '../../../helper/URLHelper';
import FinancePanel from './FinancePanel.vue';

export default {
  routes: [
    {
      // Gestão Financeira: receitas, custos, tributos e investimentos (só admin)
      path: frontendURL('accounts/:accountId/finance'),
      name: 'cevico_finance',
      meta: { permissions: ['administrator'] },
      component: FinancePanel,
    },
  ],
};
