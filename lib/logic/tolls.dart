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
import '../l10n/i18n.dart';

/// Uma praça de pedágio.
class TollPlaza {
  /// Pontos da praça (cabines); a rota passa a até [radius] m de um deles.
  final List<(double, double)> pts;

  /// Valor do carro em R$ por passagem; null = órgão não publica.
  final double? car;

  /// Moto em fração do carro (0 = isenta, 0,5 = metade); null = não informado.
  final double? moto;
  final double radius;

  /// De onde vem o valor: oficial (ANTT), a confirmar (IA/planilha) ou
  /// confirmado por pilotos.
  final TollSource source;

  /// Nome da praça, quando conhecido.
  final String name;

  const TollPlaza(this.pts, this.car, this.moto, this.radius,
      {this.source = TollSource.official, this.name = ''});

  /// Chave da praça no servidor: 1º ponto com 5 casas ("-22.12345,-47.12345").
  String get key =>
      '${pts.first.$1.toStringAsFixed(5)},${pts.first.$2.toStringAsFixed(5)}';

  /// Cartão na cabine (null = não se sabe: o app não mostra nada).
  TollCard? get card => TollCards.of(this);

  /// Todo valor pode ser confirmado/corrigido pelo piloto (até o da ANTT,
  /// que às vezes está defasado); vale com 2 pilotos ou a administração.
  bool get editable => true;

  /// Moto em R\$ (null = não informado).
  double? get motoValue => moto == null || car == null ? (moto == 0 ? 0 : null) : _round(car! * moto!);

  /// [lat, lng, carro, moto, raio, lat2, lng2, ...] (functions/tolls.js).
  /// [status] e [names]: mapas "s" e "n" da tabela, pela chave da praça.
  static TollPlaza? fromRow(List row,
      [Map<String, dynamic> status = const {}, Map<String, dynamic> names = const {}]) {
    if (row.length < 5) return null;
    final pts = <(double, double)>[
      ((row[0] as num).toDouble(), (row[1] as num).toDouble()),
      for (var i = 5; i + 1 < row.length; i += 2)
        ((row[i] as num).toDouble(), (row[i + 1] as num).toDouble()),
    ];
    final key = '${pts.first.$1.toStringAsFixed(5)},${pts.first.$2.toStringAsFixed(5)}';
    final st = status[key];
    return TollPlaza(pts, (row[2] as num?)?.toDouble(), (row[3] as num?)?.toDouble(),
        (row[4] as num?)?.toDouble() ?? 40,
        source: st == 'u'
            ? TollSource.users
            : (st == 'e' ? TollSource.estimated : TollSource.official),
        name: (names[key] as String?) ?? '');
  }
}

/// Cartão aceito na cabine manual.
enum TollCard {
  /// Débito e crédito.
  debitCredit,

  /// Só débito.
  debitOnly,
}

/// Quais praças aceitam cartão (pedido de 15/11: mostrar débito/crédito).
///
/// - Rodovias federais (valor da ANTT): débito e crédito são obrigatórios
///   desde a Decisão SUROD/ANTT nº 633, de 13/06/2025 (dinheiro, débito,
///   crédito, Pix e TAG em todas as praças).
/// - Estaduais: assets/data/pedagio_cartao.json, praça a praça, montado
///   pela operadora das cabines no OpenStreetMap e pela lista da ARTESP/
///   concessionárias (scripts/pedagio-cartao.py).
/// Sem informação: não mostra nada (melhor que chutar).
class TollCards {
  TollCards._();

  /// Chave da praça -> 'cd' (débito e crédito) ou 'd' (só débito).
  static Map<String, String> byKey = const {};

  static TollCard? of(TollPlaza p) {
    switch (byKey[p.key]) {
      case 'cd':
        return TollCard.debitCredit;
      case 'd':
        return TollCard.debitOnly;
    }
    if (p.source == TollSource.official && p.car != null) return TollCard.debitCredit;
    return null;
  }
}

/// Frase curta do cartão ('' = não se sabe).
String tollCardNote(TollPlaza? p) => switch (p?.card) {
      TollCard.debitCredit => tr('Aceita cartão de débito e crédito'),
      TollCard.debitOnly => tr('Aceita só cartão de débito'),
      null => '',
    };

