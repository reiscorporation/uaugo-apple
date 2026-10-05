// ============================================================================
// history_service.dart — "Minhas viagens" no celular
//
// O que faz: Lê e grava o arquivo viagens.json (pasta do app). Não usa o
//   Firebase.
// Quem usa: MapScreen (grava), HistoryScreen e gastos (lê/atualiza).
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/trip_record.dart';

/// "Minhas viagens": histórico guardado SÓ no celular (arquivo local).
/// Não usa o Firebase: não gasta leituras/gravações e é privado do piloto.
class HistoryService {
  HistoryService._();
  static final instance = HistoryService._();

  /// Lista mais recente primeiro (a tela se atualiza quando muda).
  final trips = ValueNotifier<List<TripRecord>>(const []);
  bool _loaded = false;
  Future<void>? _loading;

  /// Arquivo do histórico na pasta do app.
  Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/viagens.json');

  /// Lê o arquivo uma única vez (as próximas chamadas esperam a mesma leitura).
  Future<void> load() => _loading ??= _load();

  /// Leitura do arquivo; se estiver corrompido, começa com a lista vazia.
  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        trips.value = list
            .map(TripRecord.fromJson)
            .whereType<TripRecord>()
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      }
    } catch (e) {
      debugPrint('Histórico ilegível: $e');
    }
    _loaded = true;
  }

  /// Uma viagem pelo id (null se não existir).
  Future<TripRecord?> get(String id) async {
    await load();
    for (final t in trips.value) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Grava (ou atualiza, se já existir com o mesmo id).
  Future<void> save(TripRecord r) async {
    await load();
    final list = [
      r,
      for (final t in trips.value)
        if (t.id != r.id) t
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    trips.value = list;
    await _write();
  }

  /// Apaga uma viagem do celular.
  Future<void> delete(String id) async {
    await load();
    trips.value = [
      for (final t in trips.value)
        if (t.id != id) t
    ];
    await _write();
  }

  /// Grava a lista inteira no arquivo.
  Future<void> _write() async {
    if (!_loaded) return;
    final f = await _file();
    await f.writeAsString(
        jsonEncode([for (final t in trips.value) t.toJson()]),
        flush: true);
  }
}
