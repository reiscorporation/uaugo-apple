// ============================================================================
// directions_service.dart — Rotas do Google (Directions API)
//
// O que faz: Calcula a rota pelas estradas passando pelas paradas: traçado
//   detalhado (segue as curvas), tempo de cada trecho (com e sem trânsito),
//   manobras para a narração, pedágio, rotas alternativas (mais curta / evitar
//   áreas de risco).
// Quem usa: TripService, ExpeditionService (roteiro), MapScreen (recálculo,
//   trânsito).
// Onde mexer: Opções enviadas ao Google: _request. Custo: cada chamada é
//   cobrada.
// ============================================================================

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/geo.dart';
import '../logic/navigation.dart';
import '../logic/radars.dart' show nearestOnLine;
import '../logic/risk_areas.dart';
import '../logic/route_traffic.dart';
import 'app_settings.dart';
import 'hazard_service.dart';
import '../models/hazard.dart';
import 'route_engine_service.dart';
import '../l10n/i18n.dart';

/// Trecho entre dois pontos consecutivos do roteiro.
class RouteLeg {
  final int distanceM;

  /// Tempo previsto (com o trânsito do momento, se essa opção estiver ligada).
  final int durationS;

  /// Tempo típico da via, sem considerar o trânsito de agora.
  final int typicalS;
  const RouteLeg(this.distanceM, this.durationS, [int? typicalS])
      : typicalS = typicalS ?? durationS;
}

/// Resultado do cálculo: traçado, trechos (tempo e distância), manobras
/// para a narração, áreas de risco perto e se tem pedágio.
class RouteResult {
  final String polyline; // codificada, para guardar no Firestore
  final List<RouteLeg> legs; // legs[i] = do ponto i ao ponto i+1
  final List<List<NavStep>> legSteps; // manobras de cada trecho

  /// Áreas de risco reportadas a até 300 m da rota (com "Evitar locais de
  /// risco" ligado; senão 0).
  final int riskCount;

  /// A rota passa por estrada com pedágio (pelas instruções do Google).
  final bool hasToll;
  const RouteResult(this.polyline, this.legs, this.legSteps,
      [this.riskCount = 0, this.hasToll = false, this.summary = '', this.alternatives = const []]);

  /// Estrada principal ("SP-330", "Rod. Anhanguera"), para escolher a rota.
  final String summary;

  /// Outras rotas possíveis (só sem paradas no meio), da mais rápida à mais
  /// lenta; vazias se o piloto não pediu opções.
  final List<RouteResult> alternatives;

  int get distanceM => legs.fold(0, (a, l) => a + l.distanceM);
  int get durationS => legs.fold(0, (a, l) => a + l.durationS);
}

