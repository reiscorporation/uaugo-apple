// ============================================================================
// location_service.dart — GPS
//
// O que faz: Permissão e leitura contínua da posição (1 por segundo, ou 2 s na
//   economia de bateria). Com o app fora da tela, só no comboio com a opção
//   "Compartilhar posição em segundo plano": GPS econômico (a cada 15 s).
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
  ///
  /// [background]: modo para o app fora da tela (só no comboio, com a opção
  /// ligada): serviço com notificação fixa, mas econômico — precisão alta
  /// (não a máxima), uma leitura a cada 15 s e sem manter o processador
  /// acordado (wake lock). Sem isso, não há serviço: o GPS para quando o app
  /// sai da tela. O serviço também para se o app for fechado pela lista de
  /// recentes (AndroidManifest: stopWithTask).
  ///
  /// [economical] (com [background]): GPS econômico (15 s). False = modo
  /// carro (Android Auto): o celular fica bloqueado, mas a navegação segue
  /// com a precisão normal.
  static Stream<Position> track({
    bool saving = false,
    bool background = false,
    bool economical = true,
    String notificationText = 'Navegação ativa',
  }) {
    final eco = background && economical;
    final accuracy = saving || eco
        ? LocationAccuracy.high
        : LocationAccuracy.bestForNavigation;
    final interval = Duration(seconds: eco ? 15 : (saving ? 2 : 1));
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        intervalDuration: interval,
        foregroundNotificationConfig: background
            ? ForegroundNotificationConfig(
                notificationTitle: 'UauGo ativo',
                notificationText: notificationText,
                enableWakeLock: false,
              )
            : null,
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: eco ? 20 : 0,
        pauseLocationUpdatesAutomatically: !background,
        showBackgroundLocationIndicator: background,
        allowBackgroundLocationUpdates: background,
      );
    } else {
      settings = LocationSettings(accuracy: accuracy, distanceFilter: 0);
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
