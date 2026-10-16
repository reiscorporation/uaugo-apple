// ============================================================================
// radar_service.dart — Base de radares
//
// O que faz: Baixa (quando a versão muda) e guarda no celular a base nacional
//   de radares e trechos da PRF.
// Quem usa: MapScreen.
// Onde mexer: Arquivo gerado por functions/radars.js.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/radars.dart';

/// Radares fixos do Brasil + trechos de radar portátil da PRF.
///
/// O arquivo (~0,5 MB) é conferido todo dia pela Cloud Function
/// `updateRadars`. O app guarda uma cópia no celular e só baixa de novo
/// quando a versão em meta/radars muda: funciona sem sinal na estrada.
class RadarService {
  RadarService._();
  static final instance = RadarService._();

  final index = ValueNotifier<RadarIndex?>(null);
  bool _started = false;

  static const _kVersion = 'radarsVersion';
  static const _file = 'radares.json.gz';

  /// Lê a base do celular e confere se há versão nova no servidor.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final cache = File('${dir.path}/$_file');
      if (await cache.exists()) {
        index.value = await compute(_parse, await cache.readAsBytes());
      }
      await _refresh(cache);
    } catch (e) {
      debugPrint('Radares indisponíveis: $e');
      _started = false; // tenta de novo na próxima vez
    }
  }

  /// Baixa a base nova (se a versão mudou) e troca a que está em uso.
  Future<void> _refresh(File cache) async {
    final meta = await FirebaseFirestore.instance.doc('meta/radars').get();
    final version = (meta.data()?['version'] as num?)?.toInt();
    if (version == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_kVersion) == version && index.value != null) return;
    final bytes = await FirebaseStorage.instance
        .ref('public/$_file')
        .getData(20 * 1024 * 1024);
    if (bytes == null) return;
    final parsed = await compute(_parse, bytes);
    await cache.writeAsBytes(bytes, flush: true);
    await prefs.setInt(_kVersion, version);
    index.value = parsed;
    debugPrint('Radares atualizados: ${parsed.radarCount} fixos, '
        '${parsed.stretchCount} trechos PRF');
  }
}

/// Descompacta e monta o índice (roda fora da tela, em compute).
RadarIndex _parse(Uint8List bytes) => RadarIndex.fromJson(
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
