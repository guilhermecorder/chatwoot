import {
  notifyCevicoForbidden,
  isCevicoRequest,
  resetCevicoForbidden,
} from '../cevico403';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
import { useAlert } from 'dashboard/composables';

// 🔐 rodada 334: 403 das chamadas CEVICO vira um alerta, uma vez só
describe('cevico403', () => {
  const forbidden = (url, error = 'Você só pode ver o CRM.') => ({
    config: { url },
    response: { status: 403, data: { error } },
  });

  beforeEach(() => {
    resetCevicoForbidden();
    useAlert.mockClear();
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 12, 10, 0, 0));
  });
  afterEach(() => vi.useRealTimers());

  it('reconhece só as URLs CEVICO (crm e tasks)', () => {
    expect(isCevicoRequest('/api/v1/accounts/3/crm/pipelines')).toBe(true);
    expect(isCevicoRequest('/api/v1/accounts/3/tasks')).toBe(true);
    expect(isCevicoRequest('/api/v1/accounts/3/tasks?status=open')).toBe(true);
    expect(isCevicoRequest('/api/v1/accounts/3/conversations')).toBe(false);
    expect(isCevicoRequest('/api/v1/accounts/3/crmx')).toBe(false);
    expect(isCevicoRequest(undefined)).toBe(false);
  });

  it('mostra a mensagem do servidor num 403 CEVICO', () => {
    expect(
      notifyCevicoForbidden(forbidden('/api/v1/accounts/3/crm/pipelines'))
    ).toBe(true);
    expect(useAlert).toHaveBeenCalledWith('Você só pode ver o CRM.');
  });

  it('ignora 403 do core, outros status e resposta sem mensagem', () => {
    expect(
      notifyCevicoForbidden(forbidden('/api/v1/accounts/3/conversations'))
    ).toBe(false);
    expect(
      notifyCevicoForbidden({
        config: { url: '/api/v1/accounts/3/crm/pipelines' },
        response: { status: 422, data: { error: 'x' } },
      })
    ).toBe(false);
    expect(
      notifyCevicoForbidden({
        config: { url: '/api/v1/accounts/3/crm/pipelines' },
        response: { status: 403, data: {} },
      })
    ).toBe(false);
    expect(notifyCevicoForbidden(null)).toBe(false);
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('não repete a mesma mensagem em sequência (janela de 4s)', () => {
    const err = forbidden('/api/v1/accounts/3/crm/pipelines');
    expect(notifyCevicoForbidden(err)).toBe(true);
    expect(notifyCevicoForbidden(err)).toBe(false);
    expect(useAlert).toHaveBeenCalledTimes(1);
    // mensagem diferente passa
    expect(
      notifyCevicoForbidden(
        forbidden('/api/v1/accounts/3/tasks', 'Você não tem acesso a Tarefas.')
      )
    ).toBe(true);
    // depois da janela, a primeira volta a aparecer
    vi.advanceTimersByTime(4001);
    expect(notifyCevicoForbidden(err)).toBe(true);
    expect(useAlert).toHaveBeenCalledTimes(3);
  });
});
