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
}
