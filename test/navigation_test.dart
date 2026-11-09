import 'package:comboio/logic/navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('limpeza das instruções do Google', () {
    test('tira as tags e escreve abreviações por extenso', () {
      expect(
          cleanInstruction(
              'Vire à <b>esquerda</b> na <b>R. Arcipreste Paiva</b>'),
          'Vire à esquerda na Rua Arcipreste Paiva');
      expect(cleanInstruction('Pegue a <b>Rod. Gov. Gustavo Richard</b>'),
          'Pegue a Rodovia Governador Gustavo Richard');
    });

    test('tira "Você verá" mas mantém avisos úteis', () {
      expect(
          cleanInstruction('Vire à <b>esquerda</b> na <b>Av. Brasil</b>'
              '<div style="font-size:0.9em">Você verá Banco Safra (à direita)</div>'),
          'Vire à esquerda na Avenida Brasil');
      expect(
          cleanInstruction('Vire à <b>direita</b>'
              '<div style="font-size:0.9em">O destino estará à direita</div>'),
          'Vire à direita. O destino estará à direita');
    });

    test('tira "Passe por" (ponto de referência longe do começo do trecho)', () {
      expect(
          cleanInstruction('Continue na <b>SP-330</b>'
              '<div style="font-size:0.9em">Passe por Posto Ipiranga (à direita a 1,4 km)</div>'),
          'Continue na SP 330');
    });

    test('saídas de rodovia: número em destaque e até 2 destinos', () {
      expect(
          cleanInstruction('Pegue a saída <b>210</b> para a <b>BR-101</b> '
              'em direção a <b>210</b>'),
          'Pegue a saída 210, para a BR 101');
      expect(
          cleanInstruction('Pegue a saída em direção a <b>BR-101-SUL</b>/<wbr/>'
              '<b>Tubarão</b>/<wbr/><b>Porto Alegre</b>/<wbr/><b>FAIXAS 1 E 2</b>'),
          'Pegue a saída em direção a BR 101 sul e Tubarão');
      expect(
          cleanInstruction('Pegue a saída <b>47</b> para a <b>Via Anhanguera</b>'
              '/<wbr/><b>BR-050</b>/<wbr/><b>SP-330</b> em direção a '
              '<b>Vinhedo</b>/<wbr/><b>Anhanguera</b>/<wbr/><b>Jundiaí</b>'),
          'Pegue a saída 47, para a Via Anhanguera e BR 050 em direção a '
          'Vinhedo e Anhanguera');
    });

    test('rodovias e rotatórias', () {
      expect(cleanInstruction('Continue para <b>BR-282</b>'),
          'Continue para BR 282');
      expect(
          cleanInstruction(
              'Na rotatória, pegue a <b>2ª</b> saída para a <b>SC-390</b>'),
          'Na rotatória, pegue a segunda saída para a SC 390');
    });
  });

  group('curva a curva', () {
    // Trajeto em linha reta para o sul; manobras a cada ~2,2 km.
    const steps = [
      NavStep(-28.000, -49.000, 'Siga na direção sul na BR 101', ''),
      NavStep(-28.020, -49.000, 'Vire à direita na SC 390', 'turn-right'),
      NavStep(-28.030, -49.000, 'Continue para Rua X', ''),
      NavStep(-28.040, -49.000, 'Vire à esquerda na Rua Y', 'turn-left'),
    ];

    List<String> drive(TurnByTurn nav, double fromLat, double toLat,
        {double speed = 20, double step = 0.0005}) {
      final said = <String>[];
      for (var lat = fromLat; lat >= toLat; lat -= step) {
        final s = nav.update(lat, -49.0, speed);
        if (s != null) said.add(s);
      }
      return said;
    }

    test('na saída fala a direção; depois avisa antes e na hora da curva', () {
      final nav = TurnByTurn(steps);
      final said = drive(nav, -28.000, -28.0215);
      expect(said.first, 'Siga na direção sul na BR 101');
      expect(said, contains(startsWith('Em ')));
      expect(said.where((s) => s.contains('vire à direita na SC 390')),
          hasLength(1));
      // Na hora, só a manobra (a rua já foi dita no aviso de longe).
      expect(said, contains('Vire à direita'));
    });

    test('com semáforo na esquina: "No semáforo, vire..." (antes e na hora)', () {
      // Semáforo só na esquina da SC 390.
      final nav = TurnByTurn(steps,
          signalAt: (lat, lng) => (lat - -28.020).abs() < 0.0003);
      final said = drive(nav, -28.000, -28.045);
      expect(said, contains('No semáforo, vire à direita'));
      expect(said, contains(matches(RegExp(r'^Em .+, no semáforo, vire à direita na SC 390$'))));
      // Sem semáforo na outra esquina; a saída ("Siga...") nunca ganha o aviso.
      expect(said, contains('Vire à esquerda'));
      expect(said.first, 'Siga na direção sul na BR 101');
    });

    test('"Continue para" (troca de nome da rua) não é falado', () {
      final nav = TurnByTurn(steps);
      final said = drive(nav, -28.000, -28.045);
      expect(said.any((s) => s.contains('Rua X')), isFalse);
      expect(said, contains('Vire à esquerda'));
      expect(nav.finished, isTrue);
    });

    test('ligando no meio do caminho começa na manobra mais próxima', () {
      // Já passou da manobra 2 (em -28,030): começa na 3.
      final nav = TurnByTurn(steps)..syncTo(-28.033, -49.0);
      expect(nav.nextIndex, 3);
      final said = drive(nav, -28.033, -28.045);
      expect(said.any((s) => s.contains('SC 390')), isFalse);
      expect(said, contains('Vire à esquerda'));
    });

    test('ligando logo depois de uma manobra, não volta para ela', () {
      final nav = TurnByTurn(steps)..syncTo(-28.004, -49.0);
      expect(nav.nextIndex, 1);
    });

    test('pela rota: manobra silenciosa fora do caminho não trava a voz', () {
      // A manobra 2 ("Continue para...") fica 300 m fora do caminho: no modo
      // antigo (linha reta) ela segurava a sequência e a saída ficava muda.
      const ss = [
        NavStep(-28.000, -49.000, 'Siga na direção sul na BR 101', ''),
        NavStep(-28.010, -48.997, 'Continue para Rua X', ''),
        NavStep(-28.020, -49.000, 'Pegue a saída 214', 'ramp-right'),
      ];
      // Posição de cada manobra ao longo da rota (m) e avanço do piloto.
      final nav = TurnByTurn(ss)
        ..attachRoute((la, lo) => (la + 28.0).abs() * 111320);
      final said = <String>[];
      for (var along = 0.0; along <= 2300; along += 50) {
        final s = nav.updateAlong(along, 25);
        if (s != null) said.add(s);
      }
      expect(said.first, 'Siga na direção sul na BR 101');
      expect(said, contains(startsWith('Em ')));
      expect(said, contains('Pegue a saída 214'));
      expect(said.any((s) => s.contains('Rua X')), isFalse);
    });

    test('voltar para trás (simulação/GPS) recomeça na saída que falta', () {
      const ss = [
        NavStep(-28.000, -49.000, 'Siga na direção sul na BR 101', ''),
        NavStep(-28.020, -49.000, 'Pegue a saída 206', 'ramp-right'),
        NavStep(-28.030, -49.000, 'O seu destino fica à esquerda.', 'destination'),
      ];
      final nav = TurnByTurn(ss)
        ..attachRoute((la, lo) => (la + 28.0).abs() * 111320);
      nav.updateAlong(3000, 25); // já passou da saída
      expect(nav.nextIndex, 2);
      nav.syncAlong(1500); // pulou para antes dela
      expect(nav.nextIndex, 1);
    });

    test('saída na rodovia: avisa a ~900 m e na hora (só 2 vezes)', () {
      const ss = [NavStep(-28.0, -49.0, 'Pegue a saída 210, para a BR 101', 'ramp-right')];
      final nav = TurnByTurn(ss)..attachRoute((_, __) => 5000);
      final said = <String>[];
      for (var a = 0.0; a <= 5000; a += 30) {
        final s = nav.updateAlong(a, 30); // 108 km/h, 1 leitura por segundo
        if (s != null) said.add(s);
      }
      expect(said.length, 2);
      expect(said[0], startsWith('Em 900 metros'));
      expect(said[1], 'Pegue a saída 210');
    });

    test('pela rota: distância falada é a da estrada', () {
      const ss = [NavStep(-28.0, -49.0, 'Vire à direita na SC 390', 'turn-right')];
      final nav = TurnByTurn(ss)..attachRoute((_, __) => 5000);
      expect(nav.updateAlong(4200, 20), 'Em 800 metros, vire à direita na SC 390');
      expect(nav.routeDistanceTo(0, 4200), 800);
    });

    test('mais rápido, avisa mais cedo', () {
      // Para em ~890 m da curva (-28,012): só o rápido já foi avisado.
      final slow = drive(TurnByTurn(steps)..syncTo(-28.004, -49.0), -28.004,
          -28.012, speed: 10);
      final fast = drive(TurnByTurn(steps)..syncTo(-28.004, -49.0), -28.004,
          -28.012, speed: 33);
      // A 120 km/h o aviso antecipado sai a ~1 km (30 s); a 36 km/h, só a 800 m.
      expect(fast.any((s) => s.startsWith('Em ')), isTrue);
      expect(slow.any((s) => s.startsWith('Em ')), isFalse);
    });
  });

  test('números romanos nos nomes de rua são falados por extenso', () {
    expect(spokenRomanNumerals('Vire à direita na Avenida Leão XIII'),
        'Vire à direita na Avenida Leão Treze');
    expect(spokenRomanNumerals('Siga pela Rua Dom Pedro II'),
        'Siga pela Rua Dom Pedro Segundo');
    expect(spokenRomanNumerals('Praça Pio X'), 'Praça Pio Décimo');
    expect(spokenRomanNumerals('Avenida João XXIII'), 'Avenida João Vinte e três');
    expect(spokenRomanNumerals('Rua XV de novembro'), 'Rua Quinze de novembro');
    expect(spokenRomanNumerals('Rua VII de setembro'), 'Rua Sete de setembro');
    // Siglas e números normais ficam como estão.
    expect(spokenRomanNumerals('Pegue a BR 101 em direção a MG'),
        'Pegue a BR 101 em direção a MG');
    expect(spokenRomanNumerals('Rua CIC Norte'), 'Rua CIC Norte');
    expect(cleanInstruction('Vire à <b>esquerda</b> na <b>Av. Leão XIII</b>'),
        'Vire à esquerda na Avenida Leão Treze');
  });
}
