import { frontendURL } from '../../../helper/URLHelper';
import CrmBoard from './CrmBoard.vue';
import CrmCampaigns from './CrmCampaigns.vue';
import CrmCampaignsDashboard from './CrmCampaignsDashboard.vue';
import CrmForms from './CrmForms.vue';
import CrmIntegrationsPage from './CrmIntegrationsPage.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/crm'),
      name: 'crm_board',
      meta: { permissions: ['administrator', 'agent'] },
      component: CrmBoard,
    },
    {
      path: frontendURL('accounts/:accountId/crm/campaigns'),
      name: 'crm_campaigns',
      meta: { permissions: ['administrator'] },
      component: CrmCampaigns,
    },
    {
      path: frontendURL('accounts/:accountId/crm/campaigns/dashboard'),
      name: 'crm_campaigns_dashboard',
      meta: { permissions: ['administrator'] },
      component: CrmCampaignsDashboard,
    },
    {
      path: frontendURL('accounts/:accountId/crm/forms'),
      name: 'crm_forms',
      meta: { permissions: ['administrator'] },
      component: CrmForms,
    },
    {
      path: frontendURL('accounts/:accountId/crm/integrations'),
      name: 'crm_integrations',
      meta: { permissions: ['administrator'] },
      component: CrmIntegrationsPage,
    },
  ],
};
