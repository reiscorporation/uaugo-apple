import 'package:comboio/logic/costs.dart';
import 'package:comboio/logic/map_style.dart';
import 'package:comboio/logic/pois.dart';
import 'package:comboio/models/trip_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('consumo e gastos', () {
    test('combustível estimado', () {
      // 300 km a 25 km/l = 12 L; a R$ 6,50 = R$ 78,00.
      expect(fuelLiters(300000, 25), 12);
      expect(fuelCost(300000, 25, 6.5), closeTo(78, 1e-9));
      expect(fuelLiters(300000, 0), 0); // sem consumo informado
    });

    test('consumo real pelos abastecimentos', () {
      final at = DateTime(2026, 10, 5);
      final e = [
        Expense(kind: ExpenseKind.fuel, value: 60, liters: 9, at: at),
        Expense(kind: ExpenseKind.fuel, value: 40, liters: 6, at: at),
        Expense(kind: ExpenseKind.toll, value: 8.4, at: at),
      ];
      expect(realKmPerLiter(300000, e), 20); // 300 km / 15 L
      expect(totalOf(e), closeTo(108.4, 1e-9));
    });

    test('formatação em reais e leitura de números', () {
      expect(formatMoney(1234.5), r'R$ 1.234,50');
      expect(formatMoney(7), r'R$ 7,00');
      expect(parseDecimal('12,5'), 12.5);
      expect(parseDecimal('R\$ 6.49'), 6.49);
      expect(parseDecimal('abc'), isNull);
    });

    test('gastos ficam salvos na viagem', () {
      final r = TripRecord(
        id: 'x',
        expedition: true,
        title: 'Serra',
        startedAt: DateTime(2026, 10, 5, 8),
        endedAt: DateTime(2026, 10, 5, 12),
        distanceM: 100000,
        movingS: 3600,
        maxKmh: 100,
        riders: 4,
        expenses: [
          Expense(
              kind: ExpenseKind.lodging,
              value: 400,
              note: 'pousada',
              at: DateTime(2026, 10, 5)),
        ],
      );
      final back = TripRecord.fromJson(r.toJson())!;
      expect(back.riders, 4);
      expect(back.expenses.single.kind, ExpenseKind.lodging);
      expect(back.expenses.single.note, 'pousada');
    });
  });

  group('mapa noturno (pôr do sol)', () {
    // Florianópolis, 5/out: Sol nasce ~5h40 e se põe ~18h20 (UTC-3).
    const lat = -27.59, lng = -48.55;
    test('meio-dia é dia, meia-noite é noite', () {
      expect(isNight(DateTime.utc(2026, 10, 5, 15), lat, lng), isFalse);
      expect(isNight(DateTime.utc(2026, 10, 6, 3), lat, lng), isTrue);
    });
    test('escurece logo depois do pôr do sol', () {
      expect(isNight(DateTime.utc(2026, 10, 5, 20, 0), lat, lng), isFalse); // 17h
      expect(isNight(DateTime.utc(2026, 10, 5, 22, 0), lat, lng), isTrue); // 19h
    });
  });

  test('pedágio: moto paga ou isenta', () {
    final idx = PoiIndex.fromCompact([-2800000, -4900000, 3, -1000, 0, 4]);
    final kinds = idx.near(-28.005, -49.0, 1000).map((p) => p.kind).toSet();
    expect(kinds, {PoiKind.toll, PoiKind.tollMotoFree});
    expect(PoiKind.toll.isToll, isTrue);
    expect(PoiKind.bump.isToll, isFalse);
  });
}
