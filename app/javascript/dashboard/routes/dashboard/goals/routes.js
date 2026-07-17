import { frontendURL } from '../../../helper/URLHelper';
import GoalsPanel from './GoalsPanel.vue';
import ClosingTools from './ClosingTools.vue';

export default {
  routes: [
    {
      // Painel de Metas: admin define, time acompanha
      path: frontendURL('accounts/:accountId/goals'),
      name: 'cevico_goals',
      meta: { permissions: ['administrator', 'agent'] },
      component: GoalsPanel,
    },
    {
      // Ferramentas de Fechamento: script + mapa de objeções (time lê)
      path: frontendURL('accounts/:accountId/tools'),
      name: 'cevico_tools',
      meta: { permissions: ['administrator', 'agent'] },
      component: ClosingTools,
    },
  ],
};
