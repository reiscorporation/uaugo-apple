import 'dart:typed_data';

import 'package:comboio/logic/route_gif.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GIF: 50x o tempo em movimento, entre 3 e 12 s', () {
    // 5 min em movimento -> 6 s
    final a = gifPlan(300);
    expect(a.frames * a.delayCs / 100, closeTo(6, 0.2));
    // 30 s -> mínimo de 3 s
    final b = gifPlan(30);
    expect(b.frames * b.delayCs / 100, closeTo(3, 0.2));
    // 3 h -> máximo de 12 s
    final c = gifPlan(3 * 3600);
    expect(c.frames * c.delayCs / 100, closeTo(12, 0.2));
  });

  test('rastro até a metade do caminho termina no meio', () {
    final path = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)];
    final half = pathUntil(path, 0.5);
    expect(half.last.$1, closeTo(10, 1e-9));
    expect(half.last.$2, closeTo(0, 1e-9));
    expect(pathUntil(path, 1).last, (10.0, 10.0));
    expect(pathUntil(path, 0).last, (0.0, 0.0));
  });

  test('gera um GIF válido com vários quadros', () {
    const w = 40, h = 30;
    final rgba = Uint8List(w * h * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = 200;
      rgba[i + 1] = 220;
      rgba[i + 2] = 240;
      rgba[i + 3] = 255;
    }
    final gif = encodeRouteGif(RouteGifInput(
        rgba, w, h, const [(2.0, 2.0), (38.0, 2.0), (38.0, 28.0)], 5, 12));
    expect(String.fromCharCodes(gif.sublist(0, 6)), 'GIF89a');
    // Decodifica de volta: 5 quadros. O decodificador daqui não sobrepõe os
    // quadros (o navegador sim): o 1º traz o mapa inteiro e os outros só o
    // pedaço que mudou (rastro e ponto).
    final anim = img.decodeGif(gif)!;
    expect(anim.numFrames, 5);
    final bg = anim.frames.first.getPixel(20, 15);
    expect((bg.r.toInt() - 200).abs(), lessThan(12));
    expect((bg.b.toInt() - 240).abs(), lessThan(12));
    final dot = anim.frames.last.getPixel(38, 28);
    expect(dot.r.toInt(), greaterThan(230));
    expect(dot.g.toInt(), inInclusiveRange(100, 145));
    expect(anim.frames[1].getPixel(20, 2).r.toInt(), greaterThan(230));
  });

  test('GIF grande (480x680, 100 quadros) fica pequeno', () {
    const w = 480, h = 680;
    final rgba = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        // "mapa" com ruas: faixas e ruído
        rgba[i] = (x * 7 + y * 3) % 256;
        rgba[i + 1] = (x ^ y) % 256;
        rgba[i + 2] = (y * 5) % 256;
        rgba[i + 3] = 255;
      }
    }
    final path = [for (var i = 0; i <= 60; i++) (40.0 + i * 6, 40.0 + (i % 10) * 50)];
    final gif = encodeRouteGif(RouteGifInput(rgba, w, h, path, 100, 12));
    expect(gif.length, lessThan(600 * 1024));
    expect(img.decodeGif(gif)!.numFrames, 100);
  });
}
