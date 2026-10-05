// Consumo e gastos de viagem (funções puras, testáveis).

/// Tipos de gasto registrados numa viagem.
enum ExpenseKind {
  fuel('Combustível', '⛽'),
  toll('Pedágio', '🛣️'),
  food('Alimentação', '🍽️'),
  lodging('Hospedagem', '🏨'),
  other('Outros', '🧾');

  const ExpenseKind(this.label, this.emoji);
  final String label;
  final String emoji;

  /// Lê o tipo salvo pelo nome (desconhecido = "Outros").
  static ExpenseKind fromName(String? n) => ExpenseKind.values
      .firstWhere((k) => k.name == n, orElse: () => ExpenseKind.other);
}

/// Um gasto registrado na viagem (valor em reais; litros só no combustível).
class Expense {
  final ExpenseKind kind;
  final double value; // R$
  final double? liters; // só para combustível
  final String note;
  final DateTime at;

  const Expense({
    required this.kind,
    required this.value,
    this.liters,
    this.note = '',
    required this.at,
  });

  /// Formato compacto para o arquivo do histórico (chaves curtas).
  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'v': value,
        if (liters != null) 'l': liters,
        if (note.isNotEmpty) 'n': note,
        't': at.millisecondsSinceEpoch,
      };

  /// Lê um gasto salvo; null se o registro estiver corrompido.
  static Expense? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return Expense(
        kind: ExpenseKind.fromName(j['k'] as String?),
        value: (j['v'] as num).toDouble(),
        liters: (j['l'] as num?)?.toDouble(),
        note: (j['n'] ?? '') as String,
        at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Litros previstos para [meters] com consumo de [kmPerLiter].
double fuelLiters(double meters, double kmPerLiter) =>
    kmPerLiter <= 0 ? 0 : meters / 1000 / kmPerLiter;

/// Custo previsto de combustível.
double fuelCost(double meters, double kmPerLiter, double pricePerLiter) =>
    fuelLiters(meters, kmPerLiter) * pricePerLiter;

/// Consumo real (km/l) pelos abastecimentos registrados, ou null.
double? realKmPerLiter(double meters, List<Expense> expenses) {
  final liters = expenses
      .where((e) => e.kind == ExpenseKind.fuel && (e.liters ?? 0) > 0)
      .fold<double>(0, (a, e) => a + e.liters!);
  if (liters <= 0 || meters <= 0) return null;
  return meters / 1000 / liters;
}

/// Soma dos valores de todos os gastos.
double totalOf(List<Expense> expenses) =>
    expenses.fold<double>(0, (a, e) => a + e.value);

/// "R$ 1.234,50"
String formatMoney(double v) {
  final cents = (v * 100).round();
  final reais = (cents ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buf.write('.');
    buf.write(reais[i]);
  }
  return 'R\$ $buf,${(cents % 100).toString().padLeft(2, '0')}';
}

/// "12,5"
String formatDecimal(double v, [int digits = 1]) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

/// Lê "12,5" ou "12.5" (null se inválido).
double? parseDecimal(String s) =>
    double.tryParse(s.trim().replaceAll('R\$', '').replaceAll(' ', '').replaceAll(',', '.'));
