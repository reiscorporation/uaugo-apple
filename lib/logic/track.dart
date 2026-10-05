// ============================================================================
// track.dart — Gravação do caminho percorrido
//
// O que faz: Guarda os pontos do caminho (a cada ~15 m), ignora saltos
//   impossíveis do GPS e calcula km, tempo em movimento e velocidades média e
//   máxima.
// Quem usa: MapScreen (_recorder) para "Minhas viagens".
// Onde mexer: Filtros: add() (15 m, 70 m/s).
// ============================================================================

import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'geo.dart';
import 'radars.dart' show distanceMeters;

/// Grava o caminho percorrido e as estatísticas da viagem (função pura).
/// Fica só no celular: nada disso vai para o Firebase.
class TrackRecorder {
  final List<(double, double)> points = [];
  double distanceM = 0;
  int movingS = 0;
  double maxKmh = 0;
  DateTime? _lastTime;
  (double, double)? _last;

  /// Começa a partir de uma gravação anterior (mesma viagem reaberta).
  void seed(List<(double, double)> pts, double distance, int moving,
      double maxSpeed) {
    points
      ..clear()
      ..addAll(pts);
    _last = pts.isEmpty ? null : pts.last;
    distanceM = distance;
    movingS = moving;
    maxKmh = maxSpeed;
  }

  /// Nova leitura do GPS. [speedMs] = velocidade em m/s.
  void add(double lat, double lng, double speedMs, DateTime time) {
    final prevT = _lastTime;
    _lastTime = time;
    final dt = prevT == null
        ? 0
        : time.difference(prevT).inMilliseconds / 1000.0;
    if (speedMs > 1.5 && dt > 0 && dt <= 10) movingS += dt.round();
    final kmh = speedMs * 3.6;
    // Velocidade de GPS acima de 300 km/h é erro de leitura.
    if (kmh < 300 && kmh > maxKmh) maxKmh = kmh;

    final last = _last;
    if (last == null) {
      _last = (lat, lng);
      points.add((lat, lng));
      return;
    }
    final d = distanceMeters(last.$1, last.$2, lat, lng);
    if (d < 15) return; // parado ou "tremida" do GPS
    // Salto impossível (mais de 70 m/s desde o último ponto): ignora.
    final sinceLast = max(dt, 1.0);
    if (d / sinceLast > 70 && d > 500) return;
    distanceM += d;
    _last = (lat, lng);
    points.add((lat, lng));
  }

  double get avgKmh => movingS > 0 ? distanceM / movingS * 3.6 : 0;

  /// Caminho compactado para guardar (simplificado com 5 m de tolerância).
  String encoded() => encodePolyline(simplifyPolyline(
      [for (final (la, lo) in points) LatLng(la, lo)], 5));
}
