// ACESSO AOS MÓDULOS DA SAÚDE (rodada 34) — pedido dele 20/09: "o admin
// precisa ter o controle de quem terá acesso a que; algumas pessoas não
// precisam do software de boxe". O admin marca, por pessoa, quais módulos
// aparecem (crm_settings.agent_permissions.health_modules[user_id]; lista
// vazia = todos). Admin vê tudo. O boxe ainda depende do recurso ligado.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

export const HEALTH_MODULES = [
  { key: 'treino', label: 'Treino', icon: 'i-lucide-dumbbell', route: 'hub_health' },
  { key: 'cardio', label: 'Cardio', icon: 'i-lucide-heart-pulse', route: 'hub_health_cardio' },
  { key: 'boxe', label: 'Boxe', icon: 'i-lucide-swords', route: 'hub_health_boxe' },
  { key: 'corpo', label: 'Corpo', icon: 'i-lucide-ruler', route: 'hub_health_corpo' },
  { key: 'dieta', label: 'Dieta', icon: 'i-lucide-utensils', route: 'hub_health_dieta' },
  { key: 'dash', label: 'Análises', icon: 'i-lucide-area-chart', route: 'hub_health_dash' },
  { key: 'rotina', label: 'Rotina', icon: 'i-lucide-calendar-range', route: 'hub_health_rotina' },
];
export const ROUTE_MODULE = Object.fromEntries(HEALTH_MODULES.map(m => [m.route, m.key]));

export const modulesFor = (settings, userId) =>
  settings?.agent_permissions?.health_modules?.[String(userId)] ?? [];
export const moduleAllowed = (settings, userId, isAdmin, key) => {
  if (isAdmin) return true;
  const mods = modulesFor(settings, userId);
  return mods.length === 0 || mods.includes(key);
};

export const useHealthAccess = () => {
  const settings = useMapGetter('crm/getSettings');
  const role = useMapGetter('getCurrentRole');
  const uid = useMapGetter('getCurrentUserID');
  const isAdmin = computed(() => role.value === 'administrator');
  const modules = computed(() => modulesFor(settings.value, uid.value));
  const allowed = key => moduleAllowed(settings.value, uid.value, isAdmin.value, key);
  return { isAdmin, modules, allowed };
};
