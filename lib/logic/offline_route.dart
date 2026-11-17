// ============================================================================
// offline_route.dart — Rota sem internet a partir de uma viagem já feita
//
// O que faz: sem internet a rota não pode ser calculada. Se o piloto já fez
//   uma viagem que passa perto de onde ele está e chega ao destino pedido
//   (ex.: "Casa"), o trecho dessa viagem vira a rota: linha azul, radares,
//   limites e distância restante funcionam; a narração das curvas não (o
//   caminho gravado não tem as manobras). Pedido do Ricardo, 17/11.
// Quem usa: TripService.build (quando a rota não pôde ser calculada).
// Onde mexer: distâncias aceitas ([nearOriginM], [nearDestM]).
// ============================================================================

import 'radars.dart' show distanceMeters;

/// Trecho de um caminho já feito que leva de [origin] até [dest].
class OfflineRoute {
  /// Pontos (lat, lng) da origem ao destino.
  final List<(double, double)> line;
  final double lengthM;

  /// Índice do caminho de onde veio (na lista de candidatos).
  final int source;
  const OfflineRoute(this.line, this.lengthM, this.source);
}

/// Distância até onde a origem pode estar do caminho (m).
const nearOriginM = 800.0;

/// Distância até onde o destino pode estar do caminho (m).
const nearDestM = 400.0;

/// Melhor trecho (o mais curto) entre os [candidates] (caminhos gravados,
/// cada um uma lista de (lat, lng)) que passe a até [nearOriginM] da origem
/// e depois a até [nearDestM] do destino. Null se nenhum servir.
OfflineRoute? offlineRouteFrom(
  List<List<(double, double)>> candidates,
  (double, double) origin,
  (double, double) dest,
) {
  OfflineRoute? best;
  for (var c = 0; c < candidates.length; c++) {
    final line = candidates[c];
    if (line.length < 2) continue;
    // Ponto do caminho mais perto do destino (a viagem pode ter seguido
    // além dele, ex.: passou em casa e foi para outro lugar).
    var di = -1;
    var dd = nearDestM;
    for (var i = 0; i < line.length; i++) {
      final d = distanceMeters(line[i].$1, line[i].$2, dest.$1, dest.$2);
      if (d <= dd) {
        dd = d;
        di = i;
      }
    }
    if (di <= 0) continue;
    // Ponto mais perto da origem, ANTES do destino (mesmo sentido).
    var oi = -1;
    var od = nearOriginM;
    for (var i = 0; i < di; i++) {
      final d = distanceMeters(line[i].$1, line[i].$2, origin.$1, origin.$2);
      if (d <= od) {
        od = d;
        oi = i;
      }
    }
    if (oi < 0) continue;
    final seg = <(double, double)>[origin, ...line.sublist(oi, di + 1), dest];
    var len = 0.0;
    for (var i = 1; i < seg.length; i++) {
      len += distanceMeters(seg[i - 1].$1, seg[i - 1].$2, seg[i].$1, seg[i].$2);
    }
    if (best == null || len < best.lengthM) best = OfflineRoute(seg, len, c);
  }
  return best;
}
