// ============================================================================
// toll_service.dart — Tabela de pedágios
//
// O que faz: Baixa (quando a versão muda) e guarda no celular a tabela de
//   praças de pedágio com preço (custo da viagem na prévia da rota).
// Quem usa: TripPreviewSheet.
// Onde mexer: Arquivo gerado por functions/tolls.js (todo dia 5).
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/tolls.dart';

/// Praças de pedágio do Brasil (~poucas dezenas de KB). Fica no celular e só
/// é baixada de novo quando a versão em meta/tolls muda.
class TollService {
  TollService._();
  static final instance = TollService._();

  static const _kVersion = 'tollsVersion';
  static const _file = 'pedagios.json.gz';

  TollTable? _table;
  Future<TollTable?>? _loading;

  /// Tabela pronta (lê do celular e confere versão nova); null se indisponível.
  Future<TollTable?> table() {
    if (_table != null) return Future.value(_table);
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<TollTable?> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final cache = File('${dir.path}/$_file');
      if (await cache.exists()) {
        _table = await compute(_parse, await cache.readAsBytes());
      }
      await _refresh(cache);
    } catch (e) {
      debugPrint('Pedágios indisponíveis: $e');
    }
    return _table;
  }

  /// Baixa a tabela nova (se a versão mudou).
  Future<void> _refresh(File cache) async {
    final meta = await FirebaseFirestore.instance.doc('meta/tolls').get();
    final version = (meta.data()?['version'] as num?)?.toInt();
    if (version == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_kVersion) == version && _table != null) return;
    final bytes = await FirebaseStorage.instance
        .ref('public/$_file')
        .getData(5 * 1024 * 1024);
    if (bytes == null) return;
    final parsed = await compute(_parse, bytes);
    await cache.writeAsBytes(bytes, flush: true);
    await prefs.setInt(_kVersion, version);
    _table = parsed;
  }
}

TollTable _parse(Uint8List bytes) => TollTable.fromJson(
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
