// ============================================================================
// mini_streets_service.dart — Ruas do minimapa do 3D
//
// O que faz: Baixa os quadrados de ruas (0,02 grau, ~2,2 km) em volta do
//   piloto e entrega para o minimapa do 3D desenhar todas as ruas e travessas
//   (pedido de 08/11). Os quadrados são gerados no PC do Ricardo a partir do
//   OpenStreetMap (scripts/gerar-ruas-minimapa.py) e ficam na VPS. Guarda no
//   celular o que já baixou (vale 30 dias).
// Quem usa: MapScreen (_feedStreets3d) -> Sim3DController.streets.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MiniStreetsService {
  MiniStreetsService._();
  static final instance = MiniStreetsService._();

  static const base = 'https://motor.200-141-16-177.sslip.io/ruas';
  static const tile = 0.02;
  static const _maxAge = Duration(days: 30);

  /// Quadrados na memória: "ilat_ilng" -> lista de ruas (JSON) ou null =
  /// não existe (mar, fora do Brasil).
  final _mem = <String, List<dynamic>?>{};
  final _loading = <String, Future<List<dynamic>?>>{};

  /// Falhou há pouco (servidor fora, sem internet): espera antes de pedir
  /// de novo (09/11: pedia os 9 quadrados a cada segundo).
  final _failedAt = <String, DateTime>{};
  static const _retryAfter = Duration(minutes: 5);

  static String keyOf(double lat, double lng) =>
      '${(lat / tile).floor()}_${(lng / tile).floor()}';

  /// Quadrado do ponto e os 8 vizinhos.
  static List<String> around(double lat, double lng) {
    final a = (lat / tile).floor(), b = (lng / tile).floor();
    return [
      for (var i = -1; i <= 1; i++)
        for (var j = -1; j <= 1; j++) '${a + i}_${b + j}',
    ];
  }

  Future<File> _file(String k) async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/ruas');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$k.json.gz');
  }

  Future<List<dynamic>?> _get(String k) async {
    if (_mem.containsKey(k)) return _mem[k];
    final f0 = _failedAt[k];
    if (f0 != null && DateTime.now().difference(f0) < _retryAfter) return null;
    return _loading[k] ??= () async {
      List<dynamic>? ways;
      try {
        final f = await _file(k);
        List<int>? gz;
        if (await f.exists() &&
            DateTime.now().difference(await f.lastModified()) < _maxAge) {
          gz = await f.readAsBytes();
        } else {
          final r = await http.get(Uri.parse('$base/$k.json.gz')).timeout(const Duration(seconds: 15));
          if (r.statusCode == 200) {
            gz = r.bodyBytes;
            await f.writeAsBytes(gz);
          } else if (r.statusCode == 404) {
            gz = null; // quadrado sem ruas
          } else {
            throw 'HTTP ${r.statusCode}';
          }
        }
        if (gz != null) {
          final j = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
          ways = j['w'] as List<dynamic>?;
        }
        _mem[k] = ways;
        // Memória: guarda só os mais recentes.
        if (_mem.length > 36) _mem.remove(_mem.keys.first);
      } catch (e) {
        _failedAt[k] = DateTime.now();
        debugPrint('Ruas do minimapa ($k): $e');
        // Falhou (sem internet): tenta de novo na próxima vez.
      } finally {
        _loading.remove(k);
      }
      return ways;
    }();
  }

  /// Ruas dos 9 quadrados em volta, num JSON só (lista de ruas no formato
  /// do gerador: [classe, lat0, lng0, dlat, dlng, ...] em 1e-5 grau).
  Future<String?> nearJson(double lat, double lng) async {
    final keys = around(lat, lng);
    final parts = await Future.wait(keys.map(_get));
    final all = <dynamic>[for (final p in parts) ...?p];
    if (all.isEmpty) return null;
    return jsonEncode(all);
  }
}
