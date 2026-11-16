// Testes do road snapping (requisitos 11 e 12): cenários A a H.
// O cenário I (zoom, rotação e inclinação) depende da renderização do mapa
// nativo; aqui só se garante que a posição exibida não depende da câmera.

import 'dart:math';

import 'package:comboio/logic/geo.dart';
import 'package:comboio/logic/radars.dart' show distanceMeters;
import 'package:comboio/logic/road_snapper.dart';
import 'package:comboio/logic/simulation.dart';
import 'package:flutter_test/flutter_test.dart';

// Ribeirão Preto: latitude onde a conversão graus→metros não é trivial.
const lat0 = -21.17, lng0 = -47.81;
const mPerDegLat = 111320.0;
final mPerDegLng = 111320.0 * cos(lat0 * pi / 180);

/// Ponto a [east] m a leste e [north] m ao norte da origem.
(double, double) at(double east, double north) =>
    (lat0 + north / mPerDegLat, lng0 + east / mPerDegLng);

/// Estrada reta de 10 km para o leste.
RouteWalker straight() => RouteWalker([at(0, 0), at(10000, 0)]);

final t0 = DateTime(2026, 11, 16, 12);
DateTime sec(num s) => t0.add(Duration(milliseconds: (s * 1000).round()));

GpsFix fix(double east, double north, num s,
        {double acc = 5, double speed = 20, double heading = 90}) {
  final p = at(east, north);
  return GpsFix(
      lat: p.$1,
      lng: p.$2,
      time: sec(s),
      accuracy: acc,
      speed: speed,
      heading: heading);
}

/// Distância (m) da posição exibida até a rota.
double offRoute(RouteWalker w, DisplayPosition d) =>
    w.project(d.lat, d.lng).offset;

