// ============================================================================
// expedition.dart — Expedição em grupo
//
// O que faz: Formatos guardados no Firestore: Expedition, TripPlan (rota e
//   opções), Member (posição de cada piloto), Stop (parada com manobras),
//   SosAlert, StopType.
// Quem usa: ExpeditionService, MapScreen, PlanScreen.
// Onde mexer: Versão do cálculo da rota: TripPlan.currentRouteVersion.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

import '../logic/navigation.dart';
import 'bike.dart';
import '../l10n/i18n.dart';

typedef Doc = DocumentSnapshot<Map<String, dynamic>>;

/// Data de um campo do Firestore (Timestamp) ou null.
DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;
double? _num(dynamic v) => (v as num?)?.toDouble();

/// Expedição: nome, código, líder, papéis e o plano (rota e opções).
class Expedition {
  final String code;
  final String name;
  final String leaderId;
  final TripPlan plan;

  /// Capitão (puxa o comboio): só o desvio dele recalcula a rota de todos.
  /// Sem capitão definido, é o líder.
  final String captainId;

  /// Ferrolhos (fecham o comboio): até 3. Veem quem saiu do trajeto.
  final List<String> sweepers;

  /// Máximo de ferrolhos.
  static const maxSweepers = 3;

  Expedition({
    required this.code,
    required this.name,
    required this.leaderId,
    this.plan = const TripPlan(),
    String? captainId,
    this.sweepers = const [],
  }) : captainId = captainId == null || captainId.isEmpty ? leaderId : captainId;

  factory Expedition.fromDoc(Doc doc) {
    final d = doc.data() ?? {};
    return Expedition(
      code: doc.id,
      name: d['name'] ?? tr('Expedição'),
      leaderId: d['leaderId'] ?? '',
      plan: TripPlan.fromMap(d['plan'] as Map<String, dynamic>?),
      captainId: d['captainId'] as String?,
      sweepers: [
        for (final s in (d['sweepers'] as List? ?? const []))
          if (s is String) s,
      ],
    );
  }
}

/// Planejamento do roteiro (fica no documento da expedição; só o líder edita).
class TripPlan {
  /// Data de saída no formato aaaa-mm-dd (vazio = não definida).
  final String startDate;

  /// Hora de saída do 1º dia, "HH:mm".
  final String startTime;
  final bool avoidTolls;
  final bool avoidHighways;

  /// Rota pelas estradas (polyline codificada do Google), já calculada.
  final String polyline;

  /// Versão do cálculo da rota. 2 = traçado detalhado (segue as curvas);
  /// rotas antigas (1) são recalculadas quando o líder abre o roteiro.
  final int routeVersion;
  static const currentRouteVersion = 2;

  const TripPlan({
    this.startDate = '',
    this.startTime = '08:00',
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.polyline = '',
    this.routeVersion = 1,
  });

  factory TripPlan.fromMap(Map<String, dynamic>? d) {
    if (d == null) return TripPlan();
    return TripPlan(
      startDate: d['startDate'] ?? '',
      startTime: d['startTime'] ?? '08:00',
      avoidTolls: d['avoidTolls'] == true,
      avoidHighways: d['avoidHighways'] == true,
      polyline: d['polyline'] ?? '',
      routeVersion: (d['routeVersion'] as num?)?.toInt() ?? 1,
    );
  }

  /// Formato salvo no Firestore (campo "plan" da expedição).
  Map<String, dynamic> toMap() => {
        'startDate': startDate,
        'startTime': startTime,
        'avoidTolls': avoidTolls,
        'avoidHighways': avoidHighways,
        'polyline': polyline,
        'routeVersion': routeVersion,
      };

  /// Cópia com alguns campos trocados (a versão da rota é mantida).
  TripPlan copyWith({
    String? startDate,
    String? startTime,
    bool? avoidTolls,
    bool? avoidHighways,
    String? polyline,
  }) =>
      TripPlan(
        startDate: startDate ?? this.startDate,
        startTime: startTime ?? this.startTime,
        avoidTolls: avoidTolls ?? this.avoidTolls,
        avoidHighways: avoidHighways ?? this.avoidHighways,
        polyline: polyline ?? this.polyline,
        routeVersion: routeVersion,
      );
}

/// Um piloto da expedição: nome, veículo, última posição e velocidade.
class Member {
  final String uid;
  final String name;
  final double? lat;
  final double? lng;
  final double speed; // m/s
  final double heading; // graus (0 = norte)
  final DateTime? updatedAt;
  final BikeProfile bike;

