// ============================================================================
// plan_screen.dart — Roteiro da expedição
//
// O que faz: Paradas (adicionar, reordenar, editar), data e hora de saída,
//   opções de rota, agenda por dia, combustível estimado, simular a viagem. O
//   líder recalcula a rota (Directions) e todos recebem.
// Quem usa: MapScreen (botão de rota) e criação da expedição.
// Onde mexer: Recálculo: _recalc. Rotas antigas: _maybeUpgradeRoute.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/geo.dart';
import '../logic/itinerary.dart';
import '../models/expedition.dart';
import '../services/expedition_service.dart';
import '../logic/costs.dart';
import '../models/trip.dart';
import '../services/app_settings.dart';
import '../widgets/safe_sheet.dart';
import '../widgets/emoji_marker.dart';
import '../widgets/place_search.dart';
import '../logic/tolls.dart';
import '../services/profile_service.dart';
import '../services/toll_service.dart';
import '../logic/find_places.dart';
import '../logic/simulation.dart' show RouteWalker;
import '../services/places_service.dart';
import 'map_screen.dart';
import 'na_rota_screen.dart';
import 'profile_screen.dart';
import '../l10n/i18n.dart';
import '../widgets/toll_confirm_sheet.dart';

/// Planejamento do roteiro: pontos, rota pelas estradas, horários e dias.
/// O líder edita; os demais pilotos só visualizam e compartilham.
class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.code,
    required this.uid,
    this.showStartButton = false,
  });

  final String code;
  final String uid;

  /// Mostra "Abrir mapa do comboio" (quando vem direto da criação).
  final bool showStartButton;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

/// Estado do roteiro: expedição, paradas, rota e ícones.
class _PlanScreenState extends State<PlanScreen> {
  final _svc = ExpeditionService.instance;
  final List<StreamSubscription> _subs = [];
  GoogleMapController? _map;

  Expedition? _exp;
  List<Stop> _stops = [];
  bool _loaded = false;
  bool _routing = false;
  bool _routeFailed = false;
  final Map<StopType, BitmapDescriptor> _icons = {};
  String _polySig = '';
  List<LatLng> _route = [];
  String _fitSig = '';

