import Auth from '../api/auth';
import { notifyCevicoForbidden } from './cevico403';

// 🔐 rodada 334: 403 de endpoint CEVICO mostra a mensagem do servidor
// ("Você só pode ver X…") uma vez, antes de devolver o erro para a tela
const parseErrorCode = error => {
  notifyCevicoForbidden(error);
  return Promise.reject(error);
};

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });
  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();
    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }
  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );
  return wootApi;
};
