import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:comboio/l10n/en.dart';
import 'package:comboio/l10n/i18n.dart';
import 'package:comboio/logic/costs.dart';
import 'package:comboio/logic/speech.dart';

void main() {
  tearDown(() => I18n.lang.value = 'pt');

  test('português por padrão, inglês ao trocar, com partes variáveis', () {
    expect(tr('Rota até {0}', ['Campinas']), 'Rota até Campinas');
    I18n.lang.value = 'en';
    expect(tr('Rota até {0}', ['Campinas']), 'Route to Campinas');
    expect(tr('texto sem tradução'), 'texto sem tradução');
  });

  test('voz e dinheiro no idioma', () {
    expect(spokenDistance(400), '400 metros');
    expect(formatMoney(1234.5), r'R$ 1.234,50');
    I18n.lang.value = 'en';
    expect(spokenDistance(400), '400 meters');
    expect(spokenDistance(3000), '3 kilometers');
    expect(formatMoney(1234.5), r'R$ 1,234.50');
  });

  // Todo texto novo com tr('...') precisa de tradução em lib/l10n/en_*.dart.
  test('todo tr() do app tem tradução para o inglês', () {
    const same = {
      'Ricardo Reis', 'Google Maps Platform', 'Versys 650', 'UauGo · HelpAITech',
    };
    final pat = RegExp(r"\btr\(\s*'((?:[^'\\]|\\.)*)'");
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart') || f.path.contains('l10n')) {
        continue;
      }
      for (final m in pat.allMatches(f.readAsStringSync())) {
        // Desfaz os escapes do código-fonte (\n, \', \$).
        final key = m.group(1)!
            .replaceAll(r'\n', '\n')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\$', r'$')
            .replaceAll(r'\"', '"');
        if (!enStrings.containsKey(key) && !same.contains(key)) {
          missing.add('${f.path}: $key');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
