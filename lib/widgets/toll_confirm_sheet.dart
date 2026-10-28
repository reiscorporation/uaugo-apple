// ============================================================================
// toll_confirm_sheet.dart — Confirmar ou corrigir o valor dos pedágios
//
// O que faz: Lista as praças da rota com o valor de carro e moto e de onde
//   ele veio (oficial da ANTT, a confirmar, confirmado por pilotos). Nas que
//   não são oficiais, o piloto toca em "Está certo" ou "Corrigir"; o valor
//   vale para todos quando 2 pilotos informarem valores parecidos.
// Quem usa: TripPreviewSheet e PlanScreen (botão abaixo dos pedágios).
// Onde mexer: Regra de confirmação em functions/index.js (onTollReport).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/i18n.dart';
import '../logic/costs.dart' show formatMoney;
import '../logic/tolls.dart';
import '../services/auth_service.dart';
import '../services/toll_service.dart';
import 'money_input.dart';

class TollConfirmSheet extends StatefulWidget {
  const TollConfirmSheet({super.key, required this.plazas});

  /// Praças da rota, na ordem do caminho.
  final List<TollPlaza> plazas;

  static Future<void> show(BuildContext context, List<TollPlaza> plazas) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => TollConfirmSheet(plazas: plazas),
      );

  @override
  State<TollConfirmSheet> createState() => _TollConfirmSheetState();
}

class _TollConfirmSheetState extends State<TollConfirmSheet> {
  static const _kSent = 'tollReported';

  /// Praças que este piloto já confirmou/corrigiu (só no celular).
  Set<String> _sent = {};

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _sent = (p.getStringList(_kSent) ?? []).toSet());
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send(TollPlaza p, double? car, double? moto) async {
    if (AuthService.isAnonymous) {
      _snack(tr('Para confirmar valores, entre com sua conta.'));
      return;
    }
    try {
      await TollService.instance.report(p.key, car: car, moto: moto);
      _sent.add(p.key);
      (await SharedPreferences.getInstance()).setStringList(_kSent, _sent.toList());
      if (!mounted) return;
      setState(() {});
      _snack(tr('Obrigado! O valor vale para todos quando outro piloto confirmar.'));
    } catch (e) {
      _snack(tr('Não foi possível enviar: {0}', [e]));
    }
  }

  Future<void> _correct(TollPlaza p) async {
    String fmt(double? v) => v == null ? '' : MoneyInputFormatter.format(v);
    final (car0, moto0) = _values(p);
    final carCtl = TextEditingController(text: fmt(car0));
    final motoCtl = TextEditingController(text: fmt(moto0));
    double? parse(String s) {
      final t = s.trim().replaceAll(',', '.');
      return t.isEmpty ? null : double.tryParse(t);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Valor do pedágio')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: carCtl,
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            decoration: InputDecoration(labelText: tr('Carro (R\$)'), hintText: '12,40'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: motoCtl,
            keyboardType: TextInputType.number,
            inputFormatters: [MoneyInputFormatter()],
            decoration: InputDecoration(
                labelText: tr('Moto (R\$)'),
                helperText: tr('0 se a moto for isenta; vazio se não souber')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enviar'))),
        ],
      ),
    );
    if (ok != true) return;
    final car = parse(carCtl.text), moto = parse(motoCtl.text);
    if ((car == null && moto == null) || (car ?? 0) >= 500 || (moto ?? 0) >= 500) {
      _snack(tr('Informe um valor válido.'));
      return;
    }
    await _send(p, car, moto);
  }

  /// Valor informado agora por este piloto (se houver) ou o da tabela.
  (double?, double?) _values(TollPlaza p) =>
      TollService.instance.mine[p.key] ?? (p.car, p.motoValue);

  String _moto(TollPlaza p) {
    final m = _values(p).$2;
    if (m == 0) return tr('moto isenta');
    if (m == null) return tr('moto: não informado');
    return tr('moto {0}', [formatMoney(m)]);
  }

  Widget _status(TollPlaza p) {
    final (label, color) = switch (p.source) {
      _ when p.car == null => (tr('sem valor'), Colors.red.shade700),
      TollSource.official => (tr('oficial (ANTT)'), Colors.green.shade700),
      TollSource.users => (tr('confirmado por pilotos'), Colors.green.shade700),
      TollSource.estimated => (tr('a confirmar'), Colors.orange.shade800),
    };
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12));
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.plazas;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          Text(tr('Pedágios da rota'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(tr('Passou por uma praça? Confirme ou corrija o valor. Ele passa a valer para todos quando 2 pilotos informarem o mesmo.'),
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (var i = 0; i < list.length; i++)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                          list[i].name.isNotEmpty ? list[i].name : tr('Praça {0}', [i + 1]),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    _status(list[i]),
                  ]),
                  const SizedBox(height: 4),
                  Text(_values(list[i]).$1 == null
                      ? tr('Valor não informado')
                      : '${tr('carro {0}', [formatMoney(_values(list[i]).$1!)])} · ${_moto(list[i])}'),
                  // "Corrigir" fica sempre disponível, mesmo em valor já
                  // confirmado ou já informado por você: se alguém errou,
                  // dá para consertar.
                  if (list[i].editable)
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      if (_sent.contains(list[i].key))
                        Expanded(
                          child: Text(tr('✓ Você já informou esta praça'),
                              style: TextStyle(color: Colors.green.shade700)),
                        )
                      else if (list[i].car != null)
                        TextButton.icon(
                          icon: const Icon(Icons.check),
                          label: Text(tr('Está certo')),
                          onPressed: () => _send(list[i], list[i].car, list[i].motoValue),
                        ),
                      TextButton.icon(
                        icon: const Icon(Icons.edit),
                        label: Text(list[i].car == null ? tr('Informar valor') : tr('Corrigir')),
                        onPressed: () => _correct(list[i]),
                      ),
                    ]),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
