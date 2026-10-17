// ============================================================================
// car_service.dart — Modo carro (Android Auto)
//
// O que faz: Manda para a tela do carro (android/.../CarBridge.kt, canal
//   "uaugo/car") a próxima manobra, a chegada, a rota e a posição; recebe os
//   botões do carro (Radar, Perigo, Encerrar). Com o carro conectado e
//   navegando, o mapa mantém GPS, voz e avisos mesmo com o celular bloqueado.
// Quem usa: MapScreen.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CarService {
  CarService._();
  static final instance = CarService._();

  static const _ch = MethodChannel('uaugo/car');

  /// A tela do carro está aberta.
  final connected = ValueNotifier<bool>(false);

  /// Botões do carro: "radar", "hazard", "stop".
  final _actions = StreamController<String>.broadcast();
  Stream<String> get actions => _actions.stream;

  bool _started = false;
  String _routeSig = '';
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void init() {
    if (_started) return;
    _started = true;
    _ch.setMethodCallHandler((c) async {
      if (c.method == 'action') _actions.add(c.arguments as String);
      if (c.method == 'connected') connected.value = c.arguments == true;
    });
    _ch.invokeMethod<bool>('connected').then((v) => connected.value = v == true,
        onError: (_) {});
  }

  /// Estado da navegação (no máximo 1 vez por segundo). [text] null = sem
  /// navegação (o carro mostra "Abra a navegação no UauGo").
  void update({
    required double lat,
    required double lng,
    required double bearing,
    required int speedKmh,
    int limitKmh = 0,
    String? text,
    String maneuver = '',
    double meters = 0,
    double remainingM = 0,
    DateTime? eta,
    String? alert,
  }) {
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 900)) return;
    _last = now;
    _ch.invokeMethod('update', {
      'lat': lat,
      'lng': lng,
      'bearing': bearing,
      'speedKmh': speedKmh,
      'limitKmh': limitKmh,
      if (text != null) ...{
        'text': text,
        'maneuver': maneuver,
        'meters': meters,
        'remainingM': remainingM,
        'eta': eta?.millisecondsSinceEpoch ?? 0,
        if (alert != null) 'alert': alert,
      },
    }).catchError((_) => null);
  }

  /// Rota (enviada só quando muda; no máximo ~800 pontos).
  void route(List<(double, double)> pts) {
    final sig = pts.isEmpty ? '' : '${pts.length}:${pts.first}:${pts.last}';
    if (sig == _routeSig) return;
    _routeSig = sig;
    final step = (pts.length / 800).ceil().clamp(1, 1 << 20);
    final flat = <double>[
      for (var i = 0; i < pts.length; i += step) ...[pts[i].$1, pts[i].$2],
      if (pts.isNotEmpty) ...[pts.last.$1, pts.last.$2],
    ];
    _ch.invokeMethod('route', flat).catchError((_) => null);
  }

  void clear() {
    _routeSig = '';
    _ch.invokeMethod('clear').catchError((_) => null);
  }
}
