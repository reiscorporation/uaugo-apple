// ============================================================================
// expedition_service.dart — Expedição no Firestore
//
// O que faz: Criar, entrar, sair, encerrar para todos, membros e posições,
//   paradas, SOS e o cálculo da rota do roteiro.
// Quem usa: Home, MapScreen, PlanScreen.
// Onde mexer: Estrutura no banco: docs/ARQUITETURA.md, seção 6.
// ============================================================================

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../logic/itinerary.dart';
import '../logic/navigation.dart';
import '../models/bike.dart';
import '../models/expedition.dart';
import 'app_settings.dart';
import 'directions_service.dart';

/// Estrutura no Firestore:
/// expeditions/{CODIGO}
///   members/{uid}   -> nome e última posição
///   stops/{id}      -> paradas da rota
///   alerts/{id}     -> pedidos de SOS
///
/// Escritas de posição, paradas e SOS NÃO são aguardadas (sem `await`):
/// sem sinal, o Firestore guarda no aparelho e envia quando a conexão voltar.
class ExpeditionService {
  ExpeditionService._();
  static final instance = ExpeditionService._();

  final _db = FirebaseFirestore.instance;

  /// Documento da expedição no Firestore.
  DocumentReference<Map<String, dynamic>> _exp(String code) =>
      _db.collection('expeditions').doc(code);

  /// Código aleatório de 8 caracteres (sem letras que confundem). São 32^8
  /// (~1 trilhão) combinações: inviável adivinhar o código de um grupo.
  /// Códigos antigos de 6 caracteres continuam valendo.
  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Cria a expedição (o criador vira líder e membro). Devolve o código.
  Future<String> create({
    required String name,
    required String uid,
    required String userName,
  }) async {
    String code;
    do {
      code = _randomCode();
    } while ((await _exp(code).get()).exists);

    await _exp(code).set({
      'name': name,
      'leaderId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      // Começa com as preferências de rota do líder (Configurações → Rotas).
      'plan': TripPlan(
        avoidTolls: AppSettings.instance.route.value.avoidTolls,
        avoidHighways: AppSettings.instance.route.value.avoidHighways,
      ).toMap(),
    });
    await join(code: code, uid: uid, userName: userName);
    return code;
  }

  /// Procura uma expedição pelo código (null se não existir).
  Future<Expedition?> find(String code) async {
    final doc = await _exp(code).get();
    return doc.exists ? Expedition.fromDoc(doc) : null;
  }

