import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import LabelsAPI from '../../api/labels';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { LABEL_EVENTS } from '../../helper/AnalyticsHelper/events';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isDeleting: false,
  },
};

// ordem definida pelo admin na tela de Etiquetas (position); etiqueta sem
// posição vai pro fim, em ordem alfabética. Ordenar SEMPRE no cliente: o
// cache local (IndexedDB) devolve as linhas fora de ordem.
const byAdminOrder = (a, b) => {
  const positionA = Number.isFinite(a.position) ? a.position : Infinity;
  const positionB = Number.isFinite(b.position) ? b.position : Infinity;
  if (positionA !== positionB) return positionA - positionB;
  return (a.title || '').localeCompare(b.title || '');
};

export const getters = {
  getLabels(_state) {
    return [..._state.records].sort(byAdminOrder);
  },
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  getLabelsOnSidebar(_state) {
    return [..._state.records]
      .sort(byAdminOrder)
      .filter(record => record.show_on_sidebar);
  },
  getLabelById: _state => id => {
    return _state.records.find(record => record.id === Number(id)) || {};
  },
};

export const actions = {
  revalidate: async function revalidate({ commit }, { newKey }) {
    try {
      const isExistingKeyValid = await LabelsAPI.validateCacheKey(newKey);
      if (!isExistingKeyValid) {
        const response = await LabelsAPI.refetchAndCommit(newKey);
        commit(types.SET_LABELS, response.data.payload);
      }
    } catch (error) {
      // Ignore error
    }
  },

  get: async function getLabels({ commit }) {
    commit(types.SET_LABEL_UI_FLAG, { isFetching: true });
    try {
      const response = await LabelsAPI.get(true);
      // a ordem visível sai do getter (position do admin)
      commit(types.SET_LABELS, response.data.payload);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_LABEL_UI_FLAG, { isFetching: false });
    }
  },

  create: async function createLabels({ commit }, cannedObj) {
    commit(types.SET_LABEL_UI_FLAG, { isCreating: true });
    try {
      const response = await LabelsAPI.create(cannedObj);
      AnalyticsHelper.track(LABEL_EVENTS.CREATE);
      commit(types.ADD_LABEL, response.data);
    } catch (error) {
      const errorMessage = error?.response?.data?.message;
      throw new Error(errorMessage);
    } finally {
      commit(types.SET_LABEL_UI_FLAG, { isCreating: false });
    }
  },

  update: async function updateLabels({ commit }, { id, ...updateObj }) {
    commit(types.SET_LABEL_UI_FLAG, { isUpdating: true });
    try {
      const response = await LabelsAPI.update(id, updateObj);
      AnalyticsHelper.track(LABEL_EVENTS.UPDATE);
      commit(types.EDIT_LABEL, response.data);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_LABEL_UI_FLAG, { isUpdating: false });
    }
  },

  // grava a nova ordem (admin): otimista na tela (reescreve position local),
  // refetch se o servidor recusar
  reorder: async function reorderLabels(
    { commit, dispatch, state: moduleState },
    orderedIds
  ) {
    const byId = new Map(
      moduleState.records.map(record => [record.id, record])
    );
    const reordered = orderedIds
      .map((id, index) => {
        const record = byId.get(id);
        return record ? { ...record, position: index + 1 } : null;
      })
      .filter(Boolean);
    // etiqueta fora da lista (ex.: criada em outra aba) não pode sumir
    const leftover = moduleState.records.filter(
      record => !orderedIds.includes(record.id)
    );
    commit(types.SET_LABELS, [...reordered, ...leftover]);
    try {
      await LabelsAPI.reorder(orderedIds);
    } catch (error) {
      await dispatch('get');
      throw new Error(error);
    }
  },

  delete: async function deleteLabels({ commit }, id) {
    commit(types.SET_LABEL_UI_FLAG, { isDeleting: true });
    try {
      await LabelsAPI.delete(id);
      AnalyticsHelper.track(LABEL_EVENTS.DELETED);
      commit(types.DELETE_LABEL, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_LABEL_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_LABEL_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.SET_LABELS]: MutationHelpers.set,
  [types.ADD_LABEL]: MutationHelpers.create,
  [types.EDIT_LABEL]: MutationHelpers.update,
  [types.DELETE_LABEL]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
