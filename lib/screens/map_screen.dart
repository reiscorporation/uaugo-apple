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
import 'dart:io' show InternetAddress;
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/gps_speed.dart';
import '../logic/route_traffic.dart';
import '../logic/voice_commands.dart';
import '../logic/group_requests.dart';
import '../logic/find_places.dart';
import '../logic/costs.dart' show formatMoney, fuelLiters;
import '../logic/tolls.dart';
import '../logic/rodizio.dart';
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
import '../services/live_sos.dart';
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
import '../services/speed_fix_service.dart';
import '../services/voice_command_service.dart';
import '../services/voice_service.dart';
import '../services/app_settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'plan_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import '../l10n/i18n.dart';
import '../widgets/toll_confirm_sheet.dart';
import '../services/media_service.dart';
import '../widgets/sim3d_view.dart';
import '../services/directions_service.dart';
import '../services/route_engine_service.dart';
import '../services/minimized_trip.dart';
import '../services/vias_service.dart';

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
    this.simStart,
    this.startNavigation = false,
  });

  final String? code;
  final String uid;
  final String userName;
  final Trip? trip;
  final bool simulate;

  /// Simulação retomada depois de o Android fechar o app: ponto (0 a 1).
  final double? simStart;

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
      (LiveSos.active.value != null ||
          (_isExpedition && AppSettings.instance.backgroundShare.value) ||
          _carMode);

  /// Android Auto conectado e navegando: o celular costuma ficar bloqueado,
  /// mas GPS, voz e avisos continuam (a tela é a do carro).
  bool get _carMode =>
      _sim == null && _navigating && CarService.instance.connected.value;

  /// O GPS atual roda no serviço com notificação fixa ("UauGo ativo")?
  bool _bgGps = false;

  /// Parado há tanto tempo em segundo plano = o piloto esqueceu o app aberto:
  /// o GPS desliga (volta sozinho ao abrir o app).
  static const _idleBackgroundLimit = Duration(minutes: 15);
  DateTime? _idleSince;

  /// (Re)inicia o GPS (1 s, ou 2 s na economia). Quando o GPS deve seguir
  /// com o app fora da tela ([_keepGpsInBackground]), já nasce no serviço com
  /// notificação fixa, AINDA COM O APP NA TELA: no Android 14+ o serviço de
  /// localização só pode começar com o app visível — ligado na saída do app
  /// ("inactive"), o Android recusava (SecurityException) e o grupo deixava
  /// de ver o piloto. Por isso ele também não é reiniciado ao sair.
  void _startGps() {
    _gpsSub?.cancel();
    _idleSince = null;
    final service = _keepGpsInBackground;
    _bgGps = service;
    _gpsSub = LocationService.track(
      saving: _saving,
      background: service,
      economical: false,
      notificationText: LiveSos.active.value != null
          ? tr('SOS: compartilhando sua localização em tempo real')
          : tr('Compartilhando sua localização com o comboio'),
    ).listen(_onPosition, onError: (e) => _snack('GPS: $e'));
  }

  /// O SOS em tempo real ligou/desligou: o GPS entra ou sai do serviço com a
  /// notificação fixa, ainda com o app na tela.
  void _onLiveSos() {
    if (mounted && _sim == null && !_inBackground) _startGps();
  }

  /// Desliga o GPS (e o serviço com a notificação fixa).
  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _bgGps = false;
  }

  /// Em segundo plano: desliga o GPS se o piloto está parado há muito tempo.
  void _checkIdleInBackground(Position p) {
    if (!_inBackground || LiveSos.active.value != null) {
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
    if (s) _snack(tr('🔋 Economia de bateria ligada'));
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
      // Saiu da tela: o GPS só continua se já está no serviço (comboio com
      // a opção ligada, ou Android Auto); senão, desliga.
      final left = state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden;
      if (left && !_bgGps) _stopGps();
      // De volta à tela: religa, ou troca de modo se a situação mudou.
      if (state == AppLifecycleState.resumed &&
          (_gpsSub == null || _bgGps != _keepGpsInBackground)) {
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

  bool _simSaved = false;

  void _clearSimSaved() {
    if (_simSaved) ActiveTrip.clear();
    _simSaved = false;
  }

  /// Saiu da tela: para relógios e escutas do Firestore (e guarda a viagem).
  void _pauseWork() {
    // Sem serviço em segundo plano, o Android pode fechar o app na simulação.
    final sim = _sim, trip = _trip;
    if (sim != null && trip != null && MinimizedTrip.trip.value == null) {
      _simSaved = true;
      ActiveTrip.save(trip, simAt: sim.progress.value);
    }
    MediaService.instance.stop();
    _ticker?.cancel();
    _onlineTimer?.cancel();
    _routeTrafficTimer?.cancel();
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
    _clearSimSaved();
    if (AppSettings.instance.mediaControls.value) MediaService.instance.start();
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

  /// Postos policiais rodoviários perto (pins no mapa, como os radares).
  List<Poi> _policeMarkers = [];
  BitmapDescriptor? _policeIcon;
  /// Semáforos perto do piloto (só com "Semáforos" ligado nas configurações).
  List<(double, double)> _signalMarkers = [];
  BitmapDescriptor? _signalIcon;
  ({String emoji, String text, bool Function(Position) passed, VoidCallback? onTap})? _radarBanner;

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
  final _gpsGate = GpsGate();
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

  // v2: estrada em 3D, em primeira pessoa, por cima do mapa. Pinça para
  // afastar volta ao mapa de cima; zoom bem perto no mapa volta para o 3D.
  final _sim3d = Sim3DController();
  bool _show3d = false;
  String _sim3dSig = '';
  /// v2: 3D sempre, só mapa, ou mapa que vira 3D perto de saídas/bifurcações.
  /// Começa no híbrido; depois vale sempre a escolha salva do piloto.
  _Mode3d _mode3d = _Mode3d.exits;
  /// Pinça/zoom do piloto: o modo "nas saídas" não troca sozinho por um tempo.
  DateTime _manual3dUntil = DateTime(0);
  DateTime _alerts3dAt = DateTime(0);

  /// Navegação ativa (narração, painel de manobras, recálculo). Na
  /// expedição começa desligada e o piloto toca em "Iniciar navegação".
  bool _navigating = false;
  bool _simStarted = false;

  @override
  void initState() {
    super.initState();
    LiveSos.active.addListener(_onLiveSos);
    if (AppSettings.instance.mediaControls.value) MediaService.instance.start();
    if (_isExpedition) {
      _listenExpedition();
    } else {
      _trip = widget.trip;
      if (_trip != null) _onStops(_trip!.stops);
      if (_trip != null && !widget.simulate) ActiveTrip.save(_trip!);
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
      if (widget.simStart != null) {
        sim.seek(widget.simStart!);
        _simStarted = true;
        sim.paused.value = false;
      }
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
    CarService.instance.connected.addListener(_onCarConnected);
    _voiceCmd.start();
    _radarSvc.index.addListener(_onRadarIndex);
    PoiService.instance.loaded.addListener(_onPoisLoaded);
    _radarSvc.init();
    SpeedFixService.instance.start();
    SpeedFixService.instance.fixes.addListener(_onSpeedFixes);
    _speedSvc.loadSettings();
    // "Minhas viagens": grava o caminho e as estatísticas no celular.
    _startRecording();
    // Tela: sempre ligada navegando; no resto, pela opção (Configurações → Tela).
    _applyWakelock();
    AppSettings.instance.keepScreenOn.addListener(_applyWakelock);
    SharedPreferences.getInstance().then((prefs) {
      final m = _Mode3d.values.where((x) => x.name == prefs.getString('mode3d'));
      if (m.isNotEmpty && mounted) _setMode3d(m.first, save: false);
    });
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
            leading: Icon(Icons.sos, color: Colors.red),
            title: Text(tr('Pedir ajuda ao membro mais próximo')),
            onTap: () {
              Navigator.pop(ctx);
              showClubNearbySheet(context,
                  clubId: _clubId!, purpose: ClubPurpose.help, position: _me);
            },
          ),
          ListTile(
            leading: Icon(Icons.waving_hand_outlined),
            title: Text(tr('Avisar membros que estou passando')),
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
    // Saiu do mapa por vontade própria; o Android fechar o app não passa aqui.
    if (!_isExpedition && _sim == null) ActiveTrip.clear();
    _clearSimSaved();
    LiveSos.active.removeListener(_onLiveSos);
    _onlineTimer?.cancel();
    _routeTrafficTimer?.cancel();
    CarService.instance.connected.removeListener(_onCarConnected);
    _blinkTimer?.cancel();
    MediaService.instance.stop();
    _glideTimer?.cancel();
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
    SpeedFixService.instance.fixes.removeListener(_onSpeedFixes);
    PoiService.instance.loaded.removeListener(_onPoisLoaded);
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
      ..add(_svc.activeAlerts(_code).listen(_onAlerts))
      ..add(_svc.requests(_code).listen(_onRequests))
      ..add(_svc.helps(_code).listen(_onHelps));
  }

  /// Relógios da tela: textos "há X min", chuva e trânsito (só com o app
  /// na tela; param em _pauseWork).
  void _startTimers() {
    _onlineTimer?.cancel();
    _onlineTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _checkOnline());
    _checkOnline();
    _routeTrafficTimer?.cancel();
    _routeTrafficTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _refreshRouteTraffic());
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
    // Com o motor próprio, quem chama é o trânsito da rota (_onRouteDelay).
    if (!_isExpedition && !widget.simulate && _trip != null &&
        !RouteEngineService.enabled) {
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
    if (_sim == null) LiveSos.push(p);
    // Leitura ruim com o veículo parado (local coberto): a posição anda
    // sozinha e inventa velocidade. Mantém o último lugar e mostra 0.
    if (_sim == null && _me != null &&
        !_gpsGate.accept(p.accuracy, DateTime.now())) {
      if (_speedMs != 0) setState(() => _speedMs = 0);
      return;
    }
    if (_sim == null) _checkIdleInBackground(p);
    // Mudou a situação com o app na tela (entrou no comboio, ligou o Android
    // Auto...): troca o GPS para/do serviço agora, enquanto o Android deixa.
    if (_sim == null && !_inBackground && _bgGps != _keepGpsInBackground) {
      Future.microtask(() {
        if (mounted && !_inBackground) _startGps();
      });
    }
    // Minimizado / tela apagada: guarda a posição sem redesenhar a tela
    // (a voz, os avisos e a gravação continuam).
    // Posição na rota: calculada uma vez por leitura e usada pela voz,
    // radares, limite da via e avisos à frente.
    _proj = _walker?.project(p.latitude, p.longitude,
        around: (_proj?.offset ?? 1e9) < 200 ? _proj!.along : null,
        heading: _sim == null && p.speed > 3 && p.heading >= 0 ? p.heading : null);
    if (_inBackground) {
      _me = p;
    } else {
      setState(() => _me = p);
      _lead = _leadMeters(p);
      _glideMeTo(_shownPoint(p));
    }
    _updateSpeed(p);
    _checkPois(p);
    _checkHalfway();
    if (!_inBackground) _updateCamera(p);
    if (!_inBackground) _autoExit3d(p);
    // A cena 3D também alimenta o carro, mesmo com o celular apagado.
    if (!_inBackground || CarService.instance.connected.value) _feed3d();
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
        .listen((list) {
      setState(() => _hazards = list);
      _sendHazardsToCar();
    });
  }

  /// Alertas da comunidade à frente: avisa (voz/tela) e mostra a faixa com
  /// os botões "ainda está lá / não está mais".
  void _checkHazardProximity(Position p) {
    final shown = _shownHazard;
    if (shown != null && !_shownManually) {
      final d = Geolocator.distanceBetween(
          p.latitude, p.longitude, shown.lat, shown.lng);
      // Já passou do ponto: fecha o aviso (logo depois, a 30 m).
      final behind = d > 30 && !_isAhead(p, shown);
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
        _ => h.type.alertPlan(moto: _myBike.style.isMoto),
      };
      final thresholds = alertThresholds(range, repeats);
      final done = _announced[h.id] ?? 0;
      if (done >= thresholds.length) continue;
      final d =
          Geolocator.distanceBetween(p.latitude, p.longitude, h.lat, h.lng);
      if (d > range || !_isAhead(p, h) || !_sameSide(p, h)) continue;
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

  /// Postos/semáforos de um estado acabaram de carregar: redesenha já
  /// (sem esperar o piloto andar 200 m).
  void _onPoisLoaded() {
    _radarMarkersAt = null;
    final p = _me;
    if (p != null) _updateRadarsAround(p);
  }

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
    _policeIcon = await emojiMarker('🚔', Colors.blue.shade800);
    _signalIcon = await emojiMarker('🚦', Colors.green.shade700);
    if (mounted) setState(() {});
  }

  /// Correção nova (radar corrigido ou "não existe"): refaz os radares em
  /// volta na hora, sem esperar andar até outra região.
  void _onSpeedFixes() {
    _radarCell = null;
    _radarMarkersAt = null;
    if (_me case final p?) _updateRadarsAround(p);
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
    setState(() {
      _radarMarkers = [
        for (final (r, d) in withDist.take(80))
          if (d <= 10000) r
      ];
      _policeMarkers = [
        for (final q in PoiService.instance.near(p.latitude, p.longitude, 10000))
          if (q.kind == PoiKind.policePost) q
      ].take(30).toList();
      _signalMarkers = PoiService.instance
          .signalsNear(p.latitude, p.longitude, 1500)
          .take(60)
          .toList();
    });
    _sendPoisToCar();
  }

  /// Radares à frente: na pista e no sentido do piloto, nas distâncias
  /// configuradas, sempre falando a velocidade; e trechos da PRF.
  // ---- Pílula do radar ao lado do velocímetro ("📸 80 em 450 m"), como a
  // da velocidade reduzida: conta a distância até passar pelo radar.
  FixedRadar? _activeRadar;
  int? _activeRadarKmh;
  double? _activeRadarLast; // última distância (sem rota: detectar que passou)
  ({String emoji, int? kmh, int m})? _radarPill;

  /// Radar a que a faixa amarela se refere (mesmo emoji): a distância vai
  /// na faixa.
  ({String emoji, int? kmh, int m})? get _bannerRadar {
    final b = _radarBanner, r = _radarPill;
    return b != null && r != null && b.emoji == r.emoji ? r : null;
  }

  /// Faixa piscando (acima do limite do radar): fase vermelha agora?
  bool _bannerBlinkRed = false;
  Timer? _blinkTimer;

  /// Liga/desliga o pisca da faixa conforme a velocidade e o radar.
  void _updateBannerBlink() {
    final r = _bannerRadar;
    final over = r != null && r.kmh != null && r.m <= 1000 && _speedMs * 3.6 > r.kmh! + 2;
    if (over) {
      _blinkTimer ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() => _bannerBlinkRed = !_bannerBlinkRed);
      });
    } else if (_blinkTimer != null) {
      _blinkTimer!.cancel();
      _blinkTimer = null;
      if (_bannerBlinkRed) setState(() => _bannerBlinkRed = false);
    }
  }

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
      _updateBannerBlink();
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
    _updateBannerBlink();
  }

  /// O radar está na mesma via da rota? Vale para a rota inteira (guardado),
  /// porque cruzar as vias do pacote a cada leitura do GPS pesaria.
  bool _radarOnRouteRoad(FixedRadar r, RouteWalker w) {
    if (!identical(_radarRoadsOf, w)) {
      _radarRoadsOf = w;
      _radarRoads.clear();
    }
    return _radarRoads[r.id] ??= radarOnRouteRoad(
      ViasService.instance.roadsAt(r.lat, r.lng),
      (lat, lng) => w.project(lat, lng).offset,
    );
  }

  RouteWalker? _radarRoadsOf;
  final _radarRoads = <int, bool>{};

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
    if (onRoute) ViasService.instance.ensure(p.latitude, p.longitude);

    // Distância do 1º aviso e quantas vezes avisar (Configurações). Radar de
    // avanço de sinal fica em cruzamento: uma vez só, a no máximo 300 m.
    final prefs = AppSettings.instance.alerts.value;
    for (final r in _radarsAround) {
      if (r.unverified) continue;
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
        if (d != null && !_radarOnRouteRoad(r, w)) d = null;
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
          : (_speedSvc.lookup(r.lat, r.lng, _bearing, _speedMs)?.kmh ??
              // Rodovia com poucos pontos de limite perto do radar: o limite
              // da via em que o piloto está (o radar está à frente nela).
              _roadLimit?.kmh);
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
            RadarKind.fixed => tr('Radar fixo'),
            RadarKind.section => tr('Radar de velocidade média'),
            RadarKind.redLight => tr('Radar de avanço de sinal'),
          },
          kmh != null && kmh > 0 ? tr('limite {0} km/h', [kmh]) : tr('limite não informado'),
        ].join(' · '),
        speech: radarSpeech(r, d, roadLimit: roadKmh),
        // Some logo depois de passar pelo radar (antes: só ~200 m depois do
        // alcance do aviso, ex.: 950 m).
        passed: (q) => _passedPoint(q, r.lat, r.lng) ||
            distanceMeters(q.latitude, q.longitude, r.lat, r.lng) >
                range + 200,
        onTap: () => _editRadar(r, kmh),
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
        text: tr('Trecho com radar portátil da PRF · BR-{0} km {1}–{2}', [s.br, s.kmFrom.round(), s.kmTo.round()]),
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
    VoidCallback? onTap, // tocar/segurar a faixa: confirmar/corrigir
  }) {
    HapticFeedback.heavyImpact();
    if (speak && _voice.alertsOn.value) {
      _voice.alert(speech);
    } else {
      SystemSound.play(SystemSoundType.alert);
    }
    setState(
        () => _radarBanner = (emoji: emoji, text: text, passed: passed, onTap: onTap));
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
      // Lombada: bem junto do caminho (a outra pista fica a mais de 8 m) e,
      // em pista de mão única, só no sentido dela.
      if (!_onMyWay(p, poi.lat, poi.lng, side: bump ? 8 : 60)) continue;
      if (bump && !sameDirection(poi.heading, _bearing, _speedMs)) continue;
      final next = nextAlert(d, done, thresholds);
      if (next == null) continue;
      _poiSpoken[poi.id] = next;
      final plaza = toll && _tollTable != null
          ? _routePlazaNear(poi.lat, poi.lng) ??
              nearestPlaza(_tollTable!, poi.lat, poi.lng)
          : null;
      // Valor estimado (a confirmar): guarda para conferir na chegada; na
      // simulação, já oferece conferir agora.
      if (plaza != null && plaza.editable && !_tollsSeen.containsKey(plaza.key)) {
        _tollsSeen[plaza.key] = plaza;
        if (_sim != null) _offerTollCheck(plaza);
      }
      // Pedágio: quanto o veículo paga, pela tabela (ANTT por praça); moto
      // sem informação = "não informado" (nunca afirma que paga).
      final tollNote = !toll
          ? ''
          : tollPlazaNote(
              plaza,
              _myBike,
              formatMoney,
              osmMotoFree: poi.kind == PoiKind.tollMotoFree);
      final speech = bump
          ? tr('Lombada a {0}', [spokenDistance(d)])
          : toll
              ? tr('Praça de pedágio a {0}{1}', [spokenDistance(d), tollNote.isEmpty ? '' : '. $tollNote'])
              : tr('Posto policial a {0}', [spokenDistance(d)]);
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
            ? tr('Lombada à frente')
            : toll
                ? tr('Pedágio à frente{0}', [tollNote.isEmpty ? '' : ' · $tollNote'])
                : tr('Posto policial à frente'),
        speech: speech,
        speak: !bump || prefs.bumps == AlertMode.voice,
        passed: (q) =>
            _passedPoint(q, poi.lat, poi.lng) ||
            (distanceMeters(q.latitude, q.longitude, poi.lat, poi.lng) > 150 &&
                !_onMyWay(q, poi.lat, poi.lng, side: 200)),
      );
      return; // um aviso por vez
    }
  }

  /// A praça da rota (a mesma usada no custo do planejamento) mais perto
  /// do ponto: evita pegar a praça do outro sentido ou a vizinha (o aviso
  /// dizia R$ 10,20 e o planejamento R$ 8,80).
  TollPlaza? _routePlazaNear(double lat, double lng) {
    final list = _tollEst?.list ?? const <TollPlaza>[];
    TollPlaza? best;
    var bestD = 1500.0;
    for (final p in list) {
      for (final (a, b) in p.pts) {
        final d = distanceMeters(lat, lng, a, b);
        if (d < bestD) {
          bestD = d;
          best = p;
        }
      }
    }
    return best;
  }

  /// Praças com valor a confirmar por onde o piloto passou nesta viagem.
  final _tollsSeen = <String, TollPlaza>{};

  /// Simulação: "Pedágio: carro R\$ X · moto R\$ Y. Está certo?" → conferir.
  void _offerTollCheck(TollPlaza p) {
    final money = p.car == null ? tr('Valor não informado') : tr('carro {0}', [formatMoney(p.car!)]);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: Text(tr('🛣️ Pedágio: {0}. O valor está certo?', [money])),
      action: SnackBarAction(
        label: tr('Conferir'),
        onPressed: () => TollConfirmSheet.show(context, [p]),
      ),
    ));
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
    _voice.alert(tr('Você chegou à metade do trajeto. Faltam {0}', [left]));
    _showTrafficBanner(tr('🏁 Metade do trajeto! Faltam {0}', [left]));
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
          tr('🌧️ {0} a ~{1} km à frente', [rainWord(levels[i]), dists[i] ~/ 1000]));
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
            title: Text(tr('Voz'), style: Theme.of(ctx).textTheme.titleLarge),
            subtitle: Text(
                tr('Sai pelo alto-falante ou pelo intercomunicador Bluetooth. A música abaixa enquanto o app fala.')),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _voice.alertsOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.campaign),
              title: Text(tr('Avisos falados')),
              subtitle: Text(
                  tr('Radares (a 1 km), perigos na pista, SOS do grupo e paradas do roteiro')),
              value: on,
              onChanged: _voice.setAlerts,
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _voice.narrationOn,
            builder: (_, on, __) => SwitchListTile(
              secondary: const Icon(Icons.turn_right),
              title: Text(tr('Narração do trajeto')),
              subtitle: Text(_nav == null
                  ? tr('Sem rota com instruções. {0}', [_isLeader ? tr('Abra o Roteiro e recalcule a rota.') : tr('Peça ao líder para montar o roteiro.')])
                  : tr('Curva a curva, como no GPS: "Em 300 metros, vire à direita"')),
              value: on,
              onChanged: (v) {
                _voice.setNarration(v);
                _navSynced = false;
                if (v && _nav == null) {
                  _snack(tr('O roteiro ainda não tem as instruções de navegação'));
                }
              },
            ),
          ),
          ListTile(
            leading: Icon(Icons.record_voice_over),
            title: Text(tr('Testar voz')),
            onTap: () => _voice.test(hazardSpeech(tr('radar móvel'), 1000)),
          ),
          ListTile(
            leading: Icon(Icons.settings),
            title: Text(tr('Mais configurações')),
            subtitle: Text(tr('Tela sempre ligada, preferências de rota')),
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
                  ? tr('Base de radares ainda não baixada')
                  : tr('{0} radares fixos · {1} trechos da PRF{2}', [idx.radarCount, idx.stretchCount, idx.prfLabel.isEmpty ? '' : ' (${idx.prfLabel.toLowerCase()})'])),
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
  /// Já passou pelo ponto: ficou para trás (mais de 100° da direção) e a
  /// mais de 30 m.
  bool _passedPoint(Position p, double lat, double lng) {
    if (distanceMeters(p.latitude, p.longitude, lat, lng) <= 30) return false;
    if (_speedMs < 2) return false;
    final a = signedAngle(
        _bearing, bearingBetween(p.latitude, p.longitude, lat, lng));
    return a.abs() > 100;
  }

  /// Alerta de um sentido só (radar, polícia...): vale para quem anda no
  /// mesmo sentido de quem marcou (o do outro lado da pista não é avisado).
  bool _sameSide(Position p, Hazard h) =>
      !h.type.directional || sameDirection(h.heading, _bearing, p.speed);

  /// Sentido para gravar no alerta: só andando (parado o rumo não vale).
  double? get _reportHeading => _speedMs > 2 ? _bearing : null;

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
        tr('Para reportar alertas para todos, entre com sua conta. Isso evita alertas falsos e protege a comunidade.'))) {
      return;
    }
    if (!mounted) return;
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('O que tem na pista?'),
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
                      // Letra grande no celular: o desenho encolhe e o nome
                      // cabe em 2 linhas (antes cortava "Perigo na pista").
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(t.emoji,
                                    style: const TextStyle(fontSize: 36)),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(t.label,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, height: 1.1)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr('O alerta é marcado na sua posição atual e aparece para todos os usuários do app.'),
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
        tr('Para avisar radares para todos, entre com sua conta. Isso evita alertas falsos e protege a comunidade.'))) {
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
      // Se já existe o mesmo alerta a menos de 150 m (no mesmo sentido), só
      // confirma; o do outro lado da pista é outro alerta.
      for (final h in _activeHazards) {
        if (h.type != t || !_sameSide(p, h)) continue;
        final d =
            Geolocator.distanceBetween(p.latitude, p.longitude, h.lat, h.lng);
        if (d < 150) {
          if (h.createdBy != widget.uid && _voted.add(h.id)) {
            _hazardSvc.confirm(h);
          }
          _snack(tr('{0} Esse alerta já existia aqui. Confirmado!', [t.emoji]));
          _voice.alert(tr('Alerta de {0} confirmado. Obrigado!', [t.spoken]));
          return;
        }
      }
      // Confirma só quando o servidor gravar; sem internet, fica na fila.
      var sent = false;
      // Fala na hora (mesmo sem internet o alerta fica na fila).
      _voice.alert(tr('Alerta de {0} enviado. Obrigado por avisar a comunidade!', [t.spoken]));
      _hazardSvc.report(t, p.latitude, p.longitude, widget.uid,
          heading: _reportHeading).then((_) {
        sent = true;
        debugPrint('Alerta gravado: ${t.name}');
        _snack(tr('{0} {1} enviado para todos. Obrigado!', [t.emoji, t.label]));
      }, onError: (e) {
        sent = true;
        // O servidor recusou: a voz já disse "enviado", então desmente.
        final u = FirebaseAuth.instance.currentUser;
        debugPrint('Alerta recusado: $e | provedor=${u?.providerData.map((x) => x.providerId).toList()} '
            'anonimo=${u?.isAnonymous} mesmoUid=${u?.uid == widget.uid}');
        _snack(tr('Não foi possível enviar o alerta: {0}', [e]));
        _voice.alert(tr('O alerta não foi enviado.'));
        CarService.instance.toast(tr('O alerta não foi enviado.'));
      });
      Future.delayed(const Duration(seconds: 6), () {
        if (!sent && mounted) {
          debugPrint('Alerta sem resposta do servidor: ${t.name}');
          _snack(tr('{0} {1} salvo. Será enviado quando houver internet.', [t.emoji, t.label]));
        }
      });
    } catch (e) {
      _snack(tr('Não foi possível obter sua posição: {0}', [e]));
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
    _snack(tr('Obrigado por ajudar a comunidade!'));
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
          _voice.reply(tr('Na simulação os alertas não são enviados.'));
        } else if (AuthService.isAnonymous) {
          _voice.reply(tr('Para marcar alertas, entre com sua conta no app.'));
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
      case GroupRequestCommand(:final request):
        if (!_isExpedition) {
          _voice.reply(tr('Os pedidos ao grupo funcionam dentro da expedição.'));
        } else {
          await _sendGroupRequest(request);
        }
      case CancelStopCommand():
        final s = _nextSoloStop;
        if (_isExpedition) {
          _voice.reply(tr('Na expedição, as paradas são do líder ou do capitão.'));
        } else if (s == null) {
          _voice.reply(tr('Não há parada no caminho para cancelar.'));
        } else {
          _pendingCancelStop = s;
          _voice.reply(tr('Cancelar a parada {0}? Diga sim ou não.', [s.name]));
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
          _voice.reply(tr('Não encontrei um alerta seu para cancelar.'));
        } else {
          _hazardSvc.dismiss(mine, force: true);
          _lastVoiceReport = null;
          _voice.reply(tr('Alerta de {0} cancelado.', [mine.type.spoken]));
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
        // "Cancelar a parada X?" (UauGo, cancelar parada).
        final cancel = _pendingCancelStop;
        if (cancel != null) {
          _pendingCancelStop = null;
          if (yes) {
            await _removeSoloStop(cancel);
          } else {
            _voice.reply(tr('Parada mantida.'));
          }
          return;
        }
        // Capitão/líder confirmando um pedido do grupo ("sim" = OK 👍).
        final ack = _pendingAck;
        if (ack != null && yes) {
          await _ackRequest(ack);
          _voice.reply(tr('Confirmado para {0}.', [ack.name]));
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
        _voice.reply(yes ? tr('Confirmado. Obrigado!') : tr('Certo, vou avisar que não está mais. Obrigado!'));
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
          h.permanent || // já validado (3 confirmações, Gold ou administrador)
          _voted.contains(h.id) ||
          _askedHazards.contains(h.id) ||
          !_sameSide(p, h)) {
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
        _voice.alert(tr('Você passou pelo alerta de {0}. {1}', [h.type.spoken, _voiceCmd.enabled.value ? tr('Ainda está lá? Diga sim ou não.') : tr('Ainda está lá? Responda na tela.')]));
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
              child: Text(tr('{0} ainda está lá?', [h.type.label]),
                  style: white.copyWith(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: tr('Não sei'),
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
              big(tr('👍 Sim'), true, Colors.green.shade700),
              const SizedBox(width: 8),
              big(tr('👎 Não está'), false, Colors.red.shade700),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Faixa de um alerta da comunidade com a distância e os botões de voto.
  Widget _hazardBanner(Hazard h) {
    // Faixa amarela com letra preta (antes: a cor do tipo, ex. polícia azul).
    const white = TextStyle(color: Colors.black);
    final mine = h.createdBy == widget.uid;
    final canVote = !mine && !_voted.contains(h.id);
    final dist = _dist(h.lat, h.lng).replaceFirst(' · ', '');
    return Material(
      color: Colors.amber,
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
                    child: Text(tr('👍 Ainda está lá')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => _voteHazard(h, false),
                    child: Text(tr('👎 Não está mais')),
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
                child: Text(tr('REMOVER MEU ALERTA'), style: white),
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
        : _navigating && (_voice.narrationOn.value || _helpTarget != null);
    if (!on || nav == null) return;
    void say(String t) => _voice.narrate(t, force: sim != null);
    if (!_navSynced) {
      // Pela rota quando dá (em linha reta pulava a saída perto do fim).
      final pr = _proj;
      if (nav.hasRoute && pr != null && pr.offset < 250) {
        nav.syncAlong(pr.along);
      } else {
        nav.syncTo(p.latitude, p.longitude);
      }
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
        // Parado (saída demorada, estacionamento, GPS solto dentro de casa):
        // não recalcula a cada leitura; só conta fora da rota andando.
        if (_speedMs < 3) return;
        _offRouteCount++;
        if (_offRouteCount >= 3 && _helpTarget != null) {
          // Indo até um colega: refaz a rota dele, nunca a do grupo.
          _retraceHelp(p);
        } else if (_offRouteCount >= 3 && !_isExpedition && _trip != null) {
          // Navegando sozinho: recalcula como o Waze.
          _reroute(p);
        } else if (_offRouteCount >= 3 && _isExpedition && _stops.length >= 2) {
          // Expedição: capitão recalcula para todos; os outros, só para si.
          _expeditionOffRoute(p);
        } else if (_offRouteCount == 3 && !_offRoute) {
          _offRoute = true;
          say(tr('Você saiu da rota planejada'));
        }
        return;
      }
      _offRouteCount = 0;
      _checkBackOnExpeditionRoute(p);
      if (_offRoute && d < 40) {
        _offRoute = false;
        nav.syncTo(p.latitude, p.longitude);
        say(tr('Você voltou para a rota'));
      }
    }
    // Na simulação acelerada a moto "pula" muitos metros por leitura: as
    // janelas de aviso crescem nesse tanto (a velocidade continua a real).
    final jump = sim != null ? p.speed * sim.multiplier.value : 0.0;
    String? speech;
    if (w != null && proj != null) {
      // Pela rota: avanço e distâncias medidos na estrada.
      if (!nav.hasRoute) {
        // Em ordem: a saída da rotatória não cai na entrada, que fica ao lado.
        var prev = 0.0;
        nav.attachRoute((la, lo) => prev = w.project(la, lo, after: prev).along);
      }
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
    // Sem internet da última vez: não repete "Recalculando" a cada tentativa.
    if (!_rerouteOffline) _voice.narrate(tr('Recalculando a rota'));
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
      // Sem internet: avisa uma vez, segue com a rota que já está no celular
      // e tenta de novo a cada 20 s (antes: tentava a cada leitura do GPS).
      if (!_rerouteOffline) {
        _voice.alert(tr('Sem internet: volte para a rota. Recalculo quando a conexão voltar.'));
        _showTrafficBanner(tr('📵 Sem internet: siga para a rota azul'));
      }
      _rerouteOffline = true;
      _lastReroute = DateTime.now().add(const Duration(seconds: 10));
      return;
    }
    _rerouteOffline = false;
    _applyTrip(nt);
  }

  /// O último recálculo falhou (sem internet).
  bool _rerouteOffline = false;

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
    ActiveTrip.save(nt);
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
      _voice.alert(tr('Rota mais rápida encontrada: economia de {0} minutos', [mins]));
      _showTrafficBanner(tr('🚀 Rota mais rápida: economia de {0} min', [mins]));
      _applyTrip(nt);
      return;
    }
    // Mesma rota: atualiza a previsão de chegada com o trânsito de agora.
    if (nt.durationS > 0) _etaSpeed = nt.distanceM / nt.durationS;
    _sayDelay(nt.trafficDelayS, nt.typicalS ?? nt.durationS);
  }

  /// Avisa trânsito intenso; retorna true se o atraso é grande.
  bool _sayDelay(int delay, int base) {
    if (delay < 300 || delay <= 0.15 * base) return false;
    final mins = (delay / 60).round();
    final now = DateTime.now();
    if (now.difference(_lastDelayAlert) > const Duration(minutes: 15) ||
        mins >= _lastDelayMin + 5) {
      _lastDelayAlert = now;
      _lastDelayMin = mins;
      _voice.alert(tr('Trânsito intenso na rota: mais {0} minutos', [mins]));
      _showTrafficBanner(tr('🚗 Trânsito intenso na rota: +{0} min', [mins]));
    }
    return true;
  }

  DateTime _lastGoogleRoute = DateTime.fromMillisecondsSinceEpoch(0);

  /// Motor próprio: o tempo do Google corrige a chegada. Com atraso grande e
  /// sozinho, pede ao Google uma rota melhor (no máximo a cada 15 min).
  Future<void> _onRouteDelay(double meters, int durationS, int staticS) async {
    if (durationS <= 0 || staticS <= 0) return;
    _etaSpeed = meters / durationS;
    if (!_sayDelay(durationS - staticS, staticS) || _isExpedition) return;
    final now = DateTime.now();
    if (now.difference(_lastGoogleRoute) < const Duration(minutes: 15)) return;
    _lastGoogleRoute = now;
    DirectionsService.skipEngine = true;
    try {
      await _checkTraffic();
    } finally {
      DirectionsService.skipEngine = false;
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
      if (pts.length >= 2) {
        var dist = 0;
        for (final s in _stops) {
          dist += s.legDistanceM;
        }
        _calcRouteCost(pts, dist);
      }
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
    // Rota normal: custo estimado (na expedição, calculado acima).
    final t = _trip;
    if (!_isExpedition && t != null && _routeRecs.length >= 2) {
      _calcRouteCost(_routeRecs, t.distanceM);
    }
    _walker = _routeRecs.length >= 2 ? RouteWalker(_routeRecs) : null;
    // Rota nova: o trânsito da antiga não vale mais.
    _setTrafficRuns(const []);
    _trafficAt = DateTime.fromMillisecondsSinceEpoch(0);
    Future.delayed(const Duration(seconds: 3), _refreshRouteTraffic);
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
    if (_isCaptain && !_backFromHelp) {
      _voice.narrate(tr('Recalculando a rota da expedição'));
      final ok = await _svc.rerouteFromCaptain(_code, exp.plan, p.latitude,
          p.longitude, remaining, _stops.sublist(1, next));
      if (!mounted) return;
      setState(() => _rerouting = false);
      if (!ok) _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _voice.narrate(tr('Você saiu da rota da expedição. Recalculando para você voltar.'));
    final nt = await TripService.build(
      title: exp.name,
      points: [
        TripPoint(tr('Sua posição'), p.latitude, p.longitude, type: StopType.meet),
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
    // Indo até um colega: a rota própria vale até chegar nele.
    final help = _helpTarget;
    if (help != null) {
      final (lat, lng) = _helpPosition(help);
      if (distanceMeters(p.latitude, p.longitude, lat, lng) < 80) {
        _endHelp();
        _voice.alert(tr('Você chegou até {0}. Ao seguir, volto para a rota da expedição.', [help.name]));
      } else if (distanceMeters(lat, lng, help.lat, help.lng) > 300) {
        // O colega andou: a rota acompanha.
        _retraceHelp(p);
      }
      return;
    }
    final w = _expWalker;
    if (w == null || (_personalTrip == null && !_backFromHelp)) return;
    final off = w.project(p.latitude, p.longitude).offset;
    _backOnExpRoute = off < 40 ? _backOnExpRoute + 1 : 0;
    if (_backOnExpRoute < 3) return;
    _backFromHelp = false;
    if (_personalTrip == null) return;
    _personalTrip = null;
    _routeSig = '';
    _navSig = '';
    _onStops(_stops);
    _voice.narrate(tr('Você voltou para a rota da expedição'));
  }

  /// Colega que o piloto está indo buscar (SOS ou fora da rota). Com [uid],
  /// a rota acompanha a posição dele.
  ({String name, String? uid, double lat, double lng})? _helpTarget;

  /// Foi até um colega e ainda não voltou ao trajeto do grupo: o desvio é
  /// só dele, mesmo sendo o capitão (não muda a rota de todos).
  bool _backFromHelp = false;

  /// Onde o colega está agora (sem posição nova, onde a rota foi traçada).
  (double, double) _helpPosition(
      ({String name, String? uid, double lat, double lng}) t) {
    final m = _members.where((m) => m.uid == t.uid).firstOrNull;
    return m != null && m.hasLocation ? (m.lat!, m.lng!) : (t.lat, t.lng);
  }

  Future<Trip?> _helpTrip(String name, Position p, double lat, double lng) =>
      TripService.build(
        title: tr('Ajuda: {0}', [name]),
        points: [
          TripPoint(tr('Sua posição'), p.latitude, p.longitude, type: StopType.meet),
          TripPoint(name, lat, lng, type: StopType.destination),
        ],
      );

  void _useHelpTrip(Trip nt) {
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

  /// Refaz a rota até o colega (saiu dela ou ele andou), a cada 20 s no
  /// máximo. Sem internet, segue com a rota que já está no celular.
  Future<void> _retraceHelp(Position p) async {
    final t = _helpTarget;
    if (t == null || _rerouting) return;
    if (DateTime.now().difference(_lastReroute) < const Duration(seconds: 20)) return;
    _lastReroute = DateTime.now();
    final (lat, lng) = _helpPosition(t);
    setState(() => _rerouting = true);
    final nt = await _helpTrip(t.name, p, lat, lng);
    if (!mounted) return;
    setState(() => _rerouting = false);
    if (nt == null || _helpTarget != t) return;
    _helpTarget = (name: t.name, uid: t.uid, lat: lat, lng: lng);
    _useHelpTrip(nt);
  }

  /// Fim da rota até o colega (chegou ou desistiu): volta para a do grupo.
  void _endHelp() {
    _helpTarget = null;
    _personalTrip = null;
    _backFromHelp = true;
    _routeSig = '';
    _navSig = '';
    _onStops(_stops);
  }

  /// Rota temporária, dentro do UauGo, até o colega ("Ir até lá" no SOS ou
  /// segurar um piloto). Ao chegar, volta para a rota do grupo.
  Future<void> _goHelp(String name, double lat, double lng, {String? uid}) async {
    final p = _me;
    if (p == null) {
      _snack(tr('Ainda sem a sua posição pelo GPS'));
      return;
    }
    setState(() => _rerouting = true);
    final nt = await _helpTrip(name, p, lat, lng);
    if (!mounted) return;
    setState(() => _rerouting = false);
    if (nt == null) {
      _snack(tr('Não foi possível traçar a rota até {0}. Confira a internet.', [name]));
      return;
    }
    _helpTarget = (name: name, uid: uid, lat: lat, lng: lng);
    _useHelpTrip(nt);
    if (!_navigating) _startNavigation();
    _voice.alert(tr('Rota até {0}. {1}.', [name, formatDistance(nt.distanceM)]));
    if (_isExpedition && !_isCaptain) {
      _svc.sendHelping(_code, widget.uid, widget.userName, name, p.latitude, p.longitude);
    }
  }

  final Set<String> _seenHelps = {};
  bool _helpsLoaded = false;

  /// Capitão: alguém saiu para buscar um colega (voz, faixa e carro).
  void _onHelps(List<HelpingItem> list) {
    final fresh = list.where((h) => !_seenHelps.contains(h.id)).toList();
    _seenHelps.addAll(list.map((h) => h.id));
    if (!_helpsLoaded) {
      _helpsLoaded = true;
      return;
    }
    if (!_isCaptain) return;
    for (final h in fresh.reversed) {
      if (h.uid == widget.uid) continue;
      final text = tr('{0} está indo até {1}', [h.name, h.target]);
      _voice.alert(text);
      _showTrafficBanner('🧭 $text');
      _noteToCar('🧭 $text');
    }
  }

  /// Trocou o capitão: avisa todo mundo (e por voz quem virou capitão).
  void _onCaptainChanged(String uid) {
    if (uid == widget.uid) {
      _voice.narrate(tr('Agora você é o capitão da expedição'));
      _snack(tr('Agora você é o capitão: o seu desvio recalcula a rota de todos.'));
      return;
    }
    final name = _members.where((m) => m.uid == uid).firstOrNull?.name ?? tr('Outro piloto');
    _snack(tr('{0} agora é o capitão da expedição.', [name]));
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
              title: Text(tr('Ver no mapa')),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
          ListTile(
            leading: Icon(Icons.flag),
            title: Text(tr('Passar a capitania')),
            subtitle: Text(tr('O desvio dele passa a recalcular a rota de todos')),
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
        title: Text(tr('Passar a capitania para {0}?', [m.name])),
        content: Text(tr('Você deixa de ser o capitão. O desvio do novo capitão é que passa a recalcular a rota de todos.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Passar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.setRoles(_code, m.uid, [...exp.sweepers]..remove(m.uid));
    } catch (e) {
      _snack(tr('Não foi possível salvar: {0}', [e]));
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
              title: Text(tr('Ver no mapa')),
              onTap: () => Navigator.pop(ctx, 'map'),
            ),
          ListTile(
            leading: Icon(Icons.flag),
            title: Text(tr('Tornar capitão')),
            subtitle: Text(tr('Puxa o comboio: só o desvio dele recalcula a rota de todos')),
            enabled: exp.captainId != m.uid,
            onTap: () => Navigator.pop(ctx, 'captain'),
          ),
          ListTile(
            leading: Icon(Icons.shield_moon),
            title: Text(sweeper ? tr('Deixar de ser ferrolho') : tr('Tornar ferrolho')),
            subtitle: Text(sweeper
                ? tr('Volta a ser membro')
                : tr('Fecha o comboio (até {0})', [Expedition.maxSweepers])),
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
      _snack(tr('Não foi possível salvar: {0}', [e]));
    }
  }

  /// Papel do piloto, para mostrar na lista ("Capitão", "Ferrolho").
  String? _roleOf(String uid) {
    final exp = _exp;
    if (exp == null) return null;
    if (exp.captainId == uid) return tr('Capitão');
    if (exp.sweepers.contains(uid)) return tr('Ferrolho');
    return null;
  }

  /// Grade com os apelidos (capitão/ferrolhos): ⚠️ em quem saiu do trajeto;
  /// tocar mostra o piloto no mapa.
  Widget _groupGridPanel() {
    // Quem saiu do trajeto primeiro (o capitão vê na hora), depois quem está
    // sem sinal por último; no empate, pelo nome.
    int rank(Member m) => _memberOffRoute(m) ? 0 : (m.isStale ? 2 : 1);
    final others = [
      for (final m in _members)
        if (m.uid != widget.uid) m
    ]..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.name.compareTo(b.name);
      });
    // Muitos pilotos (ex.: 20 motos): duas colunas, menos rolagem.
    final twoCols = others.length > 8;
    final itemW = twoCols ? 128.0 : 178.0;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh.withAlpha(235),
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: twoCols ? 270 : 190,
            maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(6),
          child: Wrap(children: [
          for (final m in others)
            SizedBox(width: itemW, child: InkWell(
              onTap: m.hasLocation
                  ? () {
                      setState(() => _follow = false);
                      _focus(m.lat!, m.lng!);
                    }
                  : null,
              onLongPress: () => _askRouteToMember(m),
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
            )),
        ]),
        ),
      ),
    );
  }

  /// Segurou um piloto (capitão, ferrolho ou líder): oferece ir até ele,
  /// para buscar quem saiu da rota. O capitão vai pelo Google Maps; os outros,
  /// por uma rota só deles no UauGo (a do grupo não muda).
  Future<void> _askRouteToMember(Member m) async {
    if (!_watchesGroup || m.uid == widget.uid || !m.hasLocation) return;
    HapticFeedback.mediumImpact();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Traçar rota até {0}?', [m.name])),
        content: Text(m.isStale
            ? tr('Sem sinal agora: a rota vai até a última posição recebida.')
            : tr('A rota vai até a posição atual do piloto.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Traçar rota'))),
        ],
      ),
    );
    if (go != true) return;
    if (_isCaptain) {
      await _navigate(m.lat!, m.lng!);
    } else {
      await _goHelp(m.name, m.lat!, m.lng!, uid: m.uid);
    }
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
    _sendGroupToCar();
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

  // ------------------------------------------------------------ pedidos ao grupo

  /// Pedidos já vistos e OKs já avisados (o 1º lote, ao entrar, é calado).
  final Set<String> _seenRequests = {};
  final Set<String> _seenAcks = {};
  bool _requestsLoaded = false;

  /// Pedido esperando o OK do capitão/líder (o "sim" falado confirma).
  GroupRequestItem? _pendingAck;

  /// Capitão ou líder: quem confirma os pedidos.
  bool get _canAck => _isCaptain || _isLeader;

  /// Pedidos do grupo: novos (fala e mostra) e OKs do capitão.
  void _onRequests(List<GroupRequestItem> list) {
    final fresh = list.where((r) => !_seenRequests.contains(r.id)).toList();
    final acked = list
        .where((r) => r.ackName != null && !_seenAcks.contains(r.id))
        .toList();
    _seenRequests.addAll(list.map((r) => r.id));
    _seenAcks.addAll(acked.map((r) => r.id));
    if (!_requestsLoaded) {
      _requestsLoaded = true;
      return;
    }
    for (final r in fresh.reversed) {
      if (r.uid == widget.uid) continue;
      final text = groupRequestSpeech(r.name, r.kind);
      if (_canAck && r.ackName == null) {
        // Capitão/líder: pede o OK (toque ou "sim").
        _pendingAck = r;
        _voice.alert(tr('{0}. Diga sim para confirmar.', [text]));
        _sendGroupToCar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 30),
          content: Text('${r.kind.emoji} $text'),
          action: SnackBarAction(label: tr('OK 👍'), onPressed: () => _ackRequest(r)),
        ));
      } else {
        _voice.alert(text);
        _showTrafficBanner('${r.kind.emoji} $text');
        _noteToCar('${r.kind.emoji} $text');
      }
    }
    for (final r in acked) {
      if (_pendingAck?.id == r.id) _pendingAck = null;
      if (r.uid == widget.uid) {
        _voice.alert(tr('{0} viu seu pedido.', [r.ackName]));
        _showTrafficBanner(tr('👍 {0} viu seu pedido: {1}', [r.ackName, r.kind.label]));
        _noteToCar(tr('👍 {0} viu seu pedido: {1}', [r.ackName, r.kind.label]));
      } else if (!_canAck) {
        _showTrafficBanner(tr('👍 {0} confirmou o pedido de {1}', [r.ackName, r.name]));
        _noteToCar(tr('👍 {0} confirmou o pedido de {1}', [r.ackName, r.name]));
      }
    }
  }

  /// "OK 👍" no pedido (capitão/líder).
  Future<void> _ackRequest(GroupRequestItem r) async {
    if (_pendingAck?.id == r.id) _pendingAck = null;
    _sendGroupToCar();
    try {
      await _svc.ackRequest(_code, r.id, widget.uid, widget.userName);
      _snack(tr('👍 Confirmado para {0}', [r.name]));
    } catch (_) {
      // Outro (capitão ou líder) já confirmou.
    }
  }

  /// Envia um pedido só para os pilotos da expedição.
  Future<void> _sendGroupRequest(GroupRequest kind) async {
    try {
      final p = _me ?? await Geolocator.getCurrentPosition();
      _svc.sendRequest(
          _code, widget.uid, widget.userName, kind, p.latitude, p.longitude);
      AnalyticsService.event('group_request', {'kind': kind.name});
      _voice.reply(tr('Pedido enviado ao grupo: {0}.', [kind.label]));
      _snack(tr('{0} Enviado ao grupo: {1}', [kind.emoji, kind.label]));
    } catch (e) {
      _snack(tr('Não foi possível enviar: {0}', [e]));
    }
  }

  /// Botão acima do SOS: os atalhos de pedido ao grupo.
  void _showGroupRequests() {
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(tr('Pedido ao grupo'),
                style: Theme.of(ctx).textTheme.titleLarge),
            subtitle: Text(
                tr('Só os pilotos desta expedição recebem (voz e notificação). Também por voz: "UauGo, preciso abastecer".')),
          ),
          for (final r in GroupRequest.values)
            ListTile(
              minVerticalPadding: 14,
              leading: Text(r.emoji, style: const TextStyle(fontSize: 30)),
              title: Text(r.label,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _sendGroupRequest(r);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ ações

  /// Envia um SOS aos pilotos da expedição (segurar o botão) e abre os
  /// telefones de emergência.
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
        content: Text(tr('🚨 SOS enviado aos pilotos da expedição')),
        action: SnackBarAction(
          label: 'CANCELAR',
          textColor: Colors.white,
          onPressed: () => _svc.resolveAlert(_code, id),
        ),
      ));
      // Também os telefones de emergência e o envio da localização
      // (WhatsApp), como fora da expedição.
      _showEmergency();
    } catch (e) {
      _snack(tr('Não foi possível obter sua posição: {0}', [e]));
    }
  }

  /// Segurou no mapa: adiciona uma parada ali (expedição).
  Future<void> _addStopAt(LatLng pos) async {
    if (!_isLeader) {
      _snack(tr('Só o líder altera o roteiro'));
      return;
    }
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nova parada')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              hintText: tr('Ex: Posto, almoço, mirante, pernoite')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Adicionar'))),
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
    if (!ok) _snack(tr('Parada salva, mas a rota não pôde ser recalculada'));
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
            leading: Icon(Icons.navigation),
            title: Text(tr('Navegar até aqui (Google Maps)')),
            onTap: () {
              Navigator.pop(ctx);
              _navigate(s.lat, s.lng);
            },
          ),
          if (_isExpedition)
            ListTile(
              leading: const Icon(Icons.route),
              title: Text(_isLeader ? tr('Editar no roteiro') : tr('Ver roteiro')),
              onTap: () {
                Navigator.pop(ctx);
                _openPlan();
              },
            ),
          // Rota normal: tirar uma parada do meio (não a saída nem o destino).
          if (_canCancelSoloStop(s))
            ListTile(
              leading: const Icon(Icons.wrong_location_outlined, color: Colors.red),
              title: Text(tr('Cancelar esta parada')),
              subtitle: Text(tr('A rota é recalculada sem ela')),
              onTap: () {
                Navigator.pop(ctx);
                _removeSoloStop(s);
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
  /// alterna entre "só o meu veículo" e "o grupo todo".
  void _centerOnMe() {
    if (!_follow) {
      setState(() => _follow = true);
    } else if (_view == _MapView.convoy) {
      setState(() => _showAll = !_showAll);
      _lastFit = DateTime.fromMillisecondsSinceEpoch(0);
      _snack(_showAll ? tr('Mostrando o grupo todo') : tr('Mostrando {0}', [_myBike.style.noun]));
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
    _camFrom = _camTo = _camShown = null; // movida à mão/zoom: recomeça
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
    // Em cima da rota: direção da própria via (não "dança" com o erro do
    // GPS, que piora sem internet).
    final w0 = _walker, pr0 = _proj;
    final snapped = (_navigating || _sim != null) && w0 != null && pr0 != null &&
        pr0.offset <= 25 && !_offRoute;
    if (snapped && _speedMs > 1.5) _bearing = w0.at(pr0.along).bearing;
    if (_map == null || (!_follow && !force)) return;
    final here = _shownPoint(p);

    if (_view == _MapView.solo && AppSettings.instance.northUp.value) {
      // Norte para cima: mapa plano, sem girar, centrado no piloto.
      _followCamera((CameraPosition(
        target: here,
        zoom: (17 + _zoomOffset).clamp(12.0, 20.0),
        tilt: 0,
        bearing: 0,
      )), force);
      return;
    }

    if (_view == _MapView.solo) {
      // Primeira pessoa: moto na parte de baixo da tela, olhando a estrada.
      // Perto de uma saída/conversão (até 400 m), aproxima sozinho para o
      // piloto ver por onde sair; depois volta.
      final turn = _navigating ? _upcomingTurn(p) : null;
      final nearTurn = turn != null && turn.meters < 400 && !turn.step.isSilent &&
          turn.step.maneuver.isNotEmpty && turn.step.maneuver != 'straight';
      final zoom = (18 + _zoomOffset + (nearTurn ? 0.8 : 0)).clamp(12.0, 20.0);
      _followCamera((CameraPosition(
        // Quanto mais afastado o zoom, mais à frente fica o centro.
        target: _ahead(here.latitude, here.longitude, _bearing,
            90 * pow(2, 18 - zoom).toDouble()),
        zoom: zoom,
        tilt: 65,
        bearing: _bearing,
      )), force);
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
    _followCamera((CameraPosition(
        target: here, zoom: (15.5 + _zoomOffset).clamp(5.0, 20.0))), force);
  }

  // ---- Câmera acompanhando: desliza no MESMO passo do ícone "Você"
  // (mesmo relógio, sem aceleração). Com a animação do Google (acelera e
  // freia) o ícone ia para frente e para trás na tela (05/11).
  CameraPosition? _camFrom, _camTo, _camShown;

  /// Distância que já não desliza (vai direto): GPS 300 m, simulação 3 km.
  double get _jumpMeters => _sim != null ? 3000 : 300;

  void _followCamera(CameraPosition to, bool force) {
    final map = _map;
    if (map == null) return;
    final cur = _camShown;
    if (cur == null || force ||
        distanceMeters(cur.target.latitude, cur.target.longitude,
                to.target.latitude, to.target.longitude) >
            _jumpMeters) {
      _camFrom = _camTo = null;
      _camShown = to;
      map.animateCamera(CameraUpdate.newCameraPosition(to),
          duration: const Duration(milliseconds: 500));
      return;
    }
    // Animação do próprio Google, no mesmo tempo do deslize do ícone. (Mover
    // a câmera 20x por segundo deixou o mapa em branco no Galaxy, 05/11.)
    _camShown = to;
    map.animateCamera(CameraUpdate.newCameraPosition(to), duration: _glideTime);
  }

  /// Posição da câmera no instante [t] (0 a 1) do deslize.
  static CameraPosition _lerpCam(CameraPosition a, CameraPosition b, double t) {
    double l(double x, double y) => x + (y - x) * t;
    var db = (b.bearing - a.bearing) % 360;
    if (db > 180) db -= 360;
    return CameraPosition(
      target: LatLng(l(a.target.latitude, b.target.latitude),
          l(a.target.longitude, b.target.longitude)),
      zoom: l(a.zoom, b.zoom),
      tilt: l(a.tilt, b.tilt),
      bearing: (a.bearing + db * t) % 360,
    );
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
    // Parado, o GPS "treme" alguns metros: isso não pode virar velocidade
    // (aparecia 5–12 km/h com o veículo parado).
    final prev = _prevPos;
    _prevPos = p;
    double raw;
    if (gpsSpeedIsNoise(
        speed: p.speed, speedAccuracy: p.speedAccuracy, accuracy: p.accuracy)) {
      raw = 0;
    } else if (p.speed > 0.5) {
      raw = p.speed;
    } else if (p.speedAccuracy > 0 || prev == null) {
      // O aparelho mede a velocidade e diz que está parado: vale zero.
      raw = 0;
    } else {
      final dt =
          p.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
      final moved =
          distanceMeters(prev.latitude, prev.longitude, p.latitude, p.longitude);
      // Deslocamento menor que o erro do GPS = tremor, não movimento.
      raw = dt >= 0.5 && dt <= 10 && moved > max(8.0, p.accuracy)
          ? moved / dt
          : 0;
    }
    // Abaixo de ~3 km/h mostra 0; acima, suaviza um pouco os saltos.
    _speedMs = raw < 0.8 ? 0 : (_speedMs < 0.8 ? raw : _speedMs * 0.3 + raw * 0.7);
    final kmh = _speedMs * 3.6;
    // Em cima da rota: só vale o limite de pontos da rota (não a marginal).
    final w = _walker, pr = _proj;
    final onRoute = w != null && pr != null && pr.offset < 40;
    // Na rota: o limite vem do PERFIL da rota (saídas e alças curtas são
    // ignoradas); fora dela (ou sem perfil), do ponto mais próximo.
    final prof = onRoute ? _routeLimitProfile(w, pr.along) : null;
    final found = prof?.at(pr!.along) ??
        _speedSvc.lookup(p.latitude, p.longitude, _bearing, _speedMs,
            routeOffset:
                onRoute ? (la, lo) => w.offsetNear(la, lo, pr.along) : null);
    _roadLimit = _limitTracker.update(found, DateTime.now(),
        kmh: kmh, onExit: prof != null && prof.onExit(pr!.along));
    final speech = _speedAlerter.update(
        kmh, _roadLimit, _speedSvc.settings.value, DateTime.now());
    if (speech != null) _voice.alert(speech);
    _checkReducedSpeedAhead(p, onRoute ? pr.along : null);
    _checkRodizio(p);
  }

  // ---- Rodízio de São Paulo (placa salva só no celular)
  String _plate = '';
  bool _plateLoaded = false;
  String _rodizioSaid = '';
  DateTime _rodizioChecked = DateTime.fromMillisecondsSinceEpoch(0);

  /// Entrou no centro expandido no dia/horário de rodízio da placa: avisa
  /// uma vez por dia (só carro, camionete, caminhão...; moto não).
  void _checkRodizio(Position p) {
    final now = DateTime.now();
    if (now.difference(_rodizioChecked) < const Duration(seconds: 30)) return;
    _rodizioChecked = now;
    if (!_plateLoaded) {
      _plateLoaded = true;
      ProfileService.loadPlate().then((v) => _plate = v);
      return;
    }
    final d = plateDigit(_plate);
    if (d == null || !subjectToRodizio(_myBike.style) || !rodizioNow(d, now)) return;
    if (!insideCentroExpandido(p.latitude, p.longitude)) return;
    final key = '${now.year}-${now.month}-${now.day}-${now.hour < 12}';
    if (_rodizioSaid == key) return;
    _rodizioSaid = key;
    _voice.alert(tr('Atenção: rodízio. Placa final {0} não pode circular no centro expandido agora.', [d]));
    _showTrafficBanner(tr('🚫 Rodízio: placa final {0} no centro expandido agora', [d]));
  }

  // ---- Perfil do limite ao longo da rota (de 1 km atrás a 6 km à frente)
  RouteLimitProfile? _limitProfile;
  Object? _limitProfileRoute;
  List<double> _routeExits = const [];
  Object? _routeExitsNav;
  RouteWalker? _routeExitsWalker;
  RouteWalker? _noLimitsRoute;
  double _noLimitsAt = 0; // sem limite nenhum por aqui: não refaz a cada leitura

  /// Onde a rota sai da via (m pela rota), a partir das manobras.
  List<double> _exitsOn(RouteWalker w) {
    final nav = _nav;
    if (nav == null) return const [];
    if (!identical(_routeExitsNav, nav) || !identical(_routeExitsWalker, w)) {
      _routeExitsNav = nav;
      _routeExitsWalker = w;
      _routeExits = [
        for (final s in nav.steps)
          if (s.leavesRoad) w.project(s.lat, s.lng).along,
      ];
    }
    return _routeExits;
  }

  /// Perfil válido para [along]; refaz ao andar 2 km ou ao trocar a rota.
  RouteLimitProfile? _routeLimitProfile(RouteWalker w, double along) {
    final cur = _limitProfile;
    if (cur != null &&
        identical(_limitProfileRoute, w) &&
        (cur.start == 0 || along >= cur.start + 1000 - 1) &&
        along <= cur.start + 3000) {
      return cur;
    }
    // Sem nenhum limite nesta região: só tenta de novo 500 m adiante. Refazer
    // a cada leitura do GPS travava a tela nas rotas longas.
    if (identical(_noLimitsRoute, w) && (along - _noLimitsAt).abs() < 500) {
      return null;
    }
    final exits = _exitsOn(w);
    const step = 50.0;
    final start = max(0.0, along - 1000);
    final end = min(w.length, along + 6000);
    final raw = <RoadLimit?>[];
    for (var d = start; d <= end; d += step) {
      final q = w.at(d);
      raw.add(_speedSvc.lookup(q.lat, q.lng, q.bearing, max(_speedMs, 10.0),
          routeOffset: (a, b) => w.offsetNear(a, b, d), maxAngle: 30));
    }
    if (raw.every((r) => r == null)) {
      _noLimitsRoute = w; // sem dados aqui ainda
      _noLimitsAt = along;
      return null;
    }
    _noLimitsRoute = null;
    _limitProfile = RouteLimitProfile(start, step, raw, exits: exits);
    _limitProfileRoute = w;
    return _limitProfile;
  }

  // ---- Velocidade reduzida à frente ("Velocidade reduzida para 60 em 300 m")
  (int, int)? _reducedAhead; // (limite, metros) mostrado no velocímetro
  int? _reducedPendingKmh; // redução vista na leitura anterior
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
    // Precisa aparecer em DOIS pontos seguidos à frente (ex.: 300 e 400 m)
    // com o mesmo limite: um ponto solto de saída/marginal não conta.
    int? prevKmh;
    int? prevD;
    (double, double)? prevAt, foundAt;
    var prevToll = false, foundToll = false;
    for (final d in const [100, 200, 300, 400, 500, 600]) {
      double la, lo, brg;
      if (along != null && w != null) {
        final q = w.at(along + d);
        (la, lo, brg) = (q.lat, q.lng, q.bearing);
      } else {
        final q = _ahead(p.latitude, p.longitude, _bearing, d.toDouble());
        (la, lo, brg) = (q.latitude, q.longitude, _bearing);
      }
      // Na rota: o perfil (já sem as saídas curtas).
      final l = (along != null ? _limitProfile?.at(along + d) : null) ??
          _speedSvc.lookup(la, lo, brg, _speedMs,
              routeOffset: along != null && w != null
                  ? (a, b) => w.offsetNear(a, b, along + d)
                  : null);
      // Só placas e redução de pelo menos 10 km/h. Na saída que a rota pega,
      // vale também o estimado (quase nenhuma saída tem placa mapeada).
      final exit = along != null &&
          l != null &&
          isSideDrop(cur, l) &&
          (_limitProfile?.onExit(along + d) ?? false);
      final reduced = l != null && (!l.estimated || exit) && l.kmh <= cur.kmh - 10
          ? l.kmh
          : null;
      if (reduced != null && reduced == prevKmh) {
        found = (reduced, prevD!);
        foundAt = prevAt;
        foundToll = prevToll || l?.src == 'toll';
        break;
      }
      prevKmh = reduced;
      prevD = d;
      prevAt = (la, lo);
      prevToll = l?.src == 'toll';
    }
    // E em duas leituras seguidas do GPS (não fala por um instante).
    final confirmed = found != null && found.$1 == _reducedPendingKmh;
    _reducedPendingKmh = found?.$1;
    if (!confirmed) found = null;
    if (found != _reducedAhead) setState(() => _reducedAhead = found);
    if (found == null) return;
    // Fala uma vez por redução (mesmo limite num raio de ~1 km).
    final key =
        '${found.$1}_${(p.latitude * 100).round()}_${(p.longitude * 100).round()}';
    // Pedágio: faixa própria (tocar corrige a velocidade da praça) e voz.
    final f = found;
    if (foundToll && foundAt != null) {
      final plaza = _speedSvc.tollNear(foundAt.$1, foundAt.$2);
      if (plaza != null && _tollBannerShown.add(plaza.key)) {
        final (pla, plo) = plaza.pts.first;
        _reducedAnnounced.add(key);
        _announceRadar(
          emoji: '🛣️',
          text: tr('Pedágio à frente · reduza para {0} km/h', [f.$1]),
          speech: tr('Pedágio à frente. Velocidade {0} em {1} metros', [f.$1, f.$2]),
          passed: (q) => _passedPoint(q, pla, plo) ||
              distanceMeters(q.latitude, q.longitude, pla, plo) > 1500,
          onTap: () => _editSpeed(
              title: tr('Pedágio'),
              kind: 't',
              key: SpeedFixService.tollKey(plaza),
              lat: pla,
              lng: plo,
              current: f.$1),
        );
        return;
      }
    }
    if (_reducedAnnounced.add(key) && f.$2 >= 200) {
      _voice.alert(tr('Atenção: velocidade reduzida para {0} em {1} metros', [f.$1, f.$2]));
    }
  }

  final Set<String> _tollBannerShown = {};

  /// Radar: confirmar ou corrigir o limite (Gold/administração).
  void _editRadar(FixedRadar r, int? kmh) => _editSpeed(
      title: switch (r.kind) {
        RadarKind.fixed => tr('Radar fixo'),
        RadarKind.section => tr('Radar de velocidade média'),
        RadarKind.redLight => tr('Radar de avanço de sinal'),
      },
      kind: 'r',
      key: SpeedFixService.radarKey(r),
      lat: r.lat,
      lng: r.lng,
      dir: r.direction,
      current: kmh);

  /// Segurar o velocímetro: confirmar ou corrigir o limite da via aqui.
  void _editRoadSpeed() {
    final p = _me;
    if (p == null) {
      _snack(tr('Aguardando o GPS.'));
      return;
    }
    final hd = _speedMs > 2 ? _bearing : -1.0;
    _editSpeed(
        title: tr('Limite da via aqui'),
        kind: 'v',
        key: SpeedFixService.roadKey(p.latitude, p.longitude, hd),
        lat: p.latitude,
        lng: p.longitude,
        dir: hd < 0 ? -1 : hd.round() % 360,
        current: _roadLimit?.kmh);
  }

  /// Folha "Confirmar / Corrigir velocidade". Só Gold ou administração; vale
  /// para todos com 1 administrador ou 2 usuários Gold (regra de 05/11).
  Future<void> _editSpeed({
    required String title,
    required String kind,
    required String key,
    required double lat,
    required double lng,
    int dir = -1,
    int? current,
  }) async {
    if (!await SpeedFixService.instance.canEdit()) {
      _snack(tr('Só usuários Gold ou administradores podem confirmar ou corrigir velocidades.'));
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(current != null
                ? tr('No app: {0} km/h', [current])
                : tr('Sem velocidade no app')),
            const SizedBox(height: 12),
            if (current != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(tr('Confirmar {0} km/h', [current])),
                  onPressed: () => Navigator.pop(ctx, current),
                ),
              ),
            if (kind == 'r') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.block),
                  label: Text(tr('Radar não existe')),
                  onPressed: () => Navigator.pop(ctx, 0),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(tr('Corrigir para:')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final v in const [20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120])
                ActionChip(
                  label: Text('$v'),
                  onPressed: () => Navigator.pop(ctx, v),
                ),
            ]),
            const SizedBox(height: 12),
            Text(
              tr('Vale para todos com 1 administrador ou 2 usuários Gold informando a mesma velocidade.'),
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ]),
        ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await SpeedFixService.instance.report(key,
          kind: kind, lat: lat, lng: lng, dir: dir, kmh: picked);
      _snack(picked == 0
          ? tr('Obrigado! Radar marcado como inexistente.')
          : tr('Obrigado! {0} km/h registrado.', [picked]));
    } catch (e) {
      debugPrint('Correção de velocidade recusada: $e');
      _snack(tr('Não foi possível salvar agora. Confira a internet.'));
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
                  Text(tr('Velocidade'),
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                      tr('O velocímetro fica vermelho ao passar do limite da via (âmbar quando o limite é estimado).')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Avisar por voz ao passar do limite')),
                    subtitle: Text(
                        tr('Só para limites de placa (não para os estimados)')),
                    value: s.roadAlert,
                    onChanged: (v) => save(SpeedAlertSettings(
                        roadAlert: v,
                        tolerance: s.tolerance,
                        personalMax: s.personalMax)),
                  ),
                  if (s.roadAlert) ...[
                    Text(tr('Avisar a partir de')),
                    Wrap(spacing: 8, children: [
                      for (final t in const [0, 5, 10])
                        ChoiceChip(
                          label: Text(t == 0 ? tr('Limite exato') : tr('+{0} km/h', [t])),
                          selected: s.tolerance == t,
                          onSelected: (_) => save(SpeedAlertSettings(
                              roadAlert: true,
                              tolerance: t,
                              personalMax: s.personalMax)),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Text(tr('Alerta de velocidade máxima')),
                  Text(
                      tr('Avisa por voz quando você passar desta velocidade, em qualquer via.'),
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final v in const [0, 60, 80, 100, 110, 120, 140])
                      ChoiceChip(
                        label: Text(v == 0 ? tr('Desligado') : '$v km/h'),
                        selected: s.personalMax == v,
                        onSelected: (_) => save(SpeedAlertSettings(
                            roadAlert: s.roadAlert,
                            tolerance: s.tolerance,
                            personalMax: v)),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  Text(
                    tr('Limites das vias: projeto Pardal (ODbL) – ANTT, DERs e © colaboradores do OpenStreetMap. Onde não há placa mapeada, o limite é estimado pelo tipo de via. Respeite sempre a sinalização.'),
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
        title: Text(tr('SOS no comboio')),
        content: Text(tr('{0} pediu ajuda!{1}', [a.name, _dist(a.lat, a.lng)])),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _focus(a.lat, a.lng);
            },
            child: Text(tr('Ver no mapa')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goHelp(a.name, a.lat, a.lng);
            },
            child: Text(tr('Ir até lá')),
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
            _sheetTitle(tr('Pilotos ({0})', [sorted.length])),
            if (_isLeader || _isCaptain)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                    _isLeader
                        ? tr('Toque no piloto para escolher o capitão e os ferrolhos.')
                        : tr('Você é o capitão: toque num piloto para passar a capitania.'),
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
                    m.uid == widget.uid ? tr('{0} (você)', [m.name]) : m.name,
                    if (_roleOf(m.uid) case final r?) r,
                    if (m.bike.displayName.isNotEmpty) m.bike.displayName,
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _isLeader || (_isCaptain && m.uid != widget.uid)
                    ? IconButton(
                        icon: const Icon(Icons.manage_accounts),
                        tooltip: _isLeader ? tr('Capitão / ferrolho') : tr('Passar a capitania'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _editRoles(m);
                        },
                      )
                    : (_watchesGroup && _memberOffRoute(m)
                        ? const Icon(Icons.priority_high, color: Colors.amber)
                        : null),
                subtitle: Text(!m.hasLocation
                    ? tr('Sem localização ainda')
                    : m.isStale
                        ? tr('Sem sinal · última posição {0}', [_ago(m.updatedAt)])
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
                onLongPress: () {
                  Navigator.pop(ctx);
                  _askRouteToMember(m);
                },
              ),
            _sheetTitle(tr('Paradas ({0})', [_stops.length])),
            if (_stops.isEmpty)
              ListTile(
                  title: Text(tr('Toque e segure no mapa para adicionar'))),
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
    _snack(tr('Código {0} copiado. Envie para o grupo!', [_code]));
  }

  /// Sair da expedição (ou, para o líder, encerrar para todos).
  Future<void> _leave() async {
    // O líder pode encerrar a expedição para todos (apaga do Firebase; cada
    // piloto fica com a viagem salva no próprio celular).
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isLeader ? tr('Sair ou encerrar?') : tr('Sair da expedição?')),
        content: Text(_isLeader
            ? tr('Sair: só você deixa o comboio.\n\nEncerrar para todos: a expedição acaba e é apagada do servidor. A viagem fica salva em "Minhas viagens" no celular de cada piloto.')
            : tr('Você deixará de compartilhar sua localização com o grupo. A viagem fica salva em "Minhas viagens".')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Ficar'))),
          if (_isLeader)
            TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, 'end'),
                child: Text(tr('Encerrar para todos'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'leave'),
              child: Text(tr('Sair'))),
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
        _snack(tr('Não foi possível encerrar: {0}', [e]));
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
          ? (_exp?.name ?? tr('Expedição {0}', [_code]))
          : (_trip?.title ?? tr('Só dirigir')),
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
        title: Text(tr('Expedição encerrada')),
        content: Text(tr('O líder encerrou a expedição. A sua viagem ficou salva em "Minhas viagens".')),
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
    if (d.inMinutes < 60) return tr('há {0} min', [d.inMinutes]);
    return tr('há {0} h', [d.inHours]);
  }

  /// Retorna " · 2,3 km" (distância até você) ou "" se sem GPS.
  String _dist(double lat, double lng) {
    if (_me == null) return '';
    final m = Geolocator.distanceBetween(
        _me!.latitude, _me!.longitude, lat, lng);
    final txt = m < 1000
        ? '${m.round()} m'
        : '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
    return tr(' · {0} de você', [txt]);
  }

  // O GPS atualiza a cada segundo. Para não reenviar todos os marcadores ao
  // mapa nativo toda vez, os que não mudaram são reaproveitados (mesmos
  // objetos) e só a minha moto é refeita.
  Set<Marker> _staticMarkers = {};
  int _staticSig = 0;

  /// Marcadores do mapa: os fixos (paradas, grupo, alertas, radares)
  /// reaproveitados e só a moto do piloto refeita a cada leitura (leve).
  // ---- "Você" deslizando entre as leituras do GPS (sem pulos)

  /// Posição desenhada do "Você" (vai de [_glideFrom] a [_glideTo] no mesmo
  /// tempo da câmera, 0,9 s), em vez de saltar a cada leitura.
  LatLng? _shownMe;
  LatLng? _glideFrom, _glideTo;
  DateTime _glideStart = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _glideTimer;
  // Um pouco MAIS que o intervalo do GPS (1 s): o deslize nunca termina
  // antes da leitura seguinte. Com 0,9 s o ícone parava 0,1 s a cada
  // segundo e andava "dando tranco, cavalgando" (05/11).
  static const _glideTime = Duration(milliseconds: 1100);

  /// Quanto o piloto já andou desde a leitura do GPS até o fim do deslize
  /// (idade da leitura + tempo do deslize, na velocidade atual). Sem isso o
  /// "Você" e a câmera ficavam ~1 s atrás do real (20–30 m na estrada).
  /// Até 40 m; parado ou devagar (< 3 m/s), zero.
  double _lead = 0;
  double _leadMeters(Position p) {
    final v = p.speed;
    if (!v.isFinite || v < 3) return 0;
    final age = DateTime.now().difference(p.timestamp).inMilliseconds / 1000;
    final secs = age.clamp(0.0, 1.5) + _glideTime.inMilliseconds / 1000;
    return (v * secs).clamp(0.0, 40.0).toDouble();
  }

  /// Onde desenhar o "Você": navegando e a até 25 m da rota, EM CIMA da
  /// rota (o GPS do celular erra 10–30 m; sem internet, mais), já adiantado
  /// pelo tempo do deslize. Longe da rota (saiu dela), a posição do GPS.
  LatLng _shownPoint(Position p) {
    final w = _walker, pr = _proj;
    if ((_navigating || _sim != null) && w != null && pr != null &&
        pr.offset <= 25 && !_offRoute) {
      final q = w.at(pr.along + _lead);
      return LatLng(q.lat, q.lng);
    }
    return _ahead(p.latitude, p.longitude, _bearing, _lead);
  }

  void _glideMeTo(LatLng to) {
    final from = _shownMe;
    // 1ª posição ou salto grande (ex.: GPS voltou): vai direto. Simulação
    // acelerada anda centenas de metros por segundo: ali só um salto de
    // verdade (> 3 km, arrastar a linha do tempo) vai direto.
    if (from == null ||
        distanceMeters(from.latitude, from.longitude, to.latitude, to.longitude) >
            _jumpMeters) {
      // Para o deslize E libera o relógio (antes ficava cancelado mas não
      // nulo: nunca mais religava e o ícone/câmera travavam, vídeo de 05/11).
      _glideTimer?.cancel();
      _glideTimer = null;
      _glideFrom = _glideTo = null;
      _shownMe = to;
      return;
    }
    _glideFrom = from;
    _glideTo = to;
    _ensureGlideTimer();
  }

  /// ~20 quadros por segundo: ícone e câmera andam juntos, sem pesar.
  void _ensureGlideTimer() {
    _glideStart = DateTime.now();
    _glideTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _inBackground) return;
      final t = (DateTime.now().difference(_glideStart).inMilliseconds /
              _glideTime.inMilliseconds)
          .clamp(0.0, 1.0);
      final a = _glideFrom, b = _glideTo;
      if (a != null && b != null) {
        setState(() => _shownMe = LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t));
      }
      final ca = _camFrom, cb = _camTo, map = _map;
      if (ca != null && cb != null && map != null && (_follow)) {
        final c = _lerpCam(ca, cb, t);
        _camShown = c;
        map.moveCamera(CameraUpdate.newCameraPosition(c));
      }
      if (t >= 1) {
        _glideTimer?.cancel();
        _glideTimer = null;
      }
    });
  }

  Set<Marker> _buildMarkers() {
    final sig = Object.hashAll([
      identityHashCode(_stops),
      identityHashCode(_members),
      identityHashCode(_alerts),
      identityHashCode(_hazards),
      identityHashCode(_radarMarkers),
      identityHashCode(_policeMarkers),
      identityHashCode(_signalMarkers),
      _policeIcon != null,
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
        position: _shownMe ?? LatLng(me.latitude, me.longitude),
        zIndex: 3,
        anchor: icon != null ? bikeMarkerAnchor : const Offset(0.5, 1),
        icon: icon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: tr('Você')),
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
            // Vermelho transparente (todo radar é vermelho); tracejado, não
            // confunde com a rota.
            color: Colors.red.withAlpha(110),
            patterns: [PatternItem.dash(24), PatternItem.gap(10)],
            consumeTapEvents: true,
            onTap: () => _snack(
                tr('🚔 Trecho com possível radar portátil da PRF: BR-{0}, km {1} a {2}', [s.br, s.kmFrom.round(), s.kmTo.round()])),
          ),
      };
    }
    return {
      ..._prfPolylines,
      if (_route.length >= 2) ..._routePolylines(),
      if (_route.length >= 2) ..._trafficPolylines(),
    };
  }

  List<Polyline>? _routeLines;

  /// Rota que falta: navegando na rota, o trecho já percorrido some (como
  /// no Waze/Google). Refeito a cada ~20 m andados.
  List<LatLng> get _visibleRoute {
    final w = _walker, pr = _proj;
    if ((!_navigating && _sim == null) || w == null || pr == null ||
        pr.offset > 60 || _offRoute) {
      return _route;
    }
    final step = (pr.along / 20).floor();
    final cached = _trimmedRoute;
    if (cached != null && step == _trimStep && identical(_trimBase, _route)) {
      return cached;
    }
    _trimStep = step;
    _trimBase = _route;
    return _trimmedRoute = [
      for (final (la, lo) in w.pointsAfter(pr.along)) LatLng(la, lo)
    ];
  }

  List<LatLng>? _trimmedRoute;
  List<LatLng>? _trimBase;
  int _trimStep = -1;

  List<TrafficRun> _trafficRuns = const [];
  List<Polyline> _trafficLines = const [];
  Object? _trafficLinesFor;
  int _trafficLinesStep = -1;
  DateTime _trafficAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _trafficBusy = false;

  static const _trafficColors = [Color(0xFF2EA043), Color(0xFFF9A825), Color(0xFFD32F2F)];

  /// Trechos que faltam da rota, com a posição atual já descontada.
  List<(int, List<(double, double)>)> _trafficAhead() {
    final w = _walker;
    if (w == null) return const [];
    final along = _proj?.along ?? 0;
    return [
      // Livre fica na rota azul: só lento e parado ganham cor.
      for (final r in _trafficRuns)
        if (r.level > 0 && r.to > along)
          (r.level, w.pointsBetween(max(r.from, along), r.to)),
    ];
  }

  /// Amarelo e vermelho só em cima da rota (refeito a cada ~100 m).
  List<Polyline> _trafficPolylines() {
    if (_trafficRuns.isEmpty) return const [];
    final step = ((_proj?.along ?? 0) / 100).floor();
    if (identical(_trafficLinesFor, _trafficRuns) && step == _trafficLinesStep) {
      return _trafficLines;
    }
    _trafficLinesFor = _trafficRuns;
    _trafficLinesStep = step;
    var i = 0;
    return _trafficLines = [
      for (final (level, pts) in _trafficAhead())
        Polyline(
          polylineId: PolylineId('traffic_${i++}'),
          points: [for (final (la, lo) in pts) LatLng(la, lo)],
          width: 6,
          color: _trafficColors[level],
          zIndex: 3,
        ),
    ];
  }

  void _setTrafficRuns(List<TrafficRun> runs) {
    if (!mounted) return;
    setState(() => _trafficRuns = runs);
    CarService.instance.traffic(_trafficAhead());
  }

  /// Consulta o trânsito dos próximos 100 km da rota (a cada 5 min, ou ao
  /// trocar de rota). Sem resposta, a rota fica azul.
  Future<void> _refreshRouteTraffic() async {
    final w = _walker, p = _me;
    if (!AppSettings.instance.showTraffic.value || _saving || _sim != null ||
        !_navigating || !_online3d || _trafficBusy || w == null || p == null) {
      return;
    }
    if (DateTime.now().difference(_trafficAt) < const Duration(seconds: 60)) return;
    _trafficAt = DateTime.now();
    _trafficBusy = true;
    final from = _proj?.along ?? 0;
    final to = min(w.length, from + 100000);
    final pts = <LatLng>[
      LatLng(p.latitude, p.longitude),
      for (var i = 1; i <= 9; i++)
        if (w.at(from + (to - from) * i / 10) case final q) LatLng(q.lat, q.lng),
      if (w.at(to) case final q) LatLng(q.lat, q.lng),
    ];
    final got = await DirectionsService.routeTraffic(pts);
    _trafficBusy = false;
    if (!mounted || !identical(w, _walker)) return;
    if (got == null) return;
    _setTrafficRuns(trafficOnRoute(w, got.$1, got.$2, start: from));
    if (RouteEngineService.enabled) _onRouteDelay(to - from, got.$3, got.$4);
  }

  /// Rota azul com borda escura (refeita só quando muda).
  List<Polyline> _routePolylines() {
    final l = _routeLines;
    final pts = _visibleRoute;
    if (l != null && identical(l.first.points, pts)) return l;
    return _routeLines = [
      Polyline(
        polylineId: const PolylineId('route_border'),
        points: pts,
        width: 9,
        color: MapScreen.routeBorder,
        zIndex: 1,
      ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: pts,
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
          snippet: tr('Toque para opções'),
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
              ? tr('Sem sinal · {0}', [_ago(m.updatedAt)])
              : tr('{0} km/h · {1}', [(m.speed * 3.6).round(), _ago(m.updatedAt)]),
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
          title: tr('🚨 SOS: {0}', [a.name]),
          snippet: tr('Toque para traçar rota'),
          onTap: () => _navigate(a.lat, a.lng),
        ),
      ));
    }
    if (_policeIcon case final icon?) {
      for (final q in _policeMarkers) {
        markers.add(Marker(
          markerId: MarkerId('police_${q.id}'),
          position: LatLng(q.lat, q.lng),
          anchor: const Offset(0.5, 0.5),
          zIndex: 4,
          icon: icon,
          infoWindow: InfoWindow(title: tr('Posto policial')),
        ));
      }
    }
    if (_signalIcon case final icon?) {
      for (final (la, lo) in _signalMarkers) {
        markers.add(Marker(
          markerId: MarkerId('signal_${la}_$lo'),
          position: LatLng(la, lo),
          anchor: const Offset(0.5, 0.5),
          zIndex: 3,
          icon: icon,
          infoWindow: InfoWindow(title: tr('Semáforo')),
        ));
      }
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
            RadarKind.fixed => tr('Radar fixo'),
            RadarKind.section => tr('Radar de velocidade média'),
            RadarKind.redLight => tr('Radar de avanço de sinal'),
          },
          snippet: r.limit > 0 ? tr('Limite {0} km/h', [r.limit]) : null,
          onTap: () => _editRadar(r, r.limit > 0 ? r.limit : null),
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
    // v2: o painel do 3D se encaixa no espaço livre entre os botões.
    if (_hud3d) WidgetsBinding.instance.addPostFrameCallback((_) => _layoutHud3d());
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
        // Topo com as informações da viagem em 2 linhas, letra maior; deitado
        // ou no "Dirigir agora" sem destino, uma linha só (sobra mapa).
        toolbarHeight: landscape || _justDriving ? 52 : 84,
        // Toque no título: resumo da viagem (tempo, km, custo).
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showTripSummary,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                _isExpedition
                    ? (_exp?.name ?? tr('Expedição'))
                    : widget.simulate
                        ? tr('Simulação: {0}', [_trip?.title ?? ''])
                        : (_trip?.title ?? tr('Navegação')),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: landscape ? 16 : 19, fontWeight: FontWeight.bold)),
            if (!_justDriving) ...[
              if (!landscape) const SizedBox(height: 2),
              Text(
                  (_isExpedition ? _expeditionSubtitle() : _etaText())
                      .replaceAll('\n', landscape ? ' · ' : '\n'),
                  maxLines: landscape ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: landscape ? 13 : 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25)),
            ],
          ],
        ),
        ),
        actions: !_isExpedition
            ? [if (_navigating && _sim == null) _exitNavButton()]
            : [
          if (_navigating && _sim == null) _exitNavButton(),
          IconButton(
              icon: const Icon(Icons.route),
              tooltip: tr('Roteiro'),
              onPressed: _openPlan),
          IconButton(
              icon: Icon(_myBike.style.icon),
              tooltip: tr('Meu veículo'),
              onPressed: _editBike),
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: tr('Copiar código'),
              onPressed: _copyCode),
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: tr('Sair da expedição'),
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
          compassEnabled: false, // o sentido do mapa tem botão próprio
          // Trânsito do Google: vias em verde/laranja/vermelho (sem custo).
          // Na economia de bateria, sem trânsito e sem prédios 3D (menos
          // trabalho para o processador gráfico).
          // Modo leve (celulares mais simples): sem trânsito e sem prédios 3D.
          // A camada do Google pinta o mapa todo: o trânsito vai só na
          // linha da rota (_trafficPolylines).
          trafficEnabled: false,
          buildingsEnabled: !_saving && !AppSettings.instance.lightMode,
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
          // v2: zoom bem perto com os dedos (primeira pessoa) volta para o 3D.
          onCameraMove: (c) {
            if (!_show3d && !_follow && _canShow3d && c.zoom >= 19.6) {
              _manual3dUntil = DateTime.now().add(const Duration(seconds: 20));
              _set3d(true);
            }
          },
          onLongPress: _isExpedition
              ? _addStopAt
              : (_canAddSoloStop
                  ? _addSoloStopAt
                  : (_canStartRoute ? _startRouteAt : null)),
        ),
        ),

        // v2: estrada em 3D por cima do mapa (os avisos e botões ficam por cima).
        // Com a economia de memória marcada e o carro conectado: 3D só no
        // carro (os dois juntos deixavam o carro uns 3 s atrás do celular).
        if (_hud3d)
          Positioned.fill(
            child: Sim3DView(
              key: _kWeb3d,
              controller: _sim3d,
              onBackToMap: () {
                _manual3dUntil = DateTime.now().add(const Duration(seconds: 20));
                _set3d(false);
              },
            ),
          ),

        // Botões e faixas ficam acima da barra de navegação do Android
        // (no Samsung o app vai até a borda da tela).
        // Embaixo e nas laterais respeita a barra do Android (deitado ela
        // fica de lado e escondia o alerta e o velocímetro). Folgas pequenas
        // (câmera/cantos arredondados) são ignoradas para colar na borda.
        Positioned.fill(child: Padding(
          padding: EdgeInsets.only(
            left: _sideInset(MediaQuery.viewPaddingOf(context).left),
            right: _sideInset(MediaQuery.viewPaddingOf(context).right),
            bottom: MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Stack(children: [

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
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.white)),
                      SizedBox(width: 12),
                      Text(tr('Recalculando a rota...'),
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
            if (_helpTarget case final help?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.teal.shade700,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
                    child: Row(children: [
                      Expanded(
                        child: Text(tr('🧭 Indo até {0}', [help.name]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: _endHelp,
                        child: Text(tr('Cancelar')),
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
                            tr('{0} pediu ajuda · {1}{2}', [a.uid == widget.uid ? tr('Você') : a.name, _ago(a.createdAt), _dist(a.lat, a.lng)]),
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
                // Amarelo: aviso de radar/velocidade/polícia chama atenção.
                // Radar perto (400 m): borda vermelha; acima do limite dele:
                // pisca vermelho/amarelo.
                color: _bannerBlinkRed ? Colors.red.shade600 : Colors.amber,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: (_bannerRadar?.m ?? 99999) <= 400
                      ? BorderSide(color: Colors.red.shade700, width: 4)
                      : BorderSide.none,
                ),
                child: InkWell(
                  // Tocar ou segurar: confirmar/corrigir a velocidade.
                  onTap: _radarBanner!.onTap,
                  onLongPress: _radarBanner!.onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                  child: Row(children: [
                    Text(_radarBanner!.emoji,
                        style: const TextStyle(fontSize: 30)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_radarBanner!.text,
                          style: TextStyle(
                              color: _bannerBlinkRed ? Colors.white : Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                    // Distância até o radar, contando (antes ficava embaixo).
                    if (_bannerRadar case final r?)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(formatDistance(r.m),
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                color: _bannerBlinkRed ? Colors.white : Colors.black,
                                fontSize: 22,
                                fontWeight: FontWeight.w900)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black),
                      onPressed: () => setState(() => _radarBanner = null),
                    ),
                  ]),
                ),
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
                        tr('{0}, do seu clube, está em {1} (~{2} km). Avisar que você está passando?', [_passingSuggestion!.name, _passingSuggestion!.city, _passingSuggestion!.distanceKm]),
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
                  title: Text(tr('Monte o roteiro da viagem')),
                  subtitle: Text(tr('Saída, paradas, pernoites e destino')),
                  onTap: _openPlan,
                ),
              ),
            // Música (como no Waze): em pé, ícone redondo à direita, logo abaixo
            // das faixas; deitado, fica no topo da coluna da direita. Na
            // expedição a coluna da direita é alta: vai para a da esquerda.
            if (_sim == null && !landscape && !_isExpedition)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _musicButton(),
                ),
              ),
          ]),
        ),

        // Controles da música (pílula compacta que o piloto arrasta).
        if (_sim == null)
          Positioned.fill(
            child: LayoutBuilder(builder: (_, box) => _musicPill(box.biggest)),
          ),

        // Controles da simulação (pausar, velocidade, linha do tempo)
        if (_sim != null)
          Positioned(left: 8, right: 8, bottom: 16,
              child: KeyedSubtree(key: _kSimBar, child: _simControls())),

        // Recentralizar (aparece ao arrastar o mapa) + Iniciar / encerrar.
        // Deitado: à esquerda, para não tapar o marcador do piloto no centro.
        // Em pé, fica entre as colunas de botões das laterais (não cobre).
        Positioned(
          left: landscape ? 210 : 112,
          right: landscape ? null : 76,
          bottom: _sim != null ? 196 : (landscape ? 28 : 104),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!_follow && _me != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                // Compacto: não cobre o perigo/radar móvel do canto.
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 38),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    elevation: 6,
                  ),
                  onPressed: _recenter,
                  icon: const Icon(Icons.navigation, size: 18),
                  label: Text(tr('Recentralizar'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            if (_tripButton() case final btn?)
              FittedBox(fit: BoxFit.scaleDown, child: btn),
          ]),
        ),

        // Velocímetro (toque para configurar os alertas de velocidade)
        Positioned(
          left: 6,
          top: landscape ? 8 : null,
          // Embaixo, mas acima do logo do Google (o mapa exige que ele apareça).
          bottom: _sim != null ? 196 : 36,
          child: _landscapeFit(landscape, Alignment.bottomLeft, Column(
            key: _kLeftCol,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_sim == null && !landscape && _isExpedition) ...[
                _musicButton(),
                const SizedBox(height: 12),
              ],
              // Sentido do mapa (como nos outros apps): seguindo a direção ou
              // norte para cima.
              ValueListenableBuilder<bool>(
                valueListenable: AppSettings.instance.northUp,
                builder: (_, north, __) => FloatingActionButton.small(
                  heroTag: 'heading',
                  tooltip: north ? tr('Norte para cima') : tr('Seguindo a direção'),
                  onPressed: () async {
                    await AppSettings.instance.setNorthUp(!north);
                    _snack(!north
                        ? tr('Mapa com o norte para cima')
                        : tr('Mapa seguindo a sua direção'));
                    if (_me != null) _updateCamera(_me!, force: true);
                  },
                  child: north
                      ? const Text('N', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))
                      : const Icon(Icons.navigation),
                ),
              ),
              const SizedBox(height: 10),
              // Zoom: na mesma coluna do velocímetro, logo acima dele (assim
              // nunca fica atrás dele nem dos botões da direita).
              FloatingActionButton.small(
                heroTag: 'zoomIn',
                tooltip: tr('Aproximar'),
                onPressed: () => _zoom(1),
                child: const Icon(Icons.add, size: 28),
              ),
              const SizedBox(height: 6),
              FloatingActionButton.small(
                heroTag: 'zoomOut',
                tooltip: tr('Afastar'),
                onPressed: () => _zoom(-1),
                child: const Icon(Icons.remove, size: 28),
              ),
              const SizedBox(height: 12),
              // Radar à frente: distância até ele (some ao passar). Com a
              // faixa amarela na tela, a distância vai nela.
              if (_bannerRadar == null)
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
                      tr('{0} {1}{2}em {3} m', [r.emoji, r.kmh ?? '', r.kmh != null ? ' ' : '', r.m]),
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
                  child: Text(tr('↓ {0} em {1} m', [lim, m]),
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                ),
              if (!_hud3d)
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
                    onLongPress: _editRoadSpeed,
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
            // Logo abaixo da faixa da próxima curva (ou no topo, parado).
            top: _navigating ? 92 : 8,
            child: _groupGridPanel(),
          ),

        // Reportar perigo e, ao lado, o radar móvel com UM toque (o alerta
        // mais usado, precisa ser rápido): à esquerda do SOS, no mapa e no 3D
        // (pedido de 04/11), em pé ou deitado.
        if (_sim == null)
        Positioned(
          right: 6 + 88 + 10,
          bottom: 24 + (88 - 62) / 2,
          child: Row(key: _kBottomLeft, mainAxisSize: MainAxisSize.min, children: [
            // Tocar OU segurar abre as opções (segurar só mostrava a dica).
            Semantics(
              label: tr('Reportar perigo'),
              button: true,
              child: GestureDetector(
                onLongPress: _showReportSheet,
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: FloatingActionButton(
                    heroTag: 'hazard',
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    onPressed: _showReportSheet,
                    child: const Icon(Icons.warning_amber_rounded, size: 32),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 62,
              height: 62,
              child: FloatingActionButton(
                heroTag: 'radar',
                tooltip: tr('Avisar radar móvel aqui'),
                backgroundColor: HazardType.radar.color,
                foregroundColor: Colors.white,
                onPressed: _quickRadar,
                child: Text(HazardType.radar.emoji,
                    style: const TextStyle(fontSize: 26)),
              ),
            ),
          ]),
        ),

        // Botões
        Positioned(
          right: 6,
          top: landscape ? 8 : null,
          bottom: _sim != null ? 196 : 24,
          child: _landscapeFit(landscape, Alignment.bottomRight, Column(key: _kRightCol, mainAxisSize: MainAxisSize.min, children: [
            if (_clubId != null) ...[
              FloatingActionButton(
                heroTag: 'club',
                onPressed: _showClubActions,
                tooltip: tr('Clube'),
                backgroundColor: Colors.teal,
                child: const Icon(Icons.shield, color: Colors.white),
              ),
              const SizedBox(height: 12),
            ],
            if (_sim == null && landscape) _musicButton(),
            // Visão (o "olho"): SOLO (primeira pessoa) ou COMBOIO (de cima).
            FloatingActionButton.small(
              heroTag: 'view',
              tooltip: _view == _MapView.convoy
                  ? tr('Visão: comboio (toque para solo)')
                  : tr('Visão: solo (toque para comboio)'),
              onPressed: _toggleView,
              child: Icon(_view == _MapView.convoy ? Icons.groups_2 : Icons.visibility),
            ),
            const SizedBox(height: 12),
            // v2: 3D (estrada em primeira pessoa) ou mapa de cima.
            if (_canShow3d) ...[
              FloatingActionButton.small(
                heroTag: '3d',
                tooltip: tr('Escolher a visão'),
                onPressed: _chooseMode3d,
                child: Icon(_mode3d.icon),
              ),
              const SizedBox(height: 12),
            ],
            ValueListenableBuilder<bool>(
              valueListenable: _voice.alertsOn,
              builder: (_, on, __) => FloatingActionButton.small(
                heroTag: 'voice',
                tooltip: tr('Voz'),
                onPressed: _showVoiceSettings,
                child: Icon(on ? Icons.volume_up : Icons.volume_off),
              ),
            ),
            const SizedBox(height: 12),
            if (_canAddSoloStop) ...[
              FloatingActionButton.small(
                heroTag: 'addStop',
                tooltip: tr('Adicionar parada (ou segure no mapa)'),
                onPressed: _addSoloStopBySearch,
                child: const Icon(Icons.add_location_alt),
              ),
              const SizedBox(height: 12),
            ],
            if (_canStartRoute) ...[
              FloatingActionButton.small(
                heroTag: 'newRoute',
                tooltip: tr('Traçar rota (ou segure no mapa)'),
                onPressed: _startRouteBySearch,
                child: const Icon(Icons.directions),
              ),
              const SizedBox(height: 12),
            ],
            if (_watchesGroup) ...[
              FloatingActionButton.small(
                heroTag: 'groupGrid',
                tooltip: _groupGrid ? tr('Ver os pilotos no mapa') : tr('Ver em grade (apelidos)'),
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
                tooltip: tr('Grupo e paradas'),
                child: Badge(
                  label: Text('${_members.length}'),
                  child: const Icon(Icons.groups),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Só no COMBOIO: alterna "grupo todo" / "só o meu veículo" (ou volta
            // a acompanhar). No SOLO não fazia nada; lá quem volta é o
            // "Recentralizar".
            if (_view == _MapView.convoy)
              FloatingActionButton(
                heroTag: 'me',
                onPressed: _centerOnMe,
                tooltip: !_follow
                    ? tr('Voltar a acompanhar')
                    : (_showAll ? tr('Mostrar só {0}', [_myBike.style.noun]) : tr('Mostrar o grupo todo')),
                child: Icon(!_follow
                    ? Icons.my_location
                    : (_showAll ? Icons.person_pin_circle : Icons.zoom_out_map)),
              ),
            if (_sim == null && _isExpedition) ...[
              const SizedBox(height: 16),
              // Pedidos ao grupo ("Preciso abastecer"...), acima do SOS.
              FloatingActionButton(
                heroTag: 'requests',
                tooltip: tr('Pedidos ao grupo'),
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                onPressed: _showGroupRequests,
                child: const Icon(Icons.campaign, size: 30),
              ),
            ],
            if (_sim == null) ...[
            const SizedBox(height: 20),
            // Precisa SEGURAR para evitar SOS acidental (luva, vibração).
            // Sozinho (sem grupo), abre os telefones de emergência.
            GestureDetector(
              onLongPress: _isExpedition ? _sendSos : _showEmergency,
              onTap: () => _snack(_isExpedition
                  ? tr('Segure o botão para enviar o SOS')
                  : tr('Segure o botão para ver os telefones de emergência')),
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
      final said = await _voiceCmd.listenFree(tr('O que você procura? Fale agora'));
      if (!mounted) return;
      if (said == null || said.trim().isEmpty) {
        _voice.reply(tr('Não entendi. Diga, por exemplo: {0}, procurar posto.', [voiceWakeDisplay]));
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
      _voice.reply(tr('Na simulação a busca de lugares fica desligada.'));
      return;
    }
    final p = _me;
    if (p == null) {
      _voice.reply(tr('Ainda sem a sua posição pelo GPS.'));
      return;
    }
    final what = '${cat?.spoken ?? text}${cheap ? ' barato' : ''}';
    _lastFindSpoken = cat?.spoken;
    _voice.reply(tr('Procurando {0}.', [what]));
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
      _voice.reply(tr('Limite de buscas de hoje atingido. Tente amanhã.'));
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
          tr('Não encontrei {0} {1}.', [what, onRoute ? tr('à frente na rota') : tr('por perto')]));
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
    _voice.reply(tr('{0}, a {1}{2}. {3}', [
      f.name,
      spokenDistance(f.meters),
      f.onRoute ? tr(', no caminho') : '',
      _isExpedition
          ? tr('No comboio, combine a parada com o líder.')
          : tr('Adicionar como parada? Diga sim ou não.'),
    ]));
  }

  /// "Não": oferece a próxima opção (ou encerra).
  void _nextFound() {
    if (_foundIdx + 1 >= _found.length) {
      setState(() => _found = []);
      _voice.reply(tr('Sem mais opções.'));
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
      _voice.reply(tr('No comboio, combine a parada com o líder.'));
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
        TripPoint(tr('Sua posição'), p.latitude, p.longitude, type: StopType.meet),
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
      _voice.reply(tr('Não consegui incluir a parada. Confira a internet.'));
      return;
    }
    _applyTrip(nt);
    _voice.reply(tr('Parada incluída: {0}.', [name]));
  }

  /// Parada do meio da rota normal, ainda não visitada: dá para cancelar.
  bool _canCancelSoloStop(Stop s) {
    final t = _trip;
    if (_isExpedition || t == null || _sim != null) return false;
    final i = t.stops.indexWhere((x) => x.id == s.id);
    return i > 0 && i < t.stops.length - 1 && !_stopArrived.contains(s.id);
  }

  /// Próxima parada do meio (para "UauGo, cancelar parada").
  Stop? get _nextSoloStop {
    final t = _trip;
    if (t == null) return null;
    for (var i = 1; i < t.stops.length - 1; i++) {
      if (!_stopArrived.contains(t.stops[i].id)) return t.stops[i];
    }
    return null;
  }

  /// Parada esperando o "sim" de "Cancelar a parada X?".
  Stop? _pendingCancelStop;

  /// Tira a parada [s] e recalcula a rota de onde o piloto está.
  Future<void> _removeSoloStop(Stop s) async {
    final trip = _trip, p = _me;
    if (trip == null || p == null) return;
    final rest = [
      for (var i = 1; i < trip.stops.length; i++)
        if (trip.stops[i].id != s.id && !_stopArrived.contains(trip.stops[i].id))
          trip.stops[i]
    ];
    if (rest.isEmpty) return;
    setState(() => _rerouting = true);
    final nt = await TripService.build(
      title: trip.title,
      points: [
        TripPoint(tr('Sua posição'), p.latitude, p.longitude, type: StopType.meet),
        for (final x in rest) TripPoint(x.name, x.lat, x.lng, type: x.type),
      ],
      avoidTolls: trip.plan.avoidTolls,
      avoidHighways: trip.plan.avoidHighways,
    );
    if (!mounted) return;
    setState(() => _rerouting = false);
    if (nt == null) {
      _voice.reply(tr('Não consegui tirar a parada. Confira a internet.'));
      return;
    }
    _applyTrip(nt);
    _voice.reply(tr('Parada cancelada: {0}.', [s.name]));
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
          title: tr('Para onde?')),
    ));
    if (picked == null || !mounted) return;
    await _openRouteTo(picked.name, picked.lat, picked.lng);
  }

  /// Segurou no mapa ("Só dirigir"): rota até aquele ponto.
  Future<void> _startRouteAt(LatLng pos) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Traçar rota até aqui?')),
        content: Text(tr('Na prévia dá para incluir paradas antes de iniciar.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Traçar rota'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _openRouteTo(tr('Ponto no mapa'), pos.latitude, pos.longitude);
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
          title: tr('Parada no caminho')),
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
        title: Text(tr('Parada aqui')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('Nome (ex.: posto, almoço)')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isEmpty ? tr('Parada') : ctrl.text),
              child: Text(tr('Incluir na rota'))),
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
  /// Perto (400 m) de uma parada programada da rota ou do comboio, inclusive
  /// a saída e o destino: parar ali é o plano, não um veículo na pista.
  bool _nearPlannedStop(Position p) => [..._stops, ...?_trip?.stops].any((s) =>
      distanceMeters(p.latitude, p.longitude, s.lat, s.lng) < 400);

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
        _nearPlannedStop(p) ||
        AuthService.isAnonymous ||
        !highway ||
        now.difference(_stoppedSince!) < const Duration(minutes: 2) ||
        now.difference(_lastFastAt) > const Duration(minutes: 5) ||
        PoiService.instance.signalNear(p.latitude, p.longitude, meters: 150)) {
      return;
    }
    _myStoppedAlert = 'pendente';
    _hazardSvc
        .report(HazardType.stoppedVehicle, p.latitude, p.longitude, widget.uid,
            heading: _bearing)
        .then((id) {
      _myStoppedAlert = id;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Você está parado: quem vem atrás vê "veículo parado".')),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: tr('Não avisar'),
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
      _voice.reply(tr('No comboio, o destino segue o roteiro do grupo.'));
      return;
    }
    // "UauGo, ir para casa": local salvo (não precisa da pesquisa por voz).
    if (saved != null) {
      await SavedPlacesService.instance.load();
      final p = SavedPlacesService.instance.get(saved);
      if (!mounted) return;
      if (p == null) {
        _voice.reply(tr('Você ainda não salvou {0}. Salve na tela inicial.', [saved == savedHome ? tr('casa') : tr('o trabalho')]));
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
      _voice.reply(tr('Ligue a pesquisa de trajeto por voz nas configurações.'));
      return;
    }
    final text = (await _voiceCmd.recognizeDestination())?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty) {
      _voice.reply(tr('Não entendi o destino.'));
      return;
    }
    await _goToSpoken(text);
  }

  /// Vai ao destino falado: a tela inicial pesquisa e abre a rota (navegando,
  /// pergunta antes de trocar).
  Future<void> _goToSpoken(String text) async {
    if (_isExpedition) {
      _voice.reply(tr('No comboio, o destino segue o roteiro do grupo.'));
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
      _voice.reply(tr('Trocar a rota para {0}? Diga sim ou não.', [text]));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          _voiceConfirmCtx = ctx;
          return AlertDialog(
            title: Text(tr('Trocar a rota?')),
            content: Text(tr('Novo destino: "{0}".\nA rota atual será encerrada.', [text])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Não'))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr('Sim, trocar'))),
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
                child: Text(tr('Encontrados {0}', [_isExpedition ? '' : tr('(toque para incluir)')]),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: tr('Fechar'),
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
                  if (_found[i].onRoute) tr('no caminho'),
                  if (_found[i].price == 'PRICE_LEVEL_INEXPENSIVE') 'barato',
                  if (_found[i].open == true) 'aberto',
                ].join(' · ')),
                trailing: _isExpedition
                    ? null
                    : FilledButton.tonal(
                        onPressed: () => _addFoundStop(_found[i]),
                        child: Text(tr('Incluir'))),
              ),
          ]),
        ),
      ),
    );
  }

  // ---- Modo carro (Android Auto)

  /// Próxima manobra "de verdade" (pula "Continue para...") e a distância
  /// até ela (pela rota, quando houver).
  /// v2: a visão 3D cabe aqui? (sozinho, primeira pessoa, com rota)
  bool get _canShow3d =>
      !_isExpedition && _view == _MapView.solo && _routeRecs.length >= 2 &&
      (_navigating || _sim != null) && _online3d;

  /// O 3D só funciona com internet. Duas falhas seguidas (30 s) para um
  /// túnel curto não ficar trocando de tela.
  bool _online3d = true;
  int _offlineChecks = 0;
  Timer? _onlineTimer;
  Timer? _routeTrafficTimer;

  Future<void> _checkOnline() async {
    var ok = false;
    try {
      final r = await InternetAddress.lookup('firebasestorage.googleapis.com')
          .timeout(const Duration(seconds: 4));
      ok = r.isNotEmpty;
    } catch (_) {}
    if (!mounted) return;
    _offlineChecks = ok ? 0 : _offlineChecks + 1;
    final on = ok || _offlineChecks < 2;
    if (on == _online3d) return;
    final showing = _show3d;
    setState(() => _online3d = on);
    _sendMode3dToCar();
    if (on) {
      _sim3dSig = ''; // página nova: manda a rota de novo
      WidgetsBinding.instance.addPostFrameCallback((_) => _feed3d());
    } else if (showing) {
      _showTrafficBanner(tr('📵 Sem internet: voltei para o mapa. O 3D volta com a conexão.'));
      if (_me case final p?) _updateCamera(p, force: true);
    }
  }

  /// v2: escolha da visão (3D sempre / mapa / mapa + 3D nas saídas).
  Future<void> _chooseMode3d() async {
    final m = await showModalBottomSheet<_Mode3d>(
      context: context,
      builder: (ctx) => SafeArea(
        // Deitado a tela é baixa: a lista precisa rolar.
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(tr('Visão da navegação'), style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(tr('O 3D só funciona com internet.')),
            ),
            for (final x in _Mode3d.values)
              ListTile(
                leading: Icon(x.icon),
                title: Text(x.label),
                subtitle: Text(x.hint),
                trailing: x == _mode3d ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, x),
              ),
          ]),
        ),
      ),
    );
    if (m != null && mounted) _setMode3d(m);
  }

  void _sendMode3dToCar() => CarService.instance.mode3d(switch (_mode3d) {
        _ when !_online3d => 0,
        _Mode3d.map => 0,
        _Mode3d.exits => 1,
        _Mode3d.always => 2,
      });

  void _setMode3d(_Mode3d m, {bool save = true}) {
    setState(() => _mode3d = m);
    _sendMode3dToCar();
    _manual3dUntil = DateTime(0);
    if (save) SharedPreferences.getInstance().then((p) => p.setString('mode3d', m.name));
    switch (m) {
      case _Mode3d.always:
        _set3d(true);
      case _Mode3d.map:
        _set3d(false);
      case _Mode3d.exits:
        final p = _me;
        _set3d(p != null && _nearExit(p));
    }
  }

  /// Modo "nas saídas": 3D de 400 m antes até 400 m depois da manobra.
  static const _exit3dMeters = 400.0;

  /// Última saída/rotatória em que entrou no 3D: ponto e posição na rota.
  (double, double)? _exit3dPoint;
  double? _exit3dAlong;

  /// Dentro da faixa de 400 m antes ou depois de saída, bifurcação ou
  /// rotatória? Depois de passar, conta pela rota (ou em linha reta, se
  /// saiu dela).
  bool _nearExit(Position p) {
    if (!_navigating && _sim == null) return false;
    final nav = _nav;
    final ra = _riderAlong;
    if (nav != null && !nav.finished) {
      // Olha as próximas manobras (não só a primeira): às vezes vem um
      // "continue"/"siga" curto antes da saída.
      for (var i = nav.nextIndex; i < nav.steps.length && i < nav.nextIndex + 4; i++) {
        final s = nav.steps[i];
        final d = (ra != null ? nav.routeDistanceTo(i, ra) : null) ??
            distanceMeters(p.latitude, p.longitude, s.lat, s.lng);
        if (d > _exit3dMeters) break;
        if (_isExitStep(s)) {
          _exit3dPoint = (s.lat, s.lng);
          _exit3dAlong = ra == null ? null : ra + d;
          return true;
        }
      }
    }
    final pt = _exit3dPoint;
    if (pt == null) return false;
    final a = _exit3dAlong;
    final inside = ra != null && a != null
        ? ra <= a + _exit3dMeters
        : distanceMeters(p.latitude, p.longitude, pt.$1, pt.$2) <= _exit3dMeters;
    if (!inside) {
      _exit3dPoint = null;
      _exit3dAlong = null;
    }
    return inside;
  }

  /// Saída, rampa, bifurcação ou "mantenha-se" (Google em português ou
  /// inglês: o texto segue o idioma do app). Curva leve em via rápida
  /// (acima de 50 km/h) também costuma ser uma saída.
  bool _isExitStep(NavStep s) {
    final m = s.maneuver;
    if (RegExp('ramp|fork|keep|roundabout').hasMatch(m)) return true;
    if (m.startsWith('turn-slight') && _speedMs > 14) return true;
    return RegExp(
            r'sa[íi]da|bifurca|rotat[óo]ria|mantenha-se|pegue a rampa|pegue o acesso|'
            r'\bexit\b|\bfork\b|\bkeep (left|right)\b|take the ramp|slip road|roundabout',
            caseSensitive: false)
        .hasMatch(s.text);
  }

  /// Modo "nas saídas": entra no 3D perto de saídas e volta ao mapa depois.
  void _autoExit3d(Position p) {
    if (_mode3d != _Mode3d.exits || DateTime.now().isBefore(_manual3dUntil)) return;
    _set3d(_nearExit(p));
  }

  /// v2: painel do 3D (no lugar do velocímetro e da faixa da próxima curva).
  void _feedHud3d() {
    final p = _me;
    final kmh = p == null ? null : _speedMs * 3.6;
    final level = kmh == null
        ? SpeedLevel.normal
        : SpeedAlerter.level(kmh, _roadLimit, _speedSvc.settings.value.personalMax);
    final turn = p != null && (_sim != null ? _simStarted : _navigating) ? _upcomingTurn(p) : null;
    final nav = _nav;
    final last = turn != null && nav != null && identical(turn.step, nav.steps.last);
    String? eta, rem;
    final w = _walker, trip = _trip;
    if (w != null && trip != null) {
      final left = p == null ? w.length : w.remainingFrom(p.latitude, p.longitude);
      rem = formatDistance(left.round());
      if (!widget.simulate) {
        final secs = (left / (_etaSpeed ?? trip.averageSpeed)).round();
        eta = formatTime(DateTime.now().add(Duration(seconds: secs)));
      }
    }
    _sim3d.hud({
      'kmh': kmh?.round(),
      'lim': _roadLimit?.kmh,
      'over': level != SpeedLevel.normal,
      if (turn != null) ...{
        'm': turn.step.maneuver,
        'd': turn.meters.round(),
        't': turn.step.text,
        'last': last,
      },
      'eta': eta,
      'rem': rem,
    });
  }

  // v2: botões que o painel do 3D não pode cobrir (medidos na tela).
  final _kWeb3d = GlobalKey(), _kLeftCol = GlobalKey(), _kRightCol = GlobalKey();
  final _kBottomLeft = GlobalKey(), _kSimBar = GlobalKey();

  /// v2: posição do painel do 3D em função dos outros botões: entre a coluna
  /// da esquerda e a da direita, e acima do que estiver embaixo (alerta,
  /// câmera, controles da simulação). Se os botões mudarem de lugar ou de
  /// tamanho, o painel acompanha.
  void _layoutHud3d() {
    if (!mounted || !_hud3d) return;
    Rect? rect(GlobalKey k) {
      final b = k.currentContext?.findRenderObject();
      if (b is! RenderBox || !b.attached || !b.hasSize) return null;
      return b.localToGlobal(Offset.zero) & b.size;
    }
    final web = rect(_kWeb3d);
    if (web == null) return;
    final lc = rect(_kLeftCol), rc = rect(_kRightCol);
    // Sempre entre as colunas (nunca por baixo delas): se o espaço for
    // pequeno, a página compacta o painel para caber.
    final left = (lc != null ? lc.right : web.left) + 6;
    final right = (rc != null ? rc.left : web.right) - 6;
    // O mais alto dos botões de baixo que ficam na faixa do painel.
    var top = web.bottom - 8;
    for (final k in [_kBottomLeft, _kSimBar]) {
      final r = rect(k);
      if (r == null || r.right <= left || r.left >= right) continue;
      top = min(top, r.top);
    }
    _sim3d.layout(
      left: left - web.left,
      right: web.right - right,
      bottom: web.bottom - top + 8,
    );
  }

  /// v2: rodovias reais (faixas e saídas) em volta do piloto, a cada 1 km.
  (double, double)? _roads3dAt;
  String _roads3dSig = '';
  bool _roads3dBusy = false;
  void _feedRoads3d() {
    final p = _me;
    if (p == null) return;
    ViasService.instance.ensure(p.latitude, p.longitude);
    final at = _roads3dAt;
    final moved = at == null ||
        distanceMeters(at.$1, at.$2, p.latitude, p.longitude) > 1000;
    if ((!moved && _roads3dSig == _sim3dSig) || _roads3dBusy) return;
    _roads3dBusy = true;
    final sig = _sim3dSig;
    ViasService.instance.nearJson(p.latitude, p.longitude, 2200).then((json) {
      _roads3dBusy = false;
      // null: ainda baixando (ou fora dos estados com pacote).
      if (json == null || !mounted) return;
      _roads3dAt = (p.latitude, p.longitude);
      _roads3dSig = sig;
      _sim3d.roads(json);
    }, onError: (_) => _roads3dBusy = false);
  }

  /// v2: o painel do 3D substitui o velocímetro e a faixa da próxima curva.
  bool get _hud3d =>
      _show3d && _canShow3d &&
      !(CarService.instance.connected.value && AppSettings.instance.lightMode);

  /// v2: liga/desliga a visão 3D. Voltando ao mapa, ele já vem acompanhando.
  void _set3d(bool on) {
    if (on == _show3d) return;
    setState(() {
      _show3d = on;
      _follow = true;
      if (!on) _zoomOffset = 0;
    });
    if (on) {
      _sim3dSig = ''; // página nova: manda a rota de novo
      WidgetsBinding.instance.addPostFrameCallback((_) => _feed3d());
    } else if (_me case final p?) {
      _updateCamera(p, force: true);
    }
  }

  bool _off3d = false;
  int _off3dCount = 0;

  /// A barra da simulação pulou de lugar (para frente ou para trás): recomeça
  /// a posição na rota, as manobras e o estado de "fora da rota".
  void _afterSimJump() {
    _proj = null;
    _riderAlong = null;
    _navSynced = false;
    _offRoute = false;
    _offRouteCount = 0;
    _off3d = false;
    _off3dCount = 0;
    _roads3dAt = null;
    _exit3dPoint = null;
    _exit3dAlong = null;
  }

  /// v2: a cena 3D solta da rota e segue o GPS? Só com 3 leituras seguidas,
  /// longe da rota (conforme a precisão do GPS) e indo para outra direção
  /// (ou bem longe dela). Sem internet o GPS piora e "pula": uma leitura
  /// ruim não pode tirar a cena da rota.
  bool _isOff3d(({double along, double offset, double bearing}) pr, Position? me) {
    if (me == null) return _off3d;
    final acc = me.accuracy;
    if (_off3d) {
      if (pr.offset < max(15.0, acc)) {
        _off3d = false;
        _off3dCount = 0;
      }
      return _off3d;
    }
    // Rotatória/curva perto: a linha da rota corta a rotatória e o rumo muda
    // a cada segundo; a cena soltava da rota, seguia o GPS e voltava, "indo e
    // voltando" (05/11). Ali só solta bem longe e depois de mais leituras.
    final curve = (_nav?.steps ?? const <NavStep>[]).any((st) =>
        st.maneuver.isNotEmpty &&
        distanceMeters(me.latitude, me.longitude, st.lat, st.lng) < 150);
    final far = pr.offset > (curve ? max(45.0, acc * 2) : max(18.0, acc * 1.5));
    final turned = _speedMs > 2 &&
        angleDiff(me.heading >= 0 ? me.heading : _bearing, pr.bearing) > 30;
    _off3dCount = far && (turned || pr.offset > max(60.0, acc * 2.5)) ? _off3dCount + 1 : 0;
    if (_off3dCount >= (curve ? 5 : 3)) _off3d = true;
    return _off3d;
  }

  /// v2: mantém a visão 3D com a rota, as manobras e a posição atuais.
  void _feed3d() {
    final car = CarService.instance.connected.value;
    if (!_canShow3d || (!_show3d && !car)) return;
    final steps = _nav?.steps ?? const <NavStep>[];
    final sig = '$_routeSig|${steps.length}';
    if (sig != _sim3dSig) {
      _sim3dSig = sig;
      _sim3d.route(_routeRecs, steps, _trip?.title ?? '');
    }
    _sim3d.dark(_darkMap);
    final pr = _proj;
    if (pr != null) {
      final me = _me;
      _sim3d.update(pr.along, _speedMs, _isOff3d(pr, me),
          lat: me?.latitude, lng: me?.longitude, heading: _bearing);
    }
    _feedHud3d();
    _feedRoads3d();
    final me = _me;
    if (me != null && DateTime.now().difference(_alerts3dAt).inSeconds >= 4) {
      _alerts3dAt = DateTime.now();
      _sim3d.alerts(_alertsFor3d(me));
    }
  }

  /// v2: o que vira objeto na pista 3D (a página só mostra o que cai na rota).
  List<Map<String, Object?>> _alertsFor3d(Position p) => [
        // Só os radares que o app também avisa: com limite ou sentido e na
        // pista da rota (não na marginal/alça ao lado). Antes o 3D mostrava
        // radar de 40 que não existia na pista (05/11).
        for (final r in _radarMarkers.take(40))
          if (!r.unverified && (_walker == null || _radarOnRouteRoad(r, _walker!)))
          {
            'la': r.lat,
            'lo': r.lng,
            'k': switch (r.kind) {
              RadarKind.fixed => 'radar',
              RadarKind.section => 'radarAvg',
              RadarKind.redLight => 'radarRed',
            },
            'lim': r.limit,
            'dir': r.direction,
          },
        for (final q in PoiService.instance.near(p.latitude, p.longitude, 3000))
          if (sameDirection(q.heading, _bearing, _speedMs))
          {
            'la': q.lat,
            'lo': q.lng,
            'k': switch (q.kind) {
              PoiKind.bump => 'bump',
              PoiKind.policePost => 'post',
              PoiKind.toll => 'toll',
              PoiKind.tollMotoFree => 'tollMoto',
            },
          },
        for (final h in _activeHazards)
          if (distanceMeters(p.latitude, p.longitude, h.lat, h.lng) < 5000 &&
              _sameSide(p, h))
            {
              'la': h.lat,
              'lo': h.lng,
              'k': switch (h.type) {
                HazardType.radar => 'mradar',
                HazardType.fixedRadar => 'radar',
                _ => h.type.name,
              },
              'e': h.type.emoji,
              'n': h.type.label,
            },
        for (final q in _signalMarkers.take(40)) {'la': q.$1, 'lo': q.$2, 'k': 'signal'},
      ];

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

  /// A imagem do veículo no carro é a mesma do celular (foto ou ícone).
  String _carBikeSig = '';
  void _sendVehicleToCar() {
    final sig = _myBike.cacheKey;
    if (sig == _carBikeSig) return;
    _carBikeSig = sig;
    bikeBadgePng(_myBike).then(CarService.instance.vehicleImage).catchError((_) {});
  }

  /// Pins da tela do carro: radares (1 fixo, 2 média, 3 sinal) e postos
  /// policiais (4), como no celular.
  void _sendPoisToCar() {
    if (!CarService.instance.connected.value) return;
    // Com rota: só os radares à frente, na via e no sentido dela (a mesma
    // regra dos avisos). Sem rota, os mais próximos.
    final w = _walker, pr = _proj;
    final byRoute = w != null && pr != null && pr.offset < 60 &&
        (_navigating || _sim != null) && !_offRoute;
    final radars = byRoute
        ? _radarMarkers.where((r) =>
            radarAheadOnRoute(r,
                    project: w.project, riderAlong: pr.along, range: 10000) !=
                null &&
            _radarOnRouteRoad(r, w))
        : _radarMarkers.take(40);
    CarService.instance.pois([
      for (final r in radars)
        (r.lat, r.lng, switch (r.kind) {
          RadarKind.fixed => 1,
          RadarKind.section => 2,
          RadarKind.redLight => 3,
        }),
      for (final q in _policeMarkers.take(20)) (q.lat, q.lng, 4),
    ]);
  }

  /// Aviso curto na faixa do grupo do carro (pedidos e confirmações).
  void _noteToCar(String text) {
    _carNote = text;
    _carNoteUntil = DateTime.now().add(const Duration(seconds: 15));
    _sendGroupToCar();
  }

  String? _carNote;
  DateTime _carNoteUntil = DateTime(0);

  /// Expedição na tela do carro: botões do grupo e a faixa (o que importa
  /// mais vem primeiro: meu SOS, SOS de outro piloto, pedido a confirmar).
  void _sendGroupToCar() {
    if (!CarService.instance.connected.value) return;
    final car = CarService.instance;
    if (!_isExpedition) return car.group(on: false);
    final mine = _alerts.where((a) => a.uid == widget.uid).firstOrNull;
    if (mine != null) {
      return car.group(on: true, urgent: true, action: 'sosCancel:${mine.id}',
          text: tr('🚨 SOS enviado · toque para cancelar'));
    }
    final other = _alerts.firstOrNull;
    if (other != null) {
      return car.group(on: true, urgent: true,
          text: tr('🚨 SOS: {0}{1}', [other.name, _dist(other.lat, other.lng)]));
    }
    final ack = _pendingAck;
    if (ack != null) {
      return car.group(on: true, action: 'ack:${ack.id}',
          text: tr('{0} {1} · toque para confirmar',
              [ack.kind.emoji, groupRequestSpeech(ack.name, ack.kind)]));
    }
    final note = DateTime.now().isBefore(_carNoteUntil) ? _carNote : null;
    car.group(on: true, text: note);
  }

  /// Alertas da comunidade na tela do carro: os mais perto, com os do piloto
  /// marcados (ele pode remover lá).
  void _sendHazardsToCar() {
    if (!CarService.instance.connected.value) return;
    final list = [..._activeHazards];
    final p = _me;
    if (p != null) {
      double d(Hazard h) => Geolocator.distanceBetween(
          p.latitude, p.longitude, h.lat, h.lng);
      list.sort((a, b) => d(a).compareTo(d(b)));
    }
    CarService.instance.hazards([
      for (final h in list.take(30))
        (h.id, h.lat, h.lng, h.type.emoji, h.type.label, h.createdBy == widget.uid),
    ]);
  }

  /// Manda para a tela do carro a manobra, a chegada, o radar e a posição.
  void _sendToCar(Position p) {
    if (!CarService.instance.connected.value) return;
    _sendVehicleToCar();
    _sendGroupToCar();
    final turn = _navigating || _sim != null ? _upcomingTurn(p) : null;
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
      // A faixa do radar já leva a distância: sem pílula repetida.
      alert: pill == null || _bannerRadar != null
          ? null
          : tr('{0} {1}{2}em {3} m', [pill.emoji, pill.kmh ?? '', pill.kmh != null ? ' ' : '', pill.m]),
      // Faixa amarela (igual à do celular): radar/polícia/perigo à frente.
      banner: _radarBanner != null
          ? '${_radarBanner!.emoji} ${_radarBanner!.text}'
              '${_bannerRadar != null ? ' · ${_bannerRadar!.m} m' : ''}'
          : (_shownHazard != null
              ? '${_shownHazard!.type.emoji} ${_shownHazard!.type.label} a '
                  '${_dist(_shownHazard!.lat, _shownHazard!.lng).replaceFirst(' · ', '')}'
              : null),
      vehicle: _myBike.style.isMoto ? '🏍️' : (_myBike.style.isHeavy ? '🚚' : '🚗'),
    );
  }

  /// Carro conectou (ou reconectou): reenvia a rota e os pins.
  void _onCarConnected() {
    if (!mounted) return;
    setState(() {}); // o 3D do celular sai/volta com o carro
    if (!CarService.instance.connected.value) return;
    if (_routeRecs.length >= 2) CarService.instance.route(_routeRecs);
    _sendPoisToCar();
    _sendHazardsToCar();
    _sendGroupToCar();
    _sendMode3dToCar();
    _carBikeSig = ''; // reconectou: manda a imagem do veículo de novo
    _sendVehicleToCar();
    _sim3d.resendToCar();
    _feed3d();
  }

  /// Botão da tela do carro.
  Future<void> _onCarAction(String a) async {
    if (!mounted) return;
    // Destino pedido ao Assistente/Gemini no carro: rota nova, inicia sozinha.
    if (a.startsWith('navigate:')) {
      if (_isExpedition) {
        CarService.instance.toast(tr('No comboio, o destino segue o roteiro do grupo.'));
        return;
      }
      await _voice.stop();
      CarService.instance.clearNavigation();
      if (!mounted) return;
      Navigator.of(context).pop();
      // Depois de fechar a tela (a inicial só aceita quando está na frente).
      final geo = a.substring(9);
      Future.delayed(const Duration(milliseconds: 700), () {
        SharedPlaceService.instance.fromVoice = true;
        SharedPlaceService.instance.pending.value = geo;
      });
      return;
    }
    switch (a) {
      // Grupo pela tela do carro. Na simulação nada vai para o grupo.
      case 'sos' when _sim != null:
        CarService.instance.toast(tr('Na simulação nada é enviado ao grupo.'));
      case final x when x.startsWith('group:') && _sim != null:
        CarService.instance.toast(tr('Na simulação nada é enviado ao grupo.'));
      case 'sos':
        await _sendSos();
        CarService.instance.toast(tr('SOS enviado aos pilotos'));
      case final x when x.startsWith('sosCancel:'):
        _svc.resolveAlert(_code, x.substring(10));
        CarService.instance.toast(tr('SOS cancelado'));
      case final x when x.startsWith('group:'):
        final kind = GroupRequest.values
            .where((k) => k.name == x.substring(6))
            .firstOrNull;
        if (kind == null) return;
        await _sendGroupRequest(kind);
        CarService.instance.toast(tr('Enviado ao grupo: {0}', [kind.label]));
      case final x when x.startsWith('ack:'):
        final r = _pendingAck;
        if (r == null || r.id != x.substring(4)) return;
        await _ackRequest(r);
        CarService.instance.toast(tr('Pedido confirmado'));
      // Remover o próprio alerta pela tela do carro.
      case final x when x.startsWith('unhazard:'):
        final id = x.substring(9);
        final h = _hazards.where((e) => e.id == id).firstOrNull;
        if (h == null || h.createdBy != widget.uid) return;
        _hazardSvc.dismiss(h, force: true);
        setState(() {
          if (_shownHazard?.id == id) _shownHazard = null;
          _hazards = [for (final e in _hazards) if (e.id != id) e];
        });
        _sendHazardsToCar();
        CarService.instance.toast(tr('Alerta removido'));
      // Alertas do carro: sem conta ou na simulação nada é enviado (avisa
      // em vez de dizer "enviado").
      case 'radar' || 'hazard' when _sim != null:
        CarService.instance.toast(tr('Na simulação os alertas não são enviados.'));
      case final x when x.startsWith('hazard:') && _sim != null:
        CarService.instance.toast(tr('Na simulação os alertas não são enviados.'));
      case 'radar' || 'hazard' when AuthService.isAnonymous:
        CarService.instance.toast(tr('Entre na sua conta no celular para marcar alertas'));
      case final x when x.startsWith('hazard:') && AuthService.isAnonymous:
        CarService.instance.toast(tr('Entre na sua conta no celular para marcar alertas'));
      case 'radar':
        await _reportHazard(HazardType.radar);
        CarService.instance.toast(tr('Alerta enviado: radar móvel'));
      case 'hazard':
        await _reportHazard(HazardType.danger);
        CarService.instance.toast(tr('Alerta enviado: perigo na pista'));
      // Lista de alertas do carro: "hazard:police", "hazard:pothole"...
      case final x when x.startsWith('hazard:'):
        final t = HazardType.fromName(x.substring(7));
        if (t == null) return;
        await _reportHazard(t);
        CarService.instance.toast(tr('Alerta enviado: {0}', [t.label]));
      case 'stop':
        if (!_navigating) {
          CarService.instance.toast(tr('Nenhuma navegação em andamento'));
          return;
        }
        // Para já (voz, narração e tela do carro), mesmo com o celular
        // bloqueado: antes só encerrava ao desbloquear o celular.
        setState(() {
          _navigating = false;
          _applyWakelock();
        });
        if (_helpTarget != null) _endHelp();
        await _voice.stop();
        CarService.instance.clearNavigation();
        CarService.instance.toast(tr('Navegação encerrada'));
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

  /// "Dirigir agora" sem destino: só radares, perigos e velocidade.
  bool get _justDriving => !_isExpedition && _trip == null && _sim == null;

  /// Rota em andamento: sair da tela pede confirmação.
  bool get _confirmExit =>
      _sim != null ? _simStarted : _navigating && !_arrivedAtDestination;

  /// "Voltar" durante a navegação: pergunta se quer mesmo sair (a rota é
  /// encerrada). Na expedição, sair do mapa não tira do comboio.
  Future<void> _askExitNavigation() async {
    // "Voltar" não encerra a rota sozinho: minimizar mantém tudo como
    // está (ao abrir o app, volta para cá); encerrar só se o piloto pedir.
    if (_sim != null) {
      // Simulação: sair perde o andamento, então pergunta antes.
      final leave = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Sair da simulação?')),
          content: Text(tr('A simulação em andamento será perdida.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Continuar'))),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Sair'))),
          ],
        ),
      );
      if (leave != true || !mounted) return;
      await _voice.stop();
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_justDriving ? tr('Sair do Dirigir agora?') : tr('Sair da navegação?')),
        content: Text(_justDriving
            ? tr('Minimizar ou Encerrar voltam para a tela inicial e desligam os avisos.')
            : _isExpedition
                ? tr('Minimizar volta para a tela inicial; você continua no comboio. Encerrar para a navegação.')
                : tr('Minimizar volta para a tela inicial e guarda a rota para você retomar (a voz e os avisos param até lá). Encerrar apaga a rota.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'stay'),
              child: Text(tr('Continuar'))),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, 'end'),
              child: Text(tr('Encerrar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'min'),
              child: Text(tr('Minimizar'))),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    // Minimizar: volta para a tela inicial; ela pergunta se quer retomar.
    if (choice == 'min' && !_isExpedition) MinimizedTrip.trip.value = _trip;
    await _voice.stop();
    CarService.instance.clearNavigation();
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------ navegação

  /// "Iniciar" na expedição: liga a narração, o painel de manobras e a
  /// primeira pessoa.
  void _startNavigation() {
    AnalyticsService.event('expedition_start');
    if (_nav == null) {
      _snack(_isLeader
          ? tr('Monte o roteiro primeiro (botão de rota no topo)')
          : tr('O líder ainda não montou o roteiro'));
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
    ActiveTrip.clear();
    setState(() {
      _navigating = false;
      _applyWakelock();
      _offRoute = false;
    });
    final sim = _sim;
    if (sim != null) {
      sim.paused.value = true;
      _voice.narrate(tr('Você chegou ao destino: {0}. Fim da simulação.', [s.name]),
          force: true);
      return;
    }
    if (_isExpedition) {
      _voice.alert(tr('Você chegou ao destino: {0}. Navegação encerrada.', [s.name]));
      _snack(tr('🏁 Chegada! A navegação foi encerrada; você continua no comboio.'));
      return;
    }
    _voice.alert(tr('Você chegou ao destino: {0}. Viagem encerrada.', [s.name]));
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
          title: Text(tr('🏁 Você chegou!')),
          content: Text(tr('{0}\n\nA navegação foi encerrada e a viagem ficou salva em "Minhas viagens".\n\nEsta tela fecha sozinha em 20 segundos.', [s.name])),
          actions: [
            if (_tollsSeen.isNotEmpty)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'tolls'),
                  child: Text(tr('Conferir pedágios ({0})', [_tollsSeen.length]))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'stay'),
                child: Text(tr('Ficar no mapa'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, 'close'),
                child: Text(tr('Fechar'))),
          ],
        );
      },
    );
    autoClose = false;
    timer.cancel();
    if (!mounted) return;
    if (choice == 'tolls') {
      // Parado no destino: confere os pedágios da viagem e depois fecha.
      await TollConfirmSheet.show(context, _tollsSeen.values.toList());
      if (mounted) Navigator.of(context).pop();
      return;
    }
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
        title: Text(_justDriving ? tr('Sair do Dirigir agora?') : tr('Encerrar navegação?')),
        content: Text(_justDriving
            ? tr('Os avisos de radar, perigos e velocidade param.')
            : _isExpedition
                ? tr('A narração e o painel de manobras param. Você continua no comboio, compartilhando a posição com o grupo.')
                : tr('A navegação será encerrada.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Continuar'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Encerrar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_helpTarget != null) _endHelp();
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

  /// Ícone de música: o do app que está tocando (abre/fecha os controles)
  /// ou o de liberar/abrir o app de música.
  Widget _musicButton() => ValueListenableBuilder<MediaState?>(
        valueListenable: MediaService.instance.state,
        builder: (_, m, __) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: m != null && m.title.isNotEmpty
              // Tocando: ícone redondo do app (Spotify...); o toque
              // abre/fecha os controles.
              ? FloatingActionButton.small(
                  heroTag: 'music',
                  tooltip: m.artist.isEmpty ? m.title : '${m.title} · ${m.artist}',
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  backgroundColor: Colors.white,
                  onPressed: () => setState(() => _musicOpen = !_musicOpen),
                  child: m.appIcon != null
                      ? Image.memory(m.appIcon!, width: 40, height: 40, gaplessPlayback: true)
                      : const Icon(Icons.music_note, color: Colors.black87),
                )
              : FloatingActionButton.small(
                  heroTag: 'music',
                  tooltip: tr('Música'),
                  onPressed: _onMusicButton,
                  child: const Icon(Icons.music_note),
                ),
        ),
      );

  /// Folga lateral: só a da barra de navegação do Android (≥ 40 px); a da
  /// câmera/canto (menor) não afasta os botões da borda.
  static double _sideInset(double v) => v >= 40 ? v : 0;

  /// Botão de música: sem a opção ou sem o acesso do Android, explica e leva
  /// à liberação; liberado e nada tocando, abre o app de música.
  Future<void> _onMusicButton() async {
    final s = AppSettings.instance;
    final access = await MediaService.instance.hasAccess();
    if (!mounted) return;
    if (s.mediaControls.value && access) {
      await MediaService.instance.start();
      if (!await MediaService.instance.openMusicApp() && mounted) {
        _snack(tr('Nenhum app de música encontrado no celular.'));
      }
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Controles de música no mapa')),
        content: Text(tr('Para ver a música e usar anterior, tocar/pausar e próxima sem sair do mapa, libere o UauGo em "Acesso a notificações" na próxima tela. O UauGo só vê a música que está tocando; nada sai do celular.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Agora não'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Liberar'))),
        ],
      ),
    );
    if (go != true) return;
    await s.setMediaControls(true);
    if (access) {
      await MediaService.instance.start();
    } else {
      // Ao voltar para o app, _resumeWork liga o acompanhamento.
      await MediaService.instance.openSettings();
    }
  }

  /// Posição da pílula de música (fração da área do mapa); o piloto
  /// arrasta e ela fica guardada no celular.
  /// null = ainda não arrastou: abre ao lado do ícone (alto, à direita).
  Offset? _musicPos;

  /// Controles da música abertos (o ícone do app abre e fecha).
  bool _musicOpen = false;
  bool _musicPosLoaded = false;
  static const _musicPillSize = Size(212, 56);

  Future<void> _loadMusicPos() async {
    final p = await SharedPreferences.getInstance();
    final x = p.getDouble('musicPillX'), y = p.getDouble('musicPillY');
    if (x != null && y != null && mounted) setState(() => _musicPos = Offset(x, y));
  }

  /// Pílula compacta da música tocando (aberta pelo ícone do app): capa
  /// (toque = tocar/pausar; segurar mostra a música), anterior, próxima e
  /// fechar. Arrastável para qualquer canto.
  Widget _musicPill(Size area) => ValueListenableBuilder<MediaState?>(
        valueListenable: MediaService.instance.state,
        builder: (_, m, __) {
          if (m == null || m.title.isEmpty || !_musicOpen) return const SizedBox.shrink();
          if (!_musicPosLoaded) {
            _musicPosLoaded = true;
            _loadMusicPos();
          }
          final w = _musicPillSize.width, h = _musicPillSize.height;
          final maxX = (area.width - w).clamp(0.0, double.infinity);
          final maxY = (area.height - h).clamp(0.0, double.infinity);
          final pos = _musicPos;
          final left = pos == null
              ? (area.width - 6 - 48 - 8 - w).clamp(0.0, maxX)
              : (pos.dx * area.width - w / 2).clamp(0.0, maxX);
          final top = pos == null ? 8.0 : (pos.dy * area.height - h / 2).clamp(0.0, maxY);
          final scheme = Theme.of(context).colorScheme;
          Widget btn(IconData i, String c, String tip) => IconButton(
                tooltip: tip,
                iconSize: 26,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => MediaService.instance.command(c),
                icon: Icon(i),
              );
          return Stack(children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => _musicPos = Offset(
                    ((left + w / 2 + d.delta.dx) / area.width).clamp(0.0, 1.0),
                    ((top + h / 2 + d.delta.dy) / area.height).clamp(0.0, 1.0))),
                onPanEnd: (_) async {
                  final pos = _musicPos;
                  if (pos == null) return;
                  final p = await SharedPreferences.getInstance();
                  await p.setDouble('musicPillX', pos.dx);
                  await p.setDouble('musicPillY', pos.dy);
                },
                child: Material(
                  elevation: 6,
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(h / 2),
                  child: SizedBox(
                    width: w,
                    height: h,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      btn(Icons.skip_previous, 'previous', tr('Anterior')),
                      Tooltip(
                        message: m.artist.isEmpty ? m.title : '${m.title} · ${m.artist}',
                        triggerMode: TooltipTriggerMode.longPress,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => MediaService.instance.command('toggle'),
                          child: ClipOval(
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Stack(fit: StackFit.expand, children: [
                                if (m.art != null)
                                  Image.memory(m.art!, fit: BoxFit.cover, gaplessPlayback: true)
                                else
                                  ColoredBox(color: scheme.primaryContainer),
                                Container(color: Colors.black.withValues(alpha: m.art != null ? 0.35 : 0)),
                                Icon(m.playing ? Icons.pause : Icons.play_arrow,
                                    size: 28, color: m.art != null ? Colors.white : scheme.onPrimaryContainer),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      btn(Icons.skip_next, 'next', tr('Próxima')),
                      IconButton(
                        tooltip: tr('Fechar'),
                        iconSize: 22,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        onPressed: () => setState(() => _musicOpen = false),
                        icon: const Icon(Icons.close),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      );

  /// "Encerrar" no canto superior (barra do título): pequeno, vermelho, só
  /// o ícone de sair; pede confirmação ao tocar.
  Widget _exitNavButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: IconButton.filled(
          tooltip: _justDriving ? tr('Sair do Dirigir agora?') : tr('Encerrar navegação'),
          style: IconButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(40, 40)),
          onPressed: _stopNavigation,
          icon: Icon(_isExpedition ? Icons.close : Icons.logout, size: 22),
        ),
      );

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
        label: Text(tr('Iniciar simulação'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );
    }
    // Navegando, o "Encerrar" fica no canto de cima (_exitNavButton).
    if (_navigating) return null;
    if (_isExpedition && _routeRecs.length >= 2) {
      // Compacto: não encosta no perigo/radar móvel do canto esquerdo.
      return FilledButton.icon(
        style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
        onPressed: _startNavigation,
        icon: const Icon(Icons.navigation, size: 18),
        label: Text(tr('Iniciar'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      );
    }
    return null;
  }

  /// "Chegada 10:43 · faltam 85 km" (navegação sozinho e simulação).
  String _etaText() {
    final w = _walker, p = _me, trip = _trip;
    if (w == null || trip == null) return tr('Radares, perigos e velocidade');
    final left = p == null ? w.length : w.remainingFrom(p.latitude, p.longitude);
    final km = formatDistance(left.round());
    if (widget.simulate) return tr('Faltam {0}', [km]);
    // Com o trânsito conferido, usa a velocidade efetiva de agora.
    final secs = (left / (_etaSpeed ?? trip.averageSpeed)).round();
    final eta = DateTime.now().add(Duration(seconds: secs));
    return tr('Chegada {0} · {1}\nFaltam {2}{3}', [formatTime(eta), formatDuration(secs), km, '']);
  }

  /// Expedição: navegando, chegada e quanto falta pela rota do grupo (mesmo
  /// numa rota própria para voltar a ela), e o código; parado, só o código.
  String _expeditionSubtitle() {
    final w = _expWalker ?? _walker, p = _me;
    var dist = 0, dur = 0;
    for (final s in _stops) {
      dist += s.legDistanceM;
      dur += s.legDurationS;
    }
    final cost = _expCost == null ? '' : ' · ~${formatMoney(_expCost!)}';
    if (w == null || _arrivedAtDestination) return tr('Código: {0}', [_code]);
    if (!_navigating) {
      // Antes de iniciar: o roteiro todo (km, tempo e custo estimado).
      if (dist <= 0) return tr('Código: {0}', [_code]);
      return tr('{0} · {1}{2}\nCódigo {3}', [formatDistance(dist), formatDuration(dur), cost, _code]);
    }
    final left = p == null ? w.length : w.remainingFrom(p.latitude, p.longitude);
    // Velocidade: a do trânsito conferido ou a média planejada do roteiro.
    final speed = _etaSpeed ?? (dur > 0 ? dist / dur : 16.7);
    final secs = (left / speed).round();
    final eta = DateTime.now().add(Duration(seconds: secs));
    return tr('Chegada {0} · {1}\nFaltam {2}{3} · código {4}', [formatTime(eta), formatDuration(secs), formatDistance(left.round()), '', _code]);
  }

  /// Custo estimado da viagem para o MEU veículo: combustível (se o
  /// consumo e o preço estão em "Meu veículo") + pedágios da rota.
  double? _expCost;
  double? _fuelCost;
  TollEstimate? _tollEst;

  Future<void> _calcRouteCost(List<(double, double)> line, int distM) async {
    final table = await TollService.instance.table();
    if (!mounted) return;
    final tolls =
        table == null ? null : estimateTolls(table.onRoute(line), _myBike);
    final f = AppSettings.instance.fuel.value;
    final fuel = f.ready && distM > 0
        ? fuelLiters(distM.toDouble(), f.kmPerLiter) * f.pricePerLiter
        : null;
    final tollTotal = tolls != null && tolls.plazas > 0 ? tolls.total : 0.0;
    final total = (fuel ?? 0) + tollTotal;
    setState(() {
      _fuelCost = fuel;
      _tollEst = tolls;
      _expCost = total > 0 ? total : null;
    });
  }

  /// Linhas das paradas no resumo: nome, distância pela rota e chegada.
  List<Widget> _stopRows() {
    final w = _isExpedition ? (_expWalker ?? _walker) : _walker;
    final p = _me, pr = _proj;
    final speed = _etaSpeed ??
        (_trip?.averageSpeed ?? 16.7);
    return [
      for (var i = 1; i < _stops.length; i++)
        Builder(builder: (_) {
          final s = _stops[i];
          final done = _stopArrived.contains(s.id);
          String sub = '';
          if (!done && w != null && p != null) {
            final along = w.project(s.lat, s.lng).along;
            final left = along - (pr?.along ?? 0);
            if (left > 0) {
              final eta = DateTime.now().add(Duration(seconds: (left / speed).round()));
              sub = tr('{0} · chegada {1}', [formatDistance(left.round()), formatTime(eta)]);
            }
          }
          return ListTile(
            dense: true,
            leading: Text(s.type.emoji, style: const TextStyle(fontSize: 22)),
            title: Text(s.name,
                style: TextStyle(
                    decoration: done ? TextDecoration.lineThrough : null)),
            subtitle: Text(done ? tr('Visitada') : sub),
            onTap: () => _focus(s.lat, s.lng),
          );
        }),
    ];
  }

  /// Toque no título: resumo da viagem (distância, tempo, chegada, quanto
  /// falta, combustível, pedágios e custo).
  void _showTripSummary() {
    final w = _isExpedition ? (_expWalker ?? _walker) : _walker;
    if (w == null) return;
    final p = _me;
    final totalM = _isExpedition
        ? _stops.fold<int>(0, (a, s) => a + s.legDistanceM)
        : (_trip?.distanceM ?? w.length.round());
    final totalS = _isExpedition
        ? _stops.fold<int>(0, (a, s) => a + s.legDurationS)
        : (_trip?.durationS ?? 0);
    final left = p == null ? w.length : w.remainingFrom(p.latitude, p.longitude);
    final speed = _etaSpeed ??
        (totalS > 0 ? totalM / totalS : (_trip?.averageSpeed ?? 16.7));
    final secs = (left / speed).round();
    final eta = DateTime.now().add(Duration(seconds: secs));
    final f = AppSettings.instance.fuel.value;
    final tolls = _tollEst;
    Widget row(IconData i, String a, String b) => ListTile(
          dense: true,
          leading: Icon(i),
          title: Text(a),
          trailing: Text(b,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        );
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(
                _isExpedition ? (_exp?.name ?? tr('Expedição')) : (_trip?.title ?? tr('Viagem')),
                style: Theme.of(ctx).textTheme.titleLarge),
            subtitle: Text(tr('Resumo da viagem')),
          ),
          row(Icons.straighten, tr('Distância total'), formatDistance(totalM)),
          if (totalS > 0) row(Icons.timer_outlined, tr('Tempo total previsto'), formatDuration(totalS)),
          if (_navigating) ...[
            row(Icons.flag, tr('Falta'), formatDistance(left.round())),
            row(Icons.hourglass_bottom, tr('Tempo restante'), formatDuration(secs)),
            row(Icons.schedule, tr('Chegada prevista'), formatTime(eta)),
          ],
          row(Icons.local_gas_station, tr('Combustível'),
              _fuelCost != null ? formatMoney(_fuelCost!) : (f.ready ? '—' : tr('informe em Meu veículo'))),
          row(Icons.toll, tr('Pedágios'),
              tolls == null ? '—' : (tolls.plazas == 0 ? tr('sem pedágio') : formatMoney(tolls.total))),
          if (_expCost != null)
            row(Icons.payments, tr('Custo estimado'), formatMoney(_expCost!)),
          // Paradas da rota (as que faltam e as já visitadas), com a distância
          // daqui e a hora prevista de chegada em cada uma.
          if (_stops.length > 1) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(tr('Paradas'), style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ..._stopRows(),
          ],
          // Rota normal: ver a viagem antes (simulação na tela).
          if (!_isExpedition && _trip != null && !widget.simulate)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_circle_outline),
                label: Text(tr('Simular esta viagem')),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MapScreen(
                      uid: widget.uid,
                      userName: widget.userName,
                      trip: _trip,
                      simulate: true,
                    ),
                  ));
                },
              ),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  /// Próxima manobra no topo da tela (como no Waze/Google Maps).
  Widget _nextTurnCard() {
    final nav = _nav, p = _me;
    final show = !_hud3d && nav != null &&
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
    // Seta conforme a curva (suave, normal, fechada, saída, bifurcação...).
    final icon = switch (s.maneuver) {
      'turn-slight-left' || 'ramp-left' || 'keep-left' => Icons.turn_slight_left,
      'turn-slight-right' || 'ramp-right' || 'keep-right' => Icons.turn_slight_right,
      'turn-sharp-left' => Icons.turn_sharp_left,
      'turn-sharp-right' => Icons.turn_sharp_right,
      'fork-left' || 'fork-right' => Icons.fork_right,
      'uturn-left' => Icons.u_turn_left,
      'uturn-right' => Icons.u_turn_right,
      'roundabout-left' => Icons.roundabout_left,
      final m when m.startsWith('roundabout') => Icons.roundabout_right,
      'merge' => Icons.merge,
      final m when m.contains('left') => Icons.turn_left,
      final m when m.contains('right') => Icons.turn_right,
      _ => Icons.straight,
    };
    // Próximo ponto é uma parada programada: mostra também o tempo até lá
    // (pedido de 05/11), na velocidade efetiva de agora (com trânsito).
    final trip = _trip;
    final toStop = trip != null &&
        [..._stops, ...trip.stops].any((st) =>
            distanceMeters(s.lat, s.lng, st.lat, st.lng) < 150);
    final stopTime = toStop
        ? formatDuration((d / (_etaSpeed ?? trip.averageSpeed)).round())
        : null;
    final distText = Text(formatDistance(d.round()),
        style: const TextStyle(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900));
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
            if (stopTime == null)
              distText
            else
              Column(mainAxisSize: MainAxisSize.min, children: [
                distText,
                Text(stopTime,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ]),
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
                tooltip: paused ? tr('Continuar') : tr('Pausar'),
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
              tooltip: _view == _MapView.convoy ? tr('Ver em primeira pessoa') : tr('Ver de cima'),
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
                label: Text(tr('Encerrar simulação'),
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ValueListenableBuilder<double>(
            valueListenable: sim.progress,
            builder: (_, v, __) => Slider(
              value: v.clamp(0.0, 1.0),
              onChanged: (x) {
                sim.seek(x);
                _afterSimJump();
              },
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
  /// Mensagem de socorro com o link da posição no Google Maps.
  String _sosText(Position p) => '🆘 Preciso de ajuda. Estou aqui: '
      'https://www.google.com/maps/search/?api=1&query='
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

  /// Liga o compartilhamento em tempo real e monta o pedido de ajuda. Não
  /// espera o GPS: a página do link mostra a posição assim que ela chegar.
  String _sosMessage() {
    final link = LiveSos.start(widget.uid, widget.userName, first: _me);
    final me = _me;
    return '🆘 Preciso de ajuda. Minha localização em tempo real: $link'
        '${me == null ? '' : '\n\n${_sosText(me)}'}';
  }

  Future<void> _openSosChat(String number) => launchUrl(
      Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(_sosMessage())}'),
      mode: LaunchMode.externalApplication);

  /// Contato de emergência no formato do WhatsApp (com o 55 do Brasil).
  String _sosNumber(String fone) =>
      fone.startsWith('55') && fone.length >= 12 ? fone : '55$fone';

  void _showEmergency() {
    HapticFeedback.heavyImpact();
    // Com contato cadastrado, o WhatsApp abre direto com a mensagem pronta;
    // os telefones ficam atrás, para quando voltar ao app.
    final contact = AppSettings.instance.emergencyContact.value;
    if (contact != null) _openSosChat(_sosNumber(contact.$2));
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.emergency, color: Colors.red, size: 36),
            title: Text(tr('Emergência'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          for (final (num, label) in [
            ('192', tr('SAMU (ambulância)')),
            ('193', tr('Bombeiros (resgate)')),
            ('191', tr('PRF (rodovias federais)')),
            ('190', tr('Polícia Militar')),
          ])
            ListTile(
              leading: const Icon(Icons.call),
              title: Text('$num · $label'),
              onTap: () => launchUrl(Uri.parse('tel:$num')),
            ),
          // Contato de emergência (Configurações): um toque avisa pelo WhatsApp.
          if (AppSettings.instance.emergencyContact.value != null)
            Builder(builder: (_) {
              final (nome, fone) = AppSettings.instance.emergencyContact.value!;
              return ListTile(
                leading: const Icon(Icons.contact_emergency, color: Color(0xFF25D366), size: 30),
                title: Text(tr('Avisar {0} pelo WhatsApp', [nome]),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(tr('Mensagem pronta com a sua localização')),
                onTap: () => _openSosChat(_sosNumber(fone)),
              );
            }),
          // Direto no WhatsApp (a pessoa escolhe o contato); a lista de
          // compartilhar do Android às vezes nem mostra o WhatsApp.
          ListTile(
            leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
            title: Text(tr('Enviar minha localização pelo WhatsApp')),
            onTap: () async {
              final text = _sosMessage();
              final ok = await launchUrl(
                  Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
                  mode: LaunchMode.externalApplication);
              if (!ok) SharePlus.instance.share(ShareParams(text: text));
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_location),
            title: Text(tr('Enviar por outro app (SMS, Telegram...)')),
            onTap: () => SharePlus.instance.share(ShareParams(text: _sosMessage())),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: LiveSos.active,
            builder: (_, token, __) => token == null
                ? const SizedBox.shrink()
                : ListTile(
                    leading: const Icon(Icons.location_off, color: Colors.red),
                    title: Text(tr('Estou bem: parar a localização em tempo real')),
                    onTap: LiveSos.stop,
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Comboio: vista de cima. Solo: primeira pessoa, olhando a estrada.
enum _MapView { convoy, solo }

/// v2: como a navegação mostra a estrada 3D.
enum _Mode3d {
  always('3D sempre', 'Estrada em 3D o tempo todo', Icons.view_in_ar),
  map('Mapa', 'Mapa de cima o tempo todo', Icons.map),
  exits('Mapa + 3D nas saídas', 'Mapa normal; vira 3D 400 m antes e até 400 m depois de saídas, bifurcações e rotatórias', Icons.alt_route);

  const _Mode3d(this._label, this._hint, this.icon);
  final String _label;
  final String _hint;
  final IconData icon;
  String get label => tr(_label);
  String get hint => tr(_hint);
}
