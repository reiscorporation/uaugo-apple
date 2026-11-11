// ============================================================================
// trip_preview_sheet.dart — Prévia da rota
//
// O que faz: Antes de navegar: tempo, distância, chegada, trânsito,
//   combustível, pedágio, áreas de risco, opções (pedágios, rodovias, risco) e
//   os botões Simular / Iniciar. A saída pode ser trocada ("Trocar") para
//   planejar ou simular uma viagem que começa em outro lugar. Dá para
//   adicionar/remover paradas no caminho antes de iniciar.
// Quem usa: Home ("Para onde?").
// ============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../screens/na_rota_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/best_order.dart';
import '../logic/costs.dart';
import '../logic/geo.dart' show decodePolyline;
import '../logic/itinerary.dart';
import '../logic/radars.dart' show distanceMeters;
import '../logic/tolls.dart';
import '../logic/rodizio.dart';
import '../models/bike.dart';
import '../models/expedition.dart' show StopType;
import '../models/trip.dart';
import 'place_search.dart';
import '../services/app_settings.dart';
import '../services/profile_service.dart';
import '../services/planned_trips_service.dart';
import '../services/toll_service.dart';
import '../services/voice_service.dart';
import '../services/trip_service.dart';
import '../services/route_engine_service.dart';
import '../l10n/i18n.dart';
import 'toll_confirm_sheet.dart';
import '../services/calendar_service.dart';

/// O que o piloto escolheu na prévia da viagem.
enum TripAction { start, simulate }

/// Prévia da navegação sozinho: distância, tempo, opções e os botões
/// "Simular" e "Iniciar". Recalcula ao mudar as opções.
class TripPreviewSheet extends StatefulWidget {
  const TripPreviewSheet(
      {super.key,
      required this.title,
      required this.points,
      this.autoStart = false});

  final String title;
  final List<TripPoint> points;
  final bool autoStart;

  /// Mostra a prévia e devolve (ação, viagem) ou null se cancelar.
  /// [autoStart] (destino escolhido por voz): calculada a rota, fala o
  /// destino e o tempo e inicia sozinha em 5 s (dá para cancelar).
  static Future<(TripAction, Trip)?> show(BuildContext context,
          {required String title,
          required List<TripPoint> points,
          bool autoStart = false}) =>
      // Tela cheia: o mapa com a rota atrás e o painel dos cálculos por
      // cima (arrasta para baixo para ver a rota inteira).
      showModalBottomSheet<(TripAction, Trip)>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: false,
        builder: (_) => TripPreviewSheet(
            title: title, points: points, autoStart: autoStart),
      );

  @override
  State<TripPreviewSheet> createState() => _TripPreviewSheetState();
}

/// Recalcula a rota quando o piloto muda alguma opção.
class _TripPreviewSheetState extends State<TripPreviewSheet> {
  Trip? _trip;

  /// Rotas possíveis (a 1ª é a indicada); o piloto escolhe outra.
  List<Trip> _options = const [];
  bool _loading = true;
  bool _tolls = false;
  bool _highways = false;

  /// Pontos da viagem (o 1º é a saída, que o piloto pode trocar para
  /// planejar ou simular uma viagem que começa em outro lugar).
  late final List<TripPoint> _points = [...widget.points];

  /// Nome da viagem: o destino final (muda se o piloto reordenar).
  late String _title = widget.title;

