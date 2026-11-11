import 'package:comboio/logic/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  // 11/11: retorno/alça que sai e volta no mesmo alinhamento era apagado
  // (a distância era medida até a reta infinita, não até o trecho).
  test('retorno que passa do fim do trecho não some', () {
    const a = LatLng(-21.2000, -47.8000);
    const longe = LatLng(-21.2000, -47.7900); // ~1 km a leste
    const volta = LatLng(-21.2000, -47.7950); // volta pela mesma linha
    final s = simplifyPolyline([a, longe, volta], 4);
    expect(s, contains(longe));
  });

  test('reta com pontos no meio continua enxugando', () {
    final pts = [for (var i = 0; i <= 10; i++) LatLng(-21.2, -47.8 + i * 0.001)];
    expect(simplifyPolyline(pts, 4).length, 2);
  });
}
