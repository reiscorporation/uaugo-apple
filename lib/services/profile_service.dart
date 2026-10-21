// ============================================================================
// profile_service.dart — Perfil do veículo
//
// O que faz: Guarda o veículo no celular e envia a foto para o Storage.
// Quem usa: ProfileScreen, MapScreen, prévia da rota.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bike.dart';

/// Guarda a moto do piloto no aparelho e envia a foto para o Firebase Storage.
class ProfileService {
  static const _key = 'bikeProfile';

  /// Veículo salvo no celular (vazio se nunca foi salvo).
  static Future<BikeProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const BikeProfile();
    try {
      return BikeProfile.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const BikeProfile();
    }
  }

  /// Salva o veículo no celular.
  static Future<void> save(BikeProfile p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(p.toMap()));
  }

  /// Placa do veículo (só no celular, NUNCA vai para o grupo nem para o
  /// servidor): usada no aviso de rodízio.
  static Future<String> loadPlate() async =>
      (await SharedPreferences.getInstance()).getString('vehiclePlate') ?? '';

  static Future<void> savePlate(String plate) async {
    final prefs = await SharedPreferences.getInstance();
    final p = plate.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (p.isEmpty) {
      await prefs.remove('vehiclePlate');
    } else {
      await prefs.setString('vehiclePlate', p);
    }
  }

  /// Cada envio gera um arquivo novo, assim todos veem a foto atualizada.
  /// A foto anterior é apagada para não acumular arquivos.
  static Future<String> uploadPhoto(String uid, File file,
      {String? oldUrl}) async {
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref('bikes/$uid/$name');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    await deletePhoto(oldUrl);
    return url;
  }

  /// Apaga uma foto antiga do Storage (ignora erro se já não existir).
  static Future<void> deletePhoto(String? url) async {
    if (url == null) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {}
  }
}
