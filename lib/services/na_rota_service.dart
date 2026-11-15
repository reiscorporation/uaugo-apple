// ============================================================================
// na_rota_service.dart — Turismo, hospedagem e postos perto de uma parada
//
// O que faz: Baixa (uma vez por versão) os arquivos do estado com atrações e
//   postos (public/turismo/UF.json.gz) e preços da ANP
//   (public/combustivel/UF.json.gz); busca hotéis na página do Google pelo
//   próprio celular (scraping, sem API) e os detalhes da atração na
//   Wikipédia/Wikidata (grátis).
// Quem usa: NaRotaScreen.
// Onde mexer: gerador no servidor em functions/turismo.js; leitura dos
//   dados em lib/logic/na_rota.dart.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/na_rota.dart';

/// Detalhes da atração (Wikipédia): resumo, foto e página completa.
class DetalheAtracao {
  final String? resumo, foto, pagina;
  const DetalheAtracao({this.resumo, this.foto, this.pagina});
}

class NaRotaService {
  NaRotaService._();
  static final instance = NaRotaService._();

  static const _ua = 'UauGo/1.2 (app de viagens de moto; helpaitech.com.br)';
  static const _uaCelular = 'Mozilla/5.0 (Linux; Android 14; SM-A145M) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';

  final Map<String, ({List<Atracao> a, List<PostoRota> f})> _turismo = {};
  final Map<String, List<PrecoAnp>> _anp = {};
  final Map<String, String> _semana = {};
  final Map<String, List<Hotel>> _hoteis = {};
  final Map<String, DetalheAtracao> _detalhes = {};
  final Map<String, String?> _cidades = {};
  Map<String, dynamic>? _metaTur, _metaAnp;

