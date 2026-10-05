import 'package:comboio/logic/track.dart';
import 'package:comboio/models/trip_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gravação do caminho', () {
    final t0 = DateTime(2026, 10, 4, 9);

    test('soma a distância andando e ignora a "tremida" parado', () {
      final r = TrackRecorder();
      // Parado: variações de 3 m não contam.
      r.add(-28.0, -49.0, 0, t0);
      r.add(-28.00003, -49.0, 0, t0.add(const Duration(seconds: 1)));
      expect(r.distanceM, 0);
      // Andando para o sul ~111 m por leitura (≈ 40 km/h).
      for (var i = 1; i <= 10; i++) {
        r.add(-28.0 - i * 0.001, -49.0, 11, t0.add(Duration(seconds: 10 + i * 10)));
      }
      expect(r.distanceM, closeTo(1113, 10));
      // A 1ª leitura andando veio 19 s depois da anterior: intervalos acima
      // de 10 s não contam como "em movimento" (podia estar parado).
      expect(r.movingS, 90);
      expect(r.maxKmh, closeTo(39.6, 0.1));
      expect(r.avgKmh, closeTo(44.5, 0.5));
    });

    test('salto impossível do GPS é ignorado', () {
      final r = TrackRecorder();
      r.add(-28.0, -49.0, 10, t0);
      r.add(-29.0, -49.0, 10, t0.add(const Duration(seconds: 1))); // 111 km
      expect(r.distanceM, 0);
    });

    test('continua uma gravação anterior', () {
      final r = TrackRecorder()..seed([(-28.0, -49.0)], 5000, 600, 90);
      r.add(-28.001, -49.0, 15, t0);
      expect(r.distanceM, closeTo(5111, 5));
      expect(r.maxKmh, 90);
    });
  });

  test('viagem salva e lida de volta (arquivo do celular)', () {
    final rec = TripRecord(
      id: 'exp_ABC123_20261004',
      expedition: true,
      title: 'Serra',
      code: 'ABC123',
      startedAt: DateTime(2026, 10, 4, 8),
      endedAt: DateTime(2026, 10, 4, 12),
      distanceM: 180000,
      movingS: 9000,
      maxKmh: 118,
      routePolyline: 'abc',
      trackPolyline: 'def',
      stops: const [(name: 'Urubici', lat: -28.0, lng: -49.5, type: 'destination')],
    );
    final back = TripRecord.fromJson(rec.toJson())!;
    expect(back.id, rec.id);
    expect(back.code, 'ABC123');
    expect(back.distanceM, 180000);
    expect(back.avgKmh, closeTo(72, 0.1));
    expect(back.stops.single.name, 'Urubici');
    expect(TripRecord.fromJson('lixo'), isNull);
  });
}
