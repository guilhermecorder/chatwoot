import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const ONBOARDING_STEPS = ['account_details', 'enrichment'];
const routes = [...dashboard.routes];

// CEVICO (modelo de CONCESSÃO, 17/07): rotas de áreas administrativas que
// abrem para atendente COM a área concedida pelo admin em
// crm_settings.agent_permissions['grants']. A tranca de verdade é o
// backend (require_capability) — aqui é só para a navegação fazer sentido.
// Fail-closed: sem concessão confirmada, volta para o painel.
const CEVICO_GRANTED_ROUTES = {
  crm_dashboard_reports: ['reports'],
  traffic_funnel_reports: ['reports'],
  doctors_reports: ['reports'],
  agents_dashboard_reports: ['reports'],
  agenda_dashboard_reports: ['reports'],
  ads_reports: ['reports'],
  google_dashboard_reports: ['reports'],
  whatsapp_health_reports: ['reports'],
  crm_campaigns: ['campaigns'],
  crm_campaigns_dashboard: ['campaigns', 'reports'],
  cevico_automations: ['automations', 'data_tools'],
  crm_integrations: ['settings'],
  cevico_finance: ['finance'],
  cevico_strategy: ['strategy'],
  cevico_pages_analytics: ['pages'],
  cevico_ab_center: ['pages'],
};

const cevicoRouteAllowed = async (to, isAdminRole) => {
  const needed = CEVICO_GRANTED_ROUTES[to.name];
  if (!needed || isAdminRole) return true;
  let settings = store.getters['crm/getSettings'];
  if (!settings?.agent_permissions) {
    // primeira navegação por URL direta: espera as settings para decidir
    try {
      settings = await store.dispatch('crm/fetchSettings');
    } catch {
      return false;
    }
  }
  const userId = String(store.getters.getCurrentUserID);
  const grants = settings?.agent_permissions?.grants?.[userId] ?? [];
  return needed.some(capability => grants.includes(capability));
};

export const router = createRouter({ history: createWebHistory(), routes });

// CEVICO: a primeira navegação após abrir/logar cai no Meu Painel (inicio),
// e não em Conversas. Depois disso, clicar em "Conversas" funciona normal.
let initialLandingDone = false;

export const validateAuthenticateRoutePermission = async (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    return '';
  }

  const { accounts = [], account_id: accountId } = user;

  if (!accounts.length) {
    if (to.name === 'no_accounts') {
      return next();
    }
    return next(frontendURL('no-accounts'));
  }

  const routeAccountId = Number(to.params?.accountId || accountId);
  const userAccount = accounts.find(a => a.id === routeAccountId);
  const isAdmin = userAccount?.role === 'administrator';
  const isActive = userAccount?.status === 'active';
  const needsOnboarding =
    ONBOARDING_STEPS.includes(userAccount?.onboarding_step) &&
    isAdmin &&
    isActive;

  if (to.name === 'no_accounts' || !to.name) {
    const target = needsOnboarding ? 'onboarding' : 'dashboard';
    return next(frontendURL(`accounts/${routeAccountId}/${target}`));
  }

  if (needsOnboarding && !isOnOnboardingView(to)) {
    return next(frontendURL(`accounts/${routeAccountId}/onboarding`));
  }
  if (!needsOnboarding && isOnOnboardingView(to)) {
    return next(frontendURL(`accounts/${routeAccountId}/dashboard`));
  }

  if (!(await cevicoRouteAllowed(to, isAdmin))) {
    return next(frontendURL(`accounts/${routeAccountId}/dashboard`));
  }

  // tela inicial do sistema = Meu Painel
  if (!initialLandingDone && to.name === 'home') {
    initialLandingDone = true;
    return next(frontendURL(`accounts/${routeAccountId}/inicio`));
  }
  initialLandingDone = true;

  const nextRoute = validateLoggedInRoutes(to, store.getters.getCurrentUser);
  return nextRoute ? next(frontendURL(nextRoute)) : next();
};

export const initalizeRouter = () => {
  const userAuthentication = store.dispatch('setUser');

  router.beforeEach(async (to, _from, next) => {
    AnalyticsHelper.page(to.name || '', {
      path: to.path,
      name: to.name,
    });

    await userAuthentication;
    await validateAuthenticateRoutePermission(to, next, store);
  });
};

export default router;
