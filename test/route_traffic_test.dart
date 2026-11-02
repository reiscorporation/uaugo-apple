import 'package:comboio/logic/route_traffic.dart';
import 'package:comboio/logic/simulation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Rota reta para o norte, ~11 km.
  final route = RouteWalker([for (var i = 0; i <= 100; i++) (-21.0 + i * 0.001, -47.0)]);

  test('trecho do Google vira intervalo em metros na rota', () {
    final line = [(-21.0, -47.0), (-20.95, -47.0), (-20.9, -47.0)];
    final runs = trafficOnRoute(route, line, [
      (start: 0, end: 1, level: 0),
      (start: 1, end: 2, level: 2),
    ]);
    expect(runs, hasLength(2));
    expect(runs[1].level, 2);
    expect(runs[0].to, closeTo(runs[1].from, 1));
    expect(runs[1].to, closeTo(route.length, 50));
  });

  test('trecho longe da rota fica de fora', () {
    final line = [(-21.0, -46.9), (-20.9, -46.9)];
    expect(trafficOnRoute(route, line, [(start: 0, end: 1, level: 2)]), isEmpty);
  });

  test('nível pelo nome do Google', () {
    expect(trafficLevel('NORMAL'), 0);
    expect(trafficLevel('SLOW'), 1);
    expect(trafficLevel('TRAFFIC_JAM'), 2);
    expect(trafficLevel(null), 0);
  });

  test('pointsBetween vai de ponta a ponta', () {
    final p = route.pointsBetween(500, 1500);
    expect(p.length, greaterThan(2));
    expect(p.first.$1, greaterThan(-21.0));
    expect(p.last.$1, lessThan(-20.98));
  });
}
