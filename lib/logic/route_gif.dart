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

/// Monta o GIF (em loop). Pesado: chamar com compute().
///
/// O mapa entra UMA vez (1º quadro, paleta de 128 cores); cada quadro
/// seguinte grava só o retângulo que mudou (o rastro novo e o ponto) e
/// mantém o resto. Antes cada quadro regravava a imagem toda e o GIF ia a
/// vários MB (14/11); assim fica em algumas centenas de KB.
Uint8List encodeRouteGif(RouteGifInput input) {
  final w = input.width, h = input.height;
  final base = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: input.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba);

  // Paleta: 124 cores do mapa + laranja, branco e marinho do ponto/rastro.
  final q = img.NeuralQuantizer(base, numberOfColors: 124, samplingFactor: 20);
  final pal = q.palette;
  final colors = <List<int>>[
    for (var i = 0; i < min(124, pal.numColors); i++)
      [pal.getRed(i).toInt(), pal.getGreen(i).toInt(), pal.getBlue(i).toInt()],
  ];
  while (colors.length < 125) {
    colors.add([0, 0, 0]);
  }
  const orange = 125, white = 126, navy = 127;
  colors
    ..add([255, 122, 26])
    ..add([255, 255, 255])
    ..add([15, 27, 45]);

  // Mapa em índices da paleta: "trail" guarda mapa + rastro (sem o ponto).
  final trail = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = base.getPixel(x, y);
      trail[y * w + x] = q.getColorIndexRgb(px.r.toInt(), px.g.toInt(), px.b.toInt());
    }
  }

  final out = BytesBuilder(copy: false);
  // Cabeçalho, paleta global e repetição infinita.
  out.add('GIF89a'.codeUnits);
  out.add(_u16(w));
  out.add(_u16(h));
  out.addByte(0xF6); // paleta global de 128 cores (2^(6+1))
  out.addByte(0);
  out.addByte(0);
  for (final c in colors) {
    out.add(c);
  }
  out.add([0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0]);

  const lineR = 3, dotR = 11;
  var prevDot = <int>[0, 0, -1, -1]; // retângulo do ponto anterior
  final n = max(2, input.frames);
  var drawnUpTo = 0.0;
  final frame = Uint8List(w * h);
  for (var f = 0; f < n; f++) {
    final t = f / (n - 1);
    // Rastro novo entre o quadro anterior e este.
    final seg = _between(input.path, drawnUpTo, t);
    drawnUpTo = t;
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    void grow(int ax, int ay, int bx, int by) {
      x0 = min(x0, ax);
      y0 = min(y0, ay);
      x1 = max(x1, bx);
      y1 = max(y1, by);
    }
    for (var i = 1; i < seg.length; i++) {
      _thickLine(trail, w, h, seg[i - 1], seg[i], lineR, orange);
      grow(min(seg[i - 1].$1, seg[i].$1).floor() - lineR, min(seg[i - 1].$2, seg[i].$2).floor() - lineR,
          max(seg[i - 1].$1, seg[i].$1).ceil() + lineR, max(seg[i - 1].$2, seg[i].$2).ceil() + lineR);
    }
    // Quadro = mapa com rastro + o ponto na posição atual.
    final p = pathUntil(input.path, t).last;
    final cx = p.$1.round(), cy = p.$2.round();
    if (prevDot[2] >= 0) grow(prevDot[0], prevDot[1], prevDot[2], prevDot[3]);
    grow(cx - dotR, cy - dotR, cx + dotR, cy + dotR);
    prevDot = [cx - dotR, cy - dotR, cx + dotR, cy + dotR];
    if (f == 0) {
      x0 = 0;
      y0 = 0;
      x1 = w - 1;
      y1 = h - 1;
    }
    x0 = x0.clamp(0, w - 1);
    y0 = y0.clamp(0, h - 1);
    x1 = x1.clamp(0, w - 1);
    y1 = y1.clamp(0, h - 1);
    for (var y = y0; y <= y1; y++) {
      final o = y * w;
      frame.setRange(o + x0, o + x1 + 1, trail, o + x0);
    }
    _disc(frame, w, h, cx, cy, dotR, navy);
    _disc(frame, w, h, cx, cy, dotR - 3, white);
    _disc(frame, w, h, cx, cy, dotR - 6, orange);

    // Controle: tempo do quadro, "não apagar" (o próximo desenha por cima).
    final delay = f == n - 1 ? 200 : input.delayCs;
    out.add([0x21, 0xF9, 4, 0x04, delay & 0xFF, delay >> 8, 0, 0]);
    final rw = x1 - x0 + 1, rh = y1 - y0 + 1;
    out.addByte(0x2C);
    out.add(_u16(x0));
    out.add(_u16(y0));
    out.add(_u16(rw));
    out.add(_u16(rh));
    out.addByte(0);
    final sub = Uint8List(rw * rh);
    for (var y = 0; y < rh; y++) {
      sub.setRange(y * rw, (y + 1) * rw, frame, (y0 + y) * w + x0);
    }
    out.addByte(7); // tamanho mínimo do código (paleta de 128)
    final data = _lzw(sub, 7);
    for (var i = 0; i < data.length; i += 255) {
      final e = min(data.length, i + 255);
      out.addByte(e - i);
      out.add(Uint8List.sublistView(data, i, e));
    }
    out.addByte(0);
  }
  out.addByte(0x3B);
  return out.toBytes();
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];

