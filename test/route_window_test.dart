import 'dart:math';

import 'package:comboio/logic/route_window.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rota longa (300 km) cheia de curvas, um ponto a cada 2 m: o carro recebe
/// o trecho perto do veículo com todos os detalhes e o total dentro do limite.
void main() {
  const lat0 = -21.0, lng0 = -47.8;
  final kx = 111320 * cos(lat0 * pi / 180), ky = 110540.0;
  // Avança para o norte em zigue-zague suave (curvas de raio ~150 m).
  final pts = <(double, double)>[];
  for (var i = 0; i <= 150000; i++) {
    final y = i * 2.0;
    final x = 40 * sin(y / 150);
    pts.add((lat0 + y / ky, lng0 + x / kx));
  }

  test('trecho perto do veículo detalhado e total dentro do limite', () {
    // Limite menor que a rota: o resto precisa ir mais leve.
    final w = RouteWindow(pts, maxPoints: 1500);
    final out = w.build(100000); // veículo a 100 km
    expect(out.length, lessThanOrEqualTo(1500));
    // Pontos do trecho de 100 km a 105 km (pela latitude).
    final a = lat0 + 100000 / ky, b = lat0 + 105000 / ky;
    final near = out.where((p) => p.$1 >= a && p.$1 <= b).length;
    final far = out.where((p) => p.$1 >= a + 50000 / ky && p.$1 <= b + 50000 / ky).length;
    // ignore: avoid_print
    print('total ${out.length}, perto ${near}, longe (mesmo tamanho) $far');
    expect(near, greaterThan(far * 2));
    // Ordem preservada (sempre para o norte).
    for (var i = 1; i < out.length; i++) {
      expect(out[i].$1, greaterThanOrEqualTo(out[i - 1].$1));
    }
  });

  test('trecho anda com o veículo', () {
    final w = RouteWindow(pts);
    expect(w.needsMove(0), isTrue);
    w.build(0);
    expect(w.needsMove(2000), isFalse);
    expect(w.needsMove(3600), isTrue);
  });
}
