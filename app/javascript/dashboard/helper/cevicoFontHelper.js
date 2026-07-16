// CEVICO — combinações de fontes do sistema (menu do perfil → Alterar fontes).
// Serifa SÓ em títulos (regra de ouro de UX p/ sistemas de saúde); o corpo,
// inputs e chat ficam sempre sem serifa. As fontes do Google só são baixadas
// quando a combinação é escolhida (link injetado sob demanda).

const STORAGE_KEY = 'cevico_font_combo';

export const CEVICO_FONT_COMBOS = [
  {
    key: 'standard',
    label: 'Fontes Padrão (Inter)',
    description: 'A fonte atual do sistema',
    google: null,
  },
  {
    key: 'classica',
    label: 'Clássica Medicinal (Lora + Open Sans)',
    description: 'Acolhimento médico com autoridade',
    google:
      'family=Lora:wght@500;600;700&family=Open+Sans:wght@400;500;600;700',
  },
  {
    key: 'cientifica',
    label: 'Científica Moderna (Merriweather + IBM Plex Sans)',
    description: 'Precisão cirúrgica, dados sempre legíveis',
    google:
      'family=Merriweather:wght@400;700&family=IBM+Plex+Sans:wght@400;500;600;700',
  },
  {
    key: 'editorial',
    label: 'Editorial Elegante (Playfair Display + Inter)',
    description: 'Premium intelectual, títulos com charme',
    google: 'family=Playfair+Display:wght@500;600;700',
  },
];

// as duas combinações antigas (serif/mixed) migram para as novas mais próximas
const LEGACY_KEYS = { serif: 'classica', mixed: 'editorial' };

const loadGoogleFonts = combo => {
  if (!combo.google) return;
  const id = `cevico-font-${combo.key}`;
  if (document.getElementById(id)) return;
  const link = document.createElement('link');
  link.id = id;
  link.rel = 'stylesheet';
  link.href = `https://fonts.googleapis.com/css2?${combo.google}&display=swap`;
  document.head.appendChild(link);
};

export const applyCevicoFontCombo = key => {
  const combo =
    CEVICO_FONT_COMBOS.find(f => f.key === key) || CEVICO_FONT_COMBOS[0];
  localStorage.setItem(STORAGE_KEY, combo.key);
  loadGoogleFonts(combo);
  if (combo.key === 'standard') {
    delete document.documentElement.dataset.cevicoFont;
  } else {
    document.documentElement.dataset.cevicoFont = combo.key;
  }
};

export const currentCevicoFontCombo = () => {
  const stored = localStorage.getItem(STORAGE_KEY) || 'standard';
  return LEGACY_KEYS[stored] || stored;
};

// aplica a escolha salva ao abrir o sistema
export const initCevicoFontCombo = () => {
  applyCevicoFontCombo(currentCevicoFontCombo());
};
