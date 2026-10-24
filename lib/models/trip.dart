// ============================================================================
// trip.dart — Viagem sem expedição
//
// O que faz: Rota de navegação sozinho ou de simulação: título, traçado,
//   paradas com manobras, tempo típico (para o atraso do trânsito), pedágio e
//   áreas de risco. Fica só no celular.
// Quem usa: TripService (monta), TripPreviewSheet, MapScreen.
// ============================================================================

import 'dart:math';

import 'expedition.dart';

/// Viagem sem expedição (navegação sozinho, tipo Waze) ou cópia de um
/// roteiro para simular. Fica só no celular: nada vai para o Firebase.
class Trip {
  /// Ex.: "Urubici" ou o nome da expedição.
  final String title;

  /// Traçado da rota (plan.polyline) e opções (pedágios, rodovias).
  final TripPlan plan;

  /// [saída, paradas..., destino], com trechos e manobras de navegação.
  final List<Stop> stops;

  /// Tempo típico total, sem o trânsito de agora (para medir o atraso).
  final int? typicalS;

  /// Áreas de risco reportadas perto da rota escolhida.
  final int riskCount;

  /// A rota passa por estrada com pedágio.
  final bool hasToll;

  /// Estrada principal da rota ("SP-330"), para o piloto escolher.
  final String summary;

  /// Outras rotas possíveis para o mesmo trajeto (só na prévia, sem paradas).
  final List<Trip> alternatives;

  const Trip(
      {required this.title,
      required this.plan,
      required this.stops,
      this.typicalS,
      this.riskCount = 0,
      this.hasToll = false,
      this.summary = '',
      this.alternatives = const []});

  /// A mesma viagem com outra lista de opções (ao trocar a rota escolhida).
  Trip withAlternatives(List<Trip> alts) => Trip(
      title: title,
      plan: plan,
      stops: stops,
      typicalS: typicalS,
      riskCount: riskCount,
      hasToll: hasToll,
      summary: summary,
      alternatives: alts);

  int get distanceM => stops.fold(0, (a, s) => a + s.legDistanceM);
  int get durationS => stops.fold(0, (a, s) => a + s.legDurationS);

  /// Atraso causado pelo trânsito agora (0 se a opção estiver desligada).
  int get trafficDelayS => typicalS == null ? 0 : max(0, durationS - typicalS!);

  /// Velocidade média da rota (m/s), usada na simulação.
  double get averageSpeed =>
      durationS > 0 ? distanceM / durationS : 60 / 3.6;
}
