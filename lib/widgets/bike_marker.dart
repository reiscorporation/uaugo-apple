// ============================================================================
// bike_marker.dart — Ícone do veículo no mapa
//
// O que faz: Desenha o marcador com a foto (ou o ícone do tipo), o nome do
//   piloto e o modelo.
// Quem usa: MapScreen.
// ============================================================================

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/bike.dart';
import '../l10n/i18n.dart';
import 'vehicle_sprite.dart';

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

// 25/11: área do veículo "3D" maior (_top 128 -> 190, _w 240 -> 300, ~50%
// maior); a foto no círculo e a etiqueta continuam do mesmo tamanho.
const double _w = 300, _r = 58, _top = 190, _cy = _top - _r - 6, _h = _top + 82;

/// Largura máxima da etiqueta (nome e modelo).
const double _labelW = 216;

/// Ponto do marcador que fica sobre a posição (centro do círculo).
const bikeMarkerAnchor = Offset(0.5, _cy / _h);

/// Marcador do piloto: foto da moto (ou ícone do estilo na cor escolhida)
/// num círculo + etiqueta com nome e modelo.
///
/// [dir] = sentido em que o veículo anda na tela (0 = para cima, 1 = 45° à
/// direita... 7; ver screenDir): escolhe a vista do veículo sem foto.
Future<BitmapDescriptor> bikeMarker({
  required String name,
  required BikeProfile bike,
  bool isMe = false,
  int dir = 0,
}) async {
  // O mapa do Google ignorava o width/height e desenhava a imagem no
  // tamanho dela (240 px): o ícone nunca diminuía (16/11). A imagem já sai
  // no tamanho certo em pixels da tela.
  final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  final scale = bikeMarkerSize.width * dpr / _w;
  return BitmapDescriptor.bytes(
      await bikeMarkerPng(
          name: name, bike: bike, isMe: isMe, scale: scale, dir: dir),
      width: bikeMarkerSize.width,
      height: bikeMarkerSize.height);
}

/// Tamanho do marcador do piloto no mapa (pontos lógicos).
// 16/11: 80 -> 60 (testador: "meio grande", tapava as entradas próximas).
const bikeMarkerSize = Size(60 * _w / 240, 60 * _h / 240);

/// O mesmo desenho de [bikeMarker] em PNG: o "Você" fixo na tela (vista
/// solo), desenhado pelo app em vez de marcador do Google.
Future<Uint8List> bikeMarkerPng({
  required String name,
  required BikeProfile bike,
  bool isMe = false,
  double scale = 1,
  int dir = 0,
}) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..scale(scale);
  await _paintBadge(c, const Offset(_w / 2, _cy), bike, isMe,
      dir: dir, spriteBox: const Size(_w - 8, _top));
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
  )..layout(maxWidth: _labelW);
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
        )..layout(maxWidth: _labelW));

  final pillW = max(title.width, sub?.width ?? 0) + 24;
  final pillH = title.height + (sub?.height ?? 0) + 12;
  const top = _cy + _r + 12;
  c.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH((_w - pillW) / 2, top, pillW, pillH),
        const Radius.circular(14)),
    Paint()..color = const Color(0xDD000000),
  );
  title.paint(c, Offset((_w - title.width) / 2, top + 6));
  if (sub != null) {
    sub.paint(c, Offset((_w - sub.width) / 2, top + 6 + title.height));
  }

  final img = await rec
      .endRecording()
      .toImage((_w * scale).round(), (_h * scale).round());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Só o círculo do veículo (foto ou ícone), em PNG: é o mesmo desenho do
/// celular, mandado para a tela do carro (Android Auto).
Future<Uint8List> bikeBadgePng(BikeProfile bike) async {
  const size = (_r + 8) * 2;
  final rec = ui.PictureRecorder();
  await _paintBadge(Canvas(rec), const Offset(size / 2, size / 2), bike, true);
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Círculo com a foto do veículo; sem foto, o veículo "3D" do tipo na cor
/// escolhida (ou, no tipo que ainda não tem desenho, o ícone num círculo).
Future<void> _paintBadge(Canvas c, Offset center, BikeProfile bike, bool isMe,
    {int dir = 0, Size? spriteBox}) async {
  final color = Color(bike.color);
  if (bike.photoUrl == null ||
      BikeProfile.safePhotoUrl(bike.photoUrl!) == null) {
    final v = spriteView(dir);
    final img = await vehicleSprite(bike.style, bike.color, v.view);
    if (img != null) {
      // sem caixa (tela do carro, foto da viagem): o tamanho do círculo
      const round = Size((_r + 6) * 2, (_r + 6) * 2);
      final box = spriteBox ?? round;
      _paintSprite(
          c,
          Offset(center.dx,
              center.dy - (spriteBox == null ? 0 : _cy) + box.height / 2),
          box,
          img,
          mirror: v.mirror,
          isMe: isMe);
      return;
    }
  }
  c.drawCircle(center, _r + 6,
      Paint()..color = isMe ? const Color(0xFF4285F4) : Colors.white);
  c.drawCircle(center, _r, Paint()..color = color);

  final photo = bike.photoUrl == null ? null : await _loadPhoto(bike.photoUrl!);
  if (photo != null) {
    final s = min(photo.width, photo.height).toDouble();
    final src =
        Rect.fromLTWH((photo.width - s) / 2, (photo.height - s) / 2, s, s);
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
}

/// Veículo solto (sem círculo) dentro da caixa [box] centrada em [center],
/// apoiado no fundo dela: sombra no chão (azul no "Você") e um contorno
/// claro para destacar do mapa.
void _paintSprite(Canvas c, Offset center, Size box, ui.Image img,
    {required bool mirror, required bool isMe}) {
  final k = min((box.width - 8) / img.width, (box.height - 10) / img.height);
  final w = img.width * k, h = img.height * k;
  final dst = Rect.fromLTWH(
      center.dx - w / 2, center.dy + box.height / 2 - h - 6, w, h);
  final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
  // chão
  final ground = Rect.fromCenter(
      center: Offset(center.dx, dst.bottom - 4), width: w * 0.95, height: 22);
  c.drawOval(
      ground,
      Paint()
        ..color = isMe ? const Color(0x994285F4) : const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  if (isMe) {
    c.drawOval(
        ground.inflate(3),
        Paint()
          ..color = const Color(0xFF4285F4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
  }
  c.save();
  if (mirror) {
    c.translate(center.dx * 2, 0);
    c.scale(-1, 1);
  }
  // contorno claro
  c.saveLayer(
      dst.inflate(12),
      Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5)
        ..colorFilter =
            const ColorFilter.mode(Color(0xE6FFFFFF), BlendMode.srcIn));
  c.drawImageRect(img, src, dst, Paint());
  c.restore();
  c.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.medium);
  c.restore();
}
