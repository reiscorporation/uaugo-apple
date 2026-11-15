// ============================================================================
// trip_share.dart — Compartilhar a viagem
//
// O que faz: Gera a imagem para redes sociais (mapa + números), salva na
//   galeria e o arquivo GPX (Strava etc.), e abre o compartilhar do celular.
//   Também o GIF da rota acelerada (buildRouteGif) e o JPEG para a comunidade.
// Quem usa: HistoryScreen e CommunityPostSheet.
// Onde mexer: Layout da imagem: buildShareImage (1080x1350); GIF: buildRouteGif
//   (velocidade em logic/route_gif.dart).
// ============================================================================

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as im;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/geo.dart';
import '../logic/itinerary.dart';
import '../logic/route_gif.dart';
import '../services/profile_service.dart';
import 'bike_marker.dart' show bikeBadgePng;
import '../models/trip_record.dart';
import '../l10n/i18n.dart';

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
    (formatDuration(t.movingS), tr('em movimento')),
    ('${t.avgKmh.round()} km/h', tr('média')),
    ('${t.maxKmh.round()} km/h', tr('máxima')),
  ];
  for (var i = 0; i < stats.length; i++) {
    final x = 60 + i * (w - 120) / 4;
    text(stats[i].$1, x, mapH + 175, 40,
        weight: FontWeight.w900, maxW: (w - 120) / 4 - 10);
    text(stats[i].$2, x, mapH + 228, 26,
        color: Colors.white70, maxW: (w - 120) / 4 - 10);
  }
  text(tr('UauGo · HelpAITech'), 60, h - 60, 24, color: Colors.white54);

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
    ..writeln('<gpx version="1.1" creator="UauGo" '
        'xmlns="http://www.topografix.com/GPX/1/1">')
    ..writeln('  <metadata><name>${esc(t.title)}</name>'
        '<time>${t.startedAt.toUtc().toIso8601String()}</time></metadata>')
    ..writeln('  <trk><name>${esc(t.title)}</name><trkseg>');
  for (final p in pts) {
    b.writeln('    <trkpt lat="${p.latitude.toStringAsFixed(6)}" lon="${p.longitude.toStringAsFixed(6)}"/>');
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
    await Gal.putImage(imgFile.path, album: 'UauGo');
    messenger.showSnackBar(SnackBar(
        content: Text(tr('Imagem salva na galeria (álbum UauGo)'))));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text(tr('Não foi possível salvar na galeria: {0}', [e]))));
  }
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile(imgFile.path, mimeType: 'image/png'),
      XFile(gpxFile.path, mimeType: 'application/gpx+xml'),
    ],
    text: tr('{0} · {1} percorridos com o UauGo', [t.title, formatDistance(t.distanceM.round())]),
  ));
}

/// Imagem da viagem (PNG) em JPEG, como a comunidade aceita (até ~600 KB).
Future<Uint8List> shareImageJpeg(Uint8List png) => compute(_toJpeg, png);

Uint8List _toJpeg(Uint8List png) {
  var image = im.decodePng(png)!;
  var q = 85;
  var out = im.encodeJpg(image, quality: q);
  while (out.length > 560 * 1024 && q > 50) {
    q -= 10;
    out = im.encodeJpg(image, quality: q);
  }
  if (out.length > 560 * 1024) {
    image = im.copyResize(image, width: 864);
    out = im.encodeJpg(image, quality: 75);
  }
  return out;
}

