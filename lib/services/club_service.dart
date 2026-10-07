// ============================================================================
// club_service.dart — Motoclube
//
// O que faz: Clubes, membros e as chamadas às Cloud Functions de membros
//   próximos e avisos (sem revelar a posição exata de ninguém).
// Quem usa: ClubScreen, MapScreen, ClubNearbySheet.
// ============================================================================

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// Motoclube: código e nome.
class Club {
  final String id;
  final String name;
  final String createdBy;
  Club({required this.id, required this.name, required this.createdBy});
}

/// Membro do clube (nome e cidade; nunca a posição exata).
class ClubMember {
  final String uid;
  final String name;
  final String city;
  final String bike;
  ClubMember(
      {required this.uid,
      required this.name,
      required this.city,
      required this.bike});
}

/// Membro próximo devolvido pela Cloud Function: sem coordenadas,
/// só cidade e distância arredondada.
class NearbyMember {
  final String uid;
  final String name;
  final String city;
  final String bike;
  final int distanceKm;

  NearbyMember({
    required this.uid,
    required this.name,
    required this.city,
    required this.bike,
    required this.distanceKm,
  });

  factory NearbyMember.fromMap(Map<String, dynamic> m) => NearbyMember(
        uid: m['uid'] ?? '',
        name: m['name'] ?? 'Membro',
        city: m['city'] ?? '',
        bike: m['bike'] ?? '',
        distanceKm: (m['distanceKm'] as num?)?.toInt() ?? 0,
      );
}

/// Tipo de aviso para membros próximos: pedido de ajuda ou "estou
/// passando pela sua cidade".
enum ClubPurpose { help, passing }

/// Motoclubes no Firestore e as Cloud Functions de membros próximos.
class ClubService {
  ClubService._();
  static final instance = ClubService._();

  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Documento do clube no Firestore.
  DocumentReference<Map<String, dynamic>> _club(String id) =>
      _db.collection('clubs').doc(id);

  /// Código aleatório de 8 caracteres para um clube novo (antigos: 6).
  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Cria um clube e coloca o criador como membro. Devolve o código.
  Future<String> create(String name, String uid) async {
    String code;
    do {
      code = _randomCode();
    } while ((await _club(code).get()).exists);
    await _club(code).set({
      'name': name,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return code;
  }

  /// Procura um clube pelo código (null se não existir).
  Future<Club?> find(String id) async {
    final d = await _club(id).get();
    if (!d.exists) return null;
    final data = d.data()!;
    return Club(
        id: d.id, name: data['name'] ?? d.id, createdBy: data['createdBy'] ?? '');
  }

  /// Só grava a cidade se o usuário autorizou "ser encontrado".
  Future<void> join({
    required String clubId,
    required String uid,
    required String userName,
    required String city,
    required String bike,
  }) {
    return _club(clubId).collection('members').doc(uid).set({
      'name': userName,
      'city': city,
      'bike': bike,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Atualiza a cidade base do membro no clube.
  Future<void> updateCity(String clubId, String uid, String city) => _club(clubId)
      .collection('members')
      .doc(uid)
      .set({'city': city}, SetOptions(merge: true));

  /// Sai do clube.
  Future<void> leave(String clubId, String uid) =>
      _club(clubId).collection('members').doc(uid).delete();

  /// Membros do clube, em tempo real.
  Stream<List<ClubMember>> members(String clubId) =>
      _club(clubId).collection('members').snapshots().map((s) => s.docs
          .map((d) => ClubMember(
                uid: d.id,
                name: d.data()['name'] ?? 'Membro',
                city: d.data()['city'] ?? '',
                bike: d.data()['bike'] ?? '',
              ))
          .toList());

  /// Membros do clube que AUTORIZARAM o tipo de contato, do mais perto
  /// para o mais longe (até 300 km).
  Future<List<NearbyMember>> nearby({
    required String clubId,
    required double lat,
    required double lng,
    required ClubPurpose purpose,
  }) async {
    final res = await _fn.httpsCallable('clubNearby').call({
      'clubId': clubId,
      'lat': lat,
      'lng': lng,
      'purpose': purpose.name,
    });
    final list = (res.data['members'] as List?) ?? [];
    return list
        .map((m) => NearbyMember.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Avisa os membros próximos (Cloud Function clubNotify).
  Future<void> notify({
    required String clubId,
    required String targetUid,
    required ClubPurpose purpose,
    double? lat,
    double? lng,
    String? message,
    String? phone,
  }) async {
    await _fn.httpsCallable('clubNotify').call({
      'clubId': clubId,
      'targetUid': targetUid,
      'type': purpose.name,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (message != null && message.isNotEmpty) 'message': message,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
  }
}
