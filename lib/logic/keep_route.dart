// keep_route.dart — Manter o caminho que o piloto escolheu
//
// Na prévia o piloto escolhe uma das opções de rota (ex.: "via Av. X").
// Quando ele sai da rota, o recálculo pedia a rota de novo e o Google
// devolvia a opção padrão (a mais rápida de carro): o caminho escolhido se
// perdia (testador motoboy, 16/11: "mesmo selecionando o caminho").
//
// Solução: marca pontos de passagem no meio de cada trecho em que a rota
// escolhida se afasta da padrão. O recálculo já respeita pontos de passagem
// (TripService.viasAhead): segue pelo caminho escolhido.
//
// Onde mexer: distância que conta como "outro caminho" (minGapM) e o
// máximo de pontos (maxVias; cada ponto é uma parada a mais na consulta).
import 'dart:math';

import 'radars.dart' show distanceMeters;

/// Pontos de passagem que mantêm [chosen] em vez de [main] (listas de
/// (lat, lng)). Vazio se os dois caminhos são praticamente iguais.
List<(double, double)> distinctiveVias(
  List<(double, double)> chosen,
  List<(double, double)> main, {
  int maxVias = 6,
  double minGapM = 120,
  double stepM = 40,
}) {
  if (chosen.length < 2 || main.length < 2) return const [];
  final c = _resample(chosen, stepM);
  final m = _resample(main, stepM);
  // Grade de ~300 m com os pontos da rota padrão (busca rápida).
  const cell = 0.003;
  String key(double la, double lo) => '${(la / cell).floor()}:${(lo / cell).floor()}';
  final grid = <String, List<(double, double)>>{};
  for (final p in m) {
    (grid[key(p.$1, p.$2)] ??= []).add(p);
  }
  double gap(double la, double lo) {
    final cy = (la / cell).floor(), cx = (lo / cell).floor();
    var best = double.infinity;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        for (final q in grid['${cy + dy}:${cx + dx}'] ?? const <(double, double)>[]) {
          best = min(best, distanceMeters(la, lo, q.$1, q.$2));
        }
      }
    }
    return best; // infinito = longe de tudo (> ~300 m)
  }

  // Trechos seguidos da rota escolhida longe da padrão.
  final runs = <(int, int)>[];
  int? start;
  for (var i = 0; i < c.length; i++) {
    final far = gap(c[i].$1, c[i].$2) > minGapM;
    if (far) {
      start ??= i;
    } else if (start != null) {
      runs.add((start, i - 1));
      start = null;
    }
  }
  if (start != null) runs.add((start, c.length - 1));
  if (runs.isEmpty) return const [];
  // Muitos trechos: fica com os mais longos (na ordem do caminho).
  var keep = runs;
  if (runs.length > maxVias) {
    final byLen = [...runs]..sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
    final top = byLen.take(maxVias).toSet();
    keep = [for (final r in runs) if (top.contains(r)) r];
  }
  return [for (final (a, b) in keep) c[(a + b) ~/ 2]];
}

/// Pontos a cada [step] metros ao longo do traçado.
List<(double, double)> _resample(List<(double, double)> pts, double step) {
  final out = <(double, double)>[pts.first];
  var carry = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final a = pts[i - 1], b = pts[i];
    final d = distanceMeters(a.$1, a.$2, b.$1, b.$2);
    if (d <= 0) continue;
    var t = step - carry;
    while (t <= d) {
      final f = t / d;
      out.add((a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f));
      t += step;
    }
    carry = d - (t - step);
  }
  out.add(pts.last);
  return out;
}
