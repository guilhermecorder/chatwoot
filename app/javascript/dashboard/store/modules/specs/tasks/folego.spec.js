import tasks from '../../tasks';
import TasksAPI from 'dashboard/api/tasks';

// 🐢 Auditoria 10/2026 — Rodada 7 "Fôlego" (#149/#301/#316): a barra lateral
// pede só a contagem, o quadro de Tarefas só os cards e o polling leve do
// Meu Painel nunca atropela a lista completa da Agenda
vi.mock('dashboard/api/tasks', () => ({
  default: { get: vi.fn(), alertCount: vi.fn() },
}));

const { actions, getters, mutations } = tasks;
const rootGetters = { getCurrentUserID: 7 };
const card = (id, extra = {}) => ({
  id,
  task_type: null,
  unit: null,
  status: 'todo',
  assignee: { id: 7 },
  ...extra,
});
const consulta = id => ({
  id,
  task_type: 'consulta',
  unit: 'tatuape',
  status: 'todo',
  assignee: { id: 7 },
});

describe('tasks store — Rodada 7 "Fôlego"', () => {
  beforeEach(() => {
    TasksAPI.get.mockReset();
    TasksAPI.alertCount.mockReset();
  });

  it('badge usa a contagem do servidor enquanto nenhuma lista veio', async () => {
    const commit = vi.fn();
    TasksAPI.alertCount.mockResolvedValue({ data: { count: 4 } });
    await actions.fetchAlertCount({ commit });
    expect(commit).toHaveBeenCalledWith('setAlertCount', 4);
    const state = { tasks: [], loaded: false, alertCount: 4, boardCards: null };
    expect(getters.getAlertCount(state, {}, {}, rootGetters)).toBe(4);
  });

  it('com a lista carregada o badge volta a ser calculado na tela (agendamento não conta)', () => {
    const state = {
      tasks: [card(1), consulta(2)],
      loaded: true,
      alertCount: 9,
      boardCards: null,
    };
    expect(getters.getAlertCount(state, {}, {}, rootGetters)).toBe(1);
  });

  it('quadro de Tarefas troca só os cards e mantém os agendamentos da store', () => {
    const state = {
      tasks: [card(1), consulta(2)],
      loaded: true,
      alertCount: null,
      boardCards: null,
    };
    mutations.setBoardCards(state, [card(3)]);
    expect(state.tasks.map(t => t.id)).toEqual([2, 3]);

    // antes da lista completa: os cards ficam à parte (a Agenda continua
    // sabendo que precisa buscar a lista)
    const vazio = { tasks: [], loaded: false, alertCount: 0, boardCards: null };
    mutations.setBoardCards(vazio, [card(5), card(6)]);
    expect(vazio.tasks).toEqual([]);
    expect(getters.getAlertCount(vazio, {}, {}, rootGetters)).toBe(2);
  });

  it('resposta antiga (polling leve) que chega depois da nova é descartada', async () => {
    const commit = vi.fn();
    let releaseLight;
    TasksAPI.get
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            releaseLight = () => resolve({ data: [{ id: 1, light: true }] });
          })
      )
      .mockResolvedValueOnce({ data: [{ id: 1, description: 'completa' }] });

    const light = actions.fetch({ commit }, { light: 1 });
    await actions.fetch({ commit });
    releaseLight();
    await light;

    expect(commit).toHaveBeenCalledTimes(1);
    expect(commit).toHaveBeenCalledWith('setTasks', [
      { id: 1, description: 'completa' },
    ]);
  });
});