  bool get _isLeader => _exp?.leaderId == widget.uid;
  TripPlan get _plan => _exp?.plan ?? const TripPlan();

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_svc.watchExpedition(widget.code).listen((e) {
        setState(() => _exp = e);
        _updateRoute();
        _maybeUpgradeRoute();
        _calcTolls();
      }))
      ..add(_svc.stops(widget.code).listen((s) {
        setState(() {
          _stops = s;
          _loaded = true;
        });
        _updateRoute();
        _fitToStops();
        _maybeUpgradeRoute();
      }));
    _loadIcons();
  }

  /// Pergunta o intervalo e inclui um posto a cada X km da rota.
  Future<void> _askFuelStops() async {
    var km = 150;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Paradas para abastecer')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Incluir uma parada num posto a cada:')),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final k in const [100, 150, 200, 250, 300])
                ChoiceChip(
                  label: Text('$k km'),
                  selected: km == k,
                  onSelected: (_) => set(() => km = k),
                ),
            ]),
            const SizedBox(height: 10),
            Text(
                tr('O app procura o posto mais perto de cada ponto, no caminho. Depois dá para trocar ou tirar no roteiro.'),
                style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Sugerir'))),
          ],
        ),
      ),
    );
    if (ok == true) await _suggestFuelStops(km);
  }

  /// Um posto a cada [km] km pela rota (o mais perto de cada ponto, até
  /// 5 km da rota), na ordem do caminho; recalcula uma vez no fim.
  Future<void> _suggestFuelStops(int km) async {
    final pts = [for (final q in decodePolyline(_plan.polyline)) (q.latitude, q.longitude)];
    if (pts.length < 2) return;
    final w = RouteWalker(pts);
    final every = km * 1000.0;
    final marks = <double>[
      for (var d = every; d < w.length - 30000 && d <= every * 15; d += every) d
    ];
    if (marks.isEmpty) {
      _snack(tr('A rota é mais curta que {0} km: não precisa de parada.', [km]));
      return;
    }
    setState(() => _routing = true);
    final places = PlacesService();
    final found = <({String name, double lat, double lng, double along})>[];
    for (final d in marks) {
      final at = w.at(d);
      final r = await places.find(FindCategory.fuel, lat: at.lat, lng: at.lng);
      if (r.limit) break;
      for (final f in r.places) {
        final pr = w.project(f.lat, f.lng);
        if (pr.offset > 5000) continue; // longe da rota
        found.add((name: f.name, lat: f.lat, lng: f.lng, along: pr.along));
        break;
      }
    }
    if (!mounted) return;
    if (found.isEmpty) {
      setState(() => _routing = false);
      _snack(tr('Não encontrei postos perto da rota. Tente outro intervalo.'));
      return;
    }
    // Insere na ordem do caminho, entre as paradas que já existem.
    final ok = await _guard(() async {
      final items = <({String id, double along})>[
        for (final st in _stops)
          (id: st.id, along: w.project(st.lat, st.lng).along),
      ];
      for (final f in found) {
        final id = _svc.addStop(widget.code, widget.uid, f.name, f.lat, f.lng,
            type: StopType.fuel, stayMin: 15);
        items.add((id: id, along: f.along));
      }
      // Saída e destino ficam nas pontas.
      final first = _stops.first.id, last = _stops.last.id;
      double rank(({String id, double along}) e) =>
          e.id == first ? -1e12 : (e.id == last ? 1e12 : e.along);
      items.sort((a, b) => rank(a).compareTo(rank(b)));
      await _svc.reorderStops(widget.code, items.map((e) => e.id).toList());
      return true;
    });
    if (!mounted) return;
    setState(() => _routing = false);
    if (!ok) {
      _snack(tr('Não foi possível salvar as paradas. Confira a internet.'));
      return;
    }
    _snack(tr('{0} {1} no roteiro.', [found.length, found.length == 1 ? tr('posto incluído') : tr('postos incluídos')]));
    // A lista de paradas chega pelo Firestore; recalcula com ela.
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) await _recalc();
  }

  /// Fração da tela ocupada pelo mapa (a alça muda; 0,2 a 0,75).
  double _mapFrac = 0.34;

  /// Pedágios da rota do roteiro para o MEU veículo (estimado).
  TollEstimate? _tolls;
  String _tollsSig = '';

  Future<void> _calcTolls() async {
    final poly = _plan.polyline;
    if (poly == _tollsSig) return;
    _tollsSig = poly;
    if (poly.isEmpty) {
      if (mounted) setState(() => _tolls = null);
      return;
    }
    final table = await TollService.instance.table();
    final bike = await ProfileService.load();
    if (!mounted || table == null || _tollsSig != poly) return;
    final line = [for (final q in decodePolyline(poly)) (q.latitude, q.longitude)];
    setState(() => _tolls = estimateTolls(table.onRoute(line), bike));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  /// Prepara os ícones das paradas (emoji por tipo).
  Future<void> _loadIcons() async {
    const colors = {
      StopType.meet: Colors.blue,
      StopType.fuel: Colors.green,
      StopType.food: Colors.deepOrange,
      StopType.rest: Colors.brown,
      StopType.sight: Colors.purple,
      StopType.overnight: Colors.indigo,
      StopType.waypoint: Colors.blueGrey,
      StopType.destination: Colors.red,
    };
    for (final t in StopType.values) {
      _icons[t] = await emojiMarker(t.emoji, colors[t]!);
    }
    if (mounted) setState(() {});
  }

  /// Rotas calculadas antes do traçado detalhado cortavam as curvas:
  /// quando o líder abre o roteiro, recalcula uma vez, sozinho.
  bool _upgradeTried = false;
  /// Rota antiga (cortava as curvas): o líder recalcula uma vez, sozinho.
  void _maybeUpgradeRoute() {
    if (_upgradeTried || !_loaded || _exp == null || !_isLeader) return;
    if (_stops.length < 2 ||
        _plan.routeVersion >= TripPlan.currentRouteVersion) {
      return;
    }
    _upgradeTried = true;
    _recalc();
  }

  /// Atualiza o traçado no mapa (rota salva ou linhas retas entre as paradas).
  void _updateRoute() {
    final poly = _plan.polyline;
    final sig = poly.isNotEmpty
        ? poly
        : _stops.map((s) => '${s.lat},${s.lng}').join(';');
    if (sig == _polySig) return;
    _polySig = sig;
    // Sem rota calculada, liga os pontos em linha reta (pontilhado).
    _route = poly.isNotEmpty
        ? decodePolyline(poly)
        : _stops.map((s) => LatLng(s.lat, s.lng)).toList();
  }

  /// Enquadra todas as paradas no mapa.
  void _fitToStops() {
    if (_map == null || _stops.isEmpty) return;
    final sig = _stops.map((s) => s.id).join();
    if (sig == _fitSig) return;
    _fitSig = sig;
    if (_stops.length == 1) {
      _map!.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(_stops.first.lat, _stops.first.lng), 12));
      return;
    }
    var minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
    for (final s in _stops) {
      if (s.lat < minLat) minLat = s.lat;
      if (s.lat > maxLat) maxLat = s.lat;
      if (s.lng < minLng) minLng = s.lng;
      if (s.lng > maxLng) maxLng = s.lng;
    }
    _map!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng)),
        48));
  }

  /// Mostra uma mensagem rápida no rodapé.
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------ ações do líder

  /// Recalcula a rota pelo Google e salva para o grupo (só o líder).
  Future<void> _recalc([List<Stop>? stops, TripPlan? plan]) async {
    setState(() {
      _routing = true;
      _routeFailed = false;
    });
    final ok = await _guard(() =>
        _svc.recalculateRoute(widget.code, plan ?? _plan, stops ?? _stops));
    if (!mounted) return;
    setState(() {
      _routing = false;
      _routeFailed = !ok;
    });
    if (!ok) _snack(tr('Não foi possível calcular a rota. Confira a internet.'));
  }

  /// Adiciona uma parada no fim (antes do destino) e recalcula.
  Future<void> _addPoint(String name, double lat, double lng,
      {String address = ''}) async {
    // Só a saída (1º ponto): não há rota para calcular, sem "carregando".
    final first = _stops.isEmpty;
    if (!first) setState(() => _routing = true);
    final ok = await _guard(() => _svc.addToItinerary(
          code: widget.code,
          uid: widget.uid,
          plan: _plan,
          current: _stops,
          name: name,
          lat: lat,
          lng: lng,
          address: address,
        ));
    if (!mounted) return;
    setState(() {
      _routing = false;
      _routeFailed = !ok;
    });
    if (!ok) {
      _snack(tr('Não foi possível salvar a parada. Confira a internet e tente de novo.'));
    }
  }

  /// Roda uma gravação do roteiro sem travar a tela: erro do servidor ou
  /// demora (sem internet o Firestore espera para sempre) viram "false" e os
  /// botões voltam a funcionar.
  Future<bool> _guard(Future<bool> Function() op) async {
    try {
      return await op().timeout(const Duration(seconds: 25));
    } catch (e) {
      debugPrint('Roteiro: $e');
      return false;
    }
  }

  /// Busca um lugar por nome para adicionar como parada.
  Future<void> _openSearch() async {
    Position? me;
    try {
      me = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    if (!mounted) return;
    final picked = await Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PlaceSearchPage(
        near: _stops.isNotEmpty
            ? LatLng(_stops.last.lat, _stops.last.lng)
            : me == null
                ? null
                : LatLng(me.latitude, me.longitude),
        title: _stops.isEmpty
            ? tr('Ponto de saída')
            : _stops.length == 1
                ? tr('Destino')
                : tr('Adicionar parada'),
      ),
    ));
    if (picked == null) return;
    await _addPoint(picked.name, picked.lat, picked.lng,
        address: picked.address);
  }

  /// Segurou no mapa: adiciona uma parada naquele ponto.
  Future<void> _addFromMap(LatLng pos) async {
    if (!_isLeader) return;
    var name = tr('Ponto no mapa');
    var address = '';
    try {
      final p = (await placemarkFromCoordinates(pos.latitude, pos.longitude))
          .firstOrNull;
      if (p != null) {
        final street = (p.street ?? '').trim();
        final city = (p.subAdministrativeArea ?? p.locality ?? '').trim();
        name = street.isNotEmpty && !street.contains('+')
            ? street
            : city.isNotEmpty
                ? city
                : name;
        address = [city, p.administrativeArea]
            .where((x) => x != null && x.trim().isNotEmpty)
            .join(' - ');
      }
    } catch (_) {}
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Adicionar ao roteiro?')),
        content: Text(address.isEmpty ? name : '$name\n$address'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Adicionar'))),
        ],
      ),
    );
    if (ok == true) {
      await _addPoint(name, pos.latitude, pos.longitude, address: address);
    }
  }

  /// [newIndex] já vem ajustado (onReorderItem desconta o item removido).
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    final list = [..._stops];
    final s = list.removeAt(oldIndex);
    list.insert(newIndex, s);
    // A primeira é sempre a partida e a última o destino final: quem foi
    // para o fim vira destino; o destino antigo, no meio, vira passagem.
    final retype = <String, StopType>{};
    for (var i = 0; i < list.length; i++) {
      final last = i == list.length - 1 && list.length > 1;
      final x = list[i];
      final t = last
          ? StopType.destination
          : x.type == StopType.destination
              ? StopType.waypoint
              : x.type;
      if (t != x.type) {
        retype[x.id] = t;
        list[i] = _withType(x, t);
      }
    }
    setState(() => _stops = list);
    await _guard(() async {
      await _svc.reorderStops(widget.code, list.map((x) => x.id).toList());
      for (final e in retype.entries) {
        await _svc.updateStop(widget.code, e.key, {'type': e.value.name});
      }
      return true;
    });
    await _recalc(list);
  }

  /// Cópia de [s] com outro tipo (partida/destino ao reordenar).
  Stop _withType(Stop s, StopType t) => Stop(
        id: s.id,
        name: s.name,
        lat: s.lat,
        lng: s.lng,
        order: s.order,
        createdBy: s.createdBy,
        address: s.address,
        type: t,
        stayMin: s.stayMin,
        notes: s.notes,
        nextDayStart: s.nextDayStart,
        legDistanceM: s.legDistanceM,
        legDurationS: s.legDurationS,
        steps: s.steps,
      );

  /// Remove uma parada (com confirmação) e recalcula.
  Future<void> _remove(Stop s) async {
    final list = [..._stops]..removeWhere((x) => x.id == s.id);
    setState(() => _stops = list);
    await _guard(() async {
      await _svc.removeStop(widget.code, s.id);
      await _svc.reorderStops(widget.code, list.map((x) => x.id).toList());
      return true;
    });
    await _recalc(list);
  }

  /// Salva o plano; [recalc] recalcula a rota (opções que mudam o caminho).
  Future<void> _savePlan(TripPlan p, {bool recalc = false}) async {
    await _svc.savePlan(widget.code, p.copyWith(polyline: _plan.polyline));
    if (recalc) await _recalc(null, p);
  }

  /// Escolhe a data de saída.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final cur = parseDate(_plan.startDate) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: cur.isBefore(now) ? now : cur,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      helpText: tr('Data de saída'),
    );
    if (d != null) await _savePlan(_plan.copyWith(startDate: formatYmd(d)));
  }

  /// Escolhe um horário (saída ou tempo parado).
  Future<String?> _pickTime(String current, String help) async {
    final (h, m) = parseHm(current);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      helpText: help,
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Edita uma parada (nome, tipo, tempo parado).
  Future<void> _editStop(Stop s) async {
    if (!_isLeader) return _viewStop(s);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _StopEditor(
        stop: s,
        isLast: _stops.isNotEmpty && _stops.last.id == s.id,
        pickTime: _pickTime,
        onSave: (data) => _svc.updateStop(widget.code, s.id, data),
        onDelete: () => _remove(s),
        onNavigate: () => _navigate(s),
      ),
    );
  }

  /// Mostra a parada no mapa.
  void _viewStop(Stop s) {
    showSafeSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Text(s.type.emoji, style: const TextStyle(fontSize: 28)),
            title: Text(s.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text([s.type.label, s.address, s.notes]
                .where((x) => x.trim().isNotEmpty)
                .join('\n')),
          ),
          ListTile(
            leading: const Icon(Icons.navigation),
            title: Text(tr('Navegar até aqui (Google Maps)')),
            onTap: () {
              Navigator.pop(ctx);
              _navigate(s);
            },
          ),
        ]),
      ),
    );
  }

  /// Abre o Google Maps navegando até a parada.
  Future<void> _navigate(Stop s) => launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1'
          '&destination=${s.lat},${s.lng}&travelmode=driving'),
      mode: LaunchMode.externalApplication);

  /// Compartilha o roteiro (texto com paradas e horários + link do mapa).
  Future<void> _share() async {
    if (_stops.length < 2) {
      _snack(tr('Adicione pelo menos a saída e o destino'));
      return;
    }
    final text = buildShareText(
      expeditionName: _exp?.name ?? tr('Expedição'),
      code: widget.code,
      schedule: buildSchedule(_plan, _stops),
    );
    await SharePlus.instance.share(
        ShareParams(text: text, subject: _exp?.name ?? tr('Roteiro')));
  }

  /// Copia o roteiro como texto.
  Future<void> _copy() async {
    final text = buildShareText(
      expeditionName: _exp?.name ?? tr('Expedição'),
      code: widget.code,
      schedule: buildSchedule(_plan, _stops),
    );
    await Clipboard.setData(ClipboardData(text: text));
    _snack(tr('Roteiro copiado'));
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final schedule = buildSchedule(_plan, _stops);
    return Scaffold(
      resizeToAvoidBottomInset: false, // mapa não redimensiona com o teclado (evita travamento)
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Roteiro')),
          Text(_exp?.name ?? '',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.copy),
              tooltip: tr('Copiar roteiro'),
              onPressed: _stops.length < 2 ? null : _copy),
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: tr('Enviar roteiro (WhatsApp...)'),
              onPressed: _share),
        ],
      ),
      // Barra fixa do líder, sempre acima dos botões do celular.
      bottomNavigationBar: _isLeader ? _leaderBar() : null,
      body: Column(children: [
        SizedBox(
          // Altura do mapa: arraste a alça (abaixo) para aumentar ou diminuir.
          height: MediaQuery.of(context).size.height * _mapFrac,
          child: Stack(children: [
            GoogleMap(
              initialCameraPosition: const CameraPosition(
                  target: LatLng(-15.78, -47.93), zoom: 4),
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
              markers: {
                for (var i = 0; i < _stops.length; i++)
                  Marker(
                    markerId: MarkerId(_stops[i].id),
                    position: LatLng(_stops[i].lat, _stops[i].lng),
                    anchor: const Offset(0.5, 0.5),
                    icon: _icons[_stops[i].type] ??
                        BitmapDescriptor.defaultMarker,
                    infoWindow: InfoWindow(
                      title: '${i + 1}. ${_stops[i].name}',
                      onTap: () => _editStop(_stops[i]),
                    ),
                  ),
              },
              polylines: {
                if (_route.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _route,
                    width: 5,
                    color: MapScreen.routeBlue,
                    patterns: _plan.polyline.isEmpty
                        ? [PatternItem.dash(20), PatternItem.gap(12)]
                        : const [],
                  ),
              },
              onMapCreated: (c) {
                _map = c;
                _fitToStops();
              },
              onLongPress: _addFromMap,
            ),
            if (_routing)
              const Positioned(
                  top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
            if (_isLeader && _stops.isEmpty)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Text(
                      tr('Busque um lugar pelo botão abaixo ou toque e segure no mapa'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ]),
        ),
        // Alça: arraste para baixo = mapa maior; para cima = lista maior.
        // Toque: alterna entre mapa grande e normal.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _mapFrac = _mapFrac < 0.5 ? 0.7 : 0.34),
          onVerticalDragUpdate: (d) => setState(() {
            final h = MediaQuery.of(context).size.height;
            _mapFrac = (_mapFrac + d.delta.dy / h).clamp(0.2, 0.75);
          }),
          child: Container(
            height: 22,
            alignment: Alignment.center,
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        Expanded(child: _buildList(schedule)),
      ]),
    );
  }

  /// Roteiro pronto para sair (2 pontos e rota calculada).
  bool get _ready => _stops.length >= 2 && _plan.polyline.isNotEmpty;

  /// Barra do líder: adicionar ponto, salvar (volta) e iniciar a viagem.
  Widget _leaderBar() => SafeArea(
        top: false,
        child: Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(children: [
              Expanded(
                flex: 5,
                child: FilledButton.tonalIcon(
                  onPressed: _routing ? null : _openSearch,
                  icon: const Icon(Icons.add_location_alt),
                  label: Text(
                      _stops.isEmpty
                          ? tr('Saída')
                          : _stops.length == 1
                              ? tr('Destino')
                              : tr('Parada'),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: OutlinedButton(
                  onPressed: _routing
                      ? null
                      : () {
                          _snack(tr('Roteiro salvo: o grupo já vê as mudanças.'));
                          Navigator.of(context).pop(false);
                        },
                  child: Text(tr('Salvar')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: FilledButton.icon(
                  onPressed: _ready && !_routing
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  icon: const Icon(Icons.navigation),
                  label: Text(tr('Iniciar')),
                ),
              ),
            ]),
          ),
        ),
      );

  /// Lista das paradas com horários, separada por dia (o líder reordena).
  Widget _buildList(Schedule schedule) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final header = _PlanHeader(
      tolls: _tolls,
      plan: _plan,
      schedule: schedule,
      editable: _isLeader,
      routeFailed: _routeFailed,
      onDate: _pickDate,
      onTime: () async {
        final t = await _pickTime(_plan.startTime, tr('Hora de saída'));
        if (t != null) await _savePlan(_plan.copyWith(startTime: t));
      },
      onTolls: (v) => _savePlan(_plan.copyWith(avoidTolls: v), recalc: true),
      onHighways: (v) =>
          _savePlan(_plan.copyWith(avoidHighways: v), recalc: true),
      onRetry: () => _recalc(),
      onFuelStops: _isLeader && _stops.length >= 2 && _plan.polyline.isNotEmpty
          ? _askFuelStops
          : null,
      // O líder usa a barra de baixo (Salvar / Iniciar).
      onStart: widget.showStartButton && !_isLeader
          ? () => Navigator.of(context).pop(true)
          : null,
      // Simular: percorre o roteiro na tela, com narração e avisos.
      onSimulate: _stops.length >= 2 && _plan.polyline.isNotEmpty
          ? () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MapScreen(
                  code: widget.code,
                  uid: widget.uid,
                  userName: tr('Você'),
                  simulate: true,
                  trip: Trip(
                      title: _exp?.name ?? tr('Roteiro'),
                      plan: _plan,
                      stops: _stops),
                ),
              ))
          : null,
    );

    final items = schedule.stops;
    return ReorderableListView.builder(
      // A barra do líder fica fora da lista (bottomNavigationBar).
      padding: EdgeInsets.only(
          bottom: 16 +
              (_isLeader ? 0 : MediaQuery.of(context).viewPadding.bottom)),
      header: header,
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: _isLeader ? _onReorder : (_, __) {},
      itemBuilder: (ctx, i) {
        final x = items[i];
        final newDay = i == 0 || items[i - 1].day != x.day;
        final day = schedule.days.firstWhere((d) => d.day == x.day);
        return _StopTile(
          key: ValueKey(x.stop.id),
          item: x,
          isLast: i == items.length - 1,
          dayHeader: newDay && schedule.days.length > 1
              ? tr('Dia {0}{1} · {2} · {3}', [day.day, schedule.hasDate ? ' · ${formatDay(day.date)}' : '', formatDistance(day.distanceM), formatDuration(day.rideS)])
              : null,
          dragIndex: _isLeader ? i : null,
          onTap: () => _editStop(x.stop),
        );
      },
    );
  }
}

