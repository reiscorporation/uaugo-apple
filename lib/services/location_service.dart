// ============================================================================
// location_service.dart — GPS
//
// O que faz: Permissão e leitura contínua da posição (1 por segundo, ou 2 s na
//   economia de bateria), continuando com o app minimizado.
// Quem usa: MapScreen, Home.
// Onde mexer: Precisão e intervalo: track().
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// GPS do celular.
class LocationService {
  /// Confere se o GPS está ligado e pede a permissão de localização se
  /// preciso. true = pode usar.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// Leitura a cada 1 s (também parado): velocímetro em tempo real, câmera
  /// do modo Solo suave e avisos de curva/radar na hora certa. O envio da
  /// posição ao grupo é limitado à parte (1/min), então não aumenta o custo.
  ///
  /// Rastreamento que continua com o app minimizado:
  /// - Android: serviço em primeiro plano com notificação fixa.
  /// - iOS: atualizações em segundo plano (exige "Background Modes > Location").
  /// Precisão máxima ("bestForNavigation"): usa GPS + sensores, como os
  /// apps de navegação. Gasta um pouco mais de bateria só com o mapa aberto.
  ///
  /// [saving] (economia de bateria): precisão alta (em vez da máxima) e uma
  /// leitura a cada 2 s. O GPS é o maior consumo depois da tela.
  static Stream<Position> track({bool saving = false}) {
    final accuracy =
        saving ? LocationAccuracy.high : LocationAccuracy.bestForNavigation;
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        intervalDuration: Duration(seconds: saving ? 2 : 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'RodaJunto ativo',
          notificationText: 'Compartilhando sua localização com o grupo',
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = LocationSettings(accuracy: accuracy, distanceFilter: 0);
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
