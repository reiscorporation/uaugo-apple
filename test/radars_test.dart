import 'package:comboio/logic/geo.dart';
import 'package:comboio/logic/radars.dart';
import 'package:comboio/logic/simulation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  group('radarOnRouteRoad', () {
    final road = [(0.0, 0.0), (0.0, 0.1), (0.0, 0.2), (0.0, 0.3), (0.0, 0.4)];
    test('via da rota: avisa', () {
      expect(radarOnRouteRoad([road], (_, __) => 5), isTrue);
    });
    test('rotatória acima ou pista lateral: não avisa', () {
      // Só o ponto do cruzamento fica perto da rota.
      expect(radarOnRouteRoad([road], (_, lng) => lng == 0.2 ? 3 : 80), isFalse);
      expect(radarOnRouteRoad([road], (_, __) => 28), isFalse);
    });
    test('sobre duas vias: basta a rota seguir uma', () {
      final off = [(1.0, 0.0), (1.0, 0.1), (1.0, 0.2)];
      expect(radarOnRouteRoad([road, off], (lat, _) => lat == 1 ? 4 : 80), isTrue);
    });
    test('sem dados da via: avisa', () {
      expect(radarOnRouteRoad(const [], (_, __) => 80), isTrue);
      expect(radarOnRouteRoad([road.sublist(0, 2)], (_, __) => 80), isTrue);
    });
  });

  // BR-101 em SC, sentido sul: de -28.270 para -28.290 (mesma longitude).
  final line = encodePolyline(const [
    LatLng(-28.270, -48.700),
    LatLng(-28.280, -48.700),
    LatLng(-28.290, -48.700),
  ]);
  final idx = RadarIndex.fromJson({
    'attribution': 'teste',
    'radars': [
      [-28.2800, -48.7000, 0, 80, -1], // fixo, os dois sentidos
      [-28.2850, -48.7000, 0, 60, 180], // fixo, só sentido sul
      [-28.2820, -48.7000, 2, 0, -1], // avanço de sinal
      [-23.5500, -46.6300, 1, 50, -1], // São Paulo, longe
    ],
    'prf': {
      'label': 'Lista válida a partir de 03/10/2026',
      'stretches': [
        ['SC', '101', 290, 300, line],
      ],
    },
  });

  test('lê o arquivo e indexa por região', () {
    expect(idx.radarCount, 4);
    expect(idx.stretchCount, 1);
    final near = idx.radarsAround(-28.27, -48.70);
    expect(near.map((r) => r.id), containsAll([0, 1, 2]));
    expect(near.map((r) => r.id), isNot(contains(3)));
    expect(idx.stretchesAround(-28.27, -48.70), hasLength(1));
    expect(idx.stretchesAround(-23.55, -46.63), isEmpty);
  });

  group('quando avisar', () {
    final fixed = idx.radarsAround(-28.27, -48.70).firstWhere((r) => r.id == 0);
    final southOnly =
        idx.radarsAround(-28.27, -48.70).firstWhere((r) => r.id == 1);
    final redLight =
        idx.radarsAround(-28.27, -48.70).firstWhere((r) => r.id == 2);

    test('radar à frente a menos de 1 km avisa', () {
      // ~890 m ao norte do radar, indo para o sul (180°) a 25 m/s.
      expect(
          shouldAlertRadar(fixed,
              lat: -28.272, lng: -48.700, heading: 180, speed: 25),
          isTrue);
    });

    test('radar a mais de 1 km ainda não avisa', () {
      expect(
          shouldAlertRadar(fixed,
              lat: -28.268, lng: -48.700, heading: 180, speed: 25),
          isFalse);
    });

    test('radar que já ficou para trás não avisa', () {
      expect(
          shouldAlertRadar(fixed,
              lat: -28.285, lng: -48.700, heading: 180, speed: 25),
          isFalse);
    });

    test('radar do sentido contrário não avisa', () {
      // Indo para o norte (0°), com o radar à frente mas valendo só para o sul.
      expect(
          shouldAlertRadar(southOnly,
              lat: -28.293, lng: -48.700, heading: 0, speed: 25),
          isFalse);
      expect(
          shouldAlertRadar(southOnly,
              lat: -28.278, lng: -48.700, heading: 180, speed: 25),
          isTrue);
    });

    test('avanço de sinal só avisa a 300 m', () {
      expect(redLight.alertMeters, 300);
      expect(
          shouldAlertRadar(redLight,
              lat: -28.276, lng: -48.700, heading: 180, speed: 15),
          isFalse);
      expect(
          shouldAlertRadar(redLight,
              lat: -28.2795, lng: -48.700, heading: 180, speed: 15),
          isTrue);
    });
  });

  group('pista e direção certas', () {
    const ours = FixedRadar(10, -28.2800, -48.70010, RadarKind.fixed, 110, -1);
    // Pista contrária (rodovia duplicada): 30 m a leste.
    const other = FixedRadar(11, -28.2800, -48.69980, RadarKind.fixed, 110, -1);
    // Rua paralela: 300 m a leste.
    const parallel =
        FixedRadar(12, -28.2800, -48.69700, RadarKind.fixed, 60, -1);

    test('parado não avisa (não dá para saber o sentido)', () {
      expect(
          shouldAlertRadar(ours,
              lat: -28.272, lng: -48.7001, heading: 180, speed: 0),
          isFalse);
    });

    test('rua paralela não avisa', () {
      expect(
          shouldAlertRadar(parallel,
              lat: -28.272, lng: -48.7001, heading: 180, speed: 25),
          isFalse);
    });

    test('par de radares lado a lado: só o da direita (pista do piloto)', () {
      // Indo para o sul, a direita é o oeste: "ours" (mais a oeste).
      const both = [ours, other];
      expect(
          shouldAlertRadar(ours,
              lat: -28.272,
              lng: -48.7001,
              heading: 180,
              speed: 25,
              neighbors: both),
          isTrue);
      expect(
          shouldAlertRadar(other,
              lat: -28.272,
              lng: -48.7001,
              heading: 180,
              speed: 25,
              neighbors: both),
          isFalse);
    });

    test('com rota: radar da outra pista (fora da rota) não avisa', () {
      // Rota pela pista oeste, indo para o sul.
      final route = RouteWalker(const [
        (-28.2600, -48.70010),
        (-28.2900, -48.70010),
      ]);
      final rider = route.project(-28.2720, -48.70010);
      expect(
          radarAheadOnRoute(ours,
              project: route.project, riderAlong: rider.along),
          closeTo(890, 10));
      expect(
          radarAheadOnRoute(other,
              project: route.project, riderAlong: rider.along),
          isNull);
      // Já passou do radar: não avisa mais.
      final past = route.project(-28.2850, -48.70010);
      expect(
          radarAheadOnRoute(ours,
              project: route.project, riderAlong: past.along),
          isNull);
    });
  });

  test('distância até o trecho da PRF', () {
    final s = idx.stretchesAround(-28.27, -48.70).first;
    final before = nearestOnLine(-28.262, -48.700, s.points);
    expect(before.meters, closeTo(890, 30));
    final inside = nearestOnLine(-28.280, -48.7001, s.points);
    expect(inside.meters, lessThan(20));
  });

  test('frases dos radares', () {
    final r = idx.radarsAround(-28.27, -48.70);
    expect(radarSpeech(r.firstWhere((x) => x.id == 0), 1000),
        'Radar a 1 quilômetro, velocidade 80');
    // Sem limite na base: usa o limite da via no local; sem nenhum, avisa.
    final semLimite = r.firstWhere((x) => x.id == 2);
    expect(radarSpeech(semLimite, 300, roadLimit: 60),
        'Radar de avanço de sinal a 300 metros, velocidade 60');
    expect(radarSpeech(semLimite, 300),
        'Radar de avanço de sinal a 300 metros, velocidade não informada');
    final s = idx.stretchesAround(-28.27, -48.70).first;
    // Frase clara (antes: "do quilômetro 90 ao quilômetro 30", confusa).
    expect(prfStretchSpeech(s, 1000),
        startsWith('Atenção: em 1 quilômetro começa trecho com radar móvel da polícia rodoviária na B R 101'));
    expect(prfStretchSpeech(s, 1000), isNot(contains('até o quilômetro')));
    expect(prfStretchSpeech(s, 20),
        startsWith('Atenção: pode haver radar móvel da polícia rodoviária na B R 101'));
  });
}
