import 'package:flutter_test/flutter_test.dart';
import 'package:comboio/logic/navigation.dart';
import 'package:comboio/logic/speech.dart';

void main() {
  group('spokenText: placas e abreviações por extenso', () {
    test('cidades abreviadas nas placas', () {
      expect(spokenText('Pegue a saída em direção a Rib. Preto'),
          'Pegue a saída em direção a Ribeirão Preto');
      expect(spokenText('Mantenha-se à direita, siga as placas para S. J. do Rio Preto/Rib. Preto'),
          'Mantenha-se à direita, siga as placas para São José do Rio Preto/Ribeirão Preto');
      expect(spokenText('em direção a S. Carlos'), 'em direção a São Carlos');
      expect(spokenText('em direção a S.J. dos Campos.'), 'em direção a São José dos Campos.');
      expect(spokenText('Rod. Pres. Castelo Branco'), 'Rodovia Presidente Castelo Branco');
    });
    test('endereços e romanos', () {
      expect(spokenText('Vire à direita na Av. Leão XIII'), 'Vire à direita na Avenida Leão Treze');
      expect(spokenText('Siga pela Av. D. Pedro II'), 'Siga pela Avenida Dom Pedro Segundo');
      expect(spokenText('Entre na R. Jd. das Flores'), 'Entre na Rua Jardim das Flores');
      expect(spokenText('Vire na Av. N. Sra. de Fátima'), 'Vire na Avenida Nossa Senhora de Fátima');
    });
    test('aplicar duas vezes não estraga', () {
      const t = 'Pegue a SP-330 em direção a Rib. Preto';
      expect(spokenText(spokenText(t)), spokenText(t));
      expect(spokenText(t), 'Pegue a SP 330 em direção a Ribeirão Preto');
    });
  });

  group('spokenPlace: só o que ajuda a reconhecer o lugar', () {
    test('endereço completo vira rua e número', () {
      expect(spokenPlace('Av. Leão XIII, 3900 - Jardim Sumaré, Ribeirão Preto - SP, 14025-000, Brasil'),
          'Av. Leão XIII, 3900');
      expect(spokenText(spokenPlace('Av. Leão XIII, 3900 - Jardim Sumaré, Ribeirão Preto - SP')),
          'Avenida Leão Treze, 3900');
    });
    test('lugar com nome', () {
      expect(spokenPlace('Posto Graal - Rod. Anhanguera, km 120'), 'Posto Graal');
      expect(spokenPlace('Ribeirão Preto, SP'), 'Ribeirão Preto');
      expect(spokenPlace('Ribeirão Preto - SP, Brasil'), 'Ribeirão Preto');
      expect(spokenPlace('Casa'), 'Casa');
    });
    test('rua sem número', () {
      expect(spokenPlace('R. Amapá - Vila Seixas, Ribeirão Preto - SP'), 'R. Amapá');
      expect(spokenPlace('Rua Amapá, s/n - Centro'), 'Rua Amapá, s/n');
    });
  });
}
