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
import 'package:firebase_auth/firebase_auth.dart';
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

  /// Última conferência da versão da tabela.
  DateTime _checkedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Tabela pronta (lê do celular e confere versão nova); null se indisponível.
  Future<TollTable?> table() {
    if (_table != null) {
      // Os preços são atualizados ao longo do dia (rotina do n8n): confere a
      // versão de novo a cada 30 min, sem segurar quem pediu a tabela.
      if (DateTime.now().difference(_checkedAt) > const Duration(minutes: 30)) {
        _checkedAt = DateTime.now();
        getApplicationSupportDirectory()
            .then((d) => _refresh(File('${d.path}/$_file')))
            .catchError((_) {});
      }
      return Future.value(_table);
    }
    _checkedAt = DateTime.now();
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

  /// O piloto informa (ou confirma) o valor de uma praça: carro e moto em
  /// R\$ (moto 0 = isenta; null = não sabe). Um relato por pessoa e praça;
  /// vale para todos quando outro piloto informar valor parecido
  /// (functions: onTollReport). Precisa de conta (não anônima).
  Future<void> report(String key, {double? car, double? moto}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('sem login');
    await FirebaseFirestore.instance
        .doc('tollReports/$key/reports/$uid')
        .set({
      'car': car,
      'moto': moto,
      'at': FieldValue.serverTimestamp(),
    });
  }
}

TollTable _parse(Uint8List bytes) => TollTable.fromJson(
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
