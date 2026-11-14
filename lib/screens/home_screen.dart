// ============================================================================
// home_screen.dart — Tela inicial
//
// O que faz: "Para onde?" (navegação sozinho), "Só dirigir", nome do piloto,
//   veículo, histórico, clube, criar/entrar em expedição e créditos.
// Quem usa: StartupGate.
// Onde mexer: Fluxo do "Para onde?": _whereTo (busca → prévia → MapScreen).
// ============================================================================

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'na_rota_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../logic/shared_place.dart';
import '../services/places_service.dart';
import '../services/community_routes_service.dart';
import '../services/saved_places_service.dart';
import '../services/shared_place_service.dart';
import '../models/bike.dart';
import '../models/expedition.dart' show StopType;
import '../services/trip_service.dart';
import '../widgets/place_search.dart';
import '../widgets/trip_preview_sheet.dart';

import '../services/auth_service.dart';
import '../services/expedition_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../services/user_service.dart';
import '../services/analytics_service.dart';
import '../services/minimized_trip.dart';
import '../models/trip.dart';
import '../services/car_service.dart';
import '../services/planned_trips_service.dart';
import '../logic/itinerary.dart' show formatDay, formatTime;
import 'club_screen.dart';
import 'consent_screen.dart';
import 'map_screen.dart';
import 'plan_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'about_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import '../l10n/i18n.dart';
import '../services/calendar_service.dart';

/// Tela inicial do app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Estado da tela: nome do piloto, veículo, clube e última expedição.
class _HomeScreenState extends State<HomeScreen> {
  final _svc = ExpeditionService.instance;
  final _nameCtrl = TextEditingController();
  final _expNameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _lastCode;

