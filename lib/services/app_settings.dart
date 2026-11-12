// ============================================================================
// app_settings.dart — Configurações do app
//
// O que faz: Todas as opções do usuário (tela, rotas, avisos, consumo,
//   bateria, mapa noturno), guardadas no celular (SharedPreferences) e
//   expostas como ValueNotifier (a tela se atualiza sozinha).
// Quem usa: Configurações, MapScreen, DirectionsService, prévia da rota.
// Onde mexer: Padrões: construtores de RoutePrefs, AlertPrefs, FuelPrefs.
// ============================================================================

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/painting.dart' show Color;
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/map_style.dart';
import '../l10n/i18n.dart';

export '../logic/map_style.dart' show MapTheme;

/// Como escolher a "melhor rota". Quem calcula é o Google (Directions);
/// o app escolhe entre as opções que ele devolve.
enum RoutePreference {
  fastest('Mais rápida', 'A rota que o Google indica (menor tempo)'),
  shortest('Mais curta', 'Entre as alternativas do Google, a de menos km');

  const RoutePreference(this._label, this._description);
  final String _label;
  String get label => tr(_label);
  final String _description;
  String get description => tr(_description);
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
    this.liveTraffic = true,
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

  const BatteryMode(this._label);
  final String _label;
  String get label => tr(_label);
}

/// Como avisar: desligado, só na tela (com vibração) ou também por voz.
enum AlertMode {
  off('Não avisar'),
  visual('Só notificação na tela'),
  voice('Notificação e voz');

  const AlertMode(this._label);
  final String _label;
  String get label => tr(_label);
}

/// Cor dos botões no estilo Clean (Configurações → Aparência).
enum AppAccent {
  orange('Laranja', Color(0xFFF26B0F)),
  blue('Azul', Color(0xFF1A73E8)),
  green('Verde', Color(0xFF12946F)),
  purple('Roxo', Color(0xFF7B4DD8)),
  pink('Rosa', Color(0xFFD8437A)),
  gray('Cinza', Color(0xFF5F6B7A));

  const AppAccent(this._label, this.color);
  final String _label;
  String get label => tr(_label);
  final Color color;
}

/// Distância e quantidade de avisos falados até o ponto, e os avisos extras.
class AlertPrefs {
  final int radarMeters; // radar fixo e radar móvel
  final int radarRepeats;
  final int policeMeters; // polícia reportada e postos policiais
  final int policeRepeats;

  /// Postos policiais rodoviários (PRF / polícia rodoviária estadual).
  final bool policePosts;

  /// Trechos onde a polícia/órgão divulgou que pode haver radar móvel
  /// (PRF, Resolução CONTRAN 798/20): aviso ao entrar e linha no mapa.
  final bool mobileStretches;

  /// Lombadas e faixas elevadas (opcional: os dados só são baixados se ligar).
  final AlertMode bumps;

  /// "No semáforo, vire à direita" (opcional: baixa os semáforos se ligar).
  final bool signals;

  /// "Velocidade reduzida para 60 em 300 metros".
  final bool reducedSpeed;

  /// "Você chegou à metade do trajeto": viagem de estrada (40 km ou mais).
  final bool halfway;

  /// "Metade do trajeto" também em viagem na cidade (menos de 40 km).
  /// Desligado por padrão (pedido de 08/11: na cidade pouco ajuda).
  final bool halfwayCity;

  /// Tipos de aviso SEM voz (só faixa na tela e vibração), escolhidos pelo
  /// piloto: nomes de HazardType e os extras de [voiceKinds].
  final Set<String> mutedVoice;

  /// Chuva à frente (a pelo menos 2 km).
  final bool rain;

  /// Avisar quem vem atrás quando eu parar no acostamento de rodovia
  /// (publica a posição como alerta "veículo parado"). Opcional.
  final bool shareStopped;