  /// Saída planejada (null = agora): muda a chegada e o aviso de rodízio, e
  /// permite salvar a viagem para depois.
  DateTime? _departAt;

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _departAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: tr('Dia da saída'),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departAt ?? now),
      helpText: tr('Hora da saída'),
    );
    if (t == null || !mounted) return;
    setState(() => _departAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    _calcTolls(); // refaz o aviso de rodízio para o horário escolhido
  }

  Future<void> _savePlanned() async {
    final at = _departAt;
    if (at == null) return;
    await PlannedTripsService.instance.add(widget.title, at, [..._points]);
    if (!mounted) return;
    final dur = _trip == null ? null : Duration(seconds: _trip!.durationS);
    final title = widget.title, dest = _points.last.name;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(tr('Viagem planejada salva. Ela aparece na tela inicial.')),
        // Lembrete com alarme na agenda do celular (sem permissão de agenda).
        action: SnackBarAction(
          label: tr('Pôr na agenda'),
          onPressed: () => CalendarService.addTrip(
              title: title, departAt: at, duration: dur, destination: dest),
        )));
    Navigator.pop(context);
  }

  /// A saída é a posição atual do GPS? (Senão, é um lugar escolhido.)
  bool _fromHere = true;

  /// Troca o ponto de saída (busca um lugar por nome ou volta ao GPS).
  Future<void> _changeOrigin() async {
    _cancelAuto();
    final here = widget.points.first;
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlaceSearchPage(
            near: LatLng(here.lat, here.lng), title: tr('Saindo de')),
      ),
    );
    if (picked == null || !mounted) return;
    // "Usar minha localização" devolve um lugar a poucos metros do GPS.
    final isHere =
        distanceMeters(picked.lat, picked.lng, here.lat, here.lng) < 100;
    setState(() {
      _fromHere = isHere;
      _points[0] = isHere
          ? here
          : TripPoint(picked.name, picked.lat, picked.lng,
              type: StopType.meet);
    });
    _calc();
  }

  /// Adiciona uma parada no caminho (fica antes do destino). Até 10 paradas.
  Future<void> _addStop() async {
    _cancelAuto();
    final ref = _points[_points.length - 2]; // busca perto do último ponto
    final picked = await Navigator.of(context).push<PickedPlace>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PlaceSearchPage(
            near: LatLng(ref.lat, ref.lng), title: tr('Parada no caminho')),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _points.insert(_points.length - 1,
        TripPoint(picked.name, picked.lat, picked.lng)));
    _calc();
  }

  /// Remove a parada [i] (1 = primeira parada depois da saída).
  void _removeStop(int i) {
    _cancelAuto();
    setState(() => _points.removeAt(i));
    _calc();
  }

  /// Arrastou uma parada/destino para outra posição (a saída fica fixa).
  void _reorder(int from, int to) {
    _cancelAuto();
    if (to > from) to--;
    if (from == to) return;
    setState(() {
      final p = _points.removeAt(from + 1);
      _points.insert(to + 1, p);
      _title = _points.last.name;
    });
    _calc();
  }

  /// Paradas e destino em ordem, com alça para arrastar e "remover".
  Widget _stopsList() {
    final n = _points.length - 1;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: n,
      onReorder: _loading ? (_, __) {} : _reorder,
      itemBuilder: (_, k) {
        final i = k + 1, last = i == _points.length - 1;
        return Row(key: ValueKey('${_points[i].lat},${_points[i].lng},$i'), children: [
          ReorderableDragStartListener(
            index: k,
            enabled: !_loading,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Icon(Icons.drag_handle),
            ),
          ),
          const SizedBox(width: 6),
          Icon(last ? Icons.flag : Icons.more_vert,
              color: last ? Colors.red : Colors.amber, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                last
                    ? tr('Destino: {0}', [_points[i].name])
                    : tr('Parada {0}: {1}', [i, _points[i].name]),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: tr('Remover parada'),
            icon: const Icon(Icons.close, size: 20),
            onPressed: _loading || _points.length <= 2
                ? null
                : () {
                    _removeStop(i);
                    if (mounted) setState(() => _title = _points.last.name);
                  },
          ),
        ]);
      },
    );
  }

  /// Calculando a melhor sequência.
  bool _ordering = false;

  /// Vários destinos: testa as ordens mais curtas no Google (com o trânsito
  /// do momento) e fica com a mais rápida. A saída fica fixa; o fim é livre.
  Future<void> _bestOrder() async {
    _cancelAuto();
    final before = _trip;
    final dests = _points.sublist(1);
    final orders = bestOrders((_points.first.lat, _points.first.lng),
        [for (final p in dests) (p.lat, p.lng)]);
    setState(() => _ordering = true);
    Trip? best;
    List<TripPoint>? bestPts;
    for (final o in orders) {
      final pts = [_points.first, for (final i in o) dests[i]];
      final t = await TripService.build(
          title: pts.last.name,
          points: pts,
          avoidTolls: _tolls,
          avoidHighways: _highways);
      if (!mounted) return;
      if (t != null && (best == null || t.durationS < best.durationS)) {
        best = t;
        bestPts = pts;
      }
    }
    setState(() => _ordering = false);
    if (best == null || bestPts == null) {
      _snack(tr('Não foi possível calcular a melhor sequência. Confira a internet.'));
      return;
    }
    final saveMin = before == null ? 0 : ((before.durationS - best.durationS) / 60).round();
    final saveKm = before == null ? 0.0 : (before.distanceM - best.distanceM) / 1000;
    setState(() {
      _points
        ..clear()
        ..addAll(bestPts!);
      _title = _points.last.name;
      _trip = best;
      _options = [best!];
      _tollCost = null;
    });
    _calcTolls();
    _snack(saveMin > 0 || saveKm > 0.5
        ? tr('Sequência ajustada: economiza {0} min e {1} km.', [saveMin, saveKm.toStringAsFixed(1).replaceAll('.', ',')])
        : tr('A ordem atual já era a melhor.'));
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void initState() {
    super.initState();
    // Começa com as preferências salvas em Configurações → Rotas.
    final s = AppSettings.instance.route.value;
    _tolls = s.avoidTolls;
    _highways = s.avoidHighways;
    _calc();
    _loadDragIcons();
    ProfileService.load().then((b) {
      if (!mounted) return;
      setState(() => _bike = b);
      _calcTolls();
    });
    ProfileService.loadPlate().then((p) {
      _plate = p;
      if (mounted) _calcTolls();
    });
  }

  /// Placa (só no celular) e aviso de rodízio de São Paulo para esta rota.
  String _plate = '';
  String? _rodizio;

  BikeProfile _bike = const BikeProfile();

  /// Pedágios da rota para o veículo (null enquanto calcula ou sem tabela).
  TollEstimate? _tollCost;

  /// Acha as praças da rota na tabela de pedágios e soma para o veículo.
  Future<void> _calcTolls() async {
    final t = _trip;
    if (t == null) return;
    final table = await TollService.instance.table();
    if (table == null || !mounted || _trip != t) return;
    final line = [
      for (final p in decodePolyline(t.plan.polyline)) (p.latitude, p.longitude)
    ];
    setState(() {
      _tollCost = estimateTolls(table.onRoute(line), _bike);
      _rodizio = rodizioWarning(
          plate: _plate,
          style: _bike.style,
          route: line,
          when: _departAt ?? DateTime.now());
    });
  }

  // ---- Início automático (destino por voz)
  late bool _autoArmed = widget.autoStart;
  int? _countdown;
  Timer? _autoTimer;

  /// Rota pronta: fala o destino e conta 5 s para iniciar.
  void _startCountdown(Trip t) {
    final min = (t.durationS / 60).round();
    VoiceService.instance.reply(tr('Rota para {0}: {1}. Iniciando.', [widget.title, min < 60 ? tr('{0} minutos', [min]) : tr('{0} horas e {1} minutos', [min ~/ 60, min % 60])]));
    setState(() => _countdown = 5);
    _autoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      final c = (_countdown ?? 1) - 1;
      if (c <= 0) {
        timer.cancel();
        Navigator.pop(context, (TripAction.start, t));
      } else {
        setState(() => _countdown = c);
      }
    });
  }

  /// O piloto mexeu na prévia (ou tocou em "Cancelar"): não inicia sozinho.
  void _cancelAuto() {
    _autoArmed = false;
    _autoTimer?.cancel();
    if (_countdown != null && mounted) setState(() => _countdown = null);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  /// Calcula a rota com as opções escolhidas.
  Future<void> _calc() async {
    // Recalcular (opção trocada) depois de armado = o piloto mexeu: cancela.
    if (_countdown != null) _cancelAuto();
    setState(() => _loading = true);
    final t = await TripService.build(
      title: _title,
      points: _points,
      avoidTolls: _tolls,
      avoidHighways: _highways,
      // Sem paradas no meio: traz até 2 outras rotas para escolher.
      alternatives: _points.length == 2,
    );
    if (!mounted) return;
    setState(() {
      _trip = t;
      _options = t == null ? const [] : [t, ...t.alternatives.take(2)];
      _tollCost = null;
      _loading = false;
    });
    _calcTolls();
    if (_autoArmed && t != null) {
      _autoArmed = false;
      _startCountdown(t);
    }
  }

  /// Frases de pedágio da prévia.
  List<String> _tollLines(Trip t) {
    final e = _tollCost;
    if (e != null && e.plazas > 0) return describeTolls(e, _bike, formatMoney);
    if (!t.hasToll) return const [];
    // O Google indica pedágio, mas a praça não está na tabela.
    final noun = _bike.style.noun;
    return [
      tr('🛣️ Rota com pedágio. Os valores não foram fornecidos pelos órgãos responsáveis.'),
      _bike.style.isMoto
          ? tr('Na maioria das praças a moto paga metade do valor do carro.')
          : tr('{0}{1} paga pedágio.', [noun[0].toUpperCase(), noun.substring(1)]),
    ];
  }

  /// Combustível + pedágios, quando os dois são conhecidos.
  double? _tripCost(Trip t) {
    final f = AppSettings.instance.fuel.value;
    final e = _tollCost;
    if (!f.ready) return null;
    // Sem pedágio (ou valores ainda não conhecidos): só o combustível.
    final tolls = e != null && e.complete ? e.total : 0.0;
    return fuelLiters(t.distanceM.toDouble(), f.kmPerLiter) * f.pricePerLiter + tolls;
  }

  // ---- Mapa da prévia (rota escolhida em azul, as outras em cinza)

  GoogleMapController? _map;

  /// Fração da tela ocupada pelo painel (para o mapa não esconder a rota).
  double _sheetFrac = 0.6;
  String _fittedSig = '';

  Set<Polyline> _routeLines() {
    final t = _trip;
    if (t == null) return const {};
    return {
      for (var i = 0; i < _options.length; i++)
        if (!identical(_options[i], t))
          Polyline(
            polylineId: PolylineId('alt$i'),
            points: decodePolyline(_options[i].plan.polyline),
            color: Colors.grey.shade500,
            width: 6,
            consumeTapEvents: true,
            onTap: () => _chooseRoute(_options[i]),
          ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: decodePolyline(t.plan.polyline),
        color: const Color(0xFF1A73E8),
        width: 7,
        zIndex: 2,
      ),
    };
  }

  // ---- Arrastar a rota (11/11): bolinhas na linha e as paradas do meio
  // podem ser arrastadas; a rota recalcula enquanto arrasta (a cada ~1,2 s)
  // e de novo ao soltar. Segurar no mapa inclui um ponto de passagem ali.

  static const _maxPoints = 12; // saída + até 10 paradas + destino
  BitmapDescriptor? _handleIcon;
  BitmapDescriptor? _viaIcon;

  /// O piloto mexeu na rota pelo mapa: não reenquadra (a câmera ficava
  /// pulando enquanto arrastava).
  bool _userMoved = false;

  /// Arrastando: bolinha [handle] (vira parada nova) ou parada [stop].
  String? _dragId;
  List<LatLng> _frozenHandles = const [];
  int _dragSeq = 0;
  bool _liveBusy = false;
  DateTime _lastLive = DateTime(0);

  Future<BitmapDescriptor> _dot(Color fill, double r) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final size = r * 2 + 8;
    final o = Offset(size / 2, size / 2);
    c.drawCircle(o, r + 3, Paint()..color = Colors.white);
    c.drawCircle(o, r, Paint()..color = fill);
    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final b = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(b!.buffer.asUint8List(),
        width: size / 2.6, height: size / 2.6);
  }

  Future<void> _loadDragIcons() async {
    final h = await _dot(const Color(0xFF1A73E8), 22);
    final v = await _dot(const Color(0xFFFF7A1A), 22);
    if (mounted) setState(() {
      _handleIcon = h;
      _viaIcon = v;
    });
  }

  /// Bolinhas na rota (a 20, 40, 60 e 80% do caminho), longe das paradas.
  List<LatLng> _handles() {
    if (_dragId != null) return _frozenHandles;
    final t = _trip;
    if (t == null || _points.length >= _maxPoints) return const [];
    final pts = decodePolyline(t.plan.polyline);
    if (pts.length < 2) return const [];
    final acc = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      acc.add(acc.last + distanceMeters(pts[i - 1].latitude, pts[i - 1].longitude,
          pts[i].latitude, pts[i].longitude));
    }
    final total = acc.last;
    if (total < 400) return const [];
    final out = <LatLng>[];
    var j = 0;
    for (final f in [0.2, 0.4, 0.6, 0.8]) {
      while (j < acc.length - 1 && acc[j] < total * f) {
        j++;
      }
      final q = pts[j];
      final nearStop = _points.any((p) =>
          distanceMeters(p.lat, p.lng, q.latitude, q.longitude) < total * 0.08);
      if (!nearStop) out.add(q);
    }
    return out;
  }

  /// Onde entra um ponto novo: entre os dois pontos em que desvia menos.
  int _insertIndexFor(LatLng q) {
    var best = 1;
    var bestCost = double.infinity;
    for (var i = 1; i < _points.length; i++) {
      final a = _points[i - 1], b = _points[i];
      final cost = distanceMeters(a.lat, a.lng, q.latitude, q.longitude) +
          distanceMeters(q.latitude, q.longitude, b.lat, b.lng) -
          distanceMeters(a.lat, a.lng, b.lat, b.lng);
      if (cost < bestCost) {
        bestCost = cost;
        best = i;
      }
    }
    return best;
  }

  TripPoint _via(LatLng q) =>
      TripPoint(tr('Passando por aqui'), q.latitude, q.longitude);

  /// Pontos com o arrasto aplicado (bolinha vira parada; parada muda de lugar).
  List<TripPoint> _pointsWithDrag(String id, LatLng q) {
    final pts = [..._points];
    if (id.startsWith('stop')) {
      final i = int.parse(id.substring(4));
      pts[i] = TripPoint(pts[i].name, q.latitude, q.longitude, type: pts[i].type);
    } else {
      pts.insert(_insertIndexFor(q), _via(q));
    }
    return pts;
  }

  void _onDrag(String id, LatLng q) {
    if (_dragId == null) {
      _cancelAuto();
      _userMoved = true;
      _frozenHandles = _handles();
      _dragId = id;
    }
    if (_liveBusy || DateTime.now().difference(_lastLive).inMilliseconds < 1200) return;
    _liveBusy = true;
    _lastLive = DateTime.now();
    final seq = ++_dragSeq;
    TripService.build(
      title: _title,
      points: _pointsWithDrag(id, q),
      avoidTolls: _tolls,
      avoidHighways: _highways,
    ).then((t) {
      _liveBusy = false;
      if (!mounted || seq != _dragSeq || _dragId == null || t == null) return;
      setState(() {
        _trip = t;
        _options = [t];
      });
    }, onError: (_) { _liveBusy = false; });
  }

  void _onDragEnd(String id, LatLng q) {
    _dragSeq++; // descarta cálculo do arrasto que ainda estiver chegando
    final pts = _pointsWithDrag(id, q);
    setState(() {
      _dragId = null;
      _frozenHandles = const [];
      _points
        ..clear()
        ..addAll(pts);
    });
    _calc();
  }

  /// Segurou no mapa: ponto de passagem ali.
  void _addViaAt(LatLng q) {
    if (_loading || _points.length >= _maxPoints) return;
    _cancelAuto();
    _userMoved = true;
    setState(() => _points.insert(_insertIndexFor(q), _via(q)));
    _calc();
  }

  Set<Marker> _routeMarkers() => {
        for (var i = 1; i < _points.length - 1; i++)
          Marker(
            markerId: MarkerId('stop$i'),
            position: LatLng(_points[i].lat, _points[i].lng),
            draggable: !_loading || _dragId != null,
            zIndexInt: 3,
            anchor: _points[i].name == tr('Passando por aqui')
                ? const Offset(0.5, 0.5)
                : const Offset(0.5, 1),
            icon: _points[i].name == tr('Passando por aqui')
                ? (_viaIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange))
                : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
            onDrag: (q) => _onDrag('stop$i', q),
            onDragEnd: (q) => _onDragEnd('stop$i', q),
          ),
        if (_handleIcon != null && (!_loading || _dragId != null))
          for (final (k, q) in _handles().indexed)
            Marker(
              markerId: MarkerId('h$k'),
              position: q,
              draggable: true,
              zIndexInt: 2,
              anchor: const Offset(0.5, 0.5),
              icon: _handleIcon!,
              onDrag: (p) => _onDrag('h$k', p),
              onDragEnd: (p) => _onDragEnd('h$k', p),
            ),
        if (_points.isNotEmpty)
          Marker(
              markerId: const MarkerId('from'),
              position: LatLng(_points.first.lat, _points.first.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure)),
        if (_points.length > 1)
          Marker(
              markerId: const MarkerId('to'),
              position: LatLng(_points.last.lat, _points.last.lng)),
      };

  /// Enquadra a rota (e as alternativas) no espaço livre acima do painel.
  void _fitRoute() {
    final t = _trip, m = _map;
    if (t == null || m == null || _userMoved || _dragId != null) return;
    final sig = '${t.plan.polyline.hashCode}-${_options.length}';
    if (sig == _fittedSig) return;
    _fittedSig = sig;
    final pts = [
      for (final o in _options.isEmpty ? [t] : _options) ...decodePolyline(o.plan.polyline)
    ];
    if (pts.length < 2) return;
    var s = pts.first.latitude, n = s, w = pts.first.longitude, e = w;
    for (final p in pts) {
      s = p.latitude < s ? p.latitude : s;
      n = p.latitude > n ? p.latitude : n;
      w = p.longitude < w ? p.longitude : w;
      e = p.longitude > e ? p.longitude : e;
    }
    m.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e)), 48));
  }

  /// O piloto escolheu outra rota (na lista ou tocando a linha cinza).
  void _chooseRoute(Trip v) {
    _cancelAuto();
    setState(() {
      _trip = v;
      _tollCost = null;
    });
    _calcTolls();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
    return Stack(children: [
      Positioned.fill(
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
              target: LatLng(_points.first.lat, _points.first.lng), zoom: 9),
          onMapCreated: (c) {
            _map = c;
            _fittedSig = '';
            _fitRoute();
          },
          polylines: _routeLines(),
          markers: _routeMarkers(),
          onLongPress: _addViaAt,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationButtonEnabled: false,
          // A rota fica no espaço acima do painel.
          padding: EdgeInsets.only(bottom: h * _sheetFrac),
        ),
      ),
      // Fechar (o painel não fecha arrastando, para poder ver o mapa).
      Positioned(
        top: 8,
        left: 8,
        child: FloatingActionButton.small(
          heroTag: 'previewClose',
          tooltip: tr('Fechar'),
          onPressed: () => Navigator.pop(context),
          child: const Icon(Icons.close),
        ),
      ),
      NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          if ((n.extent - _sheetFrac).abs() > 0.05) {
            setState(() => _sheetFrac = n.extent);
          }
          return false;
        },
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.16,
          maxChildSize: 0.95,
          // Para onde o piloto soltar (não pula para cima/baixo).
          snap: false,
          // No mínimo, só baixa (mostra o mapa); não fecha a prévia.
          shouldCloseOnMinExtent: false,
          builder: (ctx, scroll) => Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: _details(scroll),
          ),
        ),
      ),
    ]);
  }

  /// Simular / Iniciar (ou Salvar, com saída planejada; ou a contagem do
  /// início automático).
  Widget _actions(Trip? t) {
    return Row(children: [
              if (_countdown != null) ...[
                Expanded(
                  flex: 2,
                  child: Row(children: [
                    const Icon(Icons.timer_outlined),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(tr('Iniciando em {0} s…', [_countdown]),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                        onPressed: _cancelAuto, child: Text(tr('Cancelar'))),
                  ]),
                ),
                const SizedBox(width: 8),
              ] else
              if (_departAt != null && t != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _savePlanned,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(tr('Salvar')),
                  ),
                )
              else
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: t == null
                      ? null
                      : () => Navigator.pop(context, (TripAction.simulate, t)),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(tr('Simular')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Mesma largura dos dois: "Simular" não quebra em 2 linhas
                // com a fonte grande do celular.
                flex: 1,
                child: FilledButton.icon(
                  onPressed: t == null
                      ? null
                      : () => Navigator.pop(context, (TripAction.start, t)),
                  icon: const Icon(Icons.navigation),
                  label: Text(tr('Iniciar')),
                ),
              ),
            ]);
  }

  /// Painel com os cálculos da rota (tempo, km, pedágio, custo, opções).
  Widget _details(ScrollController scroll) {
    final theme = Theme.of(context);
    final t = _trip;
    final eta = t == null
        ? null
        : (_departAt ?? DateTime.now()).add(Duration(seconds: t.durationS));
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Alça: arraste para baixo para ver a rota no mapa.
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(children: [
              const Icon(Icons.flag, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_title,
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            // Saída: posição atual ou outro lugar (para planejar/simular).
            Row(children: [
              const Icon(Icons.trip_origin, color: Colors.blue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Saindo de: {0}', [_fromHere ? tr('sua posição atual') : _points.first.name]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _changeOrigin,
                child: Text(tr('Trocar')),
              ),
            ]),
            if (!_fromHere)
              Text(
                  tr('Saída diferente da sua posição: bom para simular. Se tocar em Iniciar, a navegação recalcula a partir de onde você estiver.'),
                  style: TextStyle(fontSize: 12)),
            // Paradas e destino: arraste pela alça para mudar a ordem
            // (como no roteiro da expedição).
            if (_points.length > 2) _stopsList(),
            Wrap(spacing: 4, children: [
              TextButton.icon(
                onPressed:
                    _loading || _points.length >= 12 ? null : _addStop,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(tr('Adicionar parada')),
              ),
              // Vários destinos: a ordem que economiza tempo (com trânsito).
              if (_points.length > 2)
                TextButton.icon(
                  onPressed: _loading || _ordering ? null : _bestOrder,
                  icon: _ordering
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high),
                  label: Text(tr('Melhor sequência')),
                ),
            ]),
            Text(tr('Para mudar o caminho, segure e arraste uma bolinha da linha azul ou segure no mapa.'),
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (t == null)
              // Sem rota (sinal caiu, troca de Wi-Fi para dados): sem Iniciar e
              // Simular, então oferece calcular de novo aqui mesmo.
              Row(children: [
                Expanded(child: Text(tr('Não foi possível calcular a rota. Confira a internet.'))),
                TextButton.icon(
                  onPressed: _calc,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Tentar de novo')),
                ),
              ])
            else ...[
              // Saída: agora ou planejada (data e hora).
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(_departAt == null
                      ? tr('Saída: agora')
                      : tr('Saída: {0} {1}', [formatDay(_departAt!), formatTime(_departAt!)])),
                  onPressed: _pickDeparture,
                ),
                if (_departAt != null)
                  TextButton(
                    onPressed: () {
                      setState(() => _departAt = null);
                      _calcTolls();
                    },
                    child: Text(tr('Sair agora')),
                  ),
              ]),
              Text(
                tr('{0} · {1} · chegada {2}{3}', [formatDuration(t.durationS), formatDistance(t.distanceM), _departAt != null && (eta!.day != _departAt!.day) ? '${formatDay(eta)} ' : '', formatTime(eta!)]),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              // Iniciar / Simular logo aqui, junto das rotas sugeridas.
              const SizedBox(height: 8),
              _actions(t),
              // Turismo, hospedagem e postos perto do destino (08/11).
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.travel_explore),
                  label: Text(tr('Turismo e hospedagem no destino')),
                  onPressed: () {
                    final d = _points.last;
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => NaRotaScreen(
                              lat: d.lat,
                              lng: d.lng,
                              lugar: d.name,
                              // Atração/posto/hotel vira parada antes do destino (09/11).
                              onAddStop: _points.length >= 12
                                  ? null
                                  : (name, lat, lng, type) async {
                                      if (!mounted) return;
                                      _cancelAuto();
                                      setState(() => _points.insert(_points.length - 1,
                                          TripPoint(name, lat, lng, type: type)));
                                      _calc();
                                    },
                            )));
                  },
                ),
              ),
              const SizedBox(height: 4),
              // Versão de teste do motor próprio: mostra de onde veio a rota.
              if (RouteEngineService.enabled)
                Text(
                    RouteEngineService.lastUsed
                        ? '🧪 Rota pelo motor UauGo (teste)'
                        : '🧪 Motor UauGo fora do ar: rota pelo Google',
                    style: TextStyle(
                        color: RouteEngineService.lastUsed ? Colors.teal : Colors.orange,
                        fontWeight: FontWeight.w600)),
              // Outras rotas (ex.: não quer ir pela Anhanguera).
              if (_options.length > 1) ...[
                const SizedBox(height: 6),
                for (var i = 0; i < _options.length; i++)
                  RadioListTile<Trip>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    value: _options[i],
                    groupValue: t,
                    onChanged: (v) {
                      if (v != null) _chooseRoute(v);
                    },
                    title: Text(
                        _options[i].summary.isEmpty
                            ? tr('Rota {0}', [i + 1])
                            : tr('via {0}', [_options[i].summary]),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${formatDuration(_options[i].durationS)} · ${formatDistance(_options[i].distanceM)}'
                        '${i == 0 ? ' · ${tr('indicada')}' : ''}'),
                  ),
              ],
              // Com "Considerar o trânsito do momento" ligado.
              if (t.trafficDelayS >= 120)
                Text(
                  tr('🚗 Trânsito: +{0} min em relação ao normal', [(t.trafficDelayS / 60).round()]),
                  style: TextStyle(
                      color: t.trafficDelayS >= 600
                          ? Colors.red
                          : Colors.orange.shade800,
                      fontWeight: FontWeight.bold),
                ),
              // Combustível estimado (Minha moto/carro → consumo e gastos).
              if (AppSettings.instance.fuel.value.ready)
                Builder(builder: (_) {
                  final f = AppSettings.instance.fuel.value;
                  final l = fuelLiters(t.distanceM.toDouble(), f.kmPerLiter);
                  return Text(
                      tr('⛽ ~{0} L de combustível · {1}', [formatDecimal(l), formatMoney(l * f.pricePerLiter)]));
                }),
              if (_rodizio != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('🚫 $_rodizio',
                      style: const TextStyle(
                          color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              // Pedágios: valor para o veículo ou aviso de valor não fornecido.
              for (final line in _tollLines(t))
                Text(line, style: TextStyle(color: Colors.amber.shade800)),
              // Valores estimados: o piloto confirma ou corrige (vale para todos).
              if (_tollCost case final e? when e.list.any((p) => p.editable))
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(tr('Confirmar valores dos pedágios ({0} a confirmar)', [e.toConfirm])),
                  onPressed: () => TollConfirmSheet.show(context, e.list),
                ),
              if (_tripCost(t) case final cost?)
                Text(
                    tr('💰 Custo estimado: {0} {1}', [formatMoney(cost), (_tollCost?.total ?? 0) > 0 ? tr('(combustível + pedágios)') : tr('(combustível)')]),
                    style: const TextStyle(fontWeight: FontWeight.bold))
              else
                Text(
                    tr('Para calcular o combustível, informe o consumo e o preço do litro em "Configurar meu veículo".'),
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (AppSettings.instance.route.value.avoidRisk)
                Text(
                  t.riskCount == 0
                      ? tr('🛡️ Rota sem áreas de risco reportadas')
                      : tr('🚨 Atenção: a rota passa perto de {0} {1} de risco (não havia alternativa melhor)', [t.riskCount, t.riskCount == 1 ? tr('área') : tr('áreas')]),
                  style: TextStyle(
                      color: t.riskCount == 0
                          ? Colors.green.shade700
                          : Colors.red,
                      fontWeight: FontWeight.bold),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilterChip(
                label: Text(tr('Evitar pedágios')),
                selected: _tolls,
                onSelected: _loading
                    ? null
                    : (v) {
                        _tolls = v;
                        _calc();
                      },
              ),
              FilterChip(
                label: Text(tr('Evitar rodovias')),
                selected: _highways,
                onSelected: _loading
                    ? null
                    : (v) {
                        _highways = v;
                        _calc();
                      },
              ),
              FilterChip(
                label: Text(tr('Evitar locais de risco')),
                selected: AppSettings.instance.route.value.avoidRisk,
                onSelected: _loading
                    ? null
                    : (v) async {
                        final s = AppSettings.instance;
                        await s.setRoute(s.route.value.copyWith(avoidRisk: v));
                        _calc();
                      },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
