// ============================================================================
// shared_place.dart — Entende o endereço recebido de outro app
//
// O que faz: Transforma o texto/link que chegou ("Abrir com UauGo" ou
//   "Compartilhar → UauGo") em posição (lat/lng) ou em texto para buscar.
//   Formatos: geo:… (WhatsApp, agenda), google.navigation:…, links do Google
//   Maps (maps.google.com, google.com/maps/place/…), Waze e endereço escrito.
// Quem usa: SharedPlaceService.
// Onde mexer: Novo formato de link? Acrescente em [parseSharedPlace] e um
//   teste em test/shared_place_test.dart.
// ============================================================================

/// Lugar recebido: posição (se veio no link) e/ou texto para buscar.
class SharedPlace {
  final double? lat;
  final double? lng;

  /// Texto para buscar quando não há posição (ex.: "Rua X, 123, Curitiba").
  final String? query;

  /// Nome do lugar, se veio junto (ex.: "Restaurante Madalosso").
  final String? label;

  /// Link curto (maps.app.goo.gl): precisa abrir para saber o lugar.
  final Uri? shortLink;

  const SharedPlace({this.lat, this.lng, this.query, this.label, this.shortLink});

  bool get hasCoords => lat != null && lng != null;
}

final _coord = RegExp(r'^\s*(?:loc:)?\s*(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)'
    r'(?:\s*\((.*)\))?\s*$');
final _url = RegExp(r'https?://\S+');

/// Lê "lat,lng" (com "(nome)" opcional). Nulo se não for coordenada válida.
SharedPlace? _parseCoords(String s, {String? label}) {
  final m = _coord.firstMatch(s);
  if (m == null) return null;
  final lat = double.parse(m.group(1)!);
  final lng = double.parse(m.group(2)!);
  if (lat.abs() > 90 || lng.abs() > 180 || (lat == 0 && lng == 0)) return null;
  final name = m.group(3)?.trim();
  return SharedPlace(
      lat: lat, lng: lng, label: (name?.isNotEmpty ?? false) ? name : label);
}

/// Texto ou coordenada (formato do parâmetro q= dos mapas).
SharedPlace? _textOrCoords(String? s, {String? label}) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  return _parseCoords(t, label: label) ?? SharedPlace(query: t, label: label);
}

String _decode(String s) {
  try {
    return Uri.decodeQueryComponent(s);
  } catch (_) {
    return s;
  }
}

/// Parâmetros "a=b&c=d" sem depender do Uri (espaços e vírgulas soltos).
Map<String, String> _params(String query) {
  final out = <String, String>{};
  for (final part in query.split('&')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    out[part.substring(0, i).toLowerCase()] = _decode(part.substring(i + 1));
  }
  return out;
}

/// geo:lat,lng  |  geo:lat,lng?q=…  |  geo:0,0?q=lat,lng(Nome)  |  geo:0,0?q=Rua…
SharedPlace? _parseGeo(String raw) {
  final body = raw.substring(4);
  final q = body.indexOf('?');
  final coords = (q < 0 ? body : body.substring(0, q)).split(';').first;
  final p = q < 0 ? const <String, String>{} : _params(body.substring(q + 1));
  final here = _parseCoords(_decode(coords));
  final fromQ = _textOrCoords(p['q']);
  if (fromQ != null && fromQ.hasCoords) return fromQ;
  if (here != null) return SharedPlace(lat: here.lat, lng: here.lng, label: fromQ?.query);
  return fromQ;
}

/// Link do Google Maps (ou Waze) já completo.
SharedPlace? parseMapsUrl(Uri u) {
  final host = u.host.toLowerCase();
  final p = _params(u.query);
  if (host.contains('waze.com')) {
    return _textOrCoords(p['ll']) ?? _textOrCoords(p['q']);
  }
  if (host == 'consent.google.com' && p['continue'] != null) {
    final inner = Uri.tryParse(p['continue']!);
    return inner == null ? null : parseMapsUrl(inner);
  }
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  // Coordenada do alfinete ("!3dLAT!4dLNG"), mais exata que o centro "@lat,lng".
  final pin = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(u.toString());
  final at = segs
      .where((s) => s.startsWith('@'))
      .map((s) => _parseCoords(s.substring(1).split(',').take(2).join(',')))
      .whereType<SharedPlace>()
      .firstOrNull;
  String? named(String key) {
    final i = segs.indexOf(key);
    if (i < 0 || i + 1 >= segs.length) return null;
    final s = _decode(segs[i + 1]);
    return s.startsWith('@') || s.startsWith('data=') ? null : s;
  }

  final place = named('place');
  if (pin != null) {
    return SharedPlace(
        lat: double.parse(pin.group(1)!), lng: double.parse(pin.group(2)!), label: place);
  }
  for (final k in ['daddr', 'destination', 'q', 'query', 'll']) {
    final r = _textOrCoords(p[k], label: place);
    if (r != null) return r;
  }
  if (place != null) {
    final r = _textOrCoords(place);
    if (r != null && r.hasCoords) return r;
    return at != null
        ? SharedPlace(lat: at.lat, lng: at.lng, label: place)
        : SharedPlace(query: place);
  }
  final search = named('search');
  if (search != null) return _textOrCoords(search);
  final dir = segs.indexOf('dir');
  if (dir >= 0) {
    final dest = segs
        .skip(dir + 1)
        .where((s) => !s.startsWith('@') && !s.startsWith('data='))
        .lastOrNull;
    if (dest != null) return _textOrCoords(_decode(dest));
  }
  return at;
}

bool _isShortLink(Uri u) {
  final h = u.host.toLowerCase();
  return h == 'maps.app.goo.gl' ||
      (h == 'goo.gl' && u.path.startsWith('/maps'));
}

/// Entende o texto/link recebido. Nulo se não reconhecer nenhum lugar.
SharedPlace? parseSharedPlace(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();
  if (lower.startsWith('geo:')) return _parseGeo(text);
  if (lower.startsWith('google.navigation:')) {
    return _textOrCoords(_params(text.substring(18))['q']);
  }
  final m = _url.firstMatch(text);
  if (m != null) {
    final u = Uri.tryParse(m.group(0)!);
    if (u == null) return null;
    // O texto antes do link costuma ser o nome do lugar (compartilhar do Maps).
    final before = text.substring(0, m.start).trim().split('\n').first.trim();
    final label = before.isEmpty ? null : before;
    if (_isShortLink(u)) return SharedPlace(shortLink: u, label: label);
    final r = parseMapsUrl(u);
    if (r == null) return label == null ? null : SharedPlace(query: label);
    return r.label == null && label != null
        ? SharedPlace(lat: r.lat, lng: r.lng, query: r.query, label: label)
        : r;
  }
  // Endereço escrito (ex.: copiado de uma mensagem).
  final coords = _parseCoords(text);
  if (coords != null) return coords;
  if (text.length < 5 || text.length > 200) return null;
  return SharedPlace(
      query: text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join(', '));
}
