// ============================================================================
// community_post_service.dart — Postar a viagem na Comunidade UauGo
//
// O que faz: Lista onde o piloto pode postar (feed geral e as tribos em que
//   ele é membro ativo) e os posts dele (para ligar o novo a um da viagem),
//   envia a imagem/GIF para o armazenamento da comunidade (uaugo.com.br/api/
//   upload -> R2) e cria o post (coleção "posts" do PocketBase).
// Quem usa: widgets/community_post_sheet.dart.
// Onde mexer: Endereços em CommunityRoutesService; regras no site
//   (pb_migrations/…_comunidade.js e src/app/api/upload).
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'community_routes_service.dart';

/// Onde postar: tribo (id) ou o feed geral (id vazio).
class CommunityTarget {
  final String id;
  final String name;
  final String slug;
  const CommunityTarget(this.id, this.name, [this.slug = '']);
}

/// Um post do piloto (para ligar o novo a ele).
class MyPost {
  final String id;
  final String text;
  final DateTime created;
  const MyPost(this.id, this.text, this.created);
}

class CommunityPostService {
  static const site = 'https://uaugo.com.br';
  static const _api = 'https://api.uaugo.com.br';

  static Future<Map<String, String>> _auth() async =>
      {'Authorization': await CommunityRoutesService.session()};

  static Never _fail(http.Response res, String msg) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      CommunityRoutesService.dropSession();
      throw const CommunityRoutesError('Sessão da comunidade expirou. Tente de novo.');
    }
    throw CommunityRoutesError(msg);
  }

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on CommunityRoutesError {
      rethrow;
    } catch (_) {
      throw const CommunityRoutesError('Sem conexão com a comunidade. Confira a internet.');
    }
  }

  /// Feed geral + tribos em que o piloto é membro ativo.
  static Future<List<CommunityTarget>> targets() => _guard(() async {
        final h = await _auth();
        final me = CommunityRoutesService.userId ?? '';
        final filter = Uri.encodeQueryComponent("usuario='$me' && status='ativo'");
        final res = await http.get(
            Uri.parse('$_api/api/collections/membros/records?filter=$filter&expand=tribo&perPage=100'),
            headers: h).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) _fail(res, 'Não foi possível buscar as suas tribos.');
        final items = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['items'] as List)
            .cast<Map<String, dynamic>>();
        return [
          const CommunityTarget('', 'Feed geral'),
          for (final m in items)
            if ((m['expand'] as Map?)?['tribo'] case final Map t)
              CommunityTarget('${t['id']}', '${t['nome']}', '${t['slug'] ?? ''}'),
        ];
      });

  /// Posts do piloto, os mais recentes primeiro.
  static Future<List<MyPost>> myPosts() => _guard(() async {
        final h = await _auth();
        final me = CommunityRoutesService.userId ?? '';
        final filter = Uri.encodeQueryComponent("autor='$me'");
        final res = await http.get(
            Uri.parse('$_api/api/collections/posts/records?filter=$filter&sort=-created&perPage=20'),
            headers: h).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) _fail(res, 'Não foi possível buscar os seus posts.');
        final items = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['items'] as List)
            .cast<Map<String, dynamic>>();
        return [
          for (final p in items)
            MyPost('${p['id']}', '${p['texto'] ?? ''}'.trim(),
                DateTime.tryParse('${p['created']}') ?? DateTime.now()),
        ];
      });

  /// Envia a imagem (JPEG/WebP) ou o GIF e devolve o endereço público.
  static Future<String> upload(Uint8List bytes, String mime) => _guard(() async {
        final token = await CommunityRoutesService.session();
        final res = await http
            .post(Uri.parse('$site/api/upload'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
                body: jsonEncode({'tipo': mime, 'tamanho': bytes.length}))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 400) {
          throw CommunityRoutesError(mime == 'image/gif'
              ? 'A comunidade ainda não aceita GIF (ou ele ficou grande demais).'
              : 'Imagem grande demais para a comunidade.');
        }
        if (res.statusCode != 200) _fail(res, 'Não foi possível enviar a imagem.');
        final j = jsonDecode(res.body) as Map;
        final up = await http
            .put(Uri.parse('${j['uploadUrl']}'), headers: {'Content-Type': mime}, body: bytes)
            .timeout(const Duration(seconds: 90));
        if (up.statusCode >= 300) throw const CommunityRoutesError('Falha ao enviar a imagem.');
        return '${j['publicUrl']}';
      });

  /// Cria o post e devolve o endereço dele no site.
  static Future<String> create({
    required CommunityTarget target,
    required String text,
    required List<String> media,
    String? relatedPostId,
  }) =>
      _guard(() async {
        final h = await _auth();
        final res = await http
            .post(Uri.parse('$_api/api/collections/posts/records'),
                headers: {...h, 'Content-Type': 'application/json'},
                body: jsonEncode({
                  'autor': CommunityRoutesService.userId,
                  'tribo': target.id,
                  'tipo': 'roteiro',
                  // Post da viagem escolhido: o endereço dele vai no texto (o
                  // campo "link" do site só aparece com prévia assinada).
                  'texto': relatedPostId == null
                      ? text.trim()
                      : '${text.trim()}\n\n↪ $site/post/$relatedPostId',
                  'fotos': media,
                }))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) _fail(res, 'Não foi possível publicar o post.');
        final id = (jsonDecode(res.body) as Map)['id'];
        // Página nova aparece já (o site guarda em cache).
        http
            .post(Uri.parse('$site/api/revalidar'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'caminhos': ['/', if (target.slug.isNotEmpty) '/tribos/${target.slug}'],
                }))
            .catchError((_) => http.Response('', 500));
        return '$site/post/$id';
      });
}
