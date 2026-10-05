// ============================================================================
// trip_record.dart — Viagem gravada ("Minhas viagens")
//
// O que faz: Caminho feito, estatísticas, paradas, gastos e número de pilotos.
//   Salvo em JSON no celular (HistoryService).
// Quem usa: HistoryService, HistoryScreen, MapScreen._saveRecord.
// Onde mexer: Campos novos: toJson/fromJson (mantenha compatível com arquivos
//   antigos).
// ============================================================================

import '../logic/costs.dart';

/// Uma viagem feita, guardada SÓ no celular ("Minhas viagens").
class TripRecord {
  final String id;
  final bool expedition; // false = navegação sozinho / só dirigir
  final String title;
  final String? code; // código da expedição
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceM;
  final int movingS;
  final double maxKmh;
  final String routePolyline; // rota planejada
  final String trackPolyline; // caminho percorrido
  final List<({String name, double lat, double lng, String type})> stops;

  /// Gastos registrados pelo piloto (abastecimentos, pedágios...).
  final List<Expense> expenses;

  /// Pilotos na expedição (para dividir os gastos). 1 = sozinho.
  final int riders;

  const TripRecord({
    required this.id,
    required this.expedition,
    required this.title,
    this.code,
    required this.startedAt,
    required this.endedAt,
    required this.distanceM,
    required this.movingS,
    required this.maxKmh,
    this.routePolyline = '',
    this.trackPolyline = '',
    this.stops = const [],
    this.expenses = const [],
    this.riders = 1,
  });

  /// Cópia trocando os gastos ou o número de pilotos.
  TripRecord copyWith({List<Expense>? expenses, int? riders}) => TripRecord(
        id: id,
        expedition: expedition,
        title: title,
        code: code,
        startedAt: startedAt,
        endedAt: endedAt,
        distanceM: distanceM,
        movingS: movingS,
        maxKmh: maxKmh,
        routePolyline: routePolyline,
        trackPolyline: trackPolyline,
        stops: stops,
        expenses: expenses ?? this.expenses,
        riders: riders ?? this.riders,
      );

  double get avgKmh => movingS > 0 ? distanceM / movingS * 3.6 : 0;

  /// Formato salvo em viagens.json (chaves curtas para ocupar pouco).
  Map<String, dynamic> toJson() => {
        'id': id,
        'exp': expedition,
        'title': title,
        if (code != null) 'code': code,
        'start': startedAt.millisecondsSinceEpoch,
        'end': endedAt.millisecondsSinceEpoch,
        'dist': distanceM,
        'moving': movingS,
        'max': maxKmh,
        'route': routePolyline,
        'track': trackPolyline,
        'stops': [
          for (final s in stops)
            {'n': s.name, 'la': s.lat, 'lo': s.lng, 't': s.type}
        ],
        if (expenses.isNotEmpty) 'exps': [for (final e in expenses) e.toJson()],
        'riders': riders,
      };

  /// Lê uma viagem salva; null se o registro estiver corrompido.
  static TripRecord? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return TripRecord(
        id: j['id'] as String,
        expedition: j['exp'] == true,
        title: (j['title'] ?? 'Viagem') as String,
        code: j['code'] as String?,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch((j['start'] as num).toInt()),
        endedAt: DateTime.fromMillisecondsSinceEpoch((j['end'] as num).toInt()),
        distanceM: (j['dist'] as num).toDouble(),
        movingS: (j['moving'] as num).toInt(),
        maxKmh: (j['max'] as num).toDouble(),
        routePolyline: (j['route'] ?? '') as String,
        trackPolyline: (j['track'] ?? '') as String,
        stops: [
          for (final s in (j['stops'] as List? ?? const []))
            (
              name: (s['n'] ?? '') as String,
              lat: (s['la'] as num).toDouble(),
              lng: (s['lo'] as num).toDouble(),
              type: (s['t'] ?? 'waypoint') as String,
            )
        ],
        expenses: [
          for (final e in (j['exps'] as List? ?? const []))
            if (Expense.fromJson(e) case final x?) x
        ],
        riders: (j['riders'] as num?)?.toInt() ?? 1,
      );
    } catch (_) {
      return null;
    }
  }
}
