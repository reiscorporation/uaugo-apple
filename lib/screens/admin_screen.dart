// ============================================================================
// admin_screen.dart — Administração UauGo (clubes e convites na hora)
//
// O que faz: Para os administradores da plataforma (platformAdmins/{uid}):
//   lista os clubes, cadastra clube novo, gera CÓDIGO DE ADMINISTRADOR do
//   clube (presidente/diretor) e CONVITE DE MEMBRO, mostrando o código
//   grande, o QR code e o envio pelo WhatsApp. Feito para apresentar o app
//   num rolê e já ativar o clube.
// Quem usa: SettingsScreen (só aparece para administradores).
// Onde mexer: Servidor: functions/clubs.js (admin*). Página do QR:
//   scripts/gerar-paginas.js (/clube).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/club_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _svc = ClubService.instance;
  List<AdminClub>? _clubs;
  String _filter = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _svc.adminListClubs();
      if (mounted) setState(() => _clubs = c);
    } catch (e) {
      if (mounted) {
        setState(() => _clubs = const []);
        _snack('Não foi possível carregar os clubes: $e');
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Roda uma ação no servidor com indicador de carregamento.
  Future<T?> _run<T>(Future<T> Function() f) async {
    setState(() => _busy = true);
    try {
      return await f();
    } catch (e) {
      _snack('Erro: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newClub() async {
    final name = TextEditingController(), uf = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cadastrar clube'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome do clube'),
          ),
          TextField(
            controller: uf,
            textCapitalization: TextCapitalization.characters,
            maxLength: 2,
            decoration: const InputDecoration(labelText: 'Estado (UF)'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cadastrar')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final r = await _run(() => _svc.adminCreateClub(name.text.trim(), uf.text.trim()));
    if (r == null || !mounted) return;
    await _load();
    if (!mounted) return;
    _snack('Clube "${r.name}" cadastrado. Gere o código do presidente.');
  }

  Future<void> _actions(AdminClub c) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${c.admins} administrador(es) · ${c.members} membro(s)'
                '${c.status == 'reserved' ? ' · ainda não ativado' : ''}'),
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings),
            title: const Text('Código de administrador'),
            subtitle: const Text('Para o presidente ou diretor: ele ativa o clube '
                'e passa a convidar os membros.'),
            onTap: () => Navigator.pop(ctx, 'admin'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('Convite de membro'),
            subtitle: const Text('Uma pessoa entra no clube (vale 7 dias, um uso).'),
            onTap: () => Navigator.pop(ctx, 'member'),
          ),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'admin') {
      final r = await _run(() => _svc.adminActivationCode(c.id));
      if (r != null && mounted) {
        await _showCode(r.code,
            title: 'Código de administrador',
            club: c.name,
            how: 'No UauGo: Clube → "Sou administrador do clube" → digite o código → Ativar.');
        await _load();
      }
    } else {
      final r = await _run(() => _svc.adminMemberInvite(c.id));
      if (r != null && mounted) {
        await _showCode(r.code,
            title: 'Convite de membro',
            club: c.name,
            how: 'No UauGo: Clube → "Entrar no meu clube" → digite o convite → Entrar. '
                'Vale 7 dias e para uma pessoa.');
      }
    }
  }

  /// Código grande + QR (abre a página do convite) + enviar pelo WhatsApp.
  Future<void> _showCode(String code,
      {required String title, required String club, required String how}) {
    final shown = code.length == 12
        ? '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}'
        : '${code.substring(0, 4)}-${code.substring(4)}';
    final link = 'https://helpaitechcomboio.web.app/clube?c=$code';
    final message = '$title do clube $club no UauGo: $shown\n$how\n'
        'Abrir direto no app: $link';
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(club, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SelectableText(shown,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(data: link, size: 200),
            ),
            const SizedBox(height: 8),
            Text('Aponte a câmera do celular para o QR code.\n$how',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
          FilledButton.icon(
            onPressed: () => SharePlus.instance.share(ShareParams(text: message)),
            icon: const Icon(Icons.share),
            label: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = _clubs;
    final list = all
        ?.where((c) => _filter.isEmpty ||
            c.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administração UauGo'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _newClub,
        icon: const Icon(Icons.add),
        label: const Text('Cadastrar clube'),
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar clube',
                      border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        leading: Icon(
                            c.status == 'reserved' ? Icons.shield_outlined : Icons.shield,
                            color: c.status == 'reserved' ? Colors.grey : null),
                        title: Text(c.name),
                        subtitle: Text([
                          if (c.uf.isNotEmpty) c.uf,
                          '${c.admins} adm',
                          '${c.members} membros',
                          if (c.status == 'reserved') 'não ativado',
                        ].join(' · ')),
                        trailing: const Icon(Icons.qr_code),
                        onTap: _busy ? null : () => _actions(c),
                      );
                    },
                  ),
                ),
              ),
            ]),
    );
  }
}
