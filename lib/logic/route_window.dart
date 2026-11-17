// route_window.dart — Rota para a tela do carro: detalhada perto do veículo
//
// O carro recebe a rota inteira (para a visão geral), mas o Android Auto
// fica lento com muitos pontos. Perto do veículo (de 500 m atrás até 5 km à
// frente) a linha vai com 1 m de tolerância, igual ao celular; antes e
// depois, simplificada até caber no limite de pontos. Assim a linha azul do
// carro acompanha as curvas da rua onde o motorista está olhando.
//
// Onde mexer: tamanho do trecho (behindM/aheadM) e o limite (maxPoints).
import 'dart:math';

import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'geo.dart';
import 'radars.dart' show distanceMeters;

class RouteWindow {
  RouteWindow(this.points, {this.maxPoints = 4000}) : _cum = _cumulative(points);

  final List<(double, double)> points;
  final int maxPoints;
  final List<double> _cum;

  static const behindM = 500.0;
  static const aheadM = 5000.0;

  /// Início do trecho detalhado enviado por último (-1 = nenhum).
  double _from = -1;

  static List<double> _cumulative(List<(double, double)> p) {
    final out = <double>[0];
    for (var i = 1; i < p.length; i++) {
      out.add(out.last + distanceMeters(p[i - 1].$1, p[i - 1].$2, p[i].$1, p[i].$2));
    }
    return out;
  }

  double get length => _cum.last;

  /// O veículo já passou de 3/5 do trecho (ou voltou para antes dele).
  bool needsMove(double along) {
    if (_from < 0) return true;
    if (_from + behindM + aheadM >= length) return along < _from; // trecho já vai até o fim
    return along < _from || along > _from + behindM + aheadM * 0.6;
  }

  /// Rota a enviar com o veículo em [along] metros.
  List<(double, double)> build(double along) {
    if (points.length < 3) return points;
    final from = max(0.0, along - behindM);
    final to = min(length, along + aheadM);
    _from = from;
    // Índices do trecho (inclui os pontos das pontas).
    var i0 = 0;
    while (i0 + 1 < _cum.length && _cum[i0 + 1] <= from) {
      i0++;
    }
    var i1 = i0;
    while (i1 + 1 < _cum.length && _cum[i1] < to) {
      i1++;
    }
    List<LatLng> ll(int a, int b) => [
          for (var i = a; i <= b; i++) LatLng(points[i].$1, points[i].$2)
        ];
    final near = simplifyPolyline(ll(i0, i1), routeToleranceM);
    var before = <LatLng>[], after = <LatLng>[];
    for (final tol in [2.0, 4.0, 8.0, 16.0, 32.0]) {
      before = i0 > 0 ? simplifyPolyline(ll(0, i0), tol) : <LatLng>[];
      after = i1 < points.length - 1 ? simplifyPolyline(ll(i1, points.length - 1), tol) : <LatLng>[];
      if (before.length + near.length + after.length <= maxPoints) break;
    }
    return [
      // As pontas se repetem entre as partes: tira o repetido.
      for (final p in before.isEmpty ? before : before.sublist(0, before.length - 1))
        (p.latitude, p.longitude),
      for (final p in near) (p.latitude, p.longitude),
      for (final p in after.isEmpty ? after : after.sublist(1)) (p.latitude, p.longitude),
    ];
  }
}
