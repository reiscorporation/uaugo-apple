// ============================================================================
// place_search.dart — Busca de lugar
//
// O que faz: Tela de busca por nome (como no Google Maps), com opção de usar a
//   localização atual.
// Quem usa: Home ("Para onde?") e Roteiro (paradas).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/places_service.dart';
import '../services/recent_places_service.dart';
import '../services/saved_places_service.dart';

/// Busca de lugares por nome (como no Google Maps), com opção de usar a
/// localização atual. Devolve um [PickedPlace] ao fechar.
class PickedPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;
  const PickedPlace(this.name, this.address, this.lat, this.lng);
}

/// Tela de busca de lugar; devolve um PickedPlace ao fechar.
class PlaceSearchPage extends StatefulWidget {
  const PlaceSearchPage(
      {super.key, required this.near, required this.title, this.initialText});
  final LatLng? near;
  final String title;

  /// Texto já preenchido e buscado (endereço recebido de outro app).
  final String? initialText;

  @override
  State<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

/// Busca com espera de 350 ms entre letras (não consulta a cada tecla).
class _PlaceSearchPageState extends State<PlaceSearchPage> {
  final _places = PlacesService();
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<PlaceSuggestion> _results = [];
  bool _loading = false;
  int _seq = 0;

  /// Destinos escolhidos antes (aparecem primeiro; escolher não consulta o
  /// Google). E sugestões já buscadas nesta tela (apagar letras não repete
  /// a consulta).
  List<RecentPlace> _recents = [];
  final _cache = <String, List<PlaceSuggestion>>{};

  @override
  void initState() {
    super.initState();
    RecentPlacesService.instance.load().then((r) {
      if (mounted) setState(() => _recents = r);
    });
    final t = widget.initialText;
    if (t != null && t.trim().isNotEmpty) {
      _ctrl.text = t;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(t));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Texto mudou: agenda a busca.
  void _onChanged(String text) {
    _debounce?.cancel();
    setState(() {}); // recentes filtram na hora, sem consulta
    // Espera parar de digitar para economizar buscas.
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(text));
  }

  /// Consulta as sugestões ao Google.
  Future<void> _search(String text) async {
    final key = text.trim().toLowerCase();
    final cached = _cache[key];
    if (cached != null) {
      setState(() => _results = cached);
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await _places.search(text,
        nearLat: widget.near?.latitude, nearLng: widget.near?.longitude);
    if (!mounted || seq != _seq) return;
    if (r.isNotEmpty) _cache[key] = r;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  /// Escolheu um destino recente: fecha sem consultar o Google.
  void _chooseRecent(RecentPlace p) {
    RecentPlacesService.instance.add(p);
    Navigator.pop(context, PickedPlace(p.name, p.address, p.lat, p.lng));
  }

  /// Escolheu uma sugestão: busca a posição e fecha a tela.
  Future<void> _choose(PlaceSuggestion s) async {
    setState(() => _loading = true);
    final d = await _places.details(s);
    if (!mounted) return;
    setState(() => _loading = false);
    if (d == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir este lugar')));
      return;
    }
    RecentPlacesService.instance
        .add(RecentPlace(d.name, d.address, d.lat, d.lng));
    Navigator.pop(context, PickedPlace(d.name, d.address, d.lat, d.lng));
  }

  /// Usa a localização atual do GPS como o lugar.
  Future<void> _useMyLocation() async {
    setState(() => _loading = true);
    try {
      final p = await Geolocator.getCurrentPosition();
      var name = 'Minha localização';
      var address = '';
      try {
        final pm =
            (await placemarkFromCoordinates(p.latitude, p.longitude)).firstOrNull;
        if (pm != null) {
          address = [pm.subAdministrativeArea ?? pm.locality, pm.administrativeArea]
              .where((x) => x != null && x.trim().isNotEmpty)
              .join(' - ');
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.pop(context, PickedPlace(name, address, p.latitude, p.longitude));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('GPS indisponível: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: '${widget.title}: buscar lugar',
            border: InputBorder.none,
          ),
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator())
            : null,
      ),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.my_location),
          title: const Text('Usar minha localização atual'),
          onTap: _loading ? null : _useMyLocation,
        ),
        if (!PlacesService.available)
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Busca indisponível nesta versão (sem chave de API).'
                ' Toque e segure no mapa para escolher o ponto.'),
          ),
        // Casa e Trabalho (os salvos na tela inicial), também durante a
        // navegação: um toque e pronto.
        ValueListenableBuilder<List<SavedPlace>>(
          valueListenable: SavedPlacesService.instance.places,
          builder: (_, __, ___) {
            final fixed = [
              for (final (k, icon) in const [
                (savedHome, Icons.home),
                (savedWork, Icons.work),
              ])
                if (SavedPlacesService.instance.get(k) case final sp?) (sp, icon),
            ];
            if (fixed.isEmpty || _ctrl.text.trim().isNotEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (sp, icon) in fixed)
                  ActionChip(
                    avatar: Icon(icon, size: 18),
                    label: Text(sp.name),
                    onPressed: _loading
                        ? null
                        : () => Navigator.pop(context,
                            PickedPlace(sp.name, sp.address, sp.lat, sp.lng)),
                  ),
              ]),
            );
          },
        ),
        const Divider(height: 1),
        for (final p in RecentPlacesService.matching(_recents, _ctrl.text)
            .take(_ctrl.text.trim().isEmpty ? 8 : 3))
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(p.name),
            subtitle: p.address.isEmpty ? null : Text(p.address),
            onTap: _loading ? null : () => _chooseRecent(p),
          ),
        for (final r in _results)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(r.title),
            subtitle: r.subtitle.isEmpty ? null : Text(r.subtitle),
            onTap: _loading ? null : () => _choose(r),
          ),
        if (_results.isEmpty && _ctrl.text.trim().length >= 3 && !_loading)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
                _places.lastFailed
                    ? '📵 Sem internet: a busca precisa de conexão.\n'
                        'Os destinos recentes acima funcionam sem internet. '
                        'Os avisos de radar e velocidade continuam funcionando.'
                    : 'Nenhum lugar encontrado',
                textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}
