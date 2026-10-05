// ============================================================================
// poi_service.dart — Lombadas, postos e pedágios por estado
//
// O que faz: Baixa do Storage só o estado onde o piloto está (ou os escolhidos
//   em "Usar sem internet"), guarda no celular e consulta o índice.
// Quem usa: MapScreen e Configurações (usar sem internet).
// Onde mexer: Arquivos: public/pois/UF.json.gz (gerados por
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

/// Lombadas e postos policiais (OpenStreetMap), baixados por estado sob
/// demanda e guardados no celular: rodando, não consulta o Firebase.
class PoiService {
  PoiService._();
  static final instance = PoiService._();

  final Map<String, PoiIndex> _loaded = {};
  final Set<String> _loading = {};
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
    for (final e in m.entries) {
      final box = (e.value as Map?)?['bbox'];
      if (box is! List || !_inBox(lat, lng, box)) continue;
      final uf = e.key;
      if (_loaded.containsKey(uf) || !_loading.add(uf)) continue;
      _load(uf).whenComplete(() => _loading.remove(uf));
    }
  }

  /// Baixa (se a versão mudou) ou lê do celular o arquivo do estado.
  Future<void> _load(String uf) async {
    try {
      final version = ((_meta?[uf] as Map?)?['version'] as num?)?.toInt();
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/pois_$uf.json.gz');
      final prefs = await SharedPreferences.getInstance();
      Uint8List? bytes;
      if (await file.exists() && prefs.getInt('poisVersion_$uf') == version) {
        bytes = await file.readAsBytes();
      } else {
        bytes = await FirebaseStorage.instance
            .ref('public/pois/$uf.json.gz')
            .getData(10 * 1024 * 1024);
        if (bytes == null) return;
        await file.writeAsBytes(bytes, flush: true);
        if (version != null) await prefs.setInt('poisVersion_$uf', version);
      }
      final base = _nextId;
      _nextId += 10000000;
      _loaded[uf] = await compute(_parse, (bytes, base));
      debugPrint('Lombadas/postos $uf: ${_loaded[uf]!.length}');
    } catch (e) {
      debugPrint('Lombadas/postos $uf indisponíveis: $e');
    }
  }

  /// Baixa o arquivo do estado para o celular, sem carregar na memória.
  Future<bool> prefetch(String uf) async {
    try {
      _metaFuture ??= _loadMeta();
      await _metaFuture;
      final version = ((_meta?[uf] as Map?)?['version'] as num?)?.toInt();
      if (version == null) return false; // estado ainda sem dados
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/pois_$uf.json.gz');
      final prefs = await SharedPreferences.getInstance();
      if (await file.exists() && prefs.getInt('poisVersion_$uf') == version) {
        return true;
      }
      final bytes = await FirebaseStorage.instance
          .ref('public/pois/$uf.json.gz')
          .getData(10 * 1024 * 1024);
      if (bytes == null) return false;
      await file.writeAsBytes(bytes, flush: true);
      await prefs.setInt('poisVersion_$uf', version);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pontos a até [meters] do piloto, em todos os estados carregados.
  List<Poi> near(double lat, double lng, double meters) => [
        for (final idx in _loaded.values) ...idx.near(lat, lng, meters),
      ];
}

/// Descompacta e monta o índice (roda fora da tela, em compute).
PoiIndex _parse((Uint8List, int) a) {
  final j =
      jsonDecode(utf8.decode(gzip.decode(a.$1))) as Map<String, dynamic>;
  return PoiIndex.fromCompact(j['d'] as List, idBase: a.$2);
}