  Member({
    required this.uid,
    required this.name,
    this.lat,
    this.lng,
    this.speed = 0,
    this.heading = 0,
    this.updatedAt,
    this.bike = const BikeProfile(),
  });

  bool get hasLocation => lat != null && lng != null;

  /// Sem atualização há mais de 5 minutos = provavelmente sem sinal.
  bool get isStale =>
      updatedAt == null ||
      DateTime.now().difference(updatedAt!) > Duration(minutes: 5);

  factory Member.fromDoc(Doc doc) {
    final d = doc.data() ?? {};
    return Member(
      uid: doc.id,
      name: d['name'] ?? tr('Piloto'),
      lat: _num(d['lat']),
      lng: _num(d['lng']),
      speed: _num(d['speed']) ?? 0,
      heading: _num(d['heading']) ?? 0,
      updatedAt: _date(d['updatedAt']),
      bike: BikeProfile.fromMap(d['bike'] as Map<String, dynamic>?),
    );
  }
}

/// Tipos de ponto do roteiro. O valor (`name`) é o que vai para o Firestore.
enum StopType {
  meet('Ponto de encontro', '🤝'),
  fuel('Abastecimento', '⛽'),
  food('Refeição', '🍽️'),
  rest('Descanso', '☕'),
  sight('Ponto turístico', '📸'),
  overnight('Pernoite', '🛏️'),
  waypoint('Passagem', '📍'),
  destination('Destino', '🏁');

  const StopType(this._label, this.emoji);
  final String _label;
  String get label => tr(_label);
  final String emoji;

  /// Lê o tipo salvo pelo nome (desconhecido = ponto de passagem).
  static StopType parse(String? v) => StopType.values
      .firstWhere((t) => t.name == v, orElse: () => StopType.waypoint);
}

/// Parada do roteiro: posição, tipo, ordem, tempo parado e o trecho até
/// ela (distância, tempo e as manobras para a narração).
class Stop {
  final String id;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final int order;
  final String createdBy;
  final StopType type;

  /// Tempo parado neste ponto, em minutos.
  final int stayMin;
  final String notes;

  /// Para pernoite: hora de saída no dia seguinte ("HH:mm").
  final String nextDayStart;

  /// Trecho que CHEGA neste ponto (vindo do anterior), calculado pela rota.
  final int legDistanceM;
  final int legDurationS;

  /// Manobras desse trecho, para a narração curva a curva.
  final List<NavStep> steps;

  Stop({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.order,
    required this.createdBy,
    this.address = '',
    this.type = StopType.waypoint,
    this.stayMin = 0,
    this.notes = '',
    this.nextDayStart = '08:00',
    this.legDistanceM = 0,
    this.legDurationS = 0,
    this.steps = const [],
  });

  factory Stop.fromDoc(Doc doc) {
    final d = doc.data() ?? {};
    return Stop(
      id: doc.id,
      name: d['name'] ?? tr('Parada'),
      address: d['address'] ?? '',
      lat: _num(d['lat']) ?? 0,
      lng: _num(d['lng']) ?? 0,
      order: (d['order'] as num?)?.toInt() ?? 0,
      createdBy: d['createdBy'] ?? '',
      type: StopType.parse(d['type'] as String?),
      stayMin: (d['stayMin'] as num?)?.toInt() ?? 0,
      notes: d['notes'] ?? '',
      nextDayStart: d['nextDayStart'] ?? '08:00',
      legDistanceM: (d['legDistanceM'] as num?)?.toInt() ?? 0,
      legDurationS: (d['legDurationS'] as num?)?.toInt() ?? 0,
      steps: ((d['steps'] as List?) ?? const [])
          .map(NavStep.fromMap)
          .whereType<NavStep>()
          .toList(),
    );
  }
}

/// Pedido de socorro de um membro (ativo até alguém marcar resolvido).
class SosAlert {
  final String id;
  final String uid;
  final String name;
  final double lat;
  final double lng;
  final DateTime? createdAt;

  SosAlert({
    required this.id,
    required this.uid,
    required this.name,
    required this.lat,
    required this.lng,
    this.createdAt,
  });

  factory SosAlert.fromDoc(Doc doc) {
    final d = doc.data() ?? {};
    return SosAlert(
      id: doc.id,
      uid: d['uid'] ?? '',
      name: d['name'] ?? tr('Piloto'),
      lat: _num(d['lat']) ?? 0,
      lng: _num(d['lng']) ?? 0,
      createdAt: _date(d['createdAt']),
    );
  }
}
