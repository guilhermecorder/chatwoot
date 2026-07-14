import { frontendURL } from '../../../helper/URLHelper';
import InicioPage from './InicioPage.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/inicio'),
      name: 'inicio_home',
      meta: { permissions: ['administrator', 'agent'] },
      component: InicioPage,
    },
  ],
};
