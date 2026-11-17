import 'dart:math';

import 'package:comboio/logic/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Curva suave de avenida (raio 150 m, 60°), um ponto a cada 2 m: quanto a
/// linha azul simplificada se afasta da rua desenhada no mapa (16/11: na
/// Av. Leão XIII a linha virava reta + dobra com 4 m de tolerância).
void main() {
  const lat0 = -21.189, lng0 = -47.774;
  final kx = 111320 * cos(lat0 * pi / 180), ky = 110540.0;

  List<LatLng> curve() {
    const r = 150.0;
    return [
      for (var a = 0.0; a <= pi / 3; a += 2 / r)
        LatLng(lat0 + r * sin(a) / ky, lng0 + r * (1 - cos(a)) / kx)
    ];
  }

  double maxGap(List<LatLng> full, List<LatLng> s) {
    var worst = 0.0;
    for (final p in full) {
      var best = double.infinity;
      for (var i = 0; i + 1 < s.length; i++) {
        final ax = s[i].longitude * kx, ay = s[i].latitude * ky;
        final bx = s[i + 1].longitude * kx, by = s[i + 1].latitude * ky;
        final px = p.longitude * kx, py = p.latitude * ky;
        final dx = bx - ax, dy = by - ay;
        final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
        best = min(best, sqrt(pow(px - ax - t * dx, 2) + pow(py - ay - t * dy, 2)));
      }
      worst = max(worst, best);
    }
    return worst;
  }

  test('linha da rota fica a menos de 1 m da curva', () {
    final c = curve();
    for (final tol in [4.0, routeToleranceM]) {
      final s = simplifyPolyline(c, tol);
      // ignore: avoid_print
      print('tolerância $tol m: ${s.length} de ${c.length} pontos, '
          'afastamento máx ${maxGap(c, s).toStringAsFixed(2)} m');
    }
    expect(maxGap(c, simplifyPolyline(c, routeToleranceM)), lessThan(1.05));
  });
}