/// GIF da viagem: o caminho feito sendo percorrido bem acelerado (50x o
/// tempo em movimento, 3 a 12 s) sobre o mapa que está na tela, com o logo
/// e o nome da viagem embaixo. null se o mapa não estiver pronto.
Future<Uint8List?> buildRouteGif(TripRecord t, GoogleMapController? map,
    {double devicePixelRatio = 1}) async {
  if (map == null) return null;
  final track = decodePolyline(t.trackPolyline);
  if (track.length < 2) return null;
  Uint8List? png;
  try {
    png = await map.takeSnapshot();
  } catch (_) {}
  if (png == null) return null;
  final snap = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;

  // Até ~150 pontos do caminho, em pixels da tela do mapa.
  final step = (track.length / 150).ceil().clamp(1, 1 << 30);
  final pts = <(double, double)>[];
  for (var i = 0; i < track.length; i += step) {
    final c = await map.getScreenCoordinate(track[i]);
    pts.add((c.x.toDouble(), c.y.toDouble()));
  }
  final last = await map.getScreenCoordinate(track.last);
  pts.add((last.x.toDouble(), last.y.toDouble()));
  // Android dá pixels de verdade (como o snapshot); iOS, pontos: ajusta.
  final maxX = pts.map((p) => p.$1).reduce((a, b) => a > b ? a : b);
  final maxY = pts.map((p) => p.$2).reduce((a, b) => a > b ? a : b);
  final dpr = devicePixelRatio > 1 &&
          maxX <= snap.width / devicePixelRatio * 1.02 &&
          maxY <= snap.height / devicePixelRatio * 1.02
      ? devicePixelRatio
      : 1.0;

  // Fundo: o mapa (480 de largura) e uma faixa com o logo e o nome.
  const w = 480.0, band = 92.0;
  final k = w / snap.width;
  final mapH = (snap.height * k).clamp(200.0, 640.0);
  final h = mapH + band;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
  c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF0F1B2D));
  c.drawImageRect(snap, Rect.fromLTWH(0, 0, snap.width.toDouble(), mapH / k),
      Rect.fromLTWH(0, 0, w, mapH), Paint()..filterQuality = FilterQuality.medium);
  try {
    final logo = await rootBundle.load('assets/branding/comboio_logo.png');
    final li = (await (await ui.instantiateImageCodec(logo.buffer.asUint8List(),
                targetWidth: 64))
            .getNextFrame())
        .image;
    c.drawImage(li, Offset(14, mapH + (band - li.height) / 2), Paint());
  } catch (_) {}
  void text(String s, double y, double size, Color color, {bool bold = false}) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1, ellipsis: '…'))
      ..pushStyle(ui.TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500))
      ..addText(s);
    final para = pb.build()..layout(const ui.ParagraphConstraints(width: w - 100));
    c.drawParagraph(para, Offset(90, y));
  }
  text(t.title, mapH + 16, 22, Colors.white, bold: true);
  text('${formatDistance(t.distanceM.round())} · ${formatDuration(t.movingS)} · ${_date(t.startedAt)}',
      mapH + 50, 16, Colors.white70);
  final bg = await rec.endRecording().toImage(w.round(), h.round());
  final raw = (await bg.toByteData(format: ui.ImageByteFormat.rawRgba))!;

  final path = [for (final p in pts) (p.$1 * dpr * k, p.$2 * dpr * k)];
  final plan = gifPlan(t.movingS);
  // O veículo escolhido pelo piloto (foto ou ícone, o mesmo do mapa e do
  // Android Auto) é quem percorre a rota no GIF.
  const iconSize = 44;
  Uint8List? icon;
  try {
    final badge = await bikeBadgePng(await ProfileService.load());
    final bi = (await (await ui.instantiateImageCodec(badge,
                targetWidth: iconSize, targetHeight: iconSize))
            .getNextFrame())
        .image;
    icon = (await bi.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
  } catch (_) {}
  return compute(
      encodeRouteGif,
      RouteGifInput(raw.buffer.asUint8List(), w.round(), h.round(), path,
          plan.frames, plan.delayCs,
          iconRgba: icon, iconSize: icon == null ? 0 : iconSize));
}

/// Gera o GIF, salva na galeria e abre o compartilhar.
Future<void> shareRouteGif(BuildContext context, TripRecord t,
    GoogleMapController? map) async {
  final messenger = ScaffoldMessenger.of(context);
  final dpr = MediaQuery.of(context).devicePixelRatio;
  messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 30),
      content: Text(tr('Criando o GIF da rota… pode levar alguns segundos'))));
  final gif = await buildRouteGif(t, map, devicePixelRatio: dpr);
  messenger.hideCurrentSnackBar();
  if (gif == null) {
    messenger.showSnackBar(SnackBar(
        content: Text(tr('Não foi possível criar o GIF (mapa ou caminho da viagem indisponível).'))));
    return;
  }
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/uaugo_rota_${t.startedAt.millisecondsSinceEpoch}.gif');
  await f.writeAsBytes(gif, flush: true);
  try {
    await Gal.putImage(f.path, album: 'UauGo');
    messenger.showSnackBar(
        SnackBar(content: Text(tr('GIF salvo na galeria (álbum UauGo)'))));
  } catch (_) {}
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path, mimeType: 'image/gif')],
    text: tr('{0} · {1} percorridos com o UauGo', [t.title, formatDistance(t.distanceM.round())]),
  ));
}
