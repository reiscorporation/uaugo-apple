// ============================================================================
// map_screen.dart — Mapa e navegação — o coração do app
//
// O que faz: Uma tela para 3 modos: expedição (com grupo), navegação sozinho e
//   simulação. A cada leitura do GPS (_onPosition): limite da via,
//   lombadas/postos/pedágios, câmera, gravação, envio ao grupo, radares e
//   narração. Veja docs/ARQUITETURA.md, seção 4.
// Quem usa: Home, Roteiro, Minhas viagens.
// Onde mexer: Cada assunto tem uma seção marcada com "// ----" (radares,
//   navegação, trânsito, histórico, lombadas/chuva, bateria).
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/voice_commands.dart';
import '../logic/find_places.dart';
import '../logic/costs.dart' show formatMoney;
import '../logic/tolls.dart';
import '../services/toll_service.dart';
import '../services/places_service.dart';
import '../services/car_service.dart';
import '../services/analytics_service.dart';
import '../widgets/place_search.dart';
import '../services/saved_places_service.dart';
import '../services/shared_place_service.dart';
import '../logic/geo.dart';
import '../models/bike.dart';
import '../models/expedition.dart';
import '../models/hazard.dart';
import '../services/expedition_service.dart';
import '../services/hazard_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/club_service.dart';
import '../services/profile_service.dart';
import '../services/user_service.dart';
import '../widgets/safe_sheet.dart';
import '../widgets/club_nearby_sheet.dart';
import '../widgets/bike_marker.dart';
import '../widgets/emoji_marker.dart';
import '../widgets/speedometer.dart';
import '../logic/itinerary.dart' show formatDistance, formatDuration, formatTime;
import '../logic/navigation.dart';
import '../logic/radars.dart';
import '../logic/pois.dart';
import '../logic/simulation.dart';
import '../logic/track.dart';
import '../logic/weather.dart';
import '../logic/map_style.dart';
import '../services/battery_service.dart';
import '../services/poi_service.dart';
import '../services/weather_service.dart';
import '../models/trip.dart';
import '../models/trip_record.dart';
import '../services/history_service.dart';
import '../services/simulated_drive.dart';
import '../services/trip_service.dart';
import '../logic/speech.dart';
import '../logic/speed.dart';
import '../services/radar_service.dart';
import '../services/speed_service.dart';
import '../services/voice_command_service.dart';
import '../services/voice_service.dart';
import '../services/app_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'plan_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// Tela de mapa/navegação. Três usos:
/// - expedição em grupo: [code] preenchido;
/// - navegação sozinho (tipo Waze): [code] nulo, com ou sem [trip];
/// - simulação da viagem: [simulate] = true com uma [trip] (nada é enviado).
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.code,
    required this.uid,
    required this.userName,
    this.trip,
    this.simulate = false,
    this.startNavigation = false,
  });

  final String? code;
  final String uid;
  final String userName;
  final Trip? trip;
  final bool simulate;

  /// Expedição aberta pelo "Iniciar" do roteiro: liga a navegação assim
  /// que a rota do grupo chegar.
  final bool startNavigation;

  /// Azul da rota (o mesmo do Google Maps) e a borda escura em volta, para
  /// destacar sobre as vias coloridas da camada de trânsito.
  static const routeBlue = Color(0xFF1A73E8);
  static const routeBorder = Color(0xFF0B3D91);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// Estado da tela do mapa. Os campos e métodos estão agrupados por assunto
