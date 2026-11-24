import 'package:flutter_test/flutter_test.dart';
import 'package:comboio/logic/route_weather.dart';

void main() {
  // Reta norte-sul de ~222 km (2 graus de latitude), 3 h.
  final line = [for (var i = 0; i <= 200; i++) (-22.0 - i * 0.01, -47.0)];
  final dep = DateTime.utc(2026, 11, 24, 8);

  test('pontos: saída, intermediários, destino, com horário proporcional', () {
    final pts = weatherPoints(
      line: line,
      stops: [('Saída', -22.0, -47.0), ('Destino', -24.0, -47.0)],
      durationS: 3 * 3600,
      departAt: dep,
    );
    expect(pts.first.name, 'Saída');
    expect(pts.last.name, 'Destino');
    expect(pts.length, greaterThan(2));
    expect(pts.length, lessThanOrEqualTo(10));
    expect(pts.first.at, dep);
    expect(pts.last.at.difference(dep).inMinutes, closeTo(180, 2));
    for (var i = 1; i < pts.length; i++) {
      expect(pts[i].km, greaterThan(pts[i - 1].km));
      expect(pts[i].at.isAfter(pts[i - 1].at), isTrue);
    }
  });

  test('hora mais perto da passagem e riscos', () {
    final p = WeatherPoint('X', -22, -47, DateTime.utc(2026, 11, 24, 10, 20), 50);
    final hourly = {
      'time': ['2026-11-24T09:00', '2026-11-24T10:00', '2026-11-24T11:00'],
      'weather_code': [0, 95, 3],
      'temperature_2m': [20, 22.4, 25],
      'precipitation_probability': [0, 80, 10],
      'precipitation': [0, 6.0, 0],
      'wind_speed_10m': [5, 30, 8],
      'wind_gusts_10m': [10, 70, 12],
    };
    final w = weatherAtPassage(p, hourly)!;
    expect(w.code, 95);
    expect(w.tempC, 22.4);
    expect(w.risk, isNotNull);
  });

  test('fora do período previsto: sem previsão (não inventa)', () {
    final p = WeatherPoint('X', -22, -47, DateTime.utc(2026, 12, 30), 0);
    expect(weatherAtPassage(p, {'time': ['2026-11-24T09:00']}), isNull);
    expect(weatherAtPassage(p, {}), isNull);
  });
}
