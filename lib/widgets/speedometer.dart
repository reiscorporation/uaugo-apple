// ============================================================================
// speedometer.dart — Velocímetro
//
// O que faz: Mostra a velocidade e a placa do limite da via; vermelho acima do
//   limite, âmbar quando o limite é estimado.
// Quem usa: MapScreen.
// ============================================================================

import 'package:flutter/material.dart';

import '../logic/speed.dart';

/// Velocímetro: velocidade atual e a placa do limite da via.
/// Muda de cor ao passar do limite (âmbar se o limite for estimado).
class Speedometer extends StatelessWidget {
  const Speedometer({
    super.key,
    required this.kmh,
    required this.limit,
    required this.level,
    this.onTap,
  });

  final double? kmh; // null = sem GPS
  final RoadLimit? limit;
  final SpeedLevel level;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (level) {
      SpeedLevel.over => (Colors.red.shade700, Colors.white),
      SpeedLevel.overEstimated => (Colors.amber.shade700, Colors.black),
      SpeedLevel.normal => (const Color(0xEE1E1A16), Colors.white),
    };
    return GestureDetector(
      onTap: onTap,
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
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                kmh == null ? '--' : kmh!.round().toString(),
                style: TextStyle(
                    color: fg,
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              Text('km/h', style: TextStyle(color: fg.withAlpha(200))),
            ]),
          ),
          if (limit != null)
            Positioned(
              right: 0,
              top: 0,
              child: Tooltip(
                message: limit!.estimated
                    ? 'Limite estimado pelo tipo de via'
                    : 'Limite da via',
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
                  child: Text(
                    limit!.estimated ? '~${limit!.kmh}' : '${limit!.kmh}',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: limit!.estimated ? 12 : 15),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
