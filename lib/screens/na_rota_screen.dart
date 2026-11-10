// ============================================================================
// na_rota_screen.dart — "Na rota": turismo, hospedagem e postos perto de um
// ponto (parada, destino ou onde o piloto está)
//
// O que faz: Três abas. Turismo: atrações a até 50 km, toque abre os
//   detalhes (foto e o básico) com "Ver mais". Hospedagem: hotéis da noite
//   escolhida, mais barato primeiro (página de hotéis do Google, que junta
//   Booking, Decolar, Hoteis.com...). Postos: famosos entre motociclistas
//   primeiro, com o preço da ANP quando acha.
// Quem usa: MapScreen (opções da parada) e PlanScreen (roteiro).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/i18n.dart';
import '../logic/costs.dart';
import '../logic/na_rota.dart';
import '../models/expedition.dart';
import '../services/na_rota_service.dart';
import '../widgets/safe_sheet.dart';

/// Inclui um lugar como parada (nome, posição, tipo).
typedef AddStop = Future<void> Function(String name, double lat, double lng, StopType type);

class NaRotaScreen extends StatefulWidget {
  final double lat, lng;

  /// Nome do ponto (ex.: nome da parada), para o título.
  final String lugar;

  /// Aba inicial: 0 turismo, 1 hospedagem, 2 postos.
  final int aba;

  /// Noite da hospedagem (pernoite planejado); sem ela, hoje.
  final DateTime? noite;

  /// Sem [onAddStop], não mostra "Adicionar como parada".
  final AddStop? onAddStop;

  const NaRotaScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.lugar,
    this.aba = 0,
    this.noite,
    this.onAddStop,
  });

  @override
  State<NaRotaScreen> createState() => _NaRotaScreenState();
}

class _NaRotaScreenState extends State<NaRotaScreen> {
  final _svc = NaRotaService.instance;
  late Future<List<Atracao>> _atracoes;
  late Future<List<PostoRota>> _postos;
  late Future<List<PrecoAnp>> _precosCidade;
  Future<List<Hotel>>? _hoteis;
  late DateTime _noite;
  String? _cidade;

  @override
  void initState() {
    super.initState();
    final n = widget.noite ?? DateTime.now();
    _noite = DateTime(n.year, n.month, n.day);
    _atracoes = _svc.atracoes(widget.lat, widget.lng);
    _postos = _svc.postos(widget.lat, widget.lng);
    _precosCidade = _svc.precosCidade(widget.lat, widget.lng);
    _svc.cidadeDe(widget.lat, widget.lng).then((c) {
      if (mounted) setState(() => _cidade = c);
    });
    _buscaHoteis();
  }

  void _buscaHoteis() => _hoteis = _svc.hoteis(widget.lat, widget.lng, _noite)
    ..catchError((Object e) {
      debugPrint('Hotéis: erro $e');
      return const <Hotel>[];
    });

