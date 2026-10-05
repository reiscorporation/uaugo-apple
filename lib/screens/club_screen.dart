// ============================================================================
// club_screen.dart — Tela do motoclube
//
// O que faz: Entrar/criar um motoclube, ver membros e configurar o que o
//   piloto aceita receber (pedidos de ajuda, avisos de passagem).
// Quem usa: HomeScreen (botão Motoclube).
// Onde mexer: Regras do servidor: functions/index.js (clubNearby, clubNotify).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/privacy.dart';
import '../services/auth_service.dart';
import '../services/club_service.dart';
import '../services/profile_service.dart';
import '../services/user_service.dart';
import '../widgets/club_nearby_sheet.dart';
import 'consent_screen.dart';

/// Tela do motoclube: entrar com código, criar, ver membros, sair.
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
  String? _clubId;
  String? _clubName;
  String? _uid;
  Consents _consents = const Consents();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carrega o clube salvo no celular e as autorizações.
  Future<void> _load() async {
    final uid = await AuthService.ensureSignedIn();
    final id = await UserService.loadClubId();
    final name = await UserService.loadClubName();
    final c = await UserService.loadConsents() ?? const Consents();
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _clubId = id;
      _clubName = name;
      _consents = c;
      _loading = false;
    });
  }

  /// Mostra uma mensagem rápida no rodapé.
  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  /// Entra no clube: salva no celular e registra a cidade base no servidor.
  Future<void> _enter(String clubId, String clubName) async {
    final base = await UserService.loadBase();
    final bike = await ProfileService.load();
    await _svc.join(
      clubId: clubId,
      uid: _uid!,
      userName: widget.userName,
      city: _consents.findable ? (base?.city ?? '') : '',
      bike: bike.displayName,
    );
    await UserService.setClub(clubId, clubName);
    setState(() {
      _clubId = clubId;
      _clubName = clubName;
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
    } catch (e) {
      _snack('Erro: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cria um clube novo com o nome digitado.
  void _create() => _run(() async {
        final name = _nameCtrl.text.trim();
        if (name.isEmpty) {
          _snack('Digite o nome do motoclube');
          return;
        }
        final id = await _svc.create(name, _uid!);
        await _enter(id, name);
      });

  /// Entra num clube pelo código digitado.
  void _join() => _run(() async {
        final code = _codeCtrl.text.trim().toUpperCase();
        final club = await _svc.find(code);
        if (club == null) {
          _snack('Motoclube "$code" não encontrado');
          return;
        }
        await _enter(club.id, club.name);
      });

  /// Sai do clube (com confirmação).
  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do motoclube?'),
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
      appBar: AppBar(title: const Text('Motoclube')),
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
            'Faça parte do seu motoclube no app para pedir ajuda ao membro mais próximo ou avisar quando passar pela cidade de alguém.',
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                          labelText: 'Código do clube',
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
                    Text('Cadastrar meu clube',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                          labelText: 'Nome do motoclube',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: _create, child: const Text('Cadastrar')),
                    const SizedBox(height: 8),
                    Text(
                        'Você recebe um código para enviar aos membros do clube.',
                        style: theme.textTheme.bodySmall),
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
                    Text('Código: $_clubId', style: theme.textTheme.bodySmall),
                  ]),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar código',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _clubId!));
                _snack('Código copiado');
              },
            ),
          ]),
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
                    title: Text(m.uid == _uid ? '${m.name} (você)' : m.name),
                    subtitle: Text([
                      m.city.isEmpty ? 'Cidade não compartilhada' : m.city,
                      if (m.bike.isNotEmpty) m.bike,
                    ].join(' · ')),
                  ),
              ]);
            },
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: _leave, child: const Text('Sair do motoclube')),
        ],
      );
}
