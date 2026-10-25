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
import 'package:geolocator/geolocator.dart';

import '../models/hazard.dart';
import 'auth_service.dart';
import 'hazard_service.dart';
import '../l10n/i18n.dart';

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
      if (c.method == 'action') {
        final a = c.arguments as String;
        // Mapa aberto no celular: ele cuida. Senão, os botões ainda valem.
        if (_actions.hasListener) {
          _actions.add(a);
        } else {
          _handleWithoutMap(a);
        }
      }
      if (c.method == 'connected') connected.value = c.arguments == true;
    });
    _ch.invokeMethod<bool>('connected').then((v) => connected.value = v == true,
        onError: (_) {});
  }

  /// Aviso curto na tela do carro.
  void toast(String text) =>
      _ch.invokeMethod('toast', text).catchError((_) => null);

  /// Botão do carro com o UauGo fora do mapa (tela inicial, outra tela):
  /// Radar/Perigo marcam o alerta na posição atual; Encerrar não tem o que
  /// encerrar.
  Future<void> _handleWithoutMap(String a) async {
    final type = switch (a) {
      'radar' => HazardType.radar,
      'hazard' => HazardType.danger,
      // Lista de alertas do carro: "hazard:police", "hazard:pothole"...
      final x when x.startsWith('hazard:') => HazardType.fromName(x.substring(7)),
      _ => null,
    };
    if (type == null) {
      toast(tr('Nenhuma navegação em andamento'));
      return;
    }
    if (AuthService.isAnonymous) {
      toast(tr('Entre na sua conta no celular para marcar alertas'));
      return;
    }
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition();
      final uid = AuthService.user?.uid;
      if (uid == null) return;
      await HazardService.instance.report(type, p.latitude, p.longitude, uid);
      toast(tr('Alerta enviado: {0}', [type.label]));
    } catch (_) {
      toast(tr('Não foi possível marcar o alerta'));
    }
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
    String? banner,
    String vehicle = '🏍️',
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
      'lang': I18n.lang.value, // textos da tela do carro
      // Valem com ou sem rota (Só dirigir): contagem do radar, faixa amarela
      // de aviso e o ícone do veículo.
      if (alert != null) 'alert': alert,
      if (banner != null) 'banner': banner,
      'vehicle': vehicle,
      if (text != null) ...{
        'text': text,
        'maneuver': maneuver,
        'meters': meters,
        'remainingM': remainingM,
        'eta': eta?.millisecondsSinceEpoch ?? 0,
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
