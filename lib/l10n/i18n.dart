// ============================================================================
// i18n.dart — Idioma do app (português, inglês e espanhol)
//
// O que faz: [tr] devolve o texto no idioma escolhido. A chave é o próprio
//   texto em português (fica legível no código); a tradução vem de
//   [enStrings] (en.dart) ou [esStrings] (es.dart, 17/11). Partes variáveis vão como {0}, {1}...:
//   tr('Rota até {0}', [nome]).
// Quem usa: todas as telas e as falas da voz.
// Onde mexer: texto novo em português → inclua a tradução em en.dart (sem
//   ela, aparece em português mesmo no inglês). Escolha do idioma em
//   AppSettings.language (Configurações → Idioma).
// ============================================================================

import 'package:flutter/foundation.dart';

import 'en.dart';
import 'es.dart';

class I18n {
  I18n._();

  /// Idioma em uso: 'pt', 'en' ou 'es'.
  static final lang = ValueNotifier<String>('pt');

  static bool get isEn => lang.value == 'en';
  static bool get isEs => lang.value == 'es';

  /// Idioma da voz (TTS e reconhecimento do Android).
  static String get ttsLang => isEn ? 'en-US' : (isEs ? 'es-US' : 'pt-BR');

  /// Idioma pedido ao Google (rotas, lugares).
  static String get apiLang => isEn ? 'en' : (isEs ? 'es' : 'pt-BR');

  /// Código curto enviado às funções do servidor ('pt', 'en', 'es').
  static String get code => lang.value;
}

/// Texto no idioma do app. [pt] é o texto em português (a chave).
String tr(String pt, [List<Object?> args = const []]) {
  final l = I18n.lang.value;
  // Sem tradução: fica o português (no espanhol, mais perto que o inglês).
  var s = l == 'en' ? (enStrings[pt] ?? pt) : (l == 'es' ? (esStrings[pt] ?? pt) : pt);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
