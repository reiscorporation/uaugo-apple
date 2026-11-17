// usage_service.dart — Tempo de uso de cada piloto (para premiar no futuro)
//
// O que: soma, por conta, o tempo com o app aberto na tela, o tempo e os km
// rodados com o mapa aberto (GPS de verdade, não simulação) e os dias de
// uso. Fica em users/{uid} (só o dono lê e escreve), no total e por mês:
//   usage.appSeconds, usage.driveSeconds, usage.driveMeters, usage.days
//   usageByMonth.2026-11.appSeconds ... (para campanhas por mês)
// Pedido do Ricardo (16/11): no futuro, bonificar os pilotos com adesivos,
// camisetas, canecas etc. pelo uso.
//
// Como: acumula na memória e grava somando (FieldValue.increment) a cada
// 5 minutos e quando o app sai da tela — poucas gravações por hora.
//
// Onde mexer: intervalo de gravação (_flushEvery); o que conta como
// "rodando" fica no MapScreen (addDrive).
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsageService with WidgetsBindingObserver {
  UsageService._();
  static final instance = UsageService._();

  static const _flushEvery = Duration(minutes: 5);
  static const _kLastDay = 'usageLastDay';

  DateTime? _since; // app na tela desde
  double _appS = 0, _driveS = 0, _driveM = 0;
  int _days = 0;
  bool _started = false;

  /// Liga a contagem (uma vez, no início do app).
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _since = DateTime.now();
    _countDay();
    Timer.periodic(_flushEvery, (_) => flush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _since ??= DateTime.now();
      _countDay();
    } else if (s == AppLifecycleState.paused ||
        s == AppLifecycleState.detached ||
        s == AppLifecycleState.hidden) {
      flush();
      _since = null;
    }
  }

  /// Rodou [seconds] e [meters] com o mapa aberto (GPS de verdade).
  void addDrive(double seconds, double meters) {
    if (seconds <= 0 || seconds > 120 || meters < 0 || meters > 5000) return;
    _driveS += seconds;
    _driveM += meters;
  }

  /// Primeiro uso do dia: conta um dia.
  Future<void> _countDay() async {
    try {
      final p = await SharedPreferences.getInstance();
      final today = _day(DateTime.now());
      if (p.getString(_kLastDay) == today) return;
      await p.setString(_kLastDay, today);
      _days++;
    } catch (_) {}
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Grava o que acumulou (somando ao que já está no servidor).
  Future<void> flush() async {
    final since = _since;
    if (since != null) {
      final now = DateTime.now();
      _appS += now.difference(since).inMilliseconds / 1000;
      _since = now;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final app = _appS.round(), driveS = _driveS.round(), driveM = _driveM.round();
    final days = _days;
    if (uid == null || (app < 5 && driveS == 0 && days == 0)) return;
    _appS -= app;
    _driveS -= driveS;
    _driveM -= driveM;
    _days = 0;
    final n = DateTime.now();
    final month = '${n.year}-${n.month.toString().padLeft(2, '0')}';
    Map<String, Object> inc(String prefix) => {
          if (app > 0) '$prefix.appSeconds': FieldValue.increment(app),
          if (driveS > 0) '$prefix.driveSeconds': FieldValue.increment(driveS),
          if (driveM > 0) '$prefix.driveMeters': FieldValue.increment(driveM),
          if (days > 0) '$prefix.days': FieldValue.increment(days),
        };
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      // update() aceita "usage.appSeconds" (caminho); se o documento ainda
      // não existe, cria com set(merge).
      await ref.update({
        ...inc('usage'),
        ...inc('usageByMonth.$month'),
        'usage.lastAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) async {
        await ref.set({
          'usage': {
            if (app > 0) 'appSeconds': FieldValue.increment(app),
            if (driveS > 0) 'driveSeconds': FieldValue.increment(driveS),
            if (driveM > 0) 'driveMeters': FieldValue.increment(driveM),
            if (days > 0) 'days': FieldValue.increment(days),
            'lastAt': FieldValue.serverTimestamp(),
          },
          'usageByMonth': {
            month: {
              if (app > 0) 'appSeconds': FieldValue.increment(app),
              if (driveS > 0) 'driveSeconds': FieldValue.increment(driveS),
              if (driveM > 0) 'driveMeters': FieldValue.increment(driveM),
              if (days > 0) 'days': FieldValue.increment(days),
            },
          },
        }, SetOptions(merge: true));
      });
      if (kDebugMode) debugPrint('Uso gravado: app=${app}s rodando=${driveS}s ${driveM}m dias=$days');
    } catch (e) {
      // Sem internet: devolve para a próxima tentativa.
      _appS += app;
      _driveS += driveS;
      _driveM += driveM;
      _days += days;
      if (kDebugMode) debugPrint('Uso não gravado: $e');
    }
  }
}