  String _km(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0).replaceAll('.', ',')} km';

  Future<void> _abre(Uri u) => launchUrl(u, mode: LaunchMode.inAppBrowserView);

  Future<void> _navegar(double lat, double lng) => launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving'),
      mode: LaunchMode.externalApplication);

  Future<void> _adicionar(String nome, double lat, double lng, StopType t) async {
    final add = widget.onAddStop;
    if (add == null) return;
    Navigator.of(context).popUntil((r) => r is! PopupRoute);
    Navigator.of(context).pop();
    await add(nome, lat, lng, t);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.aba,
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Na rota')),
            Text(_cidade ?? widget.lugar,
                style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
          ]),
          bottom: TabBar(tabs: [
            Tab(icon: const Icon(Icons.photo_camera_outlined), text: tr('Turismo')),
            Tab(icon: const Icon(Icons.hotel_outlined), text: tr('Hospedagem')),
            Tab(icon: const Icon(Icons.local_gas_station_outlined), text: tr('Postos')),
          ]),
        ),
        body: TabBarView(children: [_turismo(), _hospedagem(), _postosTab()]),
      ),
    );
  }

  Widget _carregando() => const Center(child: CircularProgressIndicator());

  Widget _vazio(IconData i, String txt, {VoidCallback? retry, Widget? acao}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(txt, textAlign: TextAlign.center),
            if (acao != null) ...[const SizedBox(height: 16), acao],
            if (retry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: retry, child: Text(tr('Tentar de novo'))),
            ],
          ]),
        ),
      );

  // ------------------------------- Turismo -------------------------------

  Widget _turismo() => FutureBuilder<List<Atracao>>(
        future: _atracoes,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return _carregando();
          final l = s.data ?? const [];
          if (l.isEmpty) {
            return _vazio(Icons.photo_camera_outlined, tr('Nenhuma atração no mapa num raio de 50 km.'),
                retry: () => setState(() => _atracoes = _svc.atracoes(widget.lat, widget.lng)));
          }
          return ListView.separated(
            itemCount: l.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(tr('{0} atrações num raio de 50 km', [l.length]),
                      style: Theme.of(context).textTheme.labelLarge),
                );
              }
              final a = l[i - 1];
              return ListTile(
                leading: CircleAvatar(child: Text(a.emoji)),
                title: Text(a.nome),
                subtitle: Text([tr(a.tipoNome), _km(a.distM), if (a.cidade != null) a.cidade!].join(' · ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _detalhesTurismo(a),
              );
            },
          );
        },
      );

  /// "Detalhes de turismo": foto, o básico e "Ver mais".
  void _detalhesTurismo(Atracao a) {
    final det = _svc.detalhes(a);
    showSafeSheet(
      context: context,
      builder: (ctx) => FutureBuilder<DetalheAtracao>(
          future: det,
          builder: (_, s) {
            final d = s.data;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.connectionState != ConnectionState.done)
                const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              else if (d?.foto != null)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(d!.foto!,
                      height: 220,
                      fit: BoxFit.cover,
                      headers: const {'User-Agent': 'UauGo/1.2 (helpaitech.com.br)'},
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${a.emoji} ${a.nome}', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text([tr(a.tipoNome), tr('a {0}', [_km(a.distM)]), if (a.cidade != null) a.cidade!].join(' · '),
                      style: Theme.of(ctx).textTheme.bodySmall),
                  if (a.horario != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.schedule, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(a.horario!)),
                    ]),
                  ],
                  if (d?.resumo != null && d!.resumo!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(d.resumo!, maxLines: 8, overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.read_more),
                    label: Text(tr('Ver mais')),
                    onPressed: () => _abre(d?.pagina != null ? Uri.parse(d!.pagina!) : _svc.buscaWeb(a, _cidade)),
                  ),
                  if (widget.onAddStop != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_location_alt),
                      label: Text(tr('Adicionar como parada')),
                      onPressed: () => _adicionar(a.nome, a.lat, a.lng, StopType.sight),
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.navigation_outlined),
                    label: Text(tr('Navegar')),
                    onPressed: () => _navegar(a.lat, a.lng),
                  ),
                  if (a.site != null)
                    TextButton.icon(
                      icon: const Icon(Icons.public),
                      label: Text(tr('Site')),
                      onPressed: () => _abre(Uri.parse(a.site!.startsWith('http') ? a.site! : 'https://${a.site}')),
                    ),
                ]),
              ),
            ]);
          },
        ),
    );
  }

  // ------------------------------ Hospedagem ------------------------------

  Widget _hospedagem() {
    String dia(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(
            child: Text(tr('Noite de {0} para {1}', [dia(_noite), dia(_noite.add(const Duration(days: 1)))]),
                style: Theme.of(context).textTheme.labelLarge),
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_month),
            label: Text(tr('Trocar data')),
            onPressed: () async {
              final hoje = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: _noite,
                firstDate: DateTime(hoje.year, hoje.month, hoje.day),
                lastDate: hoje.add(const Duration(days: 330)),
              );
              if (d == null) return;
              setState(() {
                _noite = d;
                _buscaHoteis();
              });
            },
          ),
        ]),
      ),
      Expanded(
        child: FutureBuilder<List<Hotel>>(
          future: _hoteis,
          builder: (_, s) {
            if (s.connectionState != ConnectionState.done) return _carregando();
            if (s.hasError || (s.data ?? const []).isEmpty) {
              // A lista vem da página de hotéis do Google, que muda de formato.
              // Enquanto a fonte própria (API de afiliado) não entra, abre a
              // mesma busca no navegador, com a cidade e a noite escolhidas.
              return _vazio(Icons.hotel_outlined,
                  tr('A lista de hotéis não carregou agora. Veja os hotéis da cidade no Google, com a data escolhida.'),
                  acao: FilledButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: Text(tr('Ver hotéis no Google')),
                    onPressed: () => _abre(googleHoteisUri(_cidade ?? widget.lugar, _noite)),
                  ),
                  retry: () => setState(_buscaHoteis));
            }
            final l = s.data!;
            return ListView.separated(
              itemCount: l.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                if (i == l.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr('Preços de uma noite, com taxas, das agências (Booking, Decolar, Hoteis.com e outras) reunidas pelo Google. Toque para comparar as ofertas.'),
                        style: Theme.of(context).textTheme.bodySmall),
                  );
                }
                final h = l[i];
                final barato = i == 0 && h.preco != null;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: barato ? Colors.green.shade100 : null,
                    child: Text(barato ? '💰' : '🛏️'),
                  ),
                  title: Text(h.nome),
                  subtitle: Text([
                    if (h.estrelas != null) h.estrelas!,
                    if (h.nota != null) '★ ${h.nota!.toStringAsFixed(1).replaceAll('.', ',')}'
                        '${h.avaliacoes != null ? ' (${h.avaliacoes})' : ''}',
                    _km(h.distM),
                  ].join(' · ')),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(h.preco != null ? formatMoney(h.preco!.toDouble()).replaceAll(',00', '') : '—',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: barato ? Colors.green.shade700 : null)),
                    Text(tr('/noite'), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  onTap: () => _opcoesHotel(h),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  void _opcoesHotel(Hotel h) => showSafeSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(h.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([if (h.endereco != null) h.endereco!, _km(h.distM)].join(' · ')),
            ),
            ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: Text(tr('Comparar ofertas e reservar')),
              subtitle: Text(tr('Booking, Decolar, Hoteis.com e outras')),
              onTap: () {
                Navigator.pop(ctx);
                _abre(_svc.ofertasHotel(h, _cidade, _noite));
              },
            ),
            if (widget.onAddStop != null)
              ListTile(
                leading: const Icon(Icons.add_location_alt),
                title: Text(tr('Adicionar como parada')),
                onTap: () => _adicionar(h.nome, h.lat, h.lng, StopType.overnight),
              ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: Text(tr('Navegar')),
              onTap: () {
                Navigator.pop(ctx);
                _navegar(h.lat, h.lng);
              },
            ),
          ]),
        ),
      );

  // -------------------------------- Postos --------------------------------

  String _preco(double v) => formatMoney(v);

  Widget _postosTab() => FutureBuilder<List<PostoRota>>(
        future: _postos,
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) return _carregando();
          final l = (s.data ?? const <PostoRota>[]).take(80).toList();
          return FutureBuilder<List<PrecoAnp>>(
            future: _precosCidade,
            builder: (_, sp) {
              final anp = sp.data ?? const <PrecoAnp>[];
              if (l.isEmpty && anp.isEmpty) {
                return _vazio(Icons.local_gas_station_outlined, tr('Nenhum posto no mapa por aqui.'),
                    retry: () => setState(() {
                          _postos = _svc.postos(widget.lat, widget.lng);
                          _precosCidade = _svc.precosCidade(widget.lat, widget.lng);
                        }));
              }
              return ListView(children: [
                if (anp.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: ExpansionTile(
                      leading: const Icon(Icons.price_check),
                      title: Text(tr('Gasolina mais barata em {0}: {1}',
                          [anp.first.cidade, _preco(anp.first.gasolina!)])),
                      subtitle: Text(tr('Pesquisa da ANP · {0}', [_svc.semanaAnp])),
                      children: [
                        for (final a in anp.take(15))
                          ListTile(
                            dense: true,
                            title: Text(a.nome.isEmpty ? a.bandeira : a.nome),
                            subtitle: Text('${a.rua}, ${a.numero} · ${a.bandeira}'),
                            trailing: Text(_preco(a.gasolina!), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                for (final p in l) _posto(p),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('Preço da pesquisa semanal da ANP, quando o posto foi pesquisado. Pode ter mudado.'),
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ]);
            },
          );
        },
      );

  Widget _posto(PostoRota p) {
    final g = p.preco?.gasolina, e = p.preco?.precos['e'];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: p.famoso ? Colors.orange.shade100 : null,
        child: Text(p.famoso ? '🏍️' : '⛽'),
      ),
      title: Text(p.nome),
      subtitle: Text([
        if (p.famoso) tr('Famoso entre motociclistas'),
        if (p.bandeira != null && p.bandeira != p.nome) p.bandeira!,
        _km(p.distM),
        if (p.restaurante) tr('restaurante'),
      ].join(' · ')),
      trailing: g == null && e == null
          ? null
          : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (g != null) Text('G ${_preco(g)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (e != null) Text('E ${_preco(e)}', style: Theme.of(context).textTheme.bodySmall),
            ]),
      onTap: () => showSafeSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              title: Text(p.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([if (p.rua != null) p.rua!, _km(p.distM)].join(' · ')),
            ),
            if (widget.onAddStop != null)
              ListTile(
                leading: const Icon(Icons.add_location_alt),
                title: Text(tr('Adicionar como parada')),
                onTap: () => _adicionar(p.nome, p.lat, p.lng, StopType.fuel),
              ),
            ListTile(
              leading: const Icon(Icons.navigation_outlined),
              title: Text(tr('Navegar')),
              onTap: () {
                Navigator.pop(ctx);
                _navegar(p.lat, p.lng);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
