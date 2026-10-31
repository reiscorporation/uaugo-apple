// ============================================================================
// car_service.dart — Modo carro (Android Auto)
//
// O que faz: Manda para a tela do carro (android/.../CarBridge.kt, canal
//   "uaugo/car") a próxima manobra, a chegada, a rota e a posição; recebe os
//   botões do carro (Radar, Perigo, Encerrar). Com o carro conectado e
//   navegando, o mapa mantém GPS, voz e avisos mesmo com o celular bloqueado.
// Quem usa: MapScreen.
// ============================================================================

import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart';
import '../widgets/bike_marker.dart';
import 'profile_service.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/hazard.dart';
import 'auth_service.dart';
import 'hazard_service.dart';
import '../l10n/i18n.dart';
import 'shared_place_service.dart';

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
      if (c.method == 'connected') {
        // Carro (re)conectado: manda a rota e os pins de novo (a tela do
        // carro pode ter sido recriada e ficava sem o trajeto).
        if (c.arguments == true) {
          _routeSig = '';
          _poisSig = '';
        }
        connected.value = c.arguments == true;
        if (c.arguments == true) _sendVehicle();
      }
    });
    _ch.invokeMethod<bool>('connected').then((v) {
      connected.value = v == true;
      if (v == true) _sendVehicle();
    },
        onError: (_) {});
  }

  /// Aviso curto na tela do carro.
  String _poisSig = '';

  /// Manda a imagem do veículo assim que o carro conecta (sem depender do
  /// mapa aberto no celular).
  Future<void> _sendVehicle() async {
    try {
      vehicleImage(await bikeBadgePng(await ProfileService.load()));
    } catch (_) {}
  }

  /// Imagem do veículo (a mesma do mapa do celular) para a tela do carro.
  void vehicleImage(Uint8List png) {
    if (!connected.value) return;
    _ch.invokeMethod('vehicleImage', png).catchError((_) => null);
  }

  /// Comando da cena 3D (a mesma do celular) para a tela do carro.
  void sim3d(String js) {
    if (!connected.value) return;
    _ch.invokeMethod('sim3d', js).catchError((_) => null);
  }

  /// Pins de radares/postos policiais perto: (lat, lng, tipo).
  void pois(List<(double, double, int)> list) {
    final sig = list.map((e) => '${e.$1},${e.$2}').join(';');
    if (sig == _poisSig) return;
    _poisSig = sig;
    _ch.invokeMethod('pois', [
      for (final (la, lo, k) in list) ...[la, lo, k.toDouble()]
    ]).catchError((_) => null);
  }

  /// Some a navegação da tela do carro (rota, manobra, chegada) na hora.
  void clearNavigation() {
    _routeSig = '';
    _ch.invokeMethod('clearNav').catchError((_) => null);
  }

  void toast(String text) =>
      _ch.invokeMethod('toast', text).catchError((_) => null);

  /// Botão do carro com o UauGo fora do mapa (tela inicial, outra tela):
  /// Radar/Perigo marcam o alerta na posição atual; Encerrar não tem o que
  /// encerrar.
  Future<void> _handleWithoutMap(String a) async {
    // Destino pedido ao Assistente/Gemini no carro: a tela inicial traça a
    // rota e inicia sozinha.
    if (a.startsWith('navigate:')) {
      SharedPlaceService.instance.fromVoice = true;
      SharedPlaceService.instance.pending.value = a.substring(9);
      return;
    }
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
      await HazardService.instance.report(type, p.latitude, p.longitude, uid,
          heading: p.speed > 2 && p.heading >= 0 ? p.heading : null);
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
