// ============================================================================
// user_service.dart — Dados do usuário (LGPD)
//
// O que faz: Autorizações, cidade base, telefone (só no celular), clube e
//   a exclusão completa dos dados.
// Quem usa: ConsentScreen, ClubScreen, MapScreen.
// ============================================================================

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/privacy.dart';
import 'auth_service.dart';
import 'notification_service.dart';

/// Autorizações, cidade base, telefone e clube do usuário.
///
/// No Firestore, `users/{uid}` é PRIVADO (só o dono lê/escreve). As Cloud
/// Functions leem esse documento para achar membros próximos sem nunca
/// revelar coordenadas a outros usuários. O telefone fica só no aparelho.
class UserService {
  static const _kConsents = 'consents';
  static const _kBase = 'baseLocation';
  static const _kPhone = 'phone';
  static const _kClubId = 'clubId';
  static const _kClubName = 'clubName';
  static const _kHistory = 'expeditionHistory';

  /// Guarda os códigos das expedições usadas (para a exclusão de dados).
  static Future<void> addExpeditionHistory(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kHistory) ?? [];
    list.remove(code);
    list.insert(0, code);
    await prefs.setStringList(_kHistory, list.take(50).toList());
  }

  /// Exclui todos os dados do usuário no servidor e no aparelho
  /// (direito de eliminação, art. 18 da LGPD).
  static Future<void> deleteAllMyData() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_kHistory) ?? [];
    final clubId = prefs.getString(_kClubId);

    await FirebaseFunctions.instanceFor(region: 'southamerica-east1')
        .httpsCallable('deleteMyData')
        .call({'expeditions': history, if (clubId != null) 'clubId': clubId});

    for (final code in history) {
      try {
        await FirebaseMessaging.instance.unsubscribeFromTopic('exp_$code');
      } catch (_) {}
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
  }

  /// Autorizações salvas no celular (null = ainda não aceitou nada).
  static Future<Consents?> loadConsents() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kConsents);
    if (raw == null) return null;
    try {
      return Consents.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Cidade base (só se autorizou "ser encontrado").
  static Future<BaseLocation?> loadBase() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kBase);
    if (raw == null) return null;
    try {
      return BaseLocation.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Telefone (fica só no celular; vai junto apenas num pedido de ajuda).
  static Future<String> loadPhone() async =>
      (await SharedPreferences.getInstance()).getString(_kPhone) ?? '';

  /// Código do clube do piloto (null = sem clube).
  static Future<String?> loadClubId() async =>
      (await SharedPreferences.getInstance()).getString(_kClubId);

  /// Nome do clube do piloto.
  static Future<String?> loadClubName() async =>
      (await SharedPreferences.getInstance()).getString(_kClubName);

  /// Entra (id e nome) ou sai (null) do clube.
  static Future<void> setClub(String? id, String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_kClubId);
      await prefs.remove(_kClubName);
    } else {
      await prefs.setString(_kClubId, id);
      await prefs.setString(_kClubName, name ?? id);
    }
  }

  /// Salva as autorizações no celular e em users/{uid} (o servidor precisa
  /// delas para o clube). Revogar "ser encontrado" apaga a cidade base.
  static Future<void> saveConsents(
    Consents c, {
    BaseLocation? base,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kConsents, jsonEncode(c.toMap()));
    await prefs.setString(_kPhone, phone);
    if (c.findable && base != null) {
      await prefs.setString(_kBase, jsonEncode(base.toMap()));
    } else {
      await prefs.remove(_kBase);
    }

    final uid = await AuthService.ensureSignedIn();
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'consent': {...c.toMap(), 'acceptedAt': FieldValue.serverTimestamp()},
      // Revogou "ser encontrado"? A cidade base é apagada do servidor.
      'base': (c.findable && base != null) ? base.toMap() : FieldValue.delete(),
    }, SetOptions(merge: true));
    await NotificationService.saveToken(uid);
  }

  /// Usa o GPS para definir a cidade base, arredondando para ~1 km.
  static Future<BaseLocation> detectBase() async {
    final p = await Geolocator.getCurrentPosition();
    double round(double v) => (v * 100).round() / 100;
    var city = '';
    try {
      final places = await placemarkFromCoordinates(p.latitude, p.longitude);
      if (places.isNotEmpty) {
        final m = places.first;
        final name = (m.locality ?? '').isNotEmpty
            ? m.locality!
            : (m.subAdministrativeArea ?? '');
        city = [name, m.administrativeArea ?? '']
            .where((s) => s.isNotEmpty)
            .join(' - ');
      }
    } catch (_) {}
    return BaseLocation(
      lat: round(p.latitude),
      lng: round(p.longitude),
      city: city.isEmpty ? 'Cidade não identificada' : city,
    );
  }
}
