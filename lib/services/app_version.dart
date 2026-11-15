// ============================================================================
// app_version.dart — Versão do app instalado
//
// O que faz: Lê a versão do próprio app (a do pubspec.yaml no build, ex.
//   "1.2.9 (41)"). Nunca escrever a versão à mão em tela nenhuma: a Sobre
//   mostrava "1.0.0" fixo na 1.2.9 (14/11).
// Quem usa: Sobre e o rodapé da Home.
// ============================================================================

import 'package:package_info_plus/package_info_plus.dart';

class AppVersion {
  static Future<String>? _label;

  /// "1.2.9 (41)": versão e número do build publicados.
  static Future<String> label() => _label ??= PackageInfo.fromPlatform()
      .then((p) => p.buildNumber.isEmpty ? p.version : '${p.version} (${p.buildNumber})')
      .catchError((_) => '');
}
