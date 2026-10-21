import { frontendURL } from '../../../helper/URLHelper';
import NegociosPage from './NegociosPage.vue';

export default {
  routes: [
    {
      // 🏢 Meus negócios (21/10): o lançador do dono — ícones das empresas,
      // clique = entra no sistema daquela empresa (só admin + e-mail de dono)
      path: frontendURL('accounts/:accountId/negocios'),
      name: 'negocios_home',
      meta: { permissions: ['administrator'] },
      component: NegociosPage,
    },
  ],
};
