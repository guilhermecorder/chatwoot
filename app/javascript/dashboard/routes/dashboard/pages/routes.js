import { frontendURL } from '../../../helper/URLHelper';
import PagesHome from './PagesHome.vue';
import PagesAnalytics from './PagesAnalytics.vue';
import ContentBoard from './ContentBoard.vue';
import ABCenter from './ABCenter.vue';

export default {
  routes: [
    {
      // Páginas CEVICO: sites públicos por estágio da jornada do paciente
      path: frontendURL('accounts/:accountId/pages'),
      name: 'cevico_pages_home',
      meta: { permissions: ['administrator', 'agent'] },
      component: PagesHome,
    },
    {
      // Análise de Páginas + montador de funis (PÁGINAS PRO, admin)
      path: frontendURL('accounts/:accountId/pages/analise'),
      name: 'cevico_pages_analytics',
      meta: { permissions: ['administrator', 'agent'] },
      component: PagesAnalytics,
    },
    {
      // Planejamento de conteúdos (workflow de marketing)
      path: frontendURL('accounts/:accountId/pages/conteudos'),
      name: 'cevico_content_board',
      meta: { permissions: ['administrator', 'agent'] },
      component: ContentBoard,
    },
    {
      // Central de Testes A/B (admin)
      path: frontendURL('accounts/:accountId/pages/ab'),
      name: 'cevico_ab_center',
      meta: { permissions: ['administrator', 'agent'] },
      component: ABCenter,
    },
  ],
};
