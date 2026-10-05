// ============================================================================
// navigation.dart — Narração curva a curva
//
// O que faz: Transforma as manobras do Google em frases faladas (limpa HTML,
//   abreviações, número das saídas) e decide QUANDO falar cada uma, medindo o
//   avanço do piloto pela rota (TurnByTurn.updateAlong).
// Quem usa: MapScreen._narrate; testes em test/navigation_test.dart.
// Onde mexer: Distâncias dos avisos: updateAlong (nearAt, farAt, 2 km das
//   saídas).
// ============================================================================

import 'dart:math';

import 'speech.dart';

// Narração do trajeto, curva a curva (funções puras, para os testes).
// As manobras vêm do Google Directions quando o líder calcula a rota e ficam
// salvas no roteiro: durante a viagem, nada é consultado na internet.

/// Uma manobra: o que fazer ao chegar em (lat, lng).
class NavStep {
  final double lat;
  final double lng;
  final String text; // "Vire à direita na Rodovia SC 390"
  final String maneuver; // "turn-right", "roundabout-left"... ("" = seguir)
  const NavStep(this.lat, this.lng, this.text, this.maneuver);

  /// Formato salvo no Firestore junto com a parada (chaves curtas).
  Map<String, dynamic> toMap() =>
      {'la': lat, 'lo': lng, 't': text, if (maneuver.isNotEmpty) 'm': maneuver};

  /// Lê uma manobra salva; null se faltar algum campo.
  static NavStep? fromMap(dynamic m) {
    if (m is! Map) return null;
    final la = m['la'], lo = m['lo'], t = m['t'];
    if (la is! num || lo is! num || t is! String) return null;
    return NavStep(la.toDouble(), lo.toDouble(), t, (m['m'] ?? '') as String);
  }

  /// "Continue para Rua X" é só troca de nome da rua: não precisa falar.
  bool get isSilent => maneuver.isEmpty && text.startsWith('Continue');

  /// Saída de rodovia / rampa (ganha um aviso a mais, antecipado).
  bool get isExit =>
      maneuver.startsWith('ramp') ||
      text.startsWith('Pegue a saída') ||
      text.startsWith('Pegue a rampa');
}

const _abbrev = {
  'R.': 'Rua',
  'Av.': 'Avenida',
  'Rod.': 'Rodovia',
  'Estr.': 'Estrada',
  'Gov.': 'Governador',
  'Pres.': 'Presidente',
  'Dr.': 'Doutor',
  'Dep.': 'Deputado',
  'Sen.': 'Senador',
  'Pref.': 'Prefeito',
  'Eng.': 'Engenheiro',
  'Prof.': 'Professor',
  'Cel.': 'Coronel',
  'Gen.': 'General',
  'Mal.': 'Marechal',
  'Sta.': 'Santa',
  'Sto.': 'Santo',
  'Pça.': 'Praça',
  'Tv.': 'Travessa',
  'Al.': 'Alameda',
};

const _ordinals = {
  '1ª': 'primeira',
  '2ª': 'segunda',
  '3ª': 'terceira',
  '4ª': 'quarta',
  '5ª': 'quinta',
  '6ª': 'sexta',
  '7ª': 'sétima',
  '8ª': 'oitava',
};

/// Transforma o HTML do Google em frase para a voz:
/// tira as tags, as dicas "Você verá..." e escreve as abreviações por extenso.
String cleanInstruction(String html) {
  var t = html
      // Dicas em <div>: mantém avisos úteis (destino, pedágio), tira o resto.
      .replaceAllMapped(RegExp(r'<div[^>]*>(.*?)</div>'), (m) {
    final inner = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '');
    return inner.startsWith('Você verá') ? '' : '. $inner';
  })
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', 'e');
  for (final e in _abbrev.entries) {
    t = t.replaceAllMapped(RegExp('(^|\\s)${RegExp.escape(e.key)}(?=\\s)'),
        (m) => '${m[1]}${e.value}');
  }
  for (final e in _ordinals.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  // "BR-101-SUL" -> "BR 101 sul"; "BR-101" -> "BR 101" (a voz lê melhor).
  t = t.replaceAllMapped(RegExp(r'\b([A-Z]{2,3})-(\d{2,3})-(NORTE|SUL|LESTE|OESTE)\b'),
      (m) => '${m[1]} ${m[2]} ${m[3]!.toLowerCase()}');
  t = t.replaceAllMapped(
      RegExp(r'\b([A-Z]{2,3})-(\d{2,3})\b'), (m) => '${m[1]} ${m[2]}');
  return _tidyExit(
      t.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' .', '.').trim());
}

