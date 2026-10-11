import 'package:comboio/logic/shared_place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('geo com coordenada', () {
    final p = parseSharedPlace('geo:-25.4284,-49.2733')!;
    expect(p.lat, -25.4284);
    expect(p.lng, -49.2733);
  });

  test('geo 0,0 com coordenada e nome no q', () {
    final p = parseSharedPlace('geo:0,0?q=-27.59,-48.55(Ponte%20Herc%C3%ADlio%20Luz)')!;
    expect(p.lat, -27.59);
    expect(p.label, 'Ponte Hercílio Luz');
  });

  test('geo 0,0 com endereço escrito', () {
    final p = parseSharedPlace('geo:0,0?q=Rua+XV+de+Novembro,+100,+Curitiba')!;
    expect(p.hasCoords, isFalse);
    expect(p.query, 'Rua XV de Novembro, 100, Curitiba');
  });

  test('google.navigation', () {
    final p = parseSharedPlace('google.navigation:q=-23.55,-46.63')!;
    expect(p.lng, -46.63);
  });

  test('link do Maps com q=lat,lng (localização do WhatsApp)', () {
    final p = parseSharedPlace('https://maps.google.com/?q=-22.9068,-43.1729')!;
    expect(p.lat, -22.9068);
  });

  test('link de lugar usa o alfinete, não o centro da tela', () {
    final p = parseSharedPlace('https://www.google.com/maps/place/Madalosso/'
        '@-25.39,-49.27,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d-25.3911!4d-49.2702')!;
    expect(p.lat, -25.3911);
    expect(p.lng, -49.2702);
    expect(p.label, 'Madalosso');
  });

  test('link de busca', () {
    final p = parseSharedPlace('https://www.google.com/maps/search/Serra+do+Rio+do+Rastro')!;
    expect(p.query, 'Serra do Rio do Rastro');
  });

  test('link de rota usa o destino', () {
    final p = parseSharedPlace(
        'https://www.google.com/maps/dir/?api=1&destination=Urubici%2C+SC')!;
    expect(p.query, 'Urubici, SC');
  });

  test('compartilhar do Maps: nome + link curto', () {
    final p = parseSharedPlace('Restaurante Madalosso\nhttps://maps.app.goo.gl/AbC123')!;
    expect(p.shortLink.toString(), 'https://maps.app.goo.gl/AbC123');
    expect(p.label, 'Restaurante Madalosso');
  });

  test('Waze', () {
    final p = parseSharedPlace('https://waze.com/ul?ll=-26.9,-49.06&navigate=yes')!;
    expect(p.lat, -26.9);
  });

  test('endereço escrito em várias linhas', () {
    final p = parseSharedPlace('Av. Brasil, 500\nCentro\nBlumenau - SC')!;
    expect(p.query, 'Av. Brasil, 500, Centro, Blumenau - SC');
  });

  test('coordenada solta', () {
    expect(parseSharedPlace('-25.4284, -49.2733')!.hasCoords, isTrue);
  });

  test('link que não é de mapa nem texto útil', () {
    expect(parseSharedPlace('https://youtube.com/watch?v=x'), isNull);
    expect(parseSharedPlace('oi'), isNull);
  });
}
