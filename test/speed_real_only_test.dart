import 'package:comboio/logic/speed.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formato compacto a partir de pontos absolutos (lat, lng em graus).
List<int> _compact(List<(double, double, int, int)> pts) {
  final out = <int>[];
  var la = 0, lo = 0;
  for (final (lat, lng, lim, est) in pts) {
    final a = (lat * 1e5).round(), b = (lng * 1e5).round();
    out.addAll([a - la, b - lo, lim, est, -1]);
    la = a;
    lo = b;
  }
  return out;
}

void main() {
  // Rua com limite estimado (~60) e, 500 m adiante, avenida com placa de 40.
  final d = _compact([(-21.1800, -47.8100, 60, 1), (-21.1850, -47.8100, 40, 0)]);

  test('só placas reais: sem placa, sem limite (17/11)', () {
    final idx = SpeedLimitIndex.fromCompact(d, realOnly: true);
    expect(idx.length, 1);
    expect(idx.lookup(-21.1800, -47.8100), isNull);
    // As coordenadas continuam certas depois do ponto pulado.
    expect(idx.lookup(-21.1850, -47.8100), const RoadLimit(40, false));
  });

  test('sem o filtro, o estimado continua (testes antigos)', () {
    final idx = SpeedLimitIndex.fromCompact(d);
    expect(idx.length, 2);
    expect(idx.lookup(-21.1800, -47.8100), const RoadLimit(60, true));
  });
}
