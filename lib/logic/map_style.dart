// ============================================================================
// map_style.dart — Mapa noturno
//
// O que faz: Estilo escuro do Google Maps e o cálculo da altura do Sol
//   (fórmula da NOAA) para escurecer o mapa sozinho depois do pôr do sol.
// Quem usa: MapScreen (_darkMap) e Configurações (MapTheme).
// Onde mexer: Cores do mapa escuro: darkMapStyle. Quando escurece: isNight
//   (-3°).
// ============================================================================

import 'dart:math';
import '../l10n/i18n.dart';

/// Tema do mapa: automático (pelo pôr do sol), sempre claro ou sempre escuro.
enum MapTheme {
  auto('Automático (pôr do sol)'),
  day('Sempre claro'),
  night('Sempre escuro');

  const MapTheme(this._label);
  final String _label;
  String get label => tr(_label);
}

/// É noite em (lat, lng) agora? Calcula a altura do Sol (fórmula da NOAA,
/// simplificada): noite = Sol abaixo de -3° (já escurecendo).
bool isNight(DateTime when, double lat, double lng) =>
    sunElevation(when.toUtc(), lat, lng) < -3;

/// Altura do Sol no céu, em graus (negativo = abaixo do horizonte).
double sunElevation(DateTime utc, double lat, double lng) {
  final day = utc.difference(DateTime.utc(utc.year)).inMinutes / 1440.0;
  final hour = utc.hour + utc.minute / 60.0;
  // Ângulo do ano (radianos).
  final g = 2 * pi / 365 * (day - 1 + (hour - 12) / 24);
  final decl = 0.006918 -
      0.399912 * cos(g) +
      0.070257 * sin(g) -
      0.006758 * cos(2 * g) +
      0.000907 * sin(2 * g) -
      0.002697 * cos(3 * g) +
      0.00148 * sin(3 * g);
  final eqTime = 229.18 *
      (0.000075 +
          0.001868 * cos(g) -
          0.032077 * sin(g) -
          0.014615 * cos(2 * g) -
          0.040849 * sin(2 * g));
  // Hora solar verdadeira (min) e ângulo horário.
  final tst = hour * 60 + eqTime + 4 * lng;
  final ha = (tst / 4 - 180) * pi / 180;
  final phi = lat * pi / 180;
  final cosZen = sin(phi) * sin(decl) + cos(phi) * cos(decl) * cos(ha);
  return 90 - acos(cosZen.clamp(-1.0, 1.0)) * 180 / pi;
}

/// Plaquinhas de número de rodovia ("SP-330", "050") ocultas: no trecho
/// Anhanguera/Bandeirantes o Google repetia dezenas delas (15/11). Os nomes
/// das vias em texto continuam.
const lightMapStyle = '''
[
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]
''';

/// Estilo escuro do mapa (padrão "Noite" do Google), com as vias em tons de
/// cinza/âmbar para não ofuscar à noite. Também sem as plaquinhas das rodovias.
const darkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#242f3e"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#a59b8e"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a1f29"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#a5875f"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]}
]
''';
