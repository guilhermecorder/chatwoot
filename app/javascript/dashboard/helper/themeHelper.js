import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

// Temas de cor CEVICO: classe extra no <body>, persistida no localStorage
export const BRAND_THEMES = ['default', 'gold', 'ios'];

export const setBrandTheme = () => {
  const selected =
    LocalStorage.get(LOCAL_STORAGE_KEYS.BRAND_THEME) || 'default';
  document.body.classList.remove('theme-gold', 'theme-ios');
  if (selected !== 'default' && BRAND_THEMES.includes(selected)) {
    document.body.classList.add(`theme-${selected}`);
  }
};

export const setColorTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
  if (
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    selectedColorScheme === 'dark'
  ) {
    document.body.classList.add('dark');
    document.documentElement.style.setProperty('color-scheme', 'dark');
  } else {
    document.body.classList.remove('dark');
    document.documentElement.style.setProperty('color-scheme', 'light');
  }
  setBrandTheme();
};
