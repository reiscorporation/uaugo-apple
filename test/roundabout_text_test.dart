import 'package:comboio/services/route_engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entrada de rotatória em português', () {
    expect(
        RouteEngineService.roundaboutText(
            'Enter Praça Eloi Chaves and take the 2ª exit onto Avenida Presidente Castelo Branco.'),
        'Na rotatória Praça Eloi Chaves, pegue a 2ª saída para Avenida Presidente Castelo Branco.');
  });

  test('outros textos não mudam', () {
    expect(RouteEngineService.roundaboutText('Vire à esquerda.'), 'Vire à esquerda.');
    expect(
        RouteEngineService.roundaboutText(
            'Make a à esquerda U-turn toward Aguai/São João da Boa Vista.'),
        'Faça o retorno à esquerda em direção a Aguai/São João da Boa Vista.');
    expect(
        RouteEngineService.roundaboutText(
            'Enter the roundabout and take the 3rd exit onto Avenida da Universidade.'),
        'Na rotatória, pegue a 3ª saída para Avenida da Universidade.');
  });

  test('frase metade em inglês vira português', () {
    expect(RouteEngineService.roundaboutText('Turn à direita toward Rua Itu.'),
        'Vire à direita em direção a Rua Itu.');
    expect(RouteEngineService.roundaboutText('Turn right onto Avenida Brasil.'),
        'Vire à direita para Avenida Brasil.');
    expect(RouteEngineService.roundaboutText('Bear slight left toward SP-330.'),
        'Mantenha-se levemente à esquerda em direção a SP-330.');
    expect(RouteEngineService.roundaboutText('Continue na Rua Wright.'), 'Continue na Rua Wright.');
  });
}
