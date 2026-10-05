import 'package:comboio/logic/simulation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Linha reta para o sul: 0,01° de latitude ≈ 1.113 m por trecho.
  final w = RouteWalker(const [
    (-28.00, -49.0),
    (-28.01, -49.0),
    (-28.02, -49.0),
  ]);

  test('comprimento do traçado', () {
    expect(w.length, closeTo(2226, 5));
  });

  test('posição e direção ao longo do caminho', () {
    final start = w.at(0);
    expect(start.lat, -28.00);
    final mid = w.at(w.length / 2);
    expect(mid.lat, closeTo(-28.01, 1e-6));
    expect(mid.bearing, closeTo(180, 0.5)); // indo para o sul
    final past = w.at(w.length + 500); // não passa do fim
    expect(past.lat, closeTo(-28.02, 1e-9));
  });

  test('projeção rápida (só perto da última posição) dá o mesmo resultado', () {
    final full = w.project(-28.0101, -49.0001);
    final near = w.project(-28.0101, -49.0001, around: 1100);
    expect(near.along, closeTo(full.along, 0.01));
    expect(near.offset, closeTo(full.offset, 0.01));
    // Longe do trecho indicado: refaz a busca na rota toda.
    final far = w.project(-28.0101, -49.0001, around: 0);
    expect(far.along, closeTo(full.along, 0.01));
  });

  test('quanto falta para chegar', () {
    expect(w.remainingFrom(-28.0, -49.0), closeTo(2226, 5));
    expect(w.remainingFrom(-28.0101, -49.0001), closeTo(1113, 5));
    expect(w.remainingFrom(-28.02, -49.0), 0);
  });
}
