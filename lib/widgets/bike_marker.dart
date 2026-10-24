// ============================================================================
// bike_marker.dart — Ícone do veículo no mapa
//
// O que faz: Desenha o marcador com a foto (ou o ícone do tipo), o nome do
//   piloto e o modelo.
// Quem usa: MapScreen.
// ============================================================================

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/bike.dart';
import '../l10n/i18n.dart';

final Map<String, ui.Image> _photoCache = {};

/// Maior foto aceita (o Storage já recusa envios acima disso).
const _maxPhotoBytes = 2 * 1024 * 1024;

/// Baixa a foto do veículo para desenhar no marcador (null se falhar).
/// Só baixa do Storage do próprio app (BikeProfile.safePhotoUrl), até 2 MB.
Future<ui.Image?> _loadPhoto(String url) async {
  if (BikeProfile.safePhotoUrl(url) == null) return null;
  final cached = _photoCache[url];
  if (cached != null) return cached;
  try {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 || res.bodyBytes.length > _maxPhotoBytes) {
      return null;
    }
    final codec =
        await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 160);
    final frame = await codec.getNextFrame();
    return _photoCache[url] = frame.image;
  } catch (_) {
    return null;
  }
}

const double _w = 240, _h = 210, _r = 58, _cy = 64;

/// Ponto do marcador que fica sobre a posição (centro do círculo).
const bikeMarkerAnchor = Offset(0.5, _cy / _h);

/// Marcador do piloto: foto da moto (ou ícone do estilo na cor escolhida)
/// num círculo + etiqueta com nome e modelo.
Future<BitmapDescriptor> bikeMarker({
  required String name,
  required BikeProfile bike,
  bool isMe = false,
}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final color = Color(bike.color);
  const center = Offset(_w / 2, _cy);

  c.drawCircle(center, _r + 6,
      Paint()..color = isMe ? const Color(0xFF4285F4) : Colors.white);
  c.drawCircle(center, _r, Paint()..color = color);

  final photo = bike.photoUrl == null ? null : await _loadPhoto(bike.photoUrl!);
  if (photo != null) {
    final s = min(photo.width, photo.height).toDouble();
    final src = Rect.fromLTWH(
        (photo.width - s) / 2, (photo.height - s) / 2, s, s);
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: _r)));
    c.drawImageRect(photo, src, Rect.fromCircle(center: center, radius: _r),
        Paint()..filterQuality = FilterQuality.medium);
    c.restore();
  } else {
    final iconColor =
        color.computeLuminance() > 0.6 ? Colors.black : Colors.white;
    final icon = bike.style.icon;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 70,
          color: iconColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  // Etiqueta: nome + modelo
  final title = TextPainter(
    text: TextSpan(
      text: isMe ? tr('Você') : name,
      style: const TextStyle(
          color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: _w - 24);
  final sub = bike.displayName.isEmpty
      ? null
      : (TextPainter(
          text: TextSpan(
            text: bike.displayName,
            style: const TextStyle(color: Colors.white70, fontSize: 21),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: _w - 24));

  final pillW = max(title.width, sub?.width ?? 0) + 24;
  final pillH = title.height + (sub?.height ?? 0) + 12;
  const top = _cy + _r + 12;
  c.drawRRect(
    RRect.fromRectAndRadius(
        Rect.fromLTWH((_w - pillW) / 2, top, pillW, pillH),
        const Radius.circular(14)),
    Paint()..color = const Color(0xDD000000),
  );
  title.paint(c, Offset((_w - title.width) / 2, top + 6));
  if (sub != null) {
    sub.paint(c, Offset((_w - sub.width) / 2, top + 6 + title.height));
  }

  final img = await rec.endRecording().toImage(_w.toInt(), _h.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
      width: 80, height: 80 * _h / _w);
}
