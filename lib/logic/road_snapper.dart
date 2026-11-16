// ============================================================================
// road_snapper.dart — Onde desenhar o veículo (road snapping)
//
// O que faz: Recebe as leituras do GPS e decide a POSIÇÃO DE EXIBIÇÃO do
//   veículo, sem nunca alterar a leitura original:
//   - raw: a coordenada do GPS como chegou (fica guardada em [raw]);
//   - display: a posição usada para desenhar o ícone, com a origem
//     (GPS, Map Matching ou Dead Reckoning).
//   Com rota ativa, encaixa o veículo na linha da rota só quando há confiança
//   (distância lateral dentro do erro do GPS, sentido da via compatível com o
//   deslocamento e posição ao longo da rota compatível com a velocidade). Sem
//   confiança, segue a rota pela velocidade (dead reckoning) e só aceita "saiu
//   da rota" depois de várias leituras boas fora dela. Sem GPS (túnel), estima
//   a posição por até 60 s e, quando o sinal volta, corrige aos poucos.
// Quem usa: MapScreen (_shownPoint, rumo da câmera e o relógio de 1 s).
// Onde mexer: as constantes no começo da classe RoadSnapper.
// Limite: só conhece a geometria da ROTA ATIVA. Sem rota, o SDK do Google
//   Maps não fornece a malha de ruas no celular; aí não encaixa em rua
//   nenhuma, só filtra leituras ruins e mantém a continuidade.
// ============================================================================

import 'dart:math';

import 'geo.dart';
import 'radars.dart' show distanceMeters;
import 'simulation.dart';

/// De onde veio a posição desenhada.
enum PositionSource {
  /// A leitura do GPS como chegou (sem rota ou fora dela).
  gps,

  /// O ponto mais provável sobre a rota ativa.
  mapMatching,

  /// Estimada pela última velocidade e direção (sem GPS ou sem confiança).
  deadReckoning,
}

/// Uma leitura do GPS (só os campos que interessam). Nunca é alterada.
class GpsFix {
  const GpsFix({
    required this.lat,
    required this.lng,
    required this.time,
    this.accuracy = 10,
    this.speed = -1,
    this.heading = -1,
    this.headingAccuracy = 0,
  });

  final double lat, lng;

  /// Precisão horizontal informada pelo aparelho (m, raio de 68%).
  final double accuracy;

  /// m/s; negativo = o aparelho não informou.
  final double speed;

  /// Graus (0 = norte); negativo = não informou.
  final double heading;

  /// Graus; 0 = o aparelho não informa.
  final double headingAccuracy;

  /// Quando a leitura chegou ao app.
  final DateTime time;
}

/// A posição usada para desenhar o veículo.
class DisplayPosition {
  const DisplayPosition({
    required this.lat,
    required this.lng,
    required this.bearing,
    required this.source,
    required this.time,
    this.along,
  });

  final double lat, lng;

  /// Sentido do veículo (graus, 0 = norte). Nunca vem da bússola.
  final double bearing;
  final PositionSource source;

  /// Metros desde o início da rota (só quando está sobre ela).
  final double? along;

  /// Quando esta posição foi calculada.
  final DateTime time;
}

class RoadSnapper {
  /// Abaixo disso (m/s) o veículo está parado: a posição não se mexe.
  static const stillSpeed = 0.8;

  /// Acima disso (m/s) a direção do GPS e a da via são confiáveis.
  static const headingSpeed = 3.0;

  /// Leitura "boa": abaixo disso (m) pode tirar o veículo da rota.
  static const goodAccuracy = 25.0;

  /// Leituras boas fora da rota, seguidas, para aceitar que saiu dela.
  static const offRouteConfirm = 3;

  /// Sem leitura por este tempo, começa a estimar (túnel).
  static const gpsSilence = Duration(milliseconds: 2500);

  /// Estima no máximo por este tempo; depois o veículo fica parado onde está.
  static const maxDeadReckoning = Duration(seconds: 60);

  /// Diferença máxima entre a direção do veículo e a da via (graus): acima
  /// disso o trecho é de outro sentido (retorno, alça, pista contrária).
  static const maxHeadingDiff = 70.0;

  /// Fração do erro corrigida a cada leitura (correção gradual).
  static const correctionRate = 0.35;

  /// Erro acima disso (m) corrige de uma vez (GPS voltou muito longe).
  static const jumpMeters = 300.0;

