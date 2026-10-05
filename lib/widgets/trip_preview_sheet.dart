// ============================================================================
// trip_preview_sheet.dart — Prévia da rota
//
// O que faz: Antes de navegar: tempo, distância, chegada, trânsito,
//   combustível, pedágio, áreas de risco, opções (pedágios, rodovias, risco) e
//   os botões Simular / Iniciar. A saída pode ser trocada ("Trocar") para
//   planejar ou simular uma viagem que começa em outro lugar.
// Quem usa: Home ("Para onde?").
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/costs.dart';
import '../logic/itinerary.dart';
import '../logic/radars.dart' show distanceMeters;
import '../models/expedition.dart' show StopType;
import '../models/trip.dart';
import 'place_search.dart';
import '../services/app_settings.dart';
import '../services/profile_service.dart';
import '../services/trip_service.dart';

/// O que o piloto escolheu na prévia da viagem.
enum TripAction { start, simulate }

/// Prévia da navegação sozinho: distância, tempo, opções e os botões
/// "Simular" e "Iniciar". Recalcula ao mudar as opções.
class TripPreviewSheet extends StatefulWidget {
  const TripPreviewSheet({super.key, required this.title, required this.points});

  final String title;
  final List<TripPoint> points;

  /// Mostra a prévia e devolve (ação, viagem) ou null se cancelar.
  static Future<(TripAction, Trip)?> show(BuildContext context,
          {required String title, required List<TripPoint> points}) =>
      showModalBottomSheet<(TripAction, Trip)>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TripPreviewSheet(title: title, points: points),
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

  /// A saída é a posição atual do GPS? (Senão, é um lugar escolhido.)
  bool _fromHere = true;

  /// Troca o ponto de saída (busca um lugar por nome ou volta ao GPS).
  Future<void> _changeOrigin() async {
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

  @override
  void initState() {
    super.initState();
    // Começa com as preferências salvas em Configurações → Rotas.
    final s = AppSettings.instance.route.value;
    _tolls = s.avoidTolls;
    _highways = s.avoidHighways;
    _calc();
    ProfileService.load().then((b) {
      if (mounted) setState(() => _isCar = b.style.isCar);
    });
  }

  bool _isCar = false;

  /// Calcula a rota com as opções escolhidas.
  Future<void> _calc() async {
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
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _trip;
    final eta = t == null
        ? null
        : DateTime.now().add(Duration(seconds: t.durationS));
    return SafeArea(
      child: Padding(
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
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (t == null)
              const Text('Não foi possível calcular a rota. Confira a internet.')
            else ...[
              Text(
                '${formatDuration(t.durationS)} · ${formatDistance(t.distanceM)}'
                ' · chegada ${formatTime(eta!)}',
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
              if (t.hasToll)
                Text(
                  _isCar
                      ? '🛣️ Rota com pedágio'
                      : '🛣️ Rota com pedágio: na maioria das praças a moto '
                          'paga. O app avisa em cada praça.',
                  style: TextStyle(color: Colors.amber.shade800),
                ),
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
