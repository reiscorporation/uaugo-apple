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
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final best = _parse(j['trip'] as Map<String, dynamic>);
      if (best == null) return null;
      lastUsed = true;
      final alts = <RouteResult>[
        for (final a in (j['alternates'] as List? ?? const []))
          if (_parse((a as Map)['trip'] as Map<String, dynamic>) case final r?) r
      ]..sort((a, b) => a.durationS.compareTo(b.durationS));
      return RouteResult(best.polyline, best.legs, best.legSteps, 0,
          best.hasToll, best.summary, alternatives ? alts : const []);
    } catch (_) {
      return null;
    }
  }

  /// Converte a viagem do Valhalla para o formato do app.
  static RouteResult? _parse(Map<String, dynamic> trip) {
    final legsJ = (trip['legs'] as List).cast<Map<String, dynamic>>();
    final legs = <RouteLeg>[];
    final steps = <List<NavStep>>[];
    final path = <LatLng>[];
    final names = <String, double>{};
    for (final (li, l) in legsJ.indexed) {
      final shape = decodePolyline6(l['shape'] as String);
      final s = l['summary'] as Map<String, dynamic>;
      legs.add(RouteLeg(((s['length'] as num) * 1000).round(),
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
    final m = RegExp(r'^Enter (.+?) and take the (\d+)\S* exit(?: onto (.+?))?\.?$').firstMatch(t);
    if (m == null) return t;
    final to = m[3] == null ? '' : ' para ${m[3]}';
    return 'Na rotatória ${m[1]}, pegue a ${m[2]}ª saída$to.';
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
