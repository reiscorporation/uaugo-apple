// ============================================================================
// home_screen.dart — Tela inicial
//
// O que faz: "Para onde?" (navegação sozinho), "Só dirigir", nome do piloto,
//   veículo, histórico, motoclube, criar/entrar em expedição e créditos.
// Quem usa: StartupGate.
// Onde mexer: Fluxo do "Para onde?": _whereTo (busca → prévia → MapScreen).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'club_screen.dart';
import 'consent_screen.dart';
import 'map_screen.dart';
import 'plan_screen.dart';
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
  BikeProfile _bike = const BikeProfile();
  String? _clubName;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
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
        builder: (_) =>
            MapScreen(code: code, uid: uid, userName: userName),
      ));
      if (left == true) await prefs.remove('lastCode');
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

  /// Abre "Minha moto / Meu carro".
  Future<void> _editBike() async {
    final b = await Navigator.of(context).push<BikeProfile>(
        MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (b != null) setState(() => _bike = b);
  }

  /// Abre o motoclube.
  Future<void> _openClub() async {
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
  Future<void> _whereTo() async {
    setState(() => _busy = true);
    final uid = await _prepareAlone();
    Position? me;
    if (uid != null) {
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
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlaceSearchPage(
            near: LatLng(me!.latitude, me.longitude), title: 'Para onde'),
      ),
    );
    if (picked == null || !mounted) return;
    final res = await TripPreviewSheet.show(context,
        title: picked.name,
        points: [
          TripPoint('Sua posição', me.latitude, me.longitude,
              type: StopType.meet),
          TripPoint(picked.name, picked.lat, picked.lng,
              type: StopType.destination),
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
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Configurações',
                  icon: const Icon(Icons.settings),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen())),
                ),
              ),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset('assets/branding/comboio_logo.png',
                      width: 96, height: 96),
                ),
              ),
              const SizedBox(height: 8),
              Text('Comboio',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Text('Viagens em grupo, de moto ou de carro',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _justDrive,
                  icon: const Icon(Icons.speed),
                  label: const Text('Só dirigir (radares e velocidade)'),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
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
                icon: const Icon(Icons.two_wheeler),
                label: Text(_bike.isEmpty
                    ? 'Configurar minha moto'
                    : 'Minha moto: ${_bike.displayName.isEmpty ? 'com foto' : _bike.displayName}'),
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
                    ? 'Motoclube'
                    : 'Motoclube: $_clubName'),
              ),
              if (_lastCode != null) ...[
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
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código (6 letras)',
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
