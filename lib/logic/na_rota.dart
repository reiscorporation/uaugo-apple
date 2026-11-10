// ============================================================================
// na_rota.dart — Turismo, hospedagem e postos perto de um ponto (lógica pura)
//
// O que faz: Lê os arquivos por estado (public/turismo/UF.json.gz e
//   public/combustivel/UF.json.gz, gerados por functions/turismo.js), acha o
//   que está perto de um ponto, junta o preço da ANP ao posto do mapa e lê a
//   página de hotéis do Google (scraping no próprio celular).
// Quem usa: NaRotaService e NaRotaScreen.
// ============================================================================

import 'dart:math' as math;

double _rad(double d) => d * math.pi / 180;

/// Distância em metros (haversine).
double distM(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1), dLng = _rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Atração turística (OpenStreetMap).
class Atracao {
  final double lat, lng;
  final String tipo, nome;

  /// Artigo da Wikipédia ("pt:Título"), Wikidata (Q123), foto, site,
  /// horário, descrição e cidade, quando o mapa tem.
  final String? wiki, wikidata, foto, site, horario, descricao, cidade;
  double distM = 0;

  Atracao(this.lat, this.lng, this.tipo, this.nome,
      {this.wiki, this.wikidata, this.foto, this.site, this.horario, this.descricao, this.cidade});

  factory Atracao.fromList(List l) {
    final x = (l.length > 4 ? l[4] : null) as Map? ?? const {};
    return Atracao((l[0] as num) / 1e5, (l[1] as num) / 1e5, l[2] as String, l[3] as String,
        wiki: x['w'] as String?,
        wikidata: x['q'] as String?,
        foto: x['i'] as String?,
        site: x['s'] as String?,
        horario: x['h'] as String?,
        descricao: x['d'] as String?,
        cidade: x['c'] as String?);
  }

  /// Nome do tipo para mostrar.
  String get tipoNome => const {
        'museum': 'Museu',
        'attraction': 'Atração',
        'viewpoint': 'Mirante',
        'zoo': 'Zoológico',
        'theme_park': 'Parque temático',
        'gallery': 'Galeria de arte',
        'aquarium': 'Aquário',
        'waterfall': 'Cachoeira',
        'cave': 'Caverna',
        'beach': 'Praia',
        'peak': 'Pico',
        'historic': 'Histórico',
        'park': 'Parque',
      }[tipo] ??
      'Atração';

  String get emoji => const {
        'museum': '🏛️',
        'viewpoint': '🌄',
        'zoo': '🦁',
        'theme_park': '🎢',
        'gallery': '🖼️',
        'aquarium': '🐠',
        'waterfall': '💧',
        'cave': '🕳️',
        'beach': '🏖️',
        'peak': '⛰️',
        'historic': '🏰',
        'park': '🌳',
      }[tipo] ??
      '📍';

  /// Pontos para ordenar: o que tem Wikipédia/foto costuma ser o mais
  /// conhecido; o resto vai por distância.
  int get fama => (wiki != null ? 2 : 0) + (wikidata != null ? 1 : 0) + (foto != null ? 1 : 0);

  /// Quanto de informação tem (para escolher qual fica entre repetidas).
  int get riqueza =>
      fama * 10 +
      [site, horario, descricao, cidade].where((v) => v != null && v.isNotEmpty).length;
}

/// Palavras que não ajudam a diferenciar nomes ("Cachoeira do Itambé").
const _vazias = {'DE', 'DO', 'DA', 'DOS', 'DAS', 'E', 'O', 'A', 'OS', 'AS', 'NO', 'NA', 'EM'};

Set<String> _palavrasNome(String nome) =>
    normaliza(nome).split(' ').where((w) => w.isNotEmpty && !_vazias.contains(w)).toSet();

/// Duas atrações são o mesmo lugar? Mesmo Wikidata/Wikipédia, ou nomes
/// equivalentes perto uma da outra (o mapa às vezes tem o ponto e a área do
/// mesmo lugar, ou "Cachoeira do Itambé" e "Itambé").
bool mesmoLugar(Atracao a, Atracao b) {
  if (a.wikidata != null && a.wikidata == b.wikidata) return true;
  if (a.wiki != null && a.wiki == b.wiki) return true;
  // Itens diferentes no Wikidata são lugares diferentes, mesmo com nome igual.
  if (a.wikidata != null && b.wikidata != null) return false;
  final d = distM(a.lat, a.lng, b.lat, b.lng);
  if (d > 1500) return false;
  final pa = _palavrasNome(a.nome), pb = _palavrasNome(b.nome);
  if (pa.isEmpty || pb.isEmpty) return false;
  if (pa.length == pb.length && pa.containsAll(pb)) return true;
  final (menor, maior) = pa.length < pb.length ? (pa, pb) : (pb, pa);
  if (!maior.containsAll(menor)) return false;
  // Nome contido no outro: com 2+ palavras basta estar perto; com 1 só
  // ("Itambé"), tem de estar bem perto.
  return menor.length >= 2 || d <= 300;
}

