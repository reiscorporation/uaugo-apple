// ============================================================================
// app_settings.dart — Configurações do app
//
// O que faz: Todas as opções do usuário (tela, rotas, avisos, consumo,
//   bateria, mapa noturno), guardadas no celular (SharedPreferences) e
//   expostas como ValueNotifier (a tela se atualiza sozinha).
// Quem usa: Configurações, MapScreen, DirectionsService, prévia da rota.
// Onde mexer: Padrões: construtores de RoutePrefs, AlertPrefs, FuelPrefs.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/map_style.dart';

export '../logic/map_style.dart' show MapTheme;

/// Como escolher a "melhor rota". Quem calcula é o Google (Directions);
/// o app escolhe entre as opções que ele devolve.
enum RoutePreference {
  fastest('Mais rápida', 'A rota que o Google indica (menor tempo)'),
  shortest('Mais curta', 'Entre as alternativas do Google, a de menos km');

  const RoutePreference(this.label, this.description);
  final String label;
  final String description;
}

/// Preferências de rota (enviadas ao Google ao calcular).
class RoutePrefs {
  final RoutePreference preference;
  final bool avoidTolls;
  final bool avoidHighways;
  final bool avoidFerries;

  /// Tempo considerando o trânsito do momento (consulta mais cara).
  final bool liveTraffic;

  /// Evitar locais de risco (áreas com relatos de assalto da comunidade).
  final bool avoidRisk;

  const RoutePrefs({
    this.preference = RoutePreference.fastest,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.avoidFerries = false,
    this.liveTraffic = false,
    this.avoidRisk = false,
  });

  /// Cópia com algumas opções trocadas.
  RoutePrefs copyWith({
    RoutePreference? preference,
    bool? avoidTolls,
    bool? avoidHighways,
    bool? avoidFerries,
    bool? liveTraffic,
    bool? avoidRisk,
  }) =>
      RoutePrefs(
        preference: preference ?? this.preference,
        avoidTolls: avoidTolls ?? this.avoidTolls,
        avoidHighways: avoidHighways ?? this.avoidHighways,
        avoidFerries: avoidFerries ?? this.avoidFerries,
        liveTraffic: liveTraffic ?? this.liveTraffic,
        avoidRisk: avoidRisk ?? this.avoidRisk,
      );
}

/// Consumo do veículo, para estimar o gasto de combustível das viagens.
class FuelPrefs {
  final bool enabled;
  final double kmPerLiter;
  final double pricePerLiter;

  const FuelPrefs(
      {this.enabled = false, this.kmPerLiter = 0, this.pricePerLiter = 0});

  /// Ligado e com os dois números preenchidos.
  bool get ready => enabled && kmPerLiter > 0 && pricePerLiter > 0;
}

/// Economia de bateria: no modo econômico o GPS lê a cada 2 s com precisão
/// alta (em vez da máxima), o mapa fica sem prédios 3D e sem trânsito, e a
/// câmera se move menos vezes. Os avisos continuam funcionando.
enum BatteryMode {
  auto('Automático (bateria abaixo de 25% ou modo economia do celular)'),
  off('Desligada (máximo desempenho)'),
  on('Sempre ligada');

  const BatteryMode(this.label);
  final String label;
}

/// Como avisar: desligado, só na tela (com vibração) ou também por voz.
enum AlertMode {
  off('Não avisar'),
  visual('Só notificação na tela'),
  voice('Notificação e voz');

  const AlertMode(this.label);
  final String label;
}

/// Distância e quantidade de avisos falados até o ponto, e os avisos extras.
class AlertPrefs {
  final int radarMeters; // radar fixo e radar móvel
  final int radarRepeats;
  final int policeMeters; // polícia reportada e postos policiais
  final int policeRepeats;

  /// Postos policiais rodoviários (PRF / polícia rodoviária estadual).
  final bool policePosts;

  /// Lombadas e faixas elevadas (opcional: os dados só são baixados se ligar).
  final AlertMode bumps;

  /// "No semáforo, vire à direita" (opcional: baixa os semáforos se ligar).
  final bool signals;

  /// "Velocidade reduzida para 60 em 300 metros".
  final bool reducedSpeed;

