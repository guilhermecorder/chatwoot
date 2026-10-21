import { frontendURL } from '../../../../helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

// 🔐🏢 rodada 334: Configurações → Identidade da empresa (só administradores)
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/empresa'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'empresa_settings_index',
          meta: {
            permissions: ['administrator'],
          },
          component: Index,
        },
      ],
    },
  ],
};
