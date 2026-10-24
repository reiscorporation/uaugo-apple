// ============================================================================
// consent_screen.dart — Autorizações (LGPD)
//
// O que faz: No primeiro uso, o piloto escolhe o que autoriza (localização
//   obrigatória para o comboio; clube opcional). Permite revogar e excluir
//   os dados depois.
// Quem usa: StartupGate e Home (Privacidade e autorizações).
// Onde mexer: Textos legais e opções: este arquivo + models/privacy.dart.
// ============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/privacy.dart';
import '../services/club_service.dart';
import '../services/location_service.dart';
import '../services/user_service.dart';
import 'startup_gate.dart';
import '../l10n/i18n.dart';

/// Tela de autorizações. Aparece obrigatoriamente no primeiro uso
/// (cadastro) e depois em "Privacidade e autorizações".
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, this.firstTime = false, this.onDone});

  final bool firstTime;
  final VoidCallback? onDone;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

/// Estado da tela: autorizações marcadas, cidade base e telefone.
class _ConsentScreenState extends State<ConsentScreen> {
  Consents _c = const Consents();
  BaseLocation? _base;
  final _phoneCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carrega o que já foi autorizado antes.
  Future<void> _load() async {
    final c = await UserService.loadConsents();
    final b = await UserService.loadBase();
    final phone = await UserService.loadPhone();
    if (!mounted) return;
    setState(() {
      if (c != null) _c = c;
      _base = b;
      _phoneCtrl.text = phone;
      _loading = false;
    });
  }

  /// Mostra uma mensagem rápida no rodapé.
  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// Detecta a cidade base pelo GPS (arredondada a ~1 km).
  Future<void> _detect() async {
    setState(() => _detecting = true);
    try {
      if (!await LocationService.ensurePermission()) {
        _snack(tr('Permita o acesso à localização para definir sua cidade'));
        return;
      }
      final b = await UserService.detectBase();
      if (mounted) setState(() => _base = b);
    } catch (e) {
      _snack(tr('Não foi possível obter sua cidade: {0}', [e]));
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  /// Salva as autorizações (celular e servidor) e segue para o app.
  Future<void> _save() async {
    if (!_c.shareLiveLocation) {
      _snack(tr('A primeira autorização é necessária para usar o UauGo'));
      return;
    }
    if (_c.findable && _base == null) {
      _snack(tr('Defina sua cidade base para ser encontrado pelo clube'));
      return;
    }
    setState(() => _saving = true);
    try {
      await UserService.saveConsents(_c,
          base: _base, phone: _phoneCtrl.text.trim());
      // Mantém a cidade exibida no clube coerente com a autorização.
      final clubId = await UserService.loadClubId();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (clubId != null && uid != null) {
        await ClubService.instance
            .updateCity(clubId, uid, _c.findable ? (_base?.city ?? '') : '');
      }
      if (!mounted) return;
      if (widget.firstTime) {
        widget.onDone?.call();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      _snack(tr('Não foi possível salvar: {0}', [e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Exclui todos os dados do usuário (servidor e celular), com confirmação.
  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 40),
        title: Text(tr('Excluir todos os meus dados?')),
        content: Text(
            tr('Vamos apagar seu perfil, autorizações, cidade base, foto do veículo, sua participação em expedições e no clube. Alertas de perigo que você reportou continuam visíveis, mas sem ligação com você. Essa ação não pode ser desfeita.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Cancelar'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Excluir tudo')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await UserService.deleteAllMyData();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const StartupGate()),
        (_) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Seus dados foram excluídos.'))));
    } catch (e) {
      _snack(tr('Não foi possível excluir agora (verifique a conexão): {0}', [e]));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Título de seção da tela.
  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Autorizações')),
        automaticallyImplyLeading: !widget.firstTime,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.firstTime
                      ? tr('Antes de começar, escolha o que você autoriza. Nada é ativado sem a sua permissão, e você pode mudar tudo depois em "Privacidade e autorizações".')
                      : tr('Você pode ativar ou revogar cada autorização quando quiser. As mudanças valem na hora.'),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              _section(tr('Uso do app')),
              SwitchListTile(
                value: _c.shareLiveLocation,
                onChanged: (v) =>
                    setState(() => _c = _c.copyWith(shareLiveLocation: v)),
                title: Text(
                    tr('Compartilhar minha localização em tempo real com o comboio')),
                subtitle: Text(
                    tr('Obrigatório. Só os pilotos das expedições em que você entrar veem sua posição, e só enquanto a expedição estiver aberta.')),
              ),
              _section(tr('Clube')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  tr('Membros do seu clube podem pedir ajuda ou avisar que estão passando pela sua cidade. Essas autorizações são opcionais.'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              SwitchListTile(
                value: _c.findable,
                onChanged: (v) {
                  setState(() => _c = _c.copyWith(findable: v));
                  if (v && _base == null) _detect();
                },
                title: Text(tr('Ser encontrado por membros do meu clube')),
                subtitle: Text(
                    tr('Eles veem apenas seu nome, sua cidade base e a distância aproximada, nunca sua localização exata.')),
              ),
              SwitchListTile(
                value: _c.receiveHelp,
                onChanged: _c.findable
                    ? (v) => setState(() => _c = _c.copyWith(receiveHelp: v))
                    : null,
                title: Text(tr('Receber pedidos de ajuda de membros próximos')),
                subtitle: Text(
                    tr('Se um membro precisar de ajuda perto da sua cidade, você recebe uma notificação com a localização dele.')),
              ),
              SwitchListTile(
                value: _c.receivePassing,
                onChanged: _c.findable
                    ? (v) =>
                        setState(() => _c = _c.copyWith(receivePassing: v))
                    : null,
                title: Text(tr('Receber avisos de membros de passagem')),
                subtitle: Text(
                    tr('Um membro do clube pode avisar que está passando pela sua cidade.')),
              ),
              if (_c.findable)
                ListTile(
                  leading: const Icon(Icons.location_city),
                  title: Text(_base?.city ?? tr('Cidade base não definida')),
                  subtitle: Text(
                      tr('Posição aproximada (~1 km). Use onde você mora ou costuma estar.')),
                  trailing: _detecting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: _detect,
                          child: Text(tr('Usar local atual'))),
                ),
              _section(tr('Contato')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: tr('Telefone / WhatsApp (opcional)'),
                    hintText: '+55 48 99999-9999',
                    helperText:
                        tr('Fica só no seu celular. É enviado apenas quando você pede ajuda ou avisa alguém e marca essa opção.'),
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_user),
                  label: Text(widget.firstTime
                      ? tr('Concordo e continuar')
                      : tr('Salvar autorizações')),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr('Ao revogar "ser encontrado", sua cidade é apagada do servidor e você deixa de aparecer nas buscas do clube imediatamente.'),
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
              if (!widget.firstTime) ...[
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade300,
                      side: BorderSide(color: Colors.red.shade300),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _saving ? null : _deleteAll,
                    icon: const Icon(Icons.delete_forever),
                    label: Text(tr('Excluir todos os meus dados')),
                  ),
                ),
              ],
            ]),
    );
  }
}
