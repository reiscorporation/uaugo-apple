import '../l10n/i18n.dart';
import '../services/app_settings.dart' show FuelPrefs, EnergyType;
// Consumo e gastos de viagem (funções puras, testáveis).

/// Tipos de gasto registrados numa viagem.
enum ExpenseKind {
  fuel('Combustível', '⛽'),
  toll('Pedágio', '🛣️'),
  food('Alimentação', '🍽️'),
  lodging('Hospedagem', '🏨'),
  other('Outros', '🧾');

  const ExpenseKind(this._label, this.emoji);
  final String _label;
  String get label => tr(_label);
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

/// Energia prevista para a viagem conforme o tipo do veículo (12/11).
/// PHEV: elétrico até a autonomia da bateria, combustível no resto.
({double liters, double kwh, double cost}) tripEnergy(double meters, FuelPrefs f) {
  final km = meters / 1000;
  double liters = 0, kwh = 0;
  switch (f.energy) {
    case EnergyType.combustion:
    case EnergyType.hybrid:
      liters = f.kmPerLiter > 0 ? km / f.kmPerLiter : 0;
    case EnergyType.electric:
      kwh = f.kmPerKwh > 0 ? km / f.kmPerKwh : 0;
    case EnergyType.phev:
      final ev = km < f.evRangeKm ? km : f.evRangeKm;
      kwh = f.kmPerKwh > 0 ? ev / f.kmPerKwh : 0;
      liters = f.kmPerLiter > 0 ? (km - ev) / f.kmPerLiter : 0;
  }
  return (liters: liters, kwh: kwh, cost: liters * f.pricePerLiter + kwh * f.pricePerKwh);
}

/// Frase da energia prevista ("⛽ ~12 L · R\$ 70" / "⚡ ~30 kWh · R\$ 24").
String tripEnergyText(double meters, FuelPrefs f, String Function(double) decimal) {
  final e = tripEnergy(meters, f);
  final parts = <String>[
    if (e.liters > 0.05) tr('~{0} L de combustível', [decimal(e.liters)]),
    if (e.kwh > 0.05) tr('~{0} kWh', [decimal(e.kwh)]),
  ];
  final icon = e.kwh > 0.05 && e.liters <= 0.05 ? '⚡' : (e.kwh > 0.05 ? '⛽⚡' : '⛽');
  return '$icon ${parts.join(' + ')} · ${formatMoney(e.cost)}';
}

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
  // Inglês: "R\$ 1,234.50" (a moeda continua o real).
  final (thou, dec) = I18n.isEn ? (',', '.') : ('.', ',');
  for (var i = 0; i < reais.length; i++) {
    if (i > 0 && (reais.length - i) % 3 == 0) buf.write(thou);
    buf.write(reais[i]);
  }
  return 'R\$ $buf$dec${(cents % 100).toString().padLeft(2, '0')}';
}

/// "12,5"
String formatDecimal(double v, [int digits = 1]) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

/// Lê "12,5" ou "12.5" (null se inválido).
double? parseDecimal(String s) =>
    double.tryParse(s.trim().replaceAll('R\$', '').replaceAll(' ', '').replaceAll(',', '.'));
