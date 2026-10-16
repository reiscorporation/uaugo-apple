// ============================================================================
// speed.dart — Limite de velocidade da via e alertas de excesso
//
// O que faz: SpeedLimitIndex escolhe o limite da pista em que o piloto está:
//   com rota, só pontos em cima da rota; sem rota, pontos na linha da direção
//   da moto (a marginal ao lado fica de fora). SpeedAlerter fala quando passa
//   do limite.
// Quem usa: SpeedService (carrega por estado) e MapScreen._updateSpeed.
// Onde mexer: Regras de escolha: SpeedLimitIndex.lookup (testes em
//   test/speed_test.dart).
// ============================================================================

import 'dart:math';
import 'dart:typed_data';

import 'geo.dart';

// Velocímetro, limite da via e alertas de velocidade (funções puras).

/// Limite encontrado para a posição atual.
class RoadLimit {
  final int kmh;

  /// true = estimado pelo tipo de via (sem placa mapeada).
  final bool estimated;
  const RoadLimit(this.kmh, this.estimated);

  @override
  bool operator ==(Object other) =>
      other is RoadLimit && other.kmh == kmh && other.estimated == estimated;
  @override
  int get hashCode => Object.hash(kmh, estimated);
}

/// Pontos de limite de um estado, indexados em células de ~500 m.
class SpeedLimitIndex {
  SpeedLimitIndex._(this._lat, this._lng, this._lim, this._est, this._dir);

  final Int32List _lat; // graus * 1e5
  final Int32List _lng;
  final Uint8List _lim;
  final Uint8List _est;
  final Int16List _dir;
  final Map<int, List<int>> _cells = {};

  int get length => _lat.length;

  /// Chave da célula da grade (~550 m) de um ponto em 1e-5 grau.
  static int _cell(int latE5, int lngE5) =>
      ((latE5 / 500).floor() + 100000) * 1000000 +
      ((lngE5 / 500).floor() + 100000);

  /// Lê o formato compacto gerado pela Cloud Function `updateSpeedLimits`:
  /// [dLat, dLng, limite, estimado, sentido, ...] com lat/lng em diferenças.
  factory SpeedLimitIndex.fromCompact(List<dynamic> d) {
    final n = d.length ~/ 5;
    final lat = Int32List(n), lng = Int32List(n);
    final lim = Uint8List(n), est = Uint8List(n);
    final dir = Int16List(n);
    var la = 0, lo = 0;
    for (var i = 0; i < n; i++) {
      final k = i * 5;
      la += (d[k] as num).toInt();
      lo += (d[k + 1] as num).toInt();
      lat[i] = la;
      lng[i] = lo;
      lim[i] = (d[k + 2] as num).toInt();
      est[i] = (d[k + 3] as num).toInt();
      dir[i] = (d[k + 4] as num).toInt();
    }
    final idx = SpeedLimitIndex._(lat, lng, lim, est, dir);
    for (var i = 0; i < n; i++) {
      idx._cells.putIfAbsent(_cell(lat[i], lng[i]), () => []).add(i);
    }
    return idx;
  }

  /// Limite do ponto mais próximo (até [maxMeters]) no sentido do piloto.
  /// Limite da via onde o piloto está.
  ///
  /// [routeOffset] (navegando com rota): distância do ponto de limite até a
  /// rota. Só valem pontos EM CIMA da rota (até 12 m): a marginal, a 20–40 m
  /// da pista, fica de fora.
  ///
  /// Sem rota, cada candidato a até [maxMeters] ganha "pontos contra":
  /// a distância, ser estimado (não é placa) e ter limite muito abaixo da
  /// velocidade atual (a 100 km/h não se está numa marginal de 40).
  RoadLimit? lookup(double lat, double lng,
      {double heading = -1,
      double speed = 0,
      double maxMeters = 40,
      double pathMeters = 150,
      double Function(double lat, double lng)? routeOffset}) {
    final la = (lat * 1e5).round(), lo = (lng * 1e5).round();
    final kx = cos(lat * pi / 180);
    final kmh = speed * 3.6;
    final max2 = maxMeters * maxMeters;
    final path2 = pathMeters * pathMeters;
    // Sem rota, mas andando: o "caminho" é a linha da direção da moto
    // (de 150 m atrás até 60 m à frente, até 10 m para o lado).
    final hx = heading >= 0 ? sin(heading * pi / 180) : 0.0;
    final hy = heading >= 0 ? cos(heading * pi / 180) : 0.0;
    final useHeading = routeOffset == null && speed >= 3 && heading >= 0;
    var best = -1, bestOnPath = -1;
    var bestCost = double.infinity, bestPathD2 = double.infinity;
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        final c = _cell(la + i * 500, lo + j * 500);
        for (final p in _cells[c] ?? const <int>[]) {
          // Distância aproximada em metros (1e-5 grau ≈ 1,11 m).
          final dy = (_lat[p] - la) * 1.1132;
          final dx = (_lng[p] - lo) * 1.1132 * kx;
          final d2 = dx * dx + dy * dy;
          if (d2 > path2) continue;
          final dir = _dir[p];
          if (dir >= 0 && speed >= 3 && heading >= 0 &&
              angleDiff(dir.toDouble(), heading) > 60) {
            continue; // limite do outro sentido da pista
          }
          // Ponto da via em que o piloto está (rota ou linha da direção).
          if (d2 < bestPathD2) {
            bool onPath;
            if (routeOffset != null) {
              onPath = routeOffset(_lat[p] / 1e5, _lng[p] / 1e5) <= 12;
            } else if (useHeading) {
              final along = dx * hx + dy * hy;
              final side = (dx * hy - dy * hx).abs();
              onPath = along >= -150 && along <= 60 && side <= 10;
            } else {
              onPath = false;
            }
            if (onPath) {
              bestPathD2 = d2;
              bestOnPath = p;
            }
          }
          if (d2 > max2) continue;
          var cost = sqrt(d2);
          if (_est[p] == 1) cost += 15;
          if (kmh > _lim[p] + 35) cost += 40;
          if (cost < bestCost) {
            bestCost = cost;
            best = p;
          }
        }
      }
    }
    // Com rota ou andando numa direção: SÓ a via do piloto. O mais próximo
    // de qualquer via (saída, marginal, paralela) fica só para parado.
    final p = bestOnPath >= 0
        ? bestOnPath
        : (routeOffset != null || useHeading ? -1 : best);
    return p < 0 ? null : RoadLimit(_lim[p], _est[p] == 1);
  }
}