// ============================================================ cabeçalho

/// Cabeçalho do roteiro: totais, data/hora, opções de rota, combustível,
/// simular e iniciar.
class _PlanHeader extends StatelessWidget {
  const _PlanHeader({
    required this.plan,
    this.tolls,
    required this.schedule,
    required this.editable,
    required this.routeFailed,
    required this.onDate,
    required this.onTime,
    required this.onTolls,
    required this.onHighways,
    required this.onRetry,
    this.onFuelStops,
    this.onStart,
    this.onSimulate,
  });

  final TripPlan plan;

  /// Pedágios da rota (estimado) para o veículo do piloto.
  final TollEstimate? tolls;
  final Schedule schedule;
  final bool editable;
  final bool routeFailed;
  final VoidCallback onDate;
  final VoidCallback onTime;
  final ValueChanged<bool> onTolls;
  final ValueChanged<bool> onHighways;
  final VoidCallback onRetry;

  /// "Paradas a cada X km" (só o líder, com rota calculada).
  final VoidCallback? onFuelStops;
  final VoidCallback? onStart;
  final VoidCallback? onSimulate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = parseDate(plan.startDate);
    final s = schedule;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (s.stops.length >= 2)
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _Stat(Icons.straighten, formatDistance(s.totalDistanceM)),
            _Stat(Icons.timer_outlined, formatDuration(s.totalRideS)),
            _Stat(Icons.calendar_month,
                s.days.length == 1 ? tr('1 dia') : '${s.days.length} dias'),
          ]),
        // Combustível estimado (opcional: "Minha moto" → consumo e gastos).
        // Cada piloto vê o próprio gasto, pelo consumo do SEU veículo
        // ("Meu veículo", fica no celular); sem consumo, convida a informar.
        if (s.stops.length >= 2)
          ValueListenableBuilder<FuelPrefs>(
            valueListenable: AppSettings.instance.fuel,
            builder: (context, f, _) {
              if (!f.ready) {
                return Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.local_gas_station_outlined, size: 18),
                    label: Text(tr('Informe o consumo do seu veículo para ver seu gasto')),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen())),
                  ),
                );
              }
              final l = fuelLiters(s.totalDistanceM.toDouble(), f.kmPerLiter);
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('⛽ Seu combustível estimado: {0} L · {1}', [formatDecimal(l), formatMoney(l * f.pricePerLiter)]) +
                      tr(' ({0} km/l)', [formatDecimal(f.kmPerLiter)]),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        // Pedágios da rota para o seu veículo (estimado) e custo total.
        if (s.stops.length >= 2 && tolls != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tolls!.plazas == 0
                  ? tr('🛣️ Sem pedágio na rota')
                  : tr('🛣️ Pedágios: {0} ({1} {2}, estimado)', [formatMoney(tolls!.total), tolls!.plazas, tolls!.plazas == 1 ? tr('praça') : tr('praças')]),
              textAlign: TextAlign.center,
            ),
          ),
        if (s.stops.length >= 2 && tolls != null && tolls!.list.any((p) => p.editable))
          Center(
            child: TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(tr('Confirmar valores dos pedágios ({0} a confirmar)', [tolls!.toConfirm])),
                  onPressed: () => TollConfirmSheet.show(context, tolls!.list),
                ),
          ),
        if (s.stops.length >= 2 && tolls != null)
          ValueListenableBuilder<FuelPrefs>(
            valueListenable: AppSettings.instance.fuel,
            builder: (_, f, __) {
            if (!f.ready) return const SizedBox.shrink();
            final fuel = fuelLiters(s.totalDistanceM.toDouble(), f.kmPerLiter) *
                f.pricePerLiter;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                tr('💰 Custo estimado: {0} (combustível + pedágios)', [formatMoney(fuel + tolls!.total)]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          }),
        if (routeFailed)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.cloud_off),
              title: Text(tr('Rota não calculada (linha pontilhada)')),
              trailing: editable
                  ? TextButton(onPressed: onRetry, child: Text(tr('Tentar')))
                  : null,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(
            avatar: const Icon(Icons.event, size: 18),
            label: Text(date == null ? tr('Definir data') : formatDay(date)),
            onPressed: editable ? onDate : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.schedule, size: 18),
            label: Text(tr('Saída {0}', [plan.startTime])),
            onPressed: editable ? onTime : null,
          ),
          FilterChip(
            label: Text(tr('Evitar pedágios')),
            selected: plan.avoidTolls,
            onSelected: editable ? onTolls : null,
          ),
          FilterChip(
            label: Text(tr('Evitar rodovias')),
            selected: plan.avoidHighways,
            onSelected: editable ? onHighways : null,
          ),
        ]),
        if (onFuelStops != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onFuelStops,
            icon: const Icon(Icons.local_gas_station_outlined),
            label: Text(tr('Paradas para abastecer a cada X km')),
          ),
        ],
        if (onSimulate != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onSimulate,
            icon: const Icon(Icons.play_circle_outline),
            label: Text(tr('Simular a viagem')),
          ),
        ],
        if (onStart != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onStart,
            icon: const Icon(Icons.map),
            label: Text(tr('Abrir mapa do comboio')),
          ),
        ],
        if (editable && s.stops.length >= 2)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('Toque num ponto para editar · arraste ⠿ para reordenar · um "Pernoite" encerra o dia'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ]),
    );
  }
}

