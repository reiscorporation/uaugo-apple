// ============================================================================
// vehicle_sprite.dart — Veículo "3D" do marcador (quando não há foto)
//
// O que faz: Carrega as imagens do veículo (assets/vehicles, geradas por
//   tool/vehicles/build_sprites.py), troca a pintura para a cor escolhida e
//   escolhe a vista pelo sentido em que o veículo anda na tela.
// Quem usa: bike_marker.dart (_paintBadge).
// Onde mexer: Tipo novo = imagens em assets/vehicles + entrada em _kinds.
// ============================================================================

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import '../models/bike.dart';

/// Imagem usada por cada tipo (null = ainda sem imagem: fica o ícone).
const Map<BikeStyle, String> _kinds = {
  BikeStyle.adventure: 'adventure',
  BikeStyle.trail: 'adventure',
  BikeStyle.custom: 'custom',
  BikeStyle.touring: 'custom',
  BikeStyle.car: 'car',
  BikeStyle.pickup: 'pickup',
  BikeStyle.motorhome: 'motorhome',
  BikeStyle.bus: 'bus',
  BikeStyle.truck: 'truck',
  BikeStyle.bitrain: 'truck',
};

/// Se o tipo já tem o veículo desenhado.
bool hasVehicleSprite(BikeStyle s) => _kinds.containsKey(s);

/// Vista para o sentido [dir] (0 = indo para cima da tela, 1 = 45° à
/// direita... 7). As imagens só olham para a direita: a esquerda é espelho.
/// Sem a vista de frente, quem vem na direção da tela usa a de ¾ de frente.
({int view, bool mirror}) spriteView(int dir) => switch (dir % 8) {
      0 => (view: 0, mirror: false),
      1 => (view: 1, mirror: false),
      2 => (view: 2, mirror: false),
      3 || 4 => (view: 3, mirror: false),
      5 => (view: 3, mirror: true),
      6 => (view: 2, mirror: true),
      _ => (view: 1, mirror: true),
    };

/// Sentido na tela (0-7) de quem anda no rumo [heading] com o mapa girado
/// em [mapBearing] (graus).
int screenDir(double heading, double mapBearing) =>
    (((heading - mapBearing) % 360 + 360) % 360 / 45).round() % 8;

final Map<String, ui.Image> _cache = {};
final Map<String, Future<(Uint8List, Uint8List, int, int)>> _raw = {};

Future<(Uint8List, int, int)> _decode(String asset) async {
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final img = (await codec.getNextFrame()).image;
  final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final r = (bytes!.buffer.asUint8List(), img.width, img.height);
  img.dispose();
  return r;
}

Future<(Uint8List, Uint8List, int, int)> _load(String kind, int view) {
  return _raw['$kind$view'] ??= () async {
    final (px, w, h) = await _decode('assets/vehicles/${kind}_$view.png');
    final (m, _, _) = await _decode('assets/vehicles/${kind}_${view}_m.png');
    return (px, m, w, h);
  }();
}

/// Veículo do tipo [style] na vista [view] (0-3) pintado na cor [color]
/// (ARGB). null se o tipo não tem imagem ou se falhar.
Future<ui.Image?> vehicleSprite(BikeStyle style, int color, int view) async {
  final kind = _kinds[style];
  if (kind == null) return null;
  final key = '$kind|$view|$color';
  final hit = _cache[key];
  if (hit != null) return hit;
  try {
    final (src, mask, w, h) = await _load(kind, view);
    final out = recolorPixels(src, mask, color);
    final buf = await ui.ImmutableBuffer.fromUint8List(out);
    final desc = ui.ImageDescriptor.raw(buf,
        width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    return _cache[key] = (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

/// Troca a pintura (onde [mask] > 0) para [color], mantendo luz e sombra.
/// O mesmo cálculo da prévia em tool/vehicles/build_sprites.py (recolor).
Uint8List recolorPixels(Uint8List rgba, Uint8List mask, int color) {
  final out = Uint8List.fromList(rgba);
  final (th, ts, tv) = _hsv(((color >> 16) & 255) / 255,
      ((color >> 8) & 255) / 255, (color & 255) / 255);
  final gray = ts < 0.15;
  for (var i = 0; i < out.length; i += 4) {
    final p = mask[i] / 255;
    if (p <= 0) continue;
    final r = rgba[i] / 255, g = rgba[i + 1] / 255, b = rgba[i + 2] / 255;
    final (_, s, v) = _hsv(r, g, b);
    double nr, ng, nb;
    if (gray) {
      nr = ng = nb = (v * (0.15 + 0.9 * tv)).clamp(0.0, 1.0);
    } else {
      (nr, ng, nb) = _rgb(th, (s * ts).clamp(0.0, 1.0),
          (v * (0.25 + 0.85 * tv)).clamp(0.0, 1.0));
    }
    out[i] = ((r * (1 - p) + nr * p) * 255).round();
    out[i + 1] = ((g * (1 - p) + ng * p) * 255).round();
    out[i + 2] = ((b * (1 - p) + nb * p) * 255).round();
  }
  return out;
}

(double, double, double) _hsv(double r, double g, double b) {
  final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
  final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
  final d = mx - mn;
  if (mx <= 0) return (0, 0, 0);
  final s = d / mx;
  if (d == 0) return (0, s, mx);
  double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h / 6, s, mx);
}

(double, double, double) _rgb(double h, double s, double v) {
  final i = (h * 6).floor() % 6;
  final f = h * 6 - (h * 6).floor();
  final p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  return switch (i) {
    0 => (v, t, p),
    1 => (q, v, p),
    2 => (p, v, t),
    3 => (p, q, v),
    4 => (t, p, v),
    _ => (v, p, q),
  };
}
