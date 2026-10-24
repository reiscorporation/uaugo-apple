// ============================================================================
// i18n.dart — Idioma do app (português e inglês)
//
// O que faz: [tr] devolve o texto no idioma escolhido. A chave é o próprio
//   texto em português (fica legível no código); a tradução vem de
//   [enStrings] (en.dart). Partes variáveis vão como {0}, {1}...:
//   tr('Rota até {0}', [nome]).
// Quem usa: todas as telas e as falas da voz.
// Onde mexer: texto novo em português → inclua a tradução em en.dart (sem
//   ela, aparece em português mesmo no inglês). Escolha do idioma em
//   AppSettings.language (Configurações → Idioma).
// ============================================================================

import 'package:flutter/foundation.dart';

import 'en.dart';

class I18n {
  I18n._();

  /// Idioma em uso: 'pt' ou 'en'.
  static final lang = ValueNotifier<String>('pt');

  static bool get isEn => lang.value == 'en';

  /// Idioma da voz (TTS e reconhecimento do Android).
  static String get ttsLang => isEn ? 'en-US' : 'pt-BR';

  /// Idioma pedido ao Google (rotas, lugares).
  static String get apiLang => isEn ? 'en' : 'pt-BR';
}

/// Texto no idioma do app. [pt] é o texto em português (a chave).
String tr(String pt, [List<Object?> args = const []]) {
  var s = I18n.lang.value == 'en' ? (enStrings[pt] ?? pt) : pt;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
