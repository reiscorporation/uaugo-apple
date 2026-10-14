import 'dart:convert';
import 'dart:io' as io;

import 'package:comboio/logic/find_places.dart';
import 'package:comboio/logic/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

String vosk(String text, [double conf = 1]) => jsonEncode({
      'text': text,
      'result': [
        for (final w in text.split(' ')) {'word': w, 'conf': conf}
      ],
    });

FoundPlace place(String n, double lat) =>
    FoundPlace(name: n, address: '', lat: lat, lng: -49, meters: 0);

void main() {
  test('"UauGo, procurar posto" e "procura restaurante barato"', () {
    final a = parseVoiceResult(vosk('uau go procurar posto')) as FindCommand;
    expect(a.category, FindCategory.fuel);
    expect(a.cheap, isFalse);
    final b = parseVoiceResult(vosk('uau go procura restaurante barato')) as FindCommand;
    expect(b.category, FindCategory.food);
    expect(b.cheap, isTrue);
    final c = parseVoiceResult(vosk('uau go procurar caixa eletrônico')) as FindCommand;
    expect(c.category, FindCategory.atm);
  });

  test('"barato" só onde faz sentido; pedido fora da lista vira ajuda', () {
    final p = parseVoiceResult(vosk('uau go procurar posto barato')) as FindCommand;
    expect(p.category, FindCategory.fuel);
    expect(p.cheap, isFalse); // posto não tem faixa de preço no Google
    final h = parseVoiceResult(vosk('uau go procurar [unk]')) as FindCommand;
    expect(h.category, isNull);
    expect(voiceGrammar(), contains('uau go procurar pousada barato'));
  });

  test('navegando: só o que está à frente na rota, do mais perto ao mais longe', () {
    // Rota para o norte: "along" = metros desde a saída; piloto em 5000 m.
    final r = rankFound(
      [place('atrás', 1), place('longe', 3), place('perto', 2), place('fora', 4)],
      alongOf: (lat, lng) => switch (lat) {
        1 => (along: 3000.0, offset: 50.0),
        2 => (along: 8000.0, offset: 100.0),
        3 => (along: 20000.0, offset: 0.0),
        _ => (along: 9000.0, offset: 5000.0), // 5 km fora do traçado
      },
      riderAlong: 5000,
      distanceTo: (_, __) => 0,
    );
    expect(r.map((f) => f.name), ['perto', 'longe']);
    expect(r.first.meters, 3100);
    expect(r.first.onRoute, isTrue);
  });

  test('sem rota: pela distância em linha reta', () {
    final r = rankFound([place('b', 2), place('a', 1)],
        distanceTo: (lat, _) => lat * 1000);
    expect(r.map((f) => f.name), ['a', 'b']);
  });

  test('"UauGo" + pausa: bipa e o comando seguinte vale sem a palavra de ativação', () {
    expect(parseVoiceResult(vosk('uau go')), isA<WakeCommand>());
    expect((parseVoiceResult(vosk('uau go procurar')) as WakeCommand).find, isTrue);
    const w = VoiceContext.wake;
    final r = parseVoiceResult(vosk('restaurante'), context: w) as FindCommand;
    expect(r.category, FindCategory.food);
    final b = parseVoiceResult(vosk('pizzaria barato'), context: w) as FindCommand;
    expect(b.category, FindCategory.pizza);
    expect(b.cheap, isTrue);
    expect(parseVoiceResult(vosk('procurar posto'), context: w), isA<FindCommand>());
    expect(parseVoiceResult(vosk('ir para'), context: w), isA<GoToCommand>());
    expect(parseVoiceResult(vosk('radar'), context: w), isA<ReportCommand>());
    // Sem o "UauGo" antes, a mesma palavra não faz nada.
    expect(parseVoiceResult(vosk('restaurante')), isNull);
    expect(parseVoiceResult(vosk('radar')), isNull);
    // "UauGo, procurar" + algo fora da lista: pergunta o que procura.
    final f = parseVoiceResult(vosk('[unk]'), context: VoiceContext.find) as FindCommand;
    expect(f.category, isNull);
    // "sim"/"não" continuam respostas.
    expect(parseVoiceResult(vosk('sim'), context: w), isA<AnswerCommand>());
  });

  test('pedido livre: tira "procurar uma" do começo', () {
    expect(cleanFindQuery('procurar uma pizzaria'), 'pizzaria');
    expect(cleanFindQuery('loja de moto'), 'loja de moto');
  });

  test('gramática completa para conferir no modelo de voz', () {
    io.File('build/voice_grammar.json').writeAsStringSync(voiceGrammar());
  });
}
