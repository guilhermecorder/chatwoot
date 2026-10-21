import { createRouter, createWebHistory } from 'vue-router';

import { frontendURL } from '../helper/URLHelper';
import dashboard from './dashboard/dashboard.routes';
import store from 'dashboard/store';
import { validateLoggedInRoutes } from '../helper/routeHelpers';
import { isOnOnboardingView } from 'v3/helpers/RouteHelper';
import AnalyticsHelper from '../helper/AnalyticsHelper';
import { segmentoId } from '../helper/segmento';
import { routeAllowed, routeNodesFor } from '../helper/cevicoAccess';

const ONBOARDING_STEPS = ['account_details', 'enrichment', 'inbox_setup'];
const routes = [...dashboard.routes];

const onboardingPath = step =>
  step === 'inbox_setup' ? 'onboarding/inbox-setup' : 'onboarding';

// 🔐 CEVICO rodada 334 — acessos em ÁRVORE (ver × editar): a rota mapeada em
// ROUTE_NODES abre se `access.me[nó]` for pelo menos VER (qualquer nó da
// lista). A tranca de verdade é o backend (403) — aqui é só para a navegação
// fazer sentido.
//   - admin: passa SEMPRE enquanto as settings não chegaram; depois de
//     carregadas, também perde o que não está em `me` (módulo de clínica
//     numa ótica some para todo mundo)
//   - atendente: fail-closed — espera `crm/fetchSettings` para decidir
//   - rota sem nó no mapa: segue como sempre foi
const cevicoRouteAllowed = async (to, isAdminRole) => {
  if (!routeNodesFor(to.name).length) return true;
  let me = store.getters['crm/getAccess']?.me;
  if (!me) {
    // admin na primeira navegação: não espera, tem tudo mesmo
    if (isAdminRole) return true;
    // atendente por URL direta: espera as settings para decidir
    try {
      const settings = await store.dispatch('crm/fetchSettings');
      me = settings?.access?.me;
    } catch {
      return false;
    }
  }
  return routeAllowed(to.name, me, isAdminRole);
};

// HUB (rodada 34): módulos da Saúde por pessoa — rota de módulo não
// liberado volta pro Meu Painel da Saúde (lista vazia = todos)
const HEALTH_ROUTE_MODULE = {
  hub_health: 'treino',
  hub_health_cardio: 'cardio',
  hub_health_boxe: 'boxe',
  hub_health_corpo: 'corpo',
  hub_health_dieta: 'dieta',
  hub_health_dash: 'dash',
  hub_health_rotina: 'rotina',
  hub_health_educacao: 'educacao',
};
const healthRouteAllowed = async (to, isAdminRole) => {
  const key = HEALTH_ROUTE_MODULE[to.name];
  if (!key || isAdminRole) return true;
  let settings = store.getters['crm/getSettings'];
  // no 1º carregamento o store nasce com agent_permissions = {} (vazio, mas
  // truthy) — por isso o teste é pelo conteúdo, não pela presença
  if (!Object.keys(settings?.agent_permissions ?? {}).length) {
    try {
      await store.dispatch('crm/fetchSettings');
    } catch {
      return true;
    }
    settings = store.getters['crm/getSettings'];
  }
  const userId = String(store.getters.getCurrentUserID);
  const mods = settings?.agent_permissions?.health_modules?.[userId] ?? [];
  return mods.length === 0 || mods.includes(key);
};

export const router = createRouter({ history: createWebHistory(), routes });

// CEVICO: a primeira navegação após abrir/logar cai no Meu Painel (inicio),
// e não em Conversas. Depois disso, clicar em "Conversas" funciona normal.
let initialLandingDone = false;

export const validateAuthenticateRoutePermission = async (to, next) => {
  const { isLoggedIn, getCurrentUser: user } = store.getters;

  if (!isLoggedIn) {
    window.location.assign('/app/login');
    // aborta a navegação SPA enquanto o redirect acima assume — todo caminho
    // deste guard precisa chamar next (vue-router 4: "Invalid navigation guard")
    return next(false);
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
    const target = needsOnboarding
      ? onboardingPath(userAccount?.onboarding_step)
      : 'dashboard';
    return next(frontendURL(`accounts/${routeAccountId}/${target}`));
  }

  if (needsOnboarding && !isOnOnboardingView(to)) {
    return next(
      frontendURL(
        `accounts/${routeAccountId}/${onboardingPath(userAccount?.onboarding_step)}`
      )
    );
  }
  if (!needsOnboarding && isOnOnboardingView(to)) {
    return next(frontendURL(`accounts/${routeAccountId}/dashboard`));
  }

  if (!(await cevicoRouteAllowed(to, isAdmin))) {
    return next(frontendURL(`accounts/${routeAccountId}/dashboard`));
  }
  if (!(await healthRouteAllowed(to, isAdmin))) {
    return next(frontendURL(`accounts/${routeAccountId}/health/painel`));
  }

  // tela inicial do sistema = Meu Painel
  if (!initialLandingDone && (to.name === 'home' || to.name === 'inicio_home')) {
    initialLandingDone = true;
    // HUB (segmento saude, pedido 10/09): no mundo Saúde a porta de
    // entrada é o Meu Painel da Saúde — vale também pro atalho do
    // iPhone salvo em /inicio. Sem mundo escolhido, o Sidebar leva ao
    // /hub; no mundo Negócios segue o Meu Painel do negócio.
    if (segmentoId === 'saude' && localStorage.getItem('hub_mode') === 'saude') {
      return next(frontendURL(`accounts/${routeAccountId}/health/painel`));
    }
    if (to.name === 'home') {
      return next(frontendURL(`accounts/${routeAccountId}/inicio`));
    }
    return next();
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
