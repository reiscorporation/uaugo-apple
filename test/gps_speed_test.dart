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

  group('GpsGate', () {
    final t0 = DateTime(2026, 11, 1);
    test('sinal bom passa; ruim logo depois (túnel) também', () {
      final g = GpsGate();
      expect(g.accept(8, t0), isTrue);
      expect(g.accept(60, t0.add(const Duration(seconds: 10))), isTrue);
    });
    test('parado em local coberto: ruim não passa', () {
      final g = GpsGate();
      expect(g.accept(62, t0), isFalse);
      expect(g.accept(46, t0.add(const Duration(minutes: 1))), isFalse);
      final h = GpsGate()..accept(8, t0);
      expect(h.accept(62, t0.add(const Duration(seconds: 30))), isFalse);
    });
    test('só GPS fraco por 2 min: volta a valer', () {
      final g = GpsGate()..accept(40, t0);
      expect(g.accept(40, t0.add(const Duration(minutes: 2))), isTrue);
    });
  });
}
