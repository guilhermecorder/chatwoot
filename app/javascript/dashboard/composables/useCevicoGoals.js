// 🎯 Metas oficiais do mês (Painel de Metas) para os dashboards de
// Relatórios: entrega, por indicador, o valor do MÊS ATUAL, a meta, se é
// RECORDE dos últimos 12 meses e o estado contra o ritmo esperado do mês.
// Os selos dos dashboards usam SEMPRE estes números oficiais (mesma fonte
// do Painel de Metas) — assim nunca discordam da tela de Metas, mesmo
// quando o KPI ao lado está filtrado por outro período.
import { ref, computed } from 'vue';
import CrmAPI from 'dashboard/api/crm';

export function useCevicoGoals() {
  const plan = ref(null);

  const load = async () => {
    try {
      const { data } = await CrmAPI.getGoalPlans();
      plan.value = data;
    } catch {
      plan.value = null; // sem metas = dashboards seguem sem selos
    }
  };

  const loaded = computed(() => Boolean(plan.value));

  // { current, target, record, state ('record'|'hit'|'low'|'critical'|''),
  //   goal ({current,target} | null) } — ou null sem dados
  const infoFor = key => {
    const data = plan.value;
    if (!data?.history?.length) return null;

    const currentRow = data.history.find(h => h.month === data.month);
    const current = Number(currentRow?.values?.[key] || 0);
    const prevMax = Math.max(
      0,
      ...data.history
        .filter(h => h.month !== data.month)
        .map(h => Number(h.values?.[key] || 0))
    );
    // recorde só vale contra histórico REAL (sem meses anteriores com dado,
    // qualquer número viraria "recorde" — troféu vazio não anima ninguém)
    const record = prevMax > 0 && current > prevMax;
    const target = Number(data.plan?.targets?.[key] || 0);

    let state = record ? 'record' : '';
    let goal = null;
    if (target > 0) {
      goal = { current, target };
      if (current >= target) {
        state = record ? 'record' : 'hit';
      } else if (!record) {
        // ritmo esperado: proporcional ao dia do mês
        const now = new Date();
        const daysInMonth = new Date(
          now.getFullYear(),
          now.getMonth() + 1,
          0
        ).getDate();
        const pace = target * (now.getDate() / daysInMonth);
        const ratio = pace > 0 ? current / pace : 1;
        if (ratio < 0.35) state = 'critical';
        else if (ratio < 0.65) state = 'low';
      }
    }

    return { current, target, record, state, goal };
  };

  const stateFor = key => infoFor(key)?.state || '';
  const goalFor = key => infoFor(key)?.goal || null;

  return { load, loaded, infoFor, stateFor, goalFor };
}
