// ============================================================================
// tolls.dart — Pedágios da rota e quanto o veículo paga
//
// O que faz: Acha as praças de pedágio por onde a rota passa e soma o valor
//   para o veículo do piloto (carro × fator da ANTT; moto conforme a praça:
//   isenta ou metade). Praças sem preço publicado contam à parte.
// Quem usa: TollService (carrega a tabela) e TripPreviewSheet (mostra).
// Onde mexer: Tabela gerada por functions/tolls.js (formato no topo de lá).
//   Fator de cada veículo: BikeProfile.tollFactor.
// ============================================================================

import 'dart:math';

import '../models/bike.dart';
import 'radars.dart' show distanceMeters;

/// Uma praça de pedágio.
class TollPlaza {
  /// Pontos da praça (cabines); a rota passa a até [radius] m de um deles.
  final List<(double, double)> pts;

  /// Valor do carro em R$ por passagem; null = órgão não publica.
  final double? car;

  /// Moto em fração do carro (0 = isenta, 0,5 = metade); null = não informado.
  final double? moto;
  final double radius;

  const TollPlaza(this.pts, this.car, this.moto, this.radius);

  /// [lat, lng, carro, moto, raio, lat2, lng2, ...] (functions/tolls.js).
  static TollPlaza? fromRow(List row) {
    if (row.length < 5) return null;
    final pts = <(double, double)>[
      ((row[0] as num).toDouble(), (row[1] as num).toDouble()),
      for (var i = 5; i + 1 < row.length; i += 2)
        ((row[i] as num).toDouble(), (row[i + 1] as num).toDouble()),
    ];
    return TollPlaza(pts, (row[2] as num?)?.toDouble(), (row[3] as num?)?.toDouble(),
        (row[4] as num?)?.toDouble() ?? 40);
  }
}

/// Tabela nacional de praças.
class TollTable {
  final List<TollPlaza> plazas;

  /// Mês dos preços da ANTT (ex.: "12/2025").
  final String month;
  const TollTable(this.plazas, this.month);

  factory TollTable.fromJson(Map<String, dynamic> j) => TollTable(
      (j['p'] as List? ?? const [])
          .whereType<List>()
          .map(TollPlaza.fromRow)
          .whereType<TollPlaza>()
          .toList(),
      (j['month'] ?? '') as String);

  /// Praças por onde a rota [line] passa, na ordem do caminho.
  List<TollPlaza> onRoute(List<(double, double)> line) {
    if (line.length < 2) return const [];
    // Grade de ~1 km com os trechos da rota (consulta rápida por praça).
    const cell = 0.01;
    final grid = <int, List<int>>{};
    int key(int a, int b) => a * 100000 + b;
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (var i = 1; i < line.length; i++) {
      final (aLat, aLng) = line[i - 1];
      final (bLat, bLng) = line[i];
      minLat = min(minLat, min(aLat, bLat));
      maxLat = max(maxLat, max(aLat, bLat));
      minLng = min(minLng, min(aLng, bLng));
      maxLng = max(maxLng, max(aLng, bLng));
      for (var la = (min(aLat, bLat) / cell).floor(); la <= (max(aLat, bLat) / cell).floor(); la++) {
        for (var lo = (min(aLng, bLng) / cell).floor(); lo <= (max(aLng, bLng) / cell).floor(); lo++) {
          grid.putIfAbsent(key(la, lo), () => []).add(i);
        }
      }
    }
    final hits = <(int, TollPlaza)>[];
    for (final p in plazas) {
      var best = -1;
      for (final (lat, lng) in p.pts) {
        if (lat < minLat - 0.01 || lat > maxLat + 0.01 || lng < minLng - 0.01 || lng > maxLng + 0.01) {
          continue;
        }
        final la = (lat / cell).floor(), lo = (lng / cell).floor();
        for (var i = -1; i <= 1 && best < 0; i++) {
          for (var j = -1; j <= 1 && best < 0; j++) {
            for (final s in grid[key(la + i, lo + j)] ?? const <int>[]) {
              if (_segmentMeters(lat, lng, line[s - 1], line[s]) <= p.radius) {
                best = s;
                break;
              }
            }
          }
        }
        if (best >= 0) break;
      }
      if (best >= 0) hits.add((best, p));
    }
    hits.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final h in hits) h.$2];
  }
}

/// Distância (m) do ponto ao trecho a-b (projeção plana local).
double _segmentMeters(double lat, double lng, (double, double) a, (double, double) b) {
  final kx = cos(lat * pi / 180);
  final ax = a.$2 * kx, ay = a.$1, bx = b.$2 * kx, by = b.$1;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  final t = len2 == 0 ? 0.0 : (((lng * kx - ax) * dx + (lat - ay) * dy) / len2).clamp(0.0, 1.0);
  return distanceMeters(lat, lng, a.$1 + t * (b.$1 - a.$1), a.$2 + t * (b.$2 - a.$2));
}

/// Pedágios da rota para um veículo.
class TollEstimate {
  /// Praças no caminho.
  final int plazas;

  /// Praças com valor conhecido para este veículo e a soma delas (R$).
  final int priced;
  final double total;