  Future<void> _meta() async {
    if (_metaTur != null) return;
    try {
      final r = await Future.wait([
        FirebaseFirestore.instance.doc('meta/turismo').get(),
        FirebaseFirestore.instance.doc('meta/combustivel').get(),
      ]);
      _metaTur = (r[0].data()?['ufs'] as Map?)?.cast<String, dynamic>() ?? {};
      _metaAnp = (r[1].data()?['ufs'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (e) {
      debugPrint('Na rota: sem índice ($e)');
    }
  }

  /// O círculo (lat, lng, raio) encosta no retângulo do estado?
  static bool _toca(double lat, double lng, double km, List b) {
    final dLat = km / 111.0, dLng = km / 100.0;
    return lat + dLat >= (b[0] as num) &&
        lat - dLat <= (b[2] as num) &&
        lng + dLng >= (b[1] as num) &&
        lng - dLng <= (b[3] as num);
  }

  /// Arquivo do estado no celular, baixando se a versão mudou.
  Future<Map<String, dynamic>?> _arquivo(String pasta, String uf, int? version) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/${pasta}_$uf.json.gz');
    final prefs = await SharedPreferences.getInstance();
    final k = 'naRota_${pasta}_$uf';
    Uint8List? bytes;
    if (await file.exists() && prefs.getInt(k) == version) {
      bytes = await file.readAsBytes();
    } else {
      bytes = await FirebaseStorage.instance.ref('public/$pasta/$uf.json.gz').getData(10 * 1024 * 1024);
      if (bytes == null) return null;
      await file.writeAsBytes(bytes, flush: true);
      if (version != null) await prefs.setInt(k, version);
    }
    return compute(_decode, bytes);
  }

  /// Carrega os estados que o círculo toca (turismo, postos e preços).
  Future<void> _carrega(double lat, double lng, double km) async {
    await _meta();
    final jobs = <Future>[];
    for (final e in (_metaTur ?? const {}).entries) {
      final info = e.value as Map?;
      final box = info?['bbox'];
      if (box is! List || !_toca(lat, lng, km, box) || _turismo.containsKey(e.key)) continue;
      jobs.add(() async {
        final j = await _arquivo('turismo', e.key, (info?['version'] as num?)?.toInt());
        if (j == null) return;
        _turismo[e.key] = (
          a: [for (final l in (j['a'] as List? ?? const [])) Atracao.fromList(l as List)],
          f: [for (final l in (j['f'] as List? ?? const [])) PostoRota.fromList(l as List)],
        );
        // Preços da ANP do mesmo estado.
        final anp = _metaAnp?[e.key] as Map?;
        if (anp != null && !_anp.containsKey(e.key)) {
          final p = await _arquivo('combustivel', e.key, (anp['version'] as num?)?.toInt());
          if (p != null) {
            _anp[e.key] = [for (final l in (p['p'] as List? ?? const [])) PrecoAnp.fromList(l as List)];
            _semana[e.key] = p['semana'] as String? ?? '';
          }
        }
      }().catchError((Object err) => debugPrint('Na rota ${e.key}: $err')));
    }
    await Future.wait(jobs);
  }

  /// Atrações a até [km] do ponto, sem repetidas, da mais perto para a mais
  /// longe.
  Future<List<Atracao>> atracoes(double lat, double lng, {double km = 50}) async {
    await _carrega(lat, lng, km);
    final out = <Atracao>[];
    for (final t in _turismo.values) {
      for (final a in t.a) {
        final d = distM(lat, lng, a.lat, a.lng);
        if (d <= km * 1000) out.add(a..distM = d);
      }
    }
    return semRepetidas(out);
  }

  /// Postos a até [km]: os famosos entre motociclistas primeiro, depois por
  /// distância; com o preço da ANP quando acha o mesmo posto.
  Future<List<PostoRota>> postos(double lat, double lng, {double km = 50}) async {
    await _carrega(lat, lng, km);
    final cidade = await cidadeDe(lat, lng);
    final anp = [for (final l in _anp.values) ...l];
    final out = <PostoRota>[];
    for (final t in _turismo.values) {
      for (final f in t.f) {
        final d = distM(lat, lng, f.lat, f.lng);
        if (d > km * 1000) continue;
        // Cidade da parada só vale para postos perto dela (até 8 km).
        f.preco = casaPreco(f, d < 8000 ? cidade?.split(',').first : null, anp);
        out.add(f..distM = d);
      }
    }
    out.sort((x, y) => x.famoso != y.famoso ? (x.famoso ? -1 : 1) : x.distM.compareTo(y.distM));
    return out;
  }

  /// Postos da pesquisa da ANP na cidade da parada (todos os combustíveis;
  /// a tela separa o mais barato de cada um).
  Future<List<PrecoAnp>> precosCidade(double lat, double lng) async {
    await _carrega(lat, lng, 10);
    final c = normaliza((await cidadeDe(lat, lng))?.split(',').first ?? '');
    if (c.isEmpty) return const [];
    return [
      for (final l in _anp.values)
        for (final a in l)
          if (normaliza(a.cidade) == c && a.precos.isNotEmpty) a
    ];
  }

  /// Raio do turismo escolhido pelo piloto (km), guardado no aparelho.
  static const raiosTurismo = [10, 25, 50, 100, 200];

  Future<int> raioTurismo() async {
    final v = (await SharedPreferences.getInstance()).getInt('naRotaRaioTurismo');
    return raiosTurismo.contains(v) ? v! : 50;
  }

  Future<void> salvaRaioTurismo(int km) async =>
      (await SharedPreferences.getInstance()).setInt('naRotaRaioTurismo', km);

  /// Ordem do turismo escolhida pelo piloto: true = mais conhecidas primeiro.
  Future<bool> turismoPorConhecidas() async =>
      (await SharedPreferences.getInstance()).getBool('naRotaTurismoConhecidas') ?? false;

  Future<void> salvaTurismoPorConhecidas(bool v) async =>
      (await SharedPreferences.getInstance()).setBool('naRotaTurismoConhecidas', v);

  /// Semana da pesquisa da ANP carregada (para mostrar a data).
  String get semanaAnp => _semana.values.firstOrNull ?? '';

  /// "Cidade, UF" do ponto (cache por região de ~1 km).
  Future<String?> cidadeDe(double lat, double lng) async {
    final k = '${(lat * 100).round()}_${(lng * 100).round()}';
    if (_cidades.containsKey(k)) return _cidades[k];
    String? r;
    try {
      final p = (await placemarkFromCoordinates(lat, lng)).firstOrNull;
      final c = [p?.subAdministrativeArea, p?.locality].firstWhere((s) => s != null && s.isNotEmpty,
          orElse: () => null);
      if (c != null) r = '$c, ${p?.administrativeArea ?? ''}'.replaceAll(RegExp(r', $'), '');
    } catch (e) {
      debugPrint('Na rota: cidade de $lat,$lng falhou ($e)');
    }
    return _cidades[k] = r;
  }

  /// Hotéis perto do ponto para a noite [noite], mais barato primeiro. Lê a
  /// página de hotéis do Google (que junta Booking, Decolar, Hoteis.com...).
  /// Lança erro se não conseguiu ler (sem internet ou formato novo).
  Future<List<Hotel>> hoteis(double lat, double lng, DateTime noite) async {
    final lugar = await cidadeDe(lat, lng) ?? '$lat,$lng';
    final key = '$lugar|${noite.year}-${noite.month}-${noite.day}';
    final cached = _hoteis[key];
    if (cached != null) return cached;
    final uri = googleHoteisUri(lugar, noite);
    debugPrint('Hotéis: buscando $uri');
    final res = await http.get(uri, headers: {
      'User-Agent': _uaCelular,
      'Accept-Language': 'pt-BR,pt;q=0.9',
    }).timeout(const Duration(seconds: 25));
    final html = utf8.decode(res.bodyBytes, allowMalformed: true);
    final list = res.statusCode == 200 ? await compute(parseHoteisGoogle, html) : const <Hotel>[];
    if (list.isEmpty) {
      // No log: o que o Google devolveu (para ajustar a leitura da página).
      final title = RegExp(r'<title>([^<]*)').firstMatch(html)?.group(1);
      debugPrint('Hotéis: falhou HTTP ${res.statusCode}, ${html.length} bytes, '
          'título "$title", url ${res.request?.url}');
      throw FormatException('sem hotéis na página (HTTP ${res.statusCode})');
    }
    for (final h in list) {
      h.distM = distM(lat, lng, h.lat, h.lng);
    }
    list.sort((a, b) => (a.preco ?? 1 << 30).compareTo(b.preco ?? 1 << 30));
    return _hoteis[key] = list;
  }

  /// Página de ofertas do hotel (todas as agências), na mesma noite.
  Uri ofertasHotel(Hotel h, String? cidade, DateTime noite) =>
      googleHoteisUri('${h.nome}${cidade != null ? ', $cidade' : ''}', noite);

  /// Resumo, foto e link da atração (Wikipédia; sem artigo, só a foto).
  Future<DetalheAtracao> detalhes(Atracao a) async {
    final k = '${a.nome}|${a.lat}';
    final c = _detalhes[k];
    if (c != null) return c;
    String? titulo, lang = 'pt', foto = _fotoUrl(a.foto);
    if (a.wiki != null) {
      final i = a.wiki!.indexOf(':');
      if (i > 0 && i < 4) {
        lang = a.wiki!.substring(0, i);
        titulo = a.wiki!.substring(i + 1);
      } else {
        titulo = a.wiki;
      }
    }
    try {
      if (a.wikidata != null && (titulo == null || foto == null)) {
        final r = await http.get(
            Uri.https('www.wikidata.org', '/wiki/Special:EntityData/${a.wikidata}.json'),
            headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          final e = ((jsonDecode(r.body)['entities'] as Map).values.first) as Map;
          final links = e['sitelinks'] as Map? ?? const {};
          if (titulo == null) {
            final pt = links['ptwiki']?['title'] as String?;
            if (pt != null) {
              titulo = pt;
              lang = 'pt';
            } else if (links['enwiki'] != null) {
              titulo = links['enwiki']['title'] as String;
              lang = 'en';
            }
          }
          final img = ((e['claims'] as Map?)?['P18'] as List?)?.firstOrNull?['mainsnak']?['datavalue']?['value'];
          if (foto == null && img is String) foto = _fotoUrl('File:$img');
        }
      }
      if (titulo != null) {
        // O Uri já codifica o título: codificar antes dava "%25C3..." e a
        // Wikipédia respondia 404 em todo título com acento (sem foto/resumo).
        final r = await http.get(
            Uri(scheme: 'https', host: '$lang.wikipedia.org',
                pathSegments: ['api', 'rest_v1', 'page', 'summary', titulo.replaceAll(' ', '_')]),
            headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
          final d = DetalheAtracao(
            resumo: j['extract'] as String?,
            foto: _fotoWiki(j) ?? foto,
            pagina: j['content_urls']?['mobile']?['page'] as String?,
          );
          return _detalhes[k] = d;
        }
        debugPrint('Na rota: Wikipédia ${r.statusCode} para "$titulo"');
      }
    } catch (e) {
      debugPrint('Na rota: detalhes de ${a.nome} falharam ($e)');
    }
    return _detalhes[k] = DetalheAtracao(resumo: a.descricao, foto: foto);
  }

  /// Foto do resumo da Wikipédia em 960 px (tamanho padrão do Wikimedia;
  /// outros dão 400). A original pode ter vários MB.
  static String? _fotoWiki(Map j) {
    final th = j['thumbnail']?['source'] as String?;
    if (th != null && RegExp(r'/\d+px-').hasMatch(th)) {
      final w = (j['originalimage']?['width'] as num?)?.toInt() ?? 0;
      if (w > 960) return th.replaceFirst(RegExp(r'/\d+px-'), '/960px-');
      return j['originalimage']?['source'] as String? ?? th;
    }
    return j['originalimage']?['source'] as String? ?? th;
  }

  /// Foto do mapa: URL direta ou arquivo do Wikimedia Commons.
  static String? _fotoUrl(String? f) {
    if (f == null || f.isEmpty) return null;
    if (f.startsWith('http')) return f;
    final name = f.replaceFirst(RegExp(r'^(File|Arquivo|Category):'), '');
    if (f.startsWith('Category:')) return null;
    return 'https://commons.wikimedia.org/wiki/Special:FilePath/${Uri.encodeComponent(name)}?width=960';
  }

  /// "Ver mais" sem artigo: busca o lugar na internet.
  Uri buscaWeb(Atracao a, String? cidade) => Uri.https('www.google.com', '/search',
      {'q': '${a.nome} ${a.cidade ?? cidade ?? ''}'.trim(), 'hl': 'pt-BR'});
}

Map<String, dynamic> _decode(Uint8List b) =>
    jsonDecode(utf8.decode(gzip.decode(b))) as Map<String, dynamic>;
