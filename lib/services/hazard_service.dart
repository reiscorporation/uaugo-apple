// ============================================================================
// hazard_service.dart — Alertas da comunidade no Firestore
//
// O que faz: Escuta os alertas da região (células de ~11 km), grava novos,
//   confirma/descarta (votos) e busca áreas de risco para a opção de rota.
// Quem usa: MapScreen e DirectionsService (evitar locais de risco).
// Onde mexer: Validade de cada tipo: models/hazard.dart.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  /// Usuário Gold? (gold/{uid}, gravado só pelo responsável; o app só lê
  /// o próprio). Guardado na memória depois da 1ª leitura.
  Future<bool> isGold(String uid) async {
    final c = _gold;
    if (c != null && c.$1 == uid) return c.$2;
    try {
      final d = await FirebaseFirestore.instance.doc('gold/$uid').get();
      _gold = (uid, d.exists);
      return d.exists;
    } catch (_) {
      return false;
    }
  }

  (String, bool)? _gold;

  /// Grava o alerta. O Future termina quando o servidor confirma (sem
  /// internet, o Firestore guarda e envia quando a conexão voltar). Usuário
  /// Gold marcando lombada/radar fixo/semáforo: já nasce fixo no mapa.
  Future<void> report(HazardType type, double lat, double lng, String uid) async {
    final (la, lo) = cellOf(lat, lng);
    final fixed = type.canBePermanent && await isGold(uid);
    return _col.doc().set({
      'type': type.name,
      'lat': lat,
      'lng': lng,
      'cell': cellKey(la, lo),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
          fixed ? permanentExpiry : DateTime.now().add(type.lifetime)),
      'confirmations': 1,
      'dismissals': 0,
      if (fixed) ...{'permanent': true, 'gold': true},
    });
  }

  /// Grava o voto e a contagem no mesmo lote. As regras do Firestore aceitam
  /// UM voto por pessoa em cada alerta (hazards/{id}/votes/{uid}); o voto é
  /// apagado sozinho pelo TTL (campo expiresAt), como o próprio alerta.
  void _vote(Hazard h, bool up, Map<String, dynamic> changes) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final batch = FirebaseFirestore.instance.batch()
      ..set(_col.doc(h.id).collection('votes').doc(uid), {
        'up': up,
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
      })
      ..update(_col.doc(h.id), changes);
    batch.commit().catchError((_) {}); // já votou: o servidor recusa
  }

  /// "Ainda está lá": renova o prazo do alerta. Lombada/radar fixo/semáforo
  /// na 3ª confirmação fica fixo no mapa; o que já é fixo só conta o voto.
  void confirm(Hazard h) {
    final becomesFixed = !h.permanent &&
        h.type.canBePermanent &&
        h.confirmations + 1 >= permanentAfterConfirmations;
    _vote(h, true, {
      'confirmations': FieldValue.increment(1),
      'lastConfirmedAt': FieldValue.serverTimestamp(),
      if (becomesFixed) ...{
        'permanent': true,
        'expiresAt': Timestamp.fromDate(permanentExpiry),
      } else if (!h.permanent)
        'expiresAt': Timestamp.fromDate(DateTime.now().add(h.type.lifetime)),
    });
  }

  /// "Não está mais": com 2 votos (ou mais votos contra do que a favor),
  /// o alerta some do mapa. [force]: o autor removendo o próprio alerta.
  void dismiss(Hazard h, {bool force = false}) {
    final remove = shouldRemoveHazard(
        confirmations: h.confirmations,
        dismissals: h.dismissals,
        force: force,
        permanent: h.permanent,
        gold: h.gold);
    _vote(h, false, {
      'dismissals': FieldValue.increment(1),
      // Hora do servidor: as regras só aceitam "agora" para remover.
      if (remove) 'expiresAt': FieldValue.serverTimestamp(),
    });
  }
}
