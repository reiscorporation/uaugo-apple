import 'dart:io';

import 'package:comboio/logic/na_rota.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hotéis do Google: nome, posição, preço e estrelas', () {
    final html = File('test/fixtures/google_hoteis.txt').readAsStringSync();
    final h = parseHoteisGoogle(html);
    expect(h.length, greaterThanOrEqualTo(10));
    expect(h.where((x) => x.preco != null).length, greaterThanOrEqualTo(8));
    for (final x in h) {
      expect(x.lat, inInclusiveRange(-22.0, -20.5));
      expect(x.lng, inInclusiveRange(-48.5, -47.0));
      expect(x.nome, isNotEmpty);
      if (x.preco != null) expect(x.preco, inInclusiveRange(40, 5000));
      if (x.nota != null) expect(x.nota, inInclusiveRange(1.0, 5.0));
    }
    expect(h.any((x) => x.estrelas?.contains('estrela') ?? false), isTrue);
  });

  test('formato desconhecido: lista vazia, sem erro', () {
    expect(parseHoteisGoogle('<html>captcha</html>'), isEmpty);
  });

  test('preço da ANP casa com o posto do mapa pela rua e cidade', () {
    final anp = [
      PrecoAnp('POSTO GRAAL TROPICAL', 'RODOVIA ANHANGUERA', 'KM 296', 'ZONA RURAL', 'CRAVINHOS', 'PETROBRAS',
          {'g': 6.29}, '2026-10-30'),
      PrecoAnp('AUTO POSTO CENTRAL', 'RUA DUQUE DE CAXIAS', '100', 'CENTRO', 'CRAVINHOS', 'SHELL', {'g': 6.09}, ''),
      PrecoAnp('AUTO POSTO CENTRAL', 'RUA DUQUE DE CAXIAS', '100', 'CENTRO', 'SERRANA', 'SHELL', {'g': 5.99}, ''),
    ];
    final graal = PostoRota(-21.3, -47.7, 'Graal', 'Graal Tropical');
    expect(casaPreco(graal, 'Cravinhos', anp)?.gasolina, 6.29);
    final rua = PostoRota(-21.3, -47.7, '', 'Shell', rua: 'Rua Duque de Caxias', numero: '100', cidade: 'Cravinhos');
    expect(casaPreco(rua, null, anp)?.gasolina, 6.09);
    // Sem cidade conhecida não arrisca.
    expect(casaPreco(graal, null, anp), isNull);
    // Nada parecido: sem preço.
    expect(casaPreco(PostoRota(0, 0, '', 'Ipiranga', rua: 'Av. Brasil'), 'Cravinhos', anp), isNull);
  });

  test('atração: tipo, emoji e fama', () {
    final a = Atracao.fromList([-2117057, -4784955, 'museum', 'Museu do Café', {'w': 'pt:Museu do Café', 'q': 'Q1'}]);
    expect(a.lat, closeTo(-21.17057, 1e-6));
    expect(a.tipoNome, 'Museu');
    expect(a.fama, 3);
  });

  test('busca de hotéis leva a cidade e a noite', () {
    final u = googleHoteisUri('Cravinhos, SP', DateTime(2026, 11, 20));
    expect(u.queryParameters['q'], 'hotéis em Cravinhos, SP 20/11 a 21/11');
  });
}
