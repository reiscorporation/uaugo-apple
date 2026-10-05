// ============================================================================
// trip_share.dart — Compartilhar a viagem
//
// O que faz: Gera a imagem para redes sociais (mapa + números), salva na
//   galeria e o arquivo GPX (Strava etc.), e abre o compartilhar do celular.
// Quem usa: HistoryScreen.
// Onde mexer: Layout da imagem: buildShareImage (1080x1350).
// ============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/geo.dart';
import '../logic/itinerary.dart';
import '../models/trip_record.dart';

/// Data para a imagem: "05/10/2026".
String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Imagem para redes sociais (1080 x 1350): mapa com o caminho feito em
/// cima e, embaixo, o título, a data e os números da viagem.
Future<Uint8List> buildShareImage(TripRecord t, Uint8List? mapPng) async {
  const w = 1080.0, h = 1350.0, mapH = 1000.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(const Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF1B120E));

  // Mapa (recorte "cover" no topo).
  if (mapPng != null) {
    final img = (await (await ui.instantiateImageCodec(mapPng)).getNextFrame()).image;
    final s = (w / img.width) > (mapH / img.height)
        ? w / img.width
        : mapH / img.height;
    final sw = w / s, sh = mapH / s;
    c.drawImageRect(
        img,
        Rect.fromLTWH((img.width - sw) / 2, (img.height - sh) / 2, sw, sh),
        const Rect.fromLTWH(0, 0, w, mapH),
        Paint()..filterQuality = FilterQuality.high);
  }

  // Logo do app no canto do mapa.
  try {
    final logo = await rootBundle.load('assets/branding/comboio_logo.png');
    final li = (await (await ui.instantiateImageCodec(logo.buffer.asUint8List(),
                targetWidth: 150))
            .getNextFrame())
        .image;
    c.drawImage(li, const Offset(30, 30), Paint());
  } catch (_) {}

  /// Escreve um texto na imagem (uma linha, com "…" se não couber).
  void text(String s, double x, double y, double size,
      {Color color = Colors.white, FontWeight weight = FontWeight.w600,
      double maxW = w - 120}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(c, Offset(x, y));
  }

  text(t.title, 60, mapH + 30, 52, weight: FontWeight.w800);
  text('${_date(t.startedAt)} · ${formatTime(t.startedAt)}–${formatTime(t.endedAt)}',
      60, mapH + 98, 32, color: const Color(0xFFFFCC80));
  final stats = [
    (formatDistance(t.distanceM.round()), 'percorridos'),
    (formatDuration(t.movingS), 'em movimento'),
    ('${t.avgKmh.round()} km/h', 'média'),
    ('${t.maxKmh.round()} km/h', 'máxima'),
  ];
  for (var i = 0; i < stats.length; i++) {
    final x = 60 + i * (w - 120) / 4;
    text(stats[i].$1, x, mapH + 175, 40,
        weight: FontWeight.w900, maxW: (w - 120) / 4 - 10);
    text(stats[i].$2, x, mapH + 228, 26,
        color: Colors.white70, maxW: (w - 120) / 4 - 10);
  }
  text('Comboio · HelpAITech', 60, h - 60, 24, color: Colors.white54);

  final pic = rec.endRecording();
  final out = await pic.toImage(w.toInt(), h.toInt());
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Arquivo GPX (aceito por Strava, Google Earth, Wikiloc...).
String buildGpx(TripRecord t) {
  final pts = decodePolyline(t.trackPolyline);
  /// Escapa caracteres especiais do XML (GPX).
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<gpx version="1.1" creator="Comboio" '
        'xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <metadata><name>${esc(t.title)}</name>'
        '<time>${t.startedAt.toUtc().toIso8601String()}</time></metadata>')
    ..writeln('  <trk><name>${esc(t.title)}</name><trkseg>');
  for (final p in pts) {
    b.writeln('    <trkpt lat="${p.latitude.toStringAsFixed(6)}" '
        'lon="${p.longitude.toStringAsFixed(6)}"/>');
  }
  b
    ..writeln('  </trkseg></trk>')
    ..writeln('</gpx>');
  return b.toString();
}

/// Gera a imagem, salva na galeria e abre o compartilhar.
Future<void> shareTrip(BuildContext context, TripRecord t,
    GoogleMapController? map) async {
  final messenger = ScaffoldMessenger.of(context);
  Uint8List? png;
  try {
    png = await map?.takeSnapshot();
  } catch (_) {}
  final img = await buildShareImage(t, png);
  final dir = await getTemporaryDirectory();
  final name = 'comboio_${t.startedAt.millisecondsSinceEpoch}';
  final imgFile = File('${dir.path}/$name.png');
  await imgFile.writeAsBytes(img, flush: true);
  final gpxFile = File('${dir.path}/$name.gpx');
  await gpxFile.writeAsString(buildGpx(t), flush: true);
  try {
    await Gal.putImage(imgFile.path, album: 'Comboio');
    messenger.showSnackBar(const SnackBar(
        content: Text('Imagem salva na galeria (álbum Comboio)')));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text('Não foi possível salvar na galeria: $e')));
  }
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile(imgFile.path, mimeType: 'image/png'),
      XFile(gpxFile.path, mimeType: 'application/gpx+xml'),
    ],
    text: '${t.title} · ${formatDistance(t.distanceM.round())} percorridos '
        'com o Comboio',
  ));
}
