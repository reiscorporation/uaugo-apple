// ============================================================================
// community_post_sheet.dart — "Postar na comunidade" (viagem do histórico)
//
// O que faz: Folha para postar a viagem na Comunidade UauGo: escolhe onde
//   (feed geral ou uma tribo), opcionalmente liga a um post seu da viagem,
//   texto já preenchido, e anexa a imagem da viagem e/ou o GIF da rota.
// Quem usa: HistoryScreen (detalhe da viagem).
// Onde mexer: envio em services/community_post_service.dart; imagem e GIF em
//   widgets/trip_share.dart.
// ============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/i18n.dart';
import '../logic/itinerary.dart';
import '../models/trip_record.dart';
import '../services/community_post_service.dart';
import '../services/community_routes_service.dart';
import 'trip_share.dart';

Future<void> showCommunityPostSheet(
    BuildContext context, TripRecord trip, GoogleMapController? map) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CommunityPostSheet(trip: trip, map: map),
  );
}

class _CommunityPostSheet extends StatefulWidget {
  final TripRecord trip;
  final GoogleMapController? map;
  const _CommunityPostSheet({required this.trip, required this.map});

  @override
  State<_CommunityPostSheet> createState() => _CommunityPostSheetState();
}

class _CommunityPostSheetState extends State<_CommunityPostSheet> {
  List<CommunityTarget>? _targets;
  List<MyPost> _posts = const [];
  String? _error;
  CommunityTarget? _target;
  String? _related; // id do post da viagem
  bool _withImage = true;
  bool _withGif = true;
  bool _busy = false;
  String _status = '';
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final t = widget.trip;
    _text = TextEditingController(
        text: tr('{0} · {1} percorridos com o UauGo', [t.title, formatDistance(t.distanceM.round())]));
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final targets = await CommunityPostService.targets();
      final posts = await CommunityPostService.myPosts();
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _target = targets.first;
        _posts = posts;
      });
    } on CommunityRoutesError catch (e) {
      if (mounted) setState(() => _error = tr(e.message));
    }
  }

  Future<void> _publish() async {
    final target = _target;
    if (target == null || (!_withImage && !_withGif && _text.text.trim().isEmpty)) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    setState(() => _busy = true);
    try {
      final media = <String>[];
      if (_withImage) {
        setState(() => _status = tr('Preparando a imagem…'));
        Uint8List? png;
        try {
          png = await widget.map?.takeSnapshot();
        } catch (_) {}
        final jpg = await shareImageJpeg(await buildShareImage(widget.trip, png));
        setState(() => _status = tr('Enviando a imagem…'));
        media.add(await CommunityPostService.upload(jpg, 'image/jpeg'));
      }
      if (_withGif) {
        setState(() => _status = tr('Criando o GIF da rota… pode levar alguns segundos'));
        final gif = await buildRouteGif(widget.trip, widget.map, devicePixelRatio: dpr);
        if (gif != null) {
          setState(() => _status = tr('Enviando o GIF…'));
          media.add(await CommunityPostService.upload(gif, 'image/gif'));
        }
      }
      setState(() => _status = tr('Publicando…'));
      final url = await CommunityPostService.create(
          target: target, text: _text.text, media: media, relatedPostId: _related);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
        content: Text(tr('Postado na comunidade!')),
        action: SnackBarAction(
            label: tr('Abrir'),
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
      ));
    } on CommunityRoutesError catch (e) {
      if (mounted) setState(() => _error = tr(e.message));
    } catch (_) {
      if (mounted) setState(() => _error = tr('Não foi possível postar agora. Tente de novo.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Postar na comunidade'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          if (targets == null && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (targets != null) ...[
            DropdownButtonFormField<CommunityTarget>(
              initialValue: _target,
              decoration: InputDecoration(labelText: tr('Onde postar')),
              items: [
                for (final t in targets)
                  DropdownMenuItem(value: t, child: Text(t.id.isEmpty ? tr('Feed geral') : t.name)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _target = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _related,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Ligar a um post seu da viagem (opcional)')),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(tr('Nenhum'))),
                for (final p in _posts)
                  DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(
                          '${p.created.day.toString().padLeft(2, '0')}/${p.created.month.toString().padLeft(2, '0')} · '
                          '${p.text.isEmpty ? tr('(sem texto)') : p.text.split('\n').first}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _related = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _text,
              enabled: !_busy,
              minLines: 2,
              maxLines: 5,
              maxLength: 4000,
              decoration: InputDecoration(labelText: tr('Texto')),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _withImage,
              onChanged: _busy ? null : (v) => setState(() => _withImage = v ?? false),
              title: Text(tr('Imagem da viagem (mapa e números)')),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _withGif,
              onChanged: _busy ? null : (v) => setState(() => _withGif = v ?? false),
              title: Text(tr('GIF da rota (animação acelerada)')),
            ),
            const SizedBox(height: 8),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ]),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: const Icon(Icons.send),
              label: Text(tr('Publicar')),
            ),
          ],
        ]),
      ),
    );
  }
}