  RouteWalker? _route;
  GpsFix? _raw;
  DisplayPosition? _display;
  DateTime? _lastFixAt;
  GpsFix? _courseAnchor; // última leitura usada para medir a direção
  double _speed = 0;
  double? _bearing;
  int _misses = 0;

  /// Metros andados por estimativa desde a última posição confirmada: a
  /// incerteza cresce com eles (ao voltar do túnel aceita um erro maior).
  double _drMeters = 0;

  /// A última leitura do GPS, sem nenhum ajuste.
  GpsFix? get raw => _raw;

  /// A posição para desenhar o veículo.
  DisplayPosition? get display => _display;

  /// Velocidade estimada (m/s).
  double get speed => _speed;

  /// Rota ativa (null = sem rota ou fora dela por decisão do app).
  RouteWalker? get route => _route;

  /// Troca a rota (nova rota, recálculo ou fim da navegação). A posição
  /// exibida continua; só a posição na rota é procurada de novo.
  set route(RouteWalker? w) {
    if (identical(w, _route)) return;
    _route = w;
    _misses = 0;
    final d = _display;
    if (d != null) {
      _display = DisplayPosition(
          lat: d.lat,
          lng: d.lng,
          bearing: d.bearing,
          source: d.source,
          time: d.time);
    }
  }

  /// Nova leitura do GPS. [exact]: posição sem erro (simulação): encaixa
  /// direto, sem correção gradual (a simulação acelerada anda km por segundo).
  DisplayPosition update(GpsFix f, {DateTime? now, bool exact = false}) {
    final t = now ?? f.time;
    final lastAt = _lastFixAt;
    final dtFix = lastAt == null
        ? 1.0
        : (t.difference(lastAt).inMilliseconds / 1000).clamp(0.05, 60.0);
    _lastFixAt = t;
    _raw = f;
    _updateSpeed(f, dtFix);
    _updateBearing(f);

    final prev = _display;
    final dt = prev == null
        ? dtFix
        : (t.difference(prev.time).inMilliseconds / 1000).clamp(0.0, 60.0);
    final w = _route;

    if (exact) return _display = _exactFix(f, w, t);

    // H. Parado: a posição não "passeia" com o erro do GPS.
    if (prev != null &&
        _speed < stillSpeed &&
        distanceMeters(prev.lat, prev.lng, f.lat, f.lng) <
            max(25.0, 2 * f.accuracy)) {
      _misses = 0;
      return _display = DisplayPosition(
          lat: prev.lat,
          lng: prev.lng,
          bearing: prev.bearing,
          source: prev.source == PositionSource.deadReckoning
              ? PositionSource.gps
              : prev.source,
          along: prev.along,
          time: t);
    }

    if (w != null && w.points.length >= 2) {
      final m = _match(f, w, prev, dt);
      if (m != null) {
        _misses = 0;
        final along = _smoothAlong(m.along, prev, dt, w.length);
        // Incerteza que sobra: o quanto a exibição ainda está longe da
        // leitura (corrigindo aos poucos). Sem isso, a 2ª leitura depois do
        // túnel caía fora da janela e o veículo "saía da rota".
        _drMeters = (along - m.along).abs() * 2;
        final q = w.at(along);
        return _display = DisplayPosition(
            lat: q.lat,
            lng: q.lng,
            bearing: _speed >= 1.5 ? q.bearing : (prev?.bearing ?? q.bearing),
            source: PositionSource.mapMatching,
            along: along,
            time: t);
      }
      // Sem confiança para encaixar: leitura ruim ou poucas leituras fora.
      // Segue na rota pela velocidade, sem ajuste arbitrário.
      final prevAlong = prev?.along;
      final bad = f.accuracy > goodAccuracy;
      if (!bad) _misses++;
      if (prevAlong != null && (bad || _misses < offRouteConfirm)) {
        final along = _speed >= stillSpeed
            ? (prevAlong + _speed * dt).clamp(0.0, w.length).toDouble()
            : prevAlong;
        _drMeters += along - prevAlong;
        final q = w.at(along);
        return _display = DisplayPosition(
            lat: q.lat,
            lng: q.lng,
            bearing: q.bearing,
            source: PositionSource.deadReckoning,
            along: along,
            time: t);
      }
    }
    return _display = _freeFix(f, prev, dt, t);
  }

