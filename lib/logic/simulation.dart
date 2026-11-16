// ============================================================================
// simulation.dart — Andar pela rota
//
// O que faz: RouteWalker: dado um traçado, devolve a posição a X metros do
//   início, projeta um ponto na rota (quanto já andou, quanto se afastou) e
//   mede distâncias até a rota só no trecho perto do piloto (leve).
// Quem usa: Simulação, narração, radares, limite da via, chuva e metade do
//   trajeto.
// Onde mexer: Janela da busca rápida: project(around:) e offsetNear(window:).
// ============================================================================

import 'dart:math';

import 'geo.dart';
import 'radars.dart';

/// Percorre um traçado por distância: para a simulação da viagem
/// (função pura, testável).
class RouteWalker {
  RouteWalker(this.points) : _cum = _cumulative(points);

  final List<(double, double)> points; // (lat, lng)
  final List<double> _cum; // distância acumulada até cada ponto

  double get length => _cum.isEmpty ? 0 : _cum.last;

  /// Distância acumulada do início até cada ponto (mesmo tamanho de
  /// [points]); usada pelo RoadSnapper para olhar só os trechos perto.
  List<double> get cumulative => _cum;

  /// Distância acumulada do início até cada ponto do traçado.
  static List<double> _cumulative(List<(double, double)> pts) {
    final out = <double>[];
    var acc = 0.0;
    for (var i = 0; i < pts.length; i++) {
      if (i > 0) {
        acc += distanceMeters(
            pts[i - 1].$1, pts[i - 1].$2, pts[i].$1, pts[i].$2);
      }
      out.add(acc);
    }
    return out;
  }

  /// O traçado que falta a partir de [meters] (o 1º ponto é a posição
  /// exata nesse ponto): usado para apagar o trecho já percorrido.
  List<(double, double)> pointsAfter(double meters) {
    if (points.length < 2) return points;
    final here = at(meters);
    var i = 0;
    while (i < _cum.length && _cum[i] <= meters) {
      i++;
    }
    return [(here.lat, here.lng), ...points.skip(i)];
  }

  /// O traçado entre [from] e [to] metros, com as duas pontas exatas.
  List<(double, double)> pointsBetween(double from, double to) {
    final a = at(from), b = at(to);
    return [
      (a.lat, a.lng),
      for (var i = 0; i < points.length && _cum[i] < to; i++)
        if (_cum[i] > from) points[i],
      (b.lat, b.lng),
    ];
  }

  /// Posição e direção a [meters] do início (limitado ao traçado).
  ({double lat, double lng, double bearing}) at(double meters) {
    if (points.isEmpty) return (lat: 0, lng: 0, bearing: 0);
    if (points.length == 1) {
      return (lat: points.first.$1, lng: points.first.$2, bearing: 0);
    }
    final d = meters.clamp(0.0, length);
    // Busca binária do trecho que contém d.
    var lo = 0, hi = _cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final (aLat, aLng) = points[lo];
    final (bLat, bLng) = points[hi];
    final seg = _cum[hi] - _cum[lo];
    final t = seg == 0 ? 0.0 : (d - _cum[lo]) / seg;
    return (
      lat: aLat + (bLat - aLat) * t,
      lng: aLng + (bLng - aLng) * t,
      bearing: bearingBetween(aLat, aLng, bLat, bLng),
    );
  }

  /// Projeta um ponto no traçado: distância percorrida até ali ([along]),
  /// afastamento do traçado ([offset], m) e direção da via no ponto.
  ///
  /// Com [around] (onde o piloto estava na leitura anterior), olha só o
  /// trecho de ±2 km em volta: roda toda segundo, e percorrer uma rota de
  /// centenas de km inteira a cada leitura gasta bateria à toa. Se o ponto
  /// não estiver perto desse trecho, refaz a busca na rota toda.
  ///
  /// Em rotatória, alça e retorno a rota passa a poucos metros dela mesma:
  /// entre os trechos quase tão perto quanto o mais perto, fica o que segue
  /// a direção do veículo ([heading]) e o mais próximo de [around] (ou o
  /// primeiro depois de [after]). Sem isso a posição pulava para a frente e
  /// para trás (3D "em loop" e mapa perdendo a orientação).
  ({double along, double offset, double bearing}) project(
      double lat, double lng, {double? around, double? heading, double? after}) {
    if (points.length < 2) {
      return (along: 0, offset: double.infinity, bearing: 0);
    }
    if (around != null) {
      final near = _projectRange(lat, lng, _indexAt(max(0, around - 2000)),
          min(points.length - 1, _indexAt(around + 2000) + 1),
          around: around, heading: heading);
      if (near.offset < 200) return near;
    }
    return _projectRange(lat, lng, 0, points.length - 1,
        around: around, heading: heading, after: after);
  }

