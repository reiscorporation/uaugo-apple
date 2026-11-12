// ============================================================================
// car_settings.dart — Configurações do celular na tela do carro (⚙)
//
// O que faz: monta as mesmas opções de Configurações (as que dá para mudar
//   com um toque) em seções para o Android Auto, e aplica o que o motorista
//   tocar no carro. Ficam só no celular as que pedem digitar ou entrar em
//   conta (conta, contato de emergência, idioma, voz, combustível, baixar
//   mapas, administração).
// Quem usa: CarService (envia ao carro) e MapScreen (ação "cfg:chave:1|0").
// ============================================================================

import '../l10n/i18n.dart';
import '../logic/map_style.dart';
import 'app_settings.dart';
import 'voice_service.dart';

/// Uma opção liga/desliga (ou uma escolha entre várias, marcada).
class CarSetting {
  const CarSetting(this.key, this.title, this.on, [this.sub = '']);
  final String key;
  final String title;
  final bool on;
  final String sub;

  Map<String, Object> toMap() => {'k': key, 't': title, 'v': on, 's': sub};
}

class CarSettings {
  CarSettings._();

  /// Seções na ordem da tela do carro (cada uma cabe na lista do carro).
  static List<(String, List<CarSetting>)> sections() {
    final s = AppSettings.instance;
    final v = VoiceService.instance;
    final a = s.alerts.value;
    final r = s.route.value;
    return [
      (tr('Voz e avisos'), [
        CarSetting('alerts', tr('Avisos falados'), v.alertsOn.value),
        CarSetting('narration', tr('Narração das curvas na navegação'), v.narrationOn.value),
        CarSetting('policePosts', tr('Avisar postos policiais rodoviários'), a.policePosts),
        CarSetting('mobileStretches', tr('Trechos que podem ter radar móvel'), a.mobileStretches),
        CarSetting('bumps', tr('Lombadas e faixas elevadas'), a.bumps != AlertMode.off),
        CarSetting('signals', tr('Semáforos'), a.signals),
      ]),
      (tr('Mais avisos'), [
        CarSetting('reducedSpeed', tr('Velocidade reduzida à frente'), a.reducedSpeed),
        CarSetting('rain', tr('Chuva à frente'), a.rain),
        CarSetting('halfway', tr('Metade do trajeto: na estrada'), a.halfway),
        CarSetting('halfwayCity', tr('Metade do trajeto: na cidade'), a.halfwayCity),
      ]),
      (tr('Rota'), [
        CarSetting('avoidTolls', tr('Evitar pedágios'), r.avoidTolls),
        CarSetting('avoidHighways', tr('Evitar rodovias'), r.avoidHighways),
        CarSetting('avoidFerries', tr('Evitar balsas'), r.avoidFerries),
        CarSetting('liveTraffic', tr('Considerar o trânsito do momento'), r.liveTraffic),
        CarSetting('avoidRisk', tr('Evitar locais de risco'), r.avoidRisk),
      ]),
      (tr('Mapa'), [
        CarSetting('placeNames', tr('Nomes de lugares no mapa do carro'), s.carPlaceNames.value),
        CarSetting('showTraffic', tr('Mostrar trânsito na rota'), s.showTraffic.value),
        CarSetting('lightMode', tr('Modo leve'), s.lightMode),
        CarSetting('keepScreenOn', tr('Manter a tela ligada no mapa'), s.keepScreenOn.value),
        CarSetting('maxBrightness', tr('Brilho de tela máximo ao navegar'), s.maxBrightnessNav.value),
      ]),
      (tr('Mapa noturno'), [
        for (final m in MapTheme.values)
          CarSetting('mapTheme=${m.name}', m.label, s.mapTheme.value == m),
      ]),
      (tr('Economia de bateria'), [
        for (final m in BatteryMode.values)
          CarSetting('battery=${m.name}', m.label, s.batterySaver.value == m),
      ]),
    ];
  }

  /// Lista para o carro: [{t: seção, i: [opções]}].
  static List<Map<String, Object>> toCar() => [
        for (final (title, items) in sections())
          {'t': title, 'i': [for (final i in items) i.toMap()]}
      ];

  /// Aplica a escolha feita no carro.
  static Future<void> apply(String key, bool on) async {
    final s = AppSettings.instance;
    final v = VoiceService.instance;
    final a = s.alerts.value;
    final r = s.route.value;
    if (key.startsWith('mapTheme=')) {
      final m = MapTheme.values.where((m) => m.name == key.substring(9)).firstOrNull;
      if (m != null) await s.setMapTheme(m);
      return;
    }
    if (key.startsWith('battery=')) {
      final m = BatteryMode.values.where((m) => m.name == key.substring(8)).firstOrNull;
      if (m != null) await s.setBatterySaver(m);
      return;
    }
    switch (key) {
      case 'alerts':
        v.setAlerts(on);
      case 'narration':
        v.setNarration(on);
      case 'policePosts':
        await s.setAlerts(a.copyWith(policePosts: on));
      case 'mobileStretches':
        await s.setAlerts(a.copyWith(mobileStretches: on));
      case 'bumps':
        await s.setAlerts(a.copyWith(bumps: on ? AlertMode.voice : AlertMode.off));
      case 'signals':
        await s.setAlerts(a.copyWith(signals: on));
      case 'reducedSpeed':
        await s.setAlerts(a.copyWith(reducedSpeed: on));
      case 'rain':
        await s.setAlerts(a.copyWith(rain: on));
      case 'halfway':
        await s.setAlerts(a.copyWith(halfway: on));
      case 'halfwayCity':
        await s.setAlerts(a.copyWith(halfwayCity: on));
      case 'avoidTolls':
        await s.setRoute(r.copyWith(avoidTolls: on));
      case 'avoidHighways':
        await s.setRoute(r.copyWith(avoidHighways: on));
      case 'avoidFerries':
        await s.setRoute(r.copyWith(avoidFerries: on));
      case 'liveTraffic':
        await s.setRoute(r.copyWith(liveTraffic: on));
      case 'avoidRisk':
        await s.setRoute(r.copyWith(avoidRisk: on));
      case 'placeNames':
        await s.setCarPlaceNames(on);
      case 'showTraffic':
        await s.setShowTraffic(on);
      case 'lightMode':
        await s.setLightMode(on);
      case 'keepScreenOn':
        await s.setKeepScreenOn(on);
      case 'maxBrightness':
        await s.setMaxBrightnessNav(on);
    }
  }
}
