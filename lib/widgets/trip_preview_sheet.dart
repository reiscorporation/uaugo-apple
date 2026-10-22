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

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
      showModalBottomSheet<(TripAction, Trip)>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TripPreviewSheet(
            title: title, points: points, autoStart: autoStart),
      );

  @override
  State<TripPreviewSheet> createState() => _TripPreviewSheetState();
}

/// Recalcula a rota quando o piloto muda alguma opção.
class _TripPreviewSheetState extends State<TripPreviewSheet> {
  Trip? _trip;
  bool _loading = true;
  bool _tolls = false;
  bool _highways = false;

  /// Pontos da viagem (o 1º é a saída, que o piloto pode trocar para
  /// planejar ou simular uma viagem que começa em outro lugar).
  late final List<TripPoint> _points = [...widget.points];

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
      helpText: 'Dia da saída',
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departAt ?? now),
      helpText: 'Hora da saída',
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Viagem planejada salva. Ela aparece na tela inicial.')));
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
            near: LatLng(here.lat, here.lng), title: 'Saindo de'),
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
            near: LatLng(ref.lat, ref.lng), title: 'Parada no caminho'),
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

  @override
  void initState() {
    super.initState();
    // Começa com as preferências salvas em Configurações → Rotas.
    final s = AppSettings.instance.route.value;
    _tolls = s.avoidTolls;
    _highways = s.avoidHighways;
    _calc();
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
    VoiceService.instance.reply('Rota para ${widget.title}: '
        '${min < 60 ? '$min minutos' : '${min ~/ 60} horas e ${min % 60} minutos'}. '
        'Iniciando.');
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
      title: widget.title,
      points: _points,
      avoidTolls: _tolls,
      avoidHighways: _highways,
    );
    if (!mounted) return;
    setState(() {
      _trip = t;
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
      '🛣️ Rota com pedágio. Os valores não foram fornecidos pelos órgãos responsáveis.',
      _bike.style.isMoto
          ? 'Na maioria das praças a moto paga metade do valor do carro.'
          : '${noun[0].toUpperCase()}${noun.substring(1)} paga pedágio.',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _trip;
    final eta = t == null
        ? null
        : (_departAt ?? DateTime.now()).add(Duration(seconds: t.durationS));
    // Rolável: com várias paradas a prévia pode passar da altura da tela.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.flag, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
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
                  'Saindo de: ${_fromHere ? 'sua posição atual' : _points.first.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: _loading ? null : _changeOrigin,
                child: const Text('Trocar'),
              ),
            ]),
            if (!_fromHere)
              const Text(
                  'Saída diferente da sua posição: bom para simular. Se tocar '
                  'em Iniciar, a navegação recalcula a partir de onde você '
                  'estiver.',
                  style: TextStyle(fontSize: 12)),
            // Paradas no caminho (entre a saída e o destino).
            for (var i = 1; i < _points.length - 1; i++)
              Row(children: [
                const Icon(Icons.more_vert, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Parada $i: ${_points[i].name}',
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: 'Remover parada',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _loading ? null : () => _removeStop(i),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _loading || _points.length >= 12 ? null : _addStop,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Adicionar parada'),
              ),
            ),
            const SizedBox(height: 4),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (t == null)
              const Text('Não foi possível calcular a rota. Confira a internet.')
            else ...[
              // Saída: agora ou planejada (data e hora).
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(_departAt == null
                      ? 'Saída: agora'
                      : 'Saída: ${formatDay(_departAt!)} ${formatTime(_departAt!)}'),
                  onPressed: _pickDeparture,
                ),
                if (_departAt != null)
                  TextButton(
                    onPressed: () {
                      setState(() => _departAt = null);
                      _calcTolls();
                    },
                    child: const Text('Sair agora'),
                  ),
              ]),
              Text(
                '${formatDuration(t.durationS)} · ${formatDistance(t.distanceM)}'
                ' · chegada ${_departAt != null && (eta!.day != _departAt!.day) ? '${formatDay(eta)} ' : ''}${formatTime(eta!)}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              // Com "Considerar o trânsito do momento" ligado.
              if (t.trafficDelayS >= 120)
                Text(
                  '🚗 Trânsito: +${(t.trafficDelayS / 60).round()} min em relação ao normal',
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
                      '⛽ ~${formatDecimal(l)} L de combustível · '
                      '${formatMoney(l * f.pricePerLiter)}');
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
              if (_tripCost(t) case final cost?)
                Text(
                    '💰 Custo estimado: ${formatMoney(cost)} '
                    '${(_tollCost?.total ?? 0) > 0 ? '(combustível + pedágios)' : '(combustível)'}',
                    style: const TextStyle(fontWeight: FontWeight.bold))
              else
                Text(
                    'Para calcular o combustível, informe o consumo e o preço '
                    'do litro em "Configurar meu veículo".',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if (AppSettings.instance.route.value.avoidRisk)
                Text(
                  t.riskCount == 0
                      ? '🛡️ Rota sem áreas de risco reportadas'
                      : '🚨 Atenção: a rota passa perto de ${t.riskCount} '
                          '${t.riskCount == 1 ? 'área' : 'áreas'} de risco '
                          '(não havia alternativa melhor)',
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
                label: const Text('Evitar pedágios'),
                selected: _tolls,
                onSelected: _loading
                    ? null
                    : (v) {
                        _tolls = v;
                        _calc();
                      },
              ),
              FilterChip(
                label: const Text('Evitar rodovias'),
                selected: _highways,
                onSelected: _loading
                    ? null
                    : (v) {
                        _highways = v;
                        _calc();
                      },
              ),
              FilterChip(
                label: const Text('Evitar locais de risco'),
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
            const SizedBox(height: 12),
            Row(children: [
              if (_countdown != null) ...[
                Expanded(
                  flex: 2,
                  child: Row(children: [
                    const Icon(Icons.timer_outlined),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Iniciando em $_countdown s…',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                        onPressed: _cancelAuto, child: const Text('Cancelar')),
                  ]),
                ),
                const SizedBox(width: 8),
              ] else
              if (_departAt != null && t != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _savePlanned,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Salvar'),
                  ),
                )
              else
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: t == null
                      ? null
                      : () => Navigator.pop(context, (TripAction.simulate, t)),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Simular'),
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
                  label: const Text('Iniciar'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
