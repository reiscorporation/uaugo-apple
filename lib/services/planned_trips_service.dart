// ============================================================================
// planned_trips_service.dart — Viagens planejadas (rota normal, só no celular)
//
// O que faz: Guarda viagens com data e hora de saída escolhidas na prévia da
//   rota ("Saída: ..." → "Salvar viagem planejada"). Aparecem na tela
//   inicial em "Viagens planejadas" para abrir na hora de sair.
// Quem usa: TripPreviewSheet (salvar), HomeScreen (lista e abrir).
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expedition.dart' show StopType;
import 'trip_service.dart';

/// Uma viagem planejada.
class PlannedTrip {
  final String id;
  final String title;
  final DateTime departAt;
  final List<TripPoint> points;
  const PlannedTrip(this.id, this.title, this.departAt, this.points);

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'departAt': departAt.toIso8601String(),
        'points': [
          for (final p in points)
            {'name': p.name, 'lat': p.lat, 'lng': p.lng, 'type': p.type.name}
        ],
      };

  static PlannedTrip? fromMap(Object? m) {
    if (m is! Map) return null;
    try {
      return PlannedTrip(
        m['id'] as String,
        m['title'] as String,
        DateTime.parse(m['departAt'] as String),
        [
          for (final p in (m['points'] as List))
            TripPoint(p['name'] as String, (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
                type: StopType.values.firstWhere((t) => t.name == p['type'],
                    orElse: () => StopType.waypoint)),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Lista das viagens planejadas (as que já passaram há mais de 1 dia somem).
class PlannedTripsService {
  PlannedTripsService._();
  static final instance = PlannedTripsService._();

  static const _key = 'plannedTrips';
  final trips = ValueNotifier<List<PlannedTrip>>(const []);

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    List<PlannedTrip> list = [];
    if (raw != null) {
      try {
        list = (jsonDecode(raw) as List)
            .map(PlannedTrip.fromMap)
            .whereType<PlannedTrip>()
            .where((t) => t.departAt.isAfter(cutoff))
            .toList();
      } catch (_) {}
    }
    list.sort((a, b) => a.departAt.compareTo(b.departAt));
    trips.value = list;
  }

  Future<void> _save() async => (await SharedPreferences.getInstance())
      .setString(_key, jsonEncode(trips.value.map((t) => t.toMap()).toList()));

  Future<void> add(String title, DateTime departAt, List<TripPoint> points) async {
    final t = PlannedTrip(
        DateTime.now().microsecondsSinceEpoch.toString(), title, departAt, points);
    trips.value = [...trips.value, t]
      ..sort((a, b) => a.departAt.compareTo(b.departAt));
    await _save();
  }

  Future<void> remove(String id) async {
    trips.value = [for (final t in trips.value) if (t.id != id) t];
    await _save();
  }
}
