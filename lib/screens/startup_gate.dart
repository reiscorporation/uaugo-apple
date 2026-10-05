// ============================================================================
// startup_gate.dart — Porta de entrada
//
// O que faz: Decide a primeira tela: autorizações (se ainda não aceitas) ou a
//   tela inicial.
// Quem usa: main.dart.
// ============================================================================

import 'package:flutter/material.dart';

import '../services/user_service.dart';
import 'consent_screen.dart';
import 'home_screen.dart';
import 'terms_screen.dart';

/// No primeiro uso (cadastro), exige a tela de autorizações antes de tudo.
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

/// Lê os aceites e escolhe a primeira tela: Termos de Uso (versão vigente)
/// → autorizações (LGPD) → tela inicial.
class _StartupGateState extends State<StartupGate> {
  bool? _accepted;
  bool? _terms;

  @override
  void initState() {
    super.initState();
    TermsService.accepted().then((t) {
      if (mounted) setState(() => _terms = t);
    });
    UserService.loadConsents().then((c) {
      if (mounted) setState(() => _accepted = c?.isValid ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_accepted == null || _terms == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_terms == false) {
      return TermsScreen(onAccept: () => setState(() => _terms = true));
    }
    if (_accepted == false) {
      return ConsentScreen(
        firstTime: true,
        onDone: () => setState(() => _accepted = true),
      );
    }
    return const HomeScreen();
  }
}