/// em seções "// ----" (bateria, radares, navegação, trânsito, histórico...).
class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // ---- Bateria
  StreamSubscription<Position>? _gpsSub;
  bool _saving = false; // economia de bateria ligada agora
  bool _inBackground = false; // tela apagada / app minimizado

  /// GPS com o app fora da tela (minimizado ou tela apagada) só no comboio
  /// e com a opção "Compartilhar posição em segundo plano" ligada (o grupo
  /// continua vendo o piloto). Fora disso — navegando sozinho, "Só dirigir",
  /// simulação ou opção desligada — o GPS para ao sair do app e volta ao
  /// abrir: o app não gasta bateria esquecido. Navegando, a tela fica
  /// sempre ligada (_applyWakelock), então a navegação não depende disso.
  bool get _keepGpsInBackground =>
      _sim == null &&
      ((_isExpedition && AppSettings.instance.backgroundShare.value) || _carMode);

  /// Android Auto conectado e navegando: o celular costuma ficar bloqueado,
  /// mas GPS, voz e avisos continuam (a tela é a do carro).
  bool get _carMode =>
      _sim == null && _navigating && CarService.instance.connected.value;

  /// O GPS atual é o econômico de segundo plano (com notificação fixa)?
  bool _bgGps = false;

  /// Parado há tanto tempo em segundo plano = o piloto esqueceu o app aberto:
  /// o GPS desliga (volta sozinho ao abrir o app).
  static const _idleBackgroundLimit = Duration(minutes: 15);
  DateTime? _idleSince;

  /// (Re)inicia o GPS: na tela (1 s, ou 2 s na economia) ou, com
  /// [background], o econômico de segundo plano (15 s, notificação fixa).
  void _startGps({bool background = false}) {
    _gpsSub?.cancel();
    _idleSince = null;
    _bgGps = background;
    _gpsSub = LocationService.track(
      saving: _saving,
      background: background,
      economical: !_carMode,
      notificationText: 'Compartilhando sua localização com o comboio',
    ).listen(_onPosition, onError: (e) => _snack('GPS: $e'));
  }

  /// Desliga o GPS (e o serviço com a notificação fixa).
  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _bgGps = false;
  }

  /// Em segundo plano: desliga o GPS se o piloto está parado há muito tempo.
  void _checkIdleInBackground(Position p) {
    if (!_inBackground) {
      _idleSince = null;
      return;
    }
    if (p.speed > 1.5) {
      _idleSince = null;
      return;
    }
    _idleSince ??= DateTime.now();
    if (DateTime.now().difference(_idleSince!) > _idleBackgroundLimit) {
      debugPrint('GPS desligado: parado em segundo plano há 15 min');
      _stopGps();
    }
  }

  /// A economia de bateria ligou/desligou: refaz o GPS e o mapa.
  void _onSavingChanged() {
    final s = BatteryService.instance.saving.value;
    if (s == _saving || !mounted) return;
    setState(() => _saving = s);
    if (_sim == null && !_inBackground) _startGps();
    if (s) _snack('🔋 Economia de bateria ligada');
  }

  /// App fora da tela (minimizado ou tela apagada): para tudo que gasta
  /// bateria — GPS (salvo no comboio com a opção ligada, aí econômico),
  /// relógios (chuva, trânsito, bateria, gravação) e escutas do Firestore.
  /// Volta tudo ao abrir o app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasBackground = _inBackground;
    _inBackground = state != AppLifecycleState.resumed;
    // Comandos de voz só com o app na tela (o Android não deixa ouvir o
    // microfone em segundo plano sem um serviço próprio).
    _inBackground ? _voiceCmd.stop() : _voiceCmd.start();
    if (_sim == null) {
      // O serviço de segundo plano tem de começar com o app ainda visível
      // ("inactive"): o Android não deixa iniciá-lo depois de sair.
      if (state == AppLifecycleState.inactive && _keepGpsInBackground && !_bgGps) {
        _startGps(background: true);
      }
      final left = state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden;
      if (left && !_keepGpsInBackground) _stopGps();
      // De volta à tela: GPS normal, sem notificação fixa.
      if (state == AppLifecycleState.resumed && (_gpsSub == null || _bgGps)) {
        _startGps();
      }
    }
    if (_inBackground && !wasBackground) _pauseWork();
    if (!_inBackground && wasBackground) {
      _resumeWork();
      final p = _me;
      if (mounted) setState(() {});
      if (p != null) _updateCamera(p, force: true);
    }
  }

  /// Saiu da tela: para relógios e escutas do Firestore (e guarda a viagem).
  void _pauseWork() {
    _ticker?.cancel();
    _rainTimer?.cancel();
    _trafficTimer?.cancel();
    _autosave?.cancel();
    _saveRecord();
    BatteryService.instance.stop();
    for (final s in _fireSubs) {
      s.cancel();
    }
    _fireSubs.clear();
    _hazardSub?.cancel();
    _hazardSub = null;
    _hazardCell = null;
  }

  /// Voltou à tela: religa relógios e escutas.
  void _resumeWork() {
    _listenExpedition();
    _startTimers();
    BatteryService.instance.start();
    if (_recorder != null) {
      _autosave?.cancel();
      _autosave =
          Timer.periodic(const Duration(minutes: 2), (_) => _saveRecord());
    }
  }

  /// Mapa escuro: pela opção ou, no automático, depois do pôr do sol.
  bool get _darkMap {
    final t = AppSettings.instance.mapTheme.value;
    if (t != MapTheme.auto) return t == MapTheme.night;
    final p = _me;
    return p == null
        ? DateTime.now().hour >= 18 || DateTime.now().hour < 6
        : isNight(DateTime.now(), p.latitude, p.longitude);
  }

  // Envio da posição ao grupo: no máximo 1 vez por minuto (o GPS só avisa
  // quando a moto anda 25 m, então parado não envia nada). Cada envio é
  // cobrado como 1 gravação + 1 leitura por membro no Firestore.
  static const _sendInterval = Duration(minutes: 1);

  final _svc = ExpeditionService.instance;
  final List<StreamSubscription> _subs = [];

  /// Escutas do Firestore da expedição (param com o app fora da tela).
  final List<StreamSubscription> _fireSubs = [];
  GoogleMapController? _map;
  Timer? _ticker;

  Expedition? _exp;
  List<Member> _members = [];
  List<Stop> _stops = [];
  List<SosAlert> _alerts = [];
  final Set<String> _seenAlerts = {};
  bool _alertsLoaded = false;

  List<LatLng> _route = [];
  String _routeSig = '';

  Position? _me;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- Alertas públicos (polícia, buraco, perigo, radar...). A distância
  // do aviso depende do tipo (radar: 1.000 m; demais: 500 m).
  final _hazardSvc = HazardService.instance;
  final _voice = VoiceService.instance;
  final _voiceCmd = VoiceCommandService.instance;
  // Último alerta marcado por voz (para "UauGo, cancelar").
  ({HazardType type, double lat, double lng, DateTime at})? _lastVoiceReport;

  // ---- Paradas do roteiro já anunciadas por voz
  final Set<String> _stopNearAnnounced = {};
  final Set<String> _stopArrived = {};

  // ---- Radares fixos (oficiais) e trechos de radar portátil da PRF
  final _radarSvc = RadarService.instance;
  String? _radarCell;
  List<FixedRadar> _radarsAround = []; // ~33 km em volta, para os avisos
  List<FixedRadar> _radarMarkers = []; // os mais próximos, para o mapa
  List<PrfStretch> _stretchesAround = [];
  final Map<int, int> _radarSpoken = {}; // radar -> avisos já falados
  DateTime _lastRadarAlert = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<int> _stretchAnnounced = {};
  final Map<RadarKind, BitmapDescriptor> _radarIcons = {};
  ({String emoji, String text, bool Function(Position) passed})? _radarBanner;

  // ---- Visualização do mapa
  // Comboio: vista de cima (só a minha moto ou o grupo todo).
  // Solo: primeira pessoa, câmera inclinada atrás da moto, girando com ela.
  _MapView _view = _MapView.convoy;
  bool _showAll = false; // no modo comboio: enquadrar o grupo todo
  bool _follow = true; // a câmera acompanha (desliga ao arrastar o mapa)
  Offset? _touchStart;
  double _bearing = 0;
  Position? _bearingFrom;
  DateTime _lastFit = DateTime.fromMillisecondsSinceEpoch(0);

  // ---- Velocímetro e limite da via
  final _speedSvc = SpeedService.instance;
  final _limitTracker = LimitTracker();
  final _speedAlerter = SpeedAlerter();
  RoadLimit? _roadLimit;
  double _speedMs = 0; // velocidade usada no velocímetro e nos alertas
  Position? _prevPos;
  Position? _limitsCheckedAt;
  Position? _radarMarkersAt;
  Position? _lastSentPos;
  List<(double, double)> _routeRecs = [];

  double? _riderAlong; // quanto já percorreu da rota (m)
  ({double along, double offset, double bearing})? _proj;

  // ---- Narração do trajeto (curva a curva)
  TurnByTurn? _nav;
  String _navSig = '';
  bool _navSynced = false;
  int _offRouteCount = 0;
  bool _offRoute = false;
  StreamSubscription? _hazardSub;
  String? _hazardCell;
  List<Hazard> _hazards = [];
  final Map<HazardType, BitmapDescriptor> _hazardIcons = {};
  final Map<String, int> _announced = {}; // alerta -> avisos já falados
  final Set<String> _voted = {}; // já votados por este usuário
  Hazard? _shownHazard;
  bool _shownManually = false;
  // "Ainda está lá?": alertas por onde o piloto passou perto (< 150 m), os
  // que já foram perguntados e a pergunta na tela agora.
  final Set<String> _passedNear = {};
  final Set<String> _askedHazards = {};
  Hazard? _askHazard;
  Timer? _askTimer;

  // ---- Clube
  String? _clubId;
  NearbyMember? _passingSuggestion;
  Position? _lastClubCheckPos;
  final Set<String> _suggestedMembers = {};

  // ---- Ícones das motos
  BikeProfile _myBike = const BikeProfile();
  final Map<String, BitmapDescriptor> _bikeIcons = {};
  final Set<String> _bikePending = {};

  List<Hazard> get _activeHazards =>
      _hazards.where((h) => h.isActive).toList();

  String get _code => widget.code ?? '';

  /// Expedição em grupo de verdade (envia posição, SOS, membros...).
  bool get _isExpedition => widget.code != null && !widget.simulate;

  // ---- Viagem sem expedição (navegação sozinho) ou simulação
  Trip? _trip;
  SimulatedDrive? _sim;
  RouteWalker? _walker;
  bool _rerouting = false;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  double _zoomOffset = 0; // botões + e − (somam ao zoom de acompanhamento)

  /// Navegação ativa (narração, painel de manobras, recálculo). Na
  /// expedição começa desligada e o piloto toca em "Iniciar navegação".
  bool _navigating = false;
  bool _simStarted = false;

  @override
  void initState() {
    super.initState();
    if (_isExpedition) {
      _listenExpedition();
    } else {
      _trip = widget.trip;
      if (_trip != null) _onStops(_trip!.stops);
      // Navegando sozinho, a câmera começa em primeira pessoa e a navegação
      // já está ativa (o piloto tocou em "Iniciar" na prévia).
      _view = _MapView.solo;
      if (!widget.simulate) {
        _navigating = true;
        if (_trip != null) _voice.setNarration(true);
      }
    }
    final trip = _trip;
    if (widget.simulate && trip != null && trip.plan.polyline.isNotEmpty) {
      final sim = SimulatedDrive(
        RouteWalker([
          for (final p in decodePolyline(trip.plan.polyline))
            (p.latitude, p.longitude)
        ]),
        speedMs: trip.averageSpeed,
        // Velocidade de cada trecho pelo limite da via (como um piloto real).
        // Com a direção da moto: evita pegar o limite da via marginal.
        targetSpeedAt: (lat, lng, bearing) {
          final l = _speedSvc.lookup(lat, lng, bearing, 20);
          if (l == null) return trip.averageSpeed;
          return l.kmh / 3.6 * (l.estimated ? 0.85 : 0.95);
        },
      );
      _sim = sim;
      _subs.add(sim.positions.listen(_onPosition));
      // Começa parada no ponto de saída: o piloto toca em "Iniciar simulação".
      sim.paused.value = true;
      sim.start();
      // Voz acompanha a velocidade da simulação (fala mais rápido e não
      // acumula frases atrasadas).
      _voice.setFastMode(sim.multiplier.value);
      sim.multiplier.addListener(() => _voice.setFastMode(sim.multiplier.value));
    } else {
      // GPS: normal ou econômico (refeito quando a economia liga/desliga).
      _startGps();
      BatteryService.instance.saving.addListener(_onSavingChanged);
    }
    BatteryService.instance.start();
    WidgetsBinding.instance.addObserver(this);
    _startTimers();
    _loadHazardIcons();
    _voice.init();
    // Comandos de voz (opcional, Configurações → Acessibilidade).
    _subs.add(_voiceCmd.commands.listen(_onVoiceCommand));
    // Botões da tela do carro (Android Auto).
    _subs.add(CarService.instance.actions.listen(_onCarAction));
    _voiceCmd.start();
    _radarSvc.index.addListener(_onRadarIndex);
    _radarSvc.init();
    _speedSvc.loadSettings();
    // "Minhas viagens": grava o caminho e as estatísticas no celular.
    _startRecording();
    // Tela: sempre ligada navegando; no resto, pela opção (Configurações → Tela).
    _applyWakelock();
    AppSettings.instance.keepScreenOn.addListener(_applyWakelock);
    if (_isExpedition) {
      SharedPreferences.getInstance().then((prefs) {
        if (prefs.getString('mapView') == _MapView.solo.name && mounted) {
          setState(() => _view = _MapView.solo);
        }
      });
    }
    ProfileService.load().then((b) {
      if (mounted) setState(() => _myBike = b);
    });
    // Tabela de pedágios (valor e regra da moto por praça, para a voz).
    TollService.instance.table().then((t) => _tollTable = t);
    UserService.loadClubId().then((id) {
      if (mounted) setState(() => _clubId = id);
    });
  }

  /// A cada ~10 km rodados, verifica se há um membro do clube por perto
  /// (até 25 km) que aceita avisos de passagem, e sugere avisá-lo.
  Future<void> _checkClubPassing(Position p) async {
    if (_clubId == null || _passingSuggestion != null || _sim != null) return;
    final last = _lastClubCheckPos;
    if (last != null &&
        Geolocator.distanceBetween(
                last.latitude, last.longitude, p.latitude, p.longitude) <
            10000) {
      return;
    }
    _lastClubCheckPos = p;
    try {
      final list = await ClubService.instance.nearby(
        clubId: _clubId!,
        lat: p.latitude,
        lng: p.longitude,
        purpose: ClubPurpose.passing,
      );
      for (final m in list) {
        if (m.distanceKm <= 25 && _suggestedMembers.add(m.uid)) {
          if (mounted) setState(() => _passingSuggestion = m);
          break;
        }
      }
    } catch (_) {
      // Sem sinal: tenta de novo nos próximos 10 km.
      _lastClubCheckPos = null;
    }
  }

  /// Ações do clube (pedir ajuda, avisar passagem).
  void _showClubActions() {
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.sos, color: Colors.red),
            title: const Text('Pedir ajuda ao membro mais próximo'),
            onTap: () {
              Navigator.pop(ctx);
              showClubNearbySheet(context,
                  clubId: _clubId!, purpose: ClubPurpose.help, position: _me);
            },
          ),
          ListTile(
            leading: const Icon(Icons.waving_hand_outlined),
            title: const Text('Avisar membros que estou passando'),
            onTap: () {
              Navigator.pop(ctx);
              showClubNearbySheet(context,
                  clubId: _clubId!,
                  purpose: ClubPurpose.passing,
                  position: _me);
            },
          ),
        ]),
      ),
    );
  }

  /// Gera (uma vez) e guarda o marcador com a foto/ícone da moto.
  BitmapDescriptor? _bikeIcon(String name, BikeProfile bike,
      {bool isMe = false}) {
    final key = '$name|${bike.cacheKey}|$isMe';
    final cached = _bikeIcons[key];
    if (cached != null) return cached;
    if (_bikePending.add(key)) {
      bikeMarker(name: name, bike: bike, isMe: isMe).then((icon) {
        if (mounted) setState(() => _bikeIcons[key] = icon);
      }).catchError((_) {});
    }
    return null;
  }

  /// Abre "Meu veículo" e atualiza o ícone no mapa.
  Future<void> _editBike() async {
    final b = await Navigator.of(context).push<BikeProfile>(
        MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (b == null) return;
    setState(() => _myBike = b);
    _svc.updateBike(_code, widget.uid, b);
  }

  /// Prepara os ícones dos alertas da comunidade (emoji em círculo colorido).
  Future<void> _loadHazardIcons() async {
    for (final t in HazardType.values) {
      try {
        _hazardIcons[t] = await emojiMarker(t.emoji, t.color);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in [..._subs, ..._fireSubs]) {
      s.cancel();
    }
    _voiceCmd.cancelDestination();
    _voiceCmd.stop();
    CarService.instance.clear();
    _gpsSub?.cancel();
    BatteryService.instance.saving.removeListener(_onSavingChanged);
    BatteryService.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _hazardSub?.cancel();
    _askTimer?.cancel();
    _radarSvc.index.removeListener(_onRadarIndex);
    _sim?.dispose();
    if (_sim != null) {
      _voice.stop();
      _voice.setFastMode(1);
    }
    AppSettings.instance.keepScreenOn.removeListener(_applyWakelock);
    WakelockPlus.disable();
    _trafficTimer?.cancel();
    _trafficBannerTimer?.cancel();
    _autosave?.cancel();
    _rainTimer?.cancel();
    _saveRecord(); // guarda a viagem ao sair do mapa
    super.dispose();
  }

  /// Escuta a expedição no Firestore: dados, membros, paradas e SOS.
  void _listenExpedition() {
    if (!_isExpedition || _fireSubs.isNotEmpty) return;
    _fireSubs
      ..add(_svc.watchExpedition(_code).listen((e) {
        if (e != null) {
          _hadExpedition = true;
        } else if (_hadExpedition) {
          _onExpeditionEnded(); // o líder encerrou para todos
          return;
        }
        final oldCaptain = _exp?.captainId;
        setState(() => _exp = e);
        if (e != null && oldCaptain != null && oldCaptain != e.captainId) {
          _onCaptainChanged(e.captainId);
        }
        _updateRoute();
        _maybeUpgradeRoute();
      }))
      ..add(_svc.members(_code).listen((m) => setState(() => _members = m)))
      ..add(_svc.stops(_code).listen((s) {
        _onStops(s);
        _stopsLoaded = true;
        _maybeUpgradeRoute();
      }))
      ..add(_svc.activeAlerts(_code).listen(_onAlerts));
  }

  /// Relógios da tela: textos "há X min", chuva e trânsito (só com o app
  /// na tela; param em _pauseWork).
  void _startTimers() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Chuva à frente (opção): a cada 5 min (a 1ª em 20 s, com o GPS estável).
    _rainTimer?.cancel();
    _rainTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkRain());
    Future.delayed(const Duration(seconds: 20), _checkRain);
    // Navegando sozinho (opção de trânsito): a cada 5 min (a 1ª em 30 s).
    _trafficTimer?.cancel();
    if (!_isExpedition && !widget.simulate && _trip != null) {
      _trafficTimer =
          Timer.periodic(const Duration(minutes: 5), (_) => _checkTraffic());
      Future.delayed(const Duration(seconds: 30), _checkTraffic);
    }
  }

  /// Tela sempre ligada navegando (a navegação não roda com o app fora da
  /// tela) ou na simulação; no resto, conforme a configuração.
  void _applyWakelock() =>
      AppSettings.instance.keepScreenOn.value || _navigating || _sim != null
          ? WakelockPlus.enable()
          : WakelockPlus.disable();

  // ------------------------------------------------------------ eventos

  /// Nova posição do GPS (ou da simulação): tudo que depende da posição
  /// acontece aqui, nesta ordem. Veja docs/ARQUITETURA.md, seção 4.
  void _onPosition(Position p) {
    if (_sim == null) _checkIdleInBackground(p);
    // Minimizado / tela apagada: guarda a posição sem redesenhar a tela
    // (a voz, os avisos e a gravação continuam).
    if (_inBackground) {
      _me = p;
    } else {
      setState(() => _me = p);
    }
    // Posição na rota: calculada uma vez por leitura e usada pela voz,
    // radares, limite da via e avisos à frente.
    _proj = _walker?.project(p.latitude, p.longitude,
        around: (_proj?.offset ?? 1e9) < 200 ? _proj!.along : null);
    _updateSpeed(p);
    _checkPois(p);
    _checkHalfway();
    if (!_inBackground) _updateCamera(p);
    // Grava o caminho (só no celular) na expedição ou navegando.
    if (_isExpedition || _navigating) {
      _recorder?.add(p.latitude, p.longitude, _speedMs, p.timestamp);
    }
    // Envio ao grupo: no máximo 1x/min, e parado só a cada 5 min.
    final now = DateTime.now();
    final elapsed = now.difference(_lastSent);
    final last = _lastSentPos;
    final moved = last == null
        ? double.infinity
        : distanceMeters(
            last.latitude, last.longitude, p.latitude, p.longitude);
    if (_isExpedition &&
        elapsed >= _sendInterval &&
        (moved >= 20 || elapsed >= const Duration(minutes: 5))) {
      _lastSent = now;
      _lastSentPos = p;
      _svc.updateLocation(_code, widget.uid, p);
    }
    _sendToCar(p);
    // Fora da tela: só a posição para o comboio (no modo carro, segue tudo).
    if (_inBackground && !_carMode) return;
    _checkStoppedOnShoulder(p);
    _watchHazardsAround(p);
    _checkHazardProximity(p);
    _updateRadarsAround(p);
    _checkRadars(p);
    _narrate(p);
    _checkStops(p);
    _checkClubPassing(p);
  }

  // ------------------------------------------------------------ alertas públicos

  /// Troca a escuta de alertas quando o piloto muda de célula (~11 km).
  void _watchHazardsAround(Position p) {
    final (la, lo) = HazardService.cellOf(p.latitude, p.longitude);
    final key = HazardService.cellKey(la, lo);
    if (key == _hazardCell) return;
    _hazardCell = key;
    _hazardSub?.cancel();
    _hazardSub = _hazardSvc
        .watchAround(p.latitude, p.longitude)
        .listen((list) => setState(() => _hazards = list));
  }

  /// Alertas da comunidade à frente: avisa (voz/tela) e mostra a faixa com
  /// os botões "ainda está lá / não está mais".
  void _checkHazardProximity(Position p) {
    final shown = _shownHazard;
    if (shown != null && !_shownManually) {
      final d = Geolocator.distanceBetween(
          p.latitude, p.longitude, shown.lat, shown.lng);
      // Já passou do ponto: fecha o aviso.
      final behind = d > 80 && !_isAhead(p, shown);
      if (behind || d > 2200 || !shown.isActive) {
        setState(() => _shownHazard = null);
      }
    }
    _askIfPassed(p);
    // Polícia e radar móvel: distância e quantidade de avisos configuráveis
    // (ex.: 1000 m, 2 vezes -> a 1000 e a 500 m). Demais perigos: 1 aviso.
    final prefs = AppSettings.instance.alerts.value;
    for (final h in _activeHazards) {
      if (h.createdBy == widget.uid) continue;
      final (range, repeats) = switch (h.type) {
        HazardType.police => (prefs.policeMeters.toDouble(), prefs.policeRepeats),
        HazardType.radar => (prefs.radarMeters.toDouble(), prefs.radarRepeats),
        _ => (h.type.alertMeters, 1),
      };
      final thresholds = alertThresholds(range, repeats);
      final done = _announced[h.id] ?? 0;
      if (done >= thresholds.length) continue;
      final d =
          Geolocator.distanceBetween(p.latitude, p.longitude, h.lat, h.lng);
      if (d > range || !_isAhead(p, h)) continue;
      final next = nextAlert(d, done, thresholds);
      if (next == null) continue;
      // Um alerta novo só aparece se não houver outro na tela.
      if (done == 0 && _shownHazard != null) continue;
      _announced[h.id] = next;
      HapticFeedback.heavyImpact();
      if (_voice.alertsOn.value) {
        _voice.alert(hazardSpeech(h.type.spoken, d));
      } else {
        SystemSound.play(SystemSoundType.alert);
      }
      if (done == 0) {
        setState(() {
          _shownHazard = h;
          _shownManually = false;
        });
      }
      break;
    }
  }

  // ------------------------------------------------------------ radares

  /// A base de radares foi (re)carregada: refaz a lista de radares perto.
  void _onRadarIndex() {
    _radarCell = null; // força recalcular com os dados novos
    final p = _me;
    if (p != null) _updateRadarsAround(p);
    if (_radarIcons.isEmpty) _loadRadarIcons();
  }

  /// Prepara os ícones dos radares no mapa.
  Future<void> _loadRadarIcons() async {
    // Vermelho: chama atenção (o azul se confundia com a estrada).
    final radarRed = Colors.red.shade700;
    _radarIcons[RadarKind.fixed] = await emojiMarker('📸', radarRed);
    _radarIcons[RadarKind.section] = await emojiMarker('⏱️', radarRed);
    _radarIcons[RadarKind.redLight] = await emojiMarker('🚦', radarRed);
    if (mounted) setState(() {});
  }

  /// Radares e trechos da PRF perto do piloto (refeito a cada ~1 km).
  void _updateRadarsAround(Position p) {
    final idx = _radarSvc.index.value;
    if (idx == null) return;
    final cell = '${(p.latitude * 10).floor()}_${(p.longitude * 10).floor()}';
    if (cell != _radarCell) {
      _radarCell = cell;
      _radarsAround = idx.radarsAround(p.latitude, p.longitude);
      _stretchesAround = idx.stretchesAround(p.latitude, p.longitude);
      _radarMarkersAt = null;
    }
    // Ícones no mapa: recalcula a cada 200 m (o GPS lê a cada segundo).
    final at = _radarMarkersAt;
    if (at != null &&
        distanceMeters(at.latitude, at.longitude, p.latitude, p.longitude) <
            200) {
      return;
    }
    _radarMarkersAt = p;
    // No mapa, só os 80 mais próximos (até 10 km) para não poluir.
    final withDist = [
      for (final r in _radarsAround)
        (r, distanceMeters(p.latitude, p.longitude, r.lat, r.lng))
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    setState(() => _radarMarkers = [
          for (final (r, d) in withDist.take(80))
            if (d <= 10000) r
        ]);
  }

  /// Radares à frente: na pista e no sentido do piloto, nas distâncias
  /// configuradas, sempre falando a velocidade; e trechos da PRF.
  // ---- Pílula do radar ao lado do velocímetro ("📸 80 em 450 m"), como a
  // da velocidade reduzida: conta a distância até passar pelo radar.
  FixedRadar? _activeRadar;
  int? _activeRadarKmh;
  double? _activeRadarLast; // última distância (sem rota: detectar que passou)
  ({String emoji, int? kmh, int m})? _radarPill;

  /// Atualiza a distância até o radar avisado (e some ao passar por ele).
  void _updateRadarPill(Position p) {
    final r = _activeRadar;
    if (r == null) return;
    final w = _walker, pr = _proj;
    final onRoute = w != null && pr != null && pr.offset < 60 &&
        (_navigating || _sim != null) && !_offRoute;
    final straight = distanceMeters(p.latitude, p.longitude, r.lat, r.lng);
    double? d;
    if (onRoute) {
      d = radarAheadOnRoute(r,
          project: w.project, riderAlong: pr.along, range: 5000, maxOffset: 40);
    } else {
      final last = _activeRadarLast;
      // Sem rota: passou quando, já perto, a distância volta a crescer.
      final passed = last != null && last < 80 && straight > last + 15;
      d = passed || straight > 3000 ? null : straight;
    }
    _activeRadarLast = straight;
    if (d == null) {
      _activeRadar = null;
      if (_radarPill != null) setState(() => _radarPill = null);
      return;
    }
    final m = (d / 10).round() * 10;
    final emoji = switch (r.kind) {
      RadarKind.fixed => '📸',
      RadarKind.section => '⏱️',
      RadarKind.redLight => '🚦',
    };
    final pill = (emoji: emoji, kmh: _activeRadarKmh, m: m);
    if (pill != _radarPill) setState(() => _radarPill = pill);
  }

  void _checkRadars(Position p) {
    final banner = _radarBanner;
    if (banner != null && banner.passed(p)) {
      setState(() => _radarBanner = null);
    }
    _updateRadarPill(p);

    // No máximo um aviso de radar a cada 6 s (evita "radar a 900 metros"
    // repetido quando há vários radares perto).
    final now = DateTime.now();
    final radarQuiet =
        now.difference(_lastRadarAlert) < const Duration(seconds: 6);

    // Navegando com rota: só radares sobre a rota (a pista do piloto) e à
    // frente, com a distância medida pela rota. Sem rota: regras de direção.
    final w = _walker;
    final useRoute =
        w != null && (_navigating || _sim != null) && !_offRoute;
    final rider = useRoute ? _proj : null;
    final onRoute = rider != null && rider.offset < 60;

    // Distância do 1º aviso e quantas vezes avisar (Configurações). Radar de
    // avanço de sinal fica em cruzamento: uma vez só, a no máximo 300 m.
    final prefs = AppSettings.instance.alerts.value;
    for (final r in _radarsAround) {
      final redLight = r.kind == RadarKind.redLight;
      final range = redLight
          ? min(300.0, prefs.radarMeters.toDouble())
          : prefs.radarMeters.toDouble();
      final thresholds =
          alertThresholds(range, redLight ? 1 : prefs.radarRepeats);
      final done = _radarSpoken[r.id] ?? 0;
      if (done >= thresholds.length) continue;
      final straight = distanceMeters(p.latitude, p.longitude, r.lat, r.lng);
      if (straight > range + 30) continue;
      double? d;
      if (onRoute && w != null) {
        d = radarAheadOnRoute(r,
            project: w.project, riderAlong: rider.along, range: range);
      } else if (shouldAlertRadar(r,
          lat: p.latitude,
          lng: p.longitude,
          heading: _bearing,
          speed: _speedMs,
          neighbors: _radarsAround,
          range: range)) {
        d = straight;
      }
      if (d == null) continue;
      final next = nextAlert(d, done, thresholds);
      if (next == null) continue;
      // Um radar NOVO espera 6 s depois do último aviso; as repetições do
      // mesmo radar (ex.: a 500 m) não esperam.
      final first = done == 0;
      if (first && radarQuiet) continue;
      // A base junta várias fontes: o mesmo radar pode aparecer 2–3 vezes a
      // poucos metros. Conta para todos, para falar uma vez só.
      for (final o in _radarsAround) {
        if (distanceMeters(r.lat, r.lng, o.lat, o.lng) < 150) {
          _radarSpoken[o.id] = next;
        }
      }
      _lastRadarAlert = now;
      // Sem limite na base: usa o limite da via no local do radar.
      final roadKmh = r.limit > 0
          ? null
          : _speedSvc.lookup(r.lat, r.lng, _bearing, _speedMs)?.kmh;
      final kmh = r.limit > 0 ? r.limit : roadKmh;
      // Pílula ao lado do velocímetro com a distância até este radar.
      if (first || _activeRadar == null) {
        _activeRadar = r;
        _activeRadarKmh = kmh != null && kmh > 0 ? kmh : null;
        _activeRadarLast = null;
        _updateRadarPill(p);
      }
      if (!first) {
        // Repetição: só a voz (a faixa na tela continua aberta).
        if (_voice.alertsOn.value) {
          _voice.alert(radarSpeech(r, d, roadLimit: roadKmh));
        }
        return;
      }
      _announceRadar(
        emoji: switch (r.kind) {
          RadarKind.fixed => '📸',
          RadarKind.section => '⏱️',
          RadarKind.redLight => '🚦',
        },
        text: [
          switch (r.kind) {
            RadarKind.fixed => 'Radar fixo',
            RadarKind.section => 'Radar de velocidade média',
            RadarKind.redLight => 'Radar de avanço de sinal',
          },
          kmh != null && kmh > 0 ? 'limite $kmh km/h' : 'limite não informado',
        ].join(' · '),
        speech: radarSpeech(r, d, roadLimit: roadKmh),
        passed: (q) =>
            distanceMeters(q.latitude, q.longitude, r.lat, r.lng) >
            range + 200,
      );
      return; // um aviso por vez
    }

    for (final s in _stretchesAround) {
      if (_stretchAnnounced.contains(s.id)) continue;
      final n = nearestOnLine(p.latitude, p.longitude, s.points);
      if (n.meters > 1000) continue;
      final inside = n.meters < 100;
      if (!inside &&
          !isAhead(
              lat: p.latitude,
              lng: p.longitude,
              heading: p.heading,
              speed: p.speed,
              targetLat: n.lat,
              targetLng: n.lng)) {
        continue;
      }
      _stretchAnnounced.add(s.id);
      _announceRadar(
        emoji: '🚔',
        text: 'Trecho com radar portátil da PRF · BR-${s.br} '
            'km ${s.kmFrom.round()}–${s.kmTo.round()}',
        speech: prfStretchSpeech(s, n.meters),
        // Some ao sair do trecho (ou se não chegar a entrar nele).
        passed: (q) =>
            nearestOnLine(q.latitude, q.longitude, s.points).meters > 1200,
      );
      return;
    }
  }

  /// Mostra a faixa de aviso no topo, vibra e fala (ou só bipa).
  void _announceRadar({
    required String emoji,
    required String text,
    required String speech,
    required bool Function(Position) passed,
    bool speak = true, // false = só na tela (com vibração e bipe)
  }) {
    HapticFeedback.heavyImpact();
    if (speak && _voice.alertsOn.value) {
      _voice.alert(speech);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
    setState(
        () => _radarBanner = (emoji: emoji, text: text, passed: passed));
  }

  // ------------------------------------------------------------ lombadas,
  // postos policiais, metade do trajeto e chuva

  final Map<int, int> _poiSpoken = {}; // ponto -> avisos já feitos
  bool _halfwaySaid = false;
  TollTable? _tollTable;
  Timer? _rainTimer;
  DateTime _lastRainAlert = DateTime.fromMillisecondsSinceEpoch(0);

  /// O ponto está à frente, no caminho da moto? (na rota, se houver; senão
  /// no cone de ±35° da direção e até [side] m para o lado)
  bool _onMyWay(Position p, double lat, double lng, {double side = 20}) {
    final d = distanceMeters(p.latitude, p.longitude, lat, lng);
    final a =
        signedAngle(_bearing, bearingBetween(p.latitude, p.longitude, lat, lng));
    if (a.abs() > 35) return false;
    final w = _walker, pr = _proj;
    if (w != null && pr != null && pr.offset < 40 && !_offRoute) {
      return w.offsetNear(lat, lng, pr.along + d) <= side;
    }
    return (d * sin(a * pi / 180)).abs() <= side;
  }

  /// Lombadas, postos policiais e pedágios à frente, no caminho do piloto.
  void _checkPois(Position p) {
    if (_speedMs < 3 || _sim != null && !_simStarted) return;
    final prefs = AppSettings.instance.alerts.value;
    final bumpRange = max(150.0, _speedMs * 9);
    const tollRange = 1000.0;
    final range =
        max(max(prefs.policeMeters.toDouble(), bumpRange), tollRange);
    for (final poi in PoiService.instance.near(p.latitude, p.longitude, range)) {
      final bump = poi.kind == PoiKind.bump;
      final toll = poi.kind.isToll;
      if (bump && prefs.bumps == AlertMode.off) continue;
      if (poi.kind == PoiKind.policePost && !prefs.policePosts) continue;
      final thresholds = bump
          ? [bumpRange]
          : toll
              ? const [tollRange]
              : alertThresholds(
                  prefs.policeMeters.toDouble(), prefs.policeRepeats);
      final done = _poiSpoken[poi.id] ?? 0;
      if (done >= thresholds.length) continue;
      final d = distanceMeters(p.latitude, p.longitude, poi.lat, poi.lng);
      if (d > thresholds.first) continue;
      if (!_onMyWay(p, poi.lat, poi.lng, side: bump ? 15 : 60)) continue;
      final next = nextAlert(d, done, thresholds);
      if (next == null) continue;
      _poiSpoken[poi.id] = next;
      // Pedágio: quanto o veículo paga, pela tabela (ANTT por praça); moto
      // sem informação = "não informado" (nunca afirma que paga).
      final tollNote = !toll
          ? ''
          : tollPlazaNote(
              _tollTable == null
                  ? null
                  : nearestPlaza(_tollTable!, poi.lat, poi.lng),
              _myBike,
              formatMoney,
              osmMotoFree: poi.kind == PoiKind.tollMotoFree);
      final speech = bump
          ? 'Lombada a ${spokenDistance(d)}'
          : toll
              ? 'Praça de pedágio a ${spokenDistance(d)}'
                  '${tollNote.isEmpty ? '' : '. $tollNote'}'
              : 'Posto policial a ${spokenDistance(d)}';
      if (done > 0) {
        if (_voice.alertsOn.value) _voice.alert(speech);
        return;
      }
      _announceRadar(
        emoji: bump
            ? '🔺'
            : toll
                ? '🛣️'
                : '🚔',
        text: bump
            ? 'Lombada à frente'
            : toll
                ? 'Pedágio à frente${tollNote.isEmpty ? '' : ' · $tollNote'}'
                : 'Posto policial à frente',
        speech: speech,
        speak: !bump || prefs.bumps == AlertMode.voice,
        passed: (q) =>
            distanceMeters(q.latitude, q.longitude, poi.lat, poi.lng) > 150 &&
            !_onMyWay(q, poi.lat, poi.lng, side: 200),
      );
      return; // um aviso por vez
    }
  }

  /// "Você chegou à metade do trajeto" (opção em Configurações).
  void _checkHalfway() {
    if (_halfwaySaid || !AppSettings.instance.alerts.value.halfway) return;
    if (!(_navigating || _simStarted)) return;
    final w = _walker, pr = _proj;
    if (w == null || pr == null || pr.offset > 250 || w.length < 2000) return;
    if (pr.along < w.length / 2) return;
    _halfwaySaid = true;
    final left = formatDistance((w.length - pr.along).round());
    _voice.alert('Você chegou à metade do trajeto. Faltam $left');
    _showTrafficBanner('🏁 Metade do trajeto! Faltam $left');
  }

  /// Chuva à frente, a cada 10 km pela rota (até 50 km), conferida a cada
  /// 5 min.
  Future<void> _checkRain() async {
    final p = _me;
    // Só com a opção ligada e com rota traçada.
    if (!mounted || p == null || !AppSettings.instance.alerts.value.rain ||
        _walker == null || _inBackground) {
      return;
    }
    if (_speedMs < 3 && _sim == null) return; // parado: nada "à frente"
    final w = _walker, pr = _proj;
    final onRoute = w != null && pr != null && pr.offset < 250;
    const dists = [0, 10000, 20000, 30000, 40000, 50000];
    final pts = <(double, double)>[];
    for (final d in dists) {
      if (onRoute) {
        if (pr.along + d > w.length) break;
        final q = w.at(pr.along + d);
        pts.add((q.lat, q.lng));
      } else {
        final q = _ahead(p.latitude, p.longitude, _bearing, d.toDouble());
        pts.add((q.latitude, q.longitude));
      }
    }
    final levels = await WeatherService.rainAt(pts);
    if (!mounted || levels == null || levels.isEmpty) return;
    // Já está chovendo onde o piloto está: não avisa "à frente".
    if (levels.first != RainLevel.none) return;
    for (var i = 1; i < levels.length; i++) {
      if (levels[i] == RainLevel.none) continue;
      if (DateTime.now().difference(_lastRainAlert) <
          const Duration(minutes: 20)) {
        return;
      }
      _lastRainAlert = DateTime.now();
      _voice.alert(rainSpeech(levels[i], dists[i].toDouble()));
      _showTrafficBanner(
          '🌧️ ${rainWord(levels[i])} a ~${dists[i] ~/ 1000} km à frente');
      return;
    }
  }

  /// Folha de voz: avisos falados, narração, testar voz, mais configurações.
  void _showVoiceSettings() {
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('Voz', style: Theme.of(ctx).textTheme.titleLarge),
            subtitle: const Text(
                'Sai pelo alto-falante ou pelo intercomunicador Bluetooth. '
                'A música abaixa enquanto o app fala.'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _voice.alertsOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.campaign),
              title: const Text('Avisos falados'),
              subtitle: const Text(
                  'Radares (a 1 km), perigos na pista, SOS do grupo e paradas do roteiro'),
              value: on,
              onChanged: _voice.setAlerts,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _voice.narrationOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.turn_right),
              title: const Text('Narração do trajeto'),
              subtitle: Text(_nav == null
                  ? 'Sem rota com instruções. '
                      '${_isLeader ? 'Abra o Roteiro e recalcule a rota.' : 'Peça ao líder para montar o roteiro.'}'
                  : 'Curva a curva, como no GPS: "Em 300 metros, vire à direita"'),
              value: on,
              onChanged: (v) {
                _voice.setNarration(v);
                _navSynced = false;
                if (v && _nav == null) {
                  _snack('O roteiro ainda não tem as instruções de navegação');
                }
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Testar voz'),
            onTap: () => _voice.test(hazardSpeech('radar móvel', 1000)),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Mais configurações'),
            subtitle: const Text('Tela sempre ligada, preferências de rota'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SettingsScreen()));
            },
          ),
          ValueListenableBuilder<RadarIndex?>(
            valueListenable: _radarSvc.index,
            builder: (_, idx, __) => ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(idx == null
                  ? 'Base de radares ainda não baixada'
                  : '${idx.radarCount} radares fixos · '
                      '${idx.stretchCount} trechos da PRF'
                      '${idx.prfLabel.isEmpty ? '' : ' (${idx.prfLabel.toLowerCase()})'}'),
              subtitle: Text(idx?.attribution ?? ''),
            ),
          ),
        ]),
      ),
    );
  }

  // Posição de cada parada no traçado (metros desde o início), recalculada
  // quando a rota ou as paradas mudam.
  Map<String, double> _stopAlongs = const {};
  Object? _stopAlongsKey;

  /// Posição da parada [i] no traçado, ou null se ela não está na rota.
  double? _stopAlong(int i) {
    final w = _walker;
    if (w == null) return null;
    final key = (w, _stops.map((s) => s.id).join(','));
    if (key != _stopAlongsKey) {
      _stopAlongsKey = key;
      final m = <String, double>{};
      for (var j = 1; j < _stops.length; j++) {
        final s = _stops[j];
        if (j == _stops.length - 1) {
          m[s.id] = w.length; // destino = fim do traçado
        } else {
          final pr = w.project(s.lat, s.lng);
          if (pr.offset < 300) m[s.id] = pr.along;
        }
      }
      _stopAlongs = m;
    }
    return _stopAlongs[_stops[i].id];
  }

  /// Avisa por voz a 2 km da próxima parada do roteiro e ao chegar. As
  /// distâncias são medidas PELA ROTA quando possível (logic/navigation.dart:
  /// distanceToStop / hasArrived); antes eram em linha reta e, em curvas,
  /// avisava "você chegou" faltando 1 km.
  void _checkStops(Position p) {
    int? nearest;
    double nearestD = double.infinity;
    final pr = _proj;
    for (var i = 1; i < _stops.length; i++) {
      final s = _stops[i];
      if (_stopArrived.contains(s.id)) continue;
      final straight =
          Geolocator.distanceBetween(p.latitude, p.longitude, s.lat, s.lng);
      final stopAlong = _stopAlong(i);
      final dist = distanceToStop(
          straight: straight,
          riderAlong: pr?.along,
          riderOffset: pr?.offset,
          stopAlong: stopAlong);
      final d = dist.meters < 0 ? straight : dist.meters;
      if (hasArrived(
          straight: straight,
          riderAlong: pr?.along,
          riderOffset: pr?.offset,
          stopAlong: stopAlong)) {
        // Ao chegar numa parada, ela e as anteriores contam como visitadas.
        for (final prev in _stops.take(i + 1)) {
          _stopArrived.add(prev.id);
          _stopNearAnnounced.add(prev.id);
        }
        if (i == _stops.length - 1) {
          _onArrivedDestination(s); // destino final: encerra a navegação
        } else {
          _voice.alert(arrivalSpeech(s.name, isDestination: false));
        }
        return;
      }
      if (d < nearestD) {
        nearestD = d;
        nearest = i;
      }
    }
    if (nearest != null && nearestD <= 2000) {
      final s = _stops[nearest];
      if (_stopNearAnnounced.add(s.id)) {
        _voice.alert(nextStopSpeech(s.name, nearestD));
      }
    }
  }

  /// Só avisa do que está à frente (±60° da direção da moto).
  bool _isAhead(Position p, Hazard h) => isAhead(
        lat: p.latitude,
        lng: p.longitude,
        heading: p.heading,
        speed: p.speed,
        targetLat: h.lat,
        targetLng: h.lng,
      );

  /// Folha "O que tem na pista?" para reportar um alerta. Reportar exige
  /// conta (evita alertas falsos anônimos); ver os alertas, não.
  Future<void> _showReportSheet() async {
    if (!await requireAccount(
        context,
        'Para reportar alertas para todos, entre com sua conta. Isso evita '
        'alertas falsos e protege a comunidade.')) {
      return;
    }
    if (!mounted) return;
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('O que tem na pista?',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in HazardType.values)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      _reportHazard(t);
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: t.color.withAlpha(60),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.color, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(t.emoji, style: const TextStyle(fontSize: 36)),
                          const SizedBox(height: 4),
                          Text(t.label,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'O alerta é marcado na sua posição atual e aparece para todos os usuários do app.',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ]),
        ),
      ),
    );
  }

  /// Botão roxo: marca radar móvel na posição atual com um toque (exige
  /// conta, como todo alerta).
  Future<void> _quickRadar() async {
    if (!await requireAccount(
        context,
        'Para avisar radares para todos, entre com sua conta. Isso evita '
        'alertas falsos e protege a comunidade.')) {
      return;
    }
    if (mounted) _reportHazard(HazardType.radar);
  }

  /// Reporta um alerta na posição atual (ou confirma, se já existir um igual
  /// a menos de 150 m). Agradece por voz: quem está pilotando não lê a tela.
  Future<void> _reportHazard(HazardType t) async {
    AnalyticsService.event('hazard_report', {'type': t.name});
    HapticFeedback.mediumImpact();
    try {
      final p = _me ?? await Geolocator.getCurrentPosition();
      // Se já existe o mesmo alerta a menos de 150 m, só confirma.
      for (final h in _activeHazards) {
        if (h.type != t) continue;
        final d =
            Geolocator.distanceBetween(p.latitude, p.longitude, h.lat, h.lng);
        if (d < 150) {
          if (h.createdBy != widget.uid && _voted.add(h.id)) {
            _hazardSvc.confirm(h);
          }
          _snack('${t.emoji} Esse alerta já existia aqui. Confirmado!');
          _voice.alert('Alerta de ${t.spoken} confirmado. Obrigado!');
          return;
        }
      }
      // Confirma só quando o servidor gravar; sem internet, fica na fila.
      var sent = false;
      // Fala na hora (mesmo sem internet o alerta fica na fila).
      _voice.alert('Alerta de ${t.spoken} enviado. Obrigado por avisar a comunidade!');
      _hazardSvc.report(t, p.latitude, p.longitude, widget.uid).then((_) {
        sent = true;
        _snack('${t.emoji} ${t.label} enviado para todos. Obrigado!');
      }, onError: (e) => _snack('Não foi possível enviar o alerta: $e'));
      Future.delayed(const Duration(seconds: 6), () {
        if (!sent && mounted) {
          _snack('${t.emoji} ${t.label} salvo. Será enviado quando houver '
              'internet.');
        }
      });
    } catch (e) {
      _snack('Não foi possível obter sua posição: $e');
    }
  }

  /// Voto "ainda está lá" / "não está mais" num alerta.
  void _voteHazard(Hazard h, bool stillThere) {
    _voted.add(h.id);
    if (stillThere) {
      _hazardSvc.confirm(h);
    } else {
      _hazardSvc.dismiss(h);
    }
    _askTimer?.cancel();
    setState(() {
      _shownHazard = null;
      if (_askHazard?.id == h.id) _askHazard = null;
    });
    _snack('Obrigado por ajudar a comunidade!');
  }

  /// Comando de voz reconhecido (mãos livres, para quem está de luva):
  /// "UauGo, radar" marca o alerta, "UauGo, cancelar" desfaz o último
  /// marcado por voz e "sim"/"não" respondem à pergunta "ainda está lá?".
  Future<void> _onVoiceCommand(VoiceCommand cmd) async {
    if (!mounted) return;
    AnalyticsService.event('voice_command', {'kind': cmd.runtimeType.toString()});
    switch (cmd) {
      case ReportCommand(:final type):
        if (_sim != null) {
          _voice.reply('Na simulação os alertas não são enviados.');
        } else if (AuthService.isAnonymous) {
          _voice.reply('Para marcar alertas, entre com sua conta no app.');
        } else {
          final p = _me;
          if (p != null) {
            _lastVoiceReport = (
              type: type,
              lat: p.latitude,
              lng: p.longitude,
              at: DateTime.now(),
            );
          }
          // _reportHazard confirma por voz ("Alerta de radar móvel enviado").
          await _reportHazard(type);
        }
      case CancelCommand():
        final last = _lastVoiceReport;
        Hazard? mine;
        if (last != null &&
            DateTime.now().difference(last.at) < const Duration(minutes: 10)) {
          for (final h in _activeHazards) {
            if (h.createdBy == widget.uid &&
                h.type == last.type &&
                Geolocator.distanceBetween(last.lat, last.lng, h.lat, h.lng) <
                    80) {
              mine = h;
              break;
            }
          }
        }
        if (mine == null) {
          _voice.reply('Não encontrei um alerta seu para cancelar.');
        } else {
          _hazardSvc.dismiss(mine, force: true);
          _lastVoiceReport = null;
          _voice.reply('Alerta de ${mine.type.spoken} cancelado.');
        }
      case GoToCommand(:final saved):
        await _voiceGoTo(saved: saved);
      case FindCommand():
        await _voiceFind(cmd);
      case WakeCommand():
        break; // tratado no VoiceCommandService (bipe e espera o comando)
      case AnswerCommand(:final yes):
        // Resposta à pergunta "Trocar a rota?" (destino falado).
        final confirm = _voiceConfirmCtx;
        if (confirm != null && confirm.mounted) {
          Navigator.of(confirm).pop(yes);
          return;
        }
        // Resposta a "Adicionar como parada?" (procurar posto...).
        if (_found.isNotEmpty) {
          yes ? _addFoundStop(_found[_foundIdx]) : _nextFound();
          return;
        }
        final h = _askHazard ??
            (_shownHazard != null &&
                    _shownHazard!.createdBy != widget.uid &&
                    !_voted.contains(_shownHazard!.id)
                ? _shownHazard
                : null);
        if (h == null) return; // nada perguntado agora: ignora
        _voteHazard(h, yes);
        _voice.reply(yes ? 'Confirmado. Obrigado!' : 'Certo, vou avisar que não está mais. Obrigado!');
    }
  }

  /// Distância para considerar que o piloto "passou pelo" alerta.
  static const _passRadiusM = 150.0;

  /// Depois que o piloto passa por um alerta de outra pessoa (chegou a menos
  /// de 150 m e já ficou para trás), pergunta por voz e na tela se ainda está
  /// lá. Assim os alertas se mantêm atualizados. Uma vez por alerta; não
  /// pergunta na simulação, sem conta ou se já votou.
  void _askIfPassed(Position p) {
    if (_sim != null || AuthService.isAnonymous) return;
    for (final h in _activeHazards) {
      if (h.createdBy == widget.uid ||
          _voted.contains(h.id) ||
          _askedHazards.contains(h.id)) {
        continue;
      }
      final d =
          Geolocator.distanceBetween(p.latitude, p.longitude, h.lat, h.lng);
      if (d <= _passRadiusM) {
        _passedNear.add(h.id);
        continue;
      }
      // Passou perto e agora está se afastando, com o alerta para trás.
      if (_passedNear.contains(h.id) && !_isAhead(p, h) && _askHazard == null) {
        _askedHazards.add(h.id);
        _passedNear.remove(h.id);
        HapticFeedback.mediumImpact();
        _voice.alert('Você passou pelo alerta de ${h.type.spoken}. '
            '${_voiceCmd.enabled.value ? 'Ainda está lá? Diga sim ou não.' : 'Ainda está lá? Responda na tela.'}');
        setState(() {
          _askHazard = h;
          if (_shownHazard?.id == h.id) _shownHazard = null;
        });
        // Sem resposta em 25 s, a pergunta some (nada é registrado).
        _askTimer?.cancel();
        _askTimer = Timer(const Duration(seconds: 25), () {
          if (mounted) setState(() => _askHazard = null);
        });
        break;
      }
    }
  }

  /// Pergunta "ainda está lá?" depois de passar pelo alerta: botões grandes
  /// (dá para tocar de luva).
  Widget _askBanner(Hazard h) {
    const white = TextStyle(color: Colors.white);
    Widget big(String label, bool still, Color color) => Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              textStyle:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            onPressed: () => _voteHazard(h, still),
            child: Text(label),
          ),
        );
    return Material(
      color: h.type.color,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(h.type.emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${h.type.label} ainda está lá?',
                  style: white.copyWith(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Não sei',
              onPressed: () {
                _askTimer?.cancel();
                setState(() => _askHazard = null);
              },
            ),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              big('👍 Sim', true, Colors.green.shade700),
              const SizedBox(width: 8),
              big('👎 Não está', false, Colors.red.shade700),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Faixa de um alerta da comunidade com a distância e os botões de voto.
  Widget _hazardBanner(Hazard h) {
    const white = TextStyle(color: Colors.white);
    final mine = h.createdBy == widget.uid;
    final canVote = !mine && !_voted.contains(h.id);
    final dist = _dist(h.lat, h.lng).replaceFirst(' · ', '');
    return Material(
      color: h.type.color,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(h.type.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.type.label,
                      style: white.copyWith(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    [
                      if (dist.isNotEmpty) dist,
                      'visto ${_ago(h.lastSeen)}',
                      '${h.confirmations} 👍',
                    ].join(' · '),
                    style: white,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => setState(() => _shownHazard = null),
            ),
          ]),
          if (canVote)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Row(children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _voteHazard(h, true),
                    child: const Text('👍 Ainda está lá'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _voteHazard(h, false),
                    child: const Text('👎 Não está mais'),
                  ),
                ),
              ]),
            ),
          if (mine)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  _hazardSvc.dismiss(h, force: true);
                  setState(() {
                    _shownHazard = null;
                    _hazards = [for (final x in _hazards) if (x.id != h.id) x];
                  });
                },
                child: const Text('REMOVER MEU ALERTA', style: white),
              ),
            ),
        ]),
      ),
    );
  }

  /// Paradas novas (do roteiro ou da viagem): atualiza a narração e o mapa.
  void _onStops(List<Stop> stops) {
    setState(() => _stops = stops);
    _updateRoute();
    // Com rota própria (saiu do trajeto da expedição), a narração é a dela.
    if (_personalTrip != null) return;
    // Manobras de todos os trechos, na ordem do roteiro.
    final sig = stops.map((s) => '${s.id}:${s.steps.length}').join(',');
    if (sig != _navSig) {
      _navSig = sig;
      _nav = _buildNav([for (final s in stops.skip(1)) ...s.steps]);
      _navSynced = false;
    }
  }

  /// Narração curva a curva para estas manobras.
  TurnByTurn? _buildNav(List<NavStep> steps) => steps.isEmpty
      ? null
      : TurnByTurn(steps,
          // Semáforos do mapa aberto e os marcados pela comunidade.
          signalAt: (la, lo) =>
              PoiService.instance.signalNear(la, lo) ||
              _hazards.any((h) =>
                  h.type == HazardType.signal &&
                  distanceMeters(la, lo, h.lat, h.lng) < 35));

  /// Narração das curvas: confere se saiu da rota (recalcula sozinho na
  /// navegação sozinho) e fala a próxima manobra na hora certa.
  void _narrate(Position p) {
    final nav = _nav;
    // Na simulação a narração sempre fala (é para conhecer o trajeto).
    final sim = _sim;
    final on = sim != null
        ? _simStarted
        : _navigating && _voice.narrationOn.value;
    if (!on || nav == null) return;
    void say(String t) => _voice.narrate(t, force: sim != null);
    if (!_navSynced) {
      nav.syncTo(p.latitude, p.longitude);
      _navSynced = true;
    }
    // Posição medida na rota (para a narração e para saber se saiu dela).
    final w = _walker;
    final proj = _proj;
    _riderAlong = proj != null && proj.offset < 250 ? proj.along : null;
    // Fora da rota: a ~60 m dela (mais, se o GPS estiver impreciso) em 3
    // leituras seguidas (3 s). Uma leitura só não basta: o GPS "pula" em
    // túneis e viadutos.
    if (proj != null && sim == null) {
      final d = proj.offset;
      final limit = max(60.0, min(150.0, p.accuracy * 2.5));
      if (d > limit) {
        _offRouteCount++;
        if (_offRouteCount >= 3 && !_isExpedition && _trip != null) {
          // Navegando sozinho: recalcula como o Waze.
          _reroute(p);
        } else if (_offRouteCount >= 3 && _isExpedition && _stops.length >= 2) {
          // Expedição: capitão recalcula para todos; os outros, só para si.
          _expeditionOffRoute(p);
        } else if (_offRouteCount == 3 && !_offRoute) {
          _offRoute = true;
          say('Você saiu da rota planejada');
        }
        return;
      }
      _offRouteCount = 0;
      _checkBackOnExpeditionRoute(p);
      if (_offRoute && d < 40) {
        _offRoute = false;
        nav.syncTo(p.latitude, p.longitude);
        say('Você voltou para a rota');
      }
    }
    // Na simulação acelerada a moto "pula" muitos metros por leitura: as
    // janelas de aviso crescem nesse tanto (a velocidade continua a real).
    final jump = sim != null ? p.speed * sim.multiplier.value : 0.0;
    String? speech;
    if (w != null && proj != null) {
      // Pela rota: avanço e distâncias medidos na estrada.
      if (!nav.hasRoute) nav.attachRoute((la, lo) => w.project(la, lo).along);
      speech = nav.updateAlong(proj.along, p.speed, jump: jump);
    } else {
      speech = nav.update(p.latitude, p.longitude, p.speed + jump / 8);
    }
    if (speech != null) say(speech);
  }

  /// Saiu da rota navegando sozinho: calcula uma nova até os pontos que
  /// faltam na hora (e de novo, se preciso, a cada 10 s no máximo).
  Future<void> _reroute(Position p) async {
    final trip = _trip;
    if (trip == null || _rerouting) return;
    if (DateTime.now().difference(_lastReroute) < const Duration(seconds: 10)) {
      return;
    }
    setState(() => _rerouting = true);
    _lastReroute = DateTime.now();
    _voice.narrate('Recalculando a rota');
    var next = 1;
    while (next < trip.stops.length - 1 &&
        _stopArrived.contains(trip.stops[next].id)) {
      next++;
    }
    final nt = await TripService.reroute(trip,
        lat: p.latitude, lng: p.longitude, nextStopIndex: next);
    if (!mounted) return;
    setState(() => _rerouting = false);
    if (nt == null) {
      // Sem internet: permite tentar de novo logo.
      _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _applyTrip(nt);
  }

  /// Roteiro antigo (rota que cortava as curvas): o líder recalcula uma vez,
  /// sozinho, ao abrir o mapa; os participantes recebem a rota nova.
  bool _stopsLoaded = false;
  bool _upgradeTried = false;
  /// Roteiro antigo (rota que cortava as curvas): o líder recalcula uma vez.
  void _maybeUpgradeRoute() {
    final exp = _exp;
    if (_upgradeTried || !_stopsLoaded || exp == null || !_isLeader) return;
    if (_stops.length < 2 ||
        exp.plan.routeVersion >= TripPlan.currentRouteVersion) {
      return;
    }
    _upgradeTried = true;
    _svc.recalculateRoute(_code, exp.plan, _stops);
  }

  /// Troca a rota em uso (recálculo ou rota mais rápida).
  void _applyTrip(Trip nt) {
    _trip = nt;
    _etaSpeed = null;
    _stopArrived.clear();
    _stopNearAnnounced.clear();
    _offRouteCount = 0;
    _offRoute = false;
    _routeSig = '';
    _onStops(nt.stops);
  }

  // ------------------------------------------------------------ trânsito

  Timer? _trafficTimer;
  DateTime _lastDelayAlert = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastDelayMin = 0;
  double? _etaSpeed; // velocidade efetiva com o trânsito de agora (m/s)
  String? _trafficBanner;
  Timer? _trafficBannerTimer;

  /// Navegando sozinho com "Considerar o trânsito do momento": consulta o
  /// Google a cada 5 min. Troca para uma rota bem mais rápida (≥ 5 min de
  /// economia, por outro caminho) ou avisa trânsito intenso na rota atual.
  Future<void> _checkTraffic() async {
    final trip = _trip, p = _me, w = _walker;
    if (!mounted || trip == null || p == null || w == null || _rerouting) {
      return;
    }
    if (!AppSettings.instance.route.value.liveTraffic) return;
    var next = 1;
    while (next < trip.stops.length - 1 &&
        _stopArrived.contains(trip.stops[next].id)) {
      next++;
    }
    final nt = await TripService.reroute(trip,
        lat: p.latitude, lng: p.longitude, nextStopIndex: next);
    if (!mounted || nt == null || _rerouting) return;

    final remainingM = w.remainingFrom(p.latitude, p.longitude);
    final remainingNowS = remainingM / (_etaSpeed ?? trip.averageSpeed);
    final pts = decodePolyline(nt.plan.polyline);
    final mid = pts.isEmpty ? null : pts[pts.length ~/ 2];
    final otherWay = mid != null &&
        _routeRecs.length >= 2 &&
        nearestOnLine(mid.latitude, mid.longitude, _routeRecs).meters > 300;
    final saving = remainingNowS - nt.durationS;
    if (otherWay && saving >= 300) {
      final mins = (saving / 60).round();
      _voice.alert('Rota mais rápida encontrada: economia de $mins minutos');
      _showTrafficBanner('🚀 Rota mais rápida: economia de $mins min');
      _applyTrip(nt);
      return;
    }
    // Mesma rota: atualiza a previsão de chegada com o trânsito de agora.
    if (nt.durationS > 0) _etaSpeed = nt.distanceM / nt.durationS;
    final delay = nt.trafficDelayS;
    if (delay >= 300 && delay > 0.15 * (nt.typicalS ?? nt.durationS)) {
      final mins = (delay / 60).round();
      final now = DateTime.now();
      if (now.difference(_lastDelayAlert) > const Duration(minutes: 15) ||
          mins >= _lastDelayMin + 5) {
        _lastDelayAlert = now;
        _lastDelayMin = mins;
        _voice.alert('Trânsito intenso na rota: mais $mins minutos');
        _showTrafficBanner('🚗 Trânsito intenso na rota: +$mins min');
      }
    }
  }

  /// Faixa laranja temporária (20 s): trânsito, chuva, metade do trajeto.
  void _showTrafficBanner(String text) {
    setState(() => _trafficBanner = text);
    _trafficBannerTimer?.cancel();
    _trafficBannerTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _trafficBanner = null);
    });
  }

  /// A rota vem pronta do roteiro (calculada pelo líder ao planejar), então
  /// os pilotos não consultam a API de rotas. Sem rota, liga as paradas.
  void _updateRoute() {
    final expPoly = _exp?.plan.polyline ?? '';
    if (expPoly != _expWalkerSig) {
      _expWalkerSig = expPoly;
      final pts = [for (final q in decodePolyline(expPoly)) (q.latitude, q.longitude)];
      _expWalker = pts.length >= 2 ? RouteWalker(pts) : null;
    }
    final poly = _personalTrip?.plan.polyline ??
        (expPoly.isNotEmpty ? expPoly : _trip?.plan.polyline ?? '');
    final sig = poly.isNotEmpty
        ? poly
        : _stops.map((s) => '${s.lat},${s.lng}').join(';');
    if (sig == _routeSig) return;
    _routeSig = sig;
    setState(() => _route = poly.isNotEmpty
        ? decodePolyline(poly)
        : _stops.map((s) => LatLng(s.lat, s.lng)).toList());
    _routeRecs = [for (final q in _route) (q.latitude, q.longitude)];
    CarService.instance.route(_routeRecs);
    _walker = _routeRecs.length >= 2 ? RouteWalker(_routeRecs) : null;
    // Rota nova: as manobras são reposicionadas nela na próxima leitura.
    _nav?.detachRoute();
    if (widget.startNavigation && !_autoStarted && _isExpedition &&
        _routeRecs.length >= 2 && !_navigating) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_navigating) _startNavigation();
      });
    }
  }

  /// O "Iniciar" do roteiro já ligou a navegação (só uma vez).
  bool _autoStarted = false;

  bool get _isLeader => _exp?.leaderId == widget.uid;

  // ---- Capitão e ferrolhos (expedição)
  bool get _isCaptain => _exp?.captainId == widget.uid;
  bool get _isSweeper => _exp?.sweepers.contains(widget.uid) ?? false;

  /// Capitão, ferrolhos e líder veem quem saiu do trajeto (grade e ⚠️).
  bool get _watchesGroup => _isExpedition && (_isCaptain || _isSweeper || _isLeader);

  /// Visão em grade (apelidos no canto) em vez das bolinhas no mapa.
  bool _groupGrid = false;

  /// Rota da EXPEDIÇÃO (a do grupo), mesmo quando o piloto está numa rota
  /// própria para voltar a ela.
  RouteWalker? _expWalker;
  String _expWalkerSig = '';

  /// Rota própria de quem saiu do trajeto (membro/ferrolho), até voltar.
  Trip? _personalTrip;
  int _backOnExpRoute = 0;

  /// O piloto [m] está fora do trajeto da expedição (mais de 150 m)?
  bool _memberOffRoute(Member m) {
    final w = _expWalker;
    if (w == null || !m.hasLocation || m.isStale) return false;
    return w.project(m.lat!, m.lng!).offset > 150;
  }

  /// Saiu do trajeto da expedição (3 leituras fora). Capitão: a rota de
  /// todos passa a sair dele. Membro/ferrolho: rota própria pelas mesmas
  /// paradas até voltar ao trajeto.
  Future<void> _expeditionOffRoute(Position p) async {
    final exp = _exp;
    if (exp == null || _rerouting) return;
    if (DateTime.now().difference(_lastReroute) < const Duration(seconds: 20)) return;
    _lastReroute = DateTime.now();
    var next = 1;
    while (next < _stops.length - 1 && _stopArrived.contains(_stops[next].id)) {
      next++;
    }
    if (next >= _stops.length) return;
    final remaining = _stops.sublist(next);
    setState(() => _rerouting = true);
    if (_isCaptain) {
      _voice.narrate('Recalculando a rota da expedição');
      final ok = await _svc.rerouteFromCaptain(_code, exp.plan, p.latitude,
          p.longitude, remaining, _stops.sublist(1, next));
      if (!mounted) return;
      setState(() => _rerouting = false);
      if (!ok) _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _voice.narrate('Você saiu da rota da expedição. Recalculando para você voltar.');
    final nt = await TripService.build(
      title: exp.name,
      points: [
        TripPoint('Sua posição', p.latitude, p.longitude, type: StopType.meet),
        for (final s in remaining) TripPoint(s.name, s.lat, s.lng, type: s.type),
      ],
      avoidTolls: exp.plan.avoidTolls,
      avoidHighways: exp.plan.avoidHighways,
    );
    if (!mounted) return;
    setState(() => _rerouting = false);
    if (nt == null) {
      _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _personalTrip = nt;
    _backOnExpRoute = 0;
    _offRouteCount = 0;
    _offRoute = false;
    _routeSig = '';
    _updateRoute();
    _navSig = 'personal';
    _nav = _buildNav([for (final s in nt.stops.skip(1)) ...s.steps]);
    _navSynced = false;
  }

  /// Com rota própria: voltou ao trajeto da expedição (3 leituras a menos de
  /// 40 m)? Então segue a rota do grupo de novo.
  void _checkBackOnExpeditionRoute(Position p) {
    final w = _expWalker;
    if (_personalTrip == null || w == null) return;
    final off = w.project(p.latitude, p.longitude).offset;
    _backOnExpRoute = off < 40 ? _backOnExpRoute + 1 : 0;
    if (_backOnExpRoute < 3) return;
    _personalTrip = null;
    _routeSig = '';
    _navSig = '';
    _onStops(_stops);
    _voice.narrate('Você voltou para a rota da expedição');
  }

  /// Trocou o capitão: avisa todo mundo (e por voz quem virou capitão).
  void _onCaptainChanged(String uid) {
    if (uid == widget.uid) {
      _voice.narrate('Agora você é o capitão da expedição');
      _snack('Agora você é o capitão: o seu desvio recalcula a rota de todos.');
      return;
    }
    final name = _members.where((m) => m.uid == uid).firstOrNull?.name ?? 'Outro piloto';
    _snack('$name agora é o capitão da expedição.');
  }

  /// O capitão passa a capitania para outro membro.
  Future<void> _passCaptain(Member m) async {
    final exp = _exp;
    if (exp == null || !_isCaptain || m.uid == widget.uid) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold))),
          if (m.hasLocation)
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Ver no mapa'),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
          ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Passar a capitania'),
            subtitle: const Text('O desvio dele passa a recalcular a rota de todos'),
            onTap: () => Navigator.pop(ctx, 'captain'),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'map') {
      _focus(m.lat!, m.lng!);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Passar a capitania para ${m.name}?'),
        content: const Text('Você deixa de ser o capitão. O desvio do novo capitão '
            'é que passa a recalcular a rota de todos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Passar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.setRoles(_code, m.uid, [...exp.sweepers]..remove(m.uid));
    } catch (e) {
      _snack('Não foi possível salvar: $e');
    }
  }

  /// Escolhe o capitão e os ferrolhos (o líder); o capitão só passa a
  /// capitania.
  Future<void> _editRoles(Member m) async {
    final exp = _exp;
    if (exp == null) return;
    if (!_isLeader) {
      await _passCaptain(m);
      return;
    }
    final sweeper = exp.sweepers.contains(m.uid);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold))),
          if (m.hasLocation)
            ListTile(
              leading: const Icon(Icons.my_location),
              title: const Text('Ver no mapa'),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
          ListTile(
            leading: const Icon(Icons.flag),
            title: const Text('Tornar capitão'),
            subtitle: const Text('Puxa o comboio: só o desvio dele recalcula a rota de todos'),
            enabled: exp.captainId != m.uid,
            onTap: () => Navigator.pop(ctx, 'captain'),
          ),
          ListTile(
            leading: const Icon(Icons.shield_moon),
            title: Text(sweeper ? 'Deixar de ser ferrolho' : 'Tornar ferrolho'),
            subtitle: Text(sweeper
                ? 'Volta a ser membro'
                : 'Fecha o comboio (até ${Expedition.maxSweepers})'),
            enabled: sweeper || exp.sweepers.length < Expedition.maxSweepers,
            onTap: () => Navigator.pop(ctx, 'sweeper'),
          ),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'map') {
      _focus(m.lat!, m.lng!);
      return;
    }
    var captain = exp.captainId;
    final sweepers = [...exp.sweepers];
    if (choice == 'captain') {
      captain = m.uid;
      sweepers.remove(m.uid);
    } else if (sweeper) {
      sweepers.remove(m.uid);
    } else {
      sweepers.add(m.uid);
      if (captain == m.uid) captain = exp.leaderId;
    }
    try {
      await _svc.setRoles(_code, captain, sweepers);
    } catch (e) {
      _snack('Não foi possível salvar: $e');
    }
  }

  /// Papel do piloto, para mostrar na lista ("Capitão", "Ferrolho").
  String? _roleOf(String uid) {
    final exp = _exp;
    if (exp == null) return null;
    if (exp.captainId == uid) return 'Capitão';
    if (exp.sweepers.contains(uid)) return 'Ferrolho';
    return null;
  }

  /// Grade com os apelidos (capitão/ferrolhos): ⚠️ em quem saiu do trajeto;
  /// tocar mostra o piloto no mapa.
  Widget _groupGridPanel() {
    final others = [
      for (final m in _members)
        if (m.uid != widget.uid) m
    ]..sort((a, b) => a.name.compareTo(b.name));
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh.withAlpha(235),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: 190, maxHeight: MediaQuery.of(context).size.height * 0.45),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(6), children: [
          for (final m in others)
            InkWell(
              onTap: m.hasLocation
                  ? () {
                      setState(() => _follow = false);
                      _focus(m.lat!, m.lng!);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                child: Row(children: [
                  if (_memberOffRoute(m))
                    const Icon(Icons.priority_high, color: Colors.amber, size: 20)
                  else
                    Icon(Icons.circle,
                        size: 10,
                        color: m.isStale ? Colors.grey : Color(m.bike.color)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: m.isStale ? Colors.grey : null)),
                  ),
                  Text(m.hasLocation && !m.isStale ? '${(m.speed * 3.6).round()}' : '—',
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  /// Abre o roteiro da expedição.
  Future<void> _openPlan() async {
    final start = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PlanScreen(code: _code, uid: widget.uid)));
    // "Iniciar" no roteiro: já liga a navegação (a rota nova chega pelo
    // Firestore; espera um instante se ainda não chegou).
    if (start != true || !mounted || _navigating) return;
    for (var i = 0; i < 10 && _routeRecs.length < 2; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
    }
    if (_routeRecs.length >= 2) _startNavigation();
  }

  /// SOS do grupo mudaram: avisa os novos (voz, vibração e janela).
  void _onAlerts(List<SosAlert> alerts) {
    setState(() => _alerts = alerts);
    final fresh = alerts.where((a) => !_seenAlerts.contains(a.id)).toList();
    _seenAlerts.addAll(alerts.map((a) => a.id));
    // Alertas antigos aparecem só na faixa vermelha, sem pop-up.
    if (!_alertsLoaded) {
      _alertsLoaded = true;
      return;
    }
    for (final a in fresh) {
      if (a.uid == widget.uid) continue;
      final me = _me;
      _voice.alert(
        sosSpeech(
            a.name,
            me == null
                ? null
                : Geolocator.distanceBetween(
                    me.latitude, me.longitude, a.lat, a.lng)),
        urgent: true,
      );
      _showAlertDialog(a);
    }
  }

  // ------------------------------------------------------------ ações

  /// Envia um SOS ao grupo (segurar o botão).
  Future<void> _sendSos() async {
    HapticFeedback.heavyImpact();
    try {
      final p = _me ?? await Geolocator.getCurrentPosition();
      final id =
          _svc.sendSos(_code, widget.uid, widget.userName, p.latitude, p.longitude);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 8),
        content: const Text('🚨 SOS enviado ao grupo'),
        action: SnackBarAction(
          label: 'CANCELAR',
          textColor: Colors.white,
          onPressed: () => _svc.resolveAlert(_code, id),
        ),
      ));
    } catch (e) {
      _snack('Não foi possível obter sua posição: $e');
    }
  }

  /// Segurou no mapa: adiciona uma parada ali (expedição).
  Future<void> _addStopAt(LatLng pos) async {
    if (!_isLeader) {
      _snack('Só o líder altera o roteiro');
      return;
    }
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova parada'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'Ex: Posto, almoço, mirante, pernoite'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Adicionar')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final ok = await _svc.addToItinerary(
      code: _code,
      uid: widget.uid,
      plan: _exp?.plan ?? const TripPlan(),
      current: _stops,
      name: name.trim(),
      lat: pos.latitude,
      lng: pos.longitude,
    );
    if (!ok) _snack('Parada salva, mas a rota não pôde ser recalculada');
  }

  /// Opções de uma parada (navegar até ela, ver no mapa).
  void _stopOptions(Stop s) {
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(s.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_dist(s.lat, s.lng).replaceFirst(' · ', '')),
          ),
          ListTile(
            leading: const Icon(Icons.navigation),
            title: const Text('Navegar até aqui (Google Maps)'),
            onTap: () {
              Navigator.pop(ctx);
              _navigate(s.lat, s.lng);
            },
          ),
          ListTile(
            leading: const Icon(Icons.route),
            title: Text(_isLeader ? 'Editar no roteiro' : 'Ver roteiro'),
            onTap: () {
              Navigator.pop(ctx);
              _openPlan();
            },
          ),
        ]),
      ),
    );
  }

  /// Abre o app do Google Maps navegando até o ponto.
  Future<void> _navigate(double lat, double lng) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Move a câmera até um ponto e para de acompanhar a moto.
  void _focus(double lat, double lng) {
    _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15));
  }

  /// Botão de câmera: volta a acompanhar; no modo comboio, já acompanhando,
  /// alterna entre "só a minha moto" e "o grupo todo".
  void _centerOnMe() {
    if (!_follow) {
      setState(() => _follow = true);
    } else if (_view == _MapView.convoy) {
      setState(() => _showAll = !_showAll);
      _lastFit = DateTime.fromMillisecondsSinceEpoch(0);
      _snack(_showAll ? 'Mostrando o grupo todo' : 'Mostrando a sua moto');
    }
    final p = _me;
    if (p != null) _updateCamera(p, force: true);
  }

  /// Volta a câmera para a moto (no modo atual) depois de arrastar o mapa.
  void _recenter() {
    setState(() => _follow = true);
    _lastFit = DateTime.fromMillisecondsSinceEpoch(0);
    final p = _me;
    if (p != null) _updateCamera(p, force: true);
  }

  /// Troca entre Comboio (de cima) e Solo (primeira pessoa).
  Future<void> _toggleView() async {
    setState(() {
      _view = _view == _MapView.convoy ? _MapView.solo : _MapView.convoy;
      _follow = true;
    });
    (await SharedPreferences.getInstance()).setString('mapView', _view.name);
    final p = _me;
    if (p != null) {
      _updateCamera(p, force: true);
    } else if (_view == _MapView.convoy) {
      // Sem GPS ainda: volta a câmera para a vista de cima.
      _moveCamera(CameraUpdate.newCameraPosition(const CameraPosition(
          target: LatLng(-15.78, -47.93), zoom: 4)));
    }
  }

  /// Anima a câmera do mapa.
  void _moveCamera(CameraUpdate u) {
    final map = _map;
    if (map == null) return;
    map.animateCamera(u, duration: const Duration(milliseconds: 900));
  }

  /// Ponto [meters] à frente de (lat, lng) na direção [bearing].
  static LatLng _ahead(double lat, double lng, double bearing, double meters) {
    final b = bearing * pi / 180;
    final dLat = meters * cos(b) / 111320;
    final dLng = meters * sin(b) / (111320 * cos(lat * pi / 180));
    return LatLng(lat + dLat, lng + dLng);
  }

  /// Câmera acompanhando a moto: de cima, o grupo todo ou primeira pessoa
  /// (inclinada, girando com a direção). [force] ignora o intervalo mínimo.
  void _updateCamera(Position p, {bool force = false}) {
    // Rumo pelo deslocamento (a cada 8 m): mais estável que o do GPS e
    // funciona em aparelhos que não informam a direção. Parado, mantém.
    final from = _bearingFrom;
    if (from == null) {
      _bearingFrom = p;
    } else if (distanceMeters(
            from.latitude, from.longitude, p.latitude, p.longitude) >=
        8) {
      _bearing = bearingBetween(
          from.latitude, from.longitude, p.latitude, p.longitude);
      _bearingFrom = p;
    }
    if (_map == null || (!_follow && !force)) return;
    final here = LatLng(p.latitude, p.longitude);

    if (_view == _MapView.solo) {
      // Primeira pessoa: moto na parte de baixo da tela, olhando a estrada.
      final zoom = (18 + _zoomOffset).clamp(12.0, 20.0);
      _moveCamera(CameraUpdate.newCameraPosition(CameraPosition(
        // Quanto mais afastado o zoom, mais à frente fica o centro.
        target: _ahead(p.latitude, p.longitude, _bearing,
            90 * pow(2, 18 - zoom).toDouble()),
        zoom: zoom,
        tilt: 65,
        bearing: _bearing,
      )));
      return;
    }

    final others = [
      for (final m in _members)
        if (m.uid != widget.uid && m.hasLocation && !m.isStale)
          LatLng(m.lat!, m.lng!)
    ];
    if (_showAll && others.isNotEmpty) {
      // O grupo muda pouco: reenquadra a cada 10 s.
      final now = DateTime.now();
      if (!force && now.difference(_lastFit) < const Duration(seconds: 10)) {
        return;
      }
      _lastFit = now;
      final pts = [here, ...others];
      var s = pts.first.latitude, n = s, w = pts.first.longitude, e = w;
      for (final q in pts) {
        s = min(s, q.latitude);
        n = max(n, q.latitude);
        w = min(w, q.longitude);
        e = max(e, q.longitude);
      }
      if (n - s < 0.004 && e - w < 0.004) {
        _moveCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: here, zoom: 16)));
      } else {
        _moveCamera(CameraUpdate.newLatLngBounds(
            LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)),
            90));
      }
      return;
    }
    // Comboio, só a minha moto: vista de cima, norte para cima.
    _moveCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: here, zoom: (15.5 + _zoomOffset).clamp(5.0, 20.0))));
  }

  /// Botões + e −: acompanhando, ajusta o zoom de acompanhamento;
  /// com o mapa solto, só aproxima/afasta.
  void _zoom(double delta) {
    final p = _me;
    if (_follow && p != null && !(_view == _MapView.convoy && _showAll)) {
      _zoomOffset = (_zoomOffset + delta).clamp(-10.0, 4.0);
      _updateCamera(p, force: true);
    } else {
      _moveCamera(CameraUpdate.zoomBy(delta));
    }
  }

  // ------------------------------------------------------------ velocidade

  /// Velocidade (do GPS ou calculada), limite da pista em que o piloto está
  /// (só pontos da rota, quando navegando) e o alerta de excesso.
  void _updateSpeed(Position p) {
    // Baixa os limites do estado ao abrir e a cada ~20 km rodados.
    final c = _limitsCheckedAt;
    if (c == null ||
        distanceMeters(c.latitude, c.longitude, p.latitude, p.longitude) >
            20000) {
      _limitsCheckedAt = p;
      _speedSvc.ensureFor(p.latitude, p.longitude);
      PoiService.instance.ensureFor(p.latitude, p.longitude);
    }
    // Velocidade do GPS; se o aparelho não informar, calcula pelo deslocamento.
    final prev = _prevPos;
    _prevPos = p;
    if (p.speed > 0.5) {
      _speedMs = p.speed;
    } else if (prev != null) {
      final dt =
          p.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
      if (dt >= 0.5 && dt <= 10) {
        _speedMs = distanceMeters(
                prev.latitude, prev.longitude, p.latitude, p.longitude) /
            dt;
      } else if (dt > 10) {
        _speedMs = 0;
      }
    }
    final kmh = _speedMs * 3.6;
    // Em cima da rota: só vale o limite de pontos da rota (não a marginal).
    final w = _walker, pr = _proj;
    final onRoute = w != null && pr != null && pr.offset < 40;
    final found = _speedSvc.lookup(p.latitude, p.longitude, _bearing, _speedMs,
        routeOffset:
            onRoute ? (la, lo) => w.offsetNear(la, lo, pr.along) : null);
    _roadLimit = _limitTracker.update(found, DateTime.now());
    final speech = _speedAlerter.update(
        kmh, _roadLimit, _speedSvc.settings.value, DateTime.now());
    if (speech != null) _voice.alert(speech);
    _checkReducedSpeedAhead(p, onRoute ? pr.along : null);
  }

  // ---- Velocidade reduzida à frente ("Velocidade reduzida para 60 em 300 m")
  (int, int)? _reducedAhead; // (limite, metros) mostrado no velocímetro
  final Set<String> _reducedAnnounced = {};

  /// Procura à frente (100 a 500 m) um limite pelo menos 10 km/h menor e
  /// avisa "Velocidade reduzida para 60 em 300 metros".
  void _checkReducedSpeedAhead(Position p, double? along) {
    final cur = _roadLimit;
    if (!AppSettings.instance.alerts.value.reducedSpeed ||
        cur == null ||
        _speedMs < 8) {
      if (_reducedAhead != null) setState(() => _reducedAhead = null);
      return;
    }
    final w = _walker;
    (int, int)? found;
    for (final d in const [100, 200, 300, 400, 500]) {
      double la, lo, brg;
      if (along != null && w != null) {
        final q = w.at(along + d);
        (la, lo, brg) = (q.lat, q.lng, q.bearing);
      } else {
        final q = _ahead(p.latitude, p.longitude, _bearing, d.toDouble());
        (la, lo, brg) = (q.latitude, q.longitude, _bearing);
      }
      final l = _speedSvc.lookup(la, lo, brg, _speedMs,
          routeOffset: along != null && w != null
              ? (a, b) => w.offsetNear(a, b, along + d)
              : null);
      // Só placas (não estimados) e redução de pelo menos 10 km/h.
      if (l != null && !l.estimated && l.kmh <= cur.kmh - 10) {
        found = (l.kmh, d);
        break;
      }
    }
    if (found != _reducedAhead) setState(() => _reducedAhead = found);
    if (found == null) return;
    // Fala uma vez por redução (mesmo limite num raio de ~1 km).
    final key =
        '${found.$1}_${(p.latitude * 100).round()}_${(p.longitude * 100).round()}';
    if (_reducedAnnounced.add(key) && found.$2 >= 200) {
      _voice.alert('Atenção: velocidade reduzida para ${found.$1} '
          'em ${found.$2} metros');
    }
  }

  /// Folha de opções do alerta de velocidade (tolerância, máximo pessoal).
  void _showSpeedSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ValueListenableBuilder<SpeedAlertSettings>(
          valueListenable: _speedSvc.settings,
          builder: (_, s, __) {
            void save(SpeedAlertSettings n) => _speedSvc.save(n);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Velocidade',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text(
                      'O velocímetro fica vermelho ao passar do limite da via '
                      '(âmbar quando o limite é estimado).'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Avisar por voz ao passar do limite'),
                    subtitle: const Text(
                        'Só para limites de placa (não para os estimados)'),
                    value: s.roadAlert,
                    onChanged: (v) => save(SpeedAlertSettings(
                        roadAlert: v,
                        tolerance: s.tolerance,
                        personalMax: s.personalMax)),
                  ),
                  if (s.roadAlert) ...[
                    const Text('Avisar a partir de'),
                    Wrap(spacing: 8, children: [
                      for (final t in const [0, 5, 10])
                        ChoiceChip(
                          label: Text(t == 0 ? 'Limite exato' : '+$t km/h'),
                          selected: s.tolerance == t,
                          onSelected: (_) => save(SpeedAlertSettings(
                              roadAlert: true,
                              tolerance: t,
                              personalMax: s.personalMax)),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  const Text('Alerta de velocidade máxima'),
                  const Text(
                      'Avisa por voz quando você passar desta velocidade, '
                      'em qualquer via.',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final v in const [0, 60, 80, 100, 110, 120, 140])
                      ChoiceChip(
                        label: Text(v == 0 ? 'Desligado' : '$v km/h'),
                        selected: s.personalMax == v,
                        onSelected: (_) => save(SpeedAlertSettings(
                            roadAlert: s.roadAlert,
                            tolerance: s.tolerance,
                            personalMax: v)),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  Text(
                    'Limites das vias: projeto Pardal (ODbL) – ANTT, DERs e '
                    '© colaboradores do OpenStreetMap. Onde não há placa '
                    'mapeada, o limite é estimado pelo tipo de via. Respeite '
                    'sempre a sinalização.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Janela de SOS de um membro (ver no mapa, navegar, marcar resolvido).
  void _showAlertDialog(SosAlert a) {
    HapticFeedback.vibrate();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber, color: Colors.red, size: 48),
        title: const Text('SOS no comboio'),
        content: Text('${a.name} pediu ajuda!${_dist(a.lat, a.lng)}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _focus(a.lat, a.lng);
            },
            child: const Text('Ver no mapa'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigate(a.lat, a.lng);
            },
            child: const Text('Ir até lá'),
          ),
        ],
      ),
    );
  }

  /// Lista do grupo e das paradas.
  void _showGroup() {
    final sorted = [..._members]..sort((a, b) => a.name.compareTo(b.name));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            _sheetTitle('Pilotos (${sorted.length})'),
            if (_isLeader || _isCaptain)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                    _isLeader
                        ? 'Toque no piloto para escolher o capitão e os ferrolhos.'
                        : 'Você é o capitão: toque num piloto para passar a capitania.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            for (final m in sorted)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      m.isStale ? Colors.grey : Color(m.bike.color),
                  backgroundImage: m.bike.photoUrl == null
                      ? null
                      : ResizeImage(NetworkImage(m.bike.photoUrl!), width: 96),
                  child: m.bike.photoUrl == null
                      ? Icon(m.bike.style.icon, color: Colors.white)
                      : null,
                ),
                title: Text(
                  [
                    m.uid == widget.uid ? '${m.name} (você)' : m.name,
                    if (_roleOf(m.uid) case final r?) r,
                    if (m.bike.displayName.isNotEmpty) m.bike.displayName,
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _isLeader || (_isCaptain && m.uid != widget.uid)
                    ? IconButton(
                        icon: const Icon(Icons.manage_accounts),
                        tooltip: _isLeader ? 'Capitão / ferrolho' : 'Passar a capitania',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _editRoles(m);
                        },
                      )
                    : (_watchesGroup && _memberOffRoute(m)
                        ? const Icon(Icons.priority_high, color: Colors.amber)
                        : null),
                subtitle: Text(!m.hasLocation
                    ? 'Sem localização ainda'
                    : m.isStale
                        ? 'Sem sinal · última posição ${_ago(m.updatedAt)}'
                        : '${(m.speed * 3.6).round()} km/h${_dist(m.lat!, m.lng!)}'),
                onTap: _isLeader || (_isCaptain && m.uid != widget.uid)
                    ? () {
                        Navigator.pop(ctx);
                        _editRoles(m);
                      }
                    : m.hasLocation
                        ? () {
                            Navigator.pop(ctx);
                            _focus(m.lat!, m.lng!);
                          }
                        : null,
              ),
            _sheetTitle('Paradas (${_stops.length})'),
            if (_stops.isEmpty)
              const ListTile(
                  title: Text('Toque e segure no mapa para adicionar')),
            for (var i = 0; i < _stops.length; i++)
              ListTile(
                leading: CircleAvatar(
                    backgroundColor: Colors.orange, child: Text('${i + 1}')),
                title: Text(_stops[i].name),
                subtitle: Text(_dist(_stops[i].lat, _stops[i].lng)
                    .replaceFirst(' · ', '')),
                onTap: () {
                  Navigator.pop(ctx);
                  _focus(_stops[i].lat, _stops[i].lng);
                },
              ),
          ]),
        ),
      ),
    );
  }

  /// Título das folhas de baixo.
  Widget _sheetTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  /// Copia o código da expedição para enviar ao grupo.
  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _code));
    _snack('Código $_code copiado. Envie para o grupo!');
  }

  /// Sair da expedição (ou, para o líder, encerrar para todos).
  Future<void> _leave() async {
    // O líder pode encerrar a expedição para todos (apaga do Firebase; cada
    // piloto fica com a viagem salva no próprio celular).
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isLeader ? 'Sair ou encerrar?' : 'Sair da expedição?'),
        content: Text(_isLeader
            ? 'Sair: só você deixa o comboio.\n\nEncerrar para todos: a '
                'expedição acaba e é apagada do servidor. A viagem fica salva '
                'em "Minhas viagens" no celular de cada piloto.'
            : 'Você deixará de compartilhar sua localização com o grupo. A '
                'viagem fica salva em "Minhas viagens".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ficar')),
          if (_isLeader)
            TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, 'end'),
                child: const Text('Encerrar para todos')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'leave'),
              child: const Text('Sair')),
        ],
      ),
    );
    if (choice == null) return;
    await _saveRecord();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _hazardSub?.cancel();
    if (choice == 'end') {
      try {
        await _svc.endExpedition(_code);
      } catch (e) {
        _snack('Não foi possível encerrar: $e');
      }
    } else {
      await _svc.leave(_code, widget.uid).catchError((_) {});
    }
    await NotificationService.unsubscribe(_code);
    if (mounted) Navigator.pop(context, true);
  }

  // ------------------------------------------------------------ histórico

  TrackRecorder? _recorder;
  String? _recordId;
  DateTime _recordStart = DateTime.now();
  Timer? _autosave;
  bool _hadExpedition = false;
  bool _endedByLeader = false;

  /// Começa a gravar a viagem para "Minhas viagens" (na expedição, a mesma
  /// viagem continua se reabrir no mesmo dia).
  void _startRecording() {
    if (widget.simulate) return;
    final now = DateTime.now();
    _recorder = TrackRecorder();
    _recordStart = now;
    if (_isExpedition) {
      // Mesma expedição no mesmo dia = a mesma viagem (continua a gravação).
      final day =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      _recordId = 'exp_${_code}_$day';
      HistoryService.instance.get(_recordId!).then((old) {
        if (old == null || !mounted) return;
        _recordStart = old.startedAt;
        _recorder?.seed(
          [
            for (final q in decodePolyline(old.trackPolyline))
              (q.latitude, q.longitude)
          ],
          old.distanceM,
          old.movingS,
          old.maxKmh,
        );
      });
    } else {
      _recordId = 'solo_${now.millisecondsSinceEpoch}';
    }
    // Salva a cada 2 min: se o celular desligar, a viagem não se perde.
    _autosave =
        Timer.periodic(const Duration(minutes: 2), (_) => _saveRecord());
  }

  /// Grava a viagem em "Minhas viagens" (só no celular, nada no Firebase).
  Future<void> _saveRecord() async {
    final rec = _recorder, id = _recordId;
    if (rec == null || id == null || rec.distanceM < 300) return;
    // Mantém os gastos já registrados na viagem (o salvamento automático
    // a cada 2 min não pode apagá-los).
    final old = await HistoryService.instance.get(id);
    await HistoryService.instance.save(TripRecord(
      expenses: old?.expenses ?? const [],
      riders: _isExpedition ? max(1, _members.length) : 1,
      id: id,
      expedition: _isExpedition,
      title: _isExpedition
          ? (_exp?.name ?? 'Expedição $_code')
          : (_trip?.title ?? 'Só dirigir'),
      code: _isExpedition ? _code : null,
      startedAt: _recordStart,
      endedAt: DateTime.now(),
      distanceM: rec.distanceM,
      movingS: rec.movingS,
      maxKmh: rec.maxKmh,
      routePolyline: _exp?.plan.polyline ?? _trip?.plan.polyline ?? '',
      trackPolyline: rec.encoded(),
      stops: [
        for (final s in _stops)
          (name: s.name, lat: s.lat, lng: s.lng, type: s.type.name)
      ],
    ));
  }

  /// O líder encerrou a expedição (ela sumiu do servidor).
  Future<void> _onExpeditionEnded() async {
    if (_endedByLeader) return;
    _endedByLeader = true;
    await _saveRecord();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Expedição encerrada'),
        content: const Text('O líder encerrou a expedição. A sua viagem '
            'ficou salva em "Minhas viagens".'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
    await NotificationService.unsubscribe(_code);
    if (mounted) Navigator.pop(context, true);
  }

  // ------------------------------------------------------------ helpers

  /// Mostra uma mensagem rápida no rodapé.
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// "há 5 min" a partir de uma data.
  String _ago(DateTime? t) {
    if (t == null) return 'agora';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
    return 'há ${d.inHours} h';
  }

  /// Retorna " · 2,3 km" (distância até você) ou "" se sem GPS.
  String _dist(double lat, double lng) {
    if (_me == null) return '';
    final m = Geolocator.distanceBetween(
        _me!.latitude, _me!.longitude, lat, lng);
    final txt = m < 1000
        ? '${m.round()} m'
        : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    return ' · $txt de você';
  }

  // O GPS atualiza a cada segundo. Para não reenviar todos os marcadores ao
  // mapa nativo toda vez, os que não mudaram são reaproveitados (mesmos
  // objetos) e só a minha moto é refeita.
  Set<Marker> _staticMarkers = {};
  int _staticSig = 0;

  /// Marcadores do mapa: os fixos (paradas, grupo, alertas, radares)
  /// reaproveitados e só a moto do piloto refeita a cada leitura (leve).
  Set<Marker> _buildMarkers() {
    final sig = Object.hashAll([
      identityHashCode(_stops),
      identityHashCode(_members),
      identityHashCode(_alerts),
      identityHashCode(_hazards),
      identityHashCode(_radarMarkers),
      _bikeIcons.length,
      _hazardIcons.length,
      _radarIcons.length,
      // Refaz a cada 30 s para atualizar o "há X min" dos colegas.
      DateTime.now().millisecondsSinceEpoch ~/ 30000,
    ]);
    if (sig != _staticSig) {
      _staticSig = sig;
      _staticMarkers = _buildStaticMarkers();
    }
    final me = _me;
    if (me == null) return _staticMarkers;
    final icon = _bikeIcon(widget.userName, _myBike, isMe: true);
    return {
      ..._staticMarkers,
      Marker(
        markerId: const MarkerId('me'),
        position: LatLng(me.latitude, me.longitude),
        zIndex: 3,
        anchor: icon != null ? bikeMarkerAnchor : const Offset(0.5, 1),
        icon: icon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Você'),
      ),
    };
  }

  Set<Polyline> _prfPolylines = {};
  Object? _prfFor;

  /// Linhas do mapa: trechos da PRF (roxo tracejado) e a rota (azul).
  Set<Polyline> _buildPolylines() {
    if (!identical(_prfFor, _stretchesAround)) {
      _prfFor = _stretchesAround;
      _prfPolylines = {
        // Trechos onde a PRF pode fiscalizar com radar portátil.
        for (final s in _stretchesAround)
          Polyline(
            polylineId: PolylineId('prf_${s.id}'),
            points: [for (final (la, lo) in s.points) LatLng(la, lo)],
            width: 8,
            // Roxo tracejado: não confunde com o azul da rota.
            color: Colors.purple.withAlpha(120),
            patterns: [PatternItem.dash(24), PatternItem.gap(10)],
            consumeTapEvents: true,
            onTap: () => _snack(
                '🚔 Trecho com possível radar portátil da PRF: BR-${s.br}, '
                'km ${s.kmFrom.round()} a ${s.kmTo.round()}'),
          ),
      };
    }
    return {
      ..._prfPolylines,
      if (_route.length >= 2) ..._routePolylines(),
    };
  }

  List<Polyline>? _routeLines;
  /// Rota azul com borda escura (refeita só quando a rota muda).
  List<Polyline> _routePolylines() {
    final l = _routeLines;
    if (l != null && identical(l.first.points, _route)) return l;
    return _routeLines = [
      Polyline(
        polylineId: const PolylineId('route_border'),
        points: _route,
        width: 9,
        color: MapScreen.routeBorder,
        zIndex: 1,
      ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: _route,
        width: 6,
        color: MapScreen.routeBlue,
        zIndex: 2,
      ),
    ];
  }

  /// Marcadores que mudam pouco: paradas, grupo, SOS, alertas e radares.
  Set<Marker> _buildStaticMarkers() {
    final markers = <Marker>{};
    for (var i = 0; i < _stops.length; i++) {
      final s = _stops[i];
      markers.add(Marker(
        markerId: MarkerId('stop_${s.id}'),
        position: LatLng(s.lat, s.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: '${i + 1}. ${s.type.emoji} ${s.name}',
          snippet: 'Toque para opções',
          onTap: () => _stopOptions(s),
        ),
      ));
    }
    for (final m in _members) {
      if (!m.hasLocation || m.uid == widget.uid) continue;
      if (_groupGrid && _watchesGroup) continue; // visão em grade
      final icon = _bikeIcon(m.name, m.bike);
      markers.add(Marker(
        markerId: MarkerId('member_${m.uid}'),
        position: LatLng(m.lat!, m.lng!),
        alpha: m.isStale ? 0.5 : 1,
        zIndex: 2,
        anchor: icon != null ? bikeMarkerAnchor : const Offset(0.5, 1),
        icon: icon ??
            BitmapDescriptor.defaultMarkerWithHue(m.isStale
                ? BitmapDescriptor.hueViolet
                : BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(
          title: m.bike.displayName.isEmpty
              ? m.name
              : '${m.name} · ${m.bike.displayName}',
          snippet: m.isStale
              ? 'Sem sinal · ${_ago(m.updatedAt)}'
              : '${(m.speed * 3.6).round()} km/h · ${_ago(m.updatedAt)}',
        ),
      ));
    }
    for (final a in _alerts) {
      markers.add(Marker(
        markerId: MarkerId('sos_${a.id}'),
        position: LatLng(a.lat, a.lng),
        zIndex: 10,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: '🚨 SOS: ${a.name}',
          snippet: 'Toque para traçar rota',
          onTap: () => _navigate(a.lat, a.lng),
        ),
      ));
    }
    for (final r in _radarMarkers) {
      final icon = _radarIcons[r.kind];
      if (icon == null) break;
      markers.add(Marker(
        markerId: MarkerId('radar_${r.id}'),
        position: LatLng(r.lat, r.lng),
        anchor: const Offset(0.5, 0.5),
        zIndex: 4,
        icon: icon,
        infoWindow: InfoWindow(
          title: switch (r.kind) {
            RadarKind.fixed => 'Radar fixo',
            RadarKind.section => 'Radar de velocidade média',
            RadarKind.redLight => 'Radar de avanço de sinal',
          },
          snippet: r.limit > 0 ? 'Limite ${r.limit} km/h' : null,
        ),
      ));
    }
    for (final h in _activeHazards) {
      markers.add(Marker(
        markerId: MarkerId('hazard_${h.id}'),
        position: LatLng(h.lat, h.lng),
        anchor: const Offset(0.5, 0.5),
        zIndex: 5,
        icon: _hazardIcons[h.type] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        onTap: () => setState(() {
          _shownHazard = h;
          _shownManually = true;
        }),
      ));
    }
    return markers;
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    const white = TextStyle(color: Colors.white);
    // Celular deitado: faixas só na metade esquerda e colunas de botões que
    // se ajustam à altura menor. Em pé, nada muda.
    final screen = MediaQuery.of(context).size;
    final landscape = screen.width > screen.height;
    // Navegando: o "voltar" pergunta antes de encerrar a rota.
    return PopScope(
      canPop: !_confirmExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askExitNavigation();
      },
      child: Scaffold(
      // O mapa não muda de tamanho com o teclado: um redimensionamento durante
      // o fechamento da tela derrubava o app (defeito do Flutter com o mapa).
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isExpedition
                    ? (_exp?.name ?? 'Expedição')
                    : widget.simulate
                        ? 'Simulação: ${_trip?.title ?? ''}'
                        : (_trip?.title ?? 'Navegação'),
                overflow: TextOverflow.ellipsis),
            Text(_isExpedition ? _expeditionSubtitle() : _etaText(),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: !_isExpedition
            ? null
            : [
          IconButton(
              icon: const Icon(Icons.route),
              tooltip: 'Roteiro',
              onPressed: _openPlan),
          IconButton(
              icon: Icon(_myBike.style.icon),
              tooltip: 'Meu veículo',
              onPressed: _editBike),
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Copiar código',
              onPressed: _copyCode),
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sair da expedição',
              onPressed: _leave),
        ],
      ),
      body: Stack(children: [
        // Arrastar, girar ou dar zoom com os dedos pausa o acompanhamento
        // (aparece o botão "Recentralizar"). Um toque simples não pausa.
        Listener(
          onPointerDown: (e) => _touchStart = e.position,
          onPointerMove: (e) {
            final s = _touchStart;
            if (_follow && s != null && (e.position - s).distance > 24) {
              setState(() => _follow = false);
            }
          },
          onPointerUp: (_) => _touchStart = null,
          child: GoogleMap(
          initialCameraPosition: const CameraPosition(
              target: LatLng(-15.78, -47.93), zoom: 4), // Brasil
          myLocationEnabled: false, // usamos o marcador da moto
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Trânsito do Google: vias em verde/laranja/vermelho (sem custo).
          // Na economia de bateria, sem trânsito e sem prédios 3D (menos
          // trabalho para o processador gráfico).
          trafficEnabled: AppSettings.instance.showTraffic.value && !_saving,
          buildingsEnabled: !_saving,
          // Mapa escuro à noite (ou sempre, conforme Configurações).
          style: _darkMap ? darkMapStyle : null,
          // Mantém o logo do Google acima da barra de navegação.
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom),
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          onMapCreated: (c) {
            _map = c;
            final p = _me;
            if (p != null) _updateCamera(p, force: true);
          },
          onLongPress: _isExpedition
              ? _addStopAt
              : (_canAddSoloStop
                  ? _addSoloStopAt
                  : (_canStartRoute ? _startRouteAt : null)),
        ),
        ),

        // Botões e faixas ficam acima da barra de navegação do Android
        // (no Samsung o app vai até a borda da tela).
        Positioned.fill(child: SafeArea(top: false, child: Stack(children: [

        // Faixas no topo: SOS do grupo + alerta de perigo próximo
        Positioned(
          top: 8,
          // Deitado: no meio, entre a coluna do velocímetro e a dos botões.
          left: landscape ? 140 : 8,
          right: landscape ? 120 : 8,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_rerouting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.blue.shade700,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.white)),
                      SizedBox(width: 12),
                      Text('Recalculando a rota...',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              )
            else
              _nextTurnCard(),
            // "UauGo, procurar posto": até 3 opções, a perguntada em destaque.
            if (_found.isNotEmpty) _foundCard(),
            // "UauGo, ir para": ouvindo o destino (e o que já entendeu).
            ValueListenableBuilder<bool>(
              valueListenable: _voiceCmd.destListening,
              builder: (_, listening, __) => !listening
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Theme.of(context).colorScheme.primary,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: ValueListenableBuilder<String>(
                            valueListenable: _voiceCmd.destHeard,
                            builder: (_, heard, __) => Row(children: [
                              const Icon(Icons.mic, color: Colors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                    heard.isEmpty
                                        ? _voiceCmd.destPrompt.value
                                        : '“$heard”',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
            ),
            if (_trafficBanner != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.deepOrange.shade700,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    child: Row(children: [
                      Expanded(
                        child: Text(_trafficBanner!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () =>
                            setState(() => _trafficBanner = null),
                      ),
                    ]),
                  ),
                ),
              ),
            if (_alerts.isNotEmpty)
              Material(
                color: Colors.red.shade700,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(children: [
                    for (final a in _alerts.take(3))
                      Row(children: [
                        const Icon(Icons.warning_amber, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${a.uid == widget.uid ? 'Você' : a.name} pediu ajuda · '
                            '${_ago(a.createdAt)}${_dist(a.lat, a.lng)}',
                            style: white,
                          ),
                        ),
                        TextButton(
                            onPressed: () => _focus(a.lat, a.lng),
                            child: const Text('VER', style: white)),
                        TextButton(
                            onPressed: () => _svc.resolveAlert(_code, a.id),
                            child: const Text('OK', style: white)),
                      ]),
                  ]),
                ),
              ),
            if (_askHazard != null) ...[
              if (_alerts.isNotEmpty) const SizedBox(height: 8),
              _askBanner(_askHazard!),
            ] else if (_shownHazard != null) ...[
              if (_alerts.isNotEmpty) const SizedBox(height: 8),
              _hazardBanner(_shownHazard!),
            ],
            if (_radarBanner != null) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.indigo.shade700,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: Row(children: [
                    Text(_radarBanner!.emoji,
                        style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_radarBanner!.text,
                          style: white.copyWith(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => setState(() => _radarBanner = null),
                    ),
                  ]),
                ),
              ),
            ],
            if (_passingSuggestion != null) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.teal.shade700,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(children: [
                    const Icon(Icons.shield, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_passingSuggestion!.name}, do seu clube, está em ${_passingSuggestion!.city} (~${_passingSuggestion!.distanceKm} km). Avisar que você está passando?',
                        style: white,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final m = _passingSuggestion!;
                        setState(() => _passingSuggestion = null);
                        confirmAndNotify(context,
                            clubId: _clubId!,
                            member: m,
                            purpose: ClubPurpose.passing);
                      },
                      child: const Text('AVISAR', style: white),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () =>
                          setState(() => _passingSuggestion = null),
                    ),
                  ]),
                ),
              ),
            ],
            if (_alerts.isEmpty &&
                _shownHazard == null &&
                _passingSuggestion == null &&
                _stops.isEmpty &&
                _isLeader)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.route),
                  title: const Text('Monte o roteiro da viagem'),
                  subtitle: const Text('Saída, paradas, pernoites e destino'),
                  onTap: _openPlan,
                ),
              ),
          ]),
        ),

        // Controles da simulação (pausar, velocidade, linha do tempo)
        if (_sim != null)
          Positioned(left: 8, right: 8, bottom: 16, child: _simControls()),

        // Recentralizar (aparece ao arrastar o mapa) + Iniciar / encerrar.
        // Deitado: à esquerda, para não tapar o marcador do piloto no centro.
        Positioned(
          left: landscape ? 210 : 0,
          right: landscape ? null : 0,
          bottom: _sim != null ? 196 : 96,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_follow && _me != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    elevation: 6,
                  ),
                  onPressed: _recenter,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Recentralizar',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            if (_tripButton() case final btn?) btn,
          ]),
        ),

        // Velocímetro (toque para configurar os alertas de velocidade)
        Positioned(
          left: 12,
          top: landscape ? 8 : null,
          bottom: _sim != null ? 196 : (landscape ? 120 : 136),
          child: _landscapeFit(landscape, Alignment.bottomLeft, Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Radar móvel com UM toque: é o alerta mais útil para todos e
              // precisa ser rápido de marcar. Fica no topo desta coluna.
              if (_sim == null) ...[
                FloatingActionButton(
                  heroTag: 'radar',
                  tooltip: 'Avisar radar móvel aqui',
                  backgroundColor: HazardType.radar.color,
                  foregroundColor: Colors.white,
                  onPressed: _quickRadar,
                  child: Text(HazardType.radar.emoji,
                      style: const TextStyle(fontSize: 28)),
                ),
                const SizedBox(height: 10),
              ],
              // Zoom: na mesma coluna do velocímetro, logo acima dele (assim
              // nunca fica atrás dele nem dos botões da direita).
              FloatingActionButton.small(
                heroTag: 'zoomIn',
                tooltip: 'Aproximar',
                onPressed: () => _zoom(1),
                child: const Icon(Icons.add, size: 28),
              ),
              const SizedBox(height: 6),
              FloatingActionButton.small(
                heroTag: 'zoomOut',
                tooltip: 'Afastar',
                onPressed: () => _zoom(-1),
                child: const Icon(Icons.remove, size: 28),
              ),
              const SizedBox(height: 12),
              // Radar à frente: distância até ele (some ao passar).
              if (_radarPill case final r?)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.indigo, width: 3),
                  ),
                  child: Text(
                      '${r.emoji} ${r.kmh ?? ''}${r.kmh != null ? ' ' : ''}em ${r.m} m',
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                ),
              // Velocidade reduzida à frente.
              if (_reducedAhead case (final lim, final m))
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red, width: 3),
                  ),
                  child: Text('↓ $lim em $m m',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                ),
              ValueListenableBuilder<SpeedAlertSettings>(
                valueListenable: _speedSvc.settings,
                builder: (_, s, __) {
                  final kmh = _me == null ? null : _speedMs * 3.6;
                  return Speedometer(
                    kmh: kmh,
                    limit: _roadLimit,
                    level: kmh == null
                        ? SpeedLevel.normal
                        : SpeedAlerter.level(kmh, _roadLimit, s.personalMax),
                    onTap: _showSpeedSettings,
                  );
                },
              ),
            ],
          )),
        ),

        // Capitão/ferrolhos: grade com os apelidos (⚠️ = fora do trajeto).
        if (_groupGrid && _watchesGroup)
          Positioned(
            left: 8,
            top: MediaQuery.of(context).padding.top + 150,
            child: _groupGridPanel(),
          ),

        // Modo de visualização: Comboio (de cima) x Solo (primeira pessoa)
        if (_sim == null)
        Positioned(
          left: landscape ? 210 : 0,
          right: landscape ? null : 0,
          bottom: 28,
          child: Center(
            child: FloatingActionButton.extended(
              heroTag: 'view',
              tooltip: 'Trocar visualização',
              onPressed: _toggleView,
              icon: Icon(_view == _MapView.convoy
                  ? Icons.groups_2
                  : Icons.visibility),
              label: Text(_view == _MapView.convoy ? 'COMBOIO' : 'SOLO',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ),

        // Botão de reportar perigo (canto esquerdo)
        if (_sim == null)
        Positioned(
          left: 16,
          bottom: 24,
          child: FloatingActionButton.large(
            heroTag: 'hazard',
            tooltip: 'Reportar perigo',
            backgroundColor: Colors.amber,
            foregroundColor: Colors.black,
            onPressed: _showReportSheet,
            child: const Icon(Icons.warning_amber_rounded, size: 44),
          ),
        ),

        // Botões
        Positioned(
          right: 16,
          top: landscape ? 8 : null,
          bottom: _sim != null ? 196 : 24,
          child: _landscapeFit(landscape, Alignment.bottomRight, Column(mainAxisSize: MainAxisSize.min, children: [
            if (_clubId != null) ...[
              FloatingActionButton(
                heroTag: 'club',
                onPressed: _showClubActions,
                tooltip: 'Clube',
                backgroundColor: Colors.teal,
                child: const Icon(Icons.shield, color: Colors.white),
              ),
              const SizedBox(height: 12),
            ],
            ValueListenableBuilder<bool>(
              valueListenable: _voice.alertsOn,
              builder: (_, on, __) => FloatingActionButton.small(
                heroTag: 'voice',
                tooltip: 'Voz',
                onPressed: _showVoiceSettings,
                child: Icon(on ? Icons.volume_up : Icons.volume_off),
              ),
            ),
            const SizedBox(height: 12),
            if (_canAddSoloStop) ...[
              FloatingActionButton.small(
                heroTag: 'addStop',
                tooltip: 'Adicionar parada (ou segure no mapa)',
                onPressed: _addSoloStopBySearch,
                child: const Icon(Icons.add_location_alt),
              ),
              const SizedBox(height: 12),
            ],
            if (_canStartRoute) ...[
              FloatingActionButton.small(
                heroTag: 'newRoute',
                tooltip: 'Traçar rota (ou segure no mapa)',
                onPressed: _startRouteBySearch,
                child: const Icon(Icons.directions),
              ),
              const SizedBox(height: 12),
            ],
            if (_watchesGroup) ...[
              FloatingActionButton.small(
                heroTag: 'groupGrid',
                tooltip: _groupGrid ? 'Ver os pilotos no mapa' : 'Ver em grade (apelidos)',
                onPressed: () => setState(() => _groupGrid = !_groupGrid),
                child: Badge(
                  isLabelVisible: _members.any(_memberOffRoute),
                  backgroundColor: Colors.amber,
                  label: Text('${_members.where(_memberOffRoute).length}',
                      style: const TextStyle(color: Colors.black)),
                  child: Icon(_groupGrid ? Icons.place : Icons.view_list),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_isExpedition) ...[
              FloatingActionButton(
                heroTag: 'group',
                onPressed: _showGroup,
                tooltip: 'Grupo e paradas',
                child: Badge(
                  label: Text('${_members.length}'),
                  child: const Icon(Icons.groups),
                ),
              ),
              const SizedBox(height: 12),
            ],
            FloatingActionButton(
              heroTag: 'me',
              onPressed: _centerOnMe,
              tooltip: !_follow
                  ? 'Voltar a acompanhar'
                  : _view == _MapView.convoy
                      ? (_showAll ? (_myBike.style.isCar ? 'Mostrar só o meu carro' : 'Mostrar só a minha moto') : 'Mostrar o grupo todo')
                      : 'Acompanhando',
              child: Icon(!_follow
                  ? Icons.my_location
                  : _view == _MapView.convoy
                      ? (_showAll ? Icons.person_pin_circle : Icons.zoom_out_map)
                      : Icons.navigation),
            ),
            if (_sim == null) ...[
            const SizedBox(height: 20),
            // Precisa SEGURAR para evitar SOS acidental (luva, vibração).
            // Sozinho (sem grupo), abre os telefones de emergência.
            GestureDetector(
              onLongPress: _isExpedition ? _sendSos : _showEmergency,
              onTap: () => _snack(_isExpedition
                  ? 'Segure o botão para enviar o SOS'
                  : 'Segure o botão para ver os telefones de emergência'),
              child: Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(blurRadius: 10, color: Colors.black54)
                  ],
                ),
                child: const Text('SOS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900)),
              ),
            ),
            ],
          ])),
        ),
      ]))),
      ]),
    ));
  }

  // ---- "UauGo, procurar posto": lugares no caminho

  /// Resultados oferecidos agora (até 3) e qual está sendo perguntado.
  List<FoundPlace> _found = [];
  int _foundIdx = 0;

  /// Procura o lugar: navegando, ao longo da rota e só o que está à frente;
  /// sem rota, perto. Fala o mais próximo e pergunta se inclui como parada.
  Future<void> _voiceFind(FindCommand c) async {
    var cat = c.category;
    var cheap = c.cheap;
    String? text;
    if (cat == null) {
      // Fora da lista ("procurar pizzaria"...): ouve o pedido livre.
      final said = await _voiceCmd.listenFree('O que você procura? Fale agora');
      if (!mounted) return;
      if (said == null || said.trim().isEmpty) {
        _voice.reply('Não entendi. Diga, por exemplo: $voiceWakeDisplay, procurar posto.');
        return;
      }
      // A IA (Gemini) entende o pedido; sem internet, usa o texto como está.
      final ai = await PlacesService().interpret(said);
      if (!mounted) return;
      if (ai != null && ai.action == 'saved' && ai.saved.isNotEmpty) {
        await _voiceGoTo(saved: ai.saved);
        return;
      }
      if (ai != null && ai.action == 'goto' && ai.query.isNotEmpty) {
        await _goToSpoken(ai.query);
        return;
      }
      cat = FindCategory.values.where((f) => f.name == ai?.category).firstOrNull;
      cheap = ai?.cheap ?? false;
      if (cat == null) {
        text = ai != null && ai.query.isNotEmpty ? ai.query : cleanFindQuery(said);
        cat = findWords[text.toLowerCase()];
        if (cat != null) text = null;
      }
    }
    if (_sim != null) {
      _voice.reply('Na simulação a busca de lugares fica desligada.');
      return;
    }
    final p = _me;
    if (p == null) {
      _voice.reply('Ainda sem a sua posição pelo GPS.');
      return;
    }
    final what = '${cat?.spoken ?? text}${cheap ? ' barato' : ''}';
    _lastFindSpoken = cat?.spoken;
    _voice.reply('Procurando $what.');
    final trip = _trip, w = _walker, pr = _proj;
    final onRoute = _navigating && trip != null && w != null && pr != null &&
        pr.offset < 250 && trip.plan.polyline.isNotEmpty;
    final r = await PlacesService().find(cat,
        text: text,
        cheap: cheap,
        lat: p.latitude,
        lng: p.longitude,
        polyline: onRoute ? trip.plan.polyline : null);
    if (!mounted) return;
    if (r.limit) {
      _voice.reply('Limite de buscas de hoje atingido. Tente amanhã.');
      return;
    }
    final ranked = rankFound(r.places,
        alongOf: onRoute
            ? (la, lo) {
                final q = w.project(la, lo);
                return (along: q.along, offset: q.offset);
              }
            : null,
        riderAlong: onRoute ? pr.along : null,
        distanceTo: (la, lo) =>
            distanceMeters(p.latitude, p.longitude, la, lo));
    if (ranked.isEmpty) {
      _voice.reply(
          'Não encontrei $what ${onRoute ? 'à frente na rota' : 'por perto'}.');
      return;
    }
    setState(() {
      _found = ranked.take(3).toList();
      _foundIdx = 0;
    });
    _offerFound();
  }

  /// Fala a opção atual e pergunta se inclui como parada.
  void _offerFound() {
    final f = _found[_foundIdx];
    _voice.reply('${f.name}, a ${spokenDistance(f.meters)}'
        '${f.onRoute ? ', no caminho' : ''}. '
        '${_isExpedition ? 'No comboio, combine a parada com o líder.' : 'Adicionar como parada? Diga sim ou não.'}');
  }

  /// "Não": oferece a próxima opção (ou encerra).
  void _nextFound() {
    if (_foundIdx + 1 >= _found.length) {
      setState(() => _found = []);
      _voice.reply('Sem mais opções.');
      return;
    }
    setState(() => _foundIdx++);
    _offerFound();
  }

  /// "Sim" (ou toque): navegando, inclui o lugar como próxima parada (o
  /// destino continua o mesmo); sem rota, abre a rota até ele.
  Future<void> _addFoundStop(FoundPlace f) async {
    setState(() => _found = []);
    if (_isExpedition) {
      _voice.reply('No comboio, combine a parada com o líder.');
      return;
    }
    final trip = _trip, p = _me;
    if (trip == null || _arrivedAtDestination || !_navigating || p == null) {
      // Sem rota: a tela inicial abre a prévia da rota até o lugar.
      await _voice.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
      SharedPlaceService.instance
        ..fromVoice = true
        ..pending.value = 'geo:${f.lat},${f.lng}?q=${f.lat},${f.lng}'
            '(${Uri.encodeComponent(f.name)})';
      return;
    }
    final stopType = FindCategory.values
            .where((c) => c.spoken == _lastFindSpoken)
            .firstOrNull
            ?.stopType ??
        StopType.waypoint;
    await _insertSoloStop(f.name, f.lat, f.lng, stopType);
  }

  /// Navegando sozinho: inclui a parada como a PRÓXIMA do caminho (antes do
  /// destino) e recalcula a rota a partir de onde o piloto está.
  Future<void> _insertSoloStop(
      String name, double lat, double lng, StopType type) async {
    final trip = _trip, p = _me;
    if (trip == null || p == null) return;
    var next = 1;
    while (next < trip.stops.length - 1 &&
        _stopArrived.contains(trip.stops[next].id)) {
      next++;
    }
    setState(() => _rerouting = true);
    final nt = await TripService.build(
      title: trip.title,
      points: [
        TripPoint('Sua posição', p.latitude, p.longitude, type: StopType.meet),
        TripPoint(name, lat, lng, type: type),
        for (final s in trip.stops.skip(next))
          TripPoint(s.name, s.lat, s.lng, type: s.type),
      ],
      avoidTolls: trip.plan.avoidTolls,
      avoidHighways: trip.plan.avoidHighways,
    );
    if (!mounted) return;
    setState(() => _rerouting = false);
    if (nt == null) {
      _voice.reply('Não consegui incluir a parada. Confira a internet.');
      return;
    }
    _applyTrip(nt);
    _voice.reply('Parada incluída: $name.');
  }

  /// Rota normal em andamento (sozinho): dá para incluir paradas.
  bool get _canAddSoloStop =>
      !_isExpedition && _sim == null && _navigating && _trip != null &&
      !_arrivedAtDestination;

  /// "Só dirigir" (ou já chegou ao destino): dá para traçar uma rota.
  bool get _canStartRoute =>
      !_isExpedition && _sim == null && (_trip == null || _arrivedAtDestination);

  /// Botão "Traçar rota": busca o destino e abre a prévia da rota.
  Future<void> _startRouteBySearch() async {
    final p = _me;
    final picked = await Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlaceSearchPage(
          near: p == null ? null : LatLng(p.latitude, p.longitude),
          title: 'Para onde?'),
    ));
    if (picked == null || !mounted) return;
    await _openRouteTo(picked.name, picked.lat, picked.lng);
  }

  /// Segurou no mapa ("Só dirigir"): rota até aquele ponto.
  Future<void> _startRouteAt(LatLng pos) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Traçar rota até aqui?'),
        content: const Text('Na prévia dá para incluir paradas antes de iniciar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Traçar rota')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _openRouteTo('Ponto no mapa', pos.latitude, pos.longitude);
  }

  /// Sai do "Só dirigir" e a tela inicial abre a prévia da rota até o lugar.
  Future<void> _openRouteTo(String name, double lat, double lng) async {
    await _voice.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
    SharedPlaceService.instance.pending.value =
        'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})';
  }

  /// Botão "Adicionar parada": busca o lugar por nome (perto do piloto).
  Future<void> _addSoloStopBySearch() async {
    final p = _me;
    final picked = await Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlaceSearchPage(
          near: p == null ? null : LatLng(p.latitude, p.longitude),
          title: 'Parada no caminho'),
    ));
    if (picked == null || !mounted) return;
    await _insertSoloStop(picked.name, picked.lat, picked.lng, StopType.waypoint);
  }

  /// Segurou no mapa (rota normal): parada naquele ponto.
  Future<void> _addSoloStopAt(LatLng pos) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parada aqui'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nome (ex.: posto, almoço)'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? 'Parada' : ctrl.text),
              child: const Text('Incluir na rota')),
        ],
      ),
    );
    if (name == null || !mounted) return;
    await _insertSoloStop(name.trim(), pos.latitude, pos.longitude, StopType.waypoint);
  }

  /// Categoria da última busca (tipo da parada ao incluir).
  String? _lastFindSpoken;

  // ---- Veículo parado no acostamento (opção; alerta para quem vem atrás)
  DateTime? _stoppedSince;
  DateTime _lastFastAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _movingSince;
  String? _myStoppedAlert;

  /// Parado mais de 2 min numa rodovia (via de 80+ km/h, vindo a mais de
  /// 60 km/h, longe de semáforo): publica "veículo parado". Voltou a andar
  /// (10 s): tira o alerta.
  void _checkStoppedOnShoulder(Position p) {
    // Automático para todos (segurança de quem vem atrás); o alerta não
    // mostra quem é. "Não avisar" no aviso tira na hora (ex.: parou num posto).
    if (_sim != null) return;
    final now = DateTime.now();
    final v = _speedMs;
    if (v > 16.7) _lastFastAt = now;
    if (v > 5) {
      _stoppedSince = null;
      _movingSince ??= now;
      final id = _myStoppedAlert;
      if (id != null && now.difference(_movingSince!) > const Duration(seconds: 10)) {
        _myStoppedAlert = null;
        if (id != 'pendente' && id != 'removido') _hazardSvc.removeMine(id);
      }
      return;
    }
    _movingSince = null;
    if (v > 1.5) return;
    _stoppedSince ??= now;
    final highway = (_roadLimit?.kmh ?? 0) >= 80;
    if (_myStoppedAlert != null ||
        AuthService.isAnonymous ||
        !highway ||
        now.difference(_stoppedSince!) < const Duration(minutes: 2) ||
        now.difference(_lastFastAt) > const Duration(minutes: 5) ||
        PoiService.instance.signalNear(p.latitude, p.longitude, meters: 150)) {
      return;
    }
    _myStoppedAlert = 'pendente';
    _hazardSvc
        .report(HazardType.stoppedVehicle, p.latitude, p.longitude, widget.uid)
        .then((id) {
      _myStoppedAlert = id;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Você está parado: quem vem atrás vê "veículo parado".'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Não avisar',
          onPressed: () {
            _hazardSvc.removeMine(id);
            _myStoppedAlert = 'removido'; // não marca de novo nesta parada
          },
        ),
      ));
    }).catchError((_) {
      _myStoppedAlert = null;
    });
  }

  /// Diálogo "Trocar a rota?" aberto (aceita "sim"/"não" por voz).
  BuildContext? _voiceConfirmCtx;

  /// "UauGo, ir para": ouve o destino (Google) e leva ao "Para onde?" da
  /// tela inicial já pesquisando. Navegando, pergunta antes de trocar a rota.
  Future<void> _voiceGoTo({String? saved}) async {
    if (_isExpedition) {
      _voice.reply('No comboio, o destino segue o roteiro do grupo.');
      return;
    }
    // "UauGo, ir para casa": local salvo (não precisa da pesquisa por voz).
    if (saved != null) {
      await SavedPlacesService.instance.load();
      final p = SavedPlacesService.instance.get(saved);
      if (!mounted) return;
      if (p == null) {
        _voice.reply('Você ainda não salvou ${saved == savedHome ? 'casa' : 'o trabalho'}. '
            'Salve na tela inicial.');
        return;
      }
      if (_confirmExit && !await _confirmNewRoute(p.name)) return;
      await _voice.stop();
      if (!mounted) return;
      Navigator.of(context).pop();
      SharedPlaceService.instance
        ..fromVoice = true
        ..pending.value = 'geo:${p.lat},${p.lng}?q=${p.lat},${p.lng}'
            '(${Uri.encodeComponent(p.name)})';
      return;
    }
    if (!_voiceCmd.routeByVoice.value) {
      _voice.reply('Ligue a pesquisa de trajeto por voz nas configurações.');
      return;
    }
    final text = (await _voiceCmd.recognizeDestination())?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      _voice.reply('Não entendi o destino.');
      return;
    }
    await _goToSpoken(text);
  }

  /// Vai ao destino falado: a tela inicial pesquisa e abre a rota (navegando,
  /// pergunta antes de trocar).
  Future<void> _goToSpoken(String text) async {
    if (_isExpedition) {
      _voice.reply('No comboio, o destino segue o roteiro do grupo.');
      return;
    }
    if (_confirmExit && !await _confirmNewRoute(text)) return;
    await _voice.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
    // A tela inicial pesquisa o destino (como um endereço recebido).
    SharedPlaceService.instance
      ..fromVoice = true
      ..pending.value = text;
  }

  /// "Trocar a rota para X?" (aceita "sim"/"não" por voz).
  Future<bool> _confirmNewRoute(String text) async {
    {
      _voice.reply('Trocar a rota para $text? Diga sim ou não.');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          _voiceConfirmCtx = ctx;
          return AlertDialog(
            title: const Text('Trocar a rota?'),
            content: Text('Novo destino: "$text".\nA rota atual será encerrada.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Não')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Sim, trocar')),
            ],
          );
        },
      );
      _voiceConfirmCtx = null;
      return ok == true && mounted;
    }
  }

  /// Opções encontradas ("procurar posto"): nome, distância e "Adicionar".
  Widget _foundCard() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text('Encontrados ${_isExpedition ? '' : '(toque para incluir)'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Fechar',
                onPressed: () => setState(() => _found = []),
              ),
            ]),
            for (var i = 0; i < _found.length; i++)
              ListTile(
                dense: true,
                selected: i == _foundIdx,
                contentPadding: EdgeInsets.zero,
                title: Text(_found[i].name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  formatDistance(_found[i].meters.round()),
                  if (_found[i].onRoute) 'no caminho',
                  if (_found[i].price == 'PRICE_LEVEL_INEXPENSIVE') 'barato',
                  if (_found[i].open == true) 'aberto',
                ].join(' · ')),
                trailing: _isExpedition
                    ? null
                    : FilledButton.tonal(
                        onPressed: () => _addFoundStop(_found[i]),
                        child: const Text('Incluir')),
              ),
          ]),
        ),
      ),
    );
  }

  // ---- Modo carro (Android Auto)

  /// Próxima manobra "de verdade" (pula "Continue para...") e a distância
  /// até ela (pela rota, quando houver).
  ({NavStep step, double meters})? _upcomingTurn(Position p) {
    final nav = _nav;
    if (nav == null || nav.finished) return null;
    var i = nav.nextIndex;
    while (i < nav.steps.length - 1 && nav.steps[i].isSilent) {
      i++;
    }
    final s = nav.steps[i];
    final ra = _riderAlong;
    final d = (ra != null ? nav.routeDistanceTo(i, ra) : null) ??
        distanceMeters(p.latitude, p.longitude, s.lat, s.lng);
    return (step: s, meters: d);
  }

  /// Manda para a tela do carro a manobra, a chegada, o radar e a posição.
  void _sendToCar(Position p) {
    if (!CarService.instance.connected.value) return;
    final turn = _navigating ? _upcomingTurn(p) : null;
    final w = _walker;
    final left = w == null ? 0.0 : w.remainingFrom(p.latitude, p.longitude);
    final speed = _etaSpeed ?? _trip?.averageSpeed ?? 16.7;
    final pill = _radarPill;
    CarService.instance.update(
      lat: p.latitude,
      lng: p.longitude,
      bearing: _bearing,
      speedKmh: (_speedMs * 3.6).round(),
      limitKmh: _roadLimit?.kmh ?? 0,
      text: turn?.step.text,
      maneuver: turn?.step.maneuver ?? '',
      meters: turn?.meters ?? 0,
      remainingM: left,
      eta: DateTime.now().add(Duration(seconds: (left / speed).round())),
      alert: pill == null
          ? null
          : '${pill.emoji} ${pill.kmh ?? ''}${pill.kmh != null ? ' ' : ''}em ${pill.m} m',
    );
  }

  /// Botão da tela do carro.
  Future<void> _onCarAction(String a) async {
    if (!mounted) return;
    switch (a) {
      case 'radar':
        await _reportHazard(HazardType.radar);
      case 'hazard':
        await _reportHazard(HazardType.danger);
      case 'stop':
        if (!_navigating) return;
        await _voice.stop();
        if (!mounted) return;
        if (_isExpedition) {
          setState(() {
            _navigating = false;
            _applyWakelock();
          });
        } else {
          Navigator.of(context).pop();
        }
    }
  }

  /// Deitado: a coluna encolhe para caber na altura (em pé, sem mudança).
  Widget _landscapeFit(bool landscape, Alignment alignment, Widget child) =>
      landscape
          ? FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child)
          : child;

  /// Rota em andamento: sair da tela pede confirmação.
  bool get _confirmExit =>
      _navigating && _sim == null && !_arrivedAtDestination;

  /// "Voltar" durante a navegação: pergunta se quer mesmo sair (a rota é
  /// encerrada). Na expedição, sair do mapa não tira do comboio.
  Future<void> _askExitNavigation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da navegação?'),
        content: Text(_isExpedition
            ? 'A navegação até o destino será encerrada. Você continua no '
                'comboio e pode voltar ao mapa pela tela inicial.'
            : 'A rota até o destino será encerrada.'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuar navegando')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _voice.stop();
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------ navegação

  /// "Iniciar" na expedição: liga a narração, o painel de manobras e a
  /// primeira pessoa.
  void _startNavigation() {
    AnalyticsService.event('expedition_start');
    if (_nav == null) {
      _snack(_isLeader
          ? 'Monte o roteiro primeiro (botão de rota no topo)'
          : 'O líder ainda não montou o roteiro');
      return;
    }
    setState(() {
      _navigating = true;
      _applyWakelock();
      _view = _MapView.solo;
      _follow = true;
      _navSynced = false;
    });
    _voice.setNarration(true);
    final p = _me;
    if (p != null) _updateCamera(p, force: true);
  }

  bool _arrivedAtDestination = false;

  /// Chegou ao destino final: a navegação termina sozinha (narração e
  /// recálculo de rota param).
  /// - Sozinho: salva a viagem em "Minhas viagens", desliga o GPS e mostra
  ///   "Você chegou"; a tela fecha sozinha em 20 s (dá para ficar no mapa).
  /// - Expedição: só a navegação para; continua compartilhando a posição
  ///   com o grupo até sair da expedição.
  /// - Simulação: a moto de mentira para.
  Future<void> _onArrivedDestination(Stop s) async {
    if (_arrivedAtDestination) return;
    _arrivedAtDestination = true;
    setState(() {
      _navigating = false;
      _applyWakelock();
      _offRoute = false;
    });
    final sim = _sim;
    if (sim != null) {
      sim.paused.value = true;
      _voice.narrate('Você chegou ao destino: ${s.name}. Fim da simulação.',
          force: true);
      return;
    }
    if (_isExpedition) {
      _voice.alert('Você chegou ao destino: ${s.name}. Navegação encerrada.');
      _snack('🏁 Chegada! A navegação foi encerrada; você continua no comboio.');
      return;
    }
    _voice.alert('Você chegou ao destino: ${s.name}. Viagem encerrada.');
    await _saveRecord();
    _stopGps();
    if (!mounted) return;
    var autoClose = true;
    BuildContext? dialogCtx;
    final timer = Timer(const Duration(seconds: 20), () {
      final c = dialogCtx;
      if (autoClose && c != null && c.mounted) Navigator.of(c).pop('close');
    });
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        dialogCtx = ctx;
        return AlertDialog(
          title: const Text('🏁 Você chegou!'),
          content: Text('${s.name}\n\nA navegação foi encerrada e a viagem '
              'ficou salva em "Minhas viagens".\n\nEsta tela fecha sozinha '
              'em 20 segundos.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'stay'),
                child: const Text('Ficar no mapa')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'close'),
                child: const Text('Fechar')),
          ],
        );
      },
    );
    autoClose = false;
    timer.cancel();
    if (!mounted) return;
    if (choice == 'stay') {
      _startGps(); // só o mapa e os avisos, sem navegação
    } else {
      Navigator.of(context).pop();
    }
  }

  /// "Encerrar" (com confirmação): na expedição desliga a navegação; sozinho
  /// fecha a tela.
  Future<void> _stopNavigation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar navegação?'),
        content: Text(_isExpedition
            ? 'A narração e o painel de manobras param. Você continua no '
                'comboio, compartilhando a posição com o grupo.'
            : 'A navegação será encerrada.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _voice.stop();
    if (!mounted) return;
    if (_isExpedition) {
      setState(() {
        _navigating = false;
        _applyWakelock();
        _view = _MapView.convoy;
      });
      final p = _me;
      if (p != null) _updateCamera(p, force: true);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// "Iniciar simulação": a moto de mentira começa a andar.
  void _startSimulation() {
    final sim = _sim;
    if (sim == null) return;
    setState(() => _simStarted = true);
    _navSynced = false;
    sim.paused.value = false;
  }

  /// Botão grande de iniciar/encerrar (acima do botão Comboio/Solo).
  Widget? _tripButton() {
    if (_sim != null) {
      if (_simStarted) return null; // "Encerrar" fica na barra da simulação
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
        onPressed: _startSimulation,
        icon: const Icon(Icons.play_arrow, size: 28),
        label: const Text('Iniciar simulação',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );
    }
    if (_navigating) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        onPressed: _stopNavigation,
        icon: const Icon(Icons.stop),
        label: const Text('Encerrar',
            style: TextStyle(fontWeight: FontWeight.w800)),
      );
    }
    if (_isExpedition && _routeRecs.length >= 2) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        onPressed: _startNavigation,
        icon: const Icon(Icons.navigation),
        label: const Text('Iniciar',
            style: TextStyle(fontWeight: FontWeight.w800)),
      );
    }
    return null;
  }

  /// "Chegada 10:43 · faltam 85 km" (navegação sozinho e simulação).
  String _etaText() {
    final w = _walker, p = _me, trip = _trip;
    if (w == null || trip == null) return 'Radares, perigos e velocidade';
    final left = p == null ? w.length : w.remainingFrom(p.latitude, p.longitude);
    final km = formatDistance(left.round());
    if (widget.simulate) return 'Faltam $km';
    // Com o trânsito conferido, usa a velocidade efetiva de agora.
    final secs = (left / (_etaSpeed ?? trip.averageSpeed)).round();
    final eta = DateTime.now().add(Duration(seconds: secs));
    return 'Chegada ${formatTime(eta)} · ${formatDuration(secs)} · $km';
  }

  /// Expedição: navegando, chegada e quanto falta pela rota do grupo (mesmo
  /// numa rota própria para voltar a ela), e o código; parado, só o código.
  String _expeditionSubtitle() {
    final w = _expWalker ?? _walker, p = _me;
    if (!_navigating || w == null || _arrivedAtDestination) return 'Código: $_code';
    final left = p == null ? w.length : w.remainingFrom(p.latitude, p.longitude);
    // Velocidade: a do trânsito conferido ou a média planejada do roteiro.
    var dist = 0, dur = 0;
    for (final s in _stops) {
      dist += s.legDistanceM;
      dur += s.legDurationS;
    }
    final speed = _etaSpeed ?? (dur > 0 ? dist / dur : 16.7);
    final secs = (left / speed).round();
    final eta = DateTime.now().add(Duration(seconds: secs));
    return 'Chegada ${formatTime(eta)} · ${formatDuration(secs)} · '
        '${formatDistance(left.round())} · código $_code';
  }

  /// Próxima manobra no topo da tela (como no Waze/Google Maps).
  Widget _nextTurnCard() {
    final nav = _nav, p = _me;
    final show = nav != null &&
        p != null &&
        !nav.finished &&
        (_sim != null ? _simStarted : _navigating);
    if (!show) return const SizedBox.shrink();
    // Mostra a próxima manobra "de verdade" (pula "Continue para...").
    var i = nav.nextIndex;
    while (i < nav.steps.length - 1 && nav.steps[i].isSilent) {
      i++;
    }
    final s = nav.steps[i];
    // Pela rota, quando houver; senão, em linha reta.
    final ra = _riderAlong;
    final d = (ra != null ? nav.routeDistanceTo(i, ra) : null) ??
        distanceMeters(p.latitude, p.longitude, s.lat, s.lng);
    final icon = switch (s.maneuver) {
      final m when m.contains('left') => Icons.turn_left,
      final m when m.contains('right') => Icons.turn_right,
      final m when m.startsWith('roundabout') => Icons.roundabout_right,
      'merge' => Icons.merge,
      _ => Icons.straight,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.green.shade800,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 40),
            const SizedBox(width: 10),
            Text(formatDistance(d.round()),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(s.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ]),
        ),
      ),
    );
  }

  /// Barra da simulação: pausar, 1x/5x/20x, visão, encerrar e linha do tempo.
  Widget _simControls() {
    final sim = _sim!;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            ValueListenableBuilder<bool>(
              valueListenable: sim.paused,
              builder: (_, paused, __) => IconButton.filled(
                iconSize: 32,
                tooltip: paused ? 'Continuar' : 'Pausar',
                onPressed: () {
                  if (!_simStarted) {
                    _startSimulation();
                  } else if (sim.finished) {
                    sim.restart();
                    _stopArrived.clear();
                    _stopNearAnnounced.clear();
                    _navSynced = false;
                  } else {
                    sim.paused.value = !paused;
                  }
                },
                icon: Icon(sim.finished
                    ? Icons.replay
                    : paused
                        ? Icons.play_arrow
                        : Icons.pause),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: sim.multiplier,
                builder: (_, m, __) => SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1x')),
                    ButtonSegment(value: 5, label: Text('5x')),
                    ButtonSegment(value: 20, label: Text('20x')),
                  ],
                  selected: {m},
                  onSelectionChanged: (s) => sim.multiplier.value = s.first,
                ),
              ),
            ),
            IconButton(
              tooltip: _view == _MapView.convoy ? 'Ver em primeira pessoa' : 'Ver de cima',
              onPressed: _toggleView,
              icon: Icon(_view == _MapView.convoy
                  ? Icons.visibility
                  : Icons.map_outlined),
            ),
          ]),
          if (_simStarted)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                label: const Text('Encerrar simulação',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ValueListenableBuilder<double>(
            valueListenable: sim.progress,
            builder: (_, v, __) => Slider(
              value: v.clamp(0.0, 1.0),
              onChanged: (x) => sim.seek(x),
              onChangeEnd: (_) {
                // Pulou no tempo: recomeça narração e avisos do ponto novo.
                _navSynced = false;
                _stopArrived.clear();
                _stopNearAnnounced.clear();
                _radarSpoken.clear();
                _poiSpoken.clear();
                _halfwaySaid = false;
                _stretchAnnounced.clear();
                _announced.clear();
              },
            ),
          ),
        ]),
      ),
    );
  }

  /// Sozinho não há grupo para avisar: telefones de emergência e
  /// compartilhar a localização com quem você quiser.
  void _showEmergency() {
    HapticFeedback.heavyImpact();
    final p = _me;
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            leading: Icon(Icons.emergency, color: Colors.red, size: 36),
            title: Text('Emergência',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          for (final (num, label) in const [
            ('192', 'SAMU (ambulância)'),
            ('193', 'Bombeiros (resgate)'),
            ('191', 'PRF (rodovias federais)'),
            ('190', 'Polícia Militar'),
          ])
            ListTile(
              leading: const Icon(Icons.call),
              title: Text('$num · $label'),
              onTap: () => launchUrl(Uri.parse('tel:$num')),
            ),
          if (p != null)
            ListTile(
              leading: const Icon(Icons.share_location),
              title: const Text('Enviar minha localização (WhatsApp...)'),
              onTap: () => SharePlus.instance.share(ShareParams(
                  text: '🆘 Preciso de ajuda. Estou aqui: '
                      'https://www.google.com/maps/search/?api=1&query='
                      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')),
            ),
        ]),
      ),
    );
  }
}

/// Comboio: vista de cima. Solo: primeira pessoa, olhando a estrada.
enum _MapView { convoy, solo }
