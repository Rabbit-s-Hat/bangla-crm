import { Column, Row, Section, Text } from 'react-email';
import { PRODUCT_NAME } from 'twenty-shared/translations';

// Bangla CRM: a self-contained text mark instead of an image hosted on twenty.com.
const containerStyle = {
  marginBottom: '40px',
};

const badgeStyle = {
  backgroundColor: '#0B6E4F',
  borderRadius: '10px',
  width: '40px',
  height: '40px',
  textAlign: 'center' as const,
  verticalAlign: 'middle',
};

const badgeTextStyle = {
  color: '#ffffff',
  fontSize: '22px',
  fontWeight: 700,
  lineHeight: '40px',
  margin: 0,
};

const nameStyle = {
  color: '#0B6E4F',
  fontSize: '18px',
  fontWeight: 700,
  margin: 0,
  paddingLeft: '10px',
};

export const Logo = () => {
  return (
    <Section style={containerStyle}>
      <Row>
        <Column style={badgeStyle}>
          <Text style={badgeTextStyle}>ব</Text>
        </Column>
        <Column>
          <Text style={nameStyle}>{PRODUCT_NAME}</Text>
        </Column>
      </Row>
    </Section>
  );
};
