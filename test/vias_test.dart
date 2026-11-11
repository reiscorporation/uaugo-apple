import 'package:comboio/models/expedition.dart';
import 'package:comboio/services/trip_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 11/11: arrastar a rota cria ponto de passagem, que NÃO é parada.
  test('passagem entra entre os dois pontos de menor desvio', () {
    const a = TripPoint('Saída', -21.17, -47.81);
    const b = TripPoint('Parada', -21.20, -47.78);
    const c = TripPoint('Destino', -21.25, -47.70);
    final m = TripService.mergeVias([a, b, c], [(-21.23, -47.74)]);
    expect(m.map((e) => e.$2), [false, false, true, false]);
    final m2 = TripService.mergeVias([a, b, c], [(-21.18, -47.80)]);
    expect(m2.map((e) => e.$2), [false, true, false, false]);
  });

  test('passagens são guardadas e lidas de volta no plano', () {
    const p = TripPlan(polyline: 'x', vias: [(-21.1, -47.8), (-21.2, -47.7)]);
    final back = TripPlan.fromMap(p.toMap());
    expect(back.vias, [(-21.1, -47.8), (-21.2, -47.7)]);
    expect(TripPlan.fromMap(const TripPlan().toMap()).vias, isEmpty);
    expect(p.copyWith(polyline: 'y').vias.length, 2);
  });
}