  /// Entra na expedição como membro (nome e veículo).
  Future<void> join({
    required String code,
    required String uid,
    required String userName,
  }) {
    return _exp(code).collection('members').doc(uid).set({
      'name': userName,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Publica a moto do piloto para o comboio.
  void updateBike(String code, String uid, BikeProfile bike) {
    _exp(code)
        .collection('members')
        .doc(uid)
        .set({'bike': bike.toMap()}, SetOptions(merge: true));
  }

  /// Sai da expedição (apaga só o próprio membro).
  Future<void> leave(String code, String uid) =>
      _exp(code).collection('members').doc(uid).delete();

  /// Líder encerra para todos: a Cloud Function apaga a expedição inteira
  /// (membros, paradas, SOS). Cada piloto já tem a viagem salva no celular.
  Future<void> endExpedition(String code) => FirebaseFunctions.instanceFor(
          region: 'southamerica-east1')
      .httpsCallable('endExpedition')
      .call({'code': code});

  /// Expedição em tempo real (null quando o líder encerra).
  Stream<Expedition?> watchExpedition(String code) => _exp(code)
      .snapshots()
      .map((d) => d.exists ? Expedition.fromDoc(d) : null);

  // ---------- Posições ----------
  void updateLocation(String code, String uid, Position p) {
    _exp(code).collection('members').doc(uid).set({
      'lat': p.latitude,
      'lng': p.longitude,
      'speed': p.speed < 0 ? 0 : p.speed,
      'heading': p.heading,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Membros em tempo real (posições do grupo no mapa).
  Stream<List<Member>> members(String code) => _exp(code)
      .collection('members')
      .snapshots()
      .map((s) => s.docs.map(Member.fromDoc).toList());

  // ---------- Paradas ----------
  Stream<List<Stop>> stops(String code) => _exp(code)
      .collection('stops')
      .orderBy('order')
      .snapshots()
      .map((s) => s.docs.map(Stop.fromDoc).toList());

  /// Adiciona um ponto ao roteiro e retorna o id. Sem [order], vai para o final.
  /// A escrita não é aguardada (funciona sem sinal), então o id sai na hora.
  String addStop(
    String code,
    String uid,
    String name,
    double lat,
    double lng, {
    String address = '',
    StopType type = StopType.waypoint,
    int stayMin = 0,
    int? order,
  }) {
    final ref = _exp(code).collection('stops').doc();
    ref.set({
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'type': type.name,
      'stayMin': stayMin,
      'notes': '',
      'nextDayStart': '08:00',
      'order': order ?? DateTime.now().millisecondsSinceEpoch,
      'createdBy': uid,
    });
    return ref.id;
  }

  /// Coloca um ponto no roteiro na posição certa (antes do destino) e
  /// recalcula a rota. Retorna false se a rota não pôde ser recalculada.
  Future<bool> addToItinerary({
    required String code,
    required String uid,
    required TripPlan plan,
    required List<Stop> current,
    required String name,
    required double lat,
    required double lng,
    String address = '',
  }) async {
    final at = insertIndexFor(current);
    final type = defaultTypeFor(current);
    final id = addStop(code, uid, name, lat, lng,
        address: address, type: type, order: at);
    final list = [...current]..insert(
        at,
        Stop(
          id: id,
          name: name,
          lat: lat,
          lng: lng,
          order: at,
          createdBy: uid,
          address: address,
          type: type,
        ));
    await reorderStops(code, list.map((s) => s.id).toList());
    return recalculateRoute(code, plan, list);
  }

  /// Altera uma parada (nome, tipo, tempo parado...).
  Future<void> updateStop(String code, String stopId, Map<String, dynamic> data) =>
      _exp(code).collection('stops').doc(stopId).update(data);

  /// Remove uma parada.
  Future<void> removeStop(String code, String stopId) =>
      _exp(code).collection('stops').doc(stopId).delete();

  /// Grava a nova ordem dos pontos (0, 1, 2...).
  Future<void> reorderStops(String code, List<String> ids) {
    final batch = _db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(_exp(code).collection('stops').doc(ids[i]), {'order': i});
    }
    return batch.commit();
  }

  /// Salva o plano (data, hora, opções) sem recalcular a rota.
  Future<void> savePlan(String code, TripPlan plan) =>
      _exp(code).update({'plan': plan.toMap()});

  /// Papéis: o líder define capitão e até 3 ferrolhos; o capitão só passa a
  /// capitania (o novo capitão sai dos ferrolhos).
  Future<void> setRoles(String code, String captainId, List<String> sweepers) =>
      _exp(code).update({
        'captainId': captainId,
        'sweepers': sweepers.take(Expedition.maxSweepers).toList(),
      });

  /// O CAPITÃO saiu da rota: a rota da expedição passa a sair da posição
  /// dele e seguir pelas paradas que faltam ([remaining]); vale para todos.
  /// As paradas já passadas ([passed]) perdem as manobras antigas.
  Future<bool> rerouteFromCaptain(String code, TripPlan plan, double lat,
      double lng, List<Stop> remaining, List<Stop> passed) async {
    if (remaining.isEmpty) return false;
    final r = await DirectionsService.detailedRoute(
      [LatLng(lat, lng), ...remaining.map((s) => LatLng(s.lat, s.lng))],
      avoidTolls: plan.avoidTolls,
      avoidHighways: plan.avoidHighways,
    );
    if (r == null || r.legs.length != remaining.length) return false;
    final batch = _db.batch();
    for (final s in passed) {
      batch.update(_exp(code).collection('stops').doc(s.id), {'steps': []});
    }
    for (var i = 0; i < remaining.length; i++) {
      batch.update(_exp(code).collection('stops').doc(remaining[i].id), {
        'legDistanceM': r.legs[i].distanceM,
        'legDurationS': r.legs[i].durationS,
        'steps': (i < r.legSteps.length ? r.legSteps[i] : const <NavStep>[])
            .map((s) => s.toMap())
            .toList(),
      });
    }
    batch.update(_exp(code), {
      'plan.polyline': r.polyline,
      'plan.routeVersion': TripPlan.currentRouteVersion,
    });
    await batch.commit();
    return true;
  }

  /// Recalcula a rota pelas estradas e grava o traçado e os trechos, para
  /// que os pilotos não precisem chamar a API de rotas (economia).
  /// Retorna false se não foi possível calcular (sem chave/internet).
  Future<bool> recalculateRoute(
      String code, TripPlan plan, List<Stop> stops) async {
    if (stops.length < 2) {
      await _exp(code).update({'plan.polyline': ''});
      return true;
    }
    final r = await DirectionsService.detailedRoute(
      stops.map((s) => LatLng(s.lat, s.lng)).toList(),
      avoidTolls: plan.avoidTolls,
      avoidHighways: plan.avoidHighways,
    );
    if (r == null || r.legs.length != stops.length - 1) return false;
    final batch = _db.batch();
    for (var i = 0; i < stops.length; i++) {
      final leg = i == 0 ? const RouteLeg(0, 0) : r.legs[i - 1];
      final steps = i == 0 || i - 1 >= r.legSteps.length
          ? const <NavStep>[]
          : r.legSteps[i - 1];
      batch.update(_exp(code).collection('stops').doc(stops[i].id), {
        'legDistanceM': leg.distanceM,
        'legDurationS': leg.durationS,
        // Manobras do trecho que chega aqui (narração curva a curva).
        'steps': steps.map((s) => s.toMap()).toList(),
      });
    }
    batch.update(_exp(code), {
      'plan.polyline': r.polyline,
      'plan.routeVersion': TripPlan.currentRouteVersion,
    });
    await batch.commit();
    return true;
  }

  // ---------- SOS ----------
  String sendSos(
      String code, String uid, String name, double lat, double lng) {
    final ref = _exp(code).collection('alerts').doc();
    ref.set({
      'uid': uid,
      'name': name,
      'lat': lat,
      'lng': lng,
      'resolved': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Marca um SOS como resolvido.
  void resolveAlert(String code, String alertId) {
    _exp(code).collection('alerts').doc(alertId).update({
      'resolved': true,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// SOS ativos do grupo, em tempo real.
  Stream<List<SosAlert>> activeAlerts(String code) => _exp(code)
      .collection('alerts')
      .where('resolved', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.map(SosAlert.fromDoc).toList());
}
