// ============================================================================
// terms_screen.dart — Termos de Uso
//
// O que faz: Mostra os Termos de Uso (assets/legal/termos_de_uso.md) e, no
//   primeiro uso ou quando a versão muda, exige "Li e aceito" antes de usar o
//   app. O aceite (versão, data e hora) fica no celular e em users/{uid}.terms
//   no Firestore, como registro.
// Quem usa: StartupGate (aceite obrigatório) e Configurações → Sobre (leitura).
// Onde mexer: Texto: assets/legal/termos_de_uso.md. Ao mudar algo relevante,
//   aumente [TermsService.version] para todos aceitarem de novo.
// ============================================================================

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

/// Versão vigente dos Termos e o registro do aceite.
class TermsService {
  /// Aumente quando os Termos mudarem de forma relevante: todos os usuários
  /// terão de ler e aceitar de novo.
  static const version = '1.3';
  static const _key = 'termsAcceptedVersion';

  /// O usuário já aceitou a versão vigente?
  static Future<bool> accepted() async =>
      (await SharedPreferences.getInstance()).getString(_key) == version;

  /// Registra o aceite no celular e no Firestore (users/{uid}.terms), com a
  /// prova do aceite: versão dos Termos, data/hora do SERVIDOR (o usuário não
  /// consegue alterar), versão do app, sistema do celular, conta (e-mail,
  /// quando houver) e como foi aceito. Se não houver internet, o Firestore
  /// envia quando a conexão voltar.
  ///
  /// [method] descreve como foi aceito (padrão: na tela dos Termos).
  static Future<void> accept({
    String method =
        'leu até o fim + marcou "Li e aceito" + tocou em Continuar',
  }) async {
    await (await SharedPreferences.getInstance()).setString(_key, version);
    try {
      final uid = await AuthService.ensureSignedIn();
      final app = await PackageInfo.fromPlatform();
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'terms': {
          'version': version,
          'acceptedAt': FieldValue.serverTimestamp(),
          'appVersion': '${app.version}+${app.buildNumber}',
          'platform': Platform.operatingSystem,
          'osVersion': Platform.operatingSystemVersion,
          'account': AuthService.isAnonymous ? 'anônima' : AuthService.email,
          'method': method,
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // Sem conexão no primeiro uso: o aceite fica no celular e é enviado
      // de novo no próximo aceite/abertura (ver StartupGate).
    }
  }

  /// A conta anônima virou conta de verdade (mesmo uid): acrescenta o e-mail
  /// ao registro do aceite, mantendo a data e a forma do aceite original.
  static Future<void> attachAccount() async {
    try {
      final uid = await AuthService.ensureSignedIn();
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'terms': {
          'account': AuthService.email,
          'accountLinkedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}

/// Tela dos Termos. Com [onAccept], mostra a caixa "Li e aceito" e o botão
/// de continuar (primeiro uso); sem, é só leitura.
///
/// Também mostra outros documentos legais: `TermsScreen.privacy()` abre a
/// Política de Privacidade (só leitura).
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key, this.onAccept})
      : asset = 'assets/legal/termos_de_uso.md',
        title = 'Termos de Uso';

  /// Política de Privacidade (só leitura).
  const TermsScreen.privacy({super.key})
      : onAccept = null,
        asset = 'assets/legal/politica_de_privacidade.md',
        title = 'Política de Privacidade';

  final VoidCallback? onAccept;
  final String asset;
  final String title;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

/// Carrega o texto; no aceite, só libera a caixa depois de rolar até o fim.
class _TermsScreenState extends State<TermsScreen> {
  String? _text;
  bool _checked = false;
  bool _saving = false;

  /// Rolou o texto até o fim? (prova de que o texto foi percorrido)
  bool _readToEnd = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    rootBundle.loadString(widget.asset).then((t) {
      if (mounted) setState(() => _text = t);
      // Tela grande em que o texto cabe inteiro: já conta como lido.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    });
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (_readToEnd || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 40) setState(() => _readToEnd = true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _saving = true);
    await TermsService.accept();
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onAccept?.call();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    final mustAccept = widget.onAccept != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        automaticallyImplyLeading: !mustAccept,
      ),
      body: SafeArea(
        top: false,
        child: text == null
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: _render(context, text),
                  ),
                ),
                if (mustAccept)
                  Material(
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const TermsScreen.privacy())),
                            icon: const Icon(Icons.privacy_tip_outlined),
                            label: const Text('Ler a Política de Privacidade'),
                          ),
                        ),
                        if (!_readToEnd)
                          const Padding(
                            padding: EdgeInsets.only(left: 12, bottom: 4),
                            child: Row(children: [
                              Icon(Icons.arrow_downward, size: 18),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                    'Role o texto até o fim para poder aceitar.'),
                              ),
                            ]),
                          ),
                        CheckboxListTile(
                          value: _checked,
                          enabled: _readToEnd,
                          onChanged: (v) =>
                              setState(() => _checked = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                              'Li e aceito os Termos de Uso e a Política de '
                              'Privacidade. Declaro ter 18 '
                              'anos ou mais e que não vou manusear o celular '
                              'enquanto estiver dirigindo ou pilotando.'),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                _checked && !_saving ? _accept : null,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Continuar'),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]),
      ),
    );
  }

  /// Desenha o texto em Markdown simples: "#"/"##" títulos, "- " itens e
  /// **negrito**. (Evita um pacote de Markdown só para esta tela.)
  List<Widget> _render(BuildContext context, String md) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        out.add(const SizedBox(height: 8));
      } else if (line.startsWith('# ')) {
        out.add(Text(line.substring(2),
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)));
      } else if (line.startsWith('## ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(line.substring(3),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('- ')) {
        out.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: _rich(line.substring(2), theme)),
          ]),
        ));
      } else {
        out.add(_rich(line, theme));
      }
    }
    return out;
  }

  /// Texto com trechos **em negrito**.
  Widget _rich(String s, ThemeData theme) {
    final parts = s.split('**');
    return Text.rich(TextSpan(
      style: theme.textTheme.bodyMedium,
      children: [
        for (var i = 0; i < parts.length; i++)
          TextSpan(
            text: parts[i],
            style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
      ],
    ));
  }
}
