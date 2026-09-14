// 🍎🍊 useCevicoPalette (rodada 163): o MOTOR de paletas do kit "iMac G3 +
// vidro", compartilhado pelo Meu Painel e pelos Relatórios/Dashboards.
//
// Por ESCOPO (um painel do Meu Painel ou um relatório), o admin escolhe:
//   - o escopo inteiro: cor do dia (iMac G3, muda sozinha) / uma paleta fixa
//     (17 opções) / salada de frutas (cada bloco uma fruta);
//   - cada BLOCO por cima (paleta própria do bloco > salada > escopo).
// Salvo em crm settings panel_palettes[escopo] = { mode, key, blocks }.
//
// Devolve as variáveis --cv* (paletteVars) para a página inteira (cvVars) e
// para cada bloco (blockVars(id)), mais o estado do popup CevicoPalettePicker.
import { ref, computed, unref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';
import {
  paletteFor, paletteVars, DAY_KEYS, SALAD, SALAD_ORDER,
} from 'dashboard/helper/cevicoPalettes';

const FLAVOR_ORDER = [1, 2, 3, 4, 5, 6, 0];

export function useCevicoPalette({
  scope, // string | Ref<string> — chave salva (ex.: 'agendamento', 'report:agentes')
  fallbackScope = null, // Ref<string|null> — herda deste escopo quando o seu não tem nada
  blocks = [], // [{ id, label, icon }] | Ref — os blocos da tela (ordem = ordem da salada)
  themePalette = null, // Ref<paleta|null> — fallback antes da cor do dia (tema legado)
} = {}) {
  const store = useStore();
  const crmSettings = useMapGetter('crm/getSettings');
  if (!crmSettings.value) store.dispatch('crm/fetchSettings').catch(() => {});

  const scopeKey = computed(() => String(unref(scope) || ''));
  const blockDefs = computed(() => unref(blocks) || []);

  // ── cor do dia + prévia só nesta tela (quem não é admin passeia pelas 7) ──
  const flavorPreview = ref(null);
  const dayFlavor = computed(
    () => paletteFor(DAY_KEYS[flavorPreview.value ?? new Date().getDay()]) || paletteFor('bondi')
  );
  const cycleFlavor = () => {
    const current = flavorPreview.value ?? new Date().getDay();
    const i = FLAVOR_ORDER.indexOf(current);
    flavorPreview.value = FLAVOR_ORDER[(i + 1) % FLAVOR_ORDER.length];
  };

  // ── a escolha salva deste escopo ──
  const panelPalette = computed(() => {
    const all = crmSettings.value?.panel_palettes || {};
    const fb = unref(fallbackScope);
    return all[scopeKey.value] || (fb ? all[fb] : null) || {};
  });
  // a paleta da PÁGINA: banner, seletor, régua, modais
  const pagePalette = computed(() => {
    const p = panelPalette.value;
    if (p.mode === 'salad') return SALAD;
    if (p.mode === 'fixed' && paletteFor(p.key)) return paletteFor(p.key);
    return unref(themePalette) || dayFlavor.value;
  });
  // a paleta de UM BLOCO: própria > salada (uma fruta por posição) > página
  const blockPalette = blockId => {
    const p = panelPalette.value;
    const own = p.blocks?.[blockId];
    if (own && paletteFor(own)) return paletteFor(own);
    if (p.mode === 'salad') {
      const i = Math.max(0, blockDefs.value.findIndex(b => b.id === blockId));
      return paletteFor(SALAD_ORDER[i % SALAD_ORDER.length]);
    }
    return pagePalette.value;
  };
  const blockVars = blockId => paletteVars(blockPalette(blockId));
  const blockFamily = blockId => blockPalette(blockId).family;
  const cvVars = computed(() => paletteVars(pagePalette.value));
  // cards de uma fileira: na salada (sem paleta própria no bloco) alternam
  // as frutas; senão, os 4 degraus da família do bloco
  const tileGradAt = (i, blockId = 'indicadores') => {
    const p = panelPalette.value;
    if (p.mode === 'salad' && !p.blocks?.[blockId]) {
      return paletteFor(SALAD_ORDER[i % SALAD_ORDER.length]).family[2];
    }
    const fam = blockFamily(blockId);
    return fam[i % fam.length];
  };
  const paletteLabel = pal => (pal.emoji ? `${pal.emoji} ${pal.label}` : pal.label);

  // ── o POPUP (CevicoPalettePicker): alvo + escolha; salva sozinho ──
  const palettePicker = ref(null); // { target: 'panel' | blockId }
  const isSavingPalette = ref(false);
  const openPalettePicker = (target = 'panel') => {
    palettePicker.value = { target };
  };
  const closePalettePicker = () => {
    palettePicker.value = null;
  };
  const savePanelPalettes = async next => {
    const all = { ...(crmSettings.value?.panel_palettes || {}) };
    if (next) all[scopeKey.value] = next;
    else delete all[scopeKey.value];
    isSavingPalette.value = true;
    try {
      await CrmAPI.updatePanelPalettes(all);
      await store.dispatch('crm/fetchSettings');
    } finally {
      isSavingPalette.value = false;
    }
  };
  const setPanelPalette = (mode, key = '') => {
    const cur = panelPalette.value;
    savePanelPalettes({ mode, key, blocks: { ...(cur.blocks || {}) } });
  };
  const setBlockPalette = (blockId, key) => {
    const cur = panelPalette.value;
    const nextBlocks = { ...(cur.blocks || {}) };
    if (key) nextBlocks[blockId] = key;
    else delete nextBlocks[blockId];
    savePanelPalettes({ mode: cur.mode || 'day', key: cur.key || '', blocks: nextBlocks });
  };
  const clearPanelPalettes = () => savePanelPalettes(null);
  // o que está marcado no popup para o alvo atual
  const paletteChoice = computed(() => {
    const t = palettePicker.value?.target;
    const p = panelPalette.value;
    if (!t) return '';
    if (t === 'panel') {
      if (p.mode === 'salad') return 'salad';
      return p.mode === 'fixed' ? p.key : 'day';
    }
    return p.blocks?.[t] || '';
  });
  const pickPalette = key => {
    const t = palettePicker.value?.target;
    if (!t) return;
    if (t === 'panel') {
      if (key === 'day') setPanelPalette('day');
      else if (key === 'salad') setPanelPalette('salad');
      else setPanelPalette('fixed', key);
    } else {
      setBlockPalette(t, key);
    }
  };
  const paletteTargets = computed(() => [
    { id: 'panel', label: 'Página inteira', icon: 'i-lucide-layout-dashboard' },
    ...blockDefs.value,
  ]);
  const ownBlockPalettes = computed(() =>
    Object.entries(panelPalette.value.blocks || {})
      .map(([id, key]) => ({ def: blockDefs.value.find(b => b.id === id), palette: paletteFor(key) }))
      .filter(x => x.def && x.palette)
      .map(x => ({ id: x.def.id, label: x.def.label, icon: x.def.icon, palette: x.palette }))
  );

  return {
    crmSettings,
    scopeKey,
    blockDefs,
    dayFlavor,
    flavorPreview,
    cycleFlavor,
    panelPalette,
    pagePalette,
    blockPalette,
    blockVars,
    blockFamily,
    cvVars,
    tileGradAt,
    paletteLabel,
    palettePicker,
    isSavingPalette,
    openPalettePicker,
    closePalettePicker,
    savePanelPalettes,
    setPanelPalette,
    setBlockPalette,
    clearPanelPalettes,
    paletteChoice,
    pickPalette,
    paletteTargets,
    ownBlockPalettes,
  };
}
