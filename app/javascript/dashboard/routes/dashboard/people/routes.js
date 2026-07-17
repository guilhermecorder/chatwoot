import { frontendURL } from '../../../helper/URLHelper';
import PeopleSpace from './PeopleSpace.vue';

export default {
  routes: [
    {
      // Ambiente Pessoas: DISC, desenvolvimento pessoal e feedbacks
      path: frontendURL('accounts/:accountId/people'),
      name: 'cevico_people',
      meta: { permissions: ['administrator', 'agent'] },
      component: PeopleSpace,
    },
  ],
};
