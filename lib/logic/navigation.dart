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
import '../l10n/i18n.dart';

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

  /// Conversão numa esquina (onde "no semáforo" ajuda a achar a rua).
  bool get isTurn => maneuver.startsWith('turn-');

  /// Saída de rodovia / rampa (ganha um aviso a mais, antecipado).
  bool get isExit =>
      maneuver.startsWith('ramp') ||
      text.startsWith('Pegue a saída') ||
      text.startsWith('Pegue a rampa');

  /// A rota sai da via aqui (saída, conversão, rotatória): o limite menor
  /// depois deste ponto é de verdade, mesmo em trecho curto.
  bool get leavesRoad =>
      isExit ||
      (maneuver.isNotEmpty &&
          maneuver != 'straight' &&
          !maneuver.startsWith('merge'));
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
  // Placas e endereços (pente fino de 08/11).
  'Rib.': 'Ribeirão',
  'Jd.': 'Jardim',
  'Jd': 'Jardim',
  'Vl.': 'Vila',
  'Pq.': 'Parque',
  'Res.': 'Residencial',
  'Cond.': 'Condomínio',
  'Mte.': 'Monte',
  'Pto.': 'Porto',
  'Pte.': 'Ponte',
  'Marg.': 'Marginal',
  'Visc.': 'Visconde',
  'Cap.': 'Capitão',
  'Ten.': 'Tenente',
  'Maj.': 'Major',
  'Brig.': 'Brigadeiro',
  'Com.': 'Comendador',
  'Comend.': 'Comendador',
  'Des.': 'Desembargador',
  'Min.': 'Ministro',
  'Alm.': 'Almirante',
  'Gal.': 'General',
  'Cons.': 'Conselheiro',
  'Pe.': 'Padre',
  'Fr.': 'Frei',
  'Sra.': 'Senhora',
  'Fco.': 'Francisco',
  'Est.': 'Estrada',
  'Viad.': 'Viaduto',
  'Lgo.': 'Largo',
  'Faz.': 'Fazenda',
  'Bal.': 'Balneário',
  'Ver.': 'Vereador',
  'Arq.': 'Arquiteto',
  'Profa.': 'Professora',
  'Dra.': 'Doutora',
  'Pç.': 'Praça',
  'Trav.': 'Travessa',
};

/// Cidades abreviadas nas placas, por extenso. Vêm antes das abreviações
/// soltas (que não sabem o que é "S. J." ou "R. Preto").
const _places = {
  'S. J. do Rio Preto': 'São José do Rio Preto',
  'S.J. do Rio Preto': 'São José do Rio Preto',
  'S. J. Rio Preto': 'São José do Rio Preto',
  'S.J. Rio Preto': 'São José do Rio Preto',
  'S. J. dos Campos': 'São José dos Campos',
  'S.J. dos Campos': 'São José dos Campos',
  'S. J. Campos': 'São José dos Campos',
  'S. J. da Boa Vista': 'São João da Boa Vista',
  'S. J. Boa Vista': 'São João da Boa Vista',
  'S. B. do Campo': 'São Bernardo do Campo',
  'S. B. Campo': 'São Bernardo do Campo',
  'S. C. do Sul': 'São Caetano do Sul',
  'R. Preto': 'Ribeirão Preto',
  'Rib Preto': 'Ribeirão Preto',
  'B. Horizonte': 'Belo Horizonte',
  'B. Paulista': 'Bragança Paulista',
  'P. Prudente': 'Presidente Prudente',
  'Fco. Morato': 'Francisco Morato',
  'N. Sra.': 'Nossa Senhora',
  'N. Senhora': 'Nossa Senhora',
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
    // "Passe por Posto X (à direita a 1 km)": o Google fala o ponto de
    // referência no começo do trecho, longe dele; confunde mais que ajuda.
    final hint = inner.startsWith('Você verá') ||
        inner.startsWith('Passe ') ||
        inner.startsWith('Pass by ');
    return hint ? '' : '. $inner';
  })
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', 'e');
  return _tidyExit(spokenText(t));
}

