import { frontendURL } from '../../../helper/URLHelper';
import TasksBoard from './TasksBoard.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/tasks'),
      name: 'tasks_board',
      meta: { permissions: ['administrator', 'agent'] },
      component: TasksBoard,
    },
  ],
};
