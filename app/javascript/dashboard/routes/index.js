import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import AnalyticsHelper from '../helper/AnalyticsHelper';

const ONBOARDING_STEPS = ['account_details', 'enrichment'];
const routes = [...dashboard.routes];

// CEVICO: seções bloqueáveis por agente (crm_settings.agent_permissions).
// Fail-open: se as settings ainda não carregaram, deixa passar — a sidebar
// já esconde os itens; isto só barra acesso por URL direta.
const CEVICO_BLOCKED_ROUTE_CHECKS = {
  crm: name => name === 'crm_board',
  crm_campaigns: name => name === 'crm_campaigns',
  tasks: name => name === 'tasks_board',
  agenda: name => name === 'agenda_board',
  academy: name => name?.startsWith('academy'),
  reports: name => name?.includes('_reports') || name === 'label_dashboard',
  companies: name => name?.startsWith('companies_'),
  captain: name => name?.startsWith('captain_'),
};

const isCevicoBlockedRoute = to => {
  const settings = store.getters['crm/getSettings'];
  const userId = store.getters.getCurrentUserID;
  const blocked = settings?.agent_permissions?.[String(userId)] ?? [];
  return blocked.some(key => CEVICO_BLOCKED_ROUTE_CHECKS[key]?.(to.name));
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

  if (isCevicoBlockedRoute(to)) {
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
