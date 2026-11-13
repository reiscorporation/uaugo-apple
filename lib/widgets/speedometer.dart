// ============================================================================
// speedometer.dart — Velocímetro
//
// O que faz: Mostra a velocidade e a placa do limite da via; vermelho acima do
//   limite, âmbar quando o limite é estimado.
// Quem usa: MapScreen.
// ============================================================================

import 'package:flutter/material.dart';

import '../logic/speed.dart';
import '../l10n/i18n.dart';

/// Velocímetro: velocidade atual e a placa do limite da via.
/// Muda de cor ao passar do limite (âmbar se o limite for estimado).
class Speedometer extends StatelessWidget {
  const Speedometer({
    super.key,
    required this.kmh,
    required this.limit,
    required this.level,
    this.onTap,
    this.onLongPress,
    this.hud = false,
  });

  /// Visual do 3D (painel do para-brisa: número grande sobre vidro escuro,
  /// "KM/H" embaixo, placa ao lado, pisca vermelho/amarelo acima do limite),
  /// no mesmo canto e tamanho do velocímetro do mapa (13/11).
  final bool hud;

  final double? kmh; // null = sem GPS
  final RoadLimit? limit;
  final SpeedLevel level;
  final VoidCallback? onTap;

  /// Segurar: confirmar/corrigir o limite da via (Gold/administração).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (hud) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: _HudSpeedometer(kmh: kmh, limit: limit, over: level != SpeedLevel.normal),
      );
    }
    final (bg, fg) = switch (level) {
      SpeedLevel.over => (Colors.red.shade700, Colors.white),
      SpeedLevel.overEstimated => (Colors.amber.shade700, Colors.black),
      // Padrão: azul-marinho da marca; Clean (tema claro): branco.
      SpeedLevel.normal => Theme.of(context).brightness == Brightness.light
          ? (const Color(0xF2FFFFFF), const Color(0xFF16202C))
          : (const Color(0xEE0F1B2D), Colors.white),
    };
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 112,
        height: 104,
        child: Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 96,
            height: 96,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black54)],
            ),
            // Tamanho fixo (sem a escala de fonte do celular): o velocímetro
            // tem tamanho fixo e a fonte grande fazia o número estourar.
            padding: const EdgeInsets.all(6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  kmh == null ? '--' : kmh!.round().toString(),
                  maxLines: 1,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                      color: fg,
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                Text('km/h',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(color: fg.withAlpha(200))),
              ]),
            ),
          ),
          if (limit != null)
            Positioned(
              right: 0,
              top: 0,
              child: Tooltip(
                message: limit!.estimated
                    ? tr('Limite estimado pelo tipo de via')
                    : tr('Limite da via'),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: limit!.estimated ? Colors.grey : Colors.red,
                        width: 5),
                  ),
                  // "110" sempre numa linha, do tamanho da placa (a fonte
                  // grande do celular quebrava o número e cortava o "0").
                  padding: const EdgeInsets.all(2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      limit!.estimated ? '~${limit!.kmh}' : '${limit!.kmh}',
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: limit!.estimated ? 12 : 15),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}


/// Velocímetro com o visual do painel 3D (vidro escuro em hexágono).
class _HudSpeedometer extends StatefulWidget {
  const _HudSpeedometer({required this.kmh, required this.limit, required this.over});
  final double? kmh;
  final RoadLimit? limit;
  final bool over;

  @override
  State<_HudSpeedometer> createState() => _HudSpeedometerState();
}

class _HudSpeedometerState extends State<_HudSpeedometer>
    with SingleTickerProviderStateMixin {
  // Pisca a cada 0,5 s acima do limite (como no painel do 3D).
  late final _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_HudSpeedometer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.over && !_blink.isAnimating) _blink.repeat();
    if (!widget.over && _blink.isAnimating) _blink.stop();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  static const _ink = Color(0xFFF4FBFF);
  static const _shadow = [Shadow(blurRadius: 6, color: Color(0x8C000000), offset: Offset(0, 1))];

  @override
  Widget build(BuildContext context) {
    final lim = widget.limit;
    return SizedBox(
      width: 112,
      height: 104,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          top: 8,
          width: 96,
          height: 96,
          child: ClipPath(
            clipper: _HexClipper(),
            child: CustomPaint(
              painter: _HexLinePainter(),
              child: Container(
                color: const Color(0x800E1824),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedBuilder(
                    animation: _blink,
                    builder: (_, __) {
                      final color = !widget.over
                          ? _ink
                          : (_blink.value < 0.5 ? const Color(0xFFFF4B4B) : const Color(0xFFFFD23F));
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          widget.kmh == null ? '--' : widget.kmh!.round().toString(),
                          maxLines: 1,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                              color: color,
                              fontSize: 46,
                              height: 0.95,
                              fontWeight: FontWeight.w800,
                              shadows: _shadow,
                              fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        const SizedBox(height: 2),
                        const Text('KM/H',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                                color: Color(0xD9F4FBFF),
                                fontSize: 10,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w600,
                                shadows: _shadow)),
                      ]);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (lim != null)
          Positioned(
            right: 0,
            top: 0,
            child: AnimatedBuilder(
              animation: _blink,
              builder: (_, child) => Transform.scale(
                  scale: widget.over ? 1 + 0.14 * (_blink.value < 0.5 ? _blink.value * 2 : (1 - _blink.value) * 2) : 1,
                  child: child),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: lim.estimated ? Colors.grey : const Color(0xFFD8262B), width: 5),
                ),
                padding: const EdgeInsets.all(2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(lim.estimated ? '~${lim.kmh}' : '${lim.kmh}',
                      maxLines: 1,
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                          color: const Color(0xFF111111),
                          fontWeight: FontWeight.w800,
                          fontSize: lim.estimated ? 12 : 15)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

Path _hexPath(Size s) => Path()
  ..moveTo(s.width * 0.14, 0)
  ..lineTo(s.width * 0.86, 0)
  ..lineTo(s.width, s.height / 2)
  ..lineTo(s.width * 0.86, s.height)
  ..lineTo(s.width * 0.14, s.height)
  ..lineTo(0, s.height / 2)
  ..close();

class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => _hexPath(size);
  @override
  bool shouldReclip(_HexClipper oldClipper) => false;
}

/// Contorno claro do hexágono (o mesmo do painel do 3D).
class _HexLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
        _hexPath(size),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 // metade fica fora do recorte: 2 px visíveis
          ..color = const Color(0xD9F4FBFF));
  }

  @override
  bool shouldRepaint(_HexLinePainter oldDelegate) => false;
}
