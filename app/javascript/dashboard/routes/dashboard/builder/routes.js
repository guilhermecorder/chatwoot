import { frontendURL } from '../../../helper/URLHelper';
import BuilderPanel from './BuilderPanel.vue';

export default {
  routes: [
    {
      // 🧲 CONSTRUTOR (item 57): painel personalizado por pessoa —
      // drag-and-drop com ímã, tamanhos e paleta de cores
      path: frontendURL('accounts/:accountId/builder'),
      name: 'cevico_builder',
      meta: { permissions: ['administrator', 'agent'] },
      component: BuilderPanel,
    },
  ],
};