  /// "Você chegou à metade do trajeto".
  final bool halfway;

  /// Chuva à frente (a pelo menos 2 km).
  final bool rain;

  /// Avisar quem vem atrás quando eu parar no acostamento de rodovia
  /// (publica a posição como alerta "veículo parado"). Opcional.
  final bool shareStopped;

  const AlertPrefs({
    this.radarMeters = 1000,
    this.radarRepeats = 2,
    this.policeMeters = 1000,
    this.policeRepeats = 1,
    this.policePosts = true,
    this.bumps = AlertMode.off,
    this.signals = false,
    this.reducedSpeed = true,
    this.halfway = false,
    this.rain = false,
    this.shareStopped = false,
  });

  /// Cópia com algumas opções trocadas.
  AlertPrefs copyWith({
    int? radarMeters,
    int? radarRepeats,
    int? policeMeters,
    int? policeRepeats,
    bool? policePosts,
    AlertMode? bumps,
    bool? signals,
    bool? reducedSpeed,
    bool? halfway,
    bool? rain,
    bool? shareStopped,
  }) =>
      AlertPrefs(
        radarMeters: radarMeters ?? this.radarMeters,
        radarRepeats: radarRepeats ?? this.radarRepeats,
        policeMeters: policeMeters ?? this.policeMeters,
        policeRepeats: policeRepeats ?? this.policeRepeats,
        policePosts: policePosts ?? this.policePosts,
        bumps: bumps ?? this.bumps,
        signals: signals ?? this.signals,
        reducedSpeed: reducedSpeed ?? this.reducedSpeed,
        halfway: halfway ?? this.halfway,
        rain: rain ?? this.rain,
        shareStopped: shareStopped ?? this.shareStopped,
      );
}

/// Configurações gerais do app (ficam só no celular).
class AppSettings {
  AppSettings._();
  static final instance = AppSettings._();

  /// Manter a tela ligada enquanto o mapa estiver aberto.
  final keepScreenOn = ValueNotifier<bool>(true);

  /// Comboio: continuar enviando a posição ao grupo com o app fora da tela
  /// (GPS econômico, a cada 15 s). Desligado = o GPS para ao sair do app.
  final backgroundShare = ValueNotifier<bool>(false);

  /// Camada de trânsito do Google no mapa (vias em verde/laranja/vermelho).
  final showTraffic = ValueNotifier<bool>(true);

  /// Mapa claro/escuro (automático pelo pôr do sol).
  final mapTheme = ValueNotifier<MapTheme>(MapTheme.auto);

  /// Economia de bateria (ver [batterySaver]).
  final batterySaver = ValueNotifier<BatteryMode>(BatteryMode.auto);

  /// Consumo e gastos (opcional; fica só no celular, não vai para o grupo).
  final fuel = ValueNotifier<FuelPrefs>(const FuelPrefs());

  /// Salva o consumo do veículo (só no celular).
  Future<void> setFuel(FuelPrefs f) async {
    fuel.value = f;
    final p = await SharedPreferences.getInstance();
    await p.setBool('fuelOn', f.enabled);
    await p.setDouble('fuelKmL', f.kmPerLiter);
    await p.setDouble('fuelPrice', f.pricePerLiter);
  }
  final route = ValueNotifier(const RoutePrefs());
  final alerts = ValueNotifier(const AlertPrefs());
  bool _loaded = false;

