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
              // Paradas no meio passam pelo ponto (sem "chegou" falso).
              'type': i == 0 || i == points.length - 1 ? 'break' : 'through',
            }
        ],
        'costing': costing,
        'costing_options': {
          costing: {
            if (shortest) 'shortest': true,
            if (avoidTolls) 'use_tolls': 0.0,
            if (avoidHighways) 'use_highways': 0.0,
            if (avoidFerries) 'use_ferry': 0.0,
          }
        },
        'language': I18n.isEn ? 'en-US' : 'pt-BR',
        'directions_options': {'units': 'kilometers'},
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
    for (final l in legsJ) {
      final shape = decodePolyline6(l['shape'] as String);
      final s = l['summary'] as Map<String, dynamic>;
      legs.add(RouteLeg(((s['length'] as num) * 1000).round(),
          (s['time'] as num).round()));
      final ls = <NavStep>[];
      for (final m in (l['maneuvers'] as List).cast<Map<String, dynamic>>()) {
        final idx = (m['begin_shape_index'] as num).toInt().clamp(0, shape.length - 1);
        final at = shape[idx];
        final type = (m['type'] as num).toInt();
        // Rua mais longa da rota = "via ..." na escolha de rota.
        for (final n in (m['street_names'] as List? ?? const [])) {
          names[n as String] = (names[n] ?? 0) + ((m['length'] as num?)?.toDouble() ?? 0);
        }
        final text = (m['instruction'] as String? ?? '').trim();
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
