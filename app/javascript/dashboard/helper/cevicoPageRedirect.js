// ↪ item 395: redirecionamento permanente (301) por página — contas da tela
// Páginas. A página redirecionada chega da API com `redirect: { page_id,
// anchor }`; o destino é procurado na própria lista de páginas da conta.

// mesma régua do servidor (CevicoPageRedirect::REDIRECT_ANCHOR)
const ANCHOR_RULE = /^[A-Za-z0-9_-]{1,80}$/;

// "#juntos " → "juntos" (a pessoa pode colar com ou sem o #)
export const cleanAnchor = raw =>
  String(raw || '')
    .trim()
    .replace(/^#/, '');

// vazia vale (âncora é opcional)
export const anchorValid = raw => {
  const anchor = cleanAnchor(raw);
  return anchor === '' || ANCHOR_RULE.test(anchor);
};

// "/destino#ancora" a partir da página de destino e da âncora digitada
export const redirectPath = (target, anchor) => {
  if (!target) return '';
  const clean = cleanAnchor(anchor);
  return `/${target.slug}${clean ? `#${clean}` : ''}`;
};

// Para onde a página redirecionada leva e se isso está valendo:
//   ok      → destino no ar: o endereço responde 301
//   chain   → o destino também foi redirecionado (o sistema segue um nível)
//   off     → destino fora do ar: o endereço responde "não encontrada"
//   missing → destino apagado: idem
// Página sem redirecionamento devolve null.
export const redirectSummary = (page, pages) => {
  if (!page?.redirect) return null;
  const target = (pages || []).find(p => p.id === page.redirect.page_id);
  if (!target) return { state: 'missing', path: '', target: null };
  let state = 'off';
  if (target.status === 'published') state = 'ok';
  else if (target.status === 'redirected') state = 'chain';
  return { state, path: redirectPath(target, page.redirect.anchor), target };
};

// quantas páginas mandam o visitante para esta (aviso antes de excluir)
export const redirectedToCount = (page, pages) =>
  (pages || []).filter(p => p.redirect?.page_id === page?.id).length;
