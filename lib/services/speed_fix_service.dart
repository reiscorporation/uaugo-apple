// lib/services/speed_fix_service.dart
//
// O que faz: Correções de velocidade feitas pelos usuários Gold e pela
//   administração: limite de radar, velocidade da praça de pedágio e limite
//   da via num trecho. O app grava o relato em speedReports/{chave}/reports/
//   {uid}; o servidor (onSpeedReport) publica em speedFixes/{chave} quando 1
//   administrador ou 2 usuários Gold informam a mesma velocidade (regra do
//   Ricardo, 05/11). Todos os apps leem speedFixes e usam na hora.
// Usado por: MapScreen (avisos, velocímetro), SpeedService (limite da via e
//   pedágio), RadarIndex (limite do radar).

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../logic/geo.dart';
import '../logic/radars.dart';
import '../logic/tolls.dart';
import 'hazard_service.dart';

/// Uma correção publicada: [kind] 'r' radar, 't' pedágio, 'v' via.
class SpeedFix {
  final String kind;
  final double lat;
  final double lng;
  final int dir; // graus; -1 = os dois sentidos
  final int kmh;
  const SpeedFix(this.kind, this.lat, this.lng, this.dir, this.kmh);
}

/// Correções de velocidade (radar, pedágio, via) aprovadas.
class SpeedFixService {
  SpeedFixService._();
  static final instance = SpeedFixService._();

  /// Velocidade padrão das praças de pedágio (cabines), sem correção.
  static const tollDefaultKmh = 40;

  /// Até onde (m) uma correção da via vale em volta do ponto marcado.
  static const roadRadius = 300.0;

  final fixes = ValueNotifier<Map<String, SpeedFix>>({});
  StreamSubscription? _sub;

  /// Começa a ouvir as correções (poucas; chegam na hora para todos).
  void start() {
    if (_sub != null) return;
    RadarIndex.limitFix = radarKmh;
    _sub = FirebaseFirestore.instance
        .collection('speedFixes')
        .limit(5000)
        .snapshots()
        .listen((s) {
      fixes.value = {
        for (final d in s.docs)
          if (_parse(d.data()) case final f?) d.id: f,
      };
    }, onError: (e) {
      debugPrint('Correções de velocidade indisponíveis: $e');
      _sub = null;
    });
  }

  static SpeedFix? _parse(Map<String, dynamic> d) {
    final la = d['lat'], lo = d['lng'], k = d['kmh'];
    if (la is! num || lo is! num || k is! num) return null;
    return SpeedFix('${d['kind'] ?? ''}', la.toDouble(), lo.toDouble(),
        (d['dir'] as num?)?.toInt() ?? -1, k.toInt());
  }

  static String radarKey(FixedRadar r) =>
      'r_${r.lat.toStringAsFixed(5)},${r.lng.toStringAsFixed(5)}';
  static String tollKey(TollPlaza p) => 't_${p.key}';

  /// Trecho da via: quadrado de ~220 m e o sentido (8 direções).
  static String roadKey(double lat, double lng, double heading) {
    final d = heading < 0 ? 8 : ((heading % 360) / 45).round() % 8;
    return 'v_${(lat * 500).round()}_${(lng * 500).round()}_$d';
  }

  /// Limite corrigido do radar (null = sem correção).
  int? radarKmh(FixedRadar r) => fixes.value[radarKey(r)]?.kmh;

  /// Velocidade da praça (40, salvo correção).
  int tollKmh(TollPlaza p) => fixes.value[tollKey(p)]?.kmh ?? tollDefaultKmh;

  /// Limite corrigido da via perto do ponto, no sentido [heading].
  int? roadKmh(double lat, double lng, double heading) {
    SpeedFix? best;
    var bd = roadRadius;
    for (final f in fixes.value.values) {
      if (f.kind != 'v') continue;
      if ((f.lat - lat).abs() > 0.004 || (f.lng - lng).abs() > 0.004) continue;
      if (f.dir >= 0 && heading >= 0 && angleDiff(f.dir.toDouble(), heading) > 45) {
        continue;
      }
      final d = distanceMeters(lat, lng, f.lat, f.lng);
      if (d < bd) {
        bd = d;
        best = f;
      }
    }
    return best?.kmh;
  }

  /// Pode confirmar/corrigir? (usuário Gold ou administrador)
  Future<bool> canEdit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || FirebaseAuth.instance.currentUser!.isAnonymous) return false;
    return HazardService.instance.isGold(uid);
  }

  /// Grava a confirmação/correção deste usuário (uma por pessoa e lugar).
  Future<void> report(String key,
      {required String kind,
      required double lat,
      required double lng,
      int dir = -1,
      required int kmh}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .doc('speedReports/$key/reports/$uid')
        .set({
      'kind': kind,
      'lat': lat,
      'lng': lng,
      'dir': dir < 0 ? -1 : dir % 360,
      // 0 = radar não existe (só radar).
      'kmh': kmh == 0 && kind == 'r' ? 0 : max(20, min(130, kmh)),
      'at': FieldValue.serverTimestamp(),
    });
  }
}
