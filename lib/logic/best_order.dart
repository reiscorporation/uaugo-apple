// ============================================================================
// best_order.dart — Melhor sequência para visitar vários destinos
//
// O que faz: Dada a saída e uma lista de destinos ("quero ir a Curitiba,
//   Serra do Rio do Rastro, Campinas e São Paulo" ou 5 endereços na cidade),
//   devolve as ordens de visita mais curtas (em linha reta), para o app
//   calcular de verdade (Google, com trânsito) e ficar com a mais rápida.
//   Até 8 destinos testa todas as ordens; acima disso, vizinho mais próximo +
//   melhoria 2-opt.
// Quem usa: TripPreviewSheet (botão "Melhor sequência").
// Onde mexer: o fim é livre (termina no destino que fizer a rota mais curta).
// ============================================================================

import 'radars.dart' show distanceMeters;

/// Ordens (índices de [dests]) da mais curta para a mais longa, no máximo
/// [count]. [origin] e [dests] são (lat, lng).
List<List<int>> bestOrders((double, double) origin, List<(double, double)> dests,
    {int count = 3}) {
  final n = dests.length;
  if (n <= 1) return [List.generate(n, (i) => i)];
  double d((double, double) a, (double, double) b) =>
      distanceMeters(a.$1, a.$2, b.$1, b.$2);
  final fromOrigin = [for (final p in dests) d(origin, p)];
  final m = [
    for (final a in dests) [for (final b in dests) d(a, b)]
  ];
  double cost(List<int> o) {
    var c = fromOrigin[o.first];
    for (var i = 1; i < o.length; i++) {
      c += m[o[i - 1]][o[i]];
    }
    return c;
  }

  final found = <(double, List<int>)>[];
  void keep(List<int> o) {
    final c = cost(o);
    if (found.any((f) => _same(f.$2, o))) return;
    found.add((c, List.of(o)));
    found.sort((a, b) => a.$1.compareTo(b.$1));
    if (found.length > count) found.removeLast();
  }

  if (n <= 8) {
    _permute(List.generate(n, (i) => i), 0, keep);
  } else {
    // vizinho mais próximo a partir de cada destino como 1º, depois 2-opt
    for (var first = 0; first < n; first++) {
      final o = [first];
      final left = {for (var i = 0; i < n; i++) i}..remove(first);
      while (left.isNotEmpty) {
        final last = o.last;
        final next = left.reduce((a, b) => m[last][a] <= m[last][b] ? a : b);
        o.add(next);
        left.remove(next);
      }
      keep(_twoOpt(o, cost));
    }
  }
  return [for (final f in found) f.$2];
}

bool _same(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _permute(List<int> a, int k, void Function(List<int>) out) {
  if (k == a.length) return out(a);
  for (var i = k; i < a.length; i++) {
    final t = a[k];
    a[k] = a[i];
    a[i] = t;
    _permute(a, k + 1, out);
    a[i] = a[k];
    a[k] = t;
  }
}

List<int> _twoOpt(List<int> o, double Function(List<int>) cost) {
  var best = List.of(o), bc = cost(best), improved = true;
  while (improved) {
    improved = false;
    for (var i = 0; i < best.length - 1; i++) {
      for (var j = i + 1; j < best.length; j++) {
        final c = [
          ...best.sublist(0, i),
          ...best.sublist(i, j + 1).reversed,
          ...best.sublist(j + 1)
        ];
        final cc = cost(c);
        if (cc + 1e-6 < bc) {
          best = c;
          bc = cc;
          improved = true;
        }
      }
    }
  }
  return best;
}
