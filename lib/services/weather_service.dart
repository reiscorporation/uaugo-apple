// ============================================================================
// weather_service.dart — Previsão de chuva
//
// O que faz: Consulta o Open-Meteo para vários pontos à frente de uma vez (sem
//   chave), em 3 modelos de previsão; só avisa quando 2 concordam
//   (rainConsensus). ATENÇÃO: o Open-Meteo é grátis só para uso não
//   comercial; com o app monetizado, contratar o plano da API.
// Quem usa: MapScreen._checkRain (a cada 5 min).
// ============================================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/weather.dart';

/// Chuva agora / nos próximos 15 min em pontos à frente do piloto, pelo
/// Open-Meteo (sem chave; uma consulta para vários pontos de uma vez).
class WeatherService {
  /// Para cada ponto (lat, lng), o nível de chuva. Null se falhar.
  static Future<List<RainLevel>?> rainAt(List<(double, double)> pts) async {
    if (pts.isEmpty) return const [];
    String f(double v) => v.toStringAsFixed(3);
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': pts.map((p) => f(p.$1)).join(','),
      'longitude': pts.map((p) => f(p.$2)).join(','),
      'current': 'precipitation,weather_code',
      'minutely_15': 'precipitation',
      'forecast_minutely_15': '2',
      'models': rainModels.join(','),
      'timezone': 'auto',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      final list = j is List ? j : [j];
      return [
        for (final e in list)
          () {
            final cur = e['current'] as Map? ?? const {};
            final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
            final m15 = e['minutely_15'] as Map? ?? const {};
            // Maior chuva prevista por modelo nos próximos 15–30 min.
            final byModel = [
              for (final m in rainModels)
                ((m15['precipitation_$m'] as List?) ?? const [])
                    .whereType<num>()
                    .fold<double>(0, (a, v) => v > a ? v.toDouble() : a),
            ];
            return rainConsensus(code, byModel);
          }(),
      ];
    } catch (_) {
      return null;
    }
  }
}
