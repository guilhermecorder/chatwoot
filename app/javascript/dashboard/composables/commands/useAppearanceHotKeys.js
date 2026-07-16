import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  ICON_APPEARANCE,
  ICON_LIGHT_MODE,
  ICON_DARK_MODE,
  ICON_SYSTEM_MODE,
} from 'dashboard/helper/commandbar/icons';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme, setBrandTheme } from 'dashboard/helper/themeHelper.js';
import {
  CEVICO_FONT_COMBOS,
  applyCevicoFontCombo,
} from 'dashboard/helper/cevicoFontHelper';

const getThemeOptions = t => [
  {
    key: 'light',
    label: t('COMMAND_BAR.COMMANDS.LIGHT_MODE'),
    icon: ICON_LIGHT_MODE,
  },
  {
    key: 'dark',
    label: t('COMMAND_BAR.COMMANDS.DARK_MODE'),
    icon: ICON_DARK_MODE,
  },
  {
    key: 'auto',
    label: t('COMMAND_BAR.COMMANDS.SYSTEM_MODE'),
    icon: ICON_SYSTEM_MODE,
  },
];

// Temas de cor CEVICO — mudam a cor de destaque (e o efeito de vidro no iOS)
const BRAND_THEME_OPTIONS = [
  { key: 'default', label: 'Tema CEVICO Azul (padrão)' },
  { key: 'gold', label: 'Tema CEVICO Dourado' },
  { key: 'ios', label: 'Tema iOS Glass (transparências)' },
];

const setAppearance = theme => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, theme);
  const isOSOnDarkMode = window.matchMedia(
    '(prefers-color-scheme: dark)'
  ).matches;
  setColorTheme(isOSOnDarkMode);
};

const setBrandAppearance = themeKey => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.BRAND_THEME, themeKey);
  setBrandTheme();
};

export function useAppearanceHotKeys() {
  const { t } = useI18n();

  const themeOptions = computed(() => getThemeOptions(t));

  const goToAppearanceHotKeys = computed(() => {
    const options = themeOptions.value.map(theme => ({
      id: theme.key,
      title: theme.label,
      parent: 'appearance_settings',
      section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
      icon: theme.icon,
      handler: () => {
        setAppearance(theme.key);
      },
    }));

    const brandOptions = BRAND_THEME_OPTIONS.map(theme => ({
      id: `brand_theme_${theme.key}`,
      title: theme.label,
      parent: 'appearance_settings',
      section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
      icon: ICON_APPEARANCE,
      handler: () => {
        setBrandAppearance(theme.key);
      },
    }));

    // CEVICO: combinações de fontes — mesmo padrão de seleção dos temas
    const fontOptions = CEVICO_FONT_COMBOS.map(combo => ({
      id: `cevico_font_${combo.key}`,
      title: combo.label,
      parent: 'font_settings',
      section: 'Fontes',
      icon: ICON_APPEARANCE,
      handler: () => {
        applyCevicoFontCombo(combo.key);
      },
    }));

    return [
      {
        id: 'appearance_settings',
        title: t('COMMAND_BAR.COMMANDS.CHANGE_APPEARANCE'),
        section: t('COMMAND_BAR.SECTIONS.APPEARANCE'),
        icon: ICON_APPEARANCE,
        children: [
          ...options.map(option => option.id),
          ...brandOptions.map(option => option.id),
        ],
      },
      ...options,
      ...brandOptions,
      {
        id: 'font_settings',
        title: 'Alterar fontes',
        section: 'Fontes',
        icon: ICON_APPEARANCE,
        children: fontOptions.map(option => option.id),
      },
      ...fontOptions,
    ];
  });

  return {
    goToAppearanceHotKeys,
  };
}
