// ============================================================================
// vias_service.dart — Rodovias reais para a visão 3D (UauGo v2)
//
// O que faz: Baixa uma vez e guarda no celular o pacote de rodovias do
//   estado (vias expressas, rodovias, avenidas principais e as alças de
//   saída, do mapa aberto: tipo, número de faixas, mão única e o traçado) e
//   devolve as que estão perto do piloto. A visão 3D desenha com elas as
//   faixas e as saídas no lugar exato. Funciona sem internet depois de baixar.
// Quem usa: MapScreen (_feedRoads3d) -> Sim3DController.roads.
// Onde mexer: Arquivo public/vias/UF.json.gz, gerado no PC por
//   scripts/gerar-vias.py (por enquanto só SP).
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Uma via do pacote: tipo (1 expressa, 2 rodovia, 3 avenida, 4 alça),
/// faixas, mão única e o traçado em 1e-5 grau (lat, lng, lat, lng...).
class Via {
  Via(this.cls, this.lanes, this.oneway, this.pts);
  final int cls;
  final int lanes;
  final bool oneway;
  final Int32List pts;
}

class _Index {
  _Index(this.vias, this.cells);
  final List<Via> vias;
  final Map<int, List<int>> cells; // célula de ~2 km -> vias
}

class ViasService {
  ViasService._();
  static final instance = ViasService._();

  /// Estados com pacote e a área que cobrem (lat/lng mín. e máx.).
  static const _ufs = {'SP': [-25.4, -53.2, -19.7, -44.1]};

  final Map<String, _Index> _loaded = {};
  final Set<String> _loading = {};

  /// Pontos da via dentro da área (com 1 ponto de folga em cada ponta).
  static List<double> _nearPart(Int32List p, int la5, int lo5, int dLa, int dLo) {
    var first = -1, last = -1;
    for (var i = 0; i + 1 < p.length; i += 2) {
      if ((p[i] - la5).abs() <= dLa && (p[i + 1] - lo5).abs() <= dLo) {
        if (first < 0) first = i;
        last = i;
      }
    }
    final a = max(0, first - 2), b = min(p.length - 2, last + 2);
    return [for (var i = a; i <= b + 1; i++) p[i] / 1e5];
  }

  static int _cell(int lat5, int lng5) =>
      ((lat5 / 2000).floor() + 10000) * 100000 + (lng5 / 2000).floor() + 50000;

  /// Começa a baixar/ler o pacote do estado onde está o ponto.
  void ensure(double lat, double lng) {
    for (final e in _ufs.entries) {
      final b = e.value;
      if (lat < b[0] || lat > b[2] || lng < b[1] || lng > b[3]) continue;
      if (_loaded.containsKey(e.key) || !_loading.add(e.key)) continue;
      _load(e.key).whenComplete(() => _loading.remove(e.key));
    }
  }

