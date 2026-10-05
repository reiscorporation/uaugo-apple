// ============================================================================
// emoji_marker.dart — Marcador com emoji
//
// O que faz: Transforma um emoji num ícone de mapa (paradas, alertas).
// Quem usa: MapScreen, PlanScreen.
// ============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Desenha um marcador redondo com emoji (🚓, 🕳️, ⚠️...) para o mapa.
Future<BitmapDescriptor> emojiMarker(String emoji, Color color) async {
  const size = 120.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const center = Offset(size / 2, size / 2);

  canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
  canvas.drawCircle(center, size / 2 - 7, Paint()..color = color);

  final tp = TextPainter(
    text: TextSpan(text: emoji, style: const TextStyle(fontSize: 60)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

  final image =
      await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(),
      width: 40, height: 40);
}
