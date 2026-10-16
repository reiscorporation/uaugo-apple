import 'package:comboio/models/bike.dart';
import 'package:comboio/models/hazard.dart';
import 'package:comboio/models/privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BikeProfile', () {
    test('junta marca e modelo no nome exibido', () {
      const b = BikeProfile(brand: 'Kawasaki', model: 'Versys 650');
      expect(b.displayName, 'Kawasaki Versys 650');
    });

    test('marca "Outra" não aparece no nome', () {
      const b = BikeProfile(brand: 'Outra', model: 'Custom 250');
      expect(b.displayName, 'Custom 250');
    });

    test('perfil vazio é reconhecido', () {
      expect(const BikeProfile().isEmpty, isTrue);
    });

    test('toMap e fromMap preservam os dados', () {
      const b = BikeProfile(
        brand: 'Harley-Davidson',
        model: 'Fat Boy',
        style: BikeStyle.custom,
        color: 0xFF212121,
        photoUrl: '${BikeProfile.photoPrefix}u1%2F1.jpg?alt=media',
      );
      final c = BikeProfile.fromMap(b.toMap());
      expect(c.displayName, b.displayName);
      expect(c.style, BikeStyle.custom);
      expect(c.color, 0xFF212121);
      expect(c.photoUrl, b.photoUrl);
    });

    test('foto de fora do Storage do app é ignorada', () {
      for (final u in [
        'https://exemplo.com/foto.jpg',
        'http://firebasestorage.googleapis.com/v0/b/helpaitechcomboio.firebasestorage.app/o/bikes%2Fa',
        'https://firebasestorage.googleapis.com/v0/b/outro-projeto.appspot.com/o/bikes%2Fa',
        'https://firebasestorage.googleapis.com/v0/b/helpaitechcomboio.firebasestorage.app/o/public%2Fx',
        42,
      ]) {
        expect(BikeProfile.fromMap({'photoUrl': u}).photoUrl, isNull,
            reason: '$u');
      }
    });

    test('copyWith com clearPhoto remove a foto', () {
      const b = BikeProfile(photoUrl: 'x');
      expect(b.copyWith(clearPhoto: true).photoUrl, isNull);
    });

    test('estilo desconhecido vira big trail', () {
      expect(BikeStyle.fromName('foguete'), BikeStyle.adventure);
    });
  });

  group('Consents (autorizações)', () {
    test('tudo começa desligado e inválido', () {
      const c = Consents();
      expect(c.shareLiveLocation, isFalse);
      expect(c.findable, isFalse);
      expect(c.receiveHelp, isFalse);
      expect(c.receivePassing, isFalse);
      expect(c.isValid, isFalse);
    });

    test('válido apenas com a autorização obrigatória', () {
      expect(const Consents().copyWith(shareLiveLocation: true).isValid, isTrue);
    });

    test('não recebe ajuda sem "ser encontrado"', () {
      final c = const Consents().copyWith(receiveHelp: true, receivePassing: true);
      expect(c.receiveHelp, isFalse);
      expect(c.receivePassing, isFalse);
    });

    test('desligar "ser encontrado" desliga as demais', () {
      final on = const Consents()
          .copyWith(findable: true, receiveHelp: true, receivePassing: true);
      expect(on.receiveHelp, isTrue);
      final off = on.copyWith(findable: false);
      expect(off.receiveHelp, isFalse);
      expect(off.receivePassing, isFalse);
    });

    test('versão antiga exige novo aceite', () {
      final c = Consents.fromMap({'shareLiveLocation': true, 'version': 0});
      expect(c.isValid, isFalse);
    });
  });

  group('HazardType (alertas)', () {
    test('converte pelo nome', () {
      expect(HazardType.fromName('police'), HazardType.police);
      expect(HazardType.fromName('ovni'), isNull);
    });

    test('prazos de validade (RN-05)', () {
      expect(HazardType.police.lifetime, const Duration(hours: 1));
      expect(HazardType.animal.lifetime, const Duration(hours: 1));
      expect(HazardType.danger.lifetime, const Duration(hours: 3));
      expect(HazardType.oil.lifetime, const Duration(hours: 12));
      expect(HazardType.pothole.lifetime, const Duration(days: 7));
      expect(HazardType.radar.lifetime, const Duration(hours: 4));
    });

    test('radares e área de risco a 1 km; semáforo a 300 m; os demais a 500 m', () {
      const longe = [HazardType.radar, HazardType.risk, HazardType.fixedRadar];
      for (final t in longe) {
        expect(t.alertMeters, 1000, reason: t.name);
      }
      expect(HazardType.signal.alertMeters, 300);
      for (final t in HazardType.values
          .where((t) => !longe.contains(t) && t != HazardType.signal)) {
        expect(t.alertMeters, 500, reason: t.name);
      }
    });

    test('só lombada, radar fixo e semáforo podem ficar fixos', () {
      expect(
          HazardType.values.where((t) => t.canBePermanent).toSet(),
          {HazardType.bump, HazardType.fixedRadar, HazardType.signal});
    });
  });
}
