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
  group('Comandos de voz (UauGo)', () {
    test('"UauGo, radar" (reconhecido como "uau go radar") marca radar', () {
      final c = parseVoiceResult(vosk('uau go radar'));
      expect(c, isA<ReportCommand>());
      expect((c as ReportCommand).type, HazardType.radar);
    });

    test('todos os alertas da lista são reconhecidos', () {
      voiceAlertWords.forEach((word, type) {
        final c = parseVoiceResult(vosk('uau go $word'));
        expect((c as ReportCommand).type, type, reason: word);
      });
    });

    test('cancelar', () {
      expect(parseVoiceResult(vosk('uau go cancelar')), isA<CancelCommand>());
    });

    test('[unk] no começo (silêncio antes de falar) é ignorado', () {
      final c = parseVoiceResult(vosk('[unk] uau go lombada'));
      expect((c as ReportCommand).type, HazardType.bump);
    });

    test('exclamações com "uau" não disparam nada', () {
      for (final t in [
        'uau radar', // sem o "go"
        'uau [unk]', // "uau, que paisagem linda"
        'uau que [unk]',
        'uau olha [unk]',
        'uau go [unk]',
        'radar',
      ]) {
        expect(parseVoiceResult(vosk(t)), isNull, reason: t);
      }
    });

    test('pedaço de conversa ([unk] no meio) é ignorado', () {
      expect(parseVoiceResult(vosk('uau go [unk] radar')), isNull);
      expect(parseVoiceResult(vosk('')), isNull);
    });

    test('confiança baixa é ignorada', () {
      expect(parseVoiceResult(vosk('uau go radar', 0.4)), isNull);
    });

    test('sim/não exigem confiança alta', () {
      expect((parseVoiceResult(vosk('sim', 0.97)) as AnswerCommand).yes, isTrue);
      expect((parseVoiceResult(vosk('não', 0.9)) as AnswerCommand).yes, isFalse);
      // Caso real do teste com ruído: conversa virou "não" com 0,74.
      expect(parseVoiceResult(vosk('não', 0.74)), isNull);
    });

    test('a gramática tem os comandos, as exclamações e o [unk]', () {
      final g = (jsonDecode(voiceGrammar()) as List).cast<String>();
      expect(g, containsAll(['uau go radar', 'uau go área de risco',
          'uau go cancelar', 'uau [unk]', 'sim', 'não', '[unk]']));
    });

    test('JSON inválido não quebra', () {
      expect(parseVoiceResult('isto não é json'), isNull);
    });
  });
}