/// Tira as repetidas (fica a de mais informação) e ordena da mais perto
/// para a mais longe. [distM] de cada uma já deve estar calculada.
List<Atracao> semRepetidas(List<Atracao> l) {
  final porRiqueza = [...l]
    ..sort((x, y) => x.riqueza != y.riqueza ? y.riqueza - x.riqueza : x.distM.compareTo(y.distM));
  // Grade de ~1,7 km para comparar só com as vizinhas.
  const passo = 0.015;
  final grade = <(int, int), List<Atracao>>{};
  final porWiki = <String, Atracao>{};
  final out = <Atracao>[];
  for (final a in porRiqueza) {
    final gx = (a.lat / passo).floor(), gy = (a.lng / passo).floor();
    var rep = (a.wikidata != null && porWiki.containsKey('q:${a.wikidata}')) ||
        (a.wiki != null && porWiki.containsKey('w:${a.wiki}'));
    for (var i = -1; i <= 1 && !rep; i++) {
      for (var j = -1; j <= 1 && !rep; j++) {
        for (final b in grade[(gx + i, gy + j)] ?? const <Atracao>[]) {
          if (mesmoLugar(a, b)) {
            rep = true;
            break;
          }
        }
      }
    }
    if (rep) continue;
    out.add(a);
    (grade[(gx, gy)] ??= []).add(a);
    if (a.wikidata != null) porWiki['q:${a.wikidata}'] = a;
    if (a.wiki != null) porWiki['w:${a.wiki}'] = a;
  }
  out.sort((x, y) => x.distM.compareTo(y.distM));
  return out;
}

/// Posto do mapa (com o preço da ANP quando achou o mesmo posto).
class PostoRota {
  final double lat, lng;

  /// Parada famosa entre motociclistas ("Graal", "Frango Assado"...) ou ''.
  final String rede;
  final String nome;
  final String? bandeira, rua, numero, cidade;
  final bool restaurante;
  double distM = 0;
  PrecoAnp? preco;

  PostoRota(this.lat, this.lng, this.rede, this.nome,
      {this.bandeira, this.rua, this.numero, this.cidade, this.restaurante = false});

  factory PostoRota.fromList(List l) {
    final x = (l.length > 4 ? l[4] : null) as Map? ?? const {};
    return PostoRota((l[0] as num) / 1e5, (l[1] as num) / 1e5, l[2] as String, l[3] as String,
        bandeira: x['b'] as String?,
        rua: x['r'] as String?,
        numero: x['n'] as String?,
        cidade: x['c'] as String?,
        restaurante: x['x'] == 1);
  }

  bool get famoso => rede.isNotEmpty;
}

/// Posto da pesquisa semanal da ANP (sem posição; tem endereço e cidade).
class PrecoAnp {
  final String nome, rua, numero, bairro, cidade, bandeira, data;

  /// Preço por produto: g (gasolina), ga (aditivada), e (etanol), d, d10, gnv.
  final Map<String, double> precos;

  PrecoAnp(this.nome, this.rua, this.numero, this.bairro, this.cidade, this.bandeira, this.precos,
      this.data);

  factory PrecoAnp.fromList(List l) => PrecoAnp(
      l[0] as String,
      l[1] as String,
      l[2] as String,
      l[3] as String,
      l[4] as String,
      l[5] as String,
      {for (final e in (l[6] as Map).entries) e.key as String: (e.value as num).toDouble()},
      l.length > 7 ? l[7] as String : '');

  double? get gasolina => precos['g'];
}

/// Texto sem acento, maiúsculo, só letras e números (para comparar nomes).
String normaliza(String s) {
  const de = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ').replaceAll(RegExp(r' +'), ' ').trim();
}

const _comuns = {
  'POSTO', 'AUTO', 'DE', 'DA', 'DO', 'DOS', 'DAS', 'E', 'LTDA', 'COMERCIO', 'COMBUSTIVEIS',
  'COMBUSTIVEL', 'DERIVADOS', 'PETROLEO', 'SERVICOS', 'RUA', 'AVENIDA', 'AV', 'R', 'RODOVIA',
  'ROD', 'ESTRADA', 'KM', 'SN', 'S', 'N', 'ME', 'EPP', 'EIRELI', 'REDE', 'CENTRO',
};

