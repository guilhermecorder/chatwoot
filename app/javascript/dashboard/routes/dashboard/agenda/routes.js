import { frontendURL } from '../../../helper/URLHelper';
import AgendaBoard from './AgendaBoard.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/agenda'),
      name: 'agenda_board',
      meta: { permissions: ['administrator', 'agent'] },
      component: AgendaBoard,
    },
  ],
};
