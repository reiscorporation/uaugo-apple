// ============================================================================
// trip_service.dart — Viagem sozinho
//
// O que faz: Monta uma Trip a partir dos pontos (saída, destino) usando a
//   Directions API, e recalcula a partir da posição atual.
// Quem usa: Home ("Para onde?"), MapScreen (recálculo e trânsito), histórico.
// ============================================================================

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/navigation.dart';
import '../models/expedition.dart';
import '../models/trip.dart';
import 'directions_service.dart';
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
  }) async {
    if (points.length < 2) return null;
    final r = await DirectionsService.detailedRoute(
      [for (final p in points) LatLng(p.lat, p.lng)],
      avoidTolls: avoidTolls,
      avoidHighways: avoidHighways,
    );
    if (r == null || r.legs.length != points.length - 1) return null;
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
      title: title,
      plan: TripPlan(
        polyline: r.polyline,
        avoidTolls: avoidTolls,
        avoidHighways: avoidHighways,
        routeVersion: TripPlan.currentRouteVersion,
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
    );
  }
}
