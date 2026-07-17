import settings from './settings/settings.routes';
import conversation from './conversation/conversation.routes';
import { routes as searchRoutes } from '../../modules/search/search.routes';
import { routes as contactRoutes } from './contacts/routes';
import { routes as companyRoutes } from './companies/routes';
import { routes as notificationRoutes } from './notifications/routes';
import { routes as inboxRoutes } from './inbox/routes';
import { frontendURL } from '../../helper/URLHelper';
import helpcenterRoutes from './helpcenter/helpcenter.routes';
import campaignsRoutes from './campaigns/campaigns.routes';
import { routes as captainRoutes } from './captain/captain.routes';
import crmRoutes from './crm/routes';
import academyRoutes from './academy/routes';
import tasksRoutes from './tasks/routes';
import agendaRoutes from './agenda/routes';
import patientRoutes from './patient/routes';
import cevicoPagesRoutes from './pages/routes';
import cevicoStrategyRoutes from './strategy/routes';
import cevicoPeopleRoutes from './people/routes';
import cevicoGoalsRoutes from './goals/routes';
import cevicoFinanceRoutes from './finance/routes';
import inicioRoutes from './inicio/routes';
import cevicoAutomationsRoutes from './cevicoAutomations/routes';
import AppContainer from './Dashboard.vue';
import Suspended from './suspended/Index.vue';
import NoAccounts from './noAccounts/Index.vue';
import OnboardingAccountDetails from './onboarding/Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId'),
      component: AppContainer,
      children: [
        ...captainRoutes,
        ...inboxRoutes,
        ...conversation.routes,
        ...settings.routes,
        ...contactRoutes,
        ...companyRoutes,
        ...searchRoutes,
        ...notificationRoutes,
        ...helpcenterRoutes.routes,
        ...campaignsRoutes.routes,
        ...crmRoutes.routes,
        ...academyRoutes.routes,
        ...tasksRoutes.routes,
        ...agendaRoutes.routes,
        ...patientRoutes.routes,
        ...cevicoPagesRoutes.routes,
        ...cevicoStrategyRoutes.routes,
        ...cevicoPeopleRoutes.routes,
        ...cevicoGoalsRoutes.routes,
        ...cevicoFinanceRoutes.routes,
        ...inicioRoutes.routes,
        ...cevicoAutomationsRoutes.routes,
      ],
    },
    {
      path: frontendURL('accounts/:accountId/onboarding'),
      name: 'onboarding_account_details',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: OnboardingAccountDetails,
    },
    {
      path: frontendURL('accounts/:accountId/suspended'),
      name: 'account_suspended',
      meta: {
        permissions: ['administrator', 'agent', 'custom_role'],
      },
      component: Suspended,
    },
    {
      path: frontendURL('no-accounts'),
      name: 'no_accounts',
      component: NoAccounts,
    },
  ],
};
