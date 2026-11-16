// ============================================================================
// pontos_mapa.dart — "Ver no mapa": vários lugares de uma lista num mapa
//
// O que faz: Mostra no mapa os pontos de uma lista (turismo, hospedagem,
//   postos), como o "Ver no mapa" da comunidade (uaugo.com.br/viagem): todos
//   juntos com o ponto de referência; com [foco], já abre perto daquele.
//   Tocar no marcador mostra o nome; tocar no nome abre as opções do lugar.
// Quem usa: NaRotaScreen.
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../l10n/i18n.dart';
import 'emoji_marker.dart';

/// Um lugar para o mapa.
class PontoMapa {
  const PontoMapa({
    required this.nome,
    required this.lat,
    required this.lng,
    required this.emoji,
    this.detalhe,
    this.onAbrir,
  });

  final String nome;
  final double lat, lng;
  final String emoji;

  /// Linha de baixo do nome (tipo, distância, preço...).
  final String? detalhe;

  /// Tocar no nome do marcador: abre as opções do lugar.
  final VoidCallback? onAbrir;
}

class PontosMapaScreen extends StatefulWidget {
  const PontosMapaScreen({
    super.key,
    required this.titulo,
    required this.pontos,
    required this.centroLat,
    required this.centroLng,
    required this.centroNome,
    this.cor = const Color(0xFFFF7A1A),
    this.foco,
  });

  final String titulo;
  final List<PontoMapa> pontos;

  /// Ponto de referência (parada, destino ou onde o piloto está).
  final double centroLat, centroLng;
  final String centroNome;

  /// Cor dos marcadores desta lista.
  final Color cor;

  /// Índice em [pontos] para abrir já perto dele (o "📍 Ver no mapa" do item).
  final int? foco;

  @override
  State<PontosMapaScreen> createState() => _PontosMapaScreenState();
}

class _PontosMapaScreenState extends State<PontosMapaScreen> {
  final _icones = <String, BitmapDescriptor>{};
  GoogleMapController? _map;

  @override
  void initState() {
    super.initState();
    _carregaIcones();
  }

  Future<void> _carregaIcones() async {
    for (final e in {for (final p in widget.pontos) p.emoji}) {
      _icones[e] = await emojiMarker(e, widget.cor);
    }
    if (mounted) setState(() {});
  }

  /// Enquadra todos os pontos e a referência.
  LatLngBounds _limites() {
    var s = widget.centroLat, n = s, w = widget.centroLng, e = w;
    for (final p in widget.pontos) {
      s = min(s, p.lat);
      n = max(n, p.lat);
      w = min(w, p.lng);
      e = max(e, p.lng);
    }
    return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
  }

  void _criado(GoogleMapController c) {
    _map = c;
    final f = widget.foco;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (f != null && f >= 0 && f < widget.pontos.length) {
        final p = widget.pontos[f];
        c.moveCamera(CameraUpdate.newLatLngZoom(LatLng(p.lat, p.lng), 15));
        c.showMarkerInfoWindow(MarkerId('p$f'));
      } else if (widget.pontos.isNotEmpty) {
        c.moveCamera(CameraUpdate.newLatLngBounds(_limites(), 56));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('centro'),
        position: LatLng(widget.centroLat, widget.centroLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: widget.centroNome),
        zIndexInt: 2,
      ),
      for (var i = 0; i < widget.pontos.length; i++)
        Marker(
          markerId: MarkerId('p$i'),
          position: LatLng(widget.pontos[i].lat, widget.pontos[i].lng),
          icon: _icones[widget.pontos[i].emoji] ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: widget.pontos[i].nome,
            snippet: [
              if (widget.pontos[i].detalhe != null) widget.pontos[i].detalhe!,
              if (widget.pontos[i].onAbrir != null) tr('toque para opções'),
            ].join(' · '),
            onTap: widget.pontos[i].onAbrir,
          ),
        ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.titulo),
          Text(tr('{0} no mapa', [widget.pontos.length]),
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          if (widget.pontos.isNotEmpty)
            IconButton(
              tooltip: tr('Ver todos'),
              icon: const Icon(Icons.zoom_out_map),
              onPressed: () =>
                  _map?.animateCamera(CameraUpdate.newLatLngBounds(_limites(), 56)),
            ),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
            target: LatLng(widget.centroLat, widget.centroLng), zoom: 11),
        markers: markers,
        onMapCreated: _criado,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        zoomControlsEnabled: true,
      ),
    );
  }
}
