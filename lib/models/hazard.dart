// ============================================================================
// hazard.dart — Alertas da comunidade (estilo Waze)
//
// O que faz: Tipos de alerta (polícia, radar móvel, buraco, pipas, área de
//   risco...) com emoji, cor, validade, distância do aviso e a frase falada; e
//   o alerta em si.
// Quem usa: HazardService (Firestore) e MapScreen (aviso, votação).
// Onde mexer: Novo tipo: inclua aqui E em firestore.rules (lista de tipos).
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Tipos de alerta, com emoji, cor, quanto tempo ficam no mapa se ninguém
/// confirmar, a distância em que o piloto é avisado e o nome falado.
enum HazardType {
  police('Polícia', '🚓', Color(0xFF1E88E5), Duration(hours: 1), 500,
      'polícia na pista'),
  radar('Radar móvel', '📷', Color(0xFFD32F2F), Duration(hours: 4), 1000,
      'radar móvel'),
  pothole('Buraco', '🕳️', Color(0xFF6D4C41), Duration(days: 7), 500,
      'buraco'),
  // Lombada nova ou que não está no mapa (as conhecidas vêm do OpenStreetMap).
  bump('Lombada', '🚧', Color(0xFFF9A825), Duration(days: 7), 500,
      'lombada'),
  danger('Perigo na pista', '⚠️', Color(0xFFFFA000), Duration(hours: 3), 500,
      'perigo na pista'),
  oil('Óleo / areia', '🛢️', Color(0xFF546E7A), Duration(hours: 12), 500,
      'óleo ou areia na pista'),
  animal('Animal na pista', '🐄', Color(0xFF7CB342), Duration(hours: 1), 500,
      'animal na pista'),
  accident('Acidente', '💥', Color(0xFFE53935), Duration(hours: 3), 500,
      'acidente'),
  fog('Neblina', '🌫️', Color(0xFF90A4AE), Duration(hours: 3), 500,
      'neblina'),
  kite('Pipas / cerol', '🪁', Color(0xFFD81B60), Duration(days: 2), 500,
      'área de pipas, cuidado com linha com cerol'),
  // Fica 7 dias: é a base da opção de rota "Evitar locais de risco".
  risk('Área de risco / assalto', '🚨', Color(0xFFB71C1C), Duration(days: 7),
      1000, 'área de risco, com relatos de assalto'),
  // Radar fixo e semáforo que faltam no mapa: viram permanentes (veja
  // canBePermanent).
  fixedRadar('Radar fixo', '📸', Color(0xFFD32F2F), Duration(days: 7), 1000,
      'radar fixo'),
  signal('Semáforo', '🚦', Color(0xFF2E7D32), Duration(days: 7), 300,
      'semáforo'),
  // Marcado sozinho quando um usuário (com a opção ligada) para no
  // acostamento de rodovia; some quando ele volta a andar.
  stoppedVehicle('Veículo parado', '🚗', Color(0xFFFF7043),
      Duration(minutes: 30), 500, 'veículo parado no acostamento');

  /// Tipos que não mudam (lombada, radar fixo, semáforo): ficam FIXOS no mapa
  /// na 3ª confirmação, ou já ao serem marcados por um usuário Gold.
  bool get canBePermanent => this == bump || this == fixedRadar || this == signal;

  const HazardType(this.label, this.emoji, this.color, this.lifetime,
      this.alertMeters, this.spoken);
  final String label;
  final String emoji;
  final Color color;
  final Duration lifetime;

  /// A que distância (à frente) o piloto é avisado.
  final double alertMeters;

  /// Como a voz fala o alerta ("Atenção: buraco a 400 metros").
  final String spoken;

  /// Lê o tipo salvo pelo nome; null se for um tipo que o app não conhece.
  static HazardType? fromName(String? name) {
    for (final t in HazardType.values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

/// Um alerta reportado: tipo, posição, quem reportou, votos e validade.
class Hazard {
  final String id;
  final HazardType type;
  final double lat;
  final double lng;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? lastConfirmedAt;
  final DateTime expiresAt;
  final int confirmations;
  final int dismissals;

  /// Fixo no mapa (não expira); [gold] = marcado por usuário Gold.
  final bool permanent;
  final bool gold;

  Hazard({
    required this.id,
    required this.type,
    required this.lat,
    required this.lng,
    required this.createdBy,
    required this.expiresAt,
    this.createdAt,
    this.lastConfirmedAt,
    this.confirmations = 1,
    this.dismissals = 0,
    this.permanent = false,
    this.gold = false,
  });

  bool get isActive => expiresAt.isAfter(DateTime.now());

  /// Última vez que alguém viu o perigo.
  DateTime? get lastSeen => lastConfirmedAt ?? createdAt;

  /// Lê do Firestore; null se faltar campo ou o tipo for desconhecido.
  static Hazard? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    final type = HazardType.fromName(d['type'] as String?);
    final exp = d['expiresAt'];
    if (type == null || exp is! Timestamp) return null;
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return Hazard(
      id: doc.id,
      type: type,
      lat: (d['lat'] as num).toDouble(),
      lng: (d['lng'] as num).toDouble(),
      createdBy: d['createdBy'] ?? '',
      createdAt: ts(d['createdAt']),
      lastConfirmedAt: ts(d['lastConfirmedAt']),
      expiresAt: exp.toDate(),
      confirmations: (d['confirmations'] as num?)?.toInt() ?? 1,
      dismissals: (d['dismissals'] as num?)?.toInt() ?? 0,
      permanent: d['permanent'] == true,
      gold: d['gold'] == true,
    );
  }
}
