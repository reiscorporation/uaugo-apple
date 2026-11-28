// ============================================================================
// login_screen.dart — Entrar / criar conta
//
// O que faz: Login com Google, Apple (iPhone) ou e-mail e senha (criar conta,
//   já tenho conta, esqueci a senha). A conta anônima do aparelho é vinculada
//   (nada se perde). Fecha devolvendo true quando a pessoa entrou.
// Quem usa: requireAccount (ações que exigem conta) e Configurações → Conta.
// Onde mexer: Regras de senha: _validPassword. Textos de erro:
//   AuthService.friendlyError.
// ============================================================================

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../l10n/i18n.dart';

/// Exige uma conta (não anônima) antes de uma ação: se precisar, abre a tela
/// de login explicando o motivo. Devolve true se puder continuar.
Future<bool> requireAccount(BuildContext context, String reason) async {
  if (!AuthService.isAnonymous) return true;
  final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(reason: reason)));
  return ok == true && !AuthService.isAnonymous;
}

/// Tela de login. [reason] explica por que a conta é pedida agora.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.reason});
  final String? reason;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Estado: modo (criar conta x já tenho conta), campos e "carregando".
class _LoginScreenState extends State<LoginScreen> {
  bool _haveAccount = false;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// Senha forte o bastante: 8+ caracteres, com letra e número.
  static bool _validPassword(String p) =>
      p.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(p) &&
      RegExp(r'\d').hasMatch(p);

  /// Executa uma forma de login; fecha a tela se der certo.
  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      // Apple com "Ocultar meu e-mail" e sem nome (a Apple só manda o nome
      // na 1ª vez): pergunta como mostrar o nome em vez do código do e-mail.
      if (AuthService.missingName) {
        await editAccountName(context, afterLogin: true);
        if (!mounted) return;
      }
      if (done != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Botão principal do formulário de e-mail.
  void _submitEmail() {
    final email = _email.text.trim();
    final pass = _password.text;
    if (!email.contains('@')) {
      setState(() => _error = tr('Digite um e-mail válido.'));
      return;
    }
    if (_haveAccount) {
      _run(() => AuthService.signInWithEmail(email, pass));
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = tr('Digite seu nome.'));
      return;
    }
    if (!_validPassword(pass)) {
      setState(() => _error =
          tr('A senha precisa ter pelo menos 8 caracteres, com letras e números.'));
      return;
    }
    _run(() => AuthService.registerWithEmail(_name.text, email, pass),
        done: tr('Conta criada! Enviamos um e-mail para confirmar o endereço.'));
  }

  /// "Esqueci a senha": envia o link para o e-mail digitado.
  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = tr('Digite seu e-mail acima e toque de novo.'));
      return;
    }
    try {
      await AuthService.resetPassword(email);
      if (mounted) {
        setState(() => _error = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Enviamos um link para criar uma nova senha.'))));
      }
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Entrar'))),
      body: SafeArea(
        top: false,
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (widget.reason != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.reason!)),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: () => _run(AuthService.signInWithGoogle),
              icon: const Icon(Icons.g_mobiledata, size: 32),
              label: Text(tr('Continuar com Google')),
            ),
            if (AuthService.appleAvailable) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white),
                onPressed: () => _run(AuthService.signInWithApple),
                icon: const Icon(Icons.apple),
                label: Text(tr('Continuar com Apple')),
              ),
            ],
            const SizedBox(height: 20),
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(tr('ou com e-mail'), style: theme.textTheme.bodySmall),
              ),
              const Expanded(child: Divider()),
            ]),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('Criar conta'))),
                ButtonSegment(value: true, label: Text(tr('Já tenho conta'))),
              ],
              selected: {_haveAccount},
              onSelectionChanged: (s) => setState(() {
                _haveAccount = s.first;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            if (!_haveAccount) ...[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                    labelText: tr('Nome'), border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'E-mail', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: tr('Senha'),
                helperText:
                    _haveAccount ? null : tr('Mínimo 8 caracteres, letras e números'),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => _submitEmail(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: _submitEmail,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_haveAccount ? tr('Entrar') : tr('Criar conta')),
            ),
            if (_haveAccount)
              TextButton(
                onPressed: _forgot,
                child: Text(tr('Esqueci a senha')),
              ),
            const SizedBox(height: 16),
            Text(
              tr('Sua conta guarda seu perfil e permite usar o app em outro celular. O que você já fez neste aparelho continua valendo.'),
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }
}

/// Pede o nome da conta (Configurações → Minha conta, ou logo depois de
/// entrar com Apple sem nome). Pode deixar para depois.
Future<void> editAccountName(BuildContext context, {bool afterLogin = false}) async {
  final ctrl = TextEditingController(
      text: AuthService.missingName ? '' : AuthService.displayName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(afterLogin ? tr('Como quer ser chamado?') : tr('Seu nome')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        maxLength: 40,
        decoration: InputDecoration(hintText: tr('Nome ou apelido')),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(afterLogin ? tr('Depois') : tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
          child: Text(tr('Salvar')),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (name == null || name.trim().isEmpty) return;
  try {
    await AuthService.setName(name);
  } catch (_) {}
}
