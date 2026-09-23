// 🎨 CEVICO item 209 (23/09): A COR DE CADA UMA nas Conversas, em duas escolhas
// INDEPENDENTES que se combinam à vontade:
//   FUNDO  → pinta a conversa e a lista com um tom leitoso (ou preto de alto
//            contraste, letra branca);
//   BALÕES → o tom do balão recebido e do enviado.
// As meninas passam o dia na tela: tons suaves para se orientar sem cansar a
// vista. Cada escolha fica em ui_settings (da pessoa: segue no PC e no celular).
export const BG_THEME_KEY = 'cevico_bg_theme';
export const BUBBLE_THEME_KEY = 'cevico_bubble_theme';
export const DEFAULT_THEME = 'padrao';

// tons leitosos compartilhados: bg = fundo da conversa · list = fundo da lista
// (mais claro) · out = balão enviado (+ letra) · d* = versões do modo escuro
const TONES = {
  bondi_bebe: {
    label: 'Bondi blue bebê',
    bg: '#E2F2F6',
    list: '#EEF8FA',
    out: '#BFE4EC',
    outText: '#0B3B44',
    dOut: '#1F4D57',
    dOutText: '#E4F7FB',
  },
  azul_bebe: {
    label: 'Azul bebê',
    bg: '#E8F1FB',
    list: '#F2F7FD',
    out: '#CFE4FA',
    outText: '#12304F',
    dOut: '#264B70',
    dOutText: '#EAF3FF',
  },
  roxo_bebe: {
    label: 'Roxo bebê',
    bg: '#EDE7F8',
    list: '#F5F1FC',
    out: '#D8CBF2',
    outText: '#2F2361',
    dOut: '#3B2F6B',
    dOutText: '#F1ECFF',
  },
  rosa_soft: {
    label: 'Soft pink',
    bg: '#FAEDF2',
    list: '#FDF5F8',
    out: '#F2CFDC',
    outText: '#5A1E30',
    dOut: '#5A2D3B',
    dOutText: '#FFE9F0',
  },
  amarelo_soft: {
    label: 'Amarelo soft',
    bg: '#FBF5DF',
    list: '#FDFAEE',
    out: '#F4E6AE',
    outText: '#4A3A0A',
    dOut: '#4E4322',
    dOutText: '#FFF6D6',
  },
  verde_bebe: {
    label: 'Verde bebê',
    bg: '#E8F5EC',
    list: '#F2FAF4',
    out: '#CBEAD6',
    outText: '#0F3D2B',
    dOut: '#1F4A3A',
    dOutText: '#E6FFF3',
  },
  laranja_soft: {
    label: 'Laranja soft',
    bg: '#FBEEE3',
    list: '#FDF6EF',
    out: '#F6D5B9',
    outText: '#5A2E0A',
    dOut: '#5A3A22',
    dOutText: '#FFEBDD',
  },
  cinza_leve: {
    label: 'Cinza leve',
    bg: '#EEF0F3',
    list: '#F6F7F9',
    out: '#DFE3E9',
    outText: '#1D1D1F',
    dOut: '#2F3A46',
    dOutText: '#F5F5F7',
  },
};

// ── FUNDO ─────────────────────────────────────────────────────────────
export const BG_THEMES = [
  {
    key: 'padrao',
    label: 'Padrão',
    kind: 'default',
    swatch: '#F2F2F7',
  },
  ...Object.entries(TONES).map(([key, t]) => ({
    key,
    label: t.label,
    kind: 'milky',
    swatch: t.bg,
    light: { bg: t.bg, list: t.list },
  })),
  {
    key: 'preto',
    label: 'Preto (alto contraste)',
    kind: 'dark',
    swatch: '#0F1114',
    // vale no claro e no escuro: o ambiente inteiro fica escuro, letra branca
    force: {
      '--ch-bg': '#0F1114',
      '--ch-panel': '#1A1D22',
      '--ch-line': 'rgba(255, 255, 255, 0.09)',
      '--ch-line-strong': 'rgba(255, 255, 255, 0.16)',
      '--ch-text': '#FFFFFF',
      '--ch-muted': '#B4B4BC',
      '--ch-soft': '#22262C',
      '--ch-hover': 'rgba(255, 255, 255, 0.06)',
      '--ch-active': 'rgba(96, 165, 250, 0.18)',
      '--ch-in': '#262B31',
      '--ch-dots': 'rgba(255, 255, 255, 0.05)',
    },
  },
];

// ── BALÕES ────────────────────────────────────────────────────────────
export const BUBBLE_THEMES = [
  {
    key: 'padrao',
    label: 'Padrão',
    kind: 'default',
    swatch: { in: '#FFFFFF', out: '#2563EB' },
  },
  ...Object.entries(TONES).map(([key, t]) => ({
    key,
    label: t.label,
    kind: 'tint',
    swatch: { in: '#FFFFFF', out: t.out },
    light: { in: '#FFFFFF', inText: '#1D1D1F', out: t.out, outText: t.outText },
    dark: {
      in: '#202C33',
      inText: '#F5F5F7',
      out: t.dOut,
      outText: t.dOutText,
    },
  })),
  {
    key: 'preto',
    label: 'Preto (letra branca)',
    kind: 'tint',
    swatch: { in: '#262B31', out: '#1F2937' },
    light: {
      in: '#262B31',
      inText: '#FFFFFF',
      out: '#1F2937',
      outText: '#FFFFFF',
    },
    dark: {
      in: '#262B31',
      inText: '#FFFFFF',
      out: '#1F2937',
      outText: '#FFFFFF',
    },
  },
];

export const findBgTheme = key =>
  BG_THEMES.find(t => t.key === key) || BG_THEMES[0];
export const findBubbleTheme = key =>
  BUBBLE_THEMES.find(t => t.key === key) || BUBBLE_THEMES[0];

// classes da raiz .cv-chat
export const themeClasses = (bgKey, bubbleKey) => {
  const bg = findBgTheme(bgKey);
  const bubble = findBubbleTheme(bubbleKey);
  return {
    'cv-theme-on': bubble.kind !== 'default',
    'cv-theme-milky': bg.kind === 'milky',
    'cv-theme-dark': bg.kind === 'dark',
  };
};

// variáveis CSS lidas por _cevico-conversas.scss (claro e escuro juntas: o
// scss escolhe pelo .dark); padrão = nenhuma variável = pele de sempre
export const themeVars = (bgKey, bubbleKey) => {
  const bg = findBgTheme(bgKey);
  const bubble = findBubbleTheme(bubbleKey);
  const vars = {};
  if (bg.kind === 'dark') Object.assign(vars, bg.force);
  if (bg.kind === 'milky') {
    vars['--ch-t-bg-l'] = bg.light.bg;
    vars['--ch-t-list-l'] = bg.light.list;
  }
  if (bubble.light) {
    Object.assign(vars, {
      '--ch-t-in-l': bubble.light.in,
      '--ch-t-in-text-l': bubble.light.inText,
      '--ch-t-out-l': bubble.light.out,
      '--ch-t-out-text-l': bubble.light.outText,
      '--ch-t-in-d': bubble.dark.in,
      '--ch-t-in-text-d': bubble.dark.inText,
      '--ch-t-out-d': bubble.dark.out,
      '--ch-t-out-text-d': bubble.dark.outText,
    });
  }
  return vars;
};
