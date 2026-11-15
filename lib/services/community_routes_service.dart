// ============================================================================
// community_routes_service.dart — Rotas salvas na Comunidade UauGo
//
// O que faz: Busca as rotas que o piloto salvou no planejador do site
//   uaugo.com.br/viagem (coleção "rotas" do PocketBase em api.uaugo.com.br).
//   Login: o token do Firebase (mesma conta do app) é trocado por uma sessão
//   da comunidade em uaugo.com.br/api/auth/firebase.
// Quem usa: HomeScreen (botão "Rotas da comunidade").
// Onde mexer: Endereços nas constantes abaixo; formato dos pontos =
//   [{nome, lat, lng, tipo: origem|parada|destino}].
// ============================================================================

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../logic/shared_place.dart' show RoutePoint;

/// Uma rota salva no site: paradas (na ordem) e o destino. A origem salva
/// fica de fora: a saída é sempre a posição atual do celular.
class CommunityRoute {
  final String id;
  final String name;
  final List<RoutePoint> stops;
  final RoutePoint destination;
  final double km;
  const CommunityRoute(this.id, this.name, this.stops, this.destination, this.km);
}

/// Erro com mensagem pronta para mostrar ao piloto.
class CommunityRoutesError implements Exception {
  final String message;
  const CommunityRoutesError(this.message);
}

class CommunityRoutesService {
  static const _site = 'https://uaugo.com.br';
  static const _api = 'https://api.uaugo.com.br';

  static String? _token;
  static String? _userId;

  /// Sessão da comunidade (token do PocketBase), também para os posts.
  static Future<String> session() => _session();

  /// Id do piloto na comunidade (depois de [session]).
  static String? get userId => _userId;

  /// Sessão venceu (401/403): entra de novo na próxima chamada.
  static void dropSession() => _token = null;

  /// Sessão da comunidade a partir do login do app (Firebase).
  static Future<String> _session() async {
    if (_token case final t?) return t;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) {
      throw const CommunityRoutesError('Entre com a sua conta no app (a mesma do site) para ver as rotas.');
    }
    final idToken = await u.getIdToken();
    final res = await http
        .post(Uri.parse('$_site/api/auth/firebase'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 403) {
      throw const CommunityRoutesError('Confirme o seu e-mail para usar a comunidade.');
    }
    if (res.statusCode != 200) {
      throw const CommunityRoutesError('Não foi possível entrar na comunidade agora.');
    }
    final body = jsonDecode(res.body) as Map;
    _userId = (body['user'] as Map?)?['id'] as String?;
    return _token = body['token'] as String;
  }

  /// Rotas do piloto, as mais recentes primeiro.
  static Future<List<CommunityRoute>> mine() async {
    try {
      final token = await _session();
      final res = await http.get(
          Uri.parse('$_api/api/collections/rotas/records?sort=-created&perPage=50'),
          headers: {'Authorization': token}).timeout(const Duration(seconds: 15));
      if (res.statusCode == 401 || res.statusCode == 403) {
        _token = null; // sessão venceu: entra de novo na próxima
        throw const CommunityRoutesError('Sessão da comunidade expirou. Tente de novo.');
      }
      if (res.statusCode != 200) {
        throw const CommunityRoutesError('Não foi possível buscar as rotas agora.');
      }
      final items = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['items'] as List)
          .cast<Map<String, dynamic>>();
      return [for (final r in items) if (parse(r) case final c?) c];
    } on CommunityRoutesError {
      rethrow;
    } catch (_) {
      throw const CommunityRoutesError('Sem conexão com a comunidade. Confira a internet.');
    }
  }

  /// Registro do PocketBase → rota (null se não tiver destino válido).
  static CommunityRoute? parse(Map<String, dynamic> r) {
    final pts = <(RoutePoint, String)>[];
    for (final p in (r['pontos'] as List? ?? const [])) {
      if (p is! Map) continue;
      final lat = (p['lat'] as num?)?.toDouble(), lng = (p['lng'] as num?)?.toDouble();
      if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) continue;
      pts.add((RoutePoint(lat, lng, '${p['nome'] ?? ''}'.trim()), '${p['tipo'] ?? ''}'));
    }
    // sem "tipo": o primeiro é a origem e o último o destino
    final hasTypes = pts.any((p) => p.$2.isNotEmpty);
    final rest = [
      for (final (i, p) in pts.indexed)
        if (hasTypes ? p.$2 != 'origem' : i > 0) p.$1,
    ];
    if (rest.isEmpty) return null;
    return CommunityRoute(
      '${r['id']}',
      '${r['nome'] ?? ''}'.trim().isEmpty ? rest.last.name : '${r['nome']}'.trim(),
      rest.sublist(0, rest.length - 1),
      rest.last,
      (r['km'] as num?)?.toDouble() ?? 0,
    );
  }
}
