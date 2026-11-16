import 'package:comboio/logic/best_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('4 destinos numa linha: visita na ordem da linha', () {
    // saída em 0; destinos embaralhados ao longo de uma reta (norte)
    final o = bestOrders((0.0, 0.0), [(0.3, 0.0), (0.1, 0.0), (0.4, 0.0), (0.2, 0.0)]);
    expect(o.first, [1, 3, 0, 2]);
  });
  test('10 destinos: usa vizinho mais próximo + 2-opt sem erro', () {
    final d = [for (var i = 0; i < 10; i++) ((9 - i) * 0.05, 0.0)];
    final o = bestOrders((0.0, 0.0), d);
    expect(o.first, [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
  });

  test('expedição: saída, destino e pernoite fixos; troca só dentro do dia', () {
    // 0 saída, 1..2 dia 1 fora de ordem, 3 pernoite, 4..5 dia 2 fora de ordem, 6 destino
    final pts = [
      (0.0, 0.0), (0.2, 0.0), (0.1, 0.0), (0.3, 0.0),
      (0.5, 0.0), (0.4, 0.0), (0.6, 0.0)
    ];
    expect(bestOrderAnchored(pts, (i) => i == 3), [0, 2, 1, 3, 5, 4, 6]);
  });

  test('expedição: pernoite não sai do lugar mesmo se ficar mais curto', () {
    final pts = [(0.0, 0.0), (0.3, 0.0), (0.1, 0.0), (0.2, 0.0), (0.4, 0.0)];
    // 1 é pernoite: fica em 2º, e só 2 e 3 ficam entre ele e o destino
    expect(bestOrderAnchored(pts, (i) => i == 1), [0, 1, 2, 3, 4]);
  });

  test('expedição: muitas paradas num dia (vizinho mais próximo + 2-opt)', () {
    final mids = [for (var i = 10; i >= 1; i--) (i / 10, 0.0)];
    final pts = [(0.0, 0.0), ...mids, (1.1, 0.0)];
    expect(bestOrderAnchored(pts, (_) => false),
        [0, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 11]);
  });
}
