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
