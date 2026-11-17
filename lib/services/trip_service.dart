// ============================================================================
// trip_service.dart — Viagem sozinho
//
// O que faz: Monta uma Trip a partir dos pontos (saída, destino) usando a
//   Directions API, e recalcula a partir da posição atual.
// Quem usa: Home ("Para onde?"), MapScreen (recálculo e trânsito), histórico.
// ============================================================================

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/geo.dart' show decodePolyline, encodePolyline;
import '../logic/offline_route.dart';
import '../logic/navigation.dart';
import '../logic/radars.dart' show distanceMeters, nearestOnLine;
import '../models/expedition.dart';
import '../models/trip.dart';
import 'directions_service.dart';
import 'history_service.dart';
import '../l10n/i18n.dart';

/// Um ponto da viagem sozinho (saída, parada ou destino).
class TripPoint {
  final String name;
  final double lat;
  final double lng;
  final StopType type;
  const TripPoint(this.name, this.lat, this.lng,
      {this.type = StopType.waypoint});
}

/// Monta viagens sem expedição (rota calculada na hora pelo Google).
class TripService {
  /// Rota passando pelos pontos, na ordem. Null se não der para calcular.
  static Future<Trip?> build({
    required String title,
    required List<TripPoint> points,
    bool avoidTolls = false,
    bool avoidHighways = false,
    bool alternatives = false,
    List<(double, double)> vias = const [],
  }) async {
    if (points.length < 2) return null;
    if (vias.isNotEmpty) {
      return _buildWithVias(title, points, vias, avoidTolls, avoidHighways);
    }
    final r = await DirectionsService.detailedRoute(
      [for (final p in points) LatLng(p.lat, p.lng)],
      avoidTolls: avoidTolls,
      avoidHighways: avoidHighways,
      alternatives: alternatives,
    );
    if (r == null || r.legs.length != points.length - 1) {
      // Sem internet (ou falha): uma viagem já feita até o destino (17/11).
      return r == null ? await _fromHistory(title, points) : null;
    }
    return _fromRoute(r, title, points, avoidTolls, avoidHighways, [
      for (final a in r.alternatives)
        if (a.legs.length == points.length - 1)
          _fromRoute(a, title, points, avoidTolls, avoidHighways, const [])
    ]);
  }

  /// Rota tirada de uma viagem já feita (sem internet): da posição do
  /// piloto (1º ponto) ao destino (último), sem as paradas do meio. Sem
  /// manobras: a linha, os radares e a distância funcionam; a narração não.
  static Future<Trip?> _fromHistory(String title, List<TripPoint> points) async {
    try {
      await HistoryService.instance.load();
    } catch (_) {}
    final recs = HistoryService.instance.trips.value;
    if (recs.isEmpty) return null;
    final lines = <List<(double, double)>>[];
    final speeds = <double>[];
    for (final t in recs) {
      // Rota planejada (mais limpa) e o caminho de fato percorrido.
      for (final pl in [t.routePolyline, t.trackPolyline]) {
        if (pl.isEmpty) continue;
        final pts = [for (final p in decodePolyline(pl)) (p.latitude, p.longitude)];
        if (pts.length < 2) continue;
        lines.add(pts);
        speeds.add(t.movingS > 60 && t.distanceM > 500 ? t.distanceM / t.movingS : 40 / 3.6);
      }
    }
    final o = points.first, d = points.last;
    final found = offlineRouteFrom(lines, (o.lat, o.lng), (d.lat, d.lng));
    if (found == null) return null;
    final speed = speeds[found.source].clamp(5.0, 30.0);
    final len = found.lengthM.round();
    final dur = (found.lengthM / speed).round();
    return Trip(
      title: title,
      summary: tr('Caminho de uma viagem já feita (sem internet)'),
      plan: TripPlan(
        polyline: encodePolyline([for (final (la, lo) in found.line) LatLng(la, lo)]),
        routeVersion: TripPlan.currentRouteVersion,
      ),
      stops: [
        Stop(id: 'p0', name: o.name, lat: o.lat, lng: o.lng, order: 0, createdBy: '',
            type: o.type, legDistanceM: 0, legDurationS: 0, steps: const []),
        Stop(id: 'p1', name: d.name, lat: d.lat, lng: d.lng, order: 1, createdBy: '',
            type: d.type, legDistanceM: len, legDurationS: dur, steps: const []),
      ],
    );
  }

  /// Onde cada ponto de passagem entra: entre os dois pontos em que o
  /// desvio (em linha reta) é menor. Devolve a lista com a marca "é via".
  static List<(TripPoint, bool)> mergeVias(
      List<TripPoint> points, List<(double, double)> vias) {
    final out = [for (final p in points) (p, false)];
    for (final (la, lo) in vias) {
      var best = 1;
      var bestCost = double.infinity;
      for (var i = 1; i < out.length; i++) {
        final a = out[i - 1].$1, b = out[i].$1;
        final c = distanceMeters(a.lat, a.lng, la, lo) +
            distanceMeters(la, lo, b.lat, b.lng) -
            distanceMeters(a.lat, a.lng, b.lat, b.lng);
        if (c < bestCost) {
          bestCost = c;
          best = i;
        }
      }
      out.insert(best, (TripPoint('', la, lo), true));
    }
    return out;
  }

