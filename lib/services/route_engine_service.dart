// ============================================================================
// route_engine_service.dart — Motor de rotas próprio (Valhalla), na VPS
//
// O que faz: Calcula a rota no motor do UauGo (Valhalla + mapa aberto do
//   OpenStreetMap) em vez do Google: traçado, trechos, manobras faladas em
//   português, pedágio e rotas alternativas. Moto usa o perfil de moto
//   (evita vias proibidas para moto, quando o mapa marca).
// Quem usa: DirectionsService (só quando o app é gerado com
//   ROUTE_ENGINE e ROUTE_ENGINE_KEY em config/dart_defines.json; senão, Google).
// Onde mexer: plano em docs/PLANO-MOTOR-ROTAS.md. Se o motor falhar, o
//   DirectionsService volta para o Google.
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../l10n/i18n.dart';
import '../logic/geo.dart';
import '../logic/navigation.dart';
import '../logic/risk_areas.dart';
import 'directions_service.dart';
import 'profile_service.dart';

class RouteEngineService {
  RouteEngineService._();

  /// Endereço do motor nesta versão (vazio = usa o Google).
  static const url = String.fromEnvironment('ROUTE_ENGINE');
  static bool get enabled => url.isNotEmpty;

  /// Chave que o Caddy da VPS exige (sem ela, o motor responde 403).
  static const _key = String.fromEnvironment('ROUTE_ENGINE_KEY');
  static const _auth = {'X-Motor-Key': _key};

  /// Peso da distância na escolha: sem ele, o motor dava voltas para ficar em
  /// vias mais rápidas (9 de 37 viagens com desvio; com 0,25, 2 e sem mais
  /// terra). Comparação: E:/UauGo-motor/calibrar.py.
  static const _useDistance = 0.25;

  /// As velocidades do motor dão tempos 22% maiores que os do Google.
  static const _timeScale = 0.82;

  /// Lado (graus) dos quadrados de [riskAreas].
  static double areaSide = 250 / 111320;

  static (DateTime, List<(double, double)>)? _areas;

  /// Quadrados com muitos roubos, do mais crítico ao menos (dados públicos,
  /// scripts/areas-risco.py). Guarda por 6 h; vazio se não conseguir baixar.
  static Future<List<(double, double)>> riskAreas() async {
    final c = _areas;
    if (c != null && DateTime.now().difference(c.$1).inHours < 6) return c.$2;
    if (!enabled) return const [];
    try {
      final r = await http
          .get(Uri.parse('$url/areas'), headers: _auth)
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return c?.$2 ?? const [];
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      areaSide = (j['lado'] as num).toDouble();
      final list = <(double, double)>[
        for (final a in (j['c'] as List).cast<List>())
          ((a[0] as num).toDouble(), (a[1] as num).toDouble())
      ];
      _areas = (DateTime.now(), list);
      return list;
    } catch (_) {
      return c?.$2 ?? const [];
    }
  }

  /// A última rota veio do motor próprio (true) ou caiu no Google (false).
  static bool lastUsed = false;

  /// Motor fora de alcance (ex.: no 4G, longe do Wi-Fi do servidor de teste):
  /// não tenta de novo até esta hora, para não atrasar a rota pelo Google.
  static DateTime _skipUntil = DateTime(0);

