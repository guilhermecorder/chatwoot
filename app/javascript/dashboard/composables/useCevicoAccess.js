import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// 🔐 rodada 334 — acessos em ÁRVORE (ver × editar) no front.
//
// A fonte é `crm/getSettings().access`, montada pelo servidor para QUEM está
// logado: { admin, me: { 'crm': 'edit', 'relatorios.medicos': 'none', … },
// units: ['paulista'] (vazio = todas), role_id, catalog: [árvore com rótulos] }.
// `me` já vem resolvido (herança do pai, papel, padrão, ramo da empresa) —
// aqui só se compara o nível. Nó que NÃO está em `me` não existe para esta
// empresa (ex.: cirurgias numa ótica) → 'none' para todo mundo, admin incluso.
//
// Uso:  const { canView, canEdit, isAdmin, word } = useCevicoAccess();
//       v-if="canEdit('crm.funis')"   → esconde o botão de quem só vê
export const LEVEL_RANK = { none: 0, view: 1, edit: 2 };

export function useCevicoAccess() {
  const access = useMapGetter('crm/getAccess');
  const company = useMapGetter('crm/getCompany');
  const currentRole = useMapGetter('getCurrentRole');

  const isAdmin = computed(
    () => access.value?.admin === true || currentRole.value === 'administrator'
  );
  // as settings já chegaram? (antes disso o atendente não vê nada — fail-closed;
  // o admin vê tudo — fail-open, porque admin tem tudo mesmo)
  const loaded = computed(() => Boolean(access.value?.me));

  const level = key => {
    const me = access.value?.me;
    if (!me) return isAdmin.value ? 'edit' : 'none';
    return me[key] ?? 'none';
  };
  const can = (key, needed = 'view') =>
    (LEVEL_RANK[level(key)] ?? 0) >= (LEVEL_RANK[needed] ?? 1);
  const canView = key => can(key, 'view');
  const canEdit = key => can(key, 'edit');
  // qualquer um dos nós libera (ex.: um pai com vários filhos)
  const canAny = (keys, needed = 'view') => keys.some(k => can(k, needed));

  // unidades (lojas) que a pessoa pode ver; [] = todas
  const units = computed(() => access.value?.units ?? []);
  const unitAllowed = unitKey =>
    !units.value.length || !unitKey || units.value.includes(unitKey);

  // 🏢 vocabulário da empresa: word('paciente') → 'cliente' numa ótica
  const word = token => company.value?.vocabulary?.[token] ?? token;
  const fill = text =>
    String(text ?? '').replace(/\{\{(\w+)\}\}/g, (_, token) => {
      if (token === 'EMPRESA') return company.value?.name ?? 'CEVICO';
      const base = token.toLowerCase();
      const value = company.value?.vocabulary?.[base];
      if (!value) return `{{${token}}}`;
      return token[0] === token[0].toUpperCase()
        ? value.charAt(0).toUpperCase() + value.slice(1)
        : value;
    });
  const isClinic = computed(() => (company.value?.segment ?? 'clinica') === 'clinica');
  const hasModule = key => company.value?.modules?.[key] !== false;

  const catalog = computed(() => access.value?.catalog ?? []);

  return {
    access,
    company,
    isAdmin,
    loaded,
    level,
    can,
    canView,
    canEdit,
    canAny,
    units,
    unitAllowed,
    word,
    fill,
    isClinic,
    hasModule,
    catalog,
  };
}