  /// Lê tudo do celular (chamado uma vez, em main.dart). Valores que nunca
  /// foram salvos ficam com o padrão.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    keepScreenOn.value = p.getBool('keepScreenOn') ?? true;
    backgroundShare.value = p.getBool('backgroundShare') ?? false;
    showTraffic.value = p.getBool('showTraffic') ?? true;
    mapTheme.value = MapTheme.values.firstWhere(
        (m) => m.name == p.getString('mapTheme'),
        orElse: () => MapTheme.auto);
    fuel.value = FuelPrefs(
      enabled: p.getBool('fuelOn') ?? false,
      kmPerLiter: p.getDouble('fuelKmL') ?? 0,
      pricePerLiter: p.getDouble('fuelPrice') ?? 0,
    );
    batterySaver.value = BatteryMode.values.firstWhere(
        (m) => m.name == p.getString('batterySaver'),
        orElse: () => BatteryMode.auto);
    route.value = RoutePrefs(
      preference: RoutePreference.values.firstWhere(
          (r) => r.name == p.getString('routePreference'),
          orElse: () => RoutePreference.fastest),
      avoidTolls: p.getBool('routeAvoidTolls') ?? false,
      avoidHighways: p.getBool('routeAvoidHighways') ?? false,
      avoidFerries: p.getBool('routeAvoidFerries') ?? false,
      liveTraffic: p.getBool('routeLiveTraffic') ?? false,
      avoidRisk: p.getBool('routeAvoidRisk') ?? false,
    );
    alerts.value = AlertPrefs(
      radarMeters: p.getInt('alertRadarMeters') ?? 1000,
      radarRepeats: p.getInt('alertRadarRepeats') ?? 2,
      policeMeters: p.getInt('alertPoliceMeters') ?? 1000,
      policeRepeats: p.getInt('alertPoliceRepeats') ?? 1,
      policePosts: p.getBool('alertPolicePosts') ?? true,
      bumps: AlertMode.values.firstWhere(
          (m) => m.name == p.getString('alertBumps'),
          orElse: () => AlertMode.off),
      signals: p.getBool('alertSignals') ?? false,
      reducedSpeed: p.getBool('alertReducedSpeed') ?? true,
      halfway: p.getBool('alertHalfway') ?? false,
      rain: p.getBool('alertRain') ?? false,
      shareStopped: p.getBool('alertShareStopped') ?? false,
    );
  }

  /// Salva as distâncias e opções dos avisos.
  Future<void> setAlerts(AlertPrefs a) async {
    alerts.value = a;
    final p = await SharedPreferences.getInstance();
    await p.setInt('alertRadarMeters', a.radarMeters);
    await p.setInt('alertRadarRepeats', a.radarRepeats);
    await p.setInt('alertPoliceMeters', a.policeMeters);
    await p.setInt('alertPoliceRepeats', a.policeRepeats);
    await p.setBool('alertPolicePosts', a.policePosts);
    await p.setString('alertBumps', a.bumps.name);
    await p.setBool('alertSignals', a.signals);
    await p.setBool('alertReducedSpeed', a.reducedSpeed);
    await p.setBool('alertHalfway', a.halfway);
    await p.setBool('alertRain', a.rain);
    await p.setBool('alertShareStopped', a.shareStopped);
  }

  /// Salva o tema do mapa (claro, escuro, automático).
  Future<void> setMapTheme(MapTheme v) async {
    mapTheme.value = v;
    (await SharedPreferences.getInstance()).setString('mapTheme', v.name);
  }

  /// Salva o modo de economia de bateria.
  Future<void> setBatterySaver(BatteryMode v) async {
    batterySaver.value = v;
    (await SharedPreferences.getInstance()).setString('batterySaver', v.name);
  }

  /// Liga/desliga a camada de trânsito do Google no mapa.
  Future<void> setShowTraffic(bool v) async {
    showTraffic.value = v;
    (await SharedPreferences.getInstance()).setBool('showTraffic', v);
  }

  /// Liga/desliga o envio da posição ao comboio com o app fora da tela.
  Future<void> setBackgroundShare(bool v) async {
    backgroundShare.value = v;
    (await SharedPreferences.getInstance()).setBool('backgroundShare', v);
  }

  /// Liga/desliga a tela sempre acesa no mapa.
  Future<void> setKeepScreenOn(bool v) async {
    keepScreenOn.value = v;
    (await SharedPreferences.getInstance()).setBool('keepScreenOn', v);
  }

  /// Salva as preferências de rota.
  Future<void> setRoute(RoutePrefs r) async {
    route.value = r;
    final p = await SharedPreferences.getInstance();
    await p.setString('routePreference', r.preference.name);
    await p.setBool('routeAvoidTolls', r.avoidTolls);
    await p.setBool('routeAvoidHighways', r.avoidHighways);
    await p.setBool('routeAvoidFerries', r.avoidFerries);
    await p.setBool('routeLiveTraffic', r.liveTraffic);
    await p.setBool('routeAvoidRisk', r.avoidRisk);
  }
}