  /// Pergunta rápida (2 s) se o motor responde antes de pedir a rota.
  static Future<bool> _alive() async {
    try {
      final r = await http
          .get(Uri.parse('$url/status'), headers: _auth)
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Rota pelos [points] (saída, paradas, destino). null = falhou.
  static Future<RouteResult?> route(
    List<LatLng> points, {
    required bool avoidTolls,
    required bool avoidHighways,
    bool avoidFerries = false,
    bool shortest = false,
    bool alternatives = false,
    List<(double, double)> avoid = const [],
  }) async {
    if (DateTime.now().isBefore(_skipUntil)) return null;
    if (!await _alive()) {
      debugPrint('Motor: sem resposta em 2 s, usando o Google');
      _skipUntil = DateTime.now().add(const Duration(minutes: 2));
      return null;
    }
    try {
      final moto = (await ProfileService.load()).style.isMoto;
      final costing = moto ? 'motorcycle' : 'auto';
      final body = {
        'locations': [
          for (var i = 0; i < points.length; i++)
            {
              'lat': points[i].latitude,
              'lon': points[i].longitude,
              // Parada no meio: divide a rota em trechos, um por parada (o
              // app conta com isso; "through" juntava tudo num trecho só e a
              // rota com parada falhava), sem fazer retorno no ponto.
              'type': i == 0 || i == points.length - 1 ? 'break' : 'break_through',
            }
        ],
        'costing': costing,
        'costing_options': {
          costing: {
            if (shortest) 'shortest': true else 'use_distance': _useDistance,
            if (avoidTolls) 'use_tolls': 0.0,
            if (avoidHighways) 'use_highways': 0.0,
            if (avoidFerries) 'use_ferry': 0.0,
          }
        },
        'language': I18n.isEn ? 'en-US' : 'pt-BR',
        'directions_options': {'units': 'kilometers'},
        if (avoid.isNotEmpty) 'exclude_polygons': avoidPolygons(avoid, areaSide),
        if (alternatives && points.length == 2) 'alternates': 2,
      };
      final res = await http
          .post(Uri.parse('$url/route'),
              headers: {'Content-Type': 'application/json', ..._auth},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('Motor: rota ${res.statusCode}');
        return null;
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final trips = [
        j['trip'] as Map<String, dynamic>,
        for (final a in (j['alternates'] as List? ?? const []))
          (a as Map)['trip'] as Map<String, dynamic>,
      ];
      // Tempo de cada trecho somando via por via (igual ao site da comunidade);
      // se a medição falhar, fica o ajuste fixo [_timeScale].
      final byRoad = await Future.wait([
        for (final t in trips)
          Future.wait([
            for (final l in (t['legs'] as List).cast<Map<String, dynamic>>())
              _secondsByRoad(l['shape'] as String, costing),
          ]),
      ]);
      final best = _parse(trips[0], byRoad[0]);
      if (best == null) return null;
      lastUsed = true;
      final alts = <RouteResult>[
        for (var i = 1; i < trips.length; i++)
          if (_parse(trips[i], byRoad[i]) case final r?) r
      ]..sort((a, b) => a.durationS.compareTo(b.durationS));
      return RouteResult(best.polyline, best.legs, best.legSteps, 0,
          best.hasToll, best.summary, alternatives ? alts : const []);
    } catch (e) {
      debugPrint('Motor: rota falhou: $e');
      return null;
    }
  }

  /// Converte a viagem do Valhalla para o formato do app.
  /// Velocidade típica (km/h) por tipo de via quando o mapa não tem o limite.
  static const _typicalKmh = {
    'motorway': 105.0, 'trunk': 95.0, 'primary': 80.0, 'secondary': 65.0,
    'tertiary': 55.0, 'unclassified': 45.0, 'residential': 30.0,
    'service_other': 15.0,
  };

  /// Segundos de um trecho somando cada via a 95% do limite dela (ou pela
  /// velocidade típica do tipo). As velocidades próprias do motor davam
  /// tempo bem acima do real (RP→S. J. da Boa Vista: 2h38 contra ≤2h reais;
  /// assim fica ~2h05). Null se o motor não responder.
  static Future<int?> _secondsByRoad(String shape, String costing) async {
    try {
      final res = await http
          .post(Uri.parse('$url/trace_attributes'),
              headers: {'Content-Type': 'application/json', ..._auth},
              body: jsonEncode({
                'encoded_polyline': shape,
                'costing': costing,
                'shape_match': 'edge_walk',
                'filters': {
                  'attributes': ['edge.length', 'edge.speed_limit', 'edge.road_class'],
                  'action': 'include',
                },
              }))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final edges = ((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['edges'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (edges.isEmpty) return null;
      var h = 0.0;
      for (final e in edges) {
        final lim = (e['speed_limit'] as num?)?.toDouble() ?? 0;
        final v = lim > 0 ? lim * 0.95 : (_typicalKmh[e['road_class']] ?? 40.0);
        h += ((e['length'] as num?)?.toDouble() ?? 0) / v;
      }
      return (h * 3600).round();
    } catch (_) {
      return null;
    }
  }

  static RouteResult? _parse(Map<String, dynamic> trip, [List<int?>? byRoad]) {
    final legsJ = (trip['legs'] as List).cast<Map<String, dynamic>>();
    final legs = <RouteLeg>[];
    final steps = <List<NavStep>>[];
    final path = <LatLng>[];
    final names = <String, double>{};
    for (final (li, l) in legsJ.indexed) {
      final shape = decodePolyline6(l['shape'] as String);
      final s = l['summary'] as Map<String, dynamic>;
      legs.add(RouteLeg(((s['length'] as num) * 1000).round(),
          (byRoad != null && li < byRoad.length ? byRoad[li] : null) ??
              ((s['time'] as num) * _timeScale).round()));
      final ls = <NavStep>[];
      for (final m in (l['maneuvers'] as List).cast<Map<String, dynamic>>()) {
        final idx = (m['begin_shape_index'] as num).toInt().clamp(0, shape.length - 1);
        final at = shape[idx];
        final type = (m['type'] as num).toInt();
        // Rua mais longa da rota = "via ..." na escolha de rota.
        for (final n in (m['street_names'] as List? ?? const [])) {
          names[n as String] = (names[n] ?? 0) + ((m['length'] as num?)?.toDouble() ?? 0);
        }
        // Parada no meio: sem "o seu destino fica à esquerda" ao chegar nela
        // nem "dirija para oeste" ao sair (a rota continua).
        if (li < legsJ.length - 1 && type >= 4 && type <= 6) continue;
        if (li > 0 && type >= 1 && type <= 3) continue;
        final text = roundaboutText((m['instruction'] as String? ?? '').trim());
        if (text.isEmpty) continue;
        ls.add(NavStep(at.latitude, at.longitude, text, _maneuver(type)));
      }
      steps.add(ls);
      path.addAll(path.isEmpty ? shape : shape.skip(1));
    }
    if (path.length < 2) return null;
    final summary = (names.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => e.key)
        .take(1)
        .join();
    final hasToll = (trip['summary'] as Map?)?['has_toll'] == true;
    return RouteResult(encodePolyline(simplifyPolyline(path, 4)), legs, steps, 0,
        hasToll, summary);
  }

  /// O motor manda a entrada de rotatória em inglês mesmo no pedido em português.
  static String roundaboutText(String t) {
    if (I18n.isEn) return t;
    // Retorno: o motor manda meio em inglês ("Make a à esquerda U-turn
    // toward Aguai/São João.", teste de 06/11).
    final u = RegExp(r'^Make a (à esquerda|à direita|left|right) U-turn'
            r'(?: (?:onto|on) (.+?))?(?: toward (.+?))?\.?$')
        .firstMatch(t);
    if (u != null) {
      final side = u[1]!.contains('esq') || u[1] == 'left' ? 'à esquerda' : 'à direita';
      final on = u[2] == null ? '' : ' em ${u[2]}';
      final to = u[3] == null ? '' : ' em direção a ${u[3]}';
      return 'Faça o retorno $side$on$to.';
    }
    final m = RegExp(r'^Enter (.+?) and take the (\d+)\S* exit(?: onto (.+?))?\.?$').firstMatch(t);
    if (m == null) return mixedEnglishText(t);
    final to = m[3] == null ? '' : ' para ${m[3]}';
    // Rotatória sem nome no mapa: o motor manda "Enter the roundabout".
    final name = m[1]!.toLowerCase() == 'the roundabout' ? '' : ' ${m[1]}';
    return 'Na rotatória$name, pegue a ${m[2]}ª saída$to.';
  }

  /// Frase do motor que veio metade em inglês ("Turn à direita toward X",
  /// 13/11): troca as palavras em inglês que sobram. Frase toda em
  /// português passa sem mudança.
  static String mixedEnglishText(String t) {
    if (I18n.isEn) return t;
    if (!RegExp(r'\b(Turn|Bear|Keep|Make|Head|Take|toward|onto|slight|sharp|left|right|exit)\b')
        .hasMatch(t)) {
      return t;
    }
    var o = t;
    const side = {
      'slight right': 'levemente à direita', 'slight left': 'levemente à esquerda',
      'sharp right': 'acentuadamente à direita', 'sharp left': 'acentuadamente à esquerda',
      'right': 'à direita', 'left': 'à esquerda',
    };
    side.forEach((en, pt) => o = o.replaceAll(RegExp(r'\b' + en + r'\b'), pt));
    o = o
        .replaceAll(RegExp(r'^Make a (sharp|slight)\s+'), '')
        .replaceAll(RegExp(r'^Turn\b'), 'Vire')
        .replaceAll(RegExp(r'^(Bear|Keep)\b'), 'Mantenha-se')
        .replaceAll(RegExp(r'^Head\b'), 'Siga')
        .replaceAll(RegExp(r'^Take the exit\b'), 'Pegue a saída')
        .replaceAll(RegExp(r'^Take\b'), 'Pegue')
        .replaceAll(RegExp(r'\s+toward\s+'), ' em direção a ')
        .replaceAll(RegExp(r'\s+onto\s+'), ' para ')
        .replaceAll(RegExp(r'\bthe exit\b'), 'a saída')
        .replaceAll(RegExp(r'\bexit\b'), 'saída');
    return o;
  }

  /// Tipo de manobra do Valhalla -> o mesmo nome usado pelo Google no app.
  static String _maneuver(int t) => switch (t) {
        9 => 'turn-slight-right',
        10 => 'turn-right',
        11 => 'turn-sharp-right',
        12 => 'uturn-right',
        13 => 'uturn-left',
        14 => 'turn-sharp-left',
        15 => 'turn-left',
        16 => 'turn-slight-left',
        18 || 20 => 'ramp-right',
        19 || 21 => 'ramp-left',
        23 => 'keep-right',
        24 => 'keep-left',
        25 || 37 || 38 => 'merge',
        26 || 27 => 'roundabout-right',
        28 || 29 => 'ferry',
        _ => '',
      };

  /// Traçado do Valhalla (precisão de 6 casas).
  static List<LatLng> decodePolyline6(String s) {
    final out = <LatLng>[];
    var i = 0, lat = 0, lng = 0;
    while (i < s.length) {
      var shift = 0, result = 0, b = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = s.codeUnitAt(i++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      out.add(LatLng(lat / 1e6, lng / 1e6));
    }
    return out;
  }
}