/// Um número do cabeçalho com ícone (km, tempo, dias).
class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      ]);
}

// ============================================================ item da lista

/// Uma parada da lista: horários, tipo, distância do trecho.
class _StopTile extends StatelessWidget {
  const _StopTile({
    super.key,
    required this.item,
    required this.isLast,
    required this.dayHeader,
    required this.dragIndex,
    required this.onTap,
  });

  final ScheduledStop item;
  final bool isLast;
  final String? dayHeader;
  final int? dragIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = item.stop;
    final times = item.isStart
        ? tr('Saída {0}', [formatTime(item.departure)])
        : isLast || item.departure == item.arrival
            ? tr('Chegada {0}', [formatTime(item.arrival!)])
            : s.type == StopType.overnight
                ? tr('Chegada {0} · sai {1} do dia seguinte', [formatTime(item.arrival!), s.nextDayStart])
                : '${formatTime(item.arrival!)} – ${formatTime(item.departure)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dayHeader != null)
          Container(
            color: theme.colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(dayHeader!,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
        if (!item.isStart && s.legDistanceM > 0)
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2),
            child: Text(
              '↓ ${formatDistance(s.legDistanceM)} · ${formatDuration(s.legDurationS)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Text(s.type.emoji, style: const TextStyle(fontSize: 20)),
          ),
          title: Text('${item.index + 1}. ${s.name}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [
              times,
              if (s.notes.trim().isNotEmpty) s.notes.trim(),
            ].join('\n'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: dragIndex == null
              ? null
              : ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
        ),
      ],
    );
  }
}

