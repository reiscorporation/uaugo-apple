// ============================================================================
// risk_areas.dart — Quadrados que a rota deve evitar
//
// O que faz: Escolhe, entre as áreas críticas e os alertas confirmados, as que
//   ficam perto da viagem e monta os polígonos que o motor recebe.
// Quem usa: DirectionsService ("Evitar locais de risco").
// Onde mexer: Origem dos dados: scripts/areas-risco.py.
// ============================================================================

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'radars.dart' show distanceMeters;

/// O motor aceita um total de contorno por pedido (service_limits).
const maxAvoidAreas = 300;

/// Sem bloquear onde a pessoa saiu, para ou chega.
const _keepClearM = 400.0;

/// Folga em volta da viagem (graus, ~5 km).
const _margin = 0.045;

/// Áreas ([lat, lng], da mais crítica à menos) dentro da região da viagem.
/// Fora as que cobrem um ponto de [points].
List<(double, double)> avoidAreasFor(
    List<LatLng> points, List<(double, double)> areas) {
  if (points.isEmpty) return const [];
  final las = points.map((p) => p.latitude);
  final los = points.map((p) => p.longitude);
  final s = las.reduce((a, b) => a < b ? a : b) - _margin;
  final n = las.reduce((a, b) => a > b ? a : b) + _margin;
  final w = los.reduce((a, b) => a < b ? a : b) - _margin;
  final e = los.reduce((a, b) => a > b ? a : b) + _margin;
  return areas
      .where((a) =>
          a.$1 >= s &&
          a.$1 <= n &&
          a.$2 >= w &&
          a.$2 <= e &&
          points.every((p) =>
              distanceMeters(p.latitude, p.longitude, a.$1, a.$2) > _keepClearM))
      .take(maxAvoidAreas)
      .toList();
}

/// Quadrado de lado [side] graus em volta de cada área, no formato do motor
/// (`exclude_polygons`: [lng, lat], anel fechado).
List<List<List<double>>> avoidPolygons(
    List<(double, double)> areas, double side) {
  final h = side / 2;
  return [
    for (final (la, lo) in areas)
      [
        [lo - h, la - h],
        [lo + h, la - h],
        [lo + h, la + h],
        [lo - h, la + h],
        [lo - h, la - h],
      ]
  ];
}
