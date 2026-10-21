// 🧭 Estado do Painel do empresário (27/09): o quadro inteiro, o autosave
// (900 ms depois da última mudança), as DATAS de tudo que entra e a LINHA DO
// TEMPO (criado, ação feita, conquista, pivô, ajuste, retrato do radar,
// marco). Os quadros recebem isto por provide/inject ('biz').
import { ref, watch, onBeforeUnmount } from 'vue';
import CrmAPI from 'dashboard/api/crm';

export const uid = () => Math.random().toString(16).slice(2, 10);
export const nowIso = () => new Date().toISOString();

export const RADAR_AREAS = [
  { key: 'marketing', label: 'Marketing' },
  { key: 'comercial', label: 'Comercial' },
  { key: 'financeiro', label: 'Financeiro' },
  { key: 'operacional', label: 'Operacional' },
  { key: 'estrutura', label: 'Estrutura física' },
  { key: 'pessoas', label: 'Pessoas' },
];

// o que cada tipo de atualização quer dizer (botão "Atualizar" e linha do tempo)
export const UPDATE_KINDS = {
  acao: { label: 'Ação feita', emoji: '✅', color: '#0A84FF' },
  conquista: { label: 'Conquistado', emoji: '🏆', color: '#C8962E' },
  pivot: { label: 'Pivotou', emoji: '↪️', color: '#BF5AF2' },
  ajuste: { label: 'Ajuste', emoji: '✏️', color: '#64748B' },
  concluido: { label: 'Concluído', emoji: '🎉', color: '#30A46C' },
  criado: { label: 'Anotado', emoji: '🆕', color: '#94A3B8' },
  radar: { label: 'Retrato do radar', emoji: '🕸️', color: '#0A84FF' },
  marco: { label: 'Marco', emoji: '📍', color: '#FF375F' },
};

const MAX_EVENTS = 400;

const asItems = list => (list || []).map(i => ({ created_at: null, ...i }));

// objetivos/metas/atividades antigos eram 5 textos soltos
const asYearItems = list =>
  (list || [])
    .map(v =>
      typeof v === 'string' ? { id: uid(), text: v, created_at: null } : v
    )
    .filter(v => v && v.text && v.text.trim());

export const emptyBoard = () => ({
  kanban: { todo: [], doing: [], done: [] },
  spc: { continuar: [], parar: [], comecar: [] },
  priorities: { do: [], schedule: [], delegate: [], drop: [] },
  opportunities: { first: [], plan: [], fit: [], avoid: [] },
  people: [],
  objectives: [],
  goals: [],
  activities: [],
  problems: [],
  core_activities: [],
  estimates: {
    source: 'oftalmofacil',
    faturamento: '',
    cirurgias: '',
    custo: '',
    updated_at: null,
  },
  layout: [],
  locked: false,
  events: [],
  radar: {
    areas: RADAR_AREAS.map(a => ({ ...a })),
    current: {},
    desired: {},
    notes: {},
    updated_at: null,
    snapshots: [],
  },
});

export const hydrateBoard = source => {
  const base = emptyBoard();
  if (!source || typeof source !== 'object') return base;
  ['kanban', 'spc', 'priorities', 'opportunities'].forEach(section => {
    Object.keys(base[section]).forEach(k => {
      base[section][k] = asItems(source[section]?.[k]);
    });
  });
  base.people = asItems(source.people);
  base.problems = asItems(source.problems);
  base.core_activities = asItems(source.core_activities);
  base.estimates = { ...base.estimates, ...(source.estimates || {}) };
  ['objectives', 'goals', 'activities'].forEach(k => {
    base[k] = asYearItems(source[k]);
  });
  base.layout = Array.isArray(source.layout) ? source.layout : [];
  base.locked = source.locked === true;
  base.events = Array.isArray(source.events) ? source.events : [];
  if (
    source.radar &&
    Array.isArray(source.radar.areas) &&
    source.radar.areas.length
  ) {
    base.radar = {
      ...base.radar,
      ...source.radar,
      current: { ...(source.radar.current || {}) },
      desired: { ...(source.radar.desired || {}) },
      notes: { ...(source.radar.notes || {}) },
      snapshots: [...(source.radar.snapshots || [])],
    };
  }
  return base;
};

export const fmtDay = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? ''
    : d.toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: '2-digit',
      });
};

