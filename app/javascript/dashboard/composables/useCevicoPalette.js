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
//
// 🎨 item 387 (04/11, "está tudo travado no strawberry… quero escolher as
// cores, deixar aleatório"): além da tela, dá para escolher para TODAS AS
// TELAS de uma vez (escopo '*', pessoal ou da clínica) e o modo ALEATÓRIA
// (uma das 17 paletas sorteada cada vez que a tela abre). Quem vence:
//   minha cor desta tela > minha cor de todas as telas >
//   cor da clínica desta tela > cor da clínica de todas as telas > cor do dia
import { ref, computed, unref, provide, getCurrentInstance } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import CrmAPI from 'dashboard/api/crm';
import {
  paletteFor,
  paletteVars,
  DAY_KEYS,
  SALAD,
  SALAD_ORDER,
  PALETTES,
} from 'dashboard/helper/cevicoPalettes';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAdmin } from 'dashboard/composables/useAdmin';

const FLAVOR_ORDER = [1, 2, 3, 4, 5, 6, 0];
// 🎨 item 387: escopo que vale para TODAS as telas
export const ALL_SCREENS = '*';
const hasMode = entry => !!(entry && typeof entry === 'object' && entry.mode);

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
  // ── escolha PESSOAL (só para quem escolheu): fica em ui_settings do
  //    usuário, por escopo; vence a escolha do admin nesta tela ──
  const { uiSettings, updateUISettings } = useUISettings();
  const { isAdmin } = useAdmin();
  const userEntry = key => {
    const u = (uiSettings.value?.cevico_palettes || {})[key];
    return hasMode(u) ? u : null;
  };
  const userPalette = computed(() => userEntry(scopeKey.value));
  // 🎨 item 387: a minha cor de TODAS as telas
  const userGlobalPalette = computed(() => userEntry(ALL_SCREENS));
  // onde o popup salva: 'page' (esta tela) ou 'all' (todas as telas)
  const paletteReach = ref('page');
  const reachKey = () =>
    paletteReach.value === 'all' ? ALL_SCREENS : scopeKey.value;
  const saveUserPalette = next => {
    const all = { ...(uiSettings.value?.cevico_palettes || {}) };
    if (next) all[reachKey()] = next;
    else delete all[reachKey()];
    updateUISettings({ cevico_palettes: all });
  };
  const clearUserPalette = () => saveUserPalette(null);
  // tirar a cor própria desta tela (para valer a de todas as telas)
  const clearUserPagePalette = () => {
    const all = { ...(uiSettings.value?.cevico_palettes || {}) };
    delete all[scopeKey.value];
    updateUISettings({ cevico_palettes: all });
  };
  // as telas em que EU escolhi uma cor só delas
  const userOwnScopes = computed(() =>
    Object.keys(uiSettings.value?.cevico_palettes || {}).filter(
      k => k !== ALL_SCREENS && userEntry(k)
    )
  );
  // tirar as minhas cores próprias de todas as telas de uma vez
  const clearUserOwnPalettes = () => {
    const all = uiSettings.value?.cevico_palettes || {};
    updateUISettings({
      cevico_palettes: all[ALL_SCREENS]
        ? { [ALL_SCREENS]: all[ALL_SCREENS] }
        : {},
    });
  };
  // para quem o popup salva: 'me' (só eu) ou 'everyone' (admin, a clínica)
  const paletteAudience = ref('me');
  const blockDefs = computed(() => unref(blocks) || []);

  // ── cor do dia + prévia só nesta tela (quem não é admin passeia pelas 7) ──
  const flavorPreview = ref(null);
  const dayFlavor = computed(
    () =>
      paletteFor(DAY_KEYS[flavorPreview.value ?? new Date().getDay()]) ||
      paletteFor('bondi')
  );
  const cycleFlavor = () => {
    const current = flavorPreview.value ?? new Date().getDay();
    const i = FLAVOR_ORDER.indexOf(current);
    flavorPreview.value = FLAVOR_ORDER[(i + 1) % FLAVOR_ORDER.length];
  };
  // 🎲 item 387: ALEATÓRIA — uma das 17 paletas, sorteada quando a tela abre
  // (fica a mesma enquanto a tela está aberta; o dado do popup sorteia outra)
  const randomPick = () =>
    PALETTES[Math.floor(Math.random() * PALETTES.length)];
  const randomFlavor = ref(randomPick());
  const reroll = () => {
    const before = randomFlavor.value?.key;
    let next = randomPick();
    for (let i = 0; i < 5 && next.key === before; i += 1) next = randomPick();
    randomFlavor.value = next;
  };

  // ── a escolha salva deste escopo ──
  const savedPalettes = computed(() => crmSettings.value?.panel_palettes || {});
  const panelPalette = computed(() => {
    const all = savedPalettes.value;
    const fb = unref(fallbackScope);
    return all[scopeKey.value] || (fb ? all[fb] : null) || {};
  });
  // 🎨 item 387: a cor da clínica para TODAS as telas
  const clinicGlobalPalette = computed(() => {
    const g = savedPalettes.value[ALL_SCREENS];
    return hasMode(g) ? g : {};
  });
  // o que vale DE VERDADE: a minha (desta tela ou de todas) e a da clínica
  // (desta tela ou de todas — os blocos próprios desta tela continuam)
  const effUser = computed(
    () => userPalette.value || userGlobalPalette.value || null
  );
  const effClinic = computed(() => {
    const p = panelPalette.value;
    if (hasMode(p)) return p;
    const g = clinicGlobalPalette.value;
    return hasMode(g) ? { ...g, blocks: p.blocks || {} } : p;
  });
  const fromMode = entry => {
    if (entry.mode === 'salad') return SALAD;
    if (entry.mode === 'fixed' && paletteFor(entry.key))
      return paletteFor(entry.key);
    if (entry.mode === 'random') return randomFlavor.value;
    return null;
  };
  // modo que está valendo na página ('day' | 'fixed' | 'salad' | 'random')
  const pageMode = computed(
    () => effUser.value?.mode || effClinic.value.mode || 'day'
  );
  // a paleta da PÁGINA: banner, seletor, régua, modais
  const pagePalette = computed(() => {
    const u = effUser.value;
    if (u) {
      const own = fromMode(u);
      if (own) return own;
      if (u.mode === 'day') return dayFlavor.value;
    }
    return fromMode(effClinic.value) || unref(themePalette) || dayFlavor.value;
  });
  // a paleta de UM BLOCO: própria > salada (uma fruta por posição) > página
  const blockPalette = blockId => {
    const u = effUser.value;
    if (u) {
      if (u.mode === 'salad') {
        const i = Math.max(
          0,
          blockDefs.value.findIndex(b => b.id === blockId)
        );
        return paletteFor(SALAD_ORDER[i % SALAD_ORDER.length]);
      }
      return pagePalette.value;
    }
    const p = effClinic.value;
    const own = p.blocks?.[blockId];
    if (own && paletteFor(own)) return paletteFor(own);
    if (p.mode === 'salad') {
      const i = Math.max(
        0,
        blockDefs.value.findIndex(b => b.id === blockId)
      );
      return paletteFor(SALAD_ORDER[i % SALAD_ORDER.length]);
    }
    return pagePalette.value;
  };
  const blockVars = blockId => paletteVars(blockPalette(blockId));
  const blockFamily = blockId => blockPalette(blockId).family;
  // família da cor COMPLEMENTAR do bloco (cards alternados)
  const blockAltFamily = blockId => {
    const pal = blockPalette(blockId);
    return pal.altFamily || pal.family;
  };
  // tinta do texto sobre a complementar ('dark' só em cores claras)
  const blockAltInk = blockId => blockPalette(blockId).altInk || 'light';
  const cvVars = computed(() => paletteVars(pagePalette.value));
  // cards de uma fileira: na salada (sem paleta própria no bloco) alternam
  // as frutas; senão, os 4 degraus da família do bloco
  const tileGradAt = (i, blockId = 'indicadores') => {
    const u = effUser.value;
    const p = effClinic.value;
    const salad = u
      ? u.mode === 'salad'
      : p.mode === 'salad' && !p.blocks?.[blockId];
    if (salad) {
      return paletteFor(SALAD_ORDER[i % SALAD_ORDER.length]).family[2];
    }
    const fam = blockFamily(blockId);
    return fam[i % fam.length];
  };
  const paletteLabel = pal =>
    pal.emoji ? `${pal.emoji} ${pal.label}` : pal.label;

  // ── o POPUP (CevicoPalettePicker): alvo + escolha; salva sozinho ──
  const palettePicker = ref(null); // { target: 'panel' | blockId }
  const isSavingPalette = ref(false);
  const openPalettePicker = (target = 'panel') => {
    // admin abre em "todo mundo" (a não ser que já tenha cor pessoal); quem
    // não é admin só escolhe para si
    paletteAudience.value = isAdmin.value && !effUser.value ? 'everyone' : 'me';
    paletteReach.value = 'page';
    palettePicker.value = {
      target: paletteAudience.value === 'me' ? 'panel' : target,
    };
  };
  const setPaletteAudience = a => {
    paletteAudience.value =
      a === 'everyone' && isAdmin.value ? 'everyone' : 'me';
    if (paletteAudience.value === 'me' && palettePicker.value)
      palettePicker.value.target = 'panel';
  };
  // 🎨 item 387: esta tela × todas as telas (todas = só a página inteira)
  const setPaletteReach = r => {
    paletteReach.value = r === 'all' ? 'all' : 'page';
    if (paletteReach.value === 'all' && palettePicker.value)
      palettePicker.value.target = 'panel';
  };
  const closePalettePicker = () => {
    palettePicker.value = null;
  };
  const savePanelPalettes = async (next, key = scopeKey.value) => {
    // Rodada 4 (#351): manda só ESTE painel; null = apaga a paleta dele
    // (o servidor mescla painel a painel — os outros painéis ficam como estão)
    const all = { [key]: next || null };
    isSavingPalette.value = true;
    try {
      await CrmAPI.updatePanelPalettes(all);
      await store.dispatch('crm/fetchSettings');
    } finally {
      isSavingPalette.value = false;
    }
  };
  const setPanelPalette = (mode, key = '') => {
    if (paletteReach.value === 'all') {
      savePanelPalettes({ mode, key, blocks: {} }, ALL_SCREENS);
      return;
    }
    const cur = panelPalette.value;
    savePanelPalettes({ mode, key, blocks: { ...(cur.blocks || {}) } });
  };
  const setBlockPalette = (blockId, key) => {
    const cur = panelPalette.value;
    const nextBlocks = { ...(cur.blocks || {}) };
    if (key) nextBlocks[blockId] = key;
    else delete nextBlocks[blockId];
    savePanelPalettes({
      mode: cur.mode || 'day',
      key: cur.key || '',
      blocks: nextBlocks,
    });
  };
  // as telas em que a CLÍNICA escolheu uma cor só delas
  const clinicOwnScopes = computed(() =>
    Object.keys(savedPalettes.value).filter(k => k !== ALL_SCREENS)
  );
  // tirar as cores próprias da clínica de todas as telas de uma vez
  const clearClinicOwnPalettes = async () => {
    const nulls = Object.fromEntries(clinicOwnScopes.value.map(k => [k, null]));
    if (!Object.keys(nulls).length) return;
    isSavingPalette.value = true;
    try {
      await CrmAPI.updatePanelPalettes(nulls);
      await store.dispatch('crm/fetchSettings');
    } finally {
      isSavingPalette.value = false;
    }
  };
  const clearPanelPalettes = () =>
    savePanelPalettes(
      null,
      paletteReach.value === 'all' ? ALL_SCREENS : scopeKey.value
    );
  // o que está marcado no popup para o alvo atual
  const choiceOf = entry => {
    if (!hasMode(entry)) return '';
    if (['salad', 'day', 'random'].includes(entry.mode)) return entry.mode;
    return entry.key || '';
  };
  const paletteChoice = computed(() => {
    const t = palettePicker.value?.target;
    if (!t) return '';
    const all = paletteReach.value === 'all';
    if (paletteAudience.value === 'me') {
      return choiceOf(all ? userGlobalPalette.value : userPalette.value);
    }
    if (all) return choiceOf(clinicGlobalPalette.value);
    const p = panelPalette.value;
    if (t === 'panel') return choiceOf(p) || 'day';
    return p.blocks?.[t] || '';
  });
  // a escolha que está no alvo atual do popup (para o botão "voltar")
  const hasChoiceHere = computed(() => {
    const all = paletteReach.value === 'all';
    if (paletteAudience.value === 'me')
      return !!(all ? userGlobalPalette.value : userPalette.value);
    return all
      ? hasMode(clinicGlobalPalette.value)
      : Object.keys(panelPalette.value).length > 0;
  });
  const pickPalette = key => {
    const t = palettePicker.value?.target;
    if (!t) return;
    if (paletteAudience.value === 'me') {
      if (key === '') saveUserPalette(null);
      else if (['day', 'salad', 'random'].includes(key))
        saveUserPalette({ mode: key });
      else saveUserPalette({ mode: 'fixed', key });
      if (key === 'random') reroll();
      return;
    }
    if (t === 'panel') {
      if (['day', 'salad', 'random'].includes(key)) setPanelPalette(key);
      else setPanelPalette('fixed', key);
      if (key === 'random') reroll();
    } else {
      setBlockPalette(t, key);
    }
  };
  const paletteTargets = computed(() => [
    { id: 'panel', label: 'Página inteira', icon: 'i-lucide-layout-dashboard' },
    ...(paletteAudience.value === 'me' || paletteReach.value === 'all'
      ? []
      : blockDefs.value),
  ]);
  const ownBlockPalettes = computed(() =>
    Object.entries(panelPalette.value.blocks || {})
      .map(([id, key]) => ({
        def: blockDefs.value.find(b => b.id === id),
        palette: paletteFor(key),
      }))
      .filter(x => x.def && x.palette)
      .map(x => ({
        id: x.def.id,
        label: x.def.label,
        icon: x.def.icon,
        palette: x.palette,
      }))
  );

  const api = {
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
    blockAltFamily,
    blockAltInk,
    cvVars,
    tileGradAt,
    paletteLabel,
    palettePicker,
    isSavingPalette,
    openPalettePicker,
    closePalettePicker,
    userPalette,
    userGlobalPalette,
    clinicGlobalPalette,
    paletteAudience,
    setPaletteAudience,
    paletteReach,
    setPaletteReach,
    clearUserPalette,
    clearUserPagePalette,
    userOwnScopes,
    clearUserOwnPalettes,
    clinicOwnScopes,
    clearClinicOwnPalettes,
    hasChoiceHere,
    pageMode,
    randomFlavor,
    reroll,
    isAdmin,
    savePanelPalettes,
    setPanelPalette,
    setBlockPalette,
    clearPanelPalettes,
    paletteChoice,
    pickPalette,
    paletteTargets,
    ownBlockPalettes,
  };
  // 21/10: os blocos do guia arejado (CvBloco) pegam a paleta do PRÓPRIO bloco
  // daqui (salada de frutas / fruta por bloco) pelo id="bloco-<id>"
  if (getCurrentInstance()) provide('cevicoPalette', api);
  return api;
}
