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

export function useCevicoJourney({ period, compare, source, enabled = true }) {
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
    return e ? { serie: e.serie, serieAnterior: e.serie_anterior } : {};
  };

  return { journey, loading, reload: load, stepOf, lineOf };
}
