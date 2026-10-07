// ============================================================================
// club_screen.dart — Tela do clube
//
// O que faz: Clube oficial. O presidente cria o clube com o código de
//   ativação da HelpAITech e gera convites de uso único; o membro entra com
//   o convite. Também: membros (o presidente pode remover), pedidos de ajuda
//   e avisos de passagem.
// Quem usa: HomeScreen (botão Clube).
// Onde mexer: Regras do servidor: functions/clubs.js (criar, convidar,
//   entrar) e functions/index.js (clubNearby, clubNotify).
// ============================================================================

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/privacy.dart';
import '../services/auth_service.dart';
import '../services/club_service.dart';
import '../services/profile_service.dart';
import '../services/user_service.dart';
import '../widgets/club_nearby_sheet.dart';
import 'consent_screen.dart';

/// Tela do clube: entrar com código, criar, ver membros, sair.
class ClubScreen extends StatefulWidget {
  const ClubScreen({super.key, required this.userName});
  final String userName;

  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

/// Estado da tela: clube atual, cidade base e autorizações.
class _ClubScreenState extends State<ClubScreen> {
  final _svc = ClubService.instance;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _activationCtrl = TextEditingController();
  String? _clubId;
  String? _clubName;
  String _presidentId = '';
  String? _uid;
  Consents _consents = const Consents();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carrega o clube salvo no celular e as autorizações. Confere no
  /// servidor se a pessoa ainda é membro (o presidente pode remover).
  Future<void> _load() async {
    final uid = await AuthService.ensureSignedIn();
    var id = await UserService.loadClubId();
    var name = await UserService.loadClubName();
    final c = await UserService.loadConsents() ?? const Consents();
    String president = '';
    if (id != null) {
      final club = await _svc.find(id);
      if (club == null) {
        // Removido do clube (ou clube encerrado): limpa no celular.
        await UserService.setClub(null, null);
        id = null;
        name = null;
      } else {
        name = club.name;
        president = club.presidentId;
      }
    }
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _clubId = id;
      _clubName = name;
      _presidentId = president;
      _consents = c;
      _loading = false;
    });
  }

  bool get _isPresident => _presidentId.isNotEmpty && _presidentId == _uid;

  /// Mostra uma mensagem rápida no rodapé.
  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// Cidade base (só se autorizou "ser encontrado") e veículo, enviados ao
  /// entrar no clube.
  Future<(String, String)> _cityAndBike() async {
    final base = await UserService.loadBase();
    final bike = await ProfileService.load();
    return (_consents.findable ? (base?.city ?? '') : '', bike.displayName);
  }

  /// Guarda o clube no celular e mostra a tela do clube.
  Future<void> _entered(Club club) async {
    await UserService.setClub(club.id, club.name);
    setState(() {
      _clubId = club.id;
      _clubName = club.name;
      _presidentId = club.presidentId;
    });
  }

  /// Executa uma ação mostrando "carregando" e o erro, se houver.
  Future<void> _run(Future<void> Function() action) async {
    if (widget.userName.isEmpty) {
      _snack('Informe seu nome de piloto na tela inicial');
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Não foi possível concluir. Tente de novo.');
    } catch (e) {
      _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Presidente: cria o clube com o código de ativação da HelpAITech.
  void _create() => _run(() async {
        final code = _activationCtrl.text.trim();
        final name = _nameCtrl.text.trim();
        if (code.isEmpty || name.isEmpty) {
          _snack('Digite o código de ativação e o nome do clube');
          return;
        }
        final (city, bike) = await _cityAndBike();
        await _entered(await _svc.createWithActivation(
          activationCode: code,
          name: name,
          memberName: widget.userName,
          city: city,
          bike: bike,
        ));
        _snack('Clube criado! Agora gere convites para os membros.');
      });

  /// Membro: entra com o convite de uso único recebido do presidente.
  void _join() => _run(() async {
        final code = _codeCtrl.text.trim();
        if (code.isEmpty) {
          _snack('Digite o convite recebido do presidente do clube');
          return;
        }
        final (city, bike) = await _cityAndBike();
        await _entered(await _svc.joinWithInvite(
          inviteCode: code,
          memberName: widget.userName,
          city: city,
          bike: bike,
        ));
      });

  /// Presidente: gera um convite de uso único e mostra para enviar.
  void _invite() => _run(() async {
        final inv = await _svc.createInvite(_clubId!);
        if (!mounted) return;
        final d = inv.expiresAt;
        final msg = 'Convite para entrar no clube $_clubName no app '
            'Comboio: ${inv.display}\n(vale para UMA pessoa, até '
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')})';
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Convite de uso único'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              SelectableText(inv.display,
                  style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('Envie para UM membro. Ele digita em Clube → '
                  '"Entrar no meu clube". Depois de usado, o convite não vale '
                  'mais. Vale por 7 dias.'),
            ]),
            actions: [
              TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: msg));
                    Navigator.pop(ctx);
                    _snack('Convite copiado');
                  },
                  child: const Text('Copiar')),
              FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    SharePlus.instance.share(ShareParams(text: msg));
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Enviar')),
            ],
          ),
        );
      });

  /// Presidente: remove um membro (com confirmação).
  Future<void> _remove(ClubMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remover ${m.name} do clube?'),
        content: const Text('Para voltar, ele vai precisar de um novo convite.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.removeMember(_clubId!, m.uid);
      _snack('${m.name} foi removido do clube');
    } catch (e) {
      _snack('Não foi possível remover: $e');
    }
  }

  /// Sai do clube (com confirmação).
  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do clube?'),
        content: Text(_isPresident
            ? 'Você é o presidente. Saindo, ninguém mais poderá gerar '
                'convites até a HelpAITech indicar um novo presidente. Para '
                'voltar, você precisará de um convite.'
            : 'Para voltar, você precisará de um novo convite do presidente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ficar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sair')),
        ],
      ),
    );
    if (ok != true) return;
    await _svc.leave(_clubId!, _uid!);
    await UserService.setClub(null, null);
    setState(() {
      _clubId = null;
      _clubName = null;
    });
  }

  /// Abre as autorizações (ser encontrado, receber pedidos, avisos).
  Future<void> _editConsents() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const ConsentScreen()));
    final c = await UserService.loadConsents() ?? const Consents();
    if (mounted) setState(() => _consents = c);
  }

  /// Etiqueta de autorização ligada/desligada.
  Widget _status(bool on, String label) => Chip(
        avatar: Icon(on ? Icons.check_circle : Icons.cancel,
            size: 18, color: on ? Colors.green : Colors.grey),
        label: Text(label),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Clube')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _busy,
              child: _clubId == null ? _noClub(theme) : _inClub(theme),
            ),
    );
  }

  /// Conteúdo quando o piloto ainda não está em nenhum clube.
  Widget _noClub(ThemeData theme) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Faça parte do seu clube no app para pedir ajuda ao membro mais próximo ou avisar quando passar pela cidade de alguém.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Entrar no meu clube',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                        'Peça ao presidente do seu clube um convite. Cada '
                        'convite vale para uma pessoa só.',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Convite (ex.: ABCD-2345)',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _join, child: const Text('Entrar')),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Sou presidente: cadastrar o clube',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                        'O cadastro do clube é feito pelo presidente, com o '
                        'código de ativação fornecido pela HelpAITech. Para '
                        'solicitar: helpaitech.ricardo@gmail.com',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _activationCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Código de ativação',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nome do clube',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _create, child: const Text('Cadastrar')),
                  ]),
            ),
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      );

  /// Conteúdo quando o piloto já está num clube.
  Widget _inClub(ThemeData theme) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Icon(Icons.shield, size: 40, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_clubName ?? '', style: theme.textTheme.titleLarge),
                    Text(_isPresident ? 'Você é o presidente' : 'Membro oficial',
                        style: theme.textTheme.bodySmall),
                  ]),
            ),
          ]),
          if (_isPresident) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: _invite,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Convidar membro (convite de uso único)'),
            ),
          ],
          const SizedBox(height: 16),
          Text('Suas autorizações', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _status(_consents.findable, 'Ser encontrado'),
            _status(_consents.receiveHelp, 'Pedidos de ajuda'),
            _status(_consents.receivePassing, 'Avisos de passagem'),
          ]),
          TextButton.icon(
            onPressed: _editConsents,
            icon: const Icon(Icons.privacy_tip_outlined),
            label: const Text('Alterar autorizações'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52)),
            onPressed: () => showClubNearbySheet(context,
                clubId: _clubId!, purpose: ClubPurpose.help),
            icon: const Icon(Icons.sos),
            label: const Text('Pedir ajuda ao membro mais próximo'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            onPressed: () => showClubNearbySheet(context,
                clubId: _clubId!, purpose: ClubPurpose.passing),
            icon: const Icon(Icons.waving_hand_outlined),
            label: const Text('Avisar membros que estou passando'),
          ),
          const SizedBox(height: 24),
          Text('Membros', style: theme.textTheme.titleSmall),
          StreamBuilder<List<ClubMember>>(
            stream: _svc.members(_clubId!),
            builder: (ctx, snap) {
              final list = snap.data ?? [];
              return Column(children: [
                for (final m in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                        child: Text(
                            m.name.isEmpty ? '?' : m.name[0].toUpperCase())),
                    title: Text([
                      m.uid == _uid ? '${m.name} (você)' : m.name,
                      if (m.isPresident) '· presidente',
                    ].join(' ')),
                    subtitle: Text([
                      m.city.isEmpty ? 'Cidade não compartilhada' : m.city,
                      if (m.bike.isNotEmpty) m.bike,
                    ].join(' · ')),
                    trailing: _isPresident && m.uid != _uid
                        ? IconButton(
                            icon: const Icon(Icons.person_remove_outlined),
                            tooltip: 'Remover do clube',
                            onPressed: () => _remove(m),
                          )
                        : null,
                  ),
              ]);
            },
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: _leave, child: const Text('Sair do clube')),
        ],
      );
}
