import 'package:comboio/logic/speech.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distância falada', () {
    test('metros arredondados', () {
      expect(spokenDistance(43), '50 metros');
      expect(spokenDistance(180), '200 metros');
      expect(spokenDistance(412), '400 metros');
      expect(spokenDistance(930), '900 metros');
    });

    test('quilômetros por extenso', () {
      expect(spokenDistance(1000), '1 quilômetro');
      expect(spokenDistance(1020), '1 quilômetro');
      expect(spokenDistance(1500), '1 quilômetro e meio');
      expect(spokenDistance(2000), '2 quilômetros');
      expect(spokenDistance(2600), '2 quilômetros e meio');
    });
  });

  group('avisos repetidos até o ponto', () {
    test('distâncias divididas igualmente', () {
      expect(alertThresholds(1000, 1), [1000]);
      expect(alertThresholds(1000, 2), [1000, 500]);
      expect(alertThresholds(900, 3), [900, 600, 300]);
    });

    test('fala cada aviso uma vez, na hora certa', () {
      final t = alertThresholds(1000, 2);
      expect(nextAlert(1200, 0, t), isNull); // ainda longe
      expect(nextAlert(980, 0, t), 1); // 1º aviso
      expect(nextAlert(700, 1, t), isNull); // entre os dois
      expect(nextAlert(480, 1, t), 2); // 2º aviso
      expect(nextAlert(200, 2, t), isNull); // já avisou tudo
    });

    test('se pular dois pontos de uma vez, fala uma vez só', () {
      final t = alertThresholds(1000, 3);
      expect(nextAlert(300, 0, t), 3);
    });
  });

  test('frases dos avisos', () {
    expect(hazardSpeech('radar móvel', 1000),
        'Atenção: radar móvel a 1 quilômetro');
    expect(sosSpeech('João', 2000), 'S O S: João pediu ajuda, a 2 quilômetros');
    expect(sosSpeech('João', null), 'S O S: João pediu ajuda');
    expect(nextStopSpeech('Posto Shell', 2000),
        'Próxima parada: Posto Shell, a 2 quilômetros');
    expect(arrivalSpeech('Urubici', isDestination: true),
        'Você chegou ao destino: Urubici');
    expect(arrivalSpeech('Posto', isDestination: false), 'Chegando em Posto');
  });
}
