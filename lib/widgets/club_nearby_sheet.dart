// ============================================================================
// club_nearby_sheet.dart — Clube: membros próximos
//
// O que faz: Folha para pedir ajuda ou avisar membros do clube que estão
//   perto.
// Quem usa: MapScreen (botão do clube).
// ============================================================================

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/club_service.dart';
import '../services/user_service.dart';

/// Lista os membros do clube próximos que autorizaram o contato.
Future<void> showClubNearbySheet(
  BuildContext context, {
  required String clubId,
  required ClubPurpose purpose,
  Position? position,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _NearbySheet(clubId: clubId, purpose: purpose, position: position),
  );
}

/// Confirma e envia o aviso/pedido para um membro.
Future<void> confirmAndNotify(
  BuildContext context, {
  required String clubId,
  required NearbyMember member,
  required ClubPurpose purpose,
  Position? position,
}) async {
  final isHelp = purpose == ClubPurpose.help;
  final phone = await UserService.loadPhone();
  final msgCtrl = TextEditingController();
  var includePhone = phone.isNotEmpty;
  if (!context.mounted) return;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(isHelp
            ? 'Pedir ajuda a ${member.name}?'
            : 'Avisar ${member.name}?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(isHelp
                ? 'Sua localização exata será enviada para ${member.name} (${member.city}).'
                : '${member.name} vai saber que você está passando por ${member.city}. Sua localização exata não é enviada.'),
            const SizedBox(height: 12),
            TextField(
              controller: msgCtrl,
              maxLength: 140,
              decoration: InputDecoration(
                labelText: 'Mensagem (opcional)',
                hintText: isHelp
                    ? 'Pneu furado, preciso de borracharia'
                    : 'Bora um café?',
                border: const OutlineInputBorder(),
              ),
            ),
            if (phone.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includePhone,
                onChanged: (v) => setD(() => includePhone = v ?? false),
                title: Text('Enviar meu telefone ($phone)'),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isHelp ? 'Pedir ajuda' : 'Avisar')),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final pos = isHelp ? (position ?? await Geolocator.getCurrentPosition()) : null;
    await ClubService.instance.notify(
      clubId: clubId,
      targetUid: member.uid,
      purpose: purpose,
      lat: pos?.latitude,
      lng: pos?.longitude,
      message: msgCtrl.text.trim(),
      phone: includePhone ? phone : null,
    );
    messenger.showSnackBar(
        SnackBar(content: Text('Enviado para ${member.name}')));
  } on FirebaseFunctionsException catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? 'Não foi possível enviar')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Não foi possível enviar: $e')));
  }
}

/// Folha com os membros do clube por perto (ajuda ou passagem).
class _NearbySheet extends StatefulWidget {
  const _NearbySheet(
      {required this.clubId, required this.purpose, this.position});
  final String clubId;
  final ClubPurpose purpose;
  final Position? position;

  @override
  State<_NearbySheet> createState() => _NearbySheetState();
}

/// Busca os membros e envia o aviso escolhido.
class _NearbySheetState extends State<_NearbySheet> {
  late Future<List<NearbyMember>> _future;
  Position? _pos;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Membros próximos (Cloud Function clubNearby).
  Future<List<NearbyMember>> _load() async {
    final p = widget.position ?? await Geolocator.getCurrentPosition();
    _pos = p;
    return ClubService.instance.nearby(
      clubId: widget.clubId,
      lat: p.latitude,
      lng: p.longitude,
      purpose: widget.purpose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHelp = widget.purpose == ClubPurpose.help;
    return SafeArea(
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              isHelp ? 'Pedir ajuda ao clube' : 'Avisar membros próximos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Aparecem só os membros que autorizaram esse contato, até 300 km.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<NearbyMember>>(
                future: _future,
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    final e = snap.error;
                    return Text(e is FirebaseFunctionsException
                        ? (e.message ?? 'Erro ao buscar membros')
                        : 'Sem conexão para buscar membros agora.');
                  }
                  final list = snap.data ?? [];
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Nenhum membro do clube autorizou contato nessa região.',
                          textAlign: TextAlign.center),
                    );
                  }
                  final nearest = list.first;
                  return ListView(shrinkWrap: true, children: [
                    if (isHelp)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(52)),
                          onPressed: () => confirmAndNotify(context,
                              clubId: widget.clubId,
                              member: nearest,
                              purpose: widget.purpose,
                              position: _pos),
                          icon: const Icon(Icons.sos),
                          label: Text(
                              'Pedir ao mais próximo: ${nearest.name} (~${nearest.distanceKm} km)'),
                        ),
                      ),
                    for (final m in list)
                      ListTile(
                        leading: CircleAvatar(
                            child: Text(m.name.isEmpty
                                ? '?'
                                : m.name[0].toUpperCase())),
                        title: Text(m.name),
                        subtitle: Text([
                          m.city,
                          '~${m.distanceKm} km',
                          if (m.bike.isNotEmpty) m.bike,
                        ].join(' · ')),
                        trailing: FilledButton.tonal(
                          onPressed: () => confirmAndNotify(context,
                              clubId: widget.clubId,
                              member: m,
                              purpose: widget.purpose,
                              position: _pos),
                          child: Text(isHelp ? 'Pedir' : 'Avisar'),
                        ),
                      ),
                  ]);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
