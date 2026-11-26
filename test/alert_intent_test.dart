import 'package:flutter_test/flutter_test.dart';
import 'package:comboio/logic/alert_intent.dart';
import 'package:comboio/models/hazard.dart';

void main() {
  test('ordem da tela de alertas', () {
    final o = alertSheetOrder;
    expect(o.take(9), [
      HazardType.police,
      HazardType.fixedRadar,
      HazardType.oil,
      HazardType.animal,
      HazardType.kite,
      HazardType.pothole,
      HazardType.danger,
      HazardType.roadworks, // 26/11
      HazardType.risk,
    ]);
    // Nenhuma categoria some.
    expect(o.toSet(), HazardType.values.toSet());
    expect(o.length, HazardType.values.length);
  });

  test('frases do pedido de 23/11', () {
    final cases = {
      'Óleo': HazardType.oil,
      'Tem óleo na pista': HazardType.oil,
      'Obras na pista': HazardType.roadworks,
      'tem obra ali': HazardType.roadworks,
      'Areia na pista': HazardType.oil,
      'Polícia': HazardType.police,
      'Tem polícia à frente': HazardType.police,
      'Radar': HazardType.fixedRadar,
      'Animal na pista': HazardType.animal,
      'Cachorro na pista': HazardType.animal,
      'Pipa': HazardType.kite,
      'Cerol': HazardType.kite,
      'Buraco': HazardType.pothole,
      'Pista perigosa': HazardType.risk,
      'Risco na pista': HazardType.danger,
    };
    cases.forEach((said, type) =>
        expect(alertFromSpeech(said), type, reason: said));
  });

  test('expressão mais longa vence', () {
    expect(alertFromSpeech('radar móvel ali'), HazardType.radar);
    expect(alertFromSpeech('batida policial'), HazardType.police);
    expect(alertFromSpeech('uma batida feia'), HazardType.accident);
    expect(alertFromSpeech('lombada eletrônica'), HazardType.fixedRadar);
    expect(alertFromSpeech('perigo na pista'), HazardType.danger);
  });

  test('não reconhece', () {
    expect(alertFromSpeech(null), isNull);
    expect(alertFromSpeech(''), isNull);
    expect(alertFromSpeech('que paisagem linda'), isNull);
    // "perigosa" não aciona "perigo" (palavra inteira).
    expect(alertFromSpeech('perigosamente'), isNull);
  });
}
