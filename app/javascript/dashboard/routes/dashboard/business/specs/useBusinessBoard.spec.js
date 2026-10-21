// 🔒 Rodada 4 (#414): o Painel do empresário manda a VERSÃO do quadro que
// carregou; se alguém salvou depois, o servidor responde 409 e a tela troca
// pelo quadro atual — sem reenviar o quadro velho por cima.
import { nextTick } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import { useBusinessBoard, emptyBoard } from '../useBusinessBoard';

vi.mock('dashboard/api/crm', () => ({
  default: { saveBusinessBoard: vi.fn() },
}));

const flush = async () => {
  await vi.advanceTimersByTimeAsync(0);
  await nextTick();
};

describe('useBusinessBoard — versão do quadro', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    CrmAPI.saveBusinessBoard.mockReset();
    vi.spyOn(console, 'warn').mockImplementation(() => {}); // onBeforeUnmount fora de componente
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('manda a versão carregada junto com o quadro e guarda a versão nova', async () => {
    CrmAPI.saveBusinessBoard.mockResolvedValue({
      data: { business: { updated_at: 'v2' } },
    });
    const { board, saveState } = useBusinessBoard({
      ...emptyBoard(),
      updated_at: 'v1',
    });
    await vi.advanceTimersByTimeAsync(300); // a tela assentou

    board.value.people.push({ id: 'p1', name: 'Ana' });
    await nextTick();
    await vi.advanceTimersByTimeAsync(900);
    await flush();

    expect(CrmAPI.saveBusinessBoard).toHaveBeenCalledTimes(1);
    expect(CrmAPI.saveBusinessBoard.mock.calls[0][1]).toBe('v1');
    expect(saveState.value).toBe('saved');

    board.value.people.push({ id: 'p2', name: 'Bia' });
    await nextTick();
    await vi.advanceTimersByTimeAsync(900);
    await flush();
    expect(CrmAPI.saveBusinessBoard.mock.calls[1][1]).toBe('v2');
  });

  it('409: troca pelo quadro atual, avisa o conflito e NÃO manda o quadro velho de novo', async () => {
    const doOutro = {
      ...emptyBoard(),
      updated_at: 'v9',
      people: [{ id: 'x', name: 'Anotado pelo outro' }],
    };
    CrmAPI.saveBusinessBoard.mockRejectedValue({
      response: { status: 409, data: { conflict: true, business: doOutro } },
    });
    const { board, saveState } = useBusinessBoard({
      ...emptyBoard(),
      updated_at: 'v1',
    });
    await vi.advanceTimersByTimeAsync(300);

    board.value.people.push({ id: 'p1', name: 'Meu rascunho' });
    await nextTick();
    await vi.advanceTimersByTimeAsync(900);
    await flush();

    expect(saveState.value).toBe('conflict');
    expect(board.value.people.map(p => p.name)).toEqual(['Anotado pelo outro']);

    // a troca do quadro não dispara outro autosave
    await vi.advanceTimersByTimeAsync(3000);
    await flush();
    expect(CrmAPI.saveBusinessBoard).toHaveBeenCalledTimes(1);

    // depois do conflito, uma mudança nova sai com a versão atual (v9)
    CrmAPI.saveBusinessBoard.mockResolvedValue({
      data: { business: { updated_at: 'v10' } },
    });
    board.value.people.push({ id: 'p3', name: 'De novo' });
    await nextTick();
    await vi.advanceTimersByTimeAsync(900);
    await flush();
    expect(CrmAPI.saveBusinessBoard).toHaveBeenCalledTimes(2);
    expect(CrmAPI.saveBusinessBoard.mock.calls[1][1]).toBe('v9');
  });

  it('um save de cada vez: o 2º espera o 1º voltar e sai com a versão nova (rede lenta)', async () => {
    let solta;
    CrmAPI.saveBusinessBoard
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            solta = () => resolve({ data: { business: { updated_at: 'v2' } } });
          })
      )
      .mockResolvedValue({ data: { business: { updated_at: 'v3' } } });
    const { board, saveState } = useBusinessBoard({
      ...emptyBoard(),
      updated_at: 'v1',
    });
    await vi.advanceTimersByTimeAsync(300);

    board.value.people.push({ id: 'p1', name: 'Ana' });
    await nextTick();
    await vi.advanceTimersByTimeAsync(900); // save A no ar (não voltou)
    board.value.people.push({ id: 'p2', name: 'Bia' });
    await nextTick();
    await vi.advanceTimersByTimeAsync(900); // o timer do B dispara com A no ar
    await flush();
    expect(CrmAPI.saveBusinessBoard).toHaveBeenCalledTimes(1);

    solta(); // A volta com v2
    await flush();
    await flush();
    expect(CrmAPI.saveBusinessBoard).toHaveBeenCalledTimes(2);
    expect(CrmAPI.saveBusinessBoard.mock.calls[1][1]).toBe('v2');
    expect(
      CrmAPI.saveBusinessBoard.mock.calls[1][0].people.map(p => p.name)
    ).toEqual(['Ana', 'Bia']);
    await flush();
    expect(saveState.value).toBe('saved');
  });
});
