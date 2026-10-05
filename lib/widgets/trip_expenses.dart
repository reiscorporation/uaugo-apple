// ============================================================================
// trip_expenses.dart — Gastos da viagem
//
// O que faz: Combustível estimado, gastos registrados (abastecimento, pedágio,
//   alimentação...), total, valor por pessoa e consumo real.
// Quem usa: HistoryScreen (detalhe da viagem).
// Onde mexer: Cálculos: logic/costs.dart.
// ============================================================================

import 'package:flutter/material.dart';

import '../logic/costs.dart';
import '../models/trip_record.dart';
import '../services/app_settings.dart';
import '../services/history_service.dart';

/// Gastos de uma viagem de "Minhas viagens": estimativa de combustível,
/// gastos registrados, total (e por pessoa, na expedição) e consumo real.
class TripExpensesCard extends StatelessWidget {
  const TripExpensesCard({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<TripRecord>>(
      valueListenable: HistoryService.instance.trips,
      builder: (context, trips, _) {
        final t = trips.where((x) => x.id == tripId).firstOrNull;
        if (t == null) return const SizedBox.shrink();
        final fuel = AppSettings.instance.fuel.value;
        final theme = Theme.of(context);
        final total = totalOf(t.expenses);
        final real = realKmPerLiter(t.distanceM, t.expenses);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Gastos da viagem', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _add(context, t),
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar'),
                  ),
                ]),
                if (fuel.ready)
                  Text(
                      '⛽ Estimado: ${formatDecimal(fuelLiters(t.distanceM, fuel.kmPerLiter))} L'
                      ' · ${formatMoney(fuelCost(t.distanceM, fuel.kmPerLiter, fuel.pricePerLiter))}'
                      ' (${formatDecimal(fuel.kmPerLiter)} km/l)'),
                if (real != null)
                  Text('📊 Consumo real: ${formatDecimal(real)} km/l',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final e in t.expenses)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(e.kind.emoji,
                        style: const TextStyle(fontSize: 22)),
                    title: Text([
                      e.kind.label,
                      if (e.liters != null) '${formatDecimal(e.liters!)} L',
                      if (e.note.isNotEmpty) e.note,
                    ].join(' · ')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(formatMoney(e.value)),
                      IconButton(
                        tooltip: 'Remover',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => HistoryService.instance.save(t.copyWith(
                            expenses: [...t.expenses]..remove(e))),
                      ),
                    ]),
                  ),
                if (t.expenses.isNotEmpty) ...[
                  const Divider(),
                  Text('Total: ${formatMoney(total)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  if (t.expedition && t.riders > 1)
                    Text('Por pessoa (${t.riders} pilotos): '
                        '${formatMoney(total / t.riders)}'),
                ],
                if (t.expenses.isEmpty && !fuel.ready)
                  const Text(
                      'Registre abastecimentos, pedágios e outros gastos. Para '
                      'a estimativa de combustível, preencha o consumo em '
                      '"Minha moto / Meu carro".',
                      style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Janela para registrar um gasto (tipo, valor, litros, observação).
  Future<void> _add(BuildContext context, TripRecord t) async {
    var kind = ExpenseKind.fuel;
    final value = TextEditingController();
    final liters = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Registrar gasto'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in ExpenseKind.values)
                  ChoiceChip(
                    label: Text('${k.emoji} ${k.label}'),
                    selected: kind == k,
                    onSelected: (_) => set(() => kind = k),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: value,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Valor', prefixText: 'R\$ '),
              ),
              if (kind == ExpenseKind.fuel)
                TextField(
                  controller: liters,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Litros (para o consumo real)',
                      suffixText: 'L'),
                ),
              TextField(
                controller: note,
                decoration:
                    const InputDecoration(labelText: 'Observação (opcional)'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final v = parseDecimal(value.text);
    if (ok != true || v == null || v <= 0) return;
    final l = kind == ExpenseKind.fuel ? parseDecimal(liters.text) : null;
    await HistoryService.instance.save(t.copyWith(expenses: [
      ...t.expenses,
      Expense(
        kind: kind,
        value: v,
        liters: (l ?? 0) > 0 ? l : null,
        note: note.text.trim(),
        at: DateTime.now(),
      ),
    ]));
  }
}