/// Saídas de rodovia: número em destaque e no máximo 2 destinos.
/// "Pegue a saída 210 para a BR 101 em direção a 210"
///   -> "Pegue a saída 210, para a BR 101"
/// "Pegue a saída em direção a BR 101 sul/Tubarão/Porto Alegre/FAIXAS 1 E 2"
///   -> "Pegue a saída em direção a BR 101 sul e Tubarão"
String _tidyExit(String t) {
  // Lista de destinos "A/B/C": até 2, ligados por "e".
  String names(String s) {
    final parts = s
        .split('/')
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty && !RegExp(r'^FAIXAS?\b').hasMatch(x))
        .take(2)
        .toList();
    return parts.join(' e ');
  }

  t = t.replaceAllMapped(
      RegExp(r'(em direção (?:a|à|ao|às|aos)|para (?:a|o|as|os)?|acesso (?:a|à|ao|às|aos)) ([^.]*?)(?=\.|$| em direção| para )'),
      (m) => m[2]!.contains('/') ? '${m[1]} ${names(m[2]!)}' : m[0]!);
  // "saída 210 ... em direção a 210": o número repetido não ajuda.
  final num = RegExp(r'saída (\d+[A-Z]?)\b').firstMatch(t)?.group(1);
  if (num != null) {
    t = t
        .replaceAll(RegExp(' em direção (?:a|à|ao) $num\\b'), '')
        .replaceFirst('saída $num ', 'saída $num, ');
  }
  return t.replaceAll(RegExp(r',\s*,'), ',').replaceAll(RegExp(r',$'), '').trim();
}

/// "Vire à direita..." -> "vire à direita..." para encaixar em "Em 300 metros, ...".
String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Distância em metros entre dois pontos (fórmula de haversine).
double _dist(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180, dLng = (lng2 - lng1) * pi / 180;
  final a = pow(sin(dLat / 2), 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(a));
}

/// Acompanha a posição e decide o que falar. Para cada manobra:
/// 1) aviso antecipado (~30 s antes, no mínimo 800 m);
/// 2) aviso na hora (~8 s antes, no mínimo 100 m).
class TurnByTurn {
  TurnByTurn(this.steps);

  final List<NavStep> steps;
  int _next = 0;
  bool _farSaid = false;
  bool _nearSaid = false;
  double _closest = double.infinity;

  int get nextIndex => _next;
  bool get finished => _next >= steps.length;

  /// Começa na próxima manobra à frente (para quem liga a narração no meio
  /// do caminho ou volta para a rota).
  void syncTo(double lat, double lng) {
    if (steps.isEmpty) return;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < steps.length; i++) {
      final d = _dist(lat, lng, steps[i].lat, steps[i].lng);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    // Se já passou da mais próxima (está mais perto da seguinte do que ela
    // própria está), começa na seguinte.
    if (best + 1 < steps.length) {
      final n = steps[best + 1], b = steps[best];
      final passed = bestD < 60 ||
          _dist(lat, lng, n.lat, n.lng) < _dist(b.lat, b.lng, n.lat, n.lng);
      if (passed) best++;
    } else if (bestD < 60) {
      best++;
    }
    _jump(best);
  }

  /// Passa para a manobra [i] e zera os avisos já feitos dela.
  void _jump(int i) {
    _next = i;
    _farSaid = false;
    _nearSaid = false;
    _closest = double.infinity;
  }

  // ---------------------------------------------------------- pela rota
  // Com o traçado da rota, cada manobra tem a sua posição AO LONGO dela.
  // O avanço do piloto é medido pela rota: nenhuma manobra "trava" a
  // sequência (antes, um ponto fora do caminho deixava a voz muda) e as
  // distâncias faladas são as da estrada, não em linha reta.

