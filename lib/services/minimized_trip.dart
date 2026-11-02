// ============================================================================
// minimized_trip.dart — Viagem minimizada, esperando para ser retomada
//
// O que faz: Guarda a rota quando o piloto toca em "Minimizar" e volta para a
//   tela inicial. A tela inicial mostra o cartão "Retomar a navegação" e
//   pergunta antes de abrir o mapa. Só na memória: fechar o app apaga.
//   ActiveTrip guarda no celular a rota em andamento: se o Android fechar o
//   app em segundo plano, ela volta sozinha ao abrir.
// Quem usa: MapScreen (Minimizar, rota em andamento) e HomeScreen (retomar).
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/navigation.dart';
import '../models/expedition.dart';
import '../models/trip.dart';

class MinimizedTrip {
  MinimizedTrip._();

  /// Viagem à espera (null = nenhuma).
  static final trip = ValueNotifier<Trip?>(null);
}

/// Rota em andamento guardada no celular até chegar ou encerrar.
class ActiveTrip {
  ActiveTrip._();

  static const _key = 'activeTrip';

  /// Mais velha que isso não é a mesma viagem: não retoma.
  static const maxAge = Duration(hours: 6);

  static Future<void> save(Trip t) async {
    try {
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'title': t.title,
        'plan': t.plan.toMap(),
        'typicalS': t.typicalS,
        'hasToll': t.hasToll,
        'summary': t.summary,
        'stops': [
          for (final s in t.stops)
            {
              'id': s.id, 'name': s.name, 'address': s.address,
              'lat': s.lat, 'lng': s.lng, 'order': s.order,
              'createdBy': s.createdBy, 'type': s.type.name,
              'dist': s.legDistanceM, 'dur': s.legDurationS,
              'steps': [for (final n in s.steps) n.toMap()],
            }
        ],
      }));
    } catch (e) {
      debugPrint('Rota não guardada: $e');
    }
  }

  static Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);

  /// Rota que ficou em andamento; null se não há ou se está velha.
  static Future<Trip?> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      if (DateTime.now().difference(at) > maxAge) {
        await clear();
        return null;
      }
      return Trip(
        title: j['title'] as String,
        plan: TripPlan.fromMap(j['plan'] as Map<String, dynamic>),
        typicalS: j['typicalS'] as int?,
        hasToll: j['hasToll'] == true,
        summary: (j['summary'] ?? '') as String,
        stops: [
          for (final s in (j['stops'] as List).cast<Map<String, dynamic>>())
            Stop(
              id: s['id'] as String,
              name: s['name'] as String,
              address: (s['address'] ?? '') as String,
              lat: (s['lat'] as num).toDouble(),
              lng: (s['lng'] as num).toDouble(),
              order: s['order'] as int,
              createdBy: (s['createdBy'] ?? '') as String,
              type: StopType.parse(s['type'] as String?),
              legDistanceM: s['dist'] as int,
              legDurationS: s['dur'] as int,
              steps: (s['steps'] as List)
                  .map(NavStep.fromMap)
                  .whereType<NavStep>()
                  .toList(),
            ),
        ],
      );
    } catch (e) {
      debugPrint('Rota guardada ilegível: $e');
      await clear();
      return null;
    }
  }
}
