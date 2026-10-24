// ============================================================================
// notification_service.dart — Notificações
//
// O que faz: Push do Firebase (SOS, paradas do grupo) e notificações locais;
//   inscreve o celular nos tópicos da expedição.
// Quem usa: main.dart, MapScreen, UserService.
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/i18n.dart';

/// - Expedições: cada uma é um "tópico" (push de SOS e novas paradas).
/// - Clube: push direto para o aparelho do membro (token salvo em
///   users/{uid}), enviado pela Cloud Function `clubNotify`.
class NotificationService {
  static final _fm = FirebaseMessaging.instance;
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Prepara o push e as notificações locais (chamado em main.dart).
  static Future<void> init() async {
    try {
      await _fm.requestPermission(alert: true, sound: true, badge: true);
      await _fm.setForegroundNotificationPresentationOptions(
          alert: true, sound: true, badge: true);
      FirebaseMessaging.onMessage.listen(_show);
      FirebaseMessaging.onMessageOpenedApp.listen(_show);
    } catch (e) {
      debugPrint('Notificações indisponíveis: $e');
    }
  }

  /// Chamado após o runApp: trata o push que abriu o app fechado.
  static void handleInitialMessage() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final m = await _fm.getInitialMessage();
        if (m != null) _show(m);
      } catch (_) {}
    });
  }

  /// Guarda o token de push do celular em users/{uid} (para o clube).
  static Future<void> saveToken(String uid) async {
    final doc = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final token = await _fm.getToken();
      if (token != null) {
        await doc.set({'fcmToken': token}, SetOptions(merge: true));
      }
      _fm.onTokenRefresh.listen(
          (t) => doc.set({'fcmToken': t}, SetOptions(merge: true)));
    } catch (e) {
      debugPrint('Falha ao salvar token: $e');
    }
  }

  /// Recebe os push da expedição (tópico exp_CÓDIGO): SOS e paradas.
  static Future<void> subscribe(String code) async {
    try {
      await _fm.subscribeToTopic('exp_$code');
    } catch (e) {
      debugPrint('Falha ao assinar tópico: $e');
    }
  }

  /// Para de receber os push da expedição.
  static Future<void> unsubscribe(String code) async {
    try {
      await _fm.unsubscribeFromTopic('exp_$code');
    } catch (e) {
      debugPrint('Falha ao cancelar tópico: $e');
    }
  }

  /// Mostra pedidos do clube com atalhos: ir até lá, WhatsApp, ligar.
  static void _show(RemoteMessage m) {
    final d = m.data;
    final type = (d['type'] ?? '') as String;
    if (!type.startsWith('club_')) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final lat = double.tryParse('${d['lat'] ?? ''}');
    final lng = double.tryParse('${d['lng'] ?? ''}');
    final phone = '${d['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9+]'), '');
    final isHelp = type == 'club_help';

    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        icon: Icon(isHelp ? Icons.sos : Icons.two_wheeler,
            color: isHelp ? Colors.red : Colors.teal, size: 40),
        title: Text(m.notification?.title ??
            (isHelp ? tr('Pedido de ajuda do clube') : tr('Membro de passagem'))),
        content: Text(m.notification?.body ?? ''),
        actions: [
          if (phone.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(
                  Uri.parse('https://wa.me/${phone.replaceAll('+', '')}'),
                  mode: LaunchMode.externalApplication),
              child: const Text('WhatsApp'),
            ),
          if (phone.isNotEmpty)
            TextButton(
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              child: Text(tr('Ligar')),
            ),
          if (lat != null && lng != null)
            FilledButton(
              onPressed: () => launchUrl(
                  Uri.parse(
                      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
                  mode: LaunchMode.externalApplication),
              child: Text(tr('Ir até lá')),
            ),
          TextButton(
              onPressed: () => Navigator.pop(c), child: Text(tr('Fechar'))),
        ],
      ),
    );
  }
}
