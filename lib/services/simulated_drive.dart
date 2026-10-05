// ============================================================================
// simulated_drive.dart — GPS da simulação
//
// O que faz: Percorre a rota em 1x/5x/20x, acelerando e freando conforme o
//   limite de cada trecho, e entrega posições como se fosse o GPS.
// Quem usa: MapScreen (modo simulação).
// Onde mexer: Velocidade-alvo: targetSpeedAt (em MapScreen).
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../logic/simulation.dart';

/// "GPS de mentira" que percorre a rota: o piloto assiste à viagem antes de
/// sair (câmera, narração, radares, paradas), sem enviar nada ao grupo.
class SimulatedDrive {
  SimulatedDrive(this.walker, {required this.speedMs, this.targetSpeedAt})
      : _speed = speedMs;

  final RouteWalker walker;

  /// Velocidade média da rota (m/s): usada onde não há limite conhecido.
  final double speedMs;

  /// Velocidade "realista" em cada ponto (ex.: pelo limite da via), em m/s.
  final double Function(double lat, double lng, double bearing)? targetSpeedAt;

  double _speed;

  /// Quantas vezes mais rápido que a viagem real (1x, 5x, 20x).
  final multiplier = ValueNotifier<int>(5);
  final paused = ValueNotifier<bool>(false);

  /// Quanto já foi percorrido (0 a 1), para a barra de progresso.
  final progress = ValueNotifier<double>(0);

  final _ctrl = StreamController<Position>.broadcast();
  Timer? _timer;
  double _meters = 0;

  Stream<Position> get positions => _ctrl.stream;
  bool get finished => _meters >= walker.length;

  /// Começa: uma posição por segundo (avança conforme a velocidade x multiplicador).
  void start() {
    _emit();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (paused.value || finished) return;
      // Acelera/freia aos poucos até a velocidade do trecho (como de moto).
      final here = walker.at(_meters);
      final target =
          targetSpeedAt?.call(here.lat, here.lng, here.bearing) ?? speedMs;
      // Acelerada, cada passo cobre centenas de metros: ajusta mais rápido
      // (senão chega a uma via de 40 ainda a 80).
      final k = multiplier.value >= 20
          ? 4.0
          : multiplier.value > 1
              ? 2.0
              : 1.0;
      _speed += (target - _speed).clamp(-3.0 * k, 2.0 * k);
      if (_speed < 2) _speed = 2;
      _meters += _speed * multiplier.value;
      _emit();
      if (finished) paused.value = true;
    });
  }

  /// Pula para um ponto da viagem (0 a 1).
  void seek(double fraction) {
    _meters = walker.length * fraction.clamp(0.0, 1.0);
    _emit();
  }

  /// Volta ao início da rota.
  void restart() {
    _meters = 0;
    paused.value = false;
    _emit();
  }

  /// Entrega a posição atual como se viesse do GPS.
  void _emit() {
    final p = walker.at(_meters);
    progress.value = walker.length == 0 ? 1 : _meters / walker.length;
    _ctrl.add(Position(
      latitude: p.lat,
      longitude: p.lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: p.bearing,
      headingAccuracy: 5,
      speed: finished || paused.value ? 0 : _speed,
      speedAccuracy: 1,
      isMocked: true,
    ));
  }

  void dispose() {
    _timer?.cancel();
    _ctrl.close();
    multiplier.dispose();
    paused.dispose();
    progress.dispose();
  }
}
