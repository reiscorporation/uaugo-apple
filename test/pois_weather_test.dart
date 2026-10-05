import 'package:comboio/logic/pois.dart';
import 'package:comboio/logic/weather.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lombadas e postos policiais', () {
    // Lombada em (-28.00000, -49.00000) e posto 2 km ao sul.
    final idx = PoiIndex.fromCompact([
      -2800000, -4900000, 1,
      -200, 0, 2, // 0,002° ao sul (~220 m)
      -1600, 0, 2, // mais 0,016° (~1,8 km)
    ]);

    test('lê o formato compacto', () {
      expect(idx.length, 3);
    });

    test('busca só o que está perto', () {
      final near = idx.near(-28.0005, -49.0, 300);
      expect(near.map((p) => p.kind), containsAll([PoiKind.bump, PoiKind.policePost]));
      expect(near.length, 2);
      expect(idx.near(-28.0185, -49.0, 100).single.kind, PoiKind.policePost);
    });
  });

  group('chuva', () {
    test('classifica pelo código do tempo e pela quantidade', () {
      expect(rainLevel(3, 0), RainLevel.none); // nublado
      expect(rainLevel(51, 0.1), RainLevel.light); // garoa
      expect(rainLevel(63, 1.0), RainLevel.moderate);
      expect(rainLevel(65, 3.0), RainLevel.heavy);
      expect(rainLevel(95, 0), RainLevel.storm);
    });

    test('frase falada', () {
      expect(rainSpeech(RainLevel.heavy, 4000),
          'Chuva forte a aproximadamente 4 quilômetros à frente');
    });
  });
}
