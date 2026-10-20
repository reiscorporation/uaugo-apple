// ============================================================================
// radars.dart — Radares e trechos de fiscalização da PRF
//
// O que faz: Índice dos radares fixos e trechos de radar portátil, regras para
//   saber se um radar está na pista e no sentido do piloto (com ou sem rota) e
//   as frases faladas (sempre com a velocidade).
// Quem usa: RadarService (carrega) e MapScreen._checkRadars (avisa).
// Onde mexer: Regras de pista/sentido: shouldAlertRadar e radarAheadOnRoute.
// ============================================================================

import 'dart:math';

import 'geo.dart';
import 'speech.dart';

/// Radares (funções puras, sem Firebase nem GPS, para facilitar os testes).

/// Radar fixo de velocidade, de velocidade média (trecho) ou de avanço
/// de sinal (cruzamento).
enum RadarKind { fixed, section, redLight }

/// Um radar da base: posição, tipo, limite (0 = não informado) e sentido
/// (graus, -1 = vale para os dois sentidos).
class FixedRadar {
  final int id;
  final double lat;
  final double lng;
  final RadarKind kind;
  final int limit; // km/h; 0 = desconhecido
  final int direction; // graus; -1 = vale para os dois sentidos
  const FixedRadar(this.id, this.lat, this.lng, this.kind, this.limit,
      this.direction);

  /// Radar de avanço de sinal fica em cruzamento: avisa mais perto.
  double get alertMeters => kind == RadarKind.redLight ? 300 : 1000;
}

/// Trecho onde a PRF pode fiscalizar com radar portátil.
class PrfStretch {
  final int id;
  final String uf;
  final String br; // "101"
  final double kmFrom;
  final double kmTo;
  final List<(double, double)> points; // (lat, lng)
  const PrfStretch(
      this.id, this.uf, this.br, this.kmFrom, this.kmTo, this.points);
}

/// Índice em células de 0,1° (~11 km), igual ao dos alertas.
class RadarIndex {
  final Map<String, List<FixedRadar>> _radars = {};
  final Map<String, List<PrfStretch>> _stretches = {};
  final String attribution;
  final String prfLabel;
  final int radarCount;
  final int stretchCount;

  RadarIndex._(this.attribution, this.prfLabel, this.radarCount,
      this.stretchCount);

  /// Célula de 0,1° (~11 km) onde fica um ponto (chave do índice).
  static String _cell(double lat, double lng) =>
      '${(lat * 10).floor()}_${(lng * 10).floor()}';

  /// Lê o JSON gerado pela Cloud Function `updateRadars`.
  factory RadarIndex.fromJson(Map<String, dynamic> j) {
    final radars = (j['radars'] as List?) ?? const [];
    final prf = j['prf'] as Map<String, dynamic>?;
    final stretches = (prf?['stretches'] as List?) ?? const [];
    final idx = RadarIndex._(
      (j['attribution'] ?? '') as String,
      (prf?['label'] ?? '') as String,
      radars.length,
      stretches.length,
    );
    for (var i = 0; i < radars.length; i++) {
      final r = radars[i] as List;
      final lat = (r[0] as num).toDouble(), lng = (r[1] as num).toDouble();
      final kind = switch ((r[2] as num).toInt()) {
        1 => RadarKind.section,
        2 => RadarKind.redLight,
        _ => RadarKind.fixed,
      };
      final radar = FixedRadar(i, lat, lng, kind, (r[3] as num).toInt(),
          (r[4] as num).toInt());
      idx._radars.putIfAbsent(_cell(lat, lng), () => []).add(radar);
    }
    for (var i = 0; i < stretches.length; i++) {
      final s = stretches[i] as List;
      final pts = decodePolyline(s[4] as String)
          .map((p) => (p.latitude, p.longitude))
          .toList();
      if (pts.isEmpty) continue;
      final st = PrfStretch(i, s[0] as String, s[1] as String,
          (s[2] as num).toDouble(), (s[3] as num).toDouble(), pts);
      final cells = {for (final p in pts) _cell(p.$1, p.$2)};
      for (final c in cells) {
        idx._stretches.putIfAbsent(c, () => []).add(st);
      }
    }
    return idx;
  }

  /// Células em volta de um ponto (3x3 = ~33 km x 33 km).
  Iterable<String> _around(double lat, double lng) sync* {
    final la = (lat * 10).floor(), lo = (lng * 10).floor();
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        yield '${la + i}_${lo + j}';
      }
    }
  }

  /// Radares nas 9 células em volta (~33 km x 33 km).
  List<FixedRadar> radarsAround(double lat, double lng) =>
      [for (final c in _around(lat, lng)) ...?_radars[c]];

  /// Trechos de fiscalização da PRF que passam perto do ponto.
  List<PrfStretch> stretchesAround(double lat, double lng) {
    final seen = <int>{};
    return [
      for (final c in _around(lat, lng))
        for (final s in _stretches[c] ?? const <PrfStretch>[])
          if (seen.add(s.id)) s,
    ];
  }
}

// ------------------------------------------------------------ geometria

/// Distância em metros entre dois pontos (fórmula de haversine).
double _haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180, dLng = (lng2 - lng1) * pi / 180;
  final a = pow(sin(dLat / 2), 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(a));
}

/// Distância em metros entre dois pontos (uso geral no app).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) =>
    _haversine(lat1, lng1, lat2, lng2);

