// ============================================================================
// recent_places_service.dart — Destinos recentes (só no celular)
//
// O que faz: Guarda os últimos lugares escolhidos na busca (nome, endereço e
//   posição). Na busca, aparecem antes de consultar o Google: escolher um
//   recente não gera consulta paga (e funciona sem internet).
// Quem usa: PlaceSearchPage.
// Onde mexer: quantos guardar: [RecentPlacesService.max].
// ============================================================================

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Um destino escolhido antes.
class RecentPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;
  const RecentPlace(this.name, this.address, this.lat, this.lng);

  Map<String, dynamic> toMap() =>
      {'name': name, 'address': address, 'lat': lat, 'lng': lng};

  static RecentPlace? fromMap(Object? m) {
    if (m is! Map) return null;
    final lat = m['lat'], lng = m['lng'];
    if (lat is! num || lng is! num) return null;
    return RecentPlace((m['name'] ?? '') as String,
        (m['address'] ?? '') as String, lat.toDouble(), lng.toDouble());
  }

  /// Mesmo lugar (até ~50 m): não repete na lista.
  bool sameAs(RecentPlace o) =>
      (lat - o.lat).abs() < 0.0005 && (lng - o.lng).abs() < 0.0005;
}

/// Lista dos destinos recentes, do mais novo ao mais antigo.
class RecentPlacesService {
  RecentPlacesService._();
  static final instance = RecentPlacesService._();

  static const max = 20;
  static const _key = 'recentPlaces';

  /// Lê a lista guardada.
  Future<List<RecentPlace>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List)
          .map(RecentPlace.fromMap)
          .whereType<RecentPlace>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Escolheu um lugar: vai para o topo da lista.
  Future<void> add(RecentPlace p) async {
    if (p.name.trim().isEmpty) return;
    final list = [...await load()]..removeWhere((x) => x.sameAs(p));
    list.insert(0, p);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(list.take(max).map((x) => x.toMap()).toList()));
  }

  /// Recentes que combinam com o texto digitado (sem acento e maiúsculas).
  static List<RecentPlace> matching(List<RecentPlace> all, String text) {
    final q = _plain(text.trim());
    if (q.isEmpty) return all;
    return all
        .where((p) => _plain('${p.name} ${p.address}').contains(q))
        .toList();
  }

  static String _plain(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    final b = StringBuffer();
    for (final c in s.split('')) {
      final i = from.indexOf(c);
      b.write(i < 0 ? c : to[i]);
    }
    return b.toString().toLowerCase();
  }
}
