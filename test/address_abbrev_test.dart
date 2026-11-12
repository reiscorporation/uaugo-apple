import 'package:comboio/logic/address_abbrev.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('troca abreviações comuns de endereço', () {
    expect(expandAddressAbbrev('av. aparecido savegnago'),
        'Avenida aparecido savegnago');
    expect(expandAddressAbbrev('Av Presidente Vargas'), 'Avenida Presidente Vargas');
    expect(expandAddressAbbrev('r. sete de setembro 100'), 'Rua sete de setembro 100');
    expect(expandAddressAbbrev('rod anhanguera km 300'), 'Rodovia anhanguera km 300');
    expect(expandAddressAbbrev('av. pres. kennedy'), 'Avenida Presidente kennedy');
    expect(expandAddressAbbrev('jd. paulista'), 'Jardim paulista');
    expect(expandAddressAbbrev('pça da sé'), 'Praça da sé');
    expect(expandAddressAbbrev('Av. Dr. Celso Charuri'), 'Avenida Doutor Celso Charuri');
  });

  test('não mexe no que não é abreviação', () {
    expect(expandAddressAbbrev('posto ipiranga'), 'posto ipiranga');
    expect(expandAddressAbbrev('Shopping Iguatemi'), 'Shopping Iguatemi');
    expect(expandAddressAbbrev('rua com nome'), 'rua com nome');
    expect(expandAddressAbbrev('bloco d'), 'bloco d');
    expect(expandAddressAbbrev('Avenida Brasil'), 'Avenida Brasil');
  });
}
