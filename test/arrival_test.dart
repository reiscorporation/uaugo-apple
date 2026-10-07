import 'package:comboio/logic/navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chegada na parada/destino', () {
    test('caso real: 300 m em linha reta, mas 1 km pela estrada -> NÃO chegou', () {
      expect(
          hasArrived(
              straight: 300, riderAlong: 9000, riderOffset: 10, stopAlong: 10000),
          isFalse);
    });

    test('a 50 m pela rota -> chegou', () {
      expect(
          hasArrived(
              straight: 45, riderAlong: 9950, riderOffset: 8, stopAlong: 10000),
          isTrue);
    });

    test('passou um pouco do ponto -> conta como chegada', () {
      expect(
          hasArrived(
              straight: 60, riderAlong: 10040, riderOffset: 8, stopAlong: 10000),
          isTrue);
    });

    test('traçado que volta perto de si mesmo: pela rota perto, mas longe em linha reta', () {
      expect(
          hasArrived(
              straight: 900, riderAlong: 9960, riderOffset: 8, stopAlong: 10000),
          isFalse);
    });

    test('fora da rota: usa linha reta, só bem perto', () {
      expect(hasArrived(straight: 300, riderAlong: 9000, riderOffset: 400, stopAlong: 10000),
          isFalse);
      expect(hasArrived(straight: 100, riderAlong: 9000, riderOffset: 400, stopAlong: 10000),
          isTrue);
    });

    test('sem traçado: linha reta a até 120 m', () {
      expect(hasArrived(straight: 150), isFalse);
      expect(hasArrived(straight: 110), isTrue);
    });

    test('distância para o aviso "faltam 2 km" também é pela rota', () {
      final d = distanceToStop(
          straight: 800, riderAlong: 3000, riderOffset: 20, stopAlong: 5000);
      expect(d.byRoute, isTrue);
      expect(d.meters, 2000);
    });
  });
}
