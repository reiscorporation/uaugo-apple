import 'package:comboio/services/recent_places_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = RecentPlace('Posto São João', 'Urubici - SC', -28.01, -49.59);
  const b = RecentPlace('Beiramar Shopping', 'Florianópolis - SC', -27.58, -48.54);

  test('filtra sem acento e sem maiúsculas', () {
    expect(RecentPlacesService.matching([a, b], 'sao joao'), [a]);
    expect(RecentPlacesService.matching([a, b], 'FLORIANOPOLIS'), [b]);
    expect(RecentPlacesService.matching([a, b], ''), [a, b]);
  });

  test('mesmo lugar até ~50 m não repete', () {
    expect(a.sameAs(const RecentPlace('X', '', -28.0103, -49.5902)), isTrue);
    expect(a.sameAs(b), isFalse);
  });
}
