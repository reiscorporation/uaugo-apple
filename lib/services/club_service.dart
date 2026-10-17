// ============================================================================
// club_service.dart — Clube
//
// O que faz: Clube OFICIAL. Os ADMINISTRADORES de cada clube ativam o
//   acesso com um código de ativação fornecido pela HelpAITech (clubes já
//   pré-cadastrados ou novos). Os administradores geram convites de uso único
//   para os membros, removem membros e promovem outros administradores. Tudo
//   isso é conferido no servidor (functions/clubs.js). Também: membros,
//   membros próximos e avisos (sem revelar a posição exata de ninguém).
// Quem usa: ClubScreen, MapScreen, ClubNearbySheet, ConsentScreen.
// Onde mexer: Clubes pré-cadastrados: scripts/criar-clubes.js. Códigos de
//   ativação: scripts/gerar-codigos-clube.js.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Clube: código interno, nome e administradores.
class Club {
  final String id;
  final String name;
  final List<String> admins;
  Club({required this.id, required this.name, this.admins = const []});

  /// O usuário atual administra este clube?
  bool get iAmAdmin =>
      admins.contains(FirebaseAuth.instance.currentUser?.uid ?? '-');
}

/// Convite de uso único gerado por um administrador.
class ClubInvite {
  final String code; // 8 caracteres, mostrado como XXXX-XXXX
  final DateTime expiresAt;
  const ClubInvite(this.code, this.expiresAt);

  /// "ABCD2345" -> "ABCD-2345" (mais fácil de ditar e digitar).
  String get display =>
      code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
}

/// Membro do clube (nome e cidade; nunca a posição exata).
class ClubMember {
  final String uid;
  final String name;
  final String city;
  final String bike;
  final bool isAdmin;
  ClubMember(
      {required this.uid,
      required this.name,
      required this.city,
      required this.bike,
      this.isAdmin = false});
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

/// Clube na Administração UauGo.
class AdminClub {
  final String id, name, uf, status;
  final int admins, members;
  const AdminClub(this.id, this.name, this.uf, this.status, this.admins, this.members);
}

/// Tipo de aviso para membros próximos: pedido de ajuda ou "estou
/// passando pela sua cidade".
enum ClubPurpose { help, passing }

/// Clubes no Firestore e as Cloud Functions de membros próximos.
class ClubService {
  ClubService._();
  static final instance = ClubService._();

  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Documento do clube no Firestore.
  DocumentReference<Map<String, dynamic>> _club(String id) =>
      _db.collection('clubs').doc(id);

  /// Chama uma função do servidor e devolve o resultado como Map.
  Future<Map<String, dynamic>> _call(
      String name, Map<String, dynamic> data) async {
    final res = await _fn.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Usa o código de ativação da HelpAITech: a pessoa vira ADMINISTRADORA do
  /// clube do código (já cadastrado) ou cria um clube novo com [name] (só
  /// quando o código não é de um clube cadastrado). [city] só se o usuário
  /// autorizou "ser encontrado". Devolve o clube.
  Future<Club> activate({
    required String activationCode,
    required String name,
    required String memberName,
    required String city,
    required String bike,
  }) async {
    final r = await _call('createClub', {
      'activationCode': activationCode,
      if (name.isNotEmpty) 'name': name,
      'memberName': memberName,
      'city': city,
      'bike': bike,
    });
    return await find(r['clubId'] as String) ??
        Club(id: r['clubId'] as String, name: r['name'] as String, admins: [
          FirebaseAuth.instance.currentUser?.uid ?? '',
        ]);
  }

  // ---- Administração UauGo (platformAdmins/{uid}; functions/clubs.js)

  /// É administrador da plataforma? (cada um só confere o próprio)
  Future<bool> isPlatformAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    try {
      return (await _db.doc('platformAdmins/$uid').get()).exists;
    } catch (_) {
      return false;
    }
  }

  Future<List<AdminClub>> adminListClubs() async {
    final r = await _call('adminListClubs', {});
    return [
      for (final c in (r['clubs'] as List? ?? const []).whereType<Map>())
        AdminClub(
          c['id'] as String,
          (c['name'] ?? '') as String,
          (c['uf'] ?? '') as String,
          (c['status'] ?? 'active') as String,
          (c['admins'] as num?)?.toInt() ?? 0,
          (c['members'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<({String clubId, String name})> adminCreateClub(String name, String uf) async {
    final r = await _call('adminCreateClub', {'name': name, 'uf': uf});
    return (clubId: r['clubId'] as String, name: r['name'] as String);
  }

  /// Código de administrador do clube (12 caracteres).
  Future<({String code, String clubName})> adminActivationCode(String clubId) async {
    final r = await _call('adminActivationCode', {'clubId': clubId, 'note': 'gerado no app'});
    return (code: r['code'] as String, clubName: (r['clubName'] ?? '') as String);
  }

  /// Convite de membro (8 caracteres), para qualquer clube.
  Future<({String code, String clubName})> adminMemberInvite(String clubId) async {
    final r = await _call('adminMemberInvite', {'clubId': clubId});
    return (code: r['code'] as String, clubName: (r['clubName'] ?? '') as String);
  }

  /// Um administrador gera um CONVITE de uso único (vale 7 dias e uma
  /// entrada).
  Future<ClubInvite> createInvite(String clubId) async {
    final r = await _call('createClubInvite', {'clubId': clubId});
    return ClubInvite(r['code'] as String,
        DateTime.fromMillisecondsSinceEpoch((r['expiresAt'] as num).toInt()));
  }

  /// Entra no clube com o convite recebido de um administrador.
  Future<Club> joinWithInvite({
    required String inviteCode,
    required String memberName,
    required String city,
    required String bike,
  }) async {
    final r = await _call('joinClub', {
      'inviteCode': inviteCode,
      'memberName': memberName,
      'city': city,
      'bike': bike,
    });
    return Club(id: r['clubId'] as String, name: r['name'] as String);
  }

  /// Dados do clube (só membros conseguem ler). null se não existir mais
  /// ou se a pessoa foi removida.
  Future<Club?> find(String id) async {
    try {
      final d = await _club(id).get();
      if (!d.exists) return null;
      final data = d.data()!;
      // Formato antigo (um presidente) vale como um administrador.
      final admins = data['admins'] is List
          ? List<String>.from(data['admins'] as List)
          : [
              if ((data['presidentId'] ?? data['createdBy']) is String)
                (data['presidentId'] ?? data['createdBy']) as String,
            ];
      return Club(id: d.id, name: data['name'] ?? d.id, admins: admins);
    } catch (_) {
      return null;
    }
  }

  /// Um administrador promove um membro ([admin] true) ou tira a função
  /// (false). O servidor não deixa o clube ficar sem administrador.
  Future<void> setAdmin(String clubId, String uid, bool admin) =>
      _call('setClubAdmin', {'clubId': clubId, 'uid': uid, 'admin': admin});

  /// Um administrador remove um membro (que não seja administrador).
  Future<void> removeMember(String clubId, String uid) =>
      _club(clubId).collection('members').doc(uid).delete();

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
                isAdmin: d.data()['role'] == 'admin' ||
                    d.data()['role'] == 'president',
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
