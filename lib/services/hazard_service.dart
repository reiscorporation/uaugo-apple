// ============================================================================
// hazard_service.dart — Alertas da comunidade no Firestore
//
// O que faz: Escuta os alertas da região (células de ~11 km), grava novos,
//   confirma/descarta (votos) e busca áreas de risco para a opção de rota.
// Quem usa: MapScreen e DirectionsService (evitar locais de risco).
// Onde mexer: Validade de cada tipo: models/hazard.dart.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

import '../logic/geo.dart';
import '../models/hazard.dart';

/// Alertas públicos (visíveis para todos os usuários do app).
///
/// O mundo é dividido em "células" de 0,1° (~11 km). Cada alerta guarda a
/// célula onde está, e o app escuta só a célula atual + as 8 vizinhas
/// (~33 km x 33 km). Assim ninguém baixa os alertas do país inteiro.
///
/// Configure no Firestore uma política de TTL no campo `expiresAt` da
/// coleção `hazards` para que alertas vencidos sejam apagados sozinhos.
class HazardService {
  HazardService._();
  static final instance = HazardService._();

  final _col = FirebaseFirestore.instance.collection('hazards');

  static (int, int) cellOf(double lat, double lng) =>
      ((lat * 10).floor(), (lng * 10).floor());

  /// Chave da célula: "-276_-486".
  static String cellKey(int la, int lo) => '${la}_$lo';

  /// Alertas ativos da célula atual e das 8 vizinhas, em tempo real.
  Stream<List<Hazard>> watchAround(double lat, double lng) {
    final (la, lo) = cellOf(lat, lng);
    final keys = [
      for (var i = -1; i <= 1; i++)
        for (var j = -1; j <= 1; j++) cellKey(la + i, lo + j),
    ];
    return _col.where('cell', whereIn: keys).snapshots().map((s) => s.docs
        .map(Hazard.fromDoc)
        .whereType<Hazard>()
        .where((h) => h.isActive)
        .toList());
  }

  /// Áreas de risco ativas (todas: são poucas), para a opção de rota
  /// "Evitar locais de risco". Lista vazia sem internet.
  Future<List<Hazard>> activeRisks() async {
    // Guarda por 10 min: o recálculo de rota não pode esperar o servidor.
    final c = _risksCache;
    if (c != null &&
        DateTime.now().difference(c.$1) < const Duration(minutes: 10)) {
      return c.$2;
    }
    final r = await _fetchRisks();
    _risksCache = (DateTime.now(), r);
    return r;
  }

  (DateTime, List<Hazard>)? _risksCache;

  /// Busca no servidor as áreas de risco ativas (com limite de 8 s).
  Future<List<Hazard>> _fetchRisks() async {
    try {
      final s = await _col
          .where('type', isEqualTo: HazardType.risk.name)
          .get()
          .timeout(const Duration(seconds: 8));
      return s.docs
          .map(Hazard.fromDoc)
          .whereType<Hazard>()
          .where((h) => h.isActive)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Grava o alerta. O Future termina quando o servidor confirma (sem
  /// internet, o Firestore guarda e envia quando a conexão voltar).
  Future<void> report(HazardType type, double lat, double lng, String uid) {
    final (la, lo) = cellOf(lat, lng);
    return _col.doc().set({
      'type': type.name,
      'lat': lat,
      'lng': lng,
      'cell': cellKey(la, lo),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(type.lifetime)),
      'confirmations': 1,
      'dismissals': 0,
    });
  }

  /// "Ainda está lá": renova o prazo do alerta.
  void confirm(Hazard h) {
    _col.doc(h.id).update({
      'confirmations': FieldValue.increment(1),
      'lastConfirmedAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(h.type.lifetime)),
    });
  }

  /// "Não está mais": com 2 votos (ou mais votos contra do que a favor),
  /// o alerta some do mapa.
  void dismiss(Hazard h, {bool force = false}) {
    final remove = shouldRemoveHazard(
        confirmations: h.confirmations, dismissals: h.dismissals, force: force);
    _col.doc(h.id).update({
      'dismissals': FieldValue.increment(1),
      if (remove) 'expiresAt': Timestamp.now(),
    });
  }
}
