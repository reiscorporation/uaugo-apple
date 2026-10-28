// ============================================================================
// pois.dart — Lombadas, postos policiais, pedágios e semáforos
//
// O que faz: Índice em grade de ~1 km dos pontos de um estado, para a consulta
//   "o que tem perto" ser rápida (roda a cada leitura do GPS).
// Quem usa: PoiService (carrega) e MapScreen._checkPois (avisa).
// Onde mexer: Novos tipos: enum PoiKind (+ functions/pois.js no servidor).
// ============================================================================

import 'radars.dart' show distanceMeters;

/// bump = lombada; policePost = posto policial rodoviário; toll = praça de
/// pedágio (moto paga ou não informado); tollMotoFree = pedágio com moto isenta.
enum PoiKind {
  bump,
  policePost,
  toll,
  tollMotoFree;

  bool get isToll => this == toll || this == tollMotoFree;

  /// Código do arquivo do servidor (functions/pois.js) -> tipo.
  static PoiKind fromCode(int c) => switch (c) {
        2 => policePost,
        3 => toll,
        4 => tollMotoFree,
        _ => bump,
      };
}

/// Um ponto: lombada, posto policial ou pedágio.
class Poi {
  final int id;
  final double lat;
  final double lng;
  final PoiKind kind;
  const Poi(this.id, this.lat, this.lng, this.kind);
}

/// Lombadas e postos policiais de um estado, numa grade de ~1 km para a
/// consulta "o que tem perto" ser rápida (o app consulta a cada segundo).
class PoiIndex {
  final Map<int, List<Poi>> _cells = {};
  int length = 0;

  /// Chave da célula da grade (~1 km).
  static int _key(int la, int lo) => la * 100000 + lo;

  /// Semáforos, na mesma grade (só para a voz: "no semáforo, vire").
  final Map<int, List<(double, double)>> _signals = {};

  /// [d] = [dLat, dLng, tipo, ...] em 1e-5 grau (diferenças acumuladas);
  /// [signals] = [dLat, dLng, ...] dos semáforos.
  PoiIndex.fromCompact(List d, {int idBase = 0, List? signals}) {
    var sLat = 0, sLng = 0;
    for (var i = 0; signals != null && i + 1 < signals.length; i += 2) {
      sLat += (signals[i] as num).toInt();
      sLng += (signals[i + 1] as num).toInt();
      _signals
          .putIfAbsent(_key((sLat / 1000).floor(), (sLng / 1000).floor()), () => [])
          .add((sLat / 1e5, sLng / 1e5));
    }
    var lat = 0, lng = 0;
    for (var i = 0; i + 2 < d.length; i += 3) {
      lat += (d[i] as num).toInt();
      lng += (d[i + 1] as num).toInt();
      final kind = PoiKind.fromCode((d[i + 2] as num).toInt());
      final p = Poi(idBase + length, lat / 1e5, lng / 1e5, kind);
      _cells
          .putIfAbsent(_key((lat / 1000).floor(), (lng / 1000).floor()), () => [])
          .add(p);
      length++;
    }
  }

  /// Há semáforo a até [meters] (máx. ~1 km) de (lat, lng)?
  bool signalNear(double lat, double lng, double meters) {
    final la = (lat * 100).floor(), lo = (lng * 100).floor();
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        for (final (a, b) in _signals[_key(la + i, lo + j)] ?? const <(double, double)>[]) {
          if (distanceMeters(lat, lng, a, b) <= meters) return true;
        }
      }
    }
    return false;
  }

  /// Semáforos a até [meters] (máx. ~1 km) de (lat, lng), para o mapa.
  List<(double, double)> signalsNear(double lat, double lng, double meters) {
    final la = (lat * 100).floor(), lo = (lng * 100).floor();
    return [
      for (var i = -1; i <= 1; i++)
        for (var j = -1; j <= 1; j++)
          for (final (a, b) in _signals[_key(la + i, lo + j)] ?? const <(double, double)>[])
            if (distanceMeters(lat, lng, a, b) <= meters) (a, b),
    ];
  }

  /// Pontos a até [meters] (máx. ~1 km) de (lat, lng).
  List<Poi> near(double lat, double lng, double meters) {
    final la = (lat * 100).floor(), lo = (lng * 100).floor();
    final out = <Poi>[];
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        for (final p in _cells[_key(la + i, lo + j)] ?? const <Poi>[]) {
          if (distanceMeters(lat, lng, p.lat, p.lng) <= meters) out.add(p);
        }
      }
    }
    return out;
  }
}
