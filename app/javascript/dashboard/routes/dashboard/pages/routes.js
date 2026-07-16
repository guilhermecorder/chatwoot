import { frontendURL } from '../../../helper/URLHelper';
import PagesHome from './PagesHome.vue';

export default {
  routes: [
    {
      // Páginas CEVICO: sites públicos por estágio da jornada do paciente
      path: frontendURL('accounts/:accountId/pages'),
      name: 'cevico_pages_home',
      meta: { permissions: ['administrator', 'agent'] },
      component: PagesHome,
    },
  ],
};
