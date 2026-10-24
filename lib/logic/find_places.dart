// ============================================================================
// find_places.dart — "UauGo, procurar posto" (regras puras)
//
// O que faz: As categorias que dá para procurar falando ("posto",
//   "restaurante barato", "pousada"...) e a ordem dos resultados: navegando,
//   só o que está À FRENTE na rota, do mais perto ao mais longe; sem rota,
//   pela distância.
// Quem usa: voice_commands.dart (frases), PlacesService.find (busca no
//   servidor, functions/maps.js "find"), MapScreen (fala e mostra).
// Onde mexer: Categoria nova: aqui E em functions/maps.js (FIND). A palavra
//   precisa existir no modelo de voz (Vosk): "borracharia" não existe, por
//   isso a borracharia é "pneu".
// ============================================================================

import '../models/expedition.dart' show StopType;
import '../l10n/i18n.dart';

/// O que dá para procurar.
enum FindCategory {
  fuel('posto de combustível', StopType.fuel),
  food('restaurante', StopType.food),
  snack('lanchonete', StopType.food),
  cafe('café', StopType.rest),
  bakery('padaria', StopType.food),
  lodging('hotel ou pousada', StopType.overnight),
  mechanic('oficina mecânica', StopType.waypoint),
  tire('borracharia', StopType.waypoint),
  pharmacy('farmácia', StopType.waypoint),
  hospital('hospital', StopType.waypoint),
  atm('caixa eletrônico', StopType.waypoint),
  market('supermercado', StopType.waypoint),
  pizza('pizzaria', StopType.food),
  bbq('churrascaria', StopType.food),
  burger('hamburgueria', StopType.food),
  icecream('sorveteria', StopType.rest),
  acai('açaí', StopType.rest),
  bar('bar', StopType.rest),
  parking('estacionamento', StopType.waypoint),
  carwash('lava-rápido', StopType.waypoint);

  const FindCategory(this._spoken, this.stopType);

  /// Como a voz fala ("posto de combustível").
  final String _spoken;
  String get spoken => tr(_spoken);

  /// Tipo da parada ao incluir na rota.
  final StopType stopType;

  /// Categorias em que "barato" faz sentido.
  bool get hasPrice =>
      this == food ||
      this == snack ||
      this == lodging ||
      this == cafe ||
      this == pizza ||
      this == bbq ||
      this == burger ||
      this == bar;
}

/// Palavra falada -> categoria ("UauGo, procurar <palavra>").
const findWords = <String, FindCategory>{
  'posto': FindCategory.fuel,
  'gasolina': FindCategory.fuel,
  'combustível': FindCategory.fuel,
  'restaurante': FindCategory.food,
  'comida': FindCategory.food,
  'almoço': FindCategory.food,
  'jantar': FindCategory.food,
  'lanche': FindCategory.snack,
  'lanchonete': FindCategory.snack,
  'café': FindCategory.cafe,
  'padaria': FindCategory.bakery,
  'hotel': FindCategory.lodging,
  'pousada': FindCategory.lodging,
  'oficina': FindCategory.mechanic,
  'mecânico': FindCategory.mechanic,
  'pneu': FindCategory.tire,
  'farmácia': FindCategory.pharmacy,
  'hospital': FindCategory.hospital,
  'banco': FindCategory.atm,
  'caixa eletrônico': FindCategory.atm,
  'mercado': FindCategory.market,
  'supermercado': FindCategory.market,
  'pizza': FindCategory.pizza,
  'pizzaria': FindCategory.pizza,
  'churrascaria': FindCategory.bbq,
  'churrasco': FindCategory.bbq,
  'hamburguer': FindCategory.burger,
  'sorvete': FindCategory.icecream,
  'sorveteria': FindCategory.icecream,
  'açaí': FindCategory.acai,
  'bar': FindCategory.bar,
  'estacionamento': FindCategory.parking,
  'lavagem': FindCategory.carwash,
};

/// Tira do começo do pedido livre ("o que você procura?") as palavras que
/// não ajudam a busca: "procurar uma pizzaria" -> "pizzaria".
String cleanFindQuery(String spoken) {
  final m = RegExp(
          r'^((uau ?go|procurar|procura|encontrar|achar|quero|preciso de|tem)\s+)*'
          r'((um|uma|o|a|algum|alguma)\s+)?',
          caseSensitive: false)
      .firstMatch(spoken.trim());
  final t = spoken.trim().substring(m?.end ?? 0).trim();
  return t.isEmpty ? spoken.trim() : t;
}

/// Verbos aceitos antes da categoria ("procurar posto", "procura posto").
// "parar no posto", "parada restaurante": também incluem parada no caminho.
const findVerbs = ['procurar', 'procura', 'parar no', 'parar na', 'parada'];

/// Um lugar encontrado.
class FoundPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;

  /// "PRICE_LEVEL_INEXPENSIVE"... (do Google) ou null.
  final String? price;
  final bool? open;

  /// Distância até o lugar (m): pela rota, se houver; senão em linha reta.
  final double meters;

  /// Está na rota (busca ao longo do trajeto)?
  final bool onRoute;

  const FoundPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.price,
    this.open,
    required this.meters,
    this.onRoute = false,
  });

  FoundPlace withDistance(double m, {bool onRoute = false}) => FoundPlace(
        name: name,
        address: address,
        lat: lat,
        lng: lng,
        price: price,
        open: open,
        meters: m,
        onRoute: onRoute,
      );
}

/// Ordena os resultados. Navegando ([alongOf] e [riderAlong]): tira o que
/// já ficou para trás (ou a mais de [maxOffRoute] m do traçado) e ordena
/// pela distância à frente na rota. Sem rota: pela distância em linha reta
/// ([distanceTo]).
List<FoundPlace> rankFound(
  List<FoundPlace> found, {
  ({double along, double offset}) Function(double lat, double lng)? alongOf,
  double? riderAlong,
  required double Function(double lat, double lng) distanceTo,
  double maxOffRoute = 2000,
}) {
  final out = <FoundPlace>[];
  for (final f in found) {
    if (alongOf != null && riderAlong != null) {
      final a = alongOf(f.lat, f.lng);
      if (a.offset > maxOffRoute || a.along <= riderAlong) continue;
      out.add(f.withDistance(a.along - riderAlong + a.offset, onRoute: true));
    } else {
      out.add(f.withDistance(distanceTo(f.lat, f.lng)));
    }
  }
  out.sort((a, b) => a.meters.compareTo(b.meters));
  return out;
}
