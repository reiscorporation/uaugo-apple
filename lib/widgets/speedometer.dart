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
  });

  final double? kmh; // null = sem GPS
  final RoadLimit? limit;
  final SpeedLevel level;
  final VoidCallback? onTap;

  /// Segurar: confirmar/corrigir o limite da via (Gold/administração).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
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
