import 'package:comboio/logic/rodizio.dart';
import 'package:comboio/models/bike.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('final da placa e dia do rodízio', () {
    expect(plateDigit('ABC1D23'), 3);
    expect(plateDigit('abc-1230'), 0);
    expect(plateDigit('ABC'), isNull);
    expect(rodizioWeekday(2), DateTime.monday);
    expect(rodizioWeekday(0), DateTime.friday);
  });

  test('horário e feriado', () {
    // 2026-10-19 é segunda-feira.
    expect(rodizioNow(1, DateTime(2026, 10, 19, 8, 30)), isTrue);
    expect(rodizioNow(1, DateTime(2026, 10, 19, 12, 0)), isFalse);
    expect(rodizioNow(1, DateTime(2026, 10, 19, 19, 59)), isTrue);
    expect(rodizioNow(3, DateTime(2026, 10, 19, 8, 30)), isFalse);
    // 2026-10-12 (segunda, feriado): não vale.
    expect(rodizioNow(1, DateTime(2026, 10, 12, 8, 30)), isFalse);
  });

  test('área do centro expandido', () {
    expect(insideCentroExpandido(-23.5614, -46.6559), isTrue); // Av. Paulista
    expect(insideCentroExpandido(-23.5505, -46.6333), isTrue); // Sé
    expect(insideCentroExpandido(-23.6500, -46.7000), isFalse); // Santo Amaro
    expect(insideCentroExpandido(-21.1775, -47.8103), isFalse); // Ribeirão Preto
  });

  test('aviso só para carro, no dia, com rota pela área', () {
    final pela = [(-23.60, -46.80), (-23.5614, -46.6559), (-23.50, -46.50)];
    final fora = [(-21.17, -47.81), (-21.20, -47.80)];
    final seg = DateTime(2026, 10, 19, 9);
    expect(rodizioWarning(plate: 'ABC1D21', style: BikeStyle.car, route: pela, when: seg),
        contains('placa final 1'));
    expect(rodizioWarning(plate: 'ABC1D21', style: BikeStyle.adventure, route: pela, when: seg),
        isNull); // moto não participa
    expect(rodizioWarning(plate: 'ABC1D21', style: BikeStyle.car, route: fora, when: seg),
        isNull);
  });
}
