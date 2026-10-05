import 'package:comboio/logic/geo.dart';
import 'package:comboio/logic/itinerary.dart';
import 'package:comboio/models/expedition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Stop _s(String id, StopType type,
        {int legKm = 0, int legMin = 0, int stay = 0, String next = '08:00'}) =>
    Stop(
      id: id,
      name: id,
      lat: -28.0 - id.codeUnitAt(0) / 100,
      lng: -49.0,
      order: 0,
      createdBy: 'u',
      type: type,
      stayMin: stay,
      nextDayStart: next,
      legDistanceM: legKm * 1000,
      legDurationS: legMin * 60,
    );

void main() {
  group('cronograma', () {
    test('um dia: soma trechos e tempo parado', () {
      final s = buildSchedule(
        const TripPlan(startDate: '2026-10-10', startTime: '08:00'),
        [
          _s('A', StopType.meet),
          _s('B', StopType.fuel, legKm: 80, legMin: 60, stay: 30),
          _s('C', StopType.destination, legKm: 150, legMin: 120),
        ],
      );
      expect(s.days, hasLength(1));
      expect(s.hasDate, isTrue);
      expect(formatTime(s.stops[0].departure), '08:00');
      expect(formatTime(s.stops[1].arrival!), '09:00');
      expect(formatTime(s.stops[1].departure), '09:30');
      expect(formatTime(s.stops[2].arrival!), '11:30');
      expect(s.totalDistanceM, 230000);
      expect(s.totalRideS, 180 * 60);
    });

    test('pernoite encerra o dia e o seguinte começa na hora definida', () {
      final s = buildSchedule(
        const TripPlan(startDate: '2026-10-10', startTime: '07:00'),
        [
          _s('A', StopType.meet),
          _s('B', StopType.overnight, legKm: 300, legMin: 300, next: '07:30'),
          _s('C', StopType.food, legKm: 100, legMin: 90, stay: 60),
          _s('D', StopType.destination, legKm: 50, legMin: 40),
        ],
      );
      expect(s.days, hasLength(2));
      expect(s.stops[1].day, 1); // o pernoite pertence ao dia em que chega
      expect(s.stops[2].day, 2);
      expect(s.days[0].distanceM, 300000);
      expect(s.days[1].distanceM, 150000);
      expect(s.days[1].date, DateTime(2026, 10, 11));
      expect(formatTime(s.stops[1].departure), '07:30');
      expect(s.stops[1].departure.day, 11);
      expect(formatTime(s.stops[2].arrival!), '09:00');
      expect(formatTime(s.stops[3].arrival!), '10:40');
    });

    test('sem data definida ainda calcula os horários', () {
      final s = buildSchedule(const TripPlan(),
          [_s('A', StopType.meet), _s('B', StopType.destination, legMin: 30)]);
      expect(s.hasDate, isFalse);
      expect(formatTime(s.stops[1].arrival!), '08:30');
    });

    test('roteiro vazio', () {
      final s = buildSchedule(const TripPlan(), []);
      expect(s.stops, isEmpty);
      expect(s.days, isEmpty);
    });
  });

  group('inserção de pontos', () {
    test('primeiro é encontro, segundo é destino, depois paradas', () {
      expect(defaultTypeFor([]), StopType.meet);
      expect(defaultTypeFor([_s('A', StopType.meet)]), StopType.destination);
      expect(
          defaultTypeFor(
              [_s('A', StopType.meet), _s('B', StopType.destination)]),
          StopType.waypoint);
    });

    test('ponto novo entra antes do destino', () {
      final stops = [_s('A', StopType.meet), _s('B', StopType.destination)];
      expect(insertIndexFor(stops), 1);
      expect(insertIndexFor([_s('A', StopType.meet)]), 1);
      expect(
          insertIndexFor([_s('A', StopType.meet), _s('B', StopType.fuel)]), 2);
    });
  });

  group('exportação', () {
    final schedule = buildSchedule(
      const TripPlan(startDate: '2026-10-10', startTime: '07:00'),
      [
        _s('A', StopType.meet),
        _s('B', StopType.overnight, legKm: 300, legMin: 300),
        _s('C', StopType.destination, legKm: 100, legMin: 90),
      ],
    );

    test('um link do Google Maps por dia', () {
      final links = googleMapsLinks(schedule);
      expect(links, hasLength(2));
      expect(links.first, startsWith('https://www.google.com/maps/dir/?api=1'));
      expect(links.first, contains('travelmode=driving'));
    });

    test('dia com muitas paradas é dividido em vários links', () {
      final many = [
        _s('A', StopType.meet),
        for (var i = 0; i < 12; i++)
          _s(String.fromCharCode(66 + i), StopType.waypoint, legMin: 10),
        _s('Z', StopType.destination, legMin: 10),
      ];
      final links = googleMapsLinks(buildSchedule(const TripPlan(), many));
      expect(links, hasLength(2));
    });

    test('mensagem tem os dias, horários e o código', () {
      final text = buildShareText(
          expeditionName: 'Serra', code: 'ABC123', schedule: schedule);
      expect(text, contains('*Serra*'));
      expect(text, contains('Dia 1'));
      expect(text, contains('Dia 2'));
      expect(text, contains('saída 07:00'));
      expect(text, contains('ABC123'));
      expect(text, contains('400 km'));
    });
  });

  group('formatação', () {
    test('distância', () {
      expect(formatDistance(850), '850 m');
      expect(formatDistance(12300), '12,3 km');
      expect(formatDistance(245400), '245 km');
    });
    test('duração', () {
      expect(formatDuration(45 * 60), '45 min');
      expect(formatDuration(120 * 60), '2h');
      expect(formatDuration(195 * 60), '3h15');
    });
    test('hora inválida vira 08:00', () {
      expect(parseHm('25:00'), (8, 0));
      expect(parseHm('7:05'), (7, 5));
    });
  });

  test('codificar e decodificar a rota dá os mesmos pontos', () {
    const pts = [
      LatLng(-28.39123, -49.55456),
      LatLng(-28.40001, -49.5),
      LatLng(-27.0, -48.12345),
    ];
    final back = decodePolyline(encodePolyline(pts));
    expect(back, hasLength(3));
    for (var i = 0; i < pts.length; i++) {
      expect(back[i].latitude, closeTo(pts[i].latitude, 1e-5));
      expect(back[i].longitude, closeTo(pts[i].longitude, 1e-5));
    }
  });
}
