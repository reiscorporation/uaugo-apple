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
  const PlaceSearchPage({super.key, required this.near, required this.title});
  final LatLng? near;
  final String title;

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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Texto mudou: agenda a busca.
  void _onChanged(String text) {
    _debounce?.cancel();
    // Espera parar de digitar para economizar buscas.
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(text));
  }

  /// Consulta as sugestões ao Google.
  Future<void> _search(String text) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await _places.search(text,
        nearLat: widget.near?.latitude, nearLng: widget.near?.longitude);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = r;
      _loading = false;
    });
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
        const Divider(height: 1),
        for (final r in _results)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(r.title),
            subtitle: r.subtitle.isEmpty ? null : Text(r.subtitle),
            onTap: _loading ? null : () => _choose(r),
          ),
        if (_results.isEmpty && _ctrl.text.trim().length >= 3 && !_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum lugar encontrado', textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}
