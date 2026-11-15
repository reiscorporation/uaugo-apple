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

  group('atrações sem repetidas, da mais perto para a mais longe', () {
    Atracao at(String nome, double lat, double lng, double dist,
            {String? q, String? w, String? foto}) =>
        Atracao(lat, lng, 'attraction', nome, wikidata: q, wiki: w, foto: foto)..distM = dist;

    test('mesmo Wikidata longe (ponto e área): fica uma, a mais completa', () {
      final l = semRepetidas([
        at('Parque Estadual X', -21.13, -47.80, 4000, q: 'Q1', w: 'pt:Parque X', foto: 'f.jpg'),
        at('Outro Parque', -21.30, -47.80, 2000, q: 'Q1'),
      ]);
      expect(l.length, 1);
      expect(l.single.foto, 'f.jpg');
    });

    test('acento, caixa e "do/da" não fazem lugares diferentes', () {
      final l = semRepetidas([
        at('Cachoeira do Itambé', -21.0000, -47.0000, 100),
        at('CACHOEIRA ITAMBE', -21.0050, -47.0000, 650),
        at('Itambé', -21.0010, -47.0000, 210),
      ]);
      expect(l.length, 1);
    });

    test('nome contido com 1 palavra só vale bem perto', () {
      final l = semRepetidas([
        at('Museu do Café', -21.0000, -47.0000, 100),
        at('Café', -21.0080, -47.0000, 1000),
      ]);
      expect(l.length, 2);
    });

    test('mesmo nome em cidades diferentes são lugares diferentes', () {
      final l = semRepetidas([
        at('Mirante', -21.00, -47.00, 3000),
        at('Mirante', -21.30, -47.00, 30000),
      ]);
      expect(l.length, 2);
    });

    test('Wikidata diferentes com nome igual perto: os dois ficam', () {
      final l = semRepetidas([
        at('Igreja Matriz', -21.0000, -47.0000, 100, q: 'Q1'),
        at('Igreja Matriz', -21.0020, -47.0000, 300, q: 'Q2'),
      ]);
      expect(l.length, 2);
    });

    test('ordem: da mais perto para a mais longe, famosa ou não', () {
      final l = semRepetidas([
        at('Famoso', -21.20, -47.00, 20000, q: 'Q9', w: 'pt:Famoso', foto: 'x'),
        at('Perto', -21.00, -47.00, 500),
        at('Meio', -21.10, -47.00, 9000),
      ]);
      expect(l.map((a) => a.nome), ['Perto', 'Meio', 'Famoso']);
    });
  });

  test('busca de hotéis leva a cidade e a noite', () {
    final u = googleHoteisUri('Cravinhos, SP', DateTime(2026, 11, 20));
    expect(u.queryParameters['q'], 'hotéis em Cravinhos, SP 20/11 a 21/11');
  });

  test('turismo: ordenar por mais perto ou mais conhecidas', () {
    final perto = Atracao(0, 0, 'attraction', 'Praça')..distM = 500;
    final famosa = Atracao(0, 0, 'attraction', 'Theatro', wiki: 'pt:Theatro', foto: 'x.jpg')..distM = 9000;
    final media = Atracao(0, 0, 'attraction', 'Mirante', wikidata: 'Q1')..distM = 2000;
    final l = [famosa, perto, media];
    expect(ordenaAtracoes(l, conhecidas: false).map((a) => a.nome), ['Praça', 'Mirante', 'Theatro']);
    expect(ordenaAtracoes(l, conhecidas: true).map((a) => a.nome), ['Theatro', 'Mirante', 'Praça']);
  });
}
