// ============================================================================
// saved_places_service.dart — Locais salvos (Casa, Trabalho e outros)
//
// O que faz: Guarda lugares com nome para ir com um toque ("Casa") ou por voz
//   ("UauGo, ir para casa").
// Privacidade: ficam SÓ no celular (SharedPreferences), nunca no servidor:
//   o endereço de casa é dado sensível e o banco é compartilhado com o grupo.
// Quem usa: HomeScreen (atalhos), MapScreen (voz).
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Um local salvo. [key]: "casa", "trabalho" ou um id para os outros.
class SavedPlace {
  final String key;
  final String name;
  final String address;
  final double lat;
  final double lng;
  const SavedPlace(this.key, this.name, this.address, this.lat, this.lng);

  Map<String, dynamic> toJson() =>
      {'k': key, 'n': name, 'a': address, 'la': lat, 'lo': lng};

  static SavedPlace? fromJson(dynamic j) {
    if (j is! Map) return null;
    final la = j['la'], lo = j['lo'], k = j['k'], n = j['n'];
    if (la is! num || lo is! num || k is! String || n is! String) return null;
    return SavedPlace(k, n, (j['a'] ?? '') as String, la.toDouble(), lo.toDouble());
  }
}

/// Os dois locais fixos (aparecem mesmo antes de salvar).
const savedHome = 'casa';
const savedWork = 'trabalho';

class SavedPlacesService {
  SavedPlacesService._();
  static final instance = SavedPlacesService._();

  static const _k = 'savedPlaces';
  final places = ValueNotifier<List<SavedPlace>>(const []);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = (await SharedPreferences.getInstance()).getString(_k);
    if (raw == null) return;
    try {
      places.value = (jsonDecode(raw) as List)
          .map(SavedPlace.fromJson)
          .whereType<SavedPlace>()
          .toList();
    } catch (_) {}
  }

  SavedPlace? get(String key) =>
      places.value.where((p) => p.key == key).firstOrNull;

  /// Salva (ou troca) o local [p.key].
  Future<void> save(SavedPlace p) async {
    places.value = [
      for (final o in places.value)
        if (o.key != p.key) o,
      p,
    ];
    await _persist();
  }

  Future<void> remove(String key) async {
    places.value = [
      for (final o in places.value)
        if (o.key != key) o,
    ];
    await _persist();
  }

  Future<void> _persist() async => (await SharedPreferences.getInstance())
      .setString(_k, jsonEncode([for (final p in places.value) p.toJson()]));
}
