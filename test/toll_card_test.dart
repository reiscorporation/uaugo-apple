import 'package:comboio/logic/tolls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fed = TollPlaza([(-21.1, -47.8)], 10.5, 0.5, 40); // valor da ANTT
  const est = TollPlaza([(-22.2, -47.1)], 12.0, 0.5, 40, source: TollSource.estimated);
  const semValor = TollPlaza([(-23.3, -46.6)], null, null, 40);

  tearDown(() => TollCards.byKey = const {});

  test('federal (ANTT): débito e crédito pela regra da ANTT', () {
    expect(fed.card, TollCard.debitCredit);
    expect(tollCardNote(fed), contains('débito e crédito'));
  });

  test('estadual: só com a tabela; sem informação não mostra nada', () {
    expect(est.card, isNull);
    expect(tollCardNote(est), '');
    expect(semValor.card, isNull);
    TollCards.byKey = {est.key: 'd'};
    expect(est.card, TollCard.debitOnly);
  });

  test('resumo da rota', () {
    expect(tollCardsSummary([est]), '');
    expect(tollCardsSummary([fed, fed]), contains('Todas as 2'));
    TollCards.byKey = {est.key: 'd'};
    final s = tollCardsSummary([fed, est, semValor]);
    expect(s, contains('1 débito e crédito'));
    expect(s, contains('1 só débito'));
    expect(s, contains('1 sem informação'));
  });
}
