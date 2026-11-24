// ============================================================================
// upcoming_steps.dart — Lista das próximas manobras
//
// O que faz: Mostra as próximas manobras da rota (seta, distância e rua), a
//   primeira em destaque; as já passadas saem da lista. Um componente só:
//   - celular/tablet DEITADO (23/11): os 40% da direita da tela, em todos os
//     modos (mapa e 3D), com o mapa nos outros 60%;
//   - UauGo2 de testes com o Android Auto conectado (tela do celular).
// Quem usa: MapScreen (painel lateral) e main.dart (_CarSteps).
// Dados: CarService.instance.upcoming, atualizado pelo MapScreen a cada
//   posição (_publishUpcoming).
// ============================================================================

import 'package:flutter/material.dart';

import '../l10n/i18n.dart';
import '../logic/itinerary.dart' show formatDistance;
import '../services/car_service.dart';

/// Seta da manobra (o mesmo desenho da barra de cima do mapa).
IconData maneuverIcon(String m) => switch (m) {
      'turn-slight-left' || 'ramp-left' || 'keep-left' => Icons.turn_slight_left,
      'turn-slight-right' || 'ramp-right' || 'keep-right' => Icons.turn_slight_right,
      'turn-sharp-left' => Icons.turn_sharp_left,
      'turn-sharp-right' => Icons.turn_sharp_right,
      'fork-left' || 'fork-right' => Icons.fork_right,
      'uturn-left' => Icons.u_turn_left,
      'uturn-right' => Icons.u_turn_right,
      'roundabout-left' => Icons.roundabout_left,
      final x when x.startsWith('roundabout') => Icons.roundabout_right,
      'merge' => Icons.merge,
      final x when x.contains('left') => Icons.turn_left,
      final x when x.contains('right') => Icons.turn_right,
      _ => Icons.straight,
    };

/// Lista das próximas manobras. [dark]: fundo escuro (tela do carro
/// conectado); senão branco com letra preta, como o cartão de chegada.
class UpcomingSteps extends StatelessWidget {
  const UpcomingSteps(
      {super.key, this.dark = false, this.shrinkWrap = false, this.maxItems, this.skipFirst = false});

  final bool dark;
  final bool shrinkWrap;

  /// Em pé (23/11): só as próximas [maxItems] manobras, num cartão compacto.
  final int? maxItems;

  /// Pula a 1ª (já está na barra de cima).
  final bool skipFirst;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : Colors.black;
    return ValueListenableBuilder<List<(String, String, int)>>(
      valueListenable: CarService.instance.upcoming,
      builder: (_, all, __) {
        var list = skipFirst && all.isNotEmpty ? all.sublist(1) : all;
        if (maxItems != null && list.length > maxItems!) list = list.sublist(0, maxItems);
        if (list.isEmpty) {
          return shrinkWrap
              ? const SizedBox.shrink()
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr('Os próximos passos da rota aparecem aqui.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: fg.withAlpha(160), fontSize: 15)),
                  ),
                );
        }
        return ListView(
          shrinkWrap: shrinkWrap,
          physics: maxItems != null ? const NeverScrollableScrollPhysics() : null,
          padding: EdgeInsets.all(maxItems != null ? 6 : 8),
          children: [
            for (final (i, (m, text, d)) in list.indexed)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: (i == 0 && !skipFirst)
                      ? const Color(0xFFFF7A1A)
                      : (dark ? Colors.white10 : const Color(0xFFF1F3F5)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(maneuverIcon(m),
                      color: (i == 0 && !skipFirst) ? Colors.white : fg, size: (i == 0 && !skipFirst) ? 32 : 26),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: Text(formatDistance(d),
                        maxLines: 1,
                        style: TextStyle(
                            color: (i == 0 && !skipFirst) ? Colors.white : fg,
                            fontSize: (i == 0 && !skipFirst) ? 18 : 15,
                            fontWeight: FontWeight.w900)),
                  ),
                  Expanded(
                    child: Text(text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: (i == 0 && !skipFirst) ? Colors.white : fg,
                            fontSize: (i == 0 && !skipFirst) ? 15 : 14,
                            fontWeight: (i == 0 && !skipFirst) ? FontWeight.w700 : FontWeight.w500)),
                  ),
                ]),
              ),
          ],
        );
      },
    );
  }
}
