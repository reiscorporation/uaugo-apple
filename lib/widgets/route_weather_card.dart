// ============================================================================
// route_weather_card.dart — "Clima na rota"
//
// O que faz: Cartão com a previsão do tempo nos pontos da rota, na HORA em
//   que o piloto vai passar por eles (temperatura, tempo, chance e
//   quantidade de chuva, vento e rajadas). Destaca riscos (tempestade, chuva
//   forte, vento forte) no topo. Sem internet ou fora do período previsto,
//   diz isso; nunca inventa previsão.
// Quem usa: TripPreviewSheet (rota normal, viagem compartilhada) e
//   PlanScreen (roteiro da expedição/comboio). Um componente só.
// Fonte: Open-Meteo (a mesma da previsão da Comunidade do site).
// ============================================================================

import 'package:flutter/material.dart';

import '../l10n/i18n.dart';
import '../logic/itinerary.dart' show formatTime, formatDay;
import '../logic/route_weather.dart';
import '../services/weather_service.dart';

class RouteWeatherCard extends StatefulWidget {
  const RouteWeatherCard({
    super.key,
    required this.line,
    required this.stops,
    required this.durationS,
    this.departAt,
  });

  /// Traçado da rota (lat, lng).
  final List<(double, double)> line;

  /// Saída, paradas e destino (nome, lat, lng), em ordem.
  final List<(String, double, double)> stops;
  final int durationS;

  /// Saída marcada; null = agora.
  final DateTime? departAt;

  @override
  State<RouteWeatherCard> createState() => _RouteWeatherCardState();
}

class _RouteWeatherCardState extends State<RouteWeatherCard> {
  List<PointWeather?>? _data;
  bool _loading = false;
  bool _failed = false;
  String _sig = '';
  DateTime _loadedAt = DateTime(2000);

  String get _key =>
      '${widget.line.length}|${widget.line.isEmpty ? '' : widget.line.last}|'
      '${widget.durationS}|${widget.departAt}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RouteWeatherCard old) {
    super.didUpdateWidget(old);
    if (_key != _sig) _load();
  }

  Future<void> _load() async {
    _sig = _key;
    final pts = weatherPoints(
      line: widget.line,
      stops: widget.stops,
      durationS: widget.durationS,
      departAt: widget.departAt ?? DateTime.now(),
    );
    if (pts.isEmpty) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await RouteWeatherService.forRoute(pts);
    if (!mounted || _sig != _key) return;
    setState(() {
      _loading = false;
      _failed = r == null;
      _data = r;
      _loadedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;
    final risks = [
      for (final w in data ?? const <PointWeather?>[])
        if (w?.risk case final r?) (w!, r),
    ];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('🌦️', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(tr('Clima na rota'),
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            if (_loading)
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Atualizar'),
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _load,
              ),
          ]),
          if (_failed)
            Text(tr('Previsão indisponível agora (sem internet?). Toque em atualizar.'),
                style: theme.textTheme.bodySmall)
          else if (data == null)
            Text(tr('Carregando a previsão...'), style: theme.textTheme.bodySmall)
          else ...[
            if (risks.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final (w, r) in risks.take(4))
                    Text(tr('⚠️ {0} em {1} (~{2})', [r, w.point.name, formatTime(w.point.at)]),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            for (final w in data)
              if (w != null) _row(w, theme),
            if (data.any((w) => w == null))
              Text(tr('Alguns pontos estão além do período de previsão (16 dias).'),
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
                tr('Previsão para o horário estimado de passagem · Open-Meteo · atualizada às {0}',
                    [formatTime(_loadedAt)]),
                style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }

  Widget _row(PointWeather w, ThemeData theme) {
    final (icon, label) = weatherIcon(w.code, day: w.point.at.hour >= 6 && w.point.at.hour < 18);
    final sameDay = DateUtils.isSameDay(w.point.at, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 30, child: Text(icon, style: const TextStyle(fontSize: 20))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.point.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(
                '${sameDay ? '' : '${formatDay(w.point.at)} '}${formatTime(w.point.at)} · $label',
                style: theme.textTheme.bodySmall),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${w.tempC.round()}°', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('💧${w.rainProb}%${w.rainMm >= 0.1 ? ' ${w.rainMm.toStringAsFixed(1)}mm' : ''} · 💨${w.windKmh.round()}',
              style: theme.textTheme.bodySmall),
        ]),
      ]),
    );
  }
}
