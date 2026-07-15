import TasksAPI from 'dashboard/api/tasks';

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
};

const getters = {
  getTasks: s => s.tasks,
  // badge da sidebar: tarefas do usuário atual AGUARDANDO ele (a fazer),
  // mais as atrasadas/perto do prazo em andamento
  getAlertCount: (s, _g, rootState, rootGetters) => {
    const userId = rootGetters.getCurrentUserID;
    return s.tasks.filter(
      t =>
        t.assignee?.id === userId &&
        (t.status === 'todo' || isOverdue(t) || isDueSoon(t))
    ).length;
  },
};

const actions = {
  async fetch({ commit }, params = {}) {
    const { data } = await TasksAPI.get(params);
    commit('setTasks', data);
    return data;
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
  async remove({ commit }, id) {
    await TasksAPI.delete(id);
    commit('removeTask', id);
  },
};

const mutations = {
  setTasks(s, tasks) {
    s.tasks = tasks;
    s.loaded = true;
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
