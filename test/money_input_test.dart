import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comboio/l10n/i18n.dart';
import 'package:comboio/logic/costs.dart';
import 'package:comboio/widgets/money_input.dart';

void main() {
  tearDown(() => I18n.lang.value = 'pt');
  String type(String s) => MoneyInputFormatter()
      .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s))
      .text;

  test('centavos automáticos ao digitar', () {
    expect(type('1'), '0,01');
    expect(type('12'), '0,12');
    expect(type('1240'), '12,40');
    expect(type('00629'), '6,29');
    expect(type(''), '');
    expect(parseDecimal(type('1240')), 12.4);
  });

  test('inglês usa ponto', () {
    I18n.lang.value = 'en';
    expect(type('1240'), '12.40');
    expect(MoneyInputFormatter.format(6.29), '6.29');
  });
}
