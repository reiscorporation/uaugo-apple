// ============================================================================
// home_screen.dart — Tela inicial
//
// O que faz: "Para onde?" (navegação sozinho), "Só dirigir", nome do piloto,
//   veículo, histórico, clube, criar/entrar em expedição e créditos.
// Quem usa: StartupGate.
// Onde mexer: Fluxo do "Para onde?": _whereTo (busca → prévia → MapScreen).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../brand.dart';
import '../logic/shared_place.dart';
import '../services/places_service.dart';
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
import 'club_screen.dart';
import 'consent_screen.dart';
import 'map_screen.dart';
import 'plan_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'about_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

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
    SharedPlaceService.instance.pending.addListener(_onShared);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShared());
  }

  @override
  void dispose() {
    SharedPlaceService.instance.pending.removeListener(_onShared);
    super.dispose();
  }

  /// Endereço recebido de outro app ("Abrir com UauGo" / "Compartilhar"):
  /// vai direto para o "Para onde?" com o destino.
  Future<void> _onShared() async {
    if (!mounted || SharedPlaceService.instance.pending.value == null) return;
    final byVoice = SharedPlaceService.instance.fromVoice;
    SharedPlaceService.instance.fromVoice = false;
    // Em outra tela (ex.: navegando): não interrompe o que está acontecendo.
    if (!(ModalRoute.of(context)?.isCurrent ?? true) || _busy) {
      SharedPlaceService.instance.take();
      _snack('Endereço recebido. Volte à tela inicial e abra de novo.');
      return;
    }
    final raw = SharedPlaceService.instance.take()!;
    // Link do convite de clube (QR code da Administração UauGo).
    final club = clubCodeFromLink(raw);
    if (club != null) {
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ClubScreen(
              userName: _nameCtrl.text.trim(), initialCode: club)));
      return;
    }
    setState(() => _busy = true);
    final place = await SharedPlaceService.instance.resolve(raw);
    if (!mounted) return;
    setState(() => _busy = false);
    if (place == null) {
      _snack('Não consegui entender o endereço recebido');
      return;
    }
    await _whereTo(shared: place, byVoice: byVoice);
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
      _snack('Informe seu nome de piloto');
      return;
    }
    // Expedição exige conta: o grupo precisa saber quem é quem.
    if (!await requireAccount(
        context,
        'Para criar ou entrar numa expedição, entre com sua conta. Assim o '
        'grupo sabe quem é você e você pode usar o app em outro celular.')) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await LocationService.ensurePermission()) {
        _snack('Ative o GPS e permita o acesso à localização');
        return;
      }
      final uid = await AuthService.ensureSignedIn();
      NotificationService.saveToken(uid);
      final code = await action(uid, userName);
      if (code == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', userName);
      await prefs.setString('lastCode', code);
      await NotificationService.subscribe(code);
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
      _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cria uma expedição e abre o roteiro para planejar.
  void _create() => _go((uid, userName) {
        final expName = _expNameCtrl.text.trim();
        return _svc.create(
          name: expName.isEmpty ? 'Expedição de $userName' : expName,
          uid: uid,
          userName: userName,
        );
      }, planFirst: true);

  /// Entra numa expedição pelo código (digitado ou o último usado).
  void _join([String? code]) => _go((uid, userName) async {
        final c = (code ?? _codeCtrl.text).trim().toUpperCase();
        if (c.isEmpty) {
          _snack('Digite o código da expedição');
          return null;
        }
        final exp = await _svc.find(c);
        if (exp == null) {
          _snack('Expedição "$c" não encontrada');
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
        'O clube é para membros identificados: entre com sua conta.')) {
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
      _nameCtrl.text.trim().isEmpty ? 'Você' : _nameCtrl.text.trim();

  /// Permissão de GPS + login (para baixar radares e limites).
  Future<String?> _prepareAlone() async {
    if (!await LocationService.ensurePermission()) {
      _snack('Ative o GPS e permita o acesso à localização');
      return null;
    }
    try {
      return await AuthService.ensureSignedIn();
    } catch (e) {
      _snack('Sem conexão: $e');
      return null;
    }
  }

  /// "Para onde?": navegação sozinho, como no Waze.
  /// [shared]: destino recebido de outro app (pula a busca se tiver posição).
  /// [byVoice]: destino falado — vai direto ao melhor resultado da busca.
  Future<void> _whereTo({SharedPlace? shared, bool byVoice = false}) async {
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
      _snack('Não foi possível obter sua posição pelo GPS');
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
      _snack('Não encontrei "${shared?.query}". Escolha na lista.');
    }
    final picked = shared != null && shared.hasCoords
        ? PickedPlace(shared.label ?? 'Local recebido', '', shared.lat!, shared.lng!)
        : single ?? await Navigator.of(context).push<PickedPlace>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PlaceSearchPage(
                  near: LatLng(me!.latitude, me.longitude),
                  title: 'Para onde',
                  initialText: shared?.query ?? shared?.label),
            ),
          );
    if (picked == null || !mounted) return;
    final res = await TripPreviewSheet.show(context,
        autoStart: byVoice,
        title: picked.name,
        points: [
          TripPoint('Sua posição', me.latitude, me.longitude,
              type: StopType.meet),
          TripPoint(picked.name, picked.lat, picked.lng,
              type: StopType.destination),
        ]);
    if (res == null || !mounted) return;
    AnalyticsService.event(
        res.$1 == TripAction.simulate ? 'route_simulate' : 'route_start');
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
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            _savedChip(savedHome, 'Casa', Icons.home),
            _savedChip(savedWork, 'Trabalho', Icons.work),
            for (final p in list)
              if (p.key != savedHome && p.key != savedWork)
                _savedChip(p.key, p.name, Icons.star),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Salvar local'),
              onPressed: _addSavedPlace,
            ),
          ]),
        ),
      );

  Widget _savedChip(String key, String name, IconData icon) {
    final p = SavedPlacesService.instance.get(key);
    return GestureDetector(
      onLongPress: p == null ? null : () => _editSavedPlace(p),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(p == null ? '$name (definir)' : name),
        onPressed: () => p == null
            ? _pickSavedPlace(key, name)
            : _whereTo(shared: SharedPlace(lat: p.lat, lng: p.lng, label: p.name)),
      ),
    );
  }

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
        ? '$name salvo. Toque no atalho ou diga "UauGo, ir para ${key == savedHome ? 'casa' : 'o trabalho'}".'
        : '$name salvo.');
  }

  /// "Salvar local": pede o nome e o endereço.
  Future<void> _addSavedPlace() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome do local'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ex.: Casa da mãe, Oficina'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Escolher endereço')),
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
            title: const Text('Trocar endereço'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Remover'),
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
  Future<void> _openHistory() async {
    var uid = '';
    try {
      uid = await AuthService.ensureSignedIn();
    } catch (_) {}
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HistoryScreen(uid: uid, userName: _riderName)));
  }

  /// Sem destino: só radares, perigos e velocímetro.
  Future<void> _justDrive() async {
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
                StreamBuilder(
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
                          ? 'Entrar'
                          : AuthService.displayName.split(' ').first,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Configurações',
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
                      Text('Para onde?',
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer)),
                    ]),
                  ),
                ),
              ),
              _savedPlacesRow(),
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
                child: const Row(children: [
                  Icon(Icons.speed, size: 32),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DIRIGIR AGORA',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('radares e velocidade',
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
                decoration: const InputDecoration(
                  labelText: 'Seu nome de piloto',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _editBike,
                icon: Icon(_bike.style.icon),
                label: Text(_bike.isEmpty
                    ? 'Configurar meu veículo'
                    : 'Meu veículo: ${_bike.displayName.isEmpty ? 'com foto' : _bike.displayName}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openHistory,
                icon: const Icon(Icons.history),
                label: const Text('Minhas viagens'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openClub,
                icon: const Icon(Icons.shield_outlined),
                label: Text(_clubName == null
                    ? 'Clube'
                    : 'Clube: $_clubName'),
              ),
              if (_myExps.isNotEmpty) ...[
                const SizedBox(height: 24),
                _Section(
                  title: 'Minhas expedições',
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
                  label: Text('Voltar para a expedição $_lastCode'),
                ),
              ],
              const SizedBox(height: 24),
              _Section(
                title: 'Nova expedição',
                children: [
                  TextField(
                    controller: _expNameCtrl,
                    // Tocar fora fecha o teclado: assim ele não volta sozinho ao sair do
                    // mapa (isso derrubava o app: o mapa sendo fechado mudava de tamanho).
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Nome (ex: Serra do Rio do Rastro)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add_road),
                    label: const Text('Criar e planejar roteiro'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Section(
                title: 'Entrar em uma expedição',
                children: [
                  TextField(
                    controller: _codeCtrl,
                    // Tocar fora fecha o teclado: assim ele não volta sozinho ao sair do
                    // mapa (isso derrubava o app: o mapa sendo fechado mudava de tamanho).
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código do convite',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Entrar no comboio'),
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
                label: const Text('Privacidade e autorizações'),
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
                    Text('Desenvolvido por',
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
