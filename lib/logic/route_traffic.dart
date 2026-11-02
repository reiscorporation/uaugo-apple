// ============================================================================
// route_traffic.dart — Trânsito só em cima da rota
//
// O que faz: Coloca na rota do app os trechos de trânsito que o Google devolve
//   (o traçado dele não é ponto a ponto igual ao nosso): cada trecho vira um
//   intervalo em metros pela rota, com o nível de lentidão.
// Quem usa: MapScreen (_refreshRouteTraffic) e DirectionsService.routeTraffic.
// ============================================================================

import 'simulation.dart';

/// Trecho da rota com trânsito: de/até (metros pela rota) e nível
/// (0 livre, 1 lento, 2 parado).
typedef TrafficRun = ({double from, double to, int level});

/// Trecho do traçado do Google: índices dos pontos e o nível.
typedef TrafficInterval = ({int start, int end, int level});

/// Nível pelo nome do Google (NORMAL, SLOW, TRAFFIC_JAM).
int trafficLevel(String? speed) => switch (speed) {
      'SLOW' => 1,
      'TRAFFIC_JAM' => 2,
      _ => 0,
    };

/// Trechos em metros pela [route]. Parte que passa longe dela (o Google foi
/// por outro caminho) fica de fora: o trânsito só aparece na rota traçada.
List<TrafficRun> trafficOnRoute(RouteWalker route, List<(double, double)> line,
    List<TrafficInterval> intervals,
    {double start = 0, double maxOffset = 60}) {
  final out = <TrafficRun>[];
  var along = start;
  for (final t in intervals) {
    if (t.start < 0 || t.end >= line.length || t.end <= t.start) continue;
    final a = line[t.start], b = line[t.end];
    final pa = route.project(a.$1, a.$2, around: along);
    final pb = route.project(b.$1, b.$2, around: pa.along);
    if (pa.offset > maxOffset || pb.offset > maxOffset) continue;
    if (pb.along <= pa.along) continue;
    out.add((from: pa.along, to: pb.along, level: t.level));
    along = pb.along;
  }
  return out;
}