  Future<void> _load(String uf) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/vias_$uf.json.gz');
      Uint8List? bytes;
      if (await file.exists()) {
        bytes = await file.readAsBytes();
      } else {
        bytes = await FirebaseStorage.instance
            .ref('public/vias/$uf.json.gz')
            .getData(40 * 1024 * 1024);
        if (bytes == null) return;
        await file.writeAsBytes(bytes, flush: true);
      }
      _loaded[uf] = await compute(_parse, bytes);
      debugPrint('Vias $uf: ${_loaded[uf]!.vias.length}');
    } catch (e) {
      debugPrint('Vias $uf indisponíveis: $e');
    }
  }

  static _Index _parse(Uint8List gz) {
    final j = jsonDecode(utf8.decode(gzip.decode(gz))) as Map<String, dynamic>;
    final vias = <Via>[];
    final cells = <int, List<int>>{};
    for (final w in (j['w'] as List)) {
      final d = (w[3] as List).cast<int>();
      final pts = Int32List(d.length);
      var la = 0, lo = 0;
      final seen = <int>{};
      for (var i = 0; i + 1 < d.length; i += 2) {
        la += d[i];
        lo += d[i + 1];
        pts[i] = la;
        pts[i + 1] = lo;
        seen.add(_cell(la, lo));
      }
      final id = vias.length;
      vias.add(Via(w[0] as int, w[1] as int, w[2] == 1, pts));
      for (final c in seen) {
        (cells[c] ??= []).add(id);
      }
    }
    return _Index(vias, cells);
  }

  /// Trechos das vias que passam a até [nearM] do ponto: [spanM] para cada
  /// lado, com um ponto a cada ~40 m. Vazio se não houver pacote da região.
  List<List<(double, double)>> roadsAt(double lat, double lng,
      {double nearM = 12, double spanM = 200}) {
    final out = <List<(double, double)>>[];
    final la5 = (lat * 1e5).round(), lo5 = (lng * 1e5).round();
    final k = cos(lat * pi / 180);
    // Metros no plano em volta do ponto.
    double x(int lo) => (lo - lo5) * 1.1132 * k;
    double y(int la) => (la - la5) * 1.1054;
    for (final idx in _loaded.values) {
      final ids = <int>{};
      for (var a = -2000; a <= 2000; a += 2000) {
        for (var b = -2000; b <= 2000; b += 2000) {
          ids.addAll(idx.cells[_cell(la5 + a, lo5 + b)] ?? const []);
        }
      }
      for (final id in ids) {
        final p = idx.vias[id].pts;
        final pts = <(double, double)>[];
        var near = false;
        for (var i = 0; i + 3 < p.length; i += 2) {
          final ax = x(p[i + 1]), ay = y(p[i]);
          final bx = x(p[i + 3]), by = y(p[i + 2]);
          final dx = bx - ax, dy = by - ay;
          final len = sqrt(dx * dx + dy * dy);
          if (len == 0) continue;
          final t = (-(ax * dx + ay * dy) / (len * len)).clamp(0.0, 1.0);
          final px = ax + t * dx, py = ay + t * dy;
          if (px * px + py * py <= nearM * nearM) near = true;
          final n = max(1, (len / 40).ceil());
          for (var s = 0; s < n; s++) {
            final sx = ax + dx * s / n, sy = ay + dy * s / n;
            if (sx * sx + sy * sy > spanM * spanM) continue;
            pts.add((
              (la5 + sy / 1.1054) / 1e5,
              (lo5 + sx / (1.1132 * k)) / 1e5,
            ));
          }
        }
        if (near) out.add(pts);
      }
    }
    return out;
  }

  /// Vias perto do ponto já em JSON, fora da linha principal do app: em
  /// celular simples, montar isso na tela congelava o mapa e o Android Auto.
  Future<String?> nearJson(double lat, double lng, double radiusM) async {
    final list = near(lat, lng, radiusM);
    return list.isEmpty ? null : compute(jsonEncode, list);
  }

  /// Vias com algum ponto a menos de [radiusM] do ponto, no formato da
  /// visão 3D: [tipo, faixas, mãoÚnica, [lat, lng, ...]].
  List<List<Object>> near(double lat, double lng, double radiusM) {
    final out = <List<Object>>[];
    final la5 = (lat * 1e5).round(), lo5 = (lng * 1e5).round();
    final dLa = (radiusM / 1.1054).round(); // 1e-5 grau de lat ≈ 1,1054 m
    final dLo = (radiusM / (1.1132 * cos(lat * pi / 180))).round();
    for (final idx in _loaded.values) {
      final ids = <int>{};
      for (var a = la5 - dLa; a <= la5 + dLa + 2000; a += 2000) {
        for (var b = lo5 - dLo; b <= lo5 + dLo + 2000; b += 2000) {
          ids.addAll(idx.cells[_cell(a, b)] ?? const []);
        }
      }
      for (final id in ids) {
        final v = idx.vias[id];
        final p = v.pts;
        var inside = false;
        for (var i = 0; i + 1 < p.length; i += 2) {
          if ((p[i] - la5).abs() <= dLa && (p[i + 1] - lo5).abs() <= dLo) {
            inside = true;
            break;
          }
        }
        if (!inside) continue;
        out.add([
          v.cls, v.lanes, v.oneway ? 1 : 0,
          // Só o trecho perto: a via inteira pesa muito em rodovia longa.
          _nearPart(p, la5, lo5, dLa, dLo),
        ]);
      }
    }
    return out;
  }
}
