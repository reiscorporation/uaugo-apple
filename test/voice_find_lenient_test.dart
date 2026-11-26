import 'package:comboio/logic/find_places.dart';
import 'package:comboio/logic/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('busca falada do jeito que a Apple escreve (iPhone)', () {
    FindCategory? cat(String s, {VoiceContext? ctx}) =>
        lenientFind(s, context: ctx)?.category;
    expect(cat('uau go procure um posto de gasolina'), FindCategory.fuel);
    expect(cat('uau go onde tem uma farmácia'), FindCategory.pharmacy);
    expect(cat('uau go procurar restaurante'), FindCategory.food);
    expect(lenientFind('uau go procurar restaurante barato')!.cheap, isTrue);
    expect(cat('uau go quero parar num hotel'), FindCategory.lodging);
    expect(cat('uau go procurar hambúrguer'), FindCategory.burger);
    // Depois de "UauGo" + pausa: só a categoria.
    expect(cat('posto', ctx: VoiceContext.find), FindCategory.fuel);
    // Verbo sem categoria conhecida: pergunta o que procura.
    final x = lenientFind('uau go procurar uma loja de roupa');
    expect(x, isNotNull);
    expect(x!.category, isNull);
    // Não é busca.
    expect(lenientFind('uau go radar'), isNull);
    expect(lenientFind('uau go cancelar parada'), isNull);
    expect(lenientFind('uau go ir para casa'), isNull);
    expect(lenientFind('procurar posto'), isNull); // sem "UauGo" e sem contexto
  });

  test('o JSON do iPhone com "raw" chega como busca', () {
    final c = parseVoiceResult(
        '{"text":"uau go procurar [unk] posto [unk] gasolina","result":[],"raw":"uau go procure um posto de gasolina"}');
    expect(c, isA<FindCommand>());
    expect((c as FindCommand).category, FindCategory.fuel);
  });
}
