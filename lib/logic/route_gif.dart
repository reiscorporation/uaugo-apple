// ============================================================================
// route_gif.dart — GIF da viagem (a rota feita "acelerada")
//
// O que faz: Sobre a imagem do mapa da viagem, um ponto percorre o caminho
//   feito deixando o rastro laranja, como uma simulação bem acelerada (50x
//   o tempo em movimento, com limite de duração para o GIF caber num post).
//   Função pura (roda num isolate: compute).
// Quem usa: widgets/trip_share.dart (buildRouteGif).
// Onde mexer: Velocidade e limites: gifPlan; cores/espessura: _orange etc.
// ============================================================================

import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Quantos quadros e quanto tempo cada um (em 1/100 s): 50x o tempo em
/// movimento, entre 3 e 12 s de GIF, ~8 quadros por segundo.
({int frames, int delayCs}) gifPlan(int movingSeconds) {
  const delayCs = 12; // ~8 por segundo
  final seconds = (movingSeconds / 50).clamp(3.0, 12.0);
  return (frames: (seconds * 100 / delayCs).round(), delayCs: delayCs);
}

/// O que o isolate precisa: o fundo pronto (RGBA), o caminho em pixels do
/// fundo e o plano de quadros.
class RouteGifInput {
  final Uint8List rgba;
  final int width;
  final int height;
  final List<(double, double)> path;
  final int frames;
  final int delayCs;
  const RouteGifInput(this.rgba, this.width, this.height, this.path,
      this.frames, this.delayCs);
}

/// Pontos do caminho a cada fração [t] (0..1) da distância total: o rastro
/// até ali e a posição do ponto.
List<(double, double)> pathUntil(List<(double, double)> path, double t) {
  if (path.length < 2) return path;
  final cum = <double>[0];
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i];
    cum.add(cum.last + sqrt(pow(b.$1 - a.$1, 2) + pow(b.$2 - a.$2, 2)));
  }
  final goal = cum.last * t.clamp(0.0, 1.0);
  final out = <(double, double)>[path.first];
  for (var i = 1; i < path.length; i++) {
    if (cum[i] <= goal) {
      out.add(path[i]);
      continue;
    }
    final seg = cum[i] - cum[i - 1];
    final u = seg == 0 ? 0.0 : (goal - cum[i - 1]) / seg;
    final a = path[i - 1], b = path[i];
    out.add((a.$1 + (b.$1 - a.$1) * u, a.$2 + (b.$2 - a.$2) * u));
    break;
  }
  return out;
}

final _orange = img.ColorRgb8(255, 122, 26);
final _white = img.ColorRgb8(255, 255, 255);
final _navy = img.ColorRgb8(15, 27, 45);

/// Monta o GIF (em loop). Pesado: chamar com compute().
Uint8List encodeRouteGif(RouteGifInput input) {
  final base = img.Image.fromBytes(
      width: input.width,
      height: input.height,
      bytes: input.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba);
  // Sem pontilhado (mais leve e o arquivo sai menor); paleta por quadro.
  final enc = img.GifEncoder(
      delay: input.delayCs,
      repeat: 0,
      samplingFactor: 30,
      dither: img.DitherKernel.none);
  final n = max(2, input.frames);
  for (var f = 0; f < n; f++) {
    final t = f / (n - 1);
    final frame = base.clone();
    final trail = pathUntil(input.path, t);
    for (var i = 1; i < trail.length; i++) {
      img.drawLine(frame,
          x1: trail[i - 1].$1.round(),
          y1: trail[i - 1].$2.round(),
          x2: trail[i].$1.round(),
          y2: trail[i].$2.round(),
          color: _orange,
          thickness: 5);
    }
    final p = trail.last;
    img.fillCircle(frame, x: p.$1.round(), y: p.$2.round(), radius: 11, color: _navy);
    img.fillCircle(frame, x: p.$1.round(), y: p.$2.round(), radius: 8, color: _white);
    img.fillCircle(frame, x: p.$1.round(), y: p.$2.round(), radius: 5, color: _orange);
    // O último quadro fica 2 s na tela antes de recomeçar.
    enc.addFrame(frame, duration: f == n - 1 ? 200 : input.delayCs);
  }
  return enc.finish()!;
}
