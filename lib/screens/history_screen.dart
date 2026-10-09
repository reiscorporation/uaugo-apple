// ============================================================================
// history_screen.dart — "Minhas viagens"
//
// O que faz: Lista das viagens gravadas no celular e o detalhe de cada uma:
//   mapa (caminho feito x rota), estatísticas, gastos, compartilhar
//   (imagem/GPX), simular de novo e excluir.
// Quem usa: HomeScreen (botão Minhas viagens).
// Onde mexer: Gastos: widgets/trip_expenses.dart. Imagem:
//   widgets/trip_share.dart.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/geo.dart';
import '../logic/itinerary.dart';
import '../models/expedition.dart' show StopType;
import '../models/trip_record.dart';
import '../services/history_service.dart';
import '../services/trip_service.dart';
import '../widgets/trip_expenses.dart';
import '../widgets/trip_share.dart';
import 'map_screen.dart';

/// Data curta: "05/10/2026".
String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// "Minhas viagens": histórico guardado só no celular.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.uid, required this.userName});
  final String uid;
  final String userName;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// Lista das viagens (atualiza sozinha quando uma viagem muda).
class _HistoryScreenState extends State<HistoryScreen> {
  final _svc = HistoryService.instance;

  @override
  void initState() {
    super.initState();
    _svc.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Minhas viagens')),
      body: ValueListenableBuilder<List<TripRecord>>(
        valueListenable: _svc.trips,
        builder: (_, trips, __) {
          if (trips.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nenhuma viagem ainda.\n\nAs viagens (expedições e '
                  'navegação) ficam guardadas aqui, só no seu celular.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final totalKm = trips.fold<double>(0, (a, t) => a + t.distanceM);
          return ListView(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewPadding.bottom + 16),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${trips.length} ${trips.length == 1 ? 'viagem' : 'viagens'} · '
                  '${formatDistance(totalKm.round())} no total',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final t in trips)
                ListTile(
                  leading: CircleAvatar(
                    child: Icon(t.expedition ? Icons.groups : Icons.navigation),
                  ),
                  title: Text(t.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${_date(t.startedAt)} · ${formatDistance(t.distanceM.round())}'
                      ' · ${formatDuration(t.movingS)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _TripDetail(
                        trip: t, uid: widget.uid, userName: widget.userName),
                  )),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Detalhe de uma viagem: mapa, números, gastos, compartilhar, simular.
class _TripDetail extends StatelessWidget {
  _TripDetail({required this.trip, required this.uid, required this.userName});
  final TripRecord trip;
  final String uid;
  final String userName;

  /// Mapa da tela (para a foto do trajeto ao compartilhar).
  final _map = ValueNotifier<GoogleMapController?>(null);

  /// Recalcula a rota pelas mesmas paradas e abre a simulação.
  Future<void> _simulate(BuildContext context) async {
    if (trip.stops.length < 2) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Calculando a rota...')));
    final t = await TripService.build(
      title: trip.title,
      points: [
        for (final s in trip.stops)
          TripPoint(s.name, s.lat, s.lng,
              type: StopType.values.firstWhere((x) => x.name == s.type,
                  orElse: () => StopType.waypoint)),
      ],
    );
    if (!context.mounted) return;
    if (t == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível calcular a rota agora')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          MapScreen(uid: uid, userName: userName, trip: t, simulate: true),
    ));
  }

  /// Exclui a viagem do celular (com confirmação).
  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir esta viagem?'),
        content: const Text('Ela será apagada do seu celular.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await HistoryService.instance.delete(trip.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final track = decodePolyline(trip.trackPolyline);
    final route = decodePolyline(trip.routePolyline);
    final all = [...track, ...route];
    LatLngBounds? bounds;
    if (all.length >= 2) {
      var s = all.first.latitude, n = s, w = all.first.longitude, e = w;
      for (final p in all) {
        if (p.latitude < s) s = p.latitude;
        if (p.latitude > n) n = p.latitude;
        if (p.longitude < w) w = p.longitude;
        if (p.longitude > e) e = p.longitude;
      }
      bounds = LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
    }
    Widget stat(IconData i, String v, String l) => Expanded(
          child: Column(children: [
            Icon(i, color: Theme.of(context).colorScheme.primary),
            Text(v,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(l, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );

    return Scaffold(
      resizeToAvoidBottomInset: false, // mapa não redimensiona com o teclado (evita travamento)
      appBar: AppBar(
        title: Text(trip.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: 'Compartilhar',
              icon: const Icon(Icons.share),
              onPressed: () => shareTrip(context, trip, _map.value)),
          IconButton(
              tooltip: 'Excluir',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                  target:
                      all.isNotEmpty ? all.first : const LatLng(-15.78, -47.93),
                  zoom: all.isNotEmpty ? 12 : 4),
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              polylines: {
                if (route.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: route,
                    width: 5,
                    color: MapScreen.routeBlue.withAlpha(110),
                  ),
                if (track.length >= 2)
                  Polyline(
                    polylineId: const PolylineId('track'),
                    points: track,
                    width: 5,
                    color: MapScreen.routeBorder,
                  ),
              },
              markers: {
                for (var i = 0; i < trip.stops.length; i++)
                  Marker(
                    markerId: MarkerId('s$i'),
                    position: LatLng(trip.stops[i].lat, trip.stops[i].lng),
                    infoWindow: InfoWindow(title: trip.stops[i].name),
                  ),
              },
              onMapCreated: (c) {
                _map.value = c;
                if (bounds != null) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    c.animateCamera(CameraUpdate.newLatLngBounds(bounds!, 40));
                  });
                }
              },
            ),
          ),
          // Abaixo do mapa, tudo rola (os gastos podem ser muitos).
          Expanded(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '${_date(trip.startedAt)} · ${formatTime(trip.startedAt)} às '
                  '${formatTime(trip.endedAt)}',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  stat(Icons.straighten, formatDistance(trip.distanceM.round()),
                      'percorridos'),
                  stat(Icons.timer_outlined, formatDuration(trip.movingS),
                      'em movimento'),
                  stat(Icons.speed, '${trip.avgKmh.round()} km/h', 'média'),
                  stat(Icons.bolt, '${trip.maxKmh.round()} km/h', 'máxima'),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                    'Azul escuro: caminho feito · Azul claro: rota planejada',
                    style: TextStyle(fontSize: 12)),
              ),
              TripExpensesCard(tripId: trip.id),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => shareTrip(context, trip, _map.value),
                    icon: const Icon(Icons.share),
                    label: const Text('Salvar imagem e compartilhar'),
                  ),
                ),
              ),
              if (trip.stops.length >= 2)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _simulate(context),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Simular este trajeto de novo'),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
