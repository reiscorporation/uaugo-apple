// ============================================================================
// bike.dart — Perfil do veículo (moto, carro, ônibus, caminhão...)
//
// O que faz: Marca, modelo, tipo (estilos de moto, carro, camionete, jeep,
//   ônibus, caminhão, bitrem...), eixos/reboque (pedágio), cor do
//   marcador e foto. Vai para o Firestore junto com o membro da expedição
//   (para os amigos verem).
// Quem usa: ProfileScreen (edita), MapScreen (ícone no mapa), pedágio (moto x
//   carro).
// Onde mexer: Tipos: enum BikeStyle (isCar, isHeavy). Pedágio: tollFactor.
//   Marcas: bikeBrands / carBrands / heavyBrands.
// ============================================================================

import 'package:flutter/material.dart';

/// Tipo do veículo: define o ícone genérico usado quando não há foto e a
/// categoria no pedágio.
enum BikeStyle {
  adventure('Big trail', Icons.two_wheeler, 'sua moto'),
  trail('Trail / Off-road', Icons.two_wheeler, 'sua moto'),
  custom('Custom', Icons.motorcycle, 'sua moto'),
  touring('Touring', Icons.motorcycle, 'sua moto'),
  naked('Naked / Street', Icons.two_wheeler, 'sua moto'),
  sport('Esportiva', Icons.sports_motorsports, 'sua moto'),
  scooter('Scooter', Icons.moped, 'sua moto'),
  tricycle('Triciclo', Icons.electric_rickshaw, 'seu triciclo'),
  // O app também serve para quem viaja de carro, ônibus ou caminhão.
  car('Carro', Icons.directions_car, 'seu carro'),
  pickup('Camionete / picape', Icons.airport_shuttle, 'sua camionete'),
  suv('SUV', Icons.directions_car_filled, 'seu SUV'),
  jeep('Jeep / 4x4', Icons.terrain, 'seu 4x4'),
  motorhome('Motorhome', Icons.rv_hookup, 'seu motorhome'),
  bus('Ônibus', Icons.directions_bus, 'seu ônibus'),
  truck('Caminhão', Icons.local_shipping, 'seu caminhão'),
  bitrain('Bitrem / rodotrem', Icons.local_shipping, 'seu bitrem');

  /// Moto (e triciclo): paga pedágio de moto, usa "moto" nos avisos.
  bool get isMoto => index <= tricycle.index;

  /// Carro, camionete, ônibus, caminhão... (tudo que não é moto).
  bool get isCar => !isMoto;

  /// Veículo pesado: o pedágio é pelo número de eixos.
  bool get isHeavy => this == motorhome || this == bus || this == truck || this == bitrain;

  /// Eixos quando o piloto ainda não informou.
  int get defaultAxles => this == bitrain ? 7 : 2;

  /// Marcas sugeridas para o tipo.
  List<String> get brands => isMoto ? bikeBrands : (isHeavy ? heavyBrands : carBrands);

  const BikeStyle(this.label, this.icon, this.noun);
  final String label;
  final IconData icon;

  /// Para as frases do app: "sua moto", "seu caminhão"...
  final String noun;

  /// Lê o tipo salvo pelo nome (desconhecido = Big trail).
  static BikeStyle fromName(String? name) {
    for (final s in BikeStyle.values) {
      if (s.name == name) return s;
    }
    return BikeStyle.adventure;
  }
}

/// Marcas só como texto (sem logos, que são marcas registradas).
const bikeBrands = [
  'BMW', 'Ducati', 'Harley-Davidson', 'Honda', 'Kawasaki', 'KTM',
  'Royal Enfield', 'Suzuki', 'Triumph', 'Yamaha', 'Outra',
];

/// Marcas de carro (quando o tipo escolhido é carro ou picape).
const carBrands = [
  'BYD', 'Chevrolet', 'Fiat', 'Ford', 'Honda', 'Hyundai', 'Jeep', 'Mitsubishi',
  'Nissan', 'Peugeot', 'Renault', 'Toyota', 'Volkswagen', 'Outra',
];

/// Marcas de ônibus, caminhão e motorhome.
const heavyBrands = [
  'DAF', 'Ford', 'Iveco', 'Marcopolo', 'Mercedes-Benz', 'Scania', 'Volare',
  'Volkswagen', 'Volvo', 'Outra',
];