void main() {
  test('A. GPS normal: veículo em cima da via e no lugar certo', () {
    final w = straight();
    final s = RoadSnapper()..route = w;
    final rnd = Random(1);
    for (var i = 0; i < 60; i++) {
      final truth = 100.0 + 20 * i;
      final d = s.update(fix(truth + rnd.nextDouble() * 4 - 2,
          rnd.nextDouble() * 6 - 3, i));
      expect(d.source, PositionSource.mapMatching);
      expect(offRoute(w, d), lessThan(0.5));
      if (i > 3) expect((d.along! - truth).abs(), lessThan(6));
    }
  });

  test('B. precisão ruim (30 m): alinhado à rota, sem pular nem voltar', () {
    final w = straight();
    final s = RoadSnapper()..route = w;
    final rnd = Random(2);
    double? lastAlong;
    for (var i = 0; i < 60; i++) {
      final truth = 100.0 + 20 * i;
      // ±25 m para os lados e ±15 m para frente/trás
      final d = s.update(fix(truth + rnd.nextDouble() * 30 - 15,
          rnd.nextDouble() * 50 - 25, i,
          acc: 30));
      expect(offRoute(w, d), lessThan(0.5), reason: 'leitura $i');
      if (lastAlong != null) {
        expect(d.along!, greaterThanOrEqualTo(lastAlong), reason: 'voltou');
        expect(d.along! - lastAlong, lessThan(45), reason: 'saltou');
      }
      if (i > 5) expect((d.along! - truth).abs(), lessThan(20));
      lastAlong = d.along;
    }
  });

  test('C. sem internet, GPS bom: a posição não muda; leitura original intacta', () {
    // A rede não entra no cálculo: uma leitura válida é usada como veio.
    final s = RoadSnapper(); // sem rota (mapa sem internet, sem navegação)
    for (var i = 0; i < 10; i++) {
      final f = fix(20.0 * i, 0, i, acc: 6);
      final d = s.update(f);
      expect(d.source, PositionSource.gps);
      expect(distanceMeters(d.lat, d.lng, f.lat, f.lng), lessThan(0.01));
    }
    // Com rota: a exibição é encaixada, mas a leitura bruta não é alterada.
    final w = straight();
    final s2 = RoadSnapper()..route = w;
    final f = fix(500, 9, 0, acc: 8);
    final d = s2.update(f);
    expect(d.source, PositionSource.mapMatching);
    expect(offRoute(w, d), lessThan(0.5));
    expect(identical(s2.raw, f), isTrue);
    expect(s2.raw!.lat, at(500, 9).$1);
  });

  test('D. túnel: sem GPS, continua andando pela velocidade (até 60 s)', () {
    final w = straight();
    final s = RoadSnapper()..route = w;
    for (var i = 0; i < 10; i++) {
      s.update(fix(100.0 + 20 * i, 0, i));
    }
    final enter = s.display!.along!;
    // 1 s sem leitura: ainda espera
    expect(s.tick(sec(10)), isNull);
    DisplayPosition? d;
    for (var k = 12; k <= 40; k++) {
      d = s.tick(sec(k)) ?? d;
    }
    expect(d!.source, PositionSource.deadReckoning);
    expect(offRoute(w, d), lessThan(0.5));
    // 31 s depois da última leitura (9 s), a 20 m/s ≈ 620 m
    expect(d.along! - enter, closeTo(20 * 31, 25));
    // Passou de 60 s: para de estimar
    for (var k = 41; k <= 80; k++) {
      s.tick(sec(k));
    }
    final frozen = s.display!.along!;
    expect(s.tick(sec(90)), isNull);
    expect(s.display!.along!, frozen);
  });

  test('E. GPS volta depois do túnel: corrige aos poucos, sem tranco', () {
    final w = straight();
    final s = RoadSnapper()..route = w;
    for (var i = 0; i < 10; i++) {
      s.update(fix(100.0 + 20 * i, 0, i));
    }
    // No túnel o veículo desacelerou para 14 m/s; a estimativa usa 20 m/s.
    for (var k = 12; k <= 29; k++) {
      s.tick(sec(k));
    }
    var truth = 280.0 + 14 * 21; // em 30 s
    var prev = s.display!.along!;
    final errStart = prev - truth;
    expect(errStart, greaterThan(80)); // a estimativa passou do real
    for (var i = 30; i < 60; i++) {
      truth += 14;
      final d = s.update(fix(truth, 4, i, speed: 14));
      expect(d.source, isNot(PositionSource.gps), reason: 'não sai da rota');
      expect(d.along!, greaterThanOrEqualTo(prev), reason: 'não volta');
      expect(d.along! - prev, lessThan(30), reason: 'sem salto');
      prev = d.along!;
    }
    expect((prev - truth).abs(), lessThan(8));
  });

  test('F. pista paralela: não pula para a outra pista nem para a contramão', () {
    // Ida para o leste e volta para o oeste 20 m ao norte (retorno), como
    // as duas pistas de uma rodovia na mesma rota.
    final w = RouteWalker([at(0, 0), at(2000, 0), at(2000, 20), at(0, 20)]);
    final s = RoadSnapper()..route = w;
    for (var i = 0; i < 40; i++) {
      final truth = 100.0 + 20 * i;
      // O GPS puxa para o norte: mais perto da pista de volta (15 m)
      final d = s.update(fix(truth, i.isEven ? 15 : 3, i, acc: 12));
      expect(d.along!, lessThan(2000), reason: 'pulou para a pista de volta');
      expect(angleDiff(d.bearing, 90), lessThan(1));
    }
    // Rua paralela fora da rota (40 m), 1 ou 2 leituras: continua na rota.
    final s2 = RoadSnapper()..route = straight();
    for (var i = 0; i < 10; i++) {
      s2.update(fix(100.0 + 20 * i, 0, i));
    }
    for (var i = 10; i < 12; i++) {
      final d = s2.update(fix(100.0 + 20 * i, 40, i));
      expect(d.source, PositionSource.deadReckoning);
      expect(offRoute(straight(), d), lessThan(0.5));
    }
    // 3ª leitura boa fora: saiu da rota de verdade, mostra o GPS.
    final d = s2.update(fix(340, 40, 12));
    expect(d.source, PositionSource.gps);
  });

  test('G. curva: posição na via e direção acompanhando a curva', () {
    // Leste 1 km, depois norte 1 km (curva de 90°).
    final w = RouteWalker([at(0, 0), at(1000, 0), at(1000, 1000)]);
    final s = RoadSnapper()..route = w;
    final rnd = Random(3);
    for (var i = 0; i < 180; i++) {
      final d0 = 10.0 * i;
      final east = d0 <= 1000 ? d0 : 1000.0;
      final north = d0 <= 1000 ? 0.0 : d0 - 1000;
      final heading = d0 < 1000 ? 90.0 : 0.0;
      final d = s.update(fix(east + rnd.nextDouble() * 4 - 2,
          north + rnd.nextDouble() * 4 - 2, i,
          speed: 10, heading: heading));
      expect(offRoute(w, d), lessThan(0.5));
      if (d0 < 950 && i > 2) expect(angleDiff(d.bearing, 90), lessThan(2));
      if (d0 > 1050) expect(angleDiff(d.bearing, 0), lessThan(2));
    }
  });

  test('H. parado: o veículo não anda com o erro do GPS', () {
    final w = straight();
    final s = RoadSnapper()..route = w;
    s.update(fix(500, 0, 0, speed: 0, heading: -1, acc: 20));
    final first = s.display!;
    final rnd = Random(4);
    for (var i = 1; i < 120; i++) {
      final d = s.update(fix(500 + rnd.nextDouble() * 30 - 15,
          rnd.nextDouble() * 30 - 15, i,
          speed: 0, heading: -1, acc: 20));
      expect(d.lat, first.lat);
      expect(d.lng, first.lng);
      expect(s.tick(sec(i + 0.5)), isNull);
    }
    // Sem rota também
    final s2 = RoadSnapper();
    s2.update(fix(0, 0, 0, speed: 0, acc: 15));
    final p = s2.display!;
    for (var i = 1; i < 30; i++) {
      final d = s2.update(fix(i.isEven ? 10 : -8, i.isEven ? -6 : 7, i,
          speed: 0, acc: 15));
      expect((d.lat, d.lng), (p.lat, p.lng));
    }
  });

  test('I. posição exibida é só coordenada: zoom/rotação/inclinação não entram', () {
    // A mesma sequência dá o mesmo resultado; não há nenhum dado de câmera.
    DisplayPosition run() {
      final s = RoadSnapper()..route = straight();
      for (var i = 0; i < 10; i++) {
        s.update(fix(100.0 + 20 * i, 5, i));
      }
      return s.display!;
    }

    final a = run(), b = run();
    expect((a.lat, a.lng, a.bearing), (b.lat, b.lng, b.bearing));
  });

  test('direção: sem velocidade confiável não usa o rumo do GPS (nem bússola)', () {
    final s = RoadSnapper();
    // Devagar (1 m/s) com rumo do GPS "girando": a direção vem do
    // deslocamento (para o leste), não do valor informado.
    for (var i = 0; i < 10; i++) {
      s.update(fix(10.0 * i, 0, i, speed: 1, heading: (i * 97) % 360 + 0.0));
    }
    expect(angleDiff(s.display!.bearing, 90), lessThan(3));
  });

  test('simulação (exata): encaixa direto, mesmo andando km por segundo', () {
    final w = straight();
    final s = RoadSnapper()..route = w;
    for (var i = 0; i < 5; i++) {
      final d = s.update(fix(2000.0 * i, 0, i, speed: 2000), exact: true);
      expect(d.along, closeTo(2000.0 * i, 2000.0 * i * 0.002 + 0.5));
    }
  });
}
