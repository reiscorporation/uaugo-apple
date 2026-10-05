// ============================================================================
// trip_preview_sheet.dart — Prévia da rota
//
// O que faz: Antes de navegar: tempo, distância, chegada, trânsito,
//   combustível, pedágio, áreas de risco, opções (pedágios, rodovias, risco) e
//   os botões Simular / Iniciar.
// Quem usa: Home ("Para onde?").
// ============================================================================

import 'package:flutter/material.dart';

import '../logic/itinerary.dart';
import '../models/trip.dart';
import '../logic/costs.dart';
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
      points: widget.points,
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
                flex: 2,
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
