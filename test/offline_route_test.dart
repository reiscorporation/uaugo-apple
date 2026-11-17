import 'package:comboio/logic/offline_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Caminho gravado: de sul para norte, ~3 km (0,027 grau).
  final path = [for (var i = 0; i <= 30; i++) (-21.20 + i * 0.001, -47.80)];

  test('origem perto do caminho e destino nele: usa o trecho', () {
    final r = offlineRouteFrom([path], (-21.1995, -47.8003), (-21.180, -47.80));
    expect(r, isNotNull);
    expect(r!.line.first, (-21.1995, -47.8003));
    expect(r.line.last, (-21.180, -47.80));
    expect(r.lengthM, closeTo(2200, 150));
  });

  test('destino antes da origem (sentido contrário): não serve', () {
    expect(offlineRouteFrom([path], (-21.175, -47.80), (-21.195, -47.80)), isNull);
  });

  test('longe do caminho: não serve', () {
    expect(offlineRouteFrom([path], (-21.20, -47.75), (-21.180, -47.80)), isNull);
    expect(offlineRouteFrom([path], (-21.20, -47.80), (-21.18, -47.75)), isNull);
  });

  test('vários caminhos: fica com o mais curto', () {
    final longo = [(-21.20, -47.80), (-21.20, -47.78), (-21.18, -47.78), (-21.18, -47.80)];
    final r = offlineRouteFrom([longo, path], (-21.20, -47.80), (-21.18, -47.80));
    expect(r!.source, 1);
  });
}
