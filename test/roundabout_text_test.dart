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
  });
}
