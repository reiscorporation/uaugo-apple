import 'package:comboio/services/places_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('busca: mais perto primeiro; sem distância vai para o fim', () {
    final r = sortByDistance(const [
      PlaceSuggestion('a', 'Rua X', 'Manaus', 2800000),
      PlaceSuggestion('b', 'Rua X', 'sem distância'),
      PlaceSuggestion('c', 'Rua X', 'Ribeirão Preto', 1200),
    ]);
    expect(r.map((e) => e.placeId), ['c', 'a', 'b']);
  });
}