/// Traça a rota real pelas estradas passando por todas as paradas.
/// Sem internet, cai para linhas retas entre as paradas.
///
/// A chave do Google fica no SERVIDOR (functions/maps.js): o app chama a
/// função "directions", que exige login e tem limite diário por usuário.
class DirectionsService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// A API aceita até 25 paradas intermediárias por pedido; roteiros maiores
  /// são calculados em blocos e emendados.
  static const _maxWaypoints = 23;

  static bool get available => true;

  /// Trânsito pelo caminho [points] (saída, pontos da rota, chegada): o
  /// traçado do Google, os trechos dele e os tempos com e sem trânsito.
  /// null = sem o dado (a rota fica azul).
  static Future<
      (List<(double, double)>, List<TrafficInterval>, int, int)?> routeTraffic(
      List<LatLng> points) async {
    try {
      final prefs = AppSettings.instance.route.value;
      final res = await _fn.httpsCallable('routeTraffic').call({
        'origin': _fmt(points.first),
        'destination': _fmt(points.last),
        'via': [for (final p in points.sublist(1, points.length - 1)) _fmt(p)],
        'avoid': [
          if (prefs.avoidTolls) 'tolls',
          if (prefs.avoidHighways) 'highways',
          if (prefs.avoidFerries) 'ferries',
        ],
      });
      final j = jsonDecode(jsonEncode(res.data)) as Map<String, dynamic>;
      final poly = j['polyline'] as String?;
      if (poly == null) return null;
      return (
        [for (final q in decodePolyline(poly)) (q.latitude, q.longitude)],
        [
          for (final t in (j['intervals'] as List).cast<Map<String, dynamic>>())
            (
              start: (t['start'] as num).toInt(),
              end: (t['end'] as num).toInt(),
              level: trafficLevel(t['speed'] as String?),
            ),
        ],
        (j['durationS'] as num?)?.toInt() ?? 0,
        (j['staticS'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Só o traçado (cai para linhas retas entre os pontos se falhar).
  static Future<List<LatLng>> route(List<LatLng> points) async {
    final r = await detailedRoute(points);
    return r == null ? points : decodePolyline(r.polyline);
  }

  /// Rota completa com distância e tempo de cada trecho, ou null se falhar.
  static Future<RouteResult?> detailedRoute(
    List<LatLng> points, {
    bool avoidTolls = false,
    bool avoidHighways = false,
    bool alternatives = false,
  }) async {
    if (points.length < 2) return null;
    // Opções de rota: só de um ponto a outro (o Google não dá alternativas
    // com paradas no meio).
    final legs = <RouteLeg>[];
    final steps = <List<NavStep>>[];
    final path = <LatLng>[];
    var risks = 0;
    var toll = false;
    // Evitar locais de risco: alertas da comunidade e, no motor, os alertas
    // com mais de uma confirmação + as áreas críticas dos dados públicos.
    final avoidRisk = AppSettings.instance.route.value.avoidRisk;
    final hazards =
        avoidRisk ? await HazardService.instance.activeRisks() : const <Hazard>[];
    final riskPts = [for (final h in hazards) (h.lat, h.lng)];
    final avoid = avoidRisk
        ? [
            for (final h in hazards)
              if (h.confirmations >= 2) (h.lat, h.lng),
            ...await RouteEngineService.riskAreas(),
          ]
        : const <(double, double)>[];
    if (alternatives && points.length == 2) {
      return _request(points,
          avoidTolls: avoidTolls,
          avoidHighways: avoidHighways,
          risks: riskPts,
          avoid: avoid,
          alternatives: true);
    }
    for (var i = 0; i < points.length - 1; i += _maxWaypoints + 1) {
      final end = (i + _maxWaypoints + 1).clamp(0, points.length - 1);
      final part = await _request(points.sublist(i, end + 1),
          avoidTolls: avoidTolls, avoidHighways: avoidHighways, risks: riskPts, avoid: avoid);
      if (part == null) return null;
      legs.addAll(part.legs);
      steps.addAll(part.legSteps);
      risks += part.riskCount;
      toll = toll || part.hasToll;
      final pts = decodePolyline(part.polyline);
      path.addAll(path.isEmpty ? pts : pts.skip(1));
    }
    return RouteResult(encodePolyline(path), legs, steps, risks, toll);
  }

  /// Quantas áreas de risco ficam a até 300 m do traçado.
  static int countRisks(
      List<LatLng> line, List<(double, double)> risks) {
    if (risks.isEmpty || line.length < 2) return 0;
    final recs = [for (final p in line) (p.latitude, p.longitude)];
    var n = 0;
    for (final (la, lo) in risks) {
      if (nearestOnLine(la, lo, recs).meters <= 300) n++;
    }
    return n;
  }

  /// Uma chamada à Directions API (até 25 pontos). Monta as opções
  /// (evitar pedágios/rodovias/balsas, alternativas, trânsito), escolhe a
  /// melhor rota e monta o traçado detalhado a partir das manobras.
  static Future<RouteResult?> _request(
    List<LatLng> points, {
    required bool avoidTolls,
    required bool avoidHighways,
    List<(double, double)> risks = const [],
    List<(double, double)> avoid = const [],
    bool alternatives = false,
  }) async {
    final prefs0 = AppSettings.instance.route.value;
    // Mesma rota pedida há pouco (ex.: abriu a prévia de novo): usa a
    // guardada, sem nova consulta paga. Saída arredondada (~100 m).
    final key = [
      for (var i = 0; i < points.length; i++)
        i == 0
            ? '${points[i].latitude.toStringAsFixed(3)},${points[i].longitude.toStringAsFixed(3)}'
            : _fmt(points[i]),
      avoidTolls,
      avoidHighways,
      prefs0.avoidFerries,
      prefs0.preference.name,
      prefs0.liveTraffic,
      skipEngine,
      risks.length,
      avoid.length,
      I18n.lang.value, // manobras faladas no idioma do app
      alternatives,
    ].join('|');
    final hit = _cache[key];
    final ttl = prefs0.liveTraffic
        ? const Duration(minutes: 10)
        : const Duration(minutes: 30);
    if (hit != null && DateTime.now().difference(hit.$1) < ttl) return hit.$2;
    final r = await _requestServer(points,
        avoidTolls: avoidTolls,
        avoidHighways: avoidHighways,
        risks: risks,
        avoid: avoid,
        alternatives: alternatives);
    if (r != null) {
      _cache[key] = (DateTime.now(), r);
      if (_cache.length > 30) _cache.remove(_cache.keys.first);
    }
    return r;
  }

  /// Pede ao Google em vez do motor: rota alternativa quando há trânsito.
  static bool skipEngine = false;

  /// Rotas guardadas há pouco (chave -> hora e resultado).
  static final _cache = <String, (DateTime, RouteResult)>{};

  /// A consulta de fato (servidor -> Google Directions).
  static Future<RouteResult?> _requestServer(
    List<LatLng> points, {
    required bool avoidTolls,
    required bool avoidHighways,
    List<(double, double)> risks = const [],
    List<(double, double)> avoid = const [],
    bool alternatives = false,
  }) async {
    // Motor próprio primeiro; se falhar, segue pelo Google. Ainda pelo
    // Google: evitar pedágio (no mapa aberto a rodovia inteira é pedágio).
    if (RouteEngineService.enabled && !skipEngine && !avoidTolls) {
      final prefs = AppSettings.instance.route.value;
      final r = await RouteEngineService.route(points,
          avoidTolls: avoidTolls,
          avoidHighways: avoidHighways,
          avoidFerries: prefs.avoidFerries,
          shortest: prefs.preference == RoutePreference.shortest,
          alternatives: alternatives,
          avoid: avoidAreasFor(points, avoid));
      if (r != null) {
        if (risks.isEmpty) return r;
        return RouteResult(r.polyline, r.legs, r.legSteps,
            countRisks(decodePolyline(r.polyline), risks), r.hasToll, r.summary,
            r.alternatives);
      }
      RouteEngineService.lastUsed = false;
    }
    try {
      final prefs = AppSettings.instance.route.value;
      final mids = points.sublist(1, points.length - 1).map(_fmt).join('|');
      final avoid = [
        if (avoidTolls) 'tolls',
        if (avoidHighways) 'highways',
        if (prefs.avoidFerries) 'ferries',
      ];
      // "Mais curta": pede alternativas e fica com a de menos km. (O Google
      // só devolve alternativas quando não há paradas no meio.)
      final shortest = prefs.preference == RoutePreference.shortest;
      final wantAlternatives = shortest || risks.isNotEmpty || alternatives;
      // A consulta passa pelo servidor (função "directions"), que guarda a
      // chave do Google: ela não fica dentro do app.
      final res = await _fn
          .httpsCallable('directions',
              options: HttpsCallableOptions(
                  timeout: const Duration(seconds: 25)))
          .call({
        'origin': _fmt(points.first),
        'destination': _fmt(points.last),
        if (mids.isNotEmpty) 'waypoints': mids,
        'avoid': avoid,
        'alternatives': wantAlternatives && mids.isEmpty,
        'traffic': prefs.liveTraffic,
        'lang': I18n.isEn ? 'en' : 'pt',
      });
      // Converte o mapa da função para Map<String, dynamic>.
      final body =
          jsonDecode(jsonEncode(res.data)) as Map<String, dynamic>;
      if (body['status'] != 'OK') return null;
      final routes = (body['routes'] as List).cast<Map<String, dynamic>>();
      int dist(Map<String, dynamic> r) => (r['legs'] as List)
          .fold(0, (a, l) => a + (l['distance']['value'] as num).toInt());
      // Com áreas de risco: primeiro a que passa perto de menos delas; no
      // empate, a preferência (mais curta ou a 1ª = mais rápida).
      final riskOf = {
        for (final r in routes)
          r: countRisks(
              decodePolyline(r['overview_polyline']['points'] as String),
              risks),
      };
      final route = routes.reduce((a, b) {
        final ra = riskOf[a]!, rb = riskOf[b]!;
        if (ra != rb) return rb < ra ? b : a;
        return shortest && dist(b) < dist(a) ? b : a;
      });
      final best = _parseRoute(route, riskOf[route]!);
      if (!alternatives) return best;
      // Opções para o piloto escolher (ex.: não quer ir pela Anhanguera).
      final others = [
        for (final r in routes)
          if (!identical(r, route)) _parseRoute(r, riskOf[r]!)
      ]..sort((x, y) => x.durationS.compareTo(y.durationS));
      return RouteResult(best.polyline, best.legs, best.legSteps,
          best.riskCount, best.hasToll, best.summary, others);
    } catch (_) {
      return null;
    }
  }

  /// Converte uma rota do Google em [RouteResult] (traçado fiel, trechos,
  /// manobras, pedágio e a estrada principal).
  static RouteResult _parseRoute(Map<String, dynamic> route, int risk) {
    final rawLegs = route['legs'] as List;
    final legs = rawLegs
        .map((l) => RouteLeg(
              (l['distance']['value'] as num).toInt(),
              // Com trânsito em tempo real, usa o tempo com trânsito.
              ((l['duration_in_traffic'] ?? l['duration'])['value'] as num)
                  .toInt(),
              (l['duration']['value'] as num).toInt(),
            ))
        .toList();
    final legSteps = rawLegs
        .map((l) => (l['steps'] as List)
            .map((s) => NavStep(
                  (s['start_location']['lat'] as num).toDouble(),
                  (s['start_location']['lng'] as num).toDouble(),
                  cleanInstruction(s['html_instructions'] as String? ?? ''),
                  (s['maneuver'] as String?) ?? '',
                ))
            .where((s) => s.text.isNotEmpty)
            .toList())
        .toList();
    // O "overview_polyline" é resumido (curvas viram retas). O traçado
    // fiel vem de cada manobra; simplificamos com 4 m de tolerância.
    final detailed = <LatLng>[];
    for (final l in rawLegs) {
      for (final s in l['steps'] as List) {
        final enc = s['polyline']?['points'] as String?;
        if (enc == null) continue;
        final pts = decodePolyline(enc);
        detailed.addAll(detailed.isEmpty ? pts : pts.skip(1));
      }
    }
    final polyline = detailed.length >= 2
        ? encodePolyline(simplifyPolyline(detailed, 4))
        : route['overview_polyline']['points'] as String;
    // "Estrada com pedágio" aparece nas instruções do Google.
    final hasToll = rawLegs.any((l) => (l['steps'] as List).any((s) =>
        (s['html_instructions'] as String? ?? '').contains(RegExp('pedágio|[Tt]oll'))));
    return RouteResult(polyline, legs, legSteps, risk, hasToll,
        (route['summary'] as String?) ?? '');
  }

  /// Coordenada no formato do Google: "-27.59,-48.54".
  static String _fmt(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';
}
