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

import '../logic/address_abbrev.dart';
import '../logic/find_places.dart';
import '../l10n/i18n.dart';

/// Sugestão da busca (ainda sem coordenadas).
class PlaceSuggestion {
  final String placeId;
  final String title; // ex.: "Posto Shell"
  final String subtitle; // ex.: "Urubici - SC"

  /// Distância até a posição do piloto (null = o Google não informou).
  final int? meters;
  const PlaceSuggestion(this.placeId, this.title, this.subtitle, [this.meters]);
}

/// Mais perto primeiro; sem distância, no fim (mantendo a ordem do Google).
List<PlaceSuggestion> sortByDistance(List<PlaceSuggestion> list) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final d = (a.$2.meters ?? 1 << 40).compareTo(b.$2.meters ?? 1 << 40);
    return d != 0 ? d : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
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

  /// A última busca falhou por falta de conexão (ou servidor fora).
  bool lastFailed = false;

  /// Token de sessão: o Google cobra a busca inteira (várias letras +
  /// escolha) como uma consulta só.
  static String _newSession() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// Chama a função "places" do servidor e devolve o resultado como Map.
  Future<Map<String, dynamic>> _call(Map<String, dynamic> data) async {
    data = {...data, 'lang': I18n.isEn ? 'en' : 'pt'};
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
    lastFailed = false;
    // "av. aparecido savegnago" não achava "Avenida Aparecido Savegnago":
    // com abreviação, busca também por extenso e junta (por extenso primeiro).
    final full = expandAddressAbbrev(text);
    if (full != text.trim()) {
      final both = await Future.wait([
        _search(full, nearLat, nearLng),
        _search(text, nearLat, nearLng),
      ]);
      final seen = <String>{};
      final out = [
        for (final l in both)
          for (final s in l)
            if (seen.add(s.placeId)) s
      ];
      lastFailed = both.every((l) => l.isEmpty) && lastFailed;
      return sortByDistance(out);
    }
    return _search(text, nearLat, nearLng);
  }

  Future<List<PlaceSuggestion>> _search(
      String text, double? nearLat, double? nearLng) async {
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
      final out = list
          .map((s) => s['placePrediction'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .map((p) => PlaceSuggestion(
                p['placeId'] as String,
                (p['structuredFormat']?['mainText']?['text'] ??
                    p['text']?['text'] ??
                    '') as String,
                (p['structuredFormat']?['secondaryText']?['text'] ?? '')
                    as String,
                (p['distanceMeters'] as num?)?.toInt(),
              ))
          .toList();
      return sortByDistance(out);
    } catch (_) {
      lastFailed = true;
      return const [];
    }
  }

  /// "UauGo, procurar posto": lugares da [category] no caminho ([polyline],
  /// a rota codificada) ou perto de (lat, lng). [limit] = já usou as buscas
  /// do dia (teto contra abuso, functions/maps.js).
  /// Sem [category], busca o [text] falado ("loja de moto").
  Future<({List<FoundPlace> places, bool limit})> find(
    FindCategory? category, {
    String? text,
    bool cheap = false,
    required double lat,
    required double lng,
    String? polyline,
  }) async {
    try {
      final d = await _call({
        'action': 'find',
        'category': category?.name ?? 'text',
        if (category == null) 'text': text,
        'cheap': cheap,
        'lat': lat,
        'lng': lng,
        if (polyline != null && polyline.isNotEmpty) 'polyline': polyline,
      });
      final list = (d['places'] as List?) ?? const [];
      return (
        places: [
          for (final p in list.whereType<Map>())
            FoundPlace(
              name: (p['name'] ?? '') as String,
              address: (p['address'] ?? '') as String,
              lat: (p['lat'] as num).toDouble(),
              lng: (p['lng'] as num).toDouble(),
              price: p['price'] as String?,
              open: p['open'] as bool?,
              meters: 0,
            ),
        ],
        limit: false,
      );
    } on FirebaseFunctionsException catch (e) {
      return (places: const <FoundPlace>[], limit: e.code == 'resource-exhausted');
    } catch (_) {
      return (places: const <FoundPlace>[], limit: false);
    }
  }

  /// IA (Gemini, pelo servidor, functions/ai.js): entende um pedido falado
  /// livre ("restaurante bom e barato", "me leva pra casa"). Null se falhar
  /// (sem internet): o app usa o texto como está.
  Future<({String action, String category, String query, bool cheap, String saved})?>
      interpret(String text) async {
    try {
      final res = await _fn
          .httpsCallable('interpret',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call({'text': text});
      final d = Map<String, dynamic>.from(res.data as Map);
      return (
        action: (d['action'] ?? 'find') as String,
        category: (d['category'] ?? '') as String,
        query: (d['query'] ?? '') as String,
        cheap: d['cheap'] == true,
        saved: (d['saved'] ?? '') as String,
      );
    } catch (_) {
      return null;
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
      // O nome é o da sugestão (o servidor não pede o nome ao Google:
      // fica mais barato).
      return PlaceDetails(
        s.title,
        (d['formattedAddress'] ?? s.subtitle) as String,
        (loc['latitude'] as num).toDouble(),
        (loc['longitude'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