  /// Praças isentas para este veículo (moto).
  final int free;

  /// Moto: praças com preço do carro mas sem a regra da moto publicada;
  /// conta metade (regra padrão da tabela da ANTT).
  final int motoAssumed;

  const TollEstimate({
    required this.plazas,
    required this.priced,
    required this.total,
    required this.free,
    this.motoAssumed = 0,
  });

  /// Todas as praças têm valor: dá para somar no custo da viagem.
  bool get complete => plazas > 0 && priced == plazas;
  int get unpriced => plazas - priced;
}

/// Soma os pedágios de [onRoute] para [bike].
TollEstimate estimateTolls(List<TollPlaza> onRoute, BikeProfile bike) {
  final factor = bike.tollFactor;
  var priced = 0, free = 0, assumed = 0;
  var total = 0.0;
  for (final p in onRoute) {
    if (factor == null) {
      // Moto: isenta vale mesmo sem preço; metade precisa do preço do carro.
      if (p.moto == 0) {
        priced++;
        free++;
      } else if (p.car != null) {
        priced++;
        if (p.moto == null) assumed++;
        total += _round(p.car! * (p.moto ?? 0.5));
      }
    } else if (p.car != null) {
      priced++;
      total += _round(p.car! * factor);
    }
  }
  return TollEstimate(
    plazas: onRoute.length,
    priced: priced,
    total: total,
    free: free,
    motoAssumed: assumed,
  );
}

/// Arredonda em 10 centavos, como as tabelas de pedágio.
double _round(double v) => (v * 10).round() / 10;

/// Frases da prévia da rota (a 1ª é o valor ou o aviso; a 2ª, se houver,
/// diz se o veículo paga nas praças sem valor).
List<String> describeTolls(TollEstimate e, BikeProfile bike, String Function(double) money) {
  if (e.plazas == 0) return const [];
  final n = e.plazas == 1 ? '1 praça' : '${e.plazas} praças';
  final noun = bike.style.noun;
  if (e.complete) {
    if (e.total == 0) return ['🛣️ $n de pedágio: moto não paga nesta rota'];
    final freeNote = e.free > 0
        ? ' (${e.free == 1 ? '1 isenta' : '${e.free} isentas'} para moto)'
        : '';
    return [
      '🛣️ Pedágios: ≈ ${money(e.total)} em $n$freeNote',
      if (e.motoAssumed > 0) _assumedNote(e),
    ];
  }
  final missing = e.unpriced == 1 ? '1 praça' : '${e.unpriced} praças';
  final lines = <String>[
    '🛣️ $n de pedágio no caminho. Os valores de $missing não foram fornecidos '
        'pelos órgãos responsáveis.'
        '${e.priced > 0 ? ' Praças com valor: ≈ ${money(e.total)}.' : ''}',
  ];
  if (bike.style.isMoto) {
    if (e.motoAssumed > 0) lines.add(_assumedNote(e));
    lines.add('Nessas praças a moto normalmente paga metade do valor do carro.');
  } else {
    final cap = noun[0].toUpperCase() + noun.substring(1);
    final f = bike.tollFactor ?? 1;
    lines.add(f == 1
        ? '$cap paga pedágio nessas praças.'
        : '$cap paga pedágio nessas praças (${_times(f)} o valor do carro).');
  }
  return lines;
}

String _assumedNote(TollEstimate e) => e.motoAssumed == 1
    ? 'Em 1 praça a concessionária não informa a regra da moto: contei metade do carro.'
    : 'Em ${e.motoAssumed} praças a concessionária não informa a regra da moto: '
        'contei metade do carro.';

String _times(double f) =>
    f == f.roundToDouble() ? '${f.toInt()}×' : '${f.toString().replaceAll('.', ',')}×';

/// Praça da tabela a até [maxMeters] do ponto (a cabine do aviso falado).
TollPlaza? nearestPlaza(TollTable table, double lat, double lng,
    {double maxMeters = 400}) {
  TollPlaza? best;
  var bestD = maxMeters;
  for (final p in table.plazas) {
    for (final (a, b) in p.pts) {
      final d = distanceMeters(lat, lng, a, b);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
  }
  return best;
}

/// Complemento do aviso falado da praça ("Praça de pedágio a 1 km. ..."):
/// quanto o veículo paga, quando se sabe. Para moto, nunca afirma que paga
/// sem informação: [osmMotoFree] = o mapa aberto diz que a moto é isenta.
String tollPlazaNote(TollPlaza? plaza, BikeProfile bike,
    String Function(double) money, {bool osmMotoFree = false}) {
  final car = plaza?.car;
  if (bike.style.isMoto) {
    final rule = plaza?.moto ?? (osmMotoFree ? 0.0 : null);
    if (rule == 0) return 'Moto isenta';
    if (rule == null) return 'Valor para moto não informado';
    return car != null
        ? 'Moto paga ${money(_round(car * rule))}'
        : 'Moto paga metade do valor do carro';
  }
  if (car == null) return '';
  final noun = bike.style.noun;
  return '${noun[0].toUpperCase()}${noun.substring(1)} paga '
      '${money(_round(car * (bike.tollFactor ?? 1)))}';
}