/// Texto para a voz (qualquer frase: instruções do Google e do motor
/// próprio, nomes de paradas, avisos): cidades e abreviações por extenso
/// ("Rib. Preto" -> "Ribeirão Preto"), romanos ("Leão XIII" -> "Leão
/// Treze"), "BR-101" -> "BR 101". Aplicar duas vezes não estraga.
String spokenText(String text) {
  var t = text;
  for (final e in _places.entries) {
    t = t.replaceAllMapped(
        RegExp(r'(^|[\s/(,])' + RegExp.escape(e.key) + r'(?=$|[\s/),.;:])'),
        (m) => '${m[1]}${e.value}');
  }
  for (final e in _abbrev.entries) {
    t = t.replaceAllMapped(
        RegExp(r'(^|[\s/(])' + RegExp.escape(e.key) + r'(?=$|[\s/),;:])'),
        (m) => '${m[1]}${e.value}');
  }
  // Placas: "S. Carlos", "S. Paulo" = São; "D. Pedro" = Dom.
  t = t.replaceAllMapped(
      RegExp(r'(^|[\s/(])S\. (?=[A-ZÁÉÍÓÚ][a-záéíóúâêôãõç])'), (m) => '${m[1]}São ');
  t = t.replaceAllMapped(
      RegExp(r'(^|[\s/(])D\. (?=[A-Z][a-z])'), (m) => '${m[1]}Dom ');
  for (final e in _ordinals.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  // "BR-101-SUL" -> "BR 101 sul"; "BR-101" -> "BR 101" (a voz lê melhor).
  t = t.replaceAllMapped(RegExp(r'\b([A-Z]{2,3})-(\d{2,3})-(NORTE|SUL|LESTE|OESTE)\b'),
      (m) => '${m[1]} ${m[2]} ${m[3]!.toLowerCase()}');
  t = t.replaceAllMapped(
      RegExp(r'\b([A-Z]{2,3})-(\d{2,3})\b'), (m) => '${m[1]} ${m[2]}');
  t = spokenRomanNumerals(t);
  return t.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' .', '.').trim();
}

const _units = [
  '', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove',
  'dez', 'onze', 'doze', 'treze', 'catorze', 'quinze', 'dezesseis',
  'dezessete', 'dezoito', 'dezenove',
];
const _tens = ['', '', 'vinte', 'trinta', 'quarenta'];
const _ordinalsWords = [
  '', 'primeiro', 'segundo', 'terceiro', 'quarto', 'quinto', 'sexto',
  'sétimo', 'oitavo', 'nono', 'décimo',
];
const _months = 'janeiro|fevereiro|março|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro';

/// Número romano (I a XLIX) -> valor; null se não for romano válido.
int? _roman(String s) {
  const v = {'I': 1, 'V': 5, 'X': 10, 'L': 50};
  var total = 0;
  for (var i = 0; i < s.length; i++) {
    final c = v[s[i]]!;
    final n = i + 1 < s.length ? v[s[i + 1]]! : 0;
    total += c < n ? -c : c;
  }
  // Só a forma canônica (evita "IIII", "VX"...).
  String back(int n) {
    const t = ['', 'X', 'XX', 'XXX', 'XL'];
    const u = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX'];
    return t[n ~/ 10] + u[n % 10];
  }
  return total > 0 && total < 50 && back(total) == s ? total : null;
}

String _cardinal(int n) => n < 20
    ? _units[n]
    : n % 10 == 0
        ? _tens[n ~/ 10]
        : '${_tens[n ~/ 10]} e ${_units[n % 10]}';

