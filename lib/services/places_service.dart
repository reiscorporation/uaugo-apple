// ============================================================================
// places_service.dart — Busca de lugares (Places API)
//
// O que faz: Sugestões enquanto digita e os detalhes (posição) do lugar
//   escolhido. Passa pelo SERVIDOR (função "places", functions/maps.js), que
//   guarda a chave do Google: ela não fica dentro do app.
// Quem usa: PlaceSearchPage ("Para onde?" e paradas do roteiro).
// Onde mexer: Custo: cada busca é cobrada pelo Google (usa sessão para
//   baratear). Limite diário por usuário: functions/maps.js (LIMITS).
// ============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';

/// Sugestão da busca (ainda sem coordenadas).
class PlaceSuggestion {
  final String placeId;
  final String title; // ex.: "Posto Shell"
  final String subtitle; // ex.: "Urubici - SC"
  const PlaceSuggestion(this.placeId, this.title, this.subtitle);
}

/// Lugar escolhido: nome e posição.
class PlaceDetails {
  final String name;
  final String address;
  final double lat;
  final double lng;
  const PlaceDetails(this.name, this.address, this.lat, this.lng);
}

/// Busca de lugares por nome (Places API "New"), igual ao Google Maps.
///
/// Custo: a cobrança é por "sessão" (digitação + escolha do lugar); por isso
/// o mesmo token de sessão vai em todas as buscas e no detalhe escolhido.
class PlacesService {
  static bool get available => true;

  static final _fn =
      FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  String _session = _newSession();

  /// Token de sessão: o Google cobra a busca inteira (várias letras +
  /// escolha) como uma consulta só.
  static String _newSession() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Chama a função "places" do servidor e devolve o resultado como Map.
  Future<Map<String, dynamic>> _call(Map<String, dynamic> data) async {
    final res = await _fn
        .httpsCallable('places',
            options:
                HttpsCallableOptions(timeout: const Duration(seconds: 15)))
        .call(data);
    return jsonDecode(jsonEncode(res.data)) as Map<String, dynamic>;
  }

  /// Sugestões enquanto o usuário digita (perto de [nearLat]/[nearLng], se
  /// houver). Sem restrição de país: dá para buscar cidades no exterior.
  Future<List<PlaceSuggestion>> search(String text,
      {double? nearLat, double? nearLng}) async {
    if (text.trim().length < 3) return const [];
    try {
      final data = await _call({
        'action': 'autocomplete',
        'input': text.trim(),
        'sessionToken': _session,
        if (nearLat != null && nearLng != null) ...{
          'lat': nearLat,
          'lng': nearLng,
        },
      });
      final list = (data['suggestions'] as List?) ?? const [];
      return list
          .map((s) => s['placePrediction'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .map((p) => PlaceSuggestion(
                p['placeId'] as String,
                (p['structuredFormat']?['mainText']?['text'] ??
                    p['text']?['text'] ??
                    '') as String,
                (p['structuredFormat']?['secondaryText']?['text'] ?? '')
                    as String,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Posição e nome do lugar escolhido (encerra a sessão de busca).
  Future<PlaceDetails?> details(PlaceSuggestion s) async {
    try {
      final d = await _call({
        'action': 'details',
        'placeId': s.placeId,
        'sessionToken': _session,
      });
      _session = _newSession(); // a sessão termina ao escolher um lugar
      final loc = d['location'] as Map<String, dynamic>?;
      if (loc == null) return null;
      return PlaceDetails(
        (d['displayName']?['text'] ?? s.title) as String,
        (d['formattedAddress'] ?? s.subtitle) as String,
        (loc['latitude'] as num).toDouble(),
        (loc['longitude'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
