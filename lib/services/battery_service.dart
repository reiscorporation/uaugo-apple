// ============================================================================
// battery_service.dart — Economia de bateria
//
// O que faz: Liga o modo econômico pela opção do usuário ou, no automático,
//   com bateria abaixo de 25% fora da tomada ou com o modo economia do celular
//   ligado.
// Quem usa: MapScreen (GPS a cada 2 s, sem prédios 3D e sem trânsito).
// Onde mexer: Limite de 25%: _check.
// ============================================================================

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import 'app_settings.dart';

/// Decide se o app deve economizar bateria agora: pela opção do piloto ou,
/// no automático, com a bateria abaixo de 25% (fora da tomada) ou com o
/// modo economia do celular ligado. Confere a cada 2 minutos.
class BatteryService {
  BatteryService._();
  static final instance = BatteryService._();

  final _battery = Battery();
  final saving = ValueNotifier<bool>(false);
  Timer? _timer;
  int _users = 0;

  /// Começa a acompanhar (a tela do mapa chama ao abrir e [stop] ao fechar).
  void start() {
    if (_users++ > 0) return;
    AppSettings.instance.batterySaver.addListener(_check);
    _check();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _check());
  }

  /// Para de acompanhar quando a última tela que usa sai.
  void stop() {
    if (--_users > 0) return;
    _timer?.cancel();
    AppSettings.instance.batterySaver.removeListener(_check);
  }

  /// Decide agora se economiza (opção do usuário ou nível da bateria).
  Future<void> _check() async {
    final mode = AppSettings.instance.batterySaver.value;
    if (mode != BatteryMode.auto) {
      saving.value = mode == BatteryMode.on;
      return;
    }
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final charging =
          state == BatteryState.charging || state == BatteryState.full;
      final osSaver = await _battery.isInBatterySaveMode;
      saving.value = osSaver || (!charging && level < 25);
    } catch (_) {
      saving.value = false;
    }
  }
}
