// ============================================================================
// speed_service.dart — Limites de velocidade por estado
//
// O que faz: Baixa e guarda os limites do estado onde o piloto está;
//   configurações do alerta de velocidade.
// Quem usa: MapScreen, Configurações (usar sem internet).
// Onde mexer: Arquivos: public/limites/UF.json.gz (functions/speedlimits.js).
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/radars.dart' show distanceMeters;
import '../logic/speed.dart';
import '../logic/tolls.dart';
import 'speed_fix_service.dart';
import 'toll_service.dart';

/// Limites de velocidade das vias (baixados por estado, sob demanda) e a
/// configuração dos alertas de velocidade do piloto.
class SpeedService {
  SpeedService._();
  static final instance = SpeedService._();

  // ---------------------------------------------------------- configuração

  final settings = ValueNotifier(const SpeedAlertSettings());
  bool _settingsLoaded = false;

  /// Lê as opções do alerta de velocidade (uma vez).
  Future<void> loadSettings() async {
    if (_settingsLoaded) return;
    _settingsLoaded = true;
    final p = await SharedPreferences.getInstance();
    settings.value = SpeedAlertSettings(
      roadAlert: p.getBool('speedRoadAlert') ?? false,
      tolerance: p.getInt('speedTolerance') ?? 5,
      personalMax: p.getInt('speedPersonalMax') ?? 0,
    );
  }

  /// Salva as opções do alerta de velocidade.
  Future<void> save(SpeedAlertSettings s) async {
    settings.value = s;
    final p = await SharedPreferences.getInstance();
    await p.setBool('speedRoadAlert', s.roadAlert);
    await p.setInt('speedTolerance', s.tolerance);
    await p.setInt('speedPersonalMax', s.personalMax);
  }

  // ---------------------------------------------------------- limites

  final Map<String, SpeedLimitIndex> _loaded = {};
  final Set<String> _loading = {};
  Map<String, dynamic>? _meta; // ufs: { SC: { bbox, version, ... } }
  Future<void>? _metaFuture;

  /// Estados prontos para consulta (o mapa se redesenha quando muda).
  final ready = ValueNotifier<int>(0);

  /// Lê o índice meta/limits (estados disponíveis, versão de cada arquivo).
  Future<void> _loadMeta() async {
    try {
      final doc = await FirebaseFirestore.instance.doc('meta/limits').get();
      _meta = (doc.data()?['ufs'] as Map?)?.cast<String, dynamic>();
    } catch (e) {
      debugPrint('Limites: sem índice ($e)');
    }
  }

