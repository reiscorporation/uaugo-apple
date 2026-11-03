// ============================================================================
// live_sos.dart — Localização em tempo real do SOS
//
// O que faz: Enquanto o SOS está ativo, grava a posição a cada 15 s em
//   liveSos/{token}. Quem tem o link vê em public/sos.html, sem login (lê pela
//   função sosLive, porque o Firestore só aceita o app). Para em
//   "Estou bem" ou depois de 2 h; o TTL do Firestore apaga o documento.
// Quem usa: MapScreen (SOS). A posição vem do GPS da tela do mapa, que entra no
//   serviço em primeiro plano; o relógio daqui cobre o app fora do mapa.
// Onde mexer: Intervalo e duração: as constantes abaixo.
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LiveSos {
  static const _every = Duration(seconds: 15);
  static const _limit = Duration(hours: 2);

  /// Token do SOS em andamento; null = nada sendo compartilhado.
  static final active = ValueNotifier<String?>(null);

  static String _uid = '', _name = '';
  static DateTime _end = DateTime(0);
  static DateTime? _sent;
  static bool _created = false;
  static Timer? _timer;

  static DocumentReference<Map<String, dynamic>> _doc(String token) =>
      FirebaseFirestore.instance.collection('liveSos').doc(token);

  static String link(String token) =>
      'https://helpaitechcomboio.web.app/sos?t=$token';

  /// Liga o compartilhamento (ou segue o que já está ligado) e devolve o link.
  static String start(String uid, String name, {Position? first}) {
    var token = active.value;
    if (token == null) {
      final r = Random.secure();
      token = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      _uid = uid;
      _name = name.length > 60 ? name.substring(0, 60) : name;
      _end = DateTime.now().add(_limit);
      _sent = null;
      _created = false;
      _timer = Timer.periodic(_every, (_) => _tick());
      active.value = token;
    }
    if (first != null) {
      push(first);
    } else {
      _tick();
    }
    return link(token);
  }

  /// Nova leitura do GPS; grava no máximo uma a cada 15 s.
  static void push(Position p) {
    final token = active.value;
    if (token == null) return;
    final now = DateTime.now();
    if (now.isAfter(_end)) {
      stop();
      return;
    }
    final sent = _sent;
    if (sent != null && now.difference(sent) < _every) return;
    _sent = now;
    final pos = {
      'lat': p.latitude,
      'lng': p.longitude,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final write = _created
        ? _doc(token).update(pos)
        : _doc(token).set({
            ...pos,
            'uid': _uid,
            'name': _name,
            'active': true,
            'expiresAt': Timestamp.fromDate(_end),
          });
    _created = true;
    write.catchError((Object e) => debugPrint('SOS: $e'));
  }

  /// Sem leitura do mapa (saiu da tela do mapa): pede a posição ao GPS.
  static Future<void> _tick() async {
    final sent = _sent;
    if (sent != null && DateTime.now().difference(sent) < _every * 2) return;
    try {
      push(await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 10)));
    } catch (_) {}
  }

  /// "Estou bem", ou acabou o tempo.
  static void stop() {
    final token = active.value;
    if (token == null) return;
    _timer?.cancel();
    _timer = null;
    active.value = null;
    if (_created) {
      _doc(token).update({
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }).catchError((Object e) => debugPrint('SOS: $e'));
    }
  }
}
