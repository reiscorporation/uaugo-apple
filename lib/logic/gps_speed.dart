// ============================================================================
// gps_speed.dart — Velocidade do GPS que não dá para acreditar
//
// O que faz: Parado em local coberto, o GPS erra a posição em dezenas de metros
//   e inventa velocidade (ex.: 21 km/h com erro de 19 km/h). Separa isso da
//   velocidade real: sinal ruim e valor pouco maior que o próprio erro.
// Quem usa: MapScreen (velocímetro, inclusive na tela do carro).
// ============================================================================

bool gpsSpeedIsNoise({
  required double speed, // m/s
  required double speedAccuracy, // m/s (0 = o aparelho não informa)
  required double accuracy, // m
}) =>
    accuracy > 25 && speedAccuracy > 0 && speed < speedAccuracy * 2.5;

/// Filtra a posição com sinal ruim. Em local coberto o GPS passeia por
/// quilômetros (vimos 130 km/h com o celular parado), sem que dê para separar
/// isso pela velocidade. Por isso sinal ruim só vale logo depois de um sinal
/// bom (túnel, viaduto); sem nenhum sinal bom por 2 min, volta a valer, para
/// o mapa não ficar parado em quem só tem GPS fraco.
class GpsGate {
  static const goodMeters = 25.0;
  static const keepAfterGood = Duration(seconds: 20);
  static const giveUpAfter = Duration(minutes: 2);

  DateTime? _lastGood;
  DateTime? _badSince;

  bool accept(double accuracy, DateTime now) {
    if (accuracy <= goodMeters) {
      _lastGood = now;
      _badSince = null;
      return true;
    }
    final good = _lastGood;
    if (good != null && now.difference(good) < keepAfterGood) return true;
    final since = _badSince ??= now;
    return now.difference(since) >= giveUpAfter;
  }
}
