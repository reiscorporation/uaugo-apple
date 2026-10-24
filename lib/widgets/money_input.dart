// ============================================================================
// money_input.dart — Campo de valor em reais com centavos automáticos
//
// O que faz: Ao digitar só números, já põe a vírgula dos centavos: 1 → 0,01;
//   1240 → 12,40 (em inglês, 12.40). Lido com parseDecimal (costs.dart).
// Quem usa: preço do litro (Meu veículo), gastos da viagem e o valor do
//   pedágio informado pelo piloto.
// ============================================================================

import 'package:flutter/services.dart';

import '../l10n/i18n.dart';

class MoneyInputFormatter extends TextInputFormatter {
  /// Valor guardado no campo para [v] (ex.: 12.4 → "12,40").
  static String format(double v) => _fmt((v * 100).round());

  static String _fmt(int cents) {
    final sep = I18n.isEn ? '.' : ',';
    final s = cents.toString().padLeft(3, '0');
    return '${int.parse(s.substring(0, s.length - 2))}$sep${s.substring(s.length - 2)}';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    // Até R$ 99.999,99 (evita número gigante por engano).
    final cents = int.parse(digits.length > 7 ? digits.substring(digits.length - 7) : digits);
    final text = _fmt(cents);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
