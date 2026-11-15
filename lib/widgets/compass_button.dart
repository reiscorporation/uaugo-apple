// ============================================================================
// compass_button.dart — Bússola do mapa
//
// O que faz: Botão redondo com uma bússola de verdade: a agulha (ponta
//   vermelha = norte) e o "N" giram com o mapa, apontando sempre para o
//   norte. Toque: o mapa alterna entre seguir a direção e norte para cima.
// Quem usa: MapScreen (só no mapa; no 3D não aparece).
// Onde mexer: Desenho em _CompassPainter.
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';

class CompassButton extends StatelessWidget {
  const CompassButton({
    super.key,
    required this.bearing,
    required this.onPressed,
    this.tooltip,
    this.size = 52,
  });

  /// Giro do mapa em graus (0 = norte para cima).
  final double bearing;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xFF0F1B2D),
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _CompassPainter(bearing)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _CompassPainter extends CustomPainter {
  _CompassPainter(this.bearing);
  final double bearing;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    // Aro e marcas dos pontos cardeais (fixos na moldura).
    canvas.drawCircle(c, r - 3,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    // O mapa girou "bearing" graus: o norte fica a -bearing na tela.
    canvas.rotate(-bearing * pi / 180);
    final tick = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1.5;
    for (var i = 1; i < 4; i++) {
      final a = i * pi / 2;
      canvas.drawLine(Offset(sin(a) * (r - 7), -cos(a) * (r - 7)),
          Offset(sin(a) * (r - 3), -cos(a) * (r - 3)), tick);
    }
    // Agulha: metade norte vermelha, metade sul branca.
    final len = r * 0.5, half = r * 0.17;
    canvas.drawPath(
        Path()
          ..moveTo(0, -len)
          ..lineTo(half, 0)
          ..lineTo(-half, 0)
          ..close(),
        Paint()..color = const Color(0xFFE53935));
    canvas.drawPath(
        Path()
          ..moveTo(0, len)
          ..lineTo(half, 0)
          ..lineTo(-half, 0)
          ..close(),
        Paint()..color = Colors.white);
    canvas.drawCircle(Offset.zero, 2.5, Paint()..color = const Color(0xFF0F1B2D));
    // "N" na ponta norte, sempre de pé para leitura.
    final tp = TextPainter(
      text: const TextSpan(
          text: 'N',
          style: TextStyle(color: Color(0xFFFF8A80), fontSize: 10, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.translate(0, -(r - 8.5));
    canvas.rotate(bearing * pi / 180);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompassPainter old) => old.bearing != bearing;
}
