import { frontendURL } from '../../../helper/URLHelper';
import HealthPage from './HealthPage.vue';
import HealthDashboard from './HealthDashboard.vue';
import HealthHome from './HealthHome.vue';

export default {
  routes: [
    {
      // Meu Painel da Saúde: porta de entrada do mundo (alvos + execuções)
      path: frontendURL('accounts/:accountId/health/painel'),
      name: 'hub_health_painel',
      meta: { permissions: ['administrator', 'agent'] },
      component: HealthHome,
    },
    {
      // Saúde (HUB, segmento saude): treino, dieta e corpo — painel pessoal.
      // Cada aba tem rota própria pro item certo acender no menu do modo Saúde.
      path: frontendURL('accounts/:accountId/health'),
      name: 'hub_health',
      meta: { permissions: ['administrator', 'agent'], healthTab: 'treino' },
      component: HealthPage,
    },
    {
      path: frontendURL('accounts/:accountId/health/boxe'),
      name: 'hub_health_boxe',
      meta: { permissions: ['administrator', 'agent'], healthTab: 'boxe' },
      component: HealthPage,
    },
    {
      path: frontendURL('accounts/:accountId/health/dieta'),
      name: 'hub_health_dieta',
      meta: { permissions: ['administrator', 'agent'], healthTab: 'dieta' },
      component: HealthPage,
    },
    {
      path: frontendURL('accounts/:accountId/health/corpo'),
      name: 'hub_health_corpo',
      meta: { permissions: ['administrator', 'agent'], healthTab: 'corpo' },
      component: HealthPage,
    },
    {
      // Dashboard da Saúde: resultados em linha/área (treino + dieta)
      path: frontendURL('accounts/:accountId/health/dashboard'),
      name: 'hub_health_dash',
      meta: { permissions: ['administrator', 'agent'] },
      component: HealthDashboard,
    },
  ],
};
