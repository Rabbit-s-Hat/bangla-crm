import { fromStorage, fromUrl } from '@lingui/detect-locale';
import { APP_LOCALES, DEFAULT_APP_LOCALE } from 'twenty-shared/translations';
import { isDefined, isValidLocale, normalizeLocale } from 'twenty-shared/utils';
import { dynamicActivate } from '~/utils/i18n/dynamicActivate';

// Bangla-first build: ?locale= and the saved choice still win, but the browser's
// own language is no longer consulted — an unset visitor always gets Bangla.
export const initialI18nActivate = () => {
  const urlLocale = fromUrl('locale');
  const storageLocale = fromStorage('locale');

  let locale: keyof typeof APP_LOCALES = DEFAULT_APP_LOCALE;

  const normalizedUrlLocale = isDefined(urlLocale)
    ? normalizeLocale(urlLocale)
    : null;
  const normalizedStorageLocale = isDefined(storageLocale)
    ? normalizeLocale(storageLocale)
    : null;

  if (isDefined(normalizedUrlLocale) && isValidLocale(normalizedUrlLocale)) {
    locale = normalizedUrlLocale;
    try {
      localStorage.setItem('locale', normalizedUrlLocale);
    } catch (error) {
      // oxlint-disable-next-line no-console
      console.log('Failed to save locale to localStorage:', error);
    }
  } else if (
    isDefined(normalizedStorageLocale) &&
    isValidLocale(normalizedStorageLocale)
  ) {
    locale = normalizedStorageLocale;
  }

  dynamicActivate(locale);
};