  const AlertPrefs({
    this.radarMeters = 750,
    this.radarRepeats = 1,
    this.policeMeters = 1000,
    this.policeRepeats = 1,
    this.policePosts = true,
    this.mobileStretches = true,
    this.bumps = AlertMode.off,
    this.signals = true,
    this.reducedSpeed = true,
    this.halfway = false,
    this.halfwayCity = false,
    this.mutedVoice = const {},
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
    bool? mobileStretches,
    AlertMode? bumps,
    bool? signals,
    bool? reducedSpeed,
    bool? halfway,
    bool? halfwayCity,
    Set<String>? mutedVoice,
    bool? rain,
    bool? shareStopped,
  }) =>
      AlertPrefs(
        radarMeters: radarMeters ?? this.radarMeters,
        radarRepeats: radarRepeats ?? this.radarRepeats,
        policeMeters: policeMeters ?? this.policeMeters,
        policeRepeats: policeRepeats ?? this.policeRepeats,
        policePosts: policePosts ?? this.policePosts,
        mobileStretches: mobileStretches ?? this.mobileStretches,
        bumps: bumps ?? this.bumps,
        signals: signals ?? this.signals,
        reducedSpeed: reducedSpeed ?? this.reducedSpeed,
        halfway: halfway ?? this.halfway,
        halfwayCity: halfwayCity ?? this.halfwayCity,
        mutedVoice: mutedVoice ?? this.mutedVoice,
        rain: rain ?? this.rain,
        shareStopped: shareStopped ?? this.shareStopped,
      );
}

/// Avisos com voz que o piloto pode calar um por um (além dos alertas da
/// comunidade, HazardType). Chave -> nome na tela.
const voiceKinds = {
  'fixedRadar': 'Radar fixo',
  'radar': 'Radar móvel',
  'police': 'Polícia',
  'policePost': 'Posto policial',
  'bump': 'Lombada',
  'toll': 'Pedágio',
  'reducedSpeed': 'Velocidade reduzida à frente',
  'rain': 'Chuva à frente',
  'traffic': 'Trânsito e rota mais rápida',
  'halfway': 'Metade do trajeto',
  'pothole': 'Buraco',
  'danger': 'Perigo na pista',
  'oil': 'Óleo / areia',
  'animal': 'Animal na pista',
  'accident': 'Acidente',
  'fog': 'Neblina',
  'kite': 'Pipas / cerol',
  'risk': 'Área de risco',
  'stoppedVehicle': 'Veículo parado',
};

/// Configurações gerais do app (ficam só no celular).
class AppSettings {
  AppSettings._();
  static final instance = AppSettings._();

  /// Manter a tela ligada enquanto o mapa estiver aberto.
  final keepScreenOn = ValueNotifier<bool>(true);

  /// Brilho da tela no máximo enquanto navega (só na tela do UauGo; volta
  /// ao brilho do celular ao parar de navegar ou sair do app).
  final maxBrightnessNav = ValueNotifier<bool>(true);

  /// Comboio: continuar enviando a posição ao grupo com o app fora da tela
  /// (GPS econômico, a cada 15 s). Desligado = o GPS para ao sair do app.
  final backgroundShare = ValueNotifier<bool>(true);

  /// Estatísticas anônimas de uso e relatório de erros (ligado por padrão;
  /// o usuário pode recusar). Ver AnalyticsService.
  final shareStats = ValueNotifier<bool>(true);

  /// Modo leve: mapa sem prédios 3D e sem a camada de trânsito (menos
  /// memória e processador). null = automático (liga em celulares com menos
  /// de 4,5 GB de RAM, ex.: Galaxy A14).
  final lightModeChoice = ValueNotifier<bool?>(null);

  /// Nomes de lugares (museu, escola, comércio) no mapa do carro (12/11).
  final carPlaceNames = ValueNotifier<bool>(true);

  /// RAM do aparelho em MB (0 = não sabe).
  int deviceMemMb = 0;

