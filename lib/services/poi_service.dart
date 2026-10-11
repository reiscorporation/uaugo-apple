// ============================================================================
// poi_service.dart — Postos, pedágios, lombadas e semáforos por estado
//
// O que faz: Baixa do Storage só o estado onde o piloto está (ou os escolhidos
//   em "Usar sem internet"), guarda no celular e consulta o índice.
//   Lombadas e semáforos são opcionais: só baixa se o aviso estiver ligado
//   (Configurações → Outros avisos).
// Quem usa: MapScreen e Configurações (usar sem internet).
// Onde mexer: Arquivos: public/pois/UF.json.gz (postos e pedágios),
//   public/lombadas/UF.json.gz e public/semaforos/UF.json.gz (gerados por
//   functions/pois.js).
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/pois.dart';
import 'app_settings.dart';

/// Postos policiais, pedágios, lombadas e semáforos (OpenStreetMap),
/// baixados por estado sob demanda e guardados no celular: rodando, não
/// consulta o Firebase.
class PoiService {
  PoiService._();
  static final instance = PoiService._();

  /// Índices carregados, por "pasta/UF" (ex.: "lombadas/SC").
  final Map<String, PoiIndex> _loaded = {};
  final Set<String> _loading = {};

  /// Arquivos que falharam nesta versão (não tenta de novo a cada GPS).
  final Map<String, int?> _failed = {};
  Map<String, dynamic>? _meta;
  Future<void>? _metaFuture;
  int _nextId = 0;

  /// Lê o índice meta/pois (estados disponíveis, versão de cada arquivo).
  Future<void> _loadMeta() async {
    try {
      final doc = await FirebaseFirestore.instance.doc('meta/pois').get();
      _meta = (doc.data()?['ufs'] as Map?)?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('Lombadas/postos: sem índice ($e)');
    }
  }

  /// Pastas a baixar: postos/pedágios sempre; lombadas e semáforos só se o
  /// piloto ligou o aviso. [info] = dados do estado em meta/pois (arquivos
  /// antigos, sem lombadas/semáforos separados, não têm esses tamanhos).
  static List<String> _folders(Map? info) {
    final a = AppSettings.instance.alerts.value;
    return [
      'pois',
      if (a.bumps != AlertMode.off && info?['bumpBytes'] != null) 'lombadas',
      if (a.signals && info?['signalBytes'] != null) 'semaforos',
    ];
  }

  /// O ponto está no retângulo do estado (com 5 km de folga nas divisas)?
  static bool _inBox(double lat, double lng, List b) =>
      lat >= (b[0] as num) - 0.05 &&
      lat <= (b[2] as num) + 0.05 &&
      lng >= (b[1] as num) - 0.05 &&
      lng <= (b[3] as num) + 0.05;

  /// Garante os dados do estado onde o piloto está (baixa uma vez e guarda).
  Future<void> ensureFor(double lat, double lng) async {
    _metaFuture ??= _loadMeta();
    await _metaFuture;
    final m = _meta;
    if (m == null) return;
    // Aviso desligado: tira da memória o que não é mais usado.
    final a = AppSettings.instance.alerts.value;
    _loaded.removeWhere((k, _) =>
        (k.startsWith('lombadas/') && a.bumps == AlertMode.off) ||
        (k.startsWith('semaforos/') && !a.signals));
    for (final e in m.entries) {
      final info = e.value as Map?;
      final box = info?['bbox'];
      if (box is! List || !_inBox(lat, lng, box)) continue;
      final version = (info?['version'] as num?)?.toInt();
      for (final folder in _folders(info)) {
        final key = '$folder/${e.key}';
        if (_loaded.containsKey(key)) continue;
        if (_failed.containsKey(key) && _failed[key] == version) continue;
        if (!_loading.add(key)) continue;
        _load(folder, e.key, version).whenComplete(() => _loading.remove(key));
      }
    }
  }

  /// Arquivo do estado no celular, baixando se a versão mudou.
  Future<Uint8List?> _bytes(String folder, String uf, int? version) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/${folder}_$uf.json.gz');
    final prefs = await SharedPreferences.getInstance();
    final kVersion = 'poisVersion_${folder}_$uf';
    if (await file.exists() && prefs.getInt(kVersion) == version) {
      return file.readAsBytes();
    }
    final bytes = await FirebaseStorage.instance
        .ref('public/$folder/$uf.json.gz')
        .getData(10 * 1024 * 1024);
    if (bytes == null) return null;
    await file.writeAsBytes(bytes, flush: true);
    if (version != null) await prefs.setInt(kVersion, version);
    return bytes;
  }

  /// Baixa (se a versão mudou) ou lê do celular e carrega na memória.
  Future<void> _load(String folder, String uf, int? version) async {
    final key = '$folder/$uf';
    try {
      final bytes = await _bytes(folder, uf, version);
      if (bytes == null) return;
      final base = _nextId;
      _nextId += 10000000;
      _loaded[key] = await compute(_parse, (bytes, base));
      debugPrint('POIs $key: ${_loaded[key]!.length}');
    } catch (e) {
      _failed[key] = version;
      debugPrint('POIs $key indisponíveis: $e');
    }
  }

  /// Baixa os arquivos do estado para o celular, sem carregar na memória.
  Future<bool> prefetch(String uf) async {
    try {
      _metaFuture ??= _loadMeta();
      await _metaFuture;
      final info = _meta?[uf] as Map?;
      final version = (info?['version'] as num?)?.toInt();
      if (version == null) return false; // estado ainda sem dados
      for (final folder in _folders(info)) {
        if (await _bytes(folder, uf, version) == null) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pontos a até [meters] do piloto, em todos os estados carregados.
  List<Poi> near(double lat, double lng, double meters) => [
        for (final idx in _loaded.values) ...idx.near(lat, lng, meters),
      ];

  /// Há semáforo a até [meters] de (lat, lng)? (Voz: "no semáforo, vire".)
  bool signalNear(double lat, double lng, {double meters = 35}) =>
      _loaded.values.any((idx) => idx.signalNear(lat, lng, meters));
}

/// Descompacta e monta o índice (roda fora da tela, em compute).
PoiIndex _parse((Uint8List, int) a) {
  final j =
      jsonDecode(utf8.decode(gzip.decode(a.$1))) as Map<String, dynamic>;
  return PoiIndex.fromCompact((j['d'] as List?) ?? const [],
      idBase: a.$2, signals: j['s'] as List?);
}
