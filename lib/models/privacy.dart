/// Autorizações dadas pelo usuário (LGPD). Todas começam DESLIGADAS.
/// Se o texto das autorizações mudar, aumente [currentVersion] para que
/// todos precisem aceitar de novo.
class Consents {
  static const currentVersion = 1;

  /// Obrigatória para usar o app: posição ao vivo com o comboio.
  final bool shareLiveLocation;

  /// Aparecer (nome, cidade base, distância aproximada) para o clube.
  final bool findable;

  /// Receber pedidos de ajuda de membros do clube próximos.
  final bool receiveHelp;

  /// Receber avisos de membros do clube passando pela cidade.
  final bool receivePassing;

  final int version;

  const Consents({
    this.shareLiveLocation = false,
    this.findable = false,
    this.receiveHelp = false,
    this.receivePassing = false,
    this.version = currentVersion,
  });

  bool get isValid => shareLiveLocation && version == currentVersion;

  /// Cópia com algumas autorizações trocadas.
  Consents copyWith({
    bool? shareLiveLocation,
    bool? findable,
    bool? receiveHelp,
    bool? receivePassing,
  }) {
    final f = findable ?? this.findable;
    return Consents(
      shareLiveLocation: shareLiveLocation ?? this.shareLiveLocation,
      findable: f,
      // Sem "ser encontrado", ninguém consegue te contatar.
      receiveHelp: f && (receiveHelp ?? this.receiveHelp),
      receivePassing: f && (receivePassing ?? this.receivePassing),
    );
  }

  /// Formato salvo no celular e no Firestore (users/{uid}.consent).
  Map<String, dynamic> toMap() => {
        'shareLiveLocation': shareLiveLocation,
        'findable': findable,
        'receiveHelp': receiveHelp,
        'receivePassing': receivePassing,
        'version': version,
      };

  factory Consents.fromMap(Map<String, dynamic> m) => Consents(
        shareLiveLocation: m['shareLiveLocation'] == true,
        findable: m['findable'] == true,
        receiveHelp: m['receiveHelp'] == true,
        receivePassing: m['receivePassing'] == true,
        version: (m['version'] as num?)?.toInt() ?? 0,
      );
}

/// Cidade base do piloto, com posição arredondada (~1 km).
class BaseLocation {
  final double lat;
  final double lng;
  final String city;

  const BaseLocation({required this.lat, required this.lng, required this.city});

  /// Formato salvo (cidade base arredondada a ~1 km).
  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'city': city};

  factory BaseLocation.fromMap(Map<String, dynamic> m) => BaseLocation(
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        city: m['city'] ?? '',
      );
}
