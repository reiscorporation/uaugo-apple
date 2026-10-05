// ============================================================================
// geo.dart — Traçados de rota (polylines)
//
// O que faz: Codifica e decodifica o formato "encoded polyline" do Google
//   (como as rotas são guardadas no Firestore) e simplifica traçados
//   (Douglas-Peucker) sem perder as curvas.
// Quem usa: DirectionsService, MapScreen, PlanScreen, histórico.
// Onde mexer: Tolerância da simplificação: DirectionsService (4 m).
// ============================================================================

import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Funções puras (sem Firebase nem GPS) para facilitar os testes.

/// Direção de A para B em graus (0 = norte, 90 = leste), de 0 a 360.
double bearingBetween(double lat1, double lng1, double lat2, double lng2) {
  final p1 = lat1 * pi / 180;
  final p2 = lat2 * pi / 180;
  final dl = (lng2 - lng1) * pi / 180;
  final y = sin(dl) * cos(p2);
  final x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

/// Menor diferença entre dois ângulos, de 0 a 180.
double angleDiff(double a, double b) {
  var d = (a - b).abs() % 360;
  if (d > 180) d = 360 - d;
  return d;
}

/// O alvo está à frente do piloto? Parado (ou sem direção), considera que sim.
bool isAhead({
  required double lat,
  required double lng,
  required double heading,
  required double speed,
  required double targetLat,
  required double targetLng,
  double maxAngle = 60,
}) {
  if (speed < 3 || heading < 0) return true;
  final bearing = bearingBetween(lat, lng, targetLat, targetLng);
  return angleDiff(bearing, heading) < maxAngle;
}

/// Um voto "não está mais" remove o alerta? (RN-06)
bool shouldRemoveHazard({
  required int confirmations,
  required int dismissals,
  bool force = false,
}) {
  final votes = dismissals + 1;
  return force || votes >= 2 || votes > confirmations;
}

/// Decodifica a polyline do Google (formato "encoded polyline").
List<LatLng> decodePolyline(String encoded) {
  final pts = <LatLng>[];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int b = 0, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    pts.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return pts;
}

/// Simplifica um traçado (Douglas-Peucker) mantendo o desenho das curvas:
/// tira os pontos que se desviam menos de [toleranceMeters] da reta.
List<LatLng> simplifyPolyline(List<LatLng> pts, double toleranceMeters) {
  if (pts.length < 3) return pts;
  // Projeção plana local (metros) em torno do primeiro ponto.
  final lat0 = pts.first.latitude * pi / 180;
  final kx = 111320 * cos(lat0), ky = 110540.0;
  final xs = [for (final p in pts) p.longitude * kx];
  final ys = [for (final p in pts) p.latitude * ky];
  final keep = List<bool>.filled(pts.length, false)
    ..[0] = true
    ..[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  final tol2 = toleranceMeters * toleranceMeters;
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD2 = 0.0;
    var idx = -1;
    final dx = xs[b] - xs[a], dy = ys[b] - ys[a];
    final len2 = dx * dx + dy * dy;
    for (var i = a + 1; i < b; i++) {
      double d2;
      if (len2 == 0) {
        final ex = xs[i] - xs[a], ey = ys[i] - ys[a];
        d2 = ex * ex + ey * ey;
      } else {
        final cross = (xs[i] - xs[a]) * dy - (ys[i] - ys[a]) * dx;
        d2 = cross * cross / len2;
      }
      if (d2 > maxD2) {
        maxD2 = d2;
        idx = i;
      }
    }
    if (idx >= 0 && maxD2 > tol2) {
      keep[idx] = true;
      stack
        ..add((a, idx))
        ..add((idx, b));
    }
  }
  return [
    for (var i = 0; i < pts.length; i++)
      if (keep[i]) pts[i]
  ];
}

/// Codifica pontos no formato "encoded polyline" do Google (inverso do decode).
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var prevLat = 0, prevLng = 0;
  /// Escreve um número no formato do Google: blocos de 5 bits, do menos
  /// para o mais significativo, cada um somado a 63 (vira caractere ASCII).
  void enc(int v) {
    var x = v < 0 ? ~(v << 1) : (v << 1);
    while (x >= 0x20) {
      out.writeCharCode((0x20 | (x & 0x1f)) + 63);
      x >>= 5;
    }
    out.writeCharCode(x + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * 1e5).round();
    final lng = (p.longitude * 1e5).round();
    enc(lat - prevLat);
    enc(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return out.toString();
}