  /// Trecho "quase tão perto" do mais perto (m): o GPS erra uns 10 a 20 m.
  static const _tieMeters = 25.0;

  ({double along, double offset, double bearing}) _projectRange(
      double lat, double lng, int first, int last,
      {double? around, double? heading, double? after}) {
    final kx = cos(lat * pi / 180);
    var best = (along: 0.0, offset: double.infinity, bearing: 0.0);
    final close = <({double along, double offset, double bearing})>[];
    for (var i = max(1, first + 1); i <= last; i++) {
      final (aLat, aLng) = points[i - 1];
      final (bLat, bLng) = points[i];
      final ax = aLng * kx, bx = bLng * kx;
      final dx = bx - ax, dy = bLat - aLat;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0
          ? 0.0
          : (((lng * kx - ax) * dx + (lat - aLat) * dy) / len2)
              .clamp(0.0, 1.0);
      final qLat = aLat + t * (bLat - aLat), qLng = aLng + t * (bLng - aLng);
      final off = distanceMeters(lat, lng, qLat, qLng);
      if (off < best.offset || off < 80) {
        final q = (
          along: _cum[i - 1] + t * (_cum[i] - _cum[i - 1]),
          offset: off,
          bearing: bearingBetween(aLat, aLng, bLat, bLng),
        );
        if (off < best.offset) best = q;
        // Só o pé da perpendicular: a ponta do trecho vizinho não é outro caminho.
        if (off < 80 && t > 0 && t < 1) close.add(q);
      }
    }
    if (around == null && heading == null && after == null) return best;
    var pool = [
      best,
      for (final q in close)
        if (q.offset <= best.offset + _tieMeters && q != best) q
    ];
    if (pool.length < 2) return best;
    if (heading != null) {
      final same = [for (final q in pool) if (angleDiff(q.bearing, heading) < 75) q];
      if (same.isNotEmpty) pool = same;
    }
    if (after != null) {
      final ahead = [for (final q in pool) if (q.along >= after - 30) q];
      if (ahead.isNotEmpty) pool = ahead;
      return pool.reduce((a, b) => a.along <= b.along ? a : b);
    }
    if (around != null) {
      return pool.reduce(
          (a, b) => (a.along - around).abs() <= (b.along - around).abs() ? a : b);
    }
    return pool.reduce((a, b) => a.offset <= b.offset ? a : b);
  }

  /// Índice do ponto do traçado onde está a distância [meters] (busca binária).
  int _indexAt(double meters) {
    var lo = 0, hi = _cum.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_cum[mid] <= meters) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Distância (m) de um ponto até o traçado, olhando só o trecho de
  /// [around] − [window] até [around] + [window] metros (rápido: a consulta
  /// roda várias vezes por segundo).
  double offsetNear(double lat, double lng, double around,
      {double window = 400}) {
    if (points.length < 2) return double.infinity;
    final a = _indexAt(max(0, around - window));
    final b = min(points.length - 1, _indexAt(around + window) + 1);
    final kx = cos(lat * pi / 180);
    var best = double.infinity;
    for (var i = a + 1; i <= b; i++) {
      final (aLat, aLng) = points[i - 1];
      final (bLat, bLng) = points[i];
      // Projeção plana local, em metros.
      final ax = (aLng - lng) * 111320 * kx, ay = (aLat - lat) * 110540;
      final bx = (bLng - lng) * 111320 * kx, by = (bLat - lat) * 110540;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final d = sqrt(px * px + py * py);
      if (d < best) best = d;
    }
    return best;
  }

  /// Quanto falta (em metros) a partir do ponto do traçado mais próximo.
  double remainingFrom(double lat, double lng) {
    if (points.length < 2) return 0;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = distanceMeters(lat, lng, points[i].$1, points[i].$2);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return length - _cum[best];
  }
}