  /// Rota passando pelos pontos de passagem: pede ao serviço com eles no
  /// meio e junta os trechos de volta entre as paradas de verdade.
  static Future<Trip?> _buildWithVias(String title, List<TripPoint> points,
      List<(double, double)> vias, bool avoidTolls, bool avoidHighways) async {
    final merged = mergeVias(points, vias);
    final r = await DirectionsService.detailedRoute(
      [for (final (p, _) in merged) LatLng(p.lat, p.lng)],
      avoidTolls: avoidTolls,
      avoidHighways: avoidHighways,
    );
    if (r == null || r.legs.length != merged.length - 1) return null;
    final legs = <RouteLeg>[];
    final steps = <List<NavStep>>[];
    var d = 0, t = 0, ty = 0;
    var st = <NavStep>[];
    for (var i = 1; i < merged.length; i++) {
      final l = r.legs[i - 1];
      d += l.distanceM;
      t += l.durationS;
      ty += l.typicalS;
      if (i - 1 < r.legSteps.length) st.addAll(r.legSteps[i - 1]);
      if (!merged[i].$2) {
        legs.add(RouteLeg(d, t, ty));
        steps.add(st);
        d = t = ty = 0;
        st = <NavStep>[];
      }
    }
    final rr = RouteResult(r.polyline, legs, steps, r.riskCount, r.hasToll, r.summary);
    return _fromRoute(rr, title, points, avoidTolls, avoidHighways, const [],
        vias: vias);
  }

  /// Pontos de passagem que ainda estão à frente de quem está em [lat],[lng]
  /// (pela posição ao longo da rota atual).
  static List<(double, double)> viasAhead(Trip trip, double lat, double lng) {
    final vias = trip.plan.vias;
    if (vias.isEmpty) return const [];
    final line = [
      for (final p in decodePolyline(trip.plan.polyline)) (p.latitude, p.longitude)
    ];
    if (line.length < 2) return vias;
    double along(double la, double lo) {
      var best = double.infinity, at = 0.0, acc = 0.0;
      for (var i = 1; i < line.length; i++) {
        final seg = [line[i - 1], line[i]];
        final n = nearestOnLine(la, lo, seg);
        if (n.meters < best) {
          best = n.meters;
          at = acc + distanceMeters(line[i - 1].$1, line[i - 1].$2, n.lat, n.lng);
        }
        acc += distanceMeters(line[i - 1].$1, line[i - 1].$2, line[i].$1, line[i].$2);
      }
      return at;
    }
    final me = along(lat, lng);
    return [
      for (final v in vias)
        if (along(v.$1, v.$2) > me + 30) v
    ];
  }

  /// Monta a viagem a partir de uma rota calculada.
  static Trip _fromRoute(RouteResult r, String title, List<TripPoint> points,
      bool avoidTolls, bool avoidHighways, List<Trip> alternatives,
      {List<(double, double)> vias = const []}) {
    final stops = <Stop>[
      for (var i = 0; i < points.length; i++)
        Stop(
          id: 'p$i',
          name: points[i].name,
          lat: points[i].lat,
          lng: points[i].lng,
          order: i,
          createdBy: '',
          type: points[i].type,
          legDistanceM: i == 0 ? 0 : r.legs[i - 1].distanceM,
          legDurationS: i == 0 ? 0 : r.legs[i - 1].durationS,
          steps: i == 0 || i - 1 >= r.legSteps.length
              ? const <NavStep>[]
              : r.legSteps[i - 1],
        ),
    ];
    return Trip(
      typicalS: r.legs.fold<int>(0, (a, l) => a + l.typicalS),
      riskCount: r.riskCount,
      hasToll: r.hasToll,
      summary: r.summary,
      alternatives: alternatives,
      title: title,
      plan: TripPlan(
        polyline: r.polyline,
        avoidTolls: avoidTolls,
        avoidHighways: avoidHighways,
        routeVersion: TripPlan.currentRouteVersion,
        vias: vias,
      ),
      stops: stops,
    );
  }

  /// Recalcula a partir de onde o piloto está até os pontos que faltam.
  static Future<Trip?> reroute(
    Trip trip, {
    required double lat,
    required double lng,
    required int nextStopIndex,
  }) {
    final rest = trip.stops.skip(nextStopIndex.clamp(1, trip.stops.length - 1));
    return build(
      title: trip.title,
      points: [
        TripPoint(tr('Sua posição'), lat, lng, type: StopType.meet),
        for (final s in rest) TripPoint(s.name, s.lat, s.lng, type: s.type),
      ],
      avoidTolls: trip.plan.avoidTolls,
      avoidHighways: trip.plan.avoidHighways,
      vias: viasAhead(trip, lat, lng),
    );
  }
}