/// Resumo do cartão nas praças da rota ('' = nenhuma informação).
String tollCardsSummary(List<TollPlaza> list) {
  if (list.isEmpty) return '';
  var cd = 0, d = 0;
  for (final p in list) {
    switch (p.card) {
      case TollCard.debitCredit:
        cd++;
      case TollCard.debitOnly:
        d++;
      case null:
    }
  }
  final n = list.length, unknown = n - cd - d;
  if (cd + d == 0) return '';
  if (cd == n) {
    return n == 1
        ? tr('💳 A praça aceita cartão de débito e crédito.')
        : tr('💳 Todas as {0} praças aceitam cartão de débito e crédito.', [n]);
  }
  final parts = [
    if (cd > 0) tr('{0} débito e crédito', [cd]),
    if (d > 0) tr('{0} só débito', [d]),
    if (unknown > 0) tr('{0} sem informação', [unknown]),
  ];
  return tr('💳 Cartão nas praças: {0}.', [parts.join(' · ')]);
}

/// Origem do valor de uma praça.
enum TollSource {
  /// Dados abertos da ANTT.
  official,

  /// Estimado (pesquisa automática ou planilha): pede confirmação.
  estimated,

  /// Confirmado por 2 ou mais pilotos.
  users,
}

/// Tabela nacional de praças.
class TollTable {
  final List<TollPlaza> plazas;

  /// Mês dos preços da ANTT (ex.: "12/2025").
  final String month;
  const TollTable(this.plazas, this.month);

  factory TollTable.fromJson(Map<String, dynamic> j) {
    final st = (j['s'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final names = (j['n'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    return TollTable(
        (j['p'] as List? ?? const [])
            .whereType<List>()
            .map((r) => TollPlaza.fromRow(r, st, names))
            .whereType<TollPlaza>()
            .toList(),
        (j['month'] ?? '') as String);
  }

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

  /// As praças do caminho (na ordem), para confirmar/corrigir valores.
  final List<TollPlaza> list;

  const TollEstimate({
    required this.plazas,
    required this.priced,
    required this.total,
    required this.free,
    this.motoAssumed = 0,
    this.list = const [],
  });

  /// Praças com valor a confirmar (estimado ou sem valor).
  int get toConfirm =>
      list.where((p) => p.source == TollSource.estimated || p.car == null).length;

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
    list: onRoute,
  );
}

/// Arredonda em 10 centavos, como as tabelas de pedágio.
double _round(double v) => (v * 10).round() / 10;

/// Frases da prévia da rota (a 1ª é o valor ou o aviso; a 2ª, se houver,
/// diz se o veículo paga nas praças sem valor).
List<String> describeTolls(TollEstimate e, BikeProfile bike, String Function(double) money) {
  if (e.plazas == 0) return const [];
  final n = e.plazas == 1 ? tr('1 praça') : tr('{0} praças', [e.plazas]);
  final noun = bike.style.noun;
  if (e.complete) {
    if (e.total == 0) return [tr('🛣️ {0} de pedágio: moto não paga nesta rota', [n])];
    final freeNote = e.free > 0
        ? tr(' ({0} para moto)', [e.free == 1 ? tr('1 isenta') : tr('{0} isentas', [e.free])])
        : '';
    return [
      tr('🛣️ Pedágios: ≈ {0} em {1}{2}', [money(e.total), n, freeNote]),
      if (e.motoAssumed > 0) _assumedNote(e),
    ];
  }
  final missing = e.unpriced == 1 ? tr('1 praça') : tr('{0} praças', [e.unpriced]);
  final lines = <String>[
    tr('🛣️ {0} de pedágio no caminho. Os valores de {1} não foram fornecidos pelos órgãos responsáveis.{2}', [n, missing, e.priced > 0 ? tr(' Praças com valor: ≈ {0}.', [money(e.total)]) : '']),
  ];
  if (bike.style.isMoto) {
    if (e.motoAssumed > 0) lines.add(_assumedNote(e));
    lines.add(tr('Nessas praças a moto normalmente paga metade do valor do carro.'));
  } else {
    final cap = noun[0].toUpperCase() + noun.substring(1);
    final f = bike.tollFactor ?? 1;
    lines.add(f == 1
        ? tr('{0} paga pedágio nessas praças.', [cap])
        : tr('{0} paga pedágio nessas praças ({1} o valor do carro).', [cap, _times(f)]));
  }
  return lines;
}

String _assumedNote(TollEstimate e) => e.motoAssumed == 1
    ? tr('Em 1 praça a concessionária não informa a regra da moto: contei metade do carro.')
    : tr('Em {0} praças a concessionária não informa a regra da moto: contei metade do carro.', [e.motoAssumed]);

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
    if (rule == 0) return tr('Moto isenta');
    if (rule == null) return tr('Valor para moto não informado');
    return car != null
        ? tr('Moto paga {0}', [money(_round(car * rule))])
        : tr('Moto paga metade do valor do carro');
  }
  if (car == null) return '';
  final noun = bike.style.noun;
  return '${noun[0].toUpperCase()}${noun.substring(1)} paga '
      '${money(_round(car * (bike.tollFactor ?? 1)))}';
}
