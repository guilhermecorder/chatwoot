import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// 🔐🏢 rodada 334: Configurações → Acessos e papéis (só administradores)
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/acessos'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'acessos_settings_index',
          meta: {
            permissions: ['administrator'],
          },
          component: Index,
        },
      ],
    },
  ],
};