  /// "Minhas expedições": as que ainda existem no servidor (código, nome).
  List<(String, String)> _myExps = [];
  BikeProfile _bike = const BikeProfile();
  String? _clubName;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    SavedPlacesService.instance.load();
    PlannedTripsService.instance.load();
    SharedPlaceService.instance.pending.addListener(_onShared);
    CarService.instance.connected.addListener(_onCar);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _busy = true;
      final t = await ActiveTrip.load();
      _busy = false;
      if (!mounted) return;
      if (t != null) {
        MinimizedTrip.trip.value = t;
        await _resumeTrip();
        return;
      }
      _onShared();
      _onCar();
    });
  }

  @override
  void dispose() {
    SharedPlaceService.instance.pending.removeListener(_onShared);
    CarService.instance.connected.removeListener(_onCar);
    super.dispose();
  }

  /// Conectou no Android Auto com a tela inicial aberta: abre o "Dirigir
  /// agora" (radares, limite e avisos na tela do carro).
  void _onCar() {
    if (!mounted || !CarService.instance.connected.value || _busy) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _justDrive();
  }

  /// Endereço recebido de outro app ("Abrir com UauGo" / "Compartilhar"):
  /// vai direto para o "Para onde?" com o destino.
  Future<void> _onShared() async {
    if (!mounted || SharedPlaceService.instance.pending.value == null) return;
    debugPrint('Destino recebido: na frente=${ModalRoute.of(context)?.isCurrent}, ocupado=$_busy');
    final byVoice = SharedPlaceService.instance.fromVoice;
    SharedPlaceService.instance.fromVoice = false;
    // Em outra tela (ex.: navegando): não interrompe o que está acontecendo.
    if (!(ModalRoute.of(context)?.isCurrent ?? true) || _busy) {
      SharedPlaceService.instance.take();
      _snack(tr('Endereço recebido. Volte à tela inicial e abra de novo.'));
      return;
    }
    final raw = SharedPlaceService.instance.take()!;
    // Só no app de testes (debug, por cabo): "uaugo-teste lat,lng lat,lng
    // Nome" abre a prévia com a saída e o destino (bateria de simulações).
    if (kDebugMode && raw.startsWith('uaugo-teste ')) {
      await _testRoute(raw);
      return;
    }
    // Link do convite de clube (QR code da Administração UauGo).
    final club = clubCodeFromLink(raw);
    if (club != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ClubScreen(
              userName: _nameCtrl.text.trim(), initialCode: club)));
      return;
    }
    // Rota com paradas vinda do botão "Navegar" do site da comunidade.
    final route = routeFromLink(raw);
    if (route != null) {
      final last = route.last;
      await _whereTo(
          byVoice: byVoice,
          shared: SharedPlace(lat: last.lat, lng: last.lng, label: last.name),
          stops: route.sublist(0, route.length - 1));
      return;
    }
    setState(() => _busy = true);
    final place = await SharedPlaceService.instance.resolve(raw);
    if (!mounted) return;
    setState(() => _busy = false);
    if (place == null) {
      _snack(tr('Não consegui entender o endereço recebido'));
      return;
    }
    await _whereTo(shared: place, byVoice: byVoice);
  }

  /// Rotas salvas no site da comunidade: escolher uma abre a prévia saindo
  /// daqui, com as paradas e o destino dela.
  Future<void> _communityRoutes() async {
    setState(() => _busy = true);
    List<CommunityRoute>? list;
    String? error;
    try {
      list = await CommunityRoutesService.mine();
    } on CommunityRoutesError catch (e) {
      error = tr(e.message);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _snack(error);
      return;
    }
    final picked = await showModalBottomSheet<CommunityRoute>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: list!.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(tr('Nenhuma rota salva ainda.'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(tr('Monte e salve rotas em uaugo.com.br/viagem, com a mesma conta do app.'),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => launchUrl(Uri.parse('https://uaugo.com.br/viagem'),
                          mode: LaunchMode.externalApplication),
                      child: Text(tr('Abrir o planejador')),
                    ),
                  ]),
                )
              : ListView(shrinkWrap: true, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(tr('Rotas da comunidade'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  for (final r in list)
                    ListTile(
                      leading: const Icon(Icons.alt_route),
                      title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (r.stops.isNotEmpty)
                          r.stops.length == 1 ? tr('1 parada') : tr('{0} paradas', [r.stops.length]),
                        if (r.km > 0) '${r.km.round()} km',
                      ].join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(c, r),
                    ),
                ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final d = picked.destination;
    await _whereTo(
        shared: SharedPlace(lat: d.lat, lng: d.lng, label: d.name),
        stops: picked.stops);
  }

  /// Bateria de testes (só debug): prévia com saída e destino escolhidos.
  Future<void> _testRoute(String raw) async {
    final parts = raw.split(' ');
    if (parts.length < 3) return;
    (double, double) ll(String s) {
      final x = s.split(',');
      return (double.parse(x[0]), double.parse(x[1]));
    }
    final (la1, lo1) = ll(parts[1]);
    final (la2, lo2) = ll(parts[2]);
    final name = parts.length > 3 ? parts.sublist(3).join(' ') : 'Teste';
    final uid = await _prepareAlone();
    if (uid == null || !mounted) return;
    final res = await TripPreviewSheet.show(context, title: name, points: [
      TripPoint('Saída do teste', la1, lo1, type: StopType.meet),
      TripPoint(name, la2, lo2, type: StopType.destination),
    ]);
    if (res == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(
        uid: uid,
        userName: _riderName,
        trip: res.$2,
        simulate: res.$1 == TripAction.simulate,
      ),
    ));
  }

  /// Lê do celular o nome, o veículo, o clube e a última expedição.
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final bike = await ProfileService.load();
    final clubName = await UserService.loadClubName();
    if (!mounted) return;
    setState(() {
      _bike = bike;
      _clubName = clubName;
      _nameCtrl.text = prefs.getString('userName') ?? '';
      _lastCode = prefs.getString('lastCode');
    });
    _loadMyExpeditions();
  }

  /// Confere no servidor quais expedições usadas ainda existem (até 10);
  /// as encerradas saem da lista. Sem conta ou sem internet, fica vazia.
  Future<void> _loadMyExpeditions() async {
    if (AuthService.isAnonymous) {
      if (mounted) setState(() => _myExps = []);
      return;
    }
    final codes = (await UserService.loadExpeditionHistory()).take(10).toList();
    // 1º: mostra na hora o que já se conhecia (nomes guardados no celular).
    final names = await UserService.loadExpeditionNames();
    final known = [
      for (final c in codes)
        if (names[c] != null) (c, names[c]!)
    ];
    if (mounted && known.isNotEmpty) setState(() => _myExps = known);
    // 2º: confere todas no servidor AO MESMO TEMPO (antes: uma por vez, e a
    // lista demorava a aparecer). Sem resposta = mantém como estava.
    final results = await Future.wait(codes.map((c) async {
      try {
        final e = await _svc.find(c).timeout(const Duration(seconds: 10));
        return (c, e?.name, true);
      } catch (_) {
        return (c, names[c], false);
      }
    }));
    final found = <(String, String)>[];
    final fresh = <String, String>{};
    for (final (c, name, answered) in results) {
      if (name != null) {
        found.add((c, name));
        fresh[c] = name;
      } else if (answered) {
        // Encerrada: some da lista (a viagem fica em "Minhas viagens" se
        // o piloto rodou algum trecho).
        await UserService.removeExpeditionHistory(c);
      }
    }
    await UserService.saveExpeditionNames(fresh);
    if (mounted) setState(() => _myExps = found);
  }

  /// Mostra uma mensagem rápida no rodapé.
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Fluxo comum: valida nome, pede permissão, faz login, executa a ação
  /// (criar ou entrar) e abre o mapa.
  Future<void> _go(
      Future<String?> Function(String uid, String userName) action,
      {bool planFirst = false}) async {
    final userName = _nameCtrl.text.trim();
    if (userName.isEmpty) {
      _snack(tr('Informe seu nome de piloto'));
      return;
    }
    // Expedição exige conta: o grupo precisa saber quem é quem.
    if (!await requireAccount(
        context,
        tr('Para criar ou entrar numa expedição, entre com sua conta. Assim o grupo sabe quem é você e você pode usar o app em outro celular.'))) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await LocationService.ensurePermission()) {
        _snack(tr('Ative o GPS e permita o acesso à localização'));
        return;
      }
      final uid = await AuthService.ensureSignedIn();
      NotificationService.saveToken(uid);
      final code = await action(uid, userName);
      if (code == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', userName);
      await prefs.setString('lastCode', code);
      // Sem esperar: sem internet a inscrição nos avisos ficava presa.
      NotificationService.subscribe(code).catchError((_) {});
      _svc.updateBike(code, uid, await ProfileService.load());
      await UserService.addExpeditionHistory(code);
      AnalyticsService.event(planFirst ? 'expedition_create' : 'expedition_join');

      if (!mounted) return;
      // Expedição nova: primeiro monta o roteiro; o mapa abre quando o
      // líder tocar em "Abrir mapa do comboio".
      if (planFirst) {
        final start = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) =>
              PlanScreen(code: code, uid: uid, showStartButton: true),
        ));
        if (start != true || !mounted) {
          await _loadPrefs();
          return;
        }
      }
      final left = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => MapScreen(
            code: code,
            uid: uid,
            userName: userName,
            // Veio do "Iniciar" do roteiro: já começa a navegação.
            startNavigation: planFirst),
      ));
      if (left == true) {
        await prefs.remove('lastCode');
        await UserService.removeExpeditionHistory(code);
      }
      await _loadPrefs();
    } catch (e) {
      _snack(tr('Erro: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cria uma expedição e abre o roteiro para planejar.
  void _create() => _go((uid, userName) {
        final expName = _expNameCtrl.text.trim();
        return _svc.create(
          name: expName.isEmpty ? tr('Expedição de {0}', [userName]) : expName,
          uid: uid,
          userName: userName,
        );
      }, planFirst: true);

  /// Entra numa expedição pelo código (digitado ou o último usado).
  void _join([String? code]) => _go((uid, userName) async {
        final c = (code ?? _codeCtrl.text).trim().toUpperCase();
        if (c.isEmpty) {
          _snack(tr('Digite o código da expedição'));
          return null;
        }
        final exp = await _svc.find(c);
        if (exp == null) {
          _snack(tr('Expedição "{0}" não encontrada (ou sem internet para conferir).', [c]));
          return null;
        }
        await _svc.join(code: c, uid: uid, userName: userName);
        return c;
      });

  /// Abre "Meu veículo" (moto ou carro).
  Future<void> _editBike() async {
    final b = await Navigator.of(context).push<BikeProfile>(
        MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (b != null) setState(() => _bike = b);
  }

  /// Abre o clube.
  Future<void> _openClub() async {
    if (!await requireAccount(context,
        tr('O clube é para membros identificados: entre com sua conta.'))) {
      return;
    }
    if (!mounted) return;
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', name);
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ClubScreen(userName: name)));
    await _loadPrefs();
  }

  /// Abre as autorizações (LGPD).
  void _openPrivacy() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConsentScreen()));

  // ------------------------------------------------------------ sozinho

  String get _riderName =>
      _nameCtrl.text.trim().isEmpty ? tr('Você') : _nameCtrl.text.trim();

  /// Permissão de GPS + login (para baixar radares e limites).
  Future<String?> _prepareAlone() async {
    if (!await LocationService.ensurePermission()) {
      _snack(tr('Ative o GPS e permita o acesso à localização'));
      return null;
    }
    try {
      return await AuthService.ensureSignedIn();
    } catch (e) {
      _snack(tr('Sem conexão: {0}', [e]));
      return null;
    }
  }

  /// "Para onde?": navegação sozinho, como no Waze.
  /// [shared]: destino recebido de outro app (pula a busca se tiver posição).
  /// [byVoice]: destino falado — vai direto ao melhor resultado da busca.
  Future<void> _whereTo(
      {SharedPlace? shared, bool byVoice = false, List<RoutePoint> stops = const []}) async {
    setState(() => _busy = true);
    final uid = await _prepareAlone();
    Position? me;
    if (uid != null) {
      // Posição recente (até 2 min) serve de saída: não espera o GPS.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp).inMinutes < 2) {
        me = last;
      }
    }
    if (uid != null && me == null) {
      try {
        me = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(timeLimit: Duration(seconds: 10)));
      } catch (_) {
        me = await Geolocator.getLastKnownPosition();
      }
    }
    if (mounted) setState(() => _busy = false);
    if (uid == null || !mounted) return;
    if (me == null) {
      _snack(tr('Não foi possível obter sua posição pelo GPS'));
      return;
    }
    // Texto recebido: com um só resultado na busca vai direto para a rota;
    // com vários, mostra as opções. Destino falado: pega o melhor resultado
    // (quem está pilotando não toca na lista); se não for o lugar certo,
    // "Trocar" na prévia.
    final single = shared != null && !shared.hasCoords && shared.query != null
        ? await _matchFor(shared.query!, me, best: byVoice)
        : null;
    if (!mounted) return;
    if (byVoice && single == null) {
      _snack(tr('Não encontrei "{0}". Escolha na lista.', [shared?.query]));
    }
    final picked = shared != null && shared.hasCoords
        ? PickedPlace(shared.label ?? tr('Local recebido'), '', shared.lat!, shared.lng!)
        : single ?? await Navigator.of(context).push<PickedPlace>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PlaceSearchPage(
                  near: LatLng(me!.latitude, me.longitude),
                  title: tr('Para onde'),
                  initialText: shared?.query ?? shared?.label),
            ),
          );
    if (picked == null || !mounted) return;
    final res = await TripPreviewSheet.show(context,
        autoStart: byVoice,
        title: picked.name,
        points: [
          TripPoint(tr('Sua posição'), me.latitude, me.longitude,
              type: StopType.meet),
          for (final s in stops)
            TripPoint(s.name, s.lat, s.lng, type: StopType.waypoint),
          TripPoint(picked.name, picked.lat, picked.lng,
              type: StopType.destination),
        ]);
    if (res == null || !mounted) return;
    AnalyticsService.event(
        res.$1 == TripAction.simulate ? 'route_simulate' : 'route_start');
    MinimizedTrip.trip.value = null; // rota nova substitui a minimizada
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(
        uid: uid,
        userName: _riderName,
        trip: res.$2,
        simulate: res.$1 == TripAction.simulate,
      ),
    ));
  }

  // ---- Viagens planejadas (prévia da rota → "Saída" → Salvar)

  /// Lista das viagens com saída marcada; tocar abre a prévia saindo de
  /// onde o piloto estiver.
  Widget _plannedTripsList() => ValueListenableBuilder<List<PlannedTrip>>(
        valueListenable: PlannedTripsService.instance.trips,
        builder: (_, list, __) => list.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Viagens planejadas'),
                        style: Theme.of(context).textTheme.titleSmall),
                    for (final t in list.take(4))
                      Card(
                        margin: const EdgeInsets.only(top: 6),
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.event_available),
                          title: Text(t.title, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              tr('Saída {0} {1}', [formatDay(t.departAt), formatTime(t.departAt)])),
                          onTap: () => _openPlanned(t),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: tr('Pôr na agenda'),
                              icon: const Icon(Icons.event),
                              onPressed: () => CalendarService.addTrip(
                                  title: t.title,
                                  departAt: t.departAt,
                                  destination: t.points.isEmpty ? '' : t.points.last.name),
                            ),
                            IconButton(
                              tooltip: tr('Apagar'),
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  PlannedTripsService.instance.remove(t.id),
                            ),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
      );

  /// Abre a prévia da viagem planejada, saindo de onde o piloto está.
  Future<void> _openPlanned(PlannedTrip t) async {
    final uid = await _prepareAlone();
    if (uid == null || !mounted) return;
    Position? me;
    try {
      me = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(timeLimit: Duration(seconds: 10)));
    } catch (_) {
      me = await Geolocator.getLastKnownPosition();
    }
    if (!mounted) return;
    final pts = [...t.points];
    if (me != null && pts.isNotEmpty &&
        (pts.first.name == 'Sua posição' || pts.first.name == 'Your location')) {
      pts[0] = TripPoint(tr('Sua posição'), me.latitude, me.longitude, type: StopType.meet);
    }
    final res = await TripPreviewSheet.show(context, title: t.title, points: pts);
    if (res == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(
        uid: uid,
        userName: _riderName,
        trip: res.$2,
        simulate: res.$1 == TripAction.simulate,
      ),
    ));
  }

  // ---- Locais salvos (Casa, Trabalho e outros; só no celular)

  /// Atalhos abaixo do "Para onde?". Toque: rota; toque longo: trocar/remover.
  Widget _savedPlacesRow() => ValueListenableBuilder<List<SavedPlace>>(
        valueListenable: SavedPlacesService.instance.places,
        builder: (_, list, __) => Padding(
          padding: const EdgeInsets.only(top: 8),
          // Casa e Trabalho sempre à vista; os outros ficam em "Locais
          // salvos" (com muitos, a tela inicial descia demais).
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            _savedChip(savedHome, tr('Casa'), Icons.home),
            _savedChip(savedWork, tr('Trabalho'), Icons.work),
            if (list.any((p) => p.key != savedHome && p.key != savedWork))
              ActionChip(
                avatar: const Icon(Icons.star, size: 18),
                label: Text(tr('Locais salvos ({0})', [
                  list.where((p) => p.key != savedHome && p.key != savedWork).length
                ])),
                onPressed: _showSavedPlaces,
              )
            else
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(tr('Salvar local')),
                onPressed: _addSavedPlace,
              ),
          ]),
        ),
      );

  Widget _savedChip(String key, String name, IconData icon) {
    final p = SavedPlacesService.instance.get(key);
    if (p == null) {
      return ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(tr('{0} (definir)', [name])),
        onPressed: () => _pickSavedPlace(key, name),
      );
    }
    // Já salvo: toque leva até lá; o lápis (ou toque longo) troca ou remove.
    // Antes só havia o toque longo, que ninguém achava (12/11).
    return GestureDetector(
      onLongPress: () => _editSavedPlace(p),
      child: InputChip(
        avatar: Icon(icon, size: 18),
        label: Text(name),
        onPressed: () =>
            _whereTo(shared: SharedPlace(lat: p.lat, lng: p.lng, label: p.name)),
        deleteIcon: const Icon(Icons.edit, size: 18),
        deleteButtonTooltipMessage: tr('Trocar ou remover'),
        onDeleted: () => _editSavedPlace(p),
      ),
    );
  }

  /// Lista dos outros locais salvos: tocar vai até lá; lápis edita;
  /// "Salvar local" inclui um novo.
  Future<void> _showSavedPlaces() => showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (ctx) => ValueListenableBuilder<List<SavedPlace>>(
          valueListenable: SavedPlacesService.instance.places,
          builder: (_, list, __) {
            final others = [
              for (final p in list)
                if (p.key != savedHome && p.key != savedWork) p
            ];
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: ListView(shrinkWrap: true, children: [
                ListTile(title: Text(tr('Locais salvos'), style: Theme.of(ctx).textTheme.titleLarge)),
                for (final p in others)
                  ListTile(
                    leading: const Icon(Icons.star),
                    title: Text(p.name),
                    subtitle: p.address.isEmpty ? null : Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(ctx);
                      _whereTo(shared: SharedPlace(lat: p.lat, lng: p.lng, label: p.name));
                    },
                    trailing: IconButton(
                      tooltip: tr('Editar'),
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _editSavedPlace(p);
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(tr('Salvar local')),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addSavedPlace();
                  },
                ),
              ]),
            );
          },
        ),
      );

  /// Escolhe o endereço do local [key] e salva.
  Future<void> _pickSavedPlace(String key, String name) async {
    final last = await Geolocator.getLastKnownPosition();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlaceSearchPage(
          near: last == null ? null : LatLng(last.latitude, last.longitude),
          title: name),
    ));
    if (picked == null || !mounted) return;
    await SavedPlacesService.instance.save(SavedPlace(key, name,
        picked.address.isEmpty ? picked.name : picked.address, picked.lat, picked.lng));
    _snack(key == savedHome || key == savedWork
        ? tr('{0} salvo. Toque no atalho ou diga "UauGo, ir para {1}".', [name, key == savedHome ? 'casa' : 'o trabalho'])
        : tr('{0} salvo.', [name]));
  }

  /// "Salvar local": pede o nome e o endereço.
  Future<void> _addSavedPlace() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nome do local')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('Ex.: Casa da mãe, Oficina')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Escolher endereço'))),
        ],
      ),
    );
    final n = name?.trim() ?? '';
    if (n.isEmpty || !mounted) return;
    await _pickSavedPlace('p${DateTime.now().millisecondsSinceEpoch}', n);
  }

  /// Toque longo num atalho: trocar o endereço ou remover.
  Future<void> _editSavedPlace(SavedPlace p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(p.address),
          ),
          ListTile(
            leading: const Icon(Icons.edit_location_alt),
            title: Text(tr('Trocar endereço')),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr('Remover')),
            onTap: () => Navigator.pop(ctx, 'remove'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (choice == 'edit') await _pickSavedPlace(p.key, p.name);
    if (choice == 'remove') await SavedPlacesService.instance.remove(p.key);
  }

  /// Lugar da busca por [q]: o único resultado ou, com [best], o primeiro
  /// (o mais relevante e próximo). Null se não houver.
  Future<PickedPlace?> _matchFor(String q, Position me, {bool best = false}) async {
    final places = PlacesService();
    final r = await places.search(q, nearLat: me.latitude, nearLng: me.longitude);
    if (r.isEmpty || (r.length > 1 && !best)) return null;
    final d = await places.details(r.first);
    return d == null ? null : PickedPlace(d.name, d.address, d.lat, d.lng);
  }

  /// Histórico de viagens (guardado só no celular).
  /// Turismo, hospedagem e postos perto da posição atual.
  Future<void> _exploreNearby() async {
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NaRotaScreen(lat: p.latitude, lng: p.longitude, lugar: tr('Perto de você'))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Não deu para saber onde você está. Ligue a localização.'))));
      }
    }
  }

  Future<void> _openHistory() async {
    var uid = '';
    try {
      uid = await AuthService.ensureSignedIn();
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HistoryScreen(uid: uid, userName: _riderName)));
  }

  /// Abre de novo a rota minimizada.
  Future<void> _resumeTrip() async {
    final t = MinimizedTrip.trip.value;
    if (t == null) return;
    final uid = await _prepareAlone();
    if (uid == null || !mounted) return;
    MinimizedTrip.trip.value = null;
    final simAt = ActiveTrip.simAt;
    ActiveTrip.simAt = null;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MapScreen(
            uid: uid,
            userName: _riderName,
            trip: t,
            simulate: simAt != null,
            simStart: simAt,
            resumed: simAt == null)));
  }

  /// Há rota minimizada: pergunta antes de abrir o mapa. true = retomou.
  Future<bool> _askResume() async {
    final t = MinimizedTrip.trip.value;
    if (t == null) return false;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Retomar a navegação?')),
        content: Text(tr('Você tem uma rota minimizada para {0}.', [t.title])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Não'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Retomar'))),
        ],
      ),
    );
    if (!mounted) return true;
    if (yes == true) {
      await _resumeTrip();
      return true;
    }
    if (yes == false) MinimizedTrip.trip.value = null;
    return yes == null; // fora da caixa: não faz nada
  }

  /// Cartão "Retomar a navegação" enquanto houver rota minimizada.
  Widget _resumeCard() => ValueListenableBuilder<Trip?>(
        valueListenable: MinimizedTrip.trip,
        builder: (_, t, __) => t == null
            ? const SizedBox.shrink()
            : Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: const Icon(Icons.navigation),
                  title: Text(tr('Retomar a navegação?')),
                  subtitle: Text(t.title, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: tr('Descartar'),
                      icon: const Icon(Icons.close),
                      onPressed: () => MinimizedTrip.trip.value = null,
                    ),
                    FilledButton(onPressed: _resumeTrip, child: Text(tr('Retomar'))),
                  ]),
                ),
              ),
      );

  /// Sem destino: só radares, perigos e velocímetro.
  Future<void> _justDrive() async {
    if (await _askResume()) return;
    AnalyticsService.event('just_drive');
    final uid = await _prepareAlone();
    if (uid == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MapScreen(uid: uid, userName: _riderName)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                // Conta: "Entrar" (anônimo) ou o nome de quem entrou.
                // Flexible: nome/e-mail longo não passa por cima da engrenagem.
                Flexible(child: StreamBuilder(
                  stream: AuthService.changes,
                  builder: (context, _) => TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => AuthService.isAnonymous
                                ? const LoginScreen()
                                : const SettingsScreen())),
                    icon: Icon(AuthService.isAnonymous
                        ? Icons.account_circle_outlined
                        : Icons.account_circle),
                    label: Text(
                      AuthService.isAnonymous
                          ? tr('Entrar')
                          // Sem nome na conta: só a parte do e-mail antes do @.
                          : AuthService.displayName.split(' ').first.split('@').first,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                )),
                IconButton(
                  tooltip: tr('Configurações'),
                  icon: const Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen())),
                ),
              ]),
              // Marca sobre o mapa-múndi pontilhado: "qualquer caminho".
              // (scripts/gerar-mapa-pontilhado.py e scripts/gerar-icone.py)
              SizedBox(
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(
                    child: Image.asset('assets/branding/mapa_pontilhado.png',
                        fit: BoxFit.contain),
                  ),
                  Image.asset('assets/branding/uaugo_marca.png',
                      width: 104, height: 104),
                ]),
              ),
              const SizedBox(height: 4),
              Text('UauGo',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text(appSlogan,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              // Navegação sozinho (tipo Waze), sem precisar de expedição.
              Material(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: _whereTo,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(children: [
                      Icon(Icons.search,
                          color: theme.colorScheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Text(tr('Para onde?'),
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer)),
                    ]),
                  ),
                ),
              ),
              _savedPlacesRow(),
                  _resumeCard(),
              _plannedTripsList(),
              // "Só dirigir" em destaque: botão grande, logo abaixo da busca.
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _justDrive,
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                ),
                child: Row(children: [
                  Icon(Icons.speed, size: 32),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('DIRIGIR AGORA'),
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        Text(tr('radares e velocidade'),
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                // Tocar fora fecha o teclado: assim ele não volta sozinho ao sair do
                // mapa (isso derrubava o app: o mapa sendo fechado mudava de tamanho).
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr('Seu nome de piloto'),
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _editBike,
                icon: Icon(_bike.style.icon),
                label: Text(_bike.isEmpty
                    ? tr('Configurar meu veículo')
                    : tr('Meu veículo: {0}', [_bike.displayName.isEmpty ? tr('com foto') : _bike.displayName])),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openHistory,
                icon: const Icon(Icons.history),
                label: Text(tr('Minhas viagens')),
              ),
              const SizedBox(height: 8),
              // Turismo, hospedagem e postos em volta de onde estou (08/11).
              OutlinedButton.icon(
                onPressed: _exploreNearby,
                icon: const Icon(Icons.travel_explore),
                label: Text(tr('Explorar por perto')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openClub,
                icon: const Icon(Icons.shield_outlined),
                label: Text(_clubName == null
                    ? tr('Clube')
                    : tr('Clube: {0}', [_clubName])),
              ),
              const SizedBox(height: 8),
              // Comunidade UauGo (site uaugo.com.br), com a marca (12/11).
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://uaugo.com.br'),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.forum_outlined),
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('Comunidade')),
                  const SizedBox(width: 6),
                  Image.asset('assets/branding/uaugo_marca.png', height: 18),
                ]),
              ),
              const SizedBox(height: 8),
              // Rotas montadas no planejador do site (uaugo.com.br/viagem).
              OutlinedButton.icon(
                onPressed: _communityRoutes,
                icon: const Icon(Icons.alt_route),
                label: Text(tr('Rotas da comunidade')),
              ),
              if (_myExps.isNotEmpty) ...[
                const SizedBox(height: 24),
                _Section(
                  title: tr('Minhas expedições'),
                  children: [
                    for (final (code, name) in _myExps.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton.tonalIcon(
                          onPressed: () => _join(code),
                          icon: const Icon(Icons.groups),
                          label: Text('$name · $code',
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                  ],
                ),
              ] else if (_lastCode != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => _join(_lastCode),
                  icon: const Icon(Icons.replay),
                  label: Text(tr('Voltar para a expedição {0}', [_lastCode])),
                ),
              ],
              const SizedBox(height: 24),
              _Section(
                title: tr('Nova expedição'),
                children: [
                  TextField(
                    controller: _expNameCtrl,
                    // Tocar fora fecha o teclado: assim ele não volta sozinho ao sair do
                    // mapa (isso derrubava o app: o mapa sendo fechado mudava de tamanho).
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      labelText: tr('Nome (ex: Serra do Rio do Rastro)'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_road),
                    label: Text(tr('Criar e planejar roteiro')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Section(
                title: tr('Entrar em uma expedição'),
                children: [
                  TextField(
                    controller: _codeCtrl,
                    // Tocar fora fecha o teclado: assim ele não volta sozinho ao sair do
                    // mapa (isso derrubava o app: o mapa sendo fechado mudava de tamanho).
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: tr('Código do convite'),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _join,
                    icon: const Icon(Icons.login),
                    label: Text(tr('Entrar no comboio')),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _openPrivacy,
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text(tr('Privacidade e autorizações')),
              ),
              const SizedBox(height: 8),
              // Autoria: HelpAITech (toque para ver "Sobre").
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AboutScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    Text(tr('Desenvolvido por'),
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Image.asset('assets/branding/helpaitech_logo.png',
                          height: 48),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cartão de seção da tela inicial (título + conteúdo).
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
