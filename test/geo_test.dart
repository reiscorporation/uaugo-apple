import 'package:comboio/logic/geo.dart';
import 'package:comboio/services/hazard_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Direção', () {
    test('norte, leste, sul e oeste', () {
      expect(bearingBetween(0, 0, 1, 0), closeTo(0, 0.5));
      expect(bearingBetween(0, 0, 0, 1), closeTo(90, 0.5));
      expect(bearingBetween(0, 0, -1, 0), closeTo(180, 0.5));
      expect(bearingBetween(0, 0, 0, -1), closeTo(270, 0.5));
    });

    test('diferença de ângulo atravessa o 0°', () {
      expect(angleDiff(350, 10), closeTo(20, 1e-9));
      expect(angleDiff(10, 350), closeTo(20, 1e-9));
      expect(angleDiff(0, 180), closeTo(180, 1e-9));
    });
  });

  group('Alerta à frente (RN-07)', () {
    // Piloto em (0,0) indo para o norte (heading 0) a 20 m/s.
    bool ahead(double tLat, double tLng, {double speed = 20}) => isAhead(
          lat: 0,
          lng: 0,
          heading: 0,
          speed: speed,
          targetLat: tLat,
          targetLng: tLng,
        );

    test('alerta ao norte está à frente', () => expect(ahead(0.003, 0), isTrue));
    test('alerta ao sul ficou para trás', () => expect(ahead(-0.003, 0), isFalse));
    test('alerta a leste (90°) não está à frente', () => expect(ahead(0, 0.003), isFalse));
    test('parado, avisa em qualquer direção', () => expect(ahead(-0.003, 0, speed: 0), isTrue));
  });

  group('Votos (RN-06)', () {
    test('primeiro voto contra com 1 confirmação remove? não', () {
      expect(shouldRemoveHazard(confirmations: 1, dismissals: 0), isFalse);
    });
    test('segundo voto contra remove', () {
      expect(shouldRemoveHazard(confirmations: 5, dismissals: 1), isTrue);
    });
    test('voto contra sem confirmações remove', () {
      expect(shouldRemoveHazard(confirmations: 0, dismissals: 0), isTrue);
    });
    test('autor pode remover o próprio alerta', () {
      expect(shouldRemoveHazard(confirmations: 9, dismissals: 0, force: true), isTrue);
    });
  });

  group('Polyline do Google', () {
    test('decodifica o exemplo oficial', () {
      final pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(pts.length, 3);
      expect(pts[0].latitude, closeTo(38.5, 1e-5));
      expect(pts[0].longitude, closeTo(-120.2, 1e-5));
      expect(pts[2].latitude, closeTo(43.252, 1e-5));
      expect(pts[2].longitude, closeTo(-126.453, 1e-5));
    });
  });

  group('Células geográficas', () {
    test('célula de 0,1 grau', () {
      final (la, lo) = HazardService.cellOf(-23.5505, -46.6333);
      expect(HazardService.cellKey(la, lo), '-236_-467');
    });
  });
}