/// "Avenida Leão XIII" -> "Avenida Leão Treze"; "Dom Pedro II" -> "Dom Pedro
/// Segundo"; "Rua XV de Novembro" -> "Rua Quinze de Novembro". A voz do
/// celular lê romanos letra por letra. Nomes próprios: ordinal até 10,
/// cardinal acima; datas ("de novembro"): cardinal. Siglas (BR, MG) ficam.
String spokenRomanNumerals(String text) => text.replaceAllMapped(
        RegExp(r'(\S+)? ?\b([IVXL]{1,6})\b(?=( de (' + _months + r'))?)',
            caseSensitive: true),
        (m) {
      final word = m[2]!;
      final n = _roman(word);
      final prev = m[1];
      if (n == null) return m[0]!;
      final date = m[3] != null;
      // Só depois de um nome (palavra com maiúscula) ou antes de "de <mês>".
      final afterName = prev != null &&
          prev.isNotEmpty &&
          prev[0].toUpperCase() == prev[0] &&
          prev[0].toLowerCase() != prev[0];
      if (!date && !afterName) return m[0]!;
      final spoken = date || n > 10 ? _cardinal(n) : _ordinalsWords[n];
      final cap = spoken[0].toUpperCase() + spoken.substring(1);
      return prev == null ? cap : '$prev $cap';
    });

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
        .replaceFirst('saída $num ', tr('saída {0}, ', [num]));
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
  TurnByTurn(this.steps, {this.signalAt});

  final List<NavStep> steps;

  /// Há semáforo neste ponto? (PoiService: semáforos do OpenStreetMap.)
  /// Com semáforo na esquina, a voz diz "No semáforo, vire à direita...".
  final bool Function(double lat, double lng)? signalAt;

  /// Frase da manobra (com "no semáforo", quando há um na esquina).
  String _say(NavStep s) => s.isTurn && (signalAt?.call(s.lat, s.lng) ?? false)
      ? tr('No semáforo, {0}', [_lowerFirst(s.text)])
      : s.text;
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

  /// Recomeça na 1ª manobra À FRENTE de [riderAlong], medindo pela rota.
  /// (Em linha reta, perto do destino, a saída que ainda falta era dada
  /// como passada: o aviso verde e o 3D pulavam a saída, 05/11.)
  void syncAlong(double riderAlong) {
    final a = _alongs;
    if (a == null) return;
    var i = 0;
    while (i < a.length && a[i] < riderAlong - 10) {
      i++;
    }
    _farDone.removeWhere((k) => k >= i);
    _nearDone.removeWhere((k) => k >= i);
    _earlyDone.removeWhere((k) => k >= i);
    _jump(i);
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
      return _say(s);
    }
    // Saída em rodovia (acima de ~55 km/h): aviso extra a 2 km.
    if (s.isExit &&
        v > 15 &&
        d <= 2000 + jump &&
        d > farAt + 300 &&
        _earlyDone.add(j)) {
      return tr('Em {0}, {1}', [spokenDistance(d), _lowerFirst(_say(s))]);
    }
    if (!_farDone.contains(j) && d <= farAt && d > nearAt) {
      _farDone.add(j);
      return tr('Em {0}, {1}', [spokenDistance(d), _lowerFirst(_say(s))]);
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
        if (sayNow) return _say(s);
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
        return _say(s);
      }
      if (!_farSaid && d <= farAt && d > nearAt) {
        _farSaid = true;
        return tr('Em {0}, {1}', [spokenDistance(d), _lowerFirst(_say(s))]);
      }
      return null;
    }
    return null;
  }
}

// ------------------------------------------------------------ chegada

/// Chegada numa parada/destino: até 40 m PELA ROTA (o que falta de estrada),
/// e no máximo 120 m em linha reta (proteção contra traçados que passam
/// perto de si mesmos, como em serras e retornos). Antes (80/400 m) dava
/// "você chegou" ainda a caminho, em ruas que contornam o destino.
const arriveRouteMeters = 40.0;
const arriveRouteMaxStraight = 120.0;

/// Fora da rota (ou sem traçado): só em linha reta, bem mais perto.
const arriveStraightMeters = 60.0;

/// O piloto está "na rota" se estiver a menos disto do traçado.
const onRouteMaxOffset = 150.0;

/// Quanto falta até a parada. Pela rota quando dá (o piloto está no traçado
/// e a posição da parada no traçado é conhecida); senão em linha reta.
/// Antes media só em linha reta: em curvas e serras avisava "você chegou"
/// faltando 1 km de estrada.
({double meters, bool byRoute}) distanceToStop({
  required double straight,
  double? riderAlong,
  double? riderOffset,
  double? stopAlong,
}) {
  if (riderAlong != null &&
      riderOffset != null &&
      riderOffset < onRouteMaxOffset &&
      stopAlong != null) {
    return (meters: stopAlong - riderAlong, byRoute: true);
  }
  return (meters: straight, byRoute: false);
}

/// Chegou na parada? (veja [distanceToStop])
bool hasArrived({
  required double straight,
  double? riderAlong,
  double? riderOffset,
  double? stopAlong,
}) {
  final d = distanceToStop(
      straight: straight,
      riderAlong: riderAlong,
      riderOffset: riderOffset,
      stopAlong: stopAlong);
  return d.byRoute
      // Negativo = já passou do ponto (conta como chegada se estiver perto).
      ? d.meters <= arriveRouteMeters && straight <= arriveRouteMaxStraight
      : d.meters <= arriveStraightMeters;
}