/// Trecho do caminho entre as frações [a] e [b] da distância.
List<(double, double)> _between(List<(double, double)> path, double a, double b) {
  final upToB = pathUntil(path, b);
  if (a <= 0) return upToB;
  final upToA = pathUntil(path, a);
  return [upToA.last, ...upToB.skip(upToA.length - 1)];
}

void _disc(Uint8List buf, int w, int h, int cx, int cy, int r, int c) {
  for (var y = max(0, cy - r); y <= min(h - 1, cy + r); y++) {
    for (var x = max(0, cx - r); x <= min(w - 1, cx + r); x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) buf[y * w + x] = c;
    }
  }
}

void _thickLine(Uint8List buf, int w, int h, (double, double) a, (double, double) b, int r, int c) {
  final len = sqrt(pow(b.$1 - a.$1, 2) + pow(b.$2 - a.$2, 2));
  final steps = max(1, len.ceil());
  for (var i = 0; i <= steps; i++) {
    final u = i / steps;
    _disc(buf, w, h, (a.$1 + (b.$1 - a.$1) * u).round(), (a.$2 + (b.$2 - a.$2) * u).round(), r, c);
  }
}

/// Compressão LZW do GIF (códigos de tamanho variável até 12 bits).
Uint8List _lzw(Uint8List data, int minCode) {
  final clear = 1 << minCode, eoi = clear + 1;
  var size = minCode + 1, next = eoi + 1;
  final dict = <int, int>{};
  final out = BytesBuilder(copy: false);
  var acc = 0, bits = 0;
  void emit(int code) {
    acc |= code << bits;
    bits += size;
    while (bits >= 8) {
      out.addByte(acc & 0xFF);
      acc >>= 8;
      bits -= 8;
    }
    // Como o decodificador: cresce depois de gravar, quando o próximo
    // código já não cabe.
    if (next >= (1 << size) && size < 12) size++;
  }

  emit(clear);
  if (data.isEmpty) {
    emit(eoi);
  } else {
    var prefix = data[0];
    for (var i = 1; i < data.length; i++) {
      final k = data[i], key = (prefix << 8) | k;
      final hit = dict[key];
      if (hit != null) {
        prefix = hit;
        continue;
      }
      emit(prefix);
      if (next < 4096) {
        dict[key] = next++;
      } else {
        emit(clear);
        dict.clear();
        size = minCode + 1;
        next = eoi + 1;
      }
      prefix = k;
    }
    emit(prefix);
    emit(eoi);
  }
  if (bits > 0) out.addByte(acc & 0xFF);
  return out.toBytes();
}
