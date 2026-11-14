import 'package:flutter_test/flutter_test.dart';
import 'package:comboio/services/community_routes_service.dart';

void main() {
  test('rota do site: origem fica de fora, paradas na ordem, último = destino', () {
    final r = CommunityRoutesService.parse({
      'id': 'abc',
      'nome': 'Serra',
      'km': 190.4,
      'pontos': [
        {'nome': 'Casa', 'lat': -21.17, 'lng': -47.81, 'tipo': 'origem'},
        {'nome': 'Posto', 'lat': -21.5, 'lng': -47.5, 'tipo': 'parada'},
        {'nome': 'SJBV', 'lat': -21.97, 'lng': -46.79, 'tipo': 'destino'},
      ],
    })!;
    expect(r.name, 'Serra');
    expect(r.stops.map((s) => s.name), ['Posto']);
    expect(r.destination.name, 'SJBV');
    expect(r.km, 190.4);
  });

  test('rota compartilhada sem origem e sem nome', () {
    final r = CommunityRoutesService.parse({
      'id': 'x',
      'pontos': [
        {'nome': 'Destino', 'lat': -22.0, 'lng': -47.0, 'tipo': 'destino'},
      ],
    })!;
    expect(r.stops, isEmpty);
    expect(r.name, 'Destino');
  });

  test('sem pontos válidos = null', () {
    expect(CommunityRoutesService.parse({'id': 'y', 'pontos': []}), isNull);
    expect(
        CommunityRoutesService.parse({
          'id': 'z',
          'pontos': [
            {'nome': 'Casa', 'lat': 1, 'lng': 2, 'tipo': 'origem'}
          ]
        }),
        isNull);
  });
}