/// Mantém o último limite por um trecho curto sem dados (cruzamentos,
/// pontes), para o velocímetro não piscar.
class LimitTracker {
  RoadLimit? _current;
  RoadLimit? _pending;
  DateTime? _seenAt;

  RoadLimit? get current => _current;

  /// Novo resultado da busca. Um limite DIFERENTE só vale depois de aparecer
  /// em duas leituras seguidas (um ponto solto de uma saída não troca a
  /// placa); sem dado, mantém o anterior por até 15 s (cruzamentos e pontes).
  RoadLimit? update(RoadLimit? found, DateTime now) {
    if (found != null) {
      if (_current == null || found == _current || found == _pending) {
        _current = found;
        _pending = null;
      } else {
        _pending = found;
      }
      _seenAt = now;
    } else if (_seenAt != null &&
        now.difference(_seenAt!) > const Duration(seconds: 15)) {
      _current = null;
    }
    return _current;
  }
}

/// Cor do velocímetro.
enum SpeedLevel { normal, overEstimated, over }

/// Configuração dos alertas de velocidade (escolhida pelo piloto).
class SpeedAlertSettings {
  /// Avisar por voz ao passar do limite da via (só limites oficiais).
  final bool roadAlert;

  /// Margem antes do aviso de voz, em km/h (0, 5, 10).
  final int tolerance;

  /// Velocidade máxima pessoal (0 = desligado).
  final int personalMax;

  const SpeedAlertSettings({
    this.roadAlert = false,
    this.tolerance = 5,
    this.personalMax = 0,
  });
}

/// Decide a cor e quando falar. Fala uma vez ao passar; só fala de novo
/// depois de voltar abaixo do limite ou após 60 s ainda acima.
class SpeedAlerter {
  bool _roadArmed = true;
  bool _personalArmed = true;
  DateTime _lastRoad = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPersonal = DateTime.fromMillisecondsSinceEpoch(0);

  static const repeatAfter = Duration(seconds: 60);

  /// Cor do velocímetro: normal, acima do limite da via ou acima do
  /// máximo pessoal (compara o número que aparece na tela, arredondado).
  static SpeedLevel level(double kmh, RoadLimit? limit, int personalMax) {
    // Compara o número que aparece no velocímetro (arredondado): mostrar
    // "110" vermelho numa via de 110 confunde.
    final shown = kmh.round();
    if (personalMax > 0 && shown > personalMax) return SpeedLevel.over;
    if (limit == null || shown <= limit.kmh) return SpeedLevel.normal;
    return limit.estimated ? SpeedLevel.overEstimated : SpeedLevel.over;
  }

  /// Retorna a frase a falar (ou null).
  String? update(double kmh, RoadLimit? limit, SpeedAlertSettings s,
      DateTime now) {
    // Velocidade máxima pessoal tem prioridade.
    if (s.personalMax > 0) {
      if (kmh > s.personalMax) {
        if (_personalArmed || now.difference(_lastPersonal) > repeatAfter) {
          _personalArmed = false;
          _lastPersonal = now;
          return 'Atenção: velocidade acima de ${s.personalMax} quilômetros por hora';
        }
      } else if (kmh < s.personalMax - 5) {
        _personalArmed = true;
      }
    }
    if (s.roadAlert && limit != null && !limit.estimated) {
      if (kmh > limit.kmh + s.tolerance) {
        if (_roadArmed || now.difference(_lastRoad) > repeatAfter) {
          _roadArmed = false;
          _lastRoad = now;
          return 'Velocidade acima do limite de ${limit.kmh}';
        }
      } else if (kmh <= limit.kmh) {
        _roadArmed = true;
      }
    }
    return null;
  }
}
