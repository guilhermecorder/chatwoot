import { useAlert } from 'dashboard/composables';

// 🔐 rodada 334 — aviso único de 403 nas chamadas CEVICO.
//
// O servidor (Crm::AccessControl) barra quem não tem o nível e devolve
// { error: "Você só pode ver X. Peça a um administrador para liberar a
// edição." }. Aqui a mensagem vira um alerta do sistema, uma vez só: a mesma
// mensagem não repete dentro de alguns segundos (telas que já mostram o
// próprio erro não geram alerta duplo em sequência).
const CEVICO_URL = /\/api\/v1\/accounts\/\d+\/(crm|tasks)(\/|$|\?)/;
const REPEAT_WINDOW_MS = 4000;
let lastMessage = '';
let lastAt = 0;

export const isCevicoRequest = url => CEVICO_URL.test(String(url ?? ''));

export const notifyCevicoForbidden = error => {
  const status = error?.response?.status;
  if (status !== 403) return false;
  if (!isCevicoRequest(error?.config?.url)) return false;
  const message = error?.response?.data?.error;
  if (!message || typeof message !== 'string') return false;
  const now = Date.now();
  if (message === lastMessage && now - lastAt < REPEAT_WINDOW_MS) return false;
  lastMessage = message;
  lastAt = now;
  useAlert(message);
  return true;
};

// só para os testes
export const resetCevicoForbidden = () => {
  lastMessage = '';
  lastAt = 0;
};
