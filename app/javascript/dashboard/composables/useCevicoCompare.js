// 📐 item 394 (11/11) — BASE DE COMPARAÇÃO reutilizável nas telas CEVICO.
//
//   const { compare, setCompare } = useCevicoCompare('cevico_home_compare');
//     compare     → { mode, month } (v-model do CompareRuler); a escolha fica
//                   salva POR PESSOA em ui_settings[chave]
//   const { journey, loading } = useCevicoJourney({ period, compare, source });
//     journey     → a jornada do paciente (Crm::JourneyService): cada etapa com
//                   número, base de comparação e as duas linhas
//     lineOf(key) → { serie, serieAnterior } de uma etapa/desvio, pronto para
//                   v-bind num CvIndicador
// Tela nova que quiser comparar períodos: CompareRuler + compareParams(compare)
// na chamada da API; o servidor resolve com Crm::ResolvesPeriod#period_comparison.
import { ref, computed, watch, toValue } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import CrmAPI from 'dashboard/api/crm';
import {
  normalizeCompare,
  compareParams,
} from 'dashboard/helper/cevicoComparison';

export function useCevicoCompare(settingKey = 'cevico_compare') {
  const { uiSettings, updateUISettings } = useUISettings();
  const compare = ref(normalizeCompare(uiSettings.value?.[settingKey]));
  const setCompare = value => {
    compare.value = normalizeCompare(value);
    updateUISettings({ [settingKey]: compare.value });
  };
  return { compare, setCompare };
}

// 📅 item 421: QUAIS DIAS entram na Jornada — todos, só dias úteis, só fim de
// semana ou "úteis × fim de semana" (média por dia). A escolha é uma só para o
// Meu Painel novo e o clássico e fica guardada no navegador.
export const JOURNEY_DAY_MODES = [
  { key: 'all', label: 'Todos os dias' },
  { key: 'weekdays', label: 'Dias úteis' },
  { key: 'weekends', label: 'Fim de semana' },
  { key: 'versus', label: 'Úteis × fim de semana' },
];
const DAYS_STORE = 'cevico_journey_days';
const readDays = () => {
  try {
    const saved = window.localStorage.getItem(DAYS_STORE);
    return JOURNEY_DAY_MODES.some(m => m.key === saved) ? saved : 'all';
  } catch {
    return 'all';
  }
};
export const journeyDays = ref(readDays());
export const setJourneyDays = key => {
  journeyDays.value = JOURNEY_DAY_MODES.some(m => m.key === key) ? key : 'all';
  try {
    window.localStorage.setItem(DAYS_STORE, journeyDays.value);
  } catch {
    // navegador sem armazenamento: vale só nesta visita
  }
};

// `days: false` = jornada SEM o filtro de dias (para os indicadores da tela,
// que mostram o período inteiro mesmo quando o bloco da Jornada está filtrado)
export function useCevicoJourney({
  period,
  compare,
  source,
  enabled = true,
  days = true,
}) {
  const dayMode = () => (days ? journeyDays.value : 'all');
  const journey = ref(null);
  const loading = ref(false);
  let seq = 0;

  const load = async () => {
    if (!toValue(enabled)) return;
    const p = toValue(period) || {};
    seq += 1;
    const mine = seq;
    loading.value = true;
    try {
      const { data } = await CrmAPI.getJourney({
        preset: p.preset,
        from: p.from,
        to: p.to,
        source: toValue(source) || undefined,
        days: dayMode() === 'all' ? undefined : dayMode(),
        ...compareParams(toValue(compare)),
      });
      // resposta de um pedido antigo (trocou o período no meio) não vale
      if (mine === seq) journey.value = data;
    } catch {
      if (mine === seq) journey.value = null;
    } finally {
      if (mine === seq) loading.value = false;
    }
  };

  watch(
    () => [
      JSON.stringify(toValue(period) || {}),
      JSON.stringify(toValue(compare) || {}),
      toValue(source),
      toValue(enabled),
      dayMode(),
    ],
    load,
    { immediate: true }
  );

  const byKey = computed(() => {
    const map = {};
    [
      ...(journey.value?.etapas || []),
      ...(journey.value?.desvios || []),
    ].forEach(e => {
      map[e.key] = e;
    });
    return map;
  });
  const stepOf = key => byKey.value[key] || null;
  const lineOf = key => {
    const e = byKey.value[key];
    if (!e) return {};
    // 📈 item 421: período curto (Hoje, Ontem…) — a mini linha do indicador
    // começa nos dias anteriores, para mostrar de onde o número vem
    if (e.contexto?.length)
      return { serie: [...e.contexto, ...e.serie], serieAnterior: null };
    return { serie: e.serie, serieAnterior: e.serie_anterior };
  };
  // 📈 item 421: o que o CompareLine precisa além das duas séries — os dias
  // anteriores (contexto), o dia em andamento e os fins de semana
  const lineExtras = key => {
    const j = journey.value;
    const e = byKey.value[key];
    if (!j || !e) return {};
    return {
      leadValues: e.contexto || [],
      leadLabels: j.contexto?.rotulos || [],
      leadWeekends: j.contexto?.fins_de_semana || [],
      weekends: j.fins_de_semana || [],
      partial: !!j.parcial,
    };
  };

  return { journey, loading, reload: load, stepOf, lineOf, lineExtras };
}
