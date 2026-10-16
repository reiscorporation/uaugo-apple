import 'package:comboio/logic/speed.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monta o formato compacto da Cloud Function a partir de pontos absolutos.
List<int> compact(List<(double, double, int, int, int)> pts) {
  final d = <int>[];
  var pLat = 0, pLng = 0;
  for (final (lat, lng, lim, est, dir) in pts) {
    final la = (lat * 1e5).round(), lo = (lng * 1e5).round();
    d.addAll([la - pLat, lo - pLng, lim, est, dir]);
    pLat = la;
    pLng = lo;
  }
  return d;
}

void main() {
  // Rodovia norte-sul com pistas separadas (sentido sul: 80; norte: 60),
  // e uma rua urbana sem placa (estimada 40) a 2 km dali.
  final idx = SpeedLimitIndex.fromCompact(compact([
    (-28.30000, -48.70000, 80, 0, 180),
    (-28.30000, -48.70010, 60, 0, 0),
    (-28.31800, -48.70000, 40, 1, -1),
  ]));

  group('limite da via', () {
    test('acha o ponto mais próximo', () {
      expect(idx.length, 3);
      expect(idx.lookup(-28.31801, -48.70002), const RoadLimit(40, true));
    });

    test('longe de qualquer ponto, sem limite', () {
      expect(idx.lookup(-28.40, -48.70), isNull);
    });

    test('respeita o sentido da pista', () {
      expect(
          idx.lookup(-28.30000, -48.70005, heading: 180, speed: 20)?.kmh, 80);
      expect(idx.lookup(-28.30000, -48.70005, heading: 2, speed: 20)?.kmh, 60);
    });

    test('placa diferente só troca na 2ª leitura seguida', () {
      final t = LimitTracker();
      final t0 = DateTime(2026, 10, 16, 10);
      t.update(const RoadLimit(110, false), t0);
      // Um ponto solto de 60 (saída): não troca.
      expect(t.update(const RoadLimit(60, false), t0)?.kmh, 110);
      expect(t.update(const RoadLimit(110, false), t0)?.kmh, 110);
      // 80 duas vezes seguidas: troca.
      expect(t.update(const RoadLimit(80, false), t0)?.kmh, 110);
      expect(t.update(const RoadLimit(80, false), t0)?.kmh, 80);
    });

    test('mantém o último limite por um trecho curto sem dados', () {
      final t = LimitTracker();
      final t0 = DateTime(2026, 10, 3, 10);
      t.update(const RoadLimit(80, false), t0);
      expect(t.update(null, t0.add(const Duration(seconds: 10)))?.kmh, 80);
      // Sem dado por mais de 15 s: some (antes eram 45 s; atrasava demais).
      expect(t.update(null, t0.add(const Duration(seconds: 20))), isNull);
    });

    group('pista certa (não a marginal)', () {
      // Pista principal (100 km/h) em lng -49.00000 e marginal (40 km/h)
      // 25 m a leste. Pontos a cada ~110 m na pista, ~20 m na marginal.
      final d = <num>[];
      var pLat = 0, pLng = 0;
      void add(int lat, int lng, int lim) {
        d.addAll([lat - pLat, lng - pLng, lim, 0, -1]);
        pLat = lat;
        pLng = lng;
      }
      final pts = <List<int>>[
        for (var k = 0; k < 10; k++) [-2800000 - k * 100, -4900000, 100],
        for (var k = 0; k < 50; k++) [-2800000 - k * 20, -4899974, 40],
      ]..sort((a, b) => a[0] != b[0] ? a[0] - b[0] : a[1] - b[1]);
      for (final p in pts) {
        add(p[0], p[1], p[2]);
      }
      final idx = SpeedLimitIndex.fromCompact(d);
      // Moto na pista principal, entre dois pontos dela (50 m de cada).
      const lat = -28.00450, lng = -49.00000;

      test('sem velocidade, pega o mais perto (marginal)', () {
        expect(idx.lookup(lat, lng)?.kmh, 40);
      });

      test('andando para o sul: pega a pista (na linha da direção)', () {
        expect(idx.lookup(lat, lng, heading: 180, speed: 28)?.kmh, 100);
        // Devagar e sem direção, continua valendo o mais perto.
        expect(idx.lookup(lat, lng, speed: 1)?.kmh, 40);
      });

      test('com rota: só pontos em cima da rota', () {
        double offset(double la, double lo) => (lo - -49.0).abs() * 98000;
        expect(idx.lookup(lat, lng, speed: 10, routeOffset: offset)?.kmh, 100);
      });

      test('com rota sem ponto da rota por perto: nada (nunca a marginal)', () {
        // Rota passando 300 m a oeste: nenhum ponto da pista nem da marginal
        // está nela.
        double far(double la, double lo) => 300;
        expect(idx.lookup(lat, lng, speed: 10, routeOffset: far), isNull);
      });

      test('andando: sem ponto na linha da direção, não pega a paralela', () {
        // Indo para o leste (atravessando): nenhum ponto na linha da direção.
        expect(idx.lookup(lat, lng, heading: 90, speed: 20), isNull);
      });
    });
  });

  group('cor do velocímetro', () {
    const posted = RoadLimit(80, false), est = RoadLimit(60, true);
    test('vermelho acima do limite de placa; âmbar se estimado', () {
      expect(SpeedAlerter.level(78, posted, 0), SpeedLevel.normal);
      expect(SpeedAlerter.level(85, posted, 0), SpeedLevel.over);
      expect(SpeedAlerter.level(65, est, 0), SpeedLevel.overEstimated);
      expect(SpeedAlerter.level(50, null, 0), SpeedLevel.normal);
    });
    test('velocidade máxima pessoal também fica vermelho', () {
      expect(SpeedAlerter.level(105, null, 100), SpeedLevel.over);
    });
  });

  group('aviso falado', () {
    const posted = RoadLimit(80, false);
    final t0 = DateTime(2026, 10, 3, 10);

    test('desligado por padrão', () {
      final a = SpeedAlerter();
      expect(a.update(120, posted, const SpeedAlertSettings(), t0), isNull);
    });

    test('fala uma vez ao passar e de novo só depois de voltar ou 60 s', () {
      final a = SpeedAlerter();
      const s = SpeedAlertSettings(roadAlert: true, tolerance: 5);
      expect(a.update(84, posted, s, t0), isNull); // dentro da margem
      expect(a.update(86, posted, s, t0), 'Velocidade acima do limite de 80');
      expect(a.update(90, posted, s, t0.add(const Duration(seconds: 10))),
          isNull);
      expect(a.update(90, posted, s, t0.add(const Duration(seconds: 70))),
          isNotNull);
      expect(a.update(75, posted, s, t0.add(const Duration(seconds: 80))),
          isNull); // voltou para baixo do limite
      expect(a.update(88, posted, s, t0.add(const Duration(seconds: 85))),
          isNotNull);
    });

    test('limite estimado não gera aviso falado', () {
      final a = SpeedAlerter();
      const s = SpeedAlertSettings(roadAlert: true, tolerance: 0);
      expect(a.update(90, const RoadLimit(60, true), s, t0), isNull);
    });

    test('velocidade máxima pessoal', () {
      final a = SpeedAlerter();
      const s = SpeedAlertSettings(personalMax: 120);
      expect(a.update(118, null, s, t0), isNull);
      expect(a.update(123, null, s, t0),
          'Atenção: velocidade acima de 120 quilômetros por hora');
      expect(a.update(125, null, s, t0.add(const Duration(seconds: 5))),
          isNull);
    });
  });
}