  /// Relógio (1 s): sem leitura há [gpsSilence], estima a posição pela
  /// última velocidade e direção (D). Devolve null quando não mudou nada.
  DisplayPosition? tick(DateTime now) {
    final d = _display, last = _lastFixAt;
    if (d == null || last == null) return null;
    final silence = now.difference(last);
    if (silence < gpsSilence || silence > maxDeadReckoning) return null;
    if (_speed < stillSpeed) return null;
    final dt = (now.difference(d.time).inMilliseconds / 1000).clamp(0.0, 5.0);
    if (dt <= 0) return null;
    final step = _speed * dt;
    _drMeters += step;
    final w = _route, along = d.along;
    if (w != null && along != null) {
      final a = (along + step).clamp(0.0, w.length).toDouble();
      final q = w.at(a);
      return _display = DisplayPosition(
          lat: q.lat,
          lng: q.lng,
          bearing: q.bearing,
          source: PositionSource.deadReckoning,
          along: a,
          time: now);
    }
    final b = _bearing ?? d.bearing;
    final p = _ahead(d.lat, d.lng, b, step);
    return _display = DisplayPosition(
        lat: p.$1,
        lng: p.$2,
        bearing: b,
        source: PositionSource.deadReckoning,
        time: now);
  }

  // ------------------------------------------------------------ partes

  void _updateSpeed(GpsFix f, double dt) {
    if (f.speed >= 0 && f.speed.isFinite) {
      _speed = f.speed;
      return;
    }
    // Aparelho sem velocidade: pela distância entre leituras boas.
    final a = _courseAnchor;
    if (a != null && f.accuracy <= goodAccuracy && a.accuracy <= goodAccuracy) {
      final secs = f.time.difference(a.time).inMilliseconds / 1000;
      if (secs > 0.5) {
        _speed = distanceMeters(a.lat, a.lng, f.lat, f.lng) / secs;
      }
    }
  }

  /// Direção do veículo (11.4): do GPS quando confiável; senão pelo
  /// deslocamento entre leituras; a bússola nunca entra.
  void _updateBearing(GpsFix f) {
    final reliableGps = f.heading >= 0 &&
        _speed >= headingSpeed &&
        (f.headingAccuracy <= 0 || f.headingAccuracy <= 35);
    if (reliableGps) {
      _bearing = f.heading;
      _courseAnchor = f;
      return;
    }
    final a = _courseAnchor;
    if (a == null) {
      _courseAnchor = f;
      return;
    }
    if (f.accuracy > 40) return;
    final moved = distanceMeters(a.lat, a.lng, f.lat, f.lng);
    if (moved >= max(8.0, f.accuracy)) {
      _bearing = bearingBetween(a.lat, a.lng, f.lat, f.lng);
      _courseAnchor = f;
    }
  }

  /// Simulação: posição exata, encaixa direto.
  DisplayPosition _exactFix(GpsFix f, RouteWalker? w, DateTime t) {
    final h = f.heading >= 0 ? f.heading : _bearing;
    if (w != null && w.points.length >= 2) {
      final pr = w.project(f.lat, f.lng,
          around: _display?.along, heading: h);
      if (pr.offset <= 25) {
        final q = w.at(pr.along);
        return DisplayPosition(
            lat: q.lat,
            lng: q.lng,
            bearing: q.bearing,
            source: PositionSource.mapMatching,
            along: pr.along,
            time: t);
      }
    }
    return DisplayPosition(
        lat: f.lat,
        lng: f.lng,
        bearing: h ?? _display?.bearing ?? 0,
        source: PositionSource.gps,
        time: t);
  }

  /// Sem rota (ou fora dela): a leitura do GPS, com continuidade.
  DisplayPosition _freeFix(
      GpsFix f, DisplayPosition? prev, double dt, DateTime t) {
    final b = _bearing ?? prev?.bearing ?? 0;
    if (prev == null) {
      return DisplayPosition(
          lat: f.lat, lng: f.lng, bearing: b, source: PositionSource.gps, time: t);
    }
    // Leitura muito ruim andando: segue pela velocidade e direção, puxando
    // só um pouco para a leitura (não salta para onde o GPS "acha").
    if (f.accuracy > 40 && _speed >= stillSpeed && _bearing != null) {
      final p = _ahead(prev.lat, prev.lng, b, _speed * dt);
      final k = (20 / f.accuracy).clamp(0.05, 0.5);
      return DisplayPosition(
          lat: p.$1 + (f.lat - p.$1) * k,
          lng: p.$2 + (f.lng - p.$2) * k,
          bearing: b,
          source: PositionSource.deadReckoning,
          time: t);
    }
    // Voltando de uma estimativa: aproxima aos poucos (E), sem tranco.
    if (prev.source != PositionSource.gps) {
      final err = distanceMeters(prev.lat, prev.lng, f.lat, f.lng);
      if (err > 5 && err < jumpMeters) {
        final p = _ahead(prev.lat, prev.lng, b, _speed * dt);
        final k = max(correctionRate, 1 - 20 / err);
        return DisplayPosition(
            lat: p.$1 + (f.lat - p.$1) * k,
            lng: p.$2 + (f.lng - p.$2) * k,
            bearing: b,
            source: PositionSource.gps,
            time: t);
      }
    }
    _drMeters = 0;
    return DisplayPosition(
        lat: f.lat, lng: f.lng, bearing: b, source: PositionSource.gps, time: t);
  }

