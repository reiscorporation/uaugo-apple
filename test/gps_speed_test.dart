import 'package:comboio/logic/gps_speed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parado em local coberto: não é velocidade', () {
    expect(gpsSpeedIsNoise(speed: 5.92, speedAccuracy: 5.27, accuracy: 62), isTrue);
  });
  test('andando com sinal fraco: vale', () {
    expect(gpsSpeedIsNoise(speed: 27, speedAccuracy: 2, accuracy: 50), isFalse);
  });
  test('sinal bom ou simulação: vale', () {
    expect(gpsSpeedIsNoise(speed: 3, speedAccuracy: 2, accuracy: 8), isFalse);
    expect(gpsSpeedIsNoise(speed: 3, speedAccuracy: 0, accuracy: 62), isFalse);
  });
}
