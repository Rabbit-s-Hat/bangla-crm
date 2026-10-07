import { Font, Head } from 'react-email';
import { PRODUCT_NAME } from 'twenty-shared/translations';

import { canvasTheme } from 'src/common-style';

export const BaseHead = () => {
  return (
    <Head>
      <title>{`${PRODUCT_NAME} email`}</title>
      <Font
        fontFamily={canvasTheme.font.family}
        fallbackFontFamily="sans-serif"
        fontStyle="normal"
        fontWeight={canvasTheme.font.weight.regular}
      />
    </Head>
  );
};
