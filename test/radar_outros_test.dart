import 'package:comboio/logic/radars.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import 'package:comboio/logic/geo.dart';

void main() {
  final line = encodePolyline(const [LatLng(-25.50, -51.00), LatLng(-25.52, -51.00)]);
  final idx = RadarIndex.fromJson({
    'radars': [],
    'prf': {
      'label': 'x',
      'stretches': [
        ['PR', '277', 100, 110, line],
      ],
    },
    'outros': [
      {
        'org': 'DER-PR',
        'stretches': [
          ['PR', 'PRC-466', 430, 432, line],
        ],
      },
    ],
  });

  test('lê os trechos da PRF e de outros órgãos', () {
    expect(idx.stretchCount, 2);
    final s = idx.stretchesAround(-25.51, -51.0);
    final prf = s.firstWhere((e) => e.isPrf);
    final der = s.firstWhere((e) => !e.isPrf);
    expect(prf.roadLabel, 'BR-277');
    expect(der.org, 'DER-PR');
    expect(der.roadLabel, 'PRC-466');
    expect(der.roadSpoken, 'P R C 466');
    expect(prfStretchSpeech(der, 500), isNot(contains('polícia rodoviária')));
    expect(prfStretchSpeech(prf, 500), contains('polícia rodoviária'));
    expect(prfStretchSpeech(prf, 500), contains('B R 277'));
  });
}
