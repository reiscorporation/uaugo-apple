import 'package:comboio/logic/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alerta marcado indo para o norte não avisa quem vai para o sul', () {
    expect(sameDirection(0, 180, 20), isFalse);
    expect(sameDirection(0, 350, 20), isTrue); // curva leve
    expect(sameDirection(90, 140, 20), isTrue); // 50° conta como o mesmo
    expect(sameDirection(90, 160, 20), isFalse);
  });
  test('sem o sentido do alerta ou com o piloto parado, avisa todos', () {
    expect(sameDirection(null, 180, 20), isTrue);
    expect(sameDirection(0, 180, 1), isTrue);
  });
}