  List<double>? _alongs;
  final Set<int> _farDone = {};
  final Set<int> _nearDone = {};
  final Set<int> _earlyDone = {};

  bool get hasRoute => _alongs != null;

  /// [alongOf] = distância percorrida na rota até o ponto (lat, lng).
  void attachRoute(double Function(double lat, double lng) alongOf) {
    _alongs = [for (final s in steps) alongOf(s.lat, s.lng)];
  }

  /// Esquece as posições na rota (a rota mudou: serão recalculadas).
  void detachRoute() => _alongs = null;

  /// Distância pela rota até a manobra [i] (null sem rota).
  double? routeDistanceTo(int i, double riderAlong) {
    final a = _alongs;
    if (a == null || i >= a.length) return null;
    return max(0.0, a[i] - riderAlong);
  }

  /// Nova posição medida na rota. Retorna a frase a falar (ou null).
  /// [jump] = quanto o piloto avança entre uma leitura e outra (na
  /// simulação acelerada são centenas de metros): amplia as janelas para
  /// nenhuma manobra passar sem aviso.
  String? updateAlong(double riderAlong, double speed, {double jump = 0}) {
    final al = _alongs;
    if (al == null) return null;
    // Manobras que já ficaram para trás (10 m de folga).
    while (_next < steps.length && al[_next] < riderAlong - 10) {
      _next++;
    }
    // Próxima manobra que fala: as silenciosas ("Continue para...") são
    // puladas, sem segurar as seguintes.
    var j = _next;
    while (j < steps.length && steps[j].isSilent) {
      j++;
    }
    if (j >= steps.length) return null;
    final s = steps[j];
    final d = max(0.0, al[j] - riderAlong);
    final v = speed.isFinite && speed > 0 ? speed : 0.0;
    final nearAt = max(max(100.0, v * 8), jump * 1.2);
    final farAt = max(800.0, v * 30) + jump;
    if (!_nearDone.contains(j) && d <= nearAt) {
      _nearDone.add(j);
      _farDone.add(j);
      return s.text;
    }
    // Saída em rodovia (acima de ~55 km/h): aviso extra a 2 km.
    if (s.isExit &&
        v > 15 &&
        d <= 2000 + jump &&
        d > farAt + 300 &&
        _earlyDone.add(j)) {
      return 'Em ${spokenDistance(d)}, ${_lowerFirst(s.text)}';
    }
    if (!_farDone.contains(j) && d <= farAt && d > nearAt) {
      _farDone.add(j);
      return 'Em ${spokenDistance(d)}, ${_lowerFirst(s.text)}';
    }
    return null;
  }

  /// Nova posição do GPS (sem rota: pela distância em linha reta).
  /// Retorna a frase a falar (ou null).
  String? update(double lat, double lng, double speed) {
    while (!finished) {
      final s = steps[_next];
      final d = _dist(lat, lng, s.lat, s.lng);
      if (d < _closest) _closest = d;

      // Passou da manobra: chegou bem perto, ou começou a se afastar dela.
      final passed = d < 30 || (_closest < 150 && d > _closest + 60);
      // Pulou a manobra (outro caminho): a seguinte está mais perto.
      final skipped = _next + 1 < steps.length &&
          d > 400 &&
          _dist(lat, lng, steps[_next + 1].lat, steps[_next + 1].lng) < d / 3;
      if (passed || skipped) {
        // Em cima da manobra sem ter falado (ex.: "Siga na direção sul" na
        // saída de uma parada): fala agora.
        final sayNow = passed && d < 30 && !_nearSaid && !s.isSilent;
        _jump(_next + 1);
        if (sayNow) return s.text;
        continue;
      }
      if (s.isSilent) {
        // Não fala, mas avança quando passar por ela.
        return null;
      }

      final v = speed.isFinite && speed > 0 ? speed : 0.0;
      final nearAt = max(100.0, v * 8);
      final farAt = max(800.0, v * 30);
      if (!_nearSaid && d <= nearAt) {
        _nearSaid = true;
        _farSaid = true;
        return s.text;
      }
      if (!_farSaid && d <= farAt && d > nearAt) {
        _farSaid = true;
        return 'Em ${spokenDistance(d)}, ${_lowerFirst(s.text)}';
      }
      return null;
    }
    return null;
  }
}
