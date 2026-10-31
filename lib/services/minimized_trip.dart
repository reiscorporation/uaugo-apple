// ============================================================================
// minimized_trip.dart — Viagem minimizada, esperando para ser retomada
//
// O que faz: Guarda a rota quando o piloto toca em "Minimizar" e volta para a
//   tela inicial. A tela inicial mostra o cartão "Retomar a navegação" e
//   pergunta antes de abrir o mapa. Só na memória: fechar o app apaga.
// Quem usa: MapScreen (Minimizar) e HomeScreen (retomar).
// ============================================================================

import 'package:flutter/foundation.dart';

import '../models/trip.dart';

class MinimizedTrip {
  MinimizedTrip._();

  /// Viagem à espera (null = nenhuma).
  static final trip = ValueNotifier<Trip?>(null);
}
