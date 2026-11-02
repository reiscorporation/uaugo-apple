import 'package:comboio/logic/risk_areas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  const pts = [LatLng(-23.5, -46.6), LatLng(-23.6, -46.7)];

  test('fica só o que está na região da viagem', () {
    final r = avoidAreasFor(pts, [(-23.55, -46.65), (-20.0, -45.0)]);
    expect(r, [(-23.55, -46.65)]);
  });

  test('não bloqueia a saída nem o destino', () {
    expect(avoidAreasFor(pts, [(-23.5005, -46.6005)]), isEmpty);
  });

  test('respeita o limite de áreas', () {
    final many = [for (var i = 0; i < 500; i++) (-23.55, -46.65)];
    expect(avoidAreasFor(pts, many).length, maxAvoidAreas);
  });

  test('quadrado fechado em lng, lat', () {
    final p = avoidPolygons([(10.0, 20.0)], 2).single;
    expect(p.first, p.last);
    expect(p.first, [19.0, 9.0]);
    expect(p.length, 5);
  });
}