  /// Procura o ponto mais provável da rota para a leitura (11.2 e 11.6).
  /// Considera: distância lateral (dentro do erro do GPS), sentido da via
  /// (descarta trechos no sentido contrário), distância ao longo da rota
  /// (compatível com a velocidade desde a última posição) e continuidade.
  /// Null = nenhum trecho confiável.
  ({double along, double offset})? _match(
      GpsFix f, RouteWalker w, DisplayPosition? prev, double dt) {
    final pts = w.points, cum = w.cumulative;
    final prevAlong = prev?.along;
    final pred = prevAlong == null ? null : prevAlong + _speed * dt;
    final lateralTol = (f.accuracy * 1.5 + 8).clamp(15.0, 50.0);
    final longTol =
        max(40.0, f.accuracy * 2 + _speed * dt * 0.5 + 20) + _drMeters * 0.5;
    // Só os trechos perto de onde o veículo deveria estar.
    var first = 1, last = pts.length - 1;
    if (pred != null) {
      final from = prevAlong! - longTol, to = pred + longTol;
      while (first < last && cum[first] < from) {
        first++;
      }
      while (last > first && cum[last - 1] > to) {
        last--;
      }
    }
    final heading = _speed >= headingSpeed ? _bearing : null;
    final kx = cos(f.lat * pi / 180);
    ({double along, double offset})? best;
    var bestScore = double.infinity;
    for (var i = first; i <= last; i++) {
      final (aLat, aLng) = pts[i - 1];
      final (bLat, bLng) = pts[i];
      final ax = aLng * kx, bx = bLng * kx;
      final dx = bx - ax, dy = bLat - aLat;
      final len2 = dx * dx + dy * dy;
      final u = len2 == 0
          ? 0.0
          : (((f.lng * kx - ax) * dx + (f.lat - aLat) * dy) / len2)
              .clamp(0.0, 1.0);
      final qLat = aLat + u * (bLat - aLat), qLng = aLng + u * (bLng - aLng);
      final off = distanceMeters(f.lat, f.lng, qLat, qLng);
      if (off > lateralTol) continue;
      final along = cum[i - 1] + u * (cum[i] - cum[i - 1]);
      var score = off / lateralTol;
      if (heading != null && len2 > 0) {
        final diff = angleDiff(heading, bearingBetween(aLat, aLng, bLat, bLng));
        if (diff > maxHeadingDiff) continue; // outro sentido
        score += diff / 90;
      }
      if (pred != null) {
        final lon = (along - pred).abs();
        if (lon > longTol) continue; // pulo incompatível com a velocidade
        score += lon / longTol;
      }
      if (score < bestScore) {
        bestScore = score;
        best = (along: along, offset: off);
      }
    }
    return best;
  }

  /// Posição ao longo da rota sem saltos: anda pela velocidade e corrige
  /// só uma parte do erro por leitura; andando, nunca volta para trás.
  double _smoothAlong(
      double target, DisplayPosition? prev, double dt, double length) {
    final prevAlong = prev?.along;
    if (prevAlong == null) return target;
    final expected = prevAlong + (_speed >= stillSpeed ? _speed * dt : 0);
    final err = target - expected;
    double res;
    if (err.abs() >= jumpMeters) {
      res = target;
    } else if (err.abs() <= 3) {
      res = target;
    } else {
      final c = err * correctionRate;
      res = expected + (c.abs() < 3 ? 3 * err.sign : c);
    }
    if (_speed >= stillSpeed && res < prevAlong) res = prevAlong;
    return res.clamp(0.0, length).toDouble();
  }

  static (double, double) _ahead(
      double lat, double lng, double bearing, double meters) {
    final b = bearing * pi / 180;
    final dLat = meters * cos(b) / 111320;
    final dLng = meters * sin(b) / (111320 * cos(lat * pi / 180));
    return (lat + dLat, lng + dLng);
  }
}