  /// Modo leve valendo agora (escolha do usuário ou automático).
  bool get lightMode =>
      lightModeChoice.value ?? (deviceMemMb > 0 && deviceMemMb < 4500);

  /// Contato de emergência (só no celular): (nome, telefone com DDD) ou null.
  /// No SOS, "Avisar <nome> pelo WhatsApp" com a localização.
  final emergencyContact = ValueNotifier<(String, String)?>(null);

  /// Camada de trânsito do Google no mapa (vias em verde/laranja/vermelho).
  final showTraffic = ValueNotifier<bool>(true);

  /// Mini player da música (Spotify e outros) no mapa. Desligado por padrão:
  /// precisa do "Acesso a notificações" do Android.
  final mediaControls = ValueNotifier<bool>(false);

  /// Sentido do mapa na navegação: false = gira com a direção do piloto
  /// (padrão, inclinado); true = norte sempre para cima (plano).
  final northUp = ValueNotifier<bool>(false);

  Future<void> setNorthUp(bool v) async {
    northUp.value = v;
    (await SharedPreferences.getInstance()).setBool('northUp', v);
  }

  Future<void> setMediaControls(bool v) async {
    mediaControls.value = v;
    (await SharedPreferences.getInstance()).setBool('mediaControls', v);
  }

  /// Estilo do app: false = Padrão (cores originais, azul-marinho e
  /// laranja); true = Clean (tudo claro).
  final cleanTheme = ValueNotifier<bool>(false);

  /// Idioma: 'auto' (o do celular: português se for pt, senão inglês),
  /// 'pt' ou 'en'. O efetivo fica em I18n.lang.
  final language = ValueNotifier<String>('auto');

  Future<void> setLanguage(String v) async {
    language.value = v;
    _applyLanguage();
    (await SharedPreferences.getInstance()).setString('language', v);
  }

  void _applyLanguage() {
    final v = language.value;
    I18n.lang.value = v == 'auto'
        ? (PlatformDispatcher.instance.locale.languageCode == 'pt' ? 'pt' : 'en')
        : v;
  }

