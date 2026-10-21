import crm from '../../crm';
import CrmAPI from 'dashboard/api/crm';

// 🫁 Auditoria 12/10 — Rodada 7 (#323): "Carregar todos" em páginas por
// coluna, com a busca indo para o servidor (q=)
vi.mock('dashboard/api/crm', () => ({
  default: { getContacts: vi.fn() },
}));

const { actions } = crm;

describe('crm store — board em páginas (#323)', () => {
  beforeEach(() => {
    CrmAPI.getContacts.mockReset();
  });

  it('manda a busca (q) junto no "Carregar todos"', async () => {
    const commit = vi.fn();
    CrmAPI.getContacts.mockResolvedValue({
      data: { payload: [], meta: { scope: 'all', q: 'joana' } },
    });
    await actions.fetchContacts(
      { commit },
      { pipelineId: 7, scope: 'all', q: 'joana' }
    );
    expect(CrmAPI.getContacts).toHaveBeenCalledWith(7, {
      scope: 'all',
      q: 'joana',
    });
    expect(commit).toHaveBeenCalledWith('setContactsMeta', {
      scope: 'all',
      q: 'joana',
    });
  });

  it('descarta a resposta antiga que chega depois da nova (só vale a última busca)', async () => {
    const commit = vi.fn();
    let releaseOld;
    CrmAPI.getContacts
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            releaseOld = () =>
              resolve({ data: { payload: [{ id: 1 }], meta: { q: 'jo' } } });
          })
      )
      .mockResolvedValueOnce({
        data: { payload: [{ id: 2 }], meta: { q: 'joana' } },
      });

    const old = actions.fetchContacts(
      { commit },
      { pipelineId: 7, scope: 'all', q: 'jo' }
    );
    await actions.fetchContacts(
      { commit },
      { pipelineId: 7, scope: 'all', q: 'joana' }
    );
    releaseOld();
    await old;

    const contactsCommits = commit.mock.calls.filter(
      ([m]) => m === 'setContacts'
    );
    expect(contactsCommits).toEqual([['setContacts', [{ id: 2 }]]]);
  });

  it('"Carregar mais" da coluna no modo todos pede range=all e a mesma busca', async () => {
    const commit = vi.fn();
    CrmAPI.getContacts.mockResolvedValue({
      data: { payload: [{ id: 9 }], meta: {} },
    });
    await actions.fetchMoreStage(
      { commit, state: { contactsMeta: { scope: 'all', q: 'joana' } } },
      {
        pipelineId: 7,
        stageId: 3,
        offset: 200,
        limit: 200,
        range: 'all',
        q: 'joana',
      }
    );
    expect(CrmAPI.getContacts).toHaveBeenCalledWith(7, {
      scope: 'stage_page',
      stage_id: 3,
      offset: 200,
      limit: 200,
      range: 'all',
      q: 'joana',
    });
    expect(commit).toHaveBeenCalledWith('appendContacts', [{ id: 9 }]);
  });

  it('resposta velha descartada não apaga o spinner da carga nova ainda no ar', async () => {
    const commit = vi.fn();
    let releaseNew;
    CrmAPI.getContacts
      .mockResolvedValueOnce({ data: { payload: [], meta: { q: 'jo' } } })
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            releaseNew = () =>
              resolve({ data: { payload: [], meta: { q: 'joana' } } });
          })
      );

    const old = actions.fetchContacts(
      { commit },
      { pipelineId: 7, scope: 'all', q: 'jo' }
    );
    const fresh = actions.fetchContacts(
      { commit },
      { pipelineId: 7, scope: 'all', q: 'joana' }
    );
    await old;
    const flagsOff = () =>
      commit.mock.calls.filter(
        ([m, v]) => m === 'setUIFlag' && v.isFetchingContacts === false
      ).length;
    expect(flagsOff()).toBe(0);

    releaseNew();
    await fresh;
    expect(flagsOff()).toBe(1);
  });

  it('"Carregar mais" que chega depois de uma busca nova é descartado', async () => {
    const commit = vi.fn();
    let releasePage;
    CrmAPI.getContacts
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            releasePage = () =>
              resolve({ data: { payload: [{ id: 5 }], meta: {} } });
          })
      )
      .mockResolvedValueOnce({
        data: { payload: [], meta: { scope: 'all', q: 'maria' } },
      });

    const state = { contactsMeta: { scope: 'all', q: 'jo' } };
    const page = actions.fetchMoreStage(
      { commit, state },
      {
        pipelineId: 7,
        stageId: 3,
        offset: 200,
        limit: 200,
        range: 'all',
        q: 'jo',
      }
    );
    await actions.fetchContacts(
      { commit },
      { pipelineId: 7, scope: 'all', q: 'maria', silent: true }
    );
    releasePage();
    await page;

    expect(commit).not.toHaveBeenCalledWith('appendContacts', [{ id: 5 }]);
  });
});
