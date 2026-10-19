// ============================================================================
// analytics_service.dart — Estatísticas de uso e relatório de erros
//
// O que faz: Conta, de forma anônima, quantas pessoas usam o app (por dia,
//   semana e mês), quais recursos usam (rota, Só dirigir, expedição, alerta,
//   voz) e registra travamentos e erros com o modelo do celular e a versão
//   (Firebase Analytics + Crashlytics). Nada de localização exata, nome ou
//   e-mail.
// Quem usa: main.dart (inicia e captura erros), HomeScreen e MapScreen
//   (eventos), Configurações ("Compartilhar estatísticas de uso").
// Onde mexer: nomes dos eventos: [AnalyticsService.event] (até 40 letras,
//   sem acento).
// ============================================================================

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Estatísticas anônimas de uso e erros (pode ser desligado pelo usuário).
class AnalyticsService {
  AnalyticsService._();

  static bool _on = true;

  /// Liga/desliga a coleta (Configurações). Em modo debug, os erros não vão
  /// para o painel (evita misturar testes com o uso real).
  static Future<void> setEnabled(bool on) async {
    _on = on;
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(on);
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(on && !kDebugMode);
    } catch (e) {
      debugPrint('Estatísticas indisponíveis: $e');
    }
  }

  /// Um uso de recurso: "route_start", "just_drive", "expedition_create"...
  static void event(String name, [Map<String, Object>? params]) {
    if (!_on) return;
    FirebaseAnalytics.instance
        .logEvent(name: name, parameters: params)
        .catchError((_) {});
  }

  /// Erro que não derrubou o app, mas vale registrar.
  static void error(Object e, StackTrace? st, {String? reason}) {
    if (!_on || kDebugMode) return;
    FirebaseCrashlytics.instance
        .recordError(e, st, reason: reason)
        .catchError((_) {});
  }
}