Set<String> _palavras(String s) =>
    normaliza(s).split(' ').where((w) => w.length > 1 && !_comuns.contains(w)).toSet();

/// Acha na ANP o mesmo posto do mapa: mesma cidade e (rua parecida ou nome
/// parecido). Sem cidade conhecida, não arrisca.
PrecoAnp? casaPreco(PostoRota p, String? cidade, List<PrecoAnp> anp) {
  final c = normaliza(p.cidade ?? cidade ?? '');
  if (c.isEmpty) return null;
  PrecoAnp? best;
  var bestScore = 0;
  final ruaP = _palavras(p.rua ?? ''), nomeP = _palavras(p.nome);
  for (final a in anp) {
    if (normaliza(a.cidade) != c) continue;
    var score = 0;
    final ruaA = _palavras(a.rua);
    if (ruaP.isNotEmpty && ruaP.intersection(ruaA).length >= math.min(2, ruaP.length)) {
      score += 2;
      if (p.numero != null && normaliza(a.numero) == normaliza(p.numero!)) score += 2;
    }
    final nomeA = _palavras(a.nome);
    if (nomeP.isNotEmpty && nomeP.intersection(nomeA).isNotEmpty) score += 2;
    if (score > bestScore) {
      bestScore = score;
      best = a;
    }
  }
  return bestScore >= 2 ? best : null;
}

/// Hotel lido da página do Google (preço de uma noite).
class Hotel {
  final String nome;
  final double lat, lng;
  final int? preco;
  final String? estrelas;
  final double? nota;
  final int? avaliacoes;
  final String? endereco;
  double distM = 0;

  Hotel(this.nome, this.lat, this.lng,
      {this.preco, this.estrelas, this.nota, this.avaliacoes, this.endereco});
}

/// Lê os hotéis da página de hotéis do Google (versão de celular). Cada hotel
/// vem num bloco de dados com nome, posição, endereço, estrelas e preço.
/// Se o Google mudar o formato, devolve lista vazia (o app avisa).
List<Hotel> parseHoteisGoogle(String html) {
  final out = <Hotel>[];
  final starts = RegExp(r'"179305178":\[null,"((?:[^"\\]|\\.)+)",\[\[(-?\d+\.\d+),(-?\d+\.\d+)\]')
      .allMatches(html)
      .toList();
  final vistos = <String>{};
  for (var i = 0; i < starts.length; i++) {
    final m = starts[i];
    final end = i + 1 < starts.length ? starts[i + 1].start : math.min(html.length, m.start + 60000);
    final seg = html.substring(m.start, math.min(end, m.start + 60000));
    final nome = _unescape(m.group(1)!);
    if (!vistos.add(nome)) continue;
    final preco = RegExp(r'\["R\$\s?[\d.]+",null,(\d+)').firstMatch(seg);
    final estrelas = RegExp(r'\["((?:Hotel|Pousada|Hostel|Resort|Motel)[^"]{0,25})",\d\]').firstMatch(seg);
    final nota = RegExp(r'\[(\d\.\d+),(\d+)\]').firstMatch(seg);
    final end1 = RegExp(r'\]\],\[\[\["((?:[^"\\]|\\.)+)"\]\]\]').firstMatch(seg);
    final n = nota == null ? null : double.tryParse(nota.group(1)!);
    out.add(Hotel(nome, double.parse(m.group(2)!), double.parse(m.group(3)!),
        preco: preco == null ? null : int.tryParse(preco.group(1)!),
        estrelas: estrelas?.group(1),
        nota: n != null && n > 0 && n <= 5 ? n : null,
        avaliacoes: n != null && n > 0 && n <= 5 ? int.tryParse(nota!.group(2)!) : null,
        endereco: end1 == null ? null : _unescape(end1.group(1)!)));
  }
  return out;
}

String _unescape(String s) => s
    .replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
    .replaceAll(r'\"', '"')
    .replaceAll(r'\\', r'\');

/// Endereço de busca de hotéis do Google numa cidade, para uma noite.
Uri googleHoteisUri(String lugar, DateTime noite) {
  String d(DateTime x) => '${x.day}/${x.month}';
  final q = 'hotéis em $lugar ${d(noite)} a ${d(noite.add(const Duration(days: 1)))}';
  return Uri.https('www.google.com', '/travel/search',
      {'q': q, 'hl': 'pt-BR', 'gl': 'br', 'curr': 'BRL'});
}
