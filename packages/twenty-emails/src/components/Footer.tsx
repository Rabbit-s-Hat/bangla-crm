import { type I18n } from '@lingui/core';
import { Column, Container, Row } from 'react-email';
import { PRODUCT_NAME } from 'twenty-shared/translations';
import { Link } from 'src/components/Link';
import { ShadowText } from 'src/components/ShadowText';

// Bangla CRM: the footer names this product, links to its source code (AGPL section 13)
// and says truthfully that it is built on Twenty.
const SOURCE_CODE_URL = 'https://github.com/Rabbit-s-Hat/bangla-crm';
const TWENTY_URL = 'https://twenty.com/';

const footerContainerStyle = {
  marginTop: '12px',
};

type FooterProps = {
  i18n: I18n;
};

export const Footer = ({ i18n }: FooterProps) => {
  return (
    <Container style={footerContainerStyle}>
      <Row>
        <Column>
          <ShadowText>
            <Link
              href={SOURCE_CODE_URL}
              value={i18n._('Source code')}
              aria-label={i18n._('View the source code of {PRODUCT_NAME}', {
                PRODUCT_NAME,
              })}
            />
          </ShadowText>
        </Column>
        <Column>
          <ShadowText>
            <Link
              href={TWENTY_URL}
              value={i18n._('Built on Twenty')}
              aria-label={i18n._('Visit the website of Twenty, the open-source CRM this product is built on')}
            />
          </ShadowText>
        </Column>
      </Row>
      <ShadowText>
        <>
          {PRODUCT_NAME}
          <br />
          {i18n._('Free and open-source software (AGPL-3.0)')}
        </>
      </ShadowText>
    </Container>
  );
};
