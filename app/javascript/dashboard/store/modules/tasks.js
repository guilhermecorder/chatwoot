import TasksAPI from 'dashboard/api/tasks';
import { isAppointmentTask } from 'dashboard/helper/cevicoAgenda';

const isOverdue = t =>
  t.status !== 'done' && t.due_at && new Date(t.due_at) < new Date();

const isDueSoon = t => {
  if (t.status === 'done' || !t.due_at) return false;
  const due = new Date(t.due_at).getTime();
  const now = Date.now();
  return due >= now && due - now <= 24 * 60 * 60 * 1000;
};

const state = {
  tasks: [],
  loaded: false,
  // 🐢 Rodada 7: número do badge vindo do servidor (tasks/alert_count) e os
  // cards do quadro de Tarefas quando a lista completa ainda não veio
  alertCount: null,
  boardCards: null,
};

// 🐢 Rodada 7: só a resposta do pedido MAIS RECENTE entra na store — o
// polling leve do Meu Painel nunca atropela a lista completa da Agenda
let fetchSeq = 0;

const getters = {
  getTasks: s => s.tasks,
  // badge da sidebar: tarefas do usuário atual AGUARDANDO ele (a fazer),
  // mais as atrasadas/perto do prazo em andamento. Item 305: agendamento da
  // Agenda não conta — quem marcou o retorno não "deve" uma tarefa
  // Rodada 7: antes de qualquer lista, vale a contagem do servidor
  getAlertCount: (s, _g, rootState, rootGetters) => {
    const userId = rootGetters.getCurrentUserID;
    const source = s.loaded ? s.tasks : s.boardCards;
    if (!source) return s.alertCount || 0;
    return source.filter(
      t =>
        !isAppointmentTask(t) &&
        t.assignee?.id === userId &&
        (t.status === 'todo' || isOverdue(t) || isDueSoon(t))
    ).length;
  },
};

const actions = {
  // sem params = janela padrão do servidor (−365/+365 dias + Lixeira);
  // { light: 1, from, canceled: 0 } = só o que o Meu Painel usa
  async fetch({ commit }, params = {}) {
    fetchSeq += 1;
    const seq = fetchSeq;
    const { data } = await TasksAPI.get(params);
    if (seq === fetchSeq) commit('setTasks', data);
    return data;
  },
  // badge da sidebar: só a contagem (não baixa a lista)
  async fetchAlertCount({ commit }) {
    const { data } = await TasksAPI.alertCount();
    commit('setAlertCount', data?.count || 0);
    return data?.count || 0;
  },
  async create({ commit }, payload) {
    const { data } = await TasksAPI.create(payload);
    commit('upsertTask', data);
    return data;
  },
  async update({ commit }, { id, ...payload }) {
    const { data } = await TasksAPI.update(id, payload);
    commit('upsertTask', data);
    return data;
  },
  // item 304: agendamento volta cancelado (Lixeira); card comum some de vez
  async remove({ commit }, id) {
    const { data } = await TasksAPI.trash(id);
    if (data && data.id) commit('upsertTask', data);
    else commit('removeTask', id);
    return data;
  },
  async purge({ commit }, id) {
    await TasksAPI.purge(id);
    commit('removeTask', id);
  },
};

const mutations = {
  setTasks(s, tasks) {
    s.tasks = tasks;
    s.loaded = true;
    s.boardCards = null;
  },
  setAlertCount(s, count) {
    s.alertCount = count;
  },
  // quadro de Tarefas (board=1): troca só os cards; os agendamentos da
  // store (Agenda/Meu Painel) ficam como estão
  setBoardCards(s, cards) {
    if (!s.loaded) {
      s.boardCards = cards;
      return;
    }
    s.tasks = s.tasks.filter(t => isAppointmentTask(t)).concat(cards);
  },
  upsertTask(s, task) {
    const idx = s.tasks.findIndex(t => t.id === task.id);
    if (idx === -1) s.tasks.push(task);
    else s.tasks.splice(idx, 1, task);
  },
  removeTask(s, id) {
    s.tasks = s.tasks.filter(t => t.id !== id);
  },
};

export default { namespaced: true, state, getters, actions, mutations };
