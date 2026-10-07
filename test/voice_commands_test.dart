import 'dart:convert';

import 'package:comboio/logic/voice_commands.dart';
import 'package:comboio/models/hazard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta um resultado no formato do Vosk.
String vosk(String text, [double conf = 1]) => jsonEncode({
      'text': text,
      'result': [
        for (final w in text.split(' ')) {'word': w, 'conf': conf}
      ],
    });

void main() {
  group('Comandos de voz', () {
    test('"roda junto radar" marca radar', () {
      final c = parseVoiceResult(vosk('roda junto radar'));
      expect(c, isA<ReportCommand>());
      expect((c as ReportCommand).type, HazardType.radar);
    });

    test('todos os alertas da lista são reconhecidos', () {
      voiceAlertWords.forEach((word, type) {
        final c = parseVoiceResult(vosk('roda junto $word'));
        expect((c as ReportCommand).type, type, reason: word);
      });
    });

    test('cancelar', () {
      expect(parseVoiceResult(vosk('roda junto cancelar')), isA<CancelCommand>());
    });

    test('sem a palavra de ativação não faz nada', () {
      expect(parseVoiceResult(vosk('radar')), isNull);
      expect(parseVoiceResult(vosk('junto polícia roda área')), isNull);
    });

    test('pedaço de conversa ([unk]) é ignorado', () {
      expect(parseVoiceResult(vosk('radar [unk] de de [unk]')), isNull);
      expect(parseVoiceResult(vosk('')), isNull);
    });

    test('confiança baixa é ignorada', () {
      expect(parseVoiceResult(vosk('roda junto radar', 0.4)), isNull);
    });

    test('sim/não exigem confiança alta', () {
      expect((parseVoiceResult(vosk('sim', 0.97)) as AnswerCommand).yes, isTrue);
      expect((parseVoiceResult(vosk('não', 0.9)) as AnswerCommand).yes, isFalse);
      // Caso real do teste com ruído: conversa virou "não" com 0,74.
      expect(parseVoiceResult(vosk('não', 0.74)), isNull);
    });

    test('a gramática tem todas as frases e o [unk]', () {
      final g = (jsonDecode(voiceGrammar()) as List).cast<String>();
      expect(g, containsAll(['roda junto radar', 'roda junto área de risco',
          'roda junto cancelar', 'sim', 'não', '[unk]']));
    });

    test('JSON inválido não quebra', () {
      expect(parseVoiceResult('isto não é json'), isNull);
    });
  });
}
