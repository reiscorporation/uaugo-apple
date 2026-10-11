import 'package:comboio/logic/tolls.dart';
import 'package:comboio/models/bike.dart';
import 'package:flutter_test/flutter_test.dart';

String money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

void main() {
  // Rota reta para o norte, de -26,0 a -25,0 (~111 km).
  final line = [for (var i = 0; i <= 100; i++) (-26.0 + i * 0.01, -49.0)];

  const a = TollPlaza([(-25.8, -49.0)], 10, 0.5, 40); // federal, moto metade
  const b = TollPlaza([(-25.5, -49.0002)], 6, 0, 40); // federal, moto isenta
  const c = TollPlaza([(-25.2, -49.0)], null, null, 40); // estadual, sem preço
  const far = TollPlaza([(-25.5, -49.05)], 8, 0.5, 40); // estrada paralela (~5 km)

  test('acha só as praças por onde a rota passa, na ordem', () {
    final on = const TollTable([c, far, a, b], '12/2025').onRoute(line);
    expect(on, [a, b, c]);
  });

  test('carro: soma completa quando todas têm preço', () {
    final e = estimateTolls([a, b], const BikeProfile(style: BikeStyle.car));
    expect(e.complete, isTrue);
    expect(e.total, 16);
    expect(describeTolls(e, const BikeProfile(style: BikeStyle.car), money).single,
        contains('R\$ 16,00 em 2 praças'));
  });

  test('moto: metade onde paga, zero onde é isenta', () {
    const moto = BikeProfile(style: BikeStyle.naked);
    final e = estimateTolls([a, b], moto);
    expect(e.total, 5);
    expect(e.free, 1);
    expect(describeTolls(e, moto, money).single, contains('1 isenta para moto'));
  });

  test('caminhão de 6 eixos paga 6 vezes o carro; reboque de 1 eixo, 1,5', () {
    expect(estimateTolls([a], const BikeProfile(style: BikeStyle.truck, axles: 6)).total, 60);
    expect(estimateTolls([a], const BikeProfile(style: BikeStyle.car, trailerAxles: 1)).total, 15);
    expect(estimateTolls([a], const BikeProfile(style: BikeStyle.bitrain)).total, 70);
  });

  test('praça sem preço: avisa que o órgão não forneceu e se o veículo paga', () {
    const truck = BikeProfile(style: BikeStyle.truck, axles: 3);
    final e = estimateTolls([a, c], truck);
    expect(e.complete, isFalse);
    final lines = describeTolls(e, truck, money);
    expect(lines[0], contains('não foram fornecidos pelos órgãos'));
    expect(lines[0], contains('R\$ 30,00'));
    expect(lines[1], 'Seu caminhão paga pedágio nessas praças (3× o valor do carro).');
  });

  test('moto em praça sem preço: normalmente paga metade', () {
    const moto = BikeProfile(style: BikeStyle.trail);
    final lines = describeTolls(estimateTolls([c], moto), moto, money);
    expect(lines[1], contains('metade'));
  });

  test('moto só em praças isentas: não paga', () {
    const moto = BikeProfile(style: BikeStyle.custom);
    expect(describeTolls(estimateTolls([b], moto), moto, money).single,
        contains('moto não paga'));
  });

  test('moto onde a concessionária não informa a regra: metade do carro, avisando', () {
    const moto = BikeProfile(style: BikeStyle.touring);
    const d = TollPlaza([(-25.3, -49.0)], 5.7, null, 40);
    final e = estimateTolls([d, a], moto);
    expect(e.complete, isTrue);
    expect(e.total, 7.9); // 2,9 + 5
    final lines = describeTolls(e, moto, money);
    expect(lines[1], contains('não informa a regra da moto'));
  });

  test('linha da tabela do servidor', () {
    final p = TollPlaza.fromRow([-25.1, -49.1, 5.7, 0.5, 40, -25.101, -49.101])!;
    expect(p.pts.length, 2);
    expect(p.car, 5.7);
  });
}
