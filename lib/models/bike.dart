// ============================================================================
// bike.dart — Perfil do veículo (moto ou carro)
//
// O que faz: Marca, modelo, tipo (estilos de moto, carro, picape), cor do
//   marcador e foto. Vai para o Firestore junto com o membro da expedição
//   (para os amigos verem).
// Quem usa: ProfileScreen (edita), MapScreen (ícone no mapa), pedágio (moto x
//   carro).
// Onde mexer: Tipos: enum BikeStyle (isCar). Marcas: bikeBrands / carBrands.
// ============================================================================

import 'package:flutter/material.dart';

/// Estilo da moto: define o ícone genérico usado quando não há foto.
enum BikeStyle {
  adventure('Big trail', Icons.two_wheeler),
  trail('Trail / Off-road', Icons.two_wheeler),
  custom('Custom', Icons.motorcycle),
  touring('Touring', Icons.motorcycle),
  naked('Naked / Street', Icons.two_wheeler),
  sport('Esportiva', Icons.sports_motorsports),
  scooter('Scooter', Icons.moped),
  // O app também serve para quem viaja de carro.
  car('Carro', Icons.directions_car),
  pickup('Picape / SUV', Icons.airport_shuttle);

  /// Moto (paga pedágio de moto, usa "moto" nos avisos) ou carro.
  bool get isCar => this == car || this == pickup;

  const BikeStyle(this.label, this.icon);
  final String label;
  final IconData icon;

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

/// Cores disponíveis para o marcador (ARGB).
const bikeColors = <int>[
  0xFFFF9800, 0xFF43A047, 0xFFE53935, 0xFF1E88E5, 0xFF212121,
  0xFF9E9E9E, 0xFFFFFFFF, 0xFFFDD835, 0xFF6D4C41, 0xFF8E24AA,
];

/// Veículo do piloto (moto ou carro): aparece no mapa para o grupo.
class BikeProfile {
  final String brand;
  final String model;
  final BikeStyle style;
  final int color;
  final String? photoUrl;

  const BikeProfile({
    this.brand = '',
    this.model = '',
    this.style = BikeStyle.adventure,
    this.color = 0xFFFF9800,
    this.photoUrl,
  });

  /// Ex: "Kawasaki Versys 650"
  String get displayName => [
        if (brand.isNotEmpty && brand != 'Outra') brand,
        if (model.isNotEmpty) model,
      ].join(' ');

  bool get isEmpty => displayName.isEmpty && photoUrl == null;

  String get cacheKey => '$brand|$model|${style.name}|$color|$photoUrl';

  /// Cópia com alguns campos trocados ([clearPhoto] remove a foto).
  BikeProfile copyWith({
    String? brand,
    String? model,
    BikeStyle? style,
    int? color,
    String? photoUrl,
    bool clearPhoto = false,
  }) =>
      BikeProfile(
        brand: brand ?? this.brand,
        model: model ?? this.model,
        style: style ?? this.style,
        color: color ?? this.color,
        photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      );

  /// Formato salvo no celular e no Firestore (membro da expedição).
  Map<String, dynamic> toMap() => {
        'brand': brand,
        'model': model,
        'style': style.name,
        'color': color,
        'photoUrl': photoUrl,
      };

  factory BikeProfile.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const BikeProfile();
    return BikeProfile(
      brand: m['brand'] ?? '',
      model: m['model'] ?? '',
      style: BikeStyle.fromName(m['style'] as String?),
      color: (m['color'] as num?)?.toInt() ?? 0xFFFF9800,
      photoUrl: m['photoUrl'] as String?,
    );
  }
}
