import 'package:comboio/logic/keep_route.dart';
import 'package:comboio/logic/radars.dart' show distanceMeters;
import 'package:flutter_test/flutter_test.dart';

/// Rota padrão reta para o norte; a escolhida desvia 400 m para leste no
/// meio (outra avenida) e volta. O ponto de passagem fica no desvio.
void main() {
  const lat0 = -21.19, lng0 = -47.78;
  const dLat = 0.009; // ~1 km
  final main = [(lat0, lng0), (lat0 + 3 * dLat, lng0)];
  final chosen = [
    (lat0, lng0),
    (lat0 + dLat, lng0),
    (lat0 + dLat, lng0 + 0.0039), // ~400 m a leste
    (lat0 + 2 * dLat, lng0 + 0.0039),
    (lat0 + 2 * dLat, lng0),
    (lat0 + 3 * dLat, lng0),
  ];

  test('marca um ponto no trecho em que a escolhida se separa', () {
    final v = distinctiveVias(chosen, main);
    expect(v.length, 1);
    // No desvio: longe da rota padrão e perto da avenida escolhida.
    expect(distanceMeters(v.first.$1, v.first.$2, v.first.$1, lng0), greaterThan(300));
  });

  test('mesmo caminho: nenhum ponto', () {
    expect(distinctiveVias(main, main), isEmpty);
  });

  test('vários desvios: no máximo maxVias, na ordem do caminho', () {
    final zig = <(double, double)>[(lat0, lng0)];
    for (var i = 0; i < 10; i++) {
      final la = lat0 + i * dLat;
      zig.addAll([(la, lng0 + 0.004), (la + dLat * 0.5, lng0 + 0.004), (la + dLat, lng0)]);
    }
    final long = [(lat0, lng0), (lat0 + 10 * dLat, lng0)];
    final v = distinctiveVias(zig, long, maxVias: 4);
    expect(v.length, 4);
    for (var i = 1; i < v.length; i++) {
      expect(v[i].$1, greaterThan(v[i - 1].$1));
    }
  });
}
