// ============================================================================
// route_weather.dart — Clima ao longo da rota (regras puras)
//
// O que faz: Escolhe os pontos da rota onde consultar a previsão (saída,
//   paradas, trechos a cada ~N km e o destino) com o HORÁRIO previsto de
//   passagem em cada um; depois, da previsão hora a hora do Open-Meteo, pega
//   a hora da passagem e diz se há risco (chuva forte, tempestade, vento).
//   É a mesma fonte e os mesmos ícones da previsão da Comunidade do site.
// Quem usa: RouteWeatherCard (prévia da rota, roteiro da expedição).
// Testes: test/route_weather_test.dart.
// ============================================================================

import 'dart:math';

import '../l10n/i18n.dart';
import 'radars.dart' show distanceMeters;

/// Ponto da rota com o horário previsto de passagem.
class WeatherPoint {
  const WeatherPoint(this.name, this.lat, this.lng, this.at, this.km);
  final String name;
  final double lat, lng;
  final DateTime at;

  /// Distância desde a saída (km).
  final int km;
}

/// Previsão na hora da passagem.
class PointWeather {
  const PointWeather({
    required this.point,
    required this.code,
    required this.tempC,
    required this.rainProb,
    required this.rainMm,
    required this.windKmh,
    required this.gustKmh,
  });
  final WeatherPoint point;
  final int code;
  final double tempC;
  final int rainProb;
  final double rainMm;
  final double windKmh;
  final double gustKmh;

  /// Risco para quem pilota/dirige: tempestade, chuva forte provável ou
  /// rajadas fortes (acima de 50 km/h). null = sem risco.
  String? get risk {
    if (code >= 95) return tr('Tempestade');
    if (rainMm >= 4 || (rainProb >= 70 && (code == 65 || code == 67 || code == 82))) {
      return tr('Chuva forte');
    }
    if (gustKmh >= 50) return tr('Ventos fortes ({0} km/h)', [gustKmh.round()]);
    if (rainProb >= 60) return tr('Chuva provável');
    if (code == 45 || code == 48) return tr('Neblina');
    return null;
  }
}

/// Ícone e nome do tempo pelo código WMO (o mesmo da Comunidade).
(String, String) weatherIcon(int c, {bool day = true}) {
  if (c == 0) return (day ? '☀️' : '🌙', tr('Céu limpo'));
  if (c <= 2) return (day ? '🌤️' : '☁️', tr('Poucas nuvens'));
  if (c == 3) return ('☁️', tr('Nublado'));
  if (c <= 48) return ('🌫️', tr('Neblina'));
  if (c <= 57) return ('🌦️', tr('Garoa'));
  if (c <= 67) return ('🌧️', tr('Chuva'));
  if (c <= 77) return ('❄️', tr('Neve'));
  if (c <= 82) return ('🌧️', tr('Pancadas'));
  return ('⛈️', tr('Tempestade'));
}

/// Pontos para consultar: a saída, cada parada/destino e, entre eles, um a
/// cada [everyKm] (no máximo [maxPoints] no total). [line] é o traçado da
/// rota; [stops] (nome, lat, lng) em ordem; [durationS] o tempo total.
List<WeatherPoint> weatherPoints({
  required List<(double, double)> line,
  required List<(String, double, double)> stops,
  required int durationS,
  required DateTime departAt,
  double everyKm = 60,
  int maxPoints = 10,
}) {
  if (line.length < 2 || stops.isEmpty) return const [];
  // Distância acumulada no traçado.
  final acc = <double>[0];
  for (var i = 1; i < line.length; i++) {
    acc.add(acc.last +
        distanceMeters(line[i - 1].$1, line[i - 1].$2, line[i].$1, line[i].$2));
  }
  final total = acc.last;
  if (total <= 0) return const [];
  // Posição de cada parada no traçado (o ponto mais perto, em ordem).
  double alongOf(double la, double lo, double from) {
    var best = from, bestD = double.infinity;
    for (var i = 0; i < line.length; i++) {
      if (acc[i] < from) continue;
      final d = distanceMeters(la, lo, line[i].$1, line[i].$2);
      if (d < bestD) {
        bestD = d;
        best = acc[i];
      }
    }
    return best;
  }

  final marks = <(String, double)>[];
  var from = 0.0;
  for (final s in stops) {
    final a = alongOf(s.$2, s.$3, from);
    marks.add((s.$1, a));
    from = a;
  }
  // Intermediários a cada everyKm, cabendo em maxPoints.
  final room = max(0, maxPoints - marks.length);
  final step = max(everyKm * 1000, total / (room + 1));
  final mids = <(String, double)>[];
  for (var d = step; d < total - step / 3 && mids.length < room; d += step) {
    if (marks.any((m) => (m.$2 - d).abs() < step / 3)) continue;
    mids.add(('', d));
  }
  final all = [...marks, ...mids]..sort((a, b) => a.$2.compareTo(b.$2));
  (double, double) pointAt(double d) {
    for (var i = 1; i < acc.length; i++) {
      if (acc[i] >= d) {
        final seg = acc[i] - acc[i - 1];
        final t = seg <= 0 ? 0.0 : (d - acc[i - 1]) / seg;
        return (
          line[i - 1].$1 + (line[i].$1 - line[i - 1].$1) * t,
          line[i - 1].$2 + (line[i].$2 - line[i - 1].$2) * t,
        );
      }
    }
    return line.last;
  }

  return [
    for (final (name, d) in all)
      () {
        final (la, lo) = pointAt(d);
        final km = (d / 1000).round();
        return WeatherPoint(
          name.isEmpty ? tr('km {0} da rota', [km]) : name,
          la,
          lo,
          departAt.add(Duration(seconds: (durationS * d / total).round())),
          km,
        );
      }(),
  ];
}

/// Da previsão hora a hora de um ponto (listas do Open-Meteo, horário em
/// UTC "2026-11-23T14:00"), a hora mais perto da passagem. null = fora do
/// período previsto (mais de 16 dias) ou sem dados.
PointWeather? weatherAtPassage(WeatherPoint p, Map<String, dynamic> hourly) {
  final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
  if (times.isEmpty) return null;
  final target = p.at.toUtc();
  var best = -1;
  var bestDiff = const Duration(days: 999);
  for (var i = 0; i < times.length; i++) {
    final t = DateTime.tryParse('${times[i]}Z');
    if (t == null) continue;
    final diff = t.difference(target).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = i;
    }
  }
  if (best < 0 || bestDiff > const Duration(minutes: 90)) return null;
  num v(String k) {
    final l = hourly[k] as List?;
    if (l == null || best >= l.length) return 0;
    return (l[best] as num?) ?? 0;
  }

  return PointWeather(
    point: p,
    code: v('weather_code').toInt(),
    tempC: v('temperature_2m').toDouble(),
    rainProb: v('precipitation_probability').toInt(),
    rainMm: v('precipitation').toDouble(),
    windKmh: v('wind_speed_10m').toDouble(),
    gustKmh: v('wind_gusts_10m').toDouble(),
  );
}
