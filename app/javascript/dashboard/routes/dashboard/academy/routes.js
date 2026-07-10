import { frontendURL } from '../../../helper/URLHelper';
import AcademyHome from './AcademyHome.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/academy'),
      name: 'academy_home',
      meta: { permissions: ['administrator', 'agent'] },
      component: AcademyHome,
    },
  ],
};