  /// Estados cujo retângulo contém o ponto (2 perto das divisas).
  List<String> _ufsAt(double lat, double lng) {
    final m = _meta;
    if (m == null) return const [];
    return [
      for (final e in m.entries)
        if (e.key != 'BR' && e.value is Map && (e.value as Map)['bbox'] is List)
          if (_inBox(lat, lng, (e.value as Map)['bbox'] as List)) e.key,
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
    for (final uf in _ufsAt(lat, lng)) {
      if (_loaded.containsKey(uf) || !_loading.add(uf)) continue;
      _load(uf).whenComplete(() => _loading.remove(uf));
    }
  }

  /// Baixa (se a versão mudou) ou lê do celular o arquivo do estado.
  Future<void> _load(String uf) async {
    try {
      final version = ((_meta?[uf] as Map?)?['version'] as num?)?.toInt();
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/limites_$uf.json.gz');
      final prefs = await SharedPreferences.getInstance();
      Uint8List? bytes;
      if (await file.exists() && prefs.getInt('limitsVersion_$uf') == version) {
        bytes = await file.readAsBytes();
      } else {
        bytes = await FirebaseStorage.instance
            .ref('public/limites/$uf.json.gz')
            .getData(30 * 1024 * 1024);
        if (bytes == null) return;
        await file.writeAsBytes(bytes, flush: true);
        if (version != null) await prefs.setInt('limitsVersion_$uf', version);
      }
      _loaded[uf] = await compute(_parse, bytes);
      ready.value++;
      debugPrint('Limites $uf: ${_loaded[uf]!.length} pontos');
    } catch (e) {
      debugPrint('Limites $uf indisponíveis: $e');
    }
  }

  /// Estados disponíveis (para "Usar sem internet").
  Future<List<String>> availableUfs() async {
    _metaFuture ??= _loadMeta();
    await _metaFuture;
    return (_meta?.keys.where((k) => k != 'BR').toList() ?? [])..sort();
  }

  /// Já baixado e atualizado no celular?
  Future<bool> isStored(String uf) async {
    final version = ((_meta?[uf] as Map?)?['version'] as num?)?.toInt();
    final dir = await getApplicationSupportDirectory();
    return await File('${dir.path}/limites_$uf.json.gz').exists() &&
        (await SharedPreferences.getInstance()).getInt('limitsVersion_$uf') ==
            version;
  }

  /// Baixa o arquivo do estado para o celular, sem carregar na memória.
  Future<bool> prefetch(String uf) async {
    try {
      _metaFuture ??= _loadMeta();
      await _metaFuture;
      if (await isStored(uf)) return true;
      final version = ((_meta?[uf] as Map?)?['version'] as num?)?.toInt();
      final bytes = await FirebaseStorage.instance
          .ref('public/limites/$uf.json.gz')
          .getData(30 * 1024 * 1024);
      if (bytes == null) return false;
      final dir = await getApplicationSupportDirectory();
      await File('${dir.path}/limites_$uf.json.gz')
          .writeAsBytes(bytes, flush: true);
      if (version != null) {
        await (await SharedPreferences.getInstance())
            .setInt('limitsVersion_$uf', version);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Limite da via na posição (null = sem dado). [routeOffset] (navegando):
  /// distância de um ponto até a rota, para pegar o limite da pista da rota
  /// e não o da marginal.
  RoadLimit? lookup(double lat, double lng, double heading, double speed,
      {double Function(double lat, double lng)? routeOffset,
      double maxAngle = 60}) {
    // Correção de Gold/administração neste trecho e sentido: vale primeiro.
    final fix = SpeedFixService.instance.roadKmh(lat, lng, heading);
    if (fix != null) return RoadLimit(fix, false, src: 'fix');
    RoadLimit? road;
    for (final idx in _loaded.values) {
      road = idx.lookup(lat, lng,
          heading: heading,
          speed: speed,
          maxAngle: maxAngle,
          routeOffset: routeOffset);
      if (road != null) break;
    }
    // Praça de pedágio: a velocidade cai em degraus, como nas placas da
    // rodovia (110 -> 90 -> 80 -> 60 -> 40 nas cabines), e não de uma vez
    // (Ricardo, 06/11). Só vale se for menor que a da via.
    final staged = tollStage(lat, lng);
    if (staged != null && (road == null || staged.kmh < road.kmh)) return staged;
    return road;
  }

  /// Degraus antes da praça (distância até a cabine mais próxima, m).
  static const tollSteps = [(150.0, 0), (400.0, 60), (700.0, 80), (1000.0, 90)];

  /// Limite do degrau do pedágio neste ponto (null = longe de praça).
  /// O degrau das cabines usa a velocidade da praça (40, salvo correção).
  RoadLimit? tollStage(double lat, double lng) {
    final hit = tollNearDist(lat, lng, radius: tollSteps.last.$1);
    if (hit == null) return null;
    final (plaza, d) = hit;
    for (final (max, kmh) in tollSteps) {
      if (d <= max) {
        return RoadLimit(kmh == 0 ? SpeedFixService.instance.tollKmh(plaza) : kmh,
            false, src: 'toll');
      }
    }
    return null;
  }
}

extension TollNear on SpeedService {
  /// Praça de pedágio com cabine a até [radius] m do ponto.
  TollPlaza? tollNear(double lat, double lng, {double radius = 120}) =>
      tollNearDist(lat, lng, radius: radius)?.$1;

  /// Praça mais próxima a até [radius] m e a distância até a cabine.
  (TollPlaza, double)? tollNearDist(double lat, double lng, {double radius = 120}) {
    final t = TollService.instance.cached;
    if (t == null) return null;
    final box = radius / 90000 + 0.001;
    (TollPlaza, double)? best;
    for (final p in t.plazas) {
      for (final (la, lo) in p.pts) {
        if ((la - lat).abs() > box || (lo - lng).abs() > box) continue;
        final d = distanceMeters(lat, lng, la, lo);
        if (d <= radius && (best == null || d < best.$2)) best = (p, d);
      }
    }
    return best;
  }
}

/// Descompacta e monta o índice (roda fora da tela, em compute).
SpeedLimitIndex _parse(Uint8List bytes) {
  final j = jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  return SpeedLimitIndex.fromCompact(j['d'] as List);
}
