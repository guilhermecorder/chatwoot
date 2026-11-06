// 🏷️ 06/11: o favicon de cada marca mora na pasta dela (/brand-assets/otica,
// /brand-assets/life…). Antes a troca voltava para a raiz e a aba mostrava o
// ícone da CEVICO depois da primeira notificação. Agora a pasta vem do href
// que o servidor escreveu (sem pasta de marca continua sendo a raiz).
const faviconDir = favicon => {
  const href = favicon.getAttribute('href') || '';
  const cut = href.lastIndexOf('/');
  return cut > 0 ? href.slice(0, cut) : '';
};

export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = `${faviconDir(favicon)}/favicon-badge-${favicon.sizes[[0]]}.png`;
    favicon.href = newFileName;
  });
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        const oldFileName = `${faviconDir(favicon)}/favicon-${favicon.sizes[[0]]}.png`;
        favicon.href = oldFileName;
      });
    }
  });
};