/// Ponto do traçado mais próximo e a distância até ele.
({double lat, double lng, double meters}) nearestOnLine(
    double lat, double lng, List<(double, double)> line) {
  if (line.length == 1) {
    final p = line.first;
    return (lat: p.$1, lng: p.$2, meters: _haversine(lat, lng, p.$1, p.$2));
  }
  // Projeção plana local (suficiente para distâncias de poucos km).
  final kx = cos(lat * pi / 180);
  var best = (lat: line.first.$1, lng: line.first.$2, meters: double.infinity);
  for (var i = 1; i < line.length; i++) {
    final (aLat, aLng) = line[i - 1];
    final (bLat, bLng) = line[i];
    final ax = aLng * kx, ay = aLat, bx = bLng * kx, by = bLat;
    final px = lng * kx, py = lat;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final qLat = aLat + t * (bLat - aLat), qLng = aLng + t * (bLng - aLng);
    final d = _haversine(lat, lng, qLat, qLng);
    if (d < best.meters) best = (lat: qLat, lng: qLng, meters: d);
  }
  return best;
}

// ------------------------------------------------------------ quando avisar

/// O radar vale para o sentido em que o piloto está indo?
bool radarAppliesToHeading(FixedRadar r, double heading, double speed) {
  if (r.direction < 0 || speed < 3 || heading < 0) return true;
  return angleDiff(r.direction.toDouble(), heading) < 60;
}

/// Diferença de ângulo com sinal, de [from] para [to], em -180..180
/// (positivo = para a direita).
double signedAngle(double from, double to) {
  var d = (to - from) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Deslocamento lateral do alvo em relação à linha de direção do piloto,
/// em metros (positivo = à direita).
double lateralOffset(double lat, double lng, double heading, double tLat,
    double tLng) {
  final d = _haversine(lat, lng, tLat, tLng);
  final a = signedAngle(heading, bearingBetween(lat, lng, tLat, tLng));
  return d * sin(a * pi / 180);
}

/// Avisar deste radar agora, sem rota planejada? Só se:
/// - estiver em movimento (parado não dá para saber o sentido);
/// - o radar estiver à frente, quase na direção do piloto (±30°), e não
///   deslocado para o lado (rua paralela);
/// - valer para o sentido do piloto; e, se houver um par de radares lado a
///   lado sem sentido informado (um por pista), só o da direita (mão do
///   Brasil) é o da pista do piloto.
bool shouldAlertRadar(
  FixedRadar r, {
  required double lat,
  required double lng,
  required double heading,
  required double speed,
  List<FixedRadar> neighbors = const [],
  double? range, // distância do 1º aviso (padrão: a do tipo de radar)
}) {
  if (speed < 3 || heading < 0) return false;
  final d = _haversine(lat, lng, r.lat, r.lng);
  if (d > (range ?? r.alertMeters)) return false;
  if (!radarAppliesToHeading(r, heading, speed)) return false;
  final a = signedAngle(heading, bearingBetween(lat, lng, r.lat, r.lng));
  if (a.abs() > 30) return false;
  final lateral = d * sin(a * pi / 180);
  if (lateral.abs() > 40 + 0.03 * d) return false;
  if (r.direction < 0) {
    for (final t in neighbors) {
      if (t.id == r.id || t.direction >= 0) continue;
      final gap = _haversine(r.lat, r.lng, t.lat, t.lng);
      if (gap < 12 || gap > 90) continue;
      final lt = lateralOffset(lat, lng, heading, t.lat, t.lng);
      if (lt > lateral + 8) return false; // o par da direita é o nosso
    }
  }
  return true;
}

/// Com rota: distância PELA ROTA até o radar, ou null se ele não estiver
/// sobre a rota (até [maxOffset] m: radar da outra pista fica de fora), já
/// tiver ficado para trás, estiver longe demais ou for do outro sentido.
double? radarAheadOnRoute(
  FixedRadar r, {
  required ({double along, double offset, double bearing}) Function(
          double lat, double lng)
      project,
  required double riderAlong,
  double maxOffset = 15,
  double? range, // distância do 1º aviso (padrão: a do tipo de radar)
}) {
  final pr = project(r.lat, r.lng);
  if (pr.offset > maxOffset) return null;
  final ahead = pr.along - riderAlong;
  if (ahead <= 0 || ahead > (range ?? r.alertMeters)) return null;
  if (r.direction >= 0 &&
      angleDiff(r.direction.toDouble(), pr.bearing) > 60) {
    return null;
  }
  return ahead;
}

// ------------------------------------------------------------ frases

/// Sempre fala a velocidade: a do radar ou, se a base não tiver, o limite
/// da via no local ([roadLimit]).
String radarSpeech(FixedRadar r, double meters, {int? roadLimit}) {
  final dist = spokenDistance(meters);
  final kmh = r.limit > 0 ? r.limit : roadLimit;
  final limit = kmh != null && kmh > 0
      ? ', velocidade $kmh'
      : ', velocidade não informada';
  return switch (r.kind) {
    RadarKind.fixed => 'Radar a $dist$limit',
    RadarKind.section => 'Radar de velocidade média a $dist$limit',
    RadarKind.redLight => 'Radar de avanço de sinal a $dist$limit',
  };
}

/// Frase do trecho com radar portátil da PRF (entrando ou chegando).
String prfStretchSpeech(PrfStretch s, double meters) {
  // Extensão do trecho (os dados da PRF trazem o km inicial e o final, em
  // qualquer ordem): "nos próximos 60 quilômetros".
  final len = (s.kmTo - s.kmFrom).abs().round();
  final span = len >= 1
      ? ' nos próximos ${spokenDistance(len * 1000.0)}'
      : '';
  final road = 'B R ${int.parse(s.br)}';
  return meters < 100
      ? 'Atenção: pode haver radar móvel da polícia rodoviária na $road$span'
      : 'Atenção: em ${spokenDistance(meters)} começa trecho com radar móvel da polícia rodoviária na $road$span';
}