export function useBusinessBoard(initial) {
  const board = ref(hydrateBoard(initial));
  const saveState = ref('idle'); // idle | saving | saved | error | conflict
  const savedAt = ref('');
  // 🔒 Rodada 4 (#414): a VERSÃO do quadro que esta tela carregou (updated_at
  // gravado pelo servidor). Vai junto em cada save; se alguém salvou depois,
  // o servidor recusa (409) e a tela troca pelo quadro atual em vez de apagar
  // o que o outro escreveu.
  const version = ref(initial?.updated_at || null);
  let timer = null;
  let ready = false;
  let dirty = false; // há mudança ainda não gravada?
  // UM save de cada vez: o próximo só sai depois que o anterior voltar (já
  // com a versão nova na mão). Sem isso, com rede lenta o 2º save saía com a
  // versão velha e levava 409 do PRÓPRIO save — o admin perdia o que digitou.
  let inFlight = null;
  let pending = false; // pediram outro save enquanto um estava no ar
  let ignoreNextChange = false; // a troca do quadro após 409 não é edição

  const sendBoard = async () => {
    saveState.value = 'saving';
    dirty = false;
    try {
      const { data } = await CrmAPI.saveBusinessBoard(
        board.value,
        version.value
      );
      version.value = data?.business?.updated_at || version.value;
      saveState.value = 'saved';
      savedAt.value = new Date().toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      });
    } catch (e) {
      const fresh =
        e?.response?.status === 409 ? e.response.data?.business : null;
      if (fresh && typeof fresh === 'object') {
        // quem salvou por último perde só o que digitou neste instante — e vê
        // o quadro de verdade. A troca abaixo não pode disparar outro autosave
        // (nem o save que estava na fila: ele era em cima do quadro velho).
        clearTimeout(timer);
        dirty = false;
        pending = false;
        ignoreNextChange = true;
        board.value = hydrateBoard(fresh);
        version.value = fresh.updated_at || null;
        saveState.value = 'conflict';
      } else {
        dirty = true;
        saveState.value = 'error';
      }
    }
  };
  const persist = () => {
    if (inFlight) {
      pending = true;
      return inFlight;
    }
    inFlight = sendBoard().finally(() => {
      inFlight = null;
      if (pending) {
        pending = false;
        if (dirty) persist();
      }
    });
    return inFlight;
  };
  watch(
    board,
    () => {
      if (ignoreNextChange) {
        ignoreNextChange = false;
        return;
      }
      if (!ready) return;
      dirty = true;
      clearTimeout(timer);
      timer = setTimeout(persist, 900);
    },
    { deep: true }
  );
  setTimeout(() => {
    ready = true;
  }, 300);
  onBeforeUnmount(() => {
    clearTimeout(timer);
    // só o que ainda não foi gravado — o servidor confere a versão, então
    // nunca grava por cima de um quadro mais novo; estado já salvo não é
    // reenviado (#414). Se houver save no ar, este entra na fila atrás dele.
    if (dirty) persist();
  });

  // linha do tempo (mais nova primeiro)
  const log = (kind, card, text) => {
    board.value.events.unshift({
      id: uid(),
      at: nowIso(),
      kind,
      card,
      text: (text || '').slice(0, 300),
    });
    if (board.value.events.length > MAX_EVENTS)
      board.value.events.length = MAX_EVENTS;
  };

  // anotação nova: nasce com data e vai para a linha do tempo
  const stampNew = (item, card, label) => {
    const at = nowIso();
    const stamped = { id: uid(), created_at: at, ...item };
    log('criado', card, label || item.text || item.name || item.problem || '');
    return stamped;
  };

  // "Atualizar": avanço, conquista, pivô ou ajuste — fica no item e na linha do tempo
  const updateItem = (item, kind, note, card) => {
    const at = nowIso();
    item.history = [
      ...(item.history || []),
      { at, kind, note: note || '' },
    ].slice(-20);
    item.updated_at = at;
    if (kind === 'conquista') item.status = 'conquistado';
    else if (kind === 'pivot') item.status = 'pivotado';
    else if (item.status === 'conquistado' || item.status === 'pivotado')
      item.status = 'aberto';
    const what = item.text || item.name || item.problem || '';
    log(kind, card, note ? `${what} — ${note}` : what);
  };

  return { board, saveState, savedAt, log, stampNew, updateItem };
}