/// Cores disponíveis para o marcador (ARGB).
const bikeColors = <int>[
  0xFFFF9800, 0xFF43A047, 0xFFE53935, 0xFF1E88E5, 0xFF212121,
  0xFF9E9E9E, 0xFFFFFFFF, 0xFFFDD835, 0xFF6D4C41, 0xFF8E24AA,
];

/// Veículo do piloto (moto, carro, caminhão...): aparece no mapa para o grupo.
class BikeProfile {
  final String brand;
  final String model;
  final BikeStyle style;
  final int color;
  final String? photoUrl;

  /// Eixos do veículo pesado, já contando o reboque (pedágio).
  final int? axles;

  /// Reboque do carro/camionete: 0 = sem, 1 ou 2 eixos (pedágio).
  final int trailerAxles;

  const BikeProfile({
    this.brand = '',
    this.model = '',
    this.style = BikeStyle.adventure,
    this.color = 0xFFFF9800,
    this.photoUrl,
    this.axles,
    this.trailerAxles = 0,
  });

  /// Quantas vezes o valor do carro este veículo paga no pedágio (tabela
  /// da ANTT: carro 1; com reboque de 1 eixo 1,5, de 2 eixos 2; pesado = nº
  /// de eixos). Null para moto: depende da praça (isenta ou metade).
  double? get tollFactor {
    if (style.isMoto) return null;
    if (style.isHeavy) return (axles ?? style.defaultAxles).clamp(2, 20).toDouble();
    return switch (trailerAxles) { 1 => 1.5, 2 => 2.0, _ => 1.0 };
  }

  /// Ex: "Kawasaki Versys 650"
  String get displayName => [
        if (brand.isNotEmpty && brand != 'Outra') brand,
        if (model.isNotEmpty) model,
      ].join(' ');

  bool get isEmpty => displayName.isEmpty && photoUrl == null;

  String get cacheKey => '$brand|$model|${style.name}|$color|$photoUrl|$axles|$trailerAxles';

  /// Cópia com alguns campos trocados ([clearPhoto] remove a foto).
  BikeProfile copyWith({
    String? brand,
    String? model,
    BikeStyle? style,
    int? color,
    String? photoUrl,
    bool clearPhoto = false,
    int? axles,
    int? trailerAxles,
  }) =>
      BikeProfile(
        brand: brand ?? this.brand,
        model: model ?? this.model,
        style: style ?? this.style,
        color: color ?? this.color,
        photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
        axles: axles ?? this.axles,
        trailerAxles: trailerAxles ?? this.trailerAxles,
      );

  /// Formato salvo no celular e no Firestore (membro da expedição).
  Map<String, dynamic> toMap() => {
        'brand': brand,
        'model': model,
        'style': style.name,
        'color': color,
        'photoUrl': photoUrl,
        if (axles != null) 'axles': axles,
        if (trailerAxles > 0) 'trailerAxles': trailerAxles,
      };

  factory BikeProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BikeProfile();
    return BikeProfile(
      brand: m['brand'] ?? '',
      model: m['model'] ?? '',
      style: BikeStyle.fromName(m['style'] as String?),
      color: (m['color'] as num?)?.toInt() ?? 0xFFFF9800,
      photoUrl: safePhotoUrl(m['photoUrl']),
      axles: (m['axles'] as num?)?.toInt().clamp(2, 20),
      trailerAxles: ((m['trailerAxles'] as num?)?.toInt() ?? 0).clamp(0, 2),
    );
  }

  /// Endereço permitido para a foto: só o Storage do próprio app, na pasta
  /// bikes/ (lá as regras limitam a 2 MB e a imagens JPEG/PNG/WebP).
  /// Qualquer outro endereço vindo do servidor é ignorado (segurança: ninguém
  /// faz o celular do grupo baixar arquivos de sites de terceiros).
  static const photoPrefix =
      'https://firebasestorage.googleapis.com/v0/b/helpaitechcomboio.firebasestorage.app/o/bikes%2F';

  static String? safePhotoUrl(Object? url) {
    if (url is! String || url.length > 400) return null;
    if (!url.startsWith(photoPrefix)) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'firebasestorage.googleapis.com') return null;
    return url;
  }
}