  /// No Clean: cor dos botões e destaques (escolha do usuário). As cores de
  /// segurança (alertas, SOS, radar, pedidos ao grupo) não mudam.
  final accent = ValueNotifier<AppAccent>(AppAccent.orange);

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
    maxBrightnessNav.value = p.getBool('maxBrightnessNav') ?? true;
    language.value = p.getString('language') ?? 'auto';
    _applyLanguage();
    backgroundShare.value = p.getBool('backgroundShare') ?? true;
    shareStats.value = p.getBool('shareStats') ?? true;
    lightModeChoice.value =
        p.containsKey('lightMode') ? p.getBool('lightMode') : null;
    carPlaceNames.value = p.getBool('carPlaceNames') ?? true;
    try {
      deviceMemMb = await const MethodChannel('uaugo/device')
              .invokeMethod<int>('totalMemMb') ??
          0;
    } catch (_) {}
    final en = p.getString('emergencyName'), ep = p.getString('emergencyPhone');
    emergencyContact.value =
        en != null && ep != null && ep.isNotEmpty ? (en, ep) : null;
    showTraffic.value = p.getBool('showTraffic') ?? true;
    mediaControls.value = p.getBool('mediaControls') ?? false;
    northUp.value = p.getBool('northUp') ?? false;
    cleanTheme.value = p.getBool('cleanTheme') ?? false;
    accent.value = AppAccent.values
            .where((a) => a.name == p.getString('appAccent'))
            .firstOrNull ??
        AppAccent.orange;
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
      // Chave nova: passou a vir ligado para todos (antes, desligado).
      liveTraffic: p.getBool('routeLiveTraffic2') ?? true,
      avoidRisk: p.getBool('routeAvoidRisk') ?? false,
    );
    alerts.value = AlertPrefs(
      radarMeters: p.getInt('alertRadarMeters') ?? 750,
      radarRepeats: p.getInt('alertRadarRepeats') ?? 1,
      policeMeters: p.getInt('alertPoliceMeters') ?? 1000,
      policeRepeats: p.getInt('alertPoliceRepeats') ?? 1,
      policePosts: p.getBool('alertPolicePosts') ?? true,
      mobileStretches: p.getBool('alertMobileStretches') ?? true,
      bumps: AlertMode.values.firstWhere(
          (m) => m.name == p.getString('alertBumps'),
          orElse: () => AlertMode.off),
      signals: p.getBool('alertSignals2') ?? true,
      reducedSpeed: p.getBool('alertReducedSpeed') ?? true,
      halfway: p.getBool('alertHalfway') ?? false,
      halfwayCity: p.getBool('alertHalfwayCity') ?? false,
      mutedVoice: (p.getStringList('alertMutedVoice') ?? const []).toSet(),
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
    await p.setBool('alertMobileStretches', a.mobileStretches);
    await p.setString('alertBumps', a.bumps.name);
    await p.setBool('alertSignals2', a.signals);
    await p.setBool('alertReducedSpeed', a.reducedSpeed);
    await p.setBool('alertHalfway', a.halfway);
    await p.setBool('alertHalfwayCity', a.halfwayCity);
    await p.setStringList('alertMutedVoice', a.mutedVoice.toList());
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
  /// Troca o estilo (Padrão / Clean), vale na hora.
  Future<void> setCleanTheme(bool v) async {
    cleanTheme.value = v;
    (await SharedPreferences.getInstance()).setBool('cleanTheme', v);
  }

  /// Troca a cor dos botões do Clean (vale na hora).
  Future<void> setAccent(AppAccent a) async {
    accent.value = a;
    (await SharedPreferences.getInstance()).setString('appAccent', a.name);
  }

  Future<void> setShowTraffic(bool v) async {
    showTraffic.value = v;
    (await SharedPreferences.getInstance()).setBool('showTraffic', v);
  }

  /// Salva (ou apaga, com null) o contato de emergência.
  Future<void> setEmergencyContact((String, String)? c) async {
    emergencyContact.value = c;
    final p = await SharedPreferences.getInstance();
    if (c == null) {
      await p.remove('emergencyName');
      await p.remove('emergencyPhone');
    } else {
      await p.setString('emergencyName', c.$1);
      await p.setString('emergencyPhone', c.$2);
    }
  }

  /// Mostrar ou não os nomes de lugares no mapa do Android Auto.
  Future<void> setCarPlaceNames(bool v) async {
    carPlaceNames.value = v;
    (await SharedPreferences.getInstance()).setBool('carPlaceNames', v);
  }

  /// Liga/desliga o modo leve (escolha do usuário; vale sobre o automático).
  Future<void> setLightMode(bool v) async {
    lightModeChoice.value = v;
    (await SharedPreferences.getInstance()).setBool('lightMode', v);
  }

  /// Liga/desliga as estatísticas de uso e o relatório de erros.
  Future<void> setShareStats(bool v) async {
    shareStats.value = v;
    (await SharedPreferences.getInstance()).setBool('shareStats', v);
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

  /// Liga/desliga o brilho máximo ao navegar.
  Future<void> setMaxBrightnessNav(bool v) async {
    maxBrightnessNav.value = v;
    (await SharedPreferences.getInstance()).setBool('maxBrightnessNav', v);
  }

  /// Salva as preferências de rota.
  Future<void> setRoute(RoutePrefs r) async {
    route.value = r;
    final p = await SharedPreferences.getInstance();
    await p.setString('routePreference', r.preference.name);
    await p.setBool('routeAvoidTolls', r.avoidTolls);
    await p.setBool('routeAvoidHighways', r.avoidHighways);
    await p.setBool('routeAvoidFerries', r.avoidFerries);
    await p.setBool('routeLiveTraffic2', r.liveTraffic);
    await p.setBool('routeAvoidRisk', r.avoidRisk);
  }
}
