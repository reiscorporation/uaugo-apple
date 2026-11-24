// ============================================================================
// trip_launcher.dart — Abrir a viagem escolhida na prévia da rota
//
// O que faz: Depois da prévia (TripPreviewSheet), abre o mapa conforme o
//   botão tocado: Iniciar, Simular ou COMPARTILHAR VIAGEM (23/11).
//   Compartilhar transforma a rota numa expedição com código próprio
//   (ExpeditionService.createFromTrip), mostra SÓ o código por 10 segundos
//   (com o botão de copiar, que copia só o código) e abre a navegação da
//   expedição. O código continua valendo depois que some da tela, até a
//   expedição ser encerrada. Quem recebe entra em "Entrar com código", na
//   tela inicial, como em qualquer expedição.
// Quem usa: HomeScreen e HistoryScreen (um lugar só para os três botões).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/i18n.dart';
import '../models/trip.dart';
import '../services/expedition_service.dart';
import '../widgets/trip_preview_sheet.dart';
import 'login_screen.dart' show requireAccount;
import 'map_screen.dart';

/// Abre o mapa para o resultado da prévia da rota.
Future<void> launchTrip(
  BuildContext context, {
  required String uid,
  required String userName,
  required (TripAction, Trip) res,
}) async {
  final (action, trip) = res;
  if (action == TripAction.share) {
    final code = await shareTripCode(context, trip: trip, uid: uid, userName: userName);
    if (code == null || !context.mounted) return;
    // "Voltar para a expedição" na tela inicial, como nas outras.
    (await SharedPreferences.getInstance()).setString('lastCode', code);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MapScreen(
          code: code, uid: uid, userName: userName, startNavigation: true),
    ));
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MapScreen(
      uid: uid,
      userName: userName,
      trip: trip,
      simulate: action == TripAction.simulate,
    ),
  ));
}

/// Cria a expedição da viagem e mostra o código por 10 s. null = cancelado
/// ou falhou (sem conta, sem internet).
Future<String?> shareTripCode(
  BuildContext context, {
  required Trip trip,
  required String uid,
  required String userName,
}) async {
  if (!await requireAccount(context,
      tr('Para compartilhar a viagem, entre com sua conta. Quem receber o código também precisa de conta.'))) {
    return null;
  }
  if (!context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  // Aguarde: criando o código (precisa de internet).
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(tr('Criando o código da viagem...'))),
        ]),
      ),
    ),
  );
  String? code;
  try {
    code = await ExpeditionService.instance
        .createFromTrip(trip: trip, uid: uid, userName: userName)
        .timeout(const Duration(seconds: 25));
  } catch (e) {
    debugPrint('Compartilhar viagem: $e');
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (code == null) {
    messenger.showSnackBar(SnackBar(
        content: Text(tr('Não foi possível criar o código. Confira a internet e tente de novo.'))));
    return null;
  }
  if (!context.mounted) return code;
  await showDialog<void>(
    context: context,
    builder: (_) => _CodeDialog(code: code!),
  );
  return code;
}

/// O código, grande e limpo, por 10 segundos (some sozinho).
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.code});
  final String code;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  static const _seconds = 10;
  int _left = _seconds;
  Timer? _t;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        Navigator.of(context).pop();
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    // Só o código, sem frase nem link.
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Código da viagem')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: _copy,
            child: SelectableText(
              widget.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _left / _seconds),
          const SizedBox(height: 6),
          Text(tr('Some da tela em {0} s. O código continua valendo.', [_left]),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          FilledButton.icon(
            onPressed: _copy,
            icon: Icon(_copied ? Icons.check : Icons.copy),
            label: Text(_copied ? tr('Copiado') : tr('Copiar')),
          ),
        ],
      );
}
