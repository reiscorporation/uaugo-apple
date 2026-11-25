import 'dart:typed_data';

import 'package:comboio/widgets/vehicle_sprite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vista pelo sentido na tela (esquerda = espelho)', () {
    expect(spriteView(0), (view: 0, mirror: false));
    expect(spriteView(2), (view: 2, mirror: false));
    expect(spriteView(4), (view: 3, mirror: false));
    expect(spriteView(6), (view: 2, mirror: true));
    expect(spriteView(7), (view: 1, mirror: true));
  });

  test('sentido na tela desconta o giro do mapa', () {
    expect(screenDir(90, 90), 0);
    expect(screenDir(0, 90), 6);
    expect(screenDir(350, 0), 0);
    expect(screenDir(180, 0), 4);
  });

  test('troca só a pintura', () {
    final px = Uint8List.fromList([200, 30, 30, 255, 200, 30, 30, 255]);
    final m = Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255]);
    final out = recolorPixels(px, m, 0xFF1E5BD8);
    expect(out[2] > out[0], isTrue); // virou azul
    expect(out.sublist(4), px.sublist(4)); // fora da pintura não muda
  });
}
