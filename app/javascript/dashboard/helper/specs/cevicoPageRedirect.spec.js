import {
  cleanAnchor,
  anchorValid,
  redirectPath,
  redirectSummary,
  redirectedToCount,
} from '../cevicoPageRedirect';

const pages = [
  {
    id: 1,
    slug: 'astigmatismo-e-miopia',
    status: 'redirected',
    redirect: { page_id: 2, anchor: 'juntos' },
  },
  {
    id: 2,
    slug: 'diferenca-miopia-astigmatismo-hipermetropia',
    status: 'published',
    redirect: null,
  },
  {
    id: 3,
    slug: 'grau-maximo',
    status: 'redirected',
    redirect: { page_id: 1, anchor: null },
  },
  {
    id: 4,
    slug: 'guia-velho',
    status: 'redirected',
    redirect: { page_id: 5, anchor: null },
  },
  { id: 5, slug: 'rascunho', status: 'draft', redirect: null },
  {
    id: 6,
    slug: 'orfa',
    status: 'redirected',
    redirect: { page_id: 99, anchor: 'x' },
  },
];

describe('cevicoPageRedirect', () => {
  it('limpa a âncora colada com # e espaços', () => {
    expect(cleanAnchor(' #juntos ')).toBe('juntos');
    expect(cleanAnchor(null)).toBe('');
  });

  it('âncora vazia vale; fora da régua não', () => {
    expect(anchorValid('')).toBe(true);
    expect(anchorValid('#como-funciona_2')).toBe(true);
    expect(anchorValid('a b')).toBe(false);
    expect(anchorValid('a/b')).toBe(false);
  });

  it('monta o caminho do destino com a âncora no fim', () => {
    expect(redirectPath(pages[1], '#juntos')).toBe(
      '/diferenca-miopia-astigmatismo-hipermetropia#juntos'
    );
    expect(redirectPath(pages[1], '')).toBe(
      '/diferenca-miopia-astigmatismo-hipermetropia'
    );
    expect(redirectPath(null, 'x')).toBe('');
  });

  it('resume para onde a página leva e se está valendo', () => {
    expect(redirectSummary(pages[1], pages)).toBeNull();
    expect(redirectSummary(pages[0], pages)).toMatchObject({
      state: 'ok',
      path: '/diferenca-miopia-astigmatismo-hipermetropia#juntos',
    });
    expect(redirectSummary(pages[2], pages).state).toBe('chain');
    expect(redirectSummary(pages[3], pages).state).toBe('off');
    expect(redirectSummary(pages[5], pages)).toMatchObject({
      state: 'missing',
      path: '',
    });
  });

  it('conta quantas páginas redirecionam para uma página', () => {
    expect(redirectedToCount(pages[1], pages)).toBe(1);
    expect(redirectedToCount(pages[4], pages)).toBe(1);
    expect(redirectedToCount(pages[5], pages)).toBe(0);
  });
});
