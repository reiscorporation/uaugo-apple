// ============================================================================
// places_service.dart — Busca de lugares (Places API)
//
// O que faz: Sugestões enquanto digita e os detalhes (posição) do lugar
//   escolhido.
// Quem usa: PlaceSearchPage ("Para onde?" e paradas do roteiro).
// Onde mexer: Custo: cada busca é cobrada pelo Google (usa sessão para
//   baratear).
// ============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

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
/// Usa a mesma chave das rotas (DIRECTIONS_API_KEY).
///
/// Custo: a cobrança é por "sessão" (digitação + escolha do lugar); por isso
/// o mesmo token de sessão vai em todas as buscas e no detalhe escolhido.
class PlacesService {
  static const _key = String.fromEnvironment('DIRECTIONS_API_KEY');
  static bool get available => _key.isNotEmpty;

  String _session = _newSession();

  /// Token de sessão: o Google cobra a busca inteira (várias letras +
  /// escolha) como uma consulta só.
  static String _newSession() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Sugestões enquanto o usuário digita (perto de [near], se houver).
  Future<List<PlaceSuggestion>> search(String text,
      {double? nearLat, double? nearLng}) async {
    if (_key.isEmpty || text.trim().length < 3) return const [];
    try {
      final body = {
        'input': text.trim(),
        'languageCode': 'pt-BR',
        // Sem restrição de país: dá para buscar cidades no exterior. O
        // locationBias abaixo só dá preferência ao que está perto.
        'sessionToken': _session,
        if (nearLat != null && nearLng != null)
          'locationBias': {
            'circle': {
              'center': {'latitude': nearLat, 'longitude': nearLng},
              'radius': 50000.0,
            }
          },
      };
      final res = await http
          .post(
            Uri.https('places.googleapis.com', '/v1/places:autocomplete'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _key,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
    if (_key.isEmpty) return null;
    try {
      final res = await http.get(
        Uri.https('places.googleapis.com', '/v1/places/${s.placeId}',
            {'sessionToken': _session, 'languageCode': 'pt-BR'}),
        headers: {
          'X-Goog-Api-Key': _key,
          'X-Goog-FieldMask': 'displayName,formattedAddress,location',
        },
      ).timeout(const Duration(seconds: 10));
      _session = _newSession(); // a sessão termina ao escolher um lugar
      if (res.statusCode != 200) return null;
      final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