// ============================================================ editor do ponto

/// Janela de edição de uma parada.
class _StopEditor extends StatefulWidget {
  const _StopEditor({
    required this.stop,
    required this.isLast,
    required this.pickTime,
    required this.onSave,
    required this.onDelete,
    required this.onNavigate,
  });

  final Stop stop;
  final bool isLast;
  final Future<String?> Function(String current, String help) pickTime;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  final Future<void> Function() onDelete;
  final Future<void> Function() onNavigate;

  @override
  State<_StopEditor> createState() => _StopEditorState();
}

/// Estado da edição: nome, tipo e tempo parado.
class _StopEditorState extends State<_StopEditor> {
  late final _name = TextEditingController(text: widget.stop.name);
  late final _notes = TextEditingController(text: widget.stop.notes);
  late StopType _type = widget.stop.type;
  late int _stay = widget.stop.stayMin;
  late String _nextDay = widget.stop.nextDayStart;

  static const _stayOptions = [0, 10, 15, 20, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          // Teclado + barra de navegação do Android (botão Salvar visível).
          bottom: MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom +
              16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Editar ponto'), style: theme.textTheme.titleLarge),
            if (widget.stop.address.isNotEmpty)
              Text(widget.stop.address, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                  labelText: tr('Nome'), border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Text(tr('Tipo'), style: theme.textTheme.labelLarge),
            Wrap(spacing: 6, runSpacing: 0, children: [
              for (final t in StopType.values)
                ChoiceChip(
                  label: Text('${t.emoji} ${t.label}'),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ]),
            if (!widget.isLast && _type != StopType.overnight) ...[
              const SizedBox(height: 12),
              Text(tr('Tempo parado'), style: theme.textTheme.labelLarge),
              Wrap(spacing: 6, children: [
                for (final m in _stayOptions)
                  ChoiceChip(
                    label: Text(m == 0 ? tr('Não para') : formatDuration(m * 60)),
                    selected: _stay == m,
                    onSelected: (_) => setState(() => _stay = m),
                  ),
              ]),
            ],
            if (_type == StopType.overnight && !widget.isLast) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wb_sunny_outlined),
                title: Text(tr('Saída no dia seguinte')),
                trailing: Text(_nextDay, style: theme.textTheme.titleMedium),
                onTap: () async {
                  final t = await widget.pickTime(_nextDay, tr('Saída no dia seguinte'));
                  if (t != null) setState(() => _nextDay = t);
                },
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Observações'),
                hintText: tr('Ex.: abastecer cheio, próximo posto a 120 km'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              IconButton(
                tooltip: tr('Remover do roteiro'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.onDelete();
                },
              ),
              IconButton(
                tooltip: tr('Navegar até aqui'),
                icon: const Icon(Icons.navigation_outlined),
                onPressed: widget.onNavigate,
              ),
              IconButton(
                tooltip: tr('Turismo, hospedagem e postos'),
                icon: const Icon(Icons.travel_explore),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NaRotaScreen(
                    lat: widget.stop.lat,
                    lng: widget.stop.lng,
                    lugar: widget.stop.name,
                    aba: widget.stop.type == StopType.overnight ? 1 : 0,
                  ),
                )),
              ),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('Cancelar'))),
              FilledButton(
                onPressed: () async {
                  final name = _name.text.trim();
                  Navigator.pop(context);
                  await widget.onSave({
                    if (name.isNotEmpty) 'name': name,
                    'type': _type.name,
                    'stayMin': _type == StopType.overnight ? 0 : _stay,
                    'notes': _notes.text.trim(),
                    'nextDayStart': _nextDay,
                  });
                },
                child: Text(tr('Salvar')),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
