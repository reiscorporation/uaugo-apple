// ============================================================================
// calendar_service.dart — Lembrete da viagem planejada na agenda do celular
//
// O que faz: Abre o app de agenda do celular já preenchido (título, saída,
//   chegada prevista, destino e alarme). Quem salva é a própria agenda: o
//   UauGo não pede permissão de agenda nem lê os compromissos do usuário.
// Quem usa: TripPreviewSheet (ao salvar a viagem) e a lista "Viagens
//   planejadas" da tela inicial.
// Onde mexer: Lado Android em MainActivity.kt (canal "uaugo/device").
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../l10n/i18n.dart';

class CalendarService {
  CalendarService._();

  static const _ch = MethodChannel('uaugo/device');

  /// Abre a agenda com o evento da viagem. [duration]: tempo previsto (sem
  /// ele, 1 hora). Devolve false se não houver app de agenda.
  static Future<bool> addTrip({
    required String title,
    required DateTime departAt,
    Duration? duration,
    String destination = '',
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final end = departAt.add(duration ?? const Duration(hours: 1));
    try {
      return await _ch.invokeMethod<bool>('addToCalendar', {
            'title': tr('Viagem: {0}', [title]),
            'begin': departAt.millisecondsSinceEpoch,
            'end': end.millisecondsSinceEpoch,
            'location': destination,
            'description': tr('Viagem planejada no UauGo. Abra o app e toque em "Viagens planejadas" para sair.'),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
