// ============================================================================
// auth_service.dart — Conta do usuário (login)
//
// O que faz: Todo aparelho começa com uma conta ANÔNIMA (sem cadastro). Quando
//   a pessoa entra com Google, Apple ou e-mail e senha, a conta anônima é
//   VINCULADA à nova (mesmo uid): expedições, alertas e clube continuam.
//   Se a conta já existia (ex.: outro celular), entra nela e regrava os
//   aceites (termos/autorizações) para o uid dessa conta.
// Quem usa: LoginScreen, Configurações (Minha conta), telas que exigem conta
//   (criar/entrar em expedição, reportar alertas, clube).
// Onde mexer: Provedores ativos no Firebase (Authentication → Sign-in method):
//   anônimo, e-mail/senha, Google e (no iPhone) Apple.
// ============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Conta do usuário no Firebase Authentication.
class AuthService {
  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Chamado depois de trocar de conta (entrar numa conta que já existia),
  /// para regravar os aceites no uid novo. Registrado em main.dart.
  static Future<void> Function()? onAccountChanged;

  /// Chamado quando a conta anônima é vinculada (mesmo uid): só acrescenta a
  /// conta (e-mail) ao registro do aceite, sem mudar a data original.
  static Future<void> Function()? onLinked;

  /// Garante um usuário (anônimo, se ainda não houver). Devolve o uid.
  static Future<String> ensureSignedIn() async {
    final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user!;
    return user.uid;
  }

  static User? get user => _auth.currentUser;

  /// true = ainda não entrou com Google/Apple/e-mail.
  static bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  /// Nome (ou e-mail) e e-mail para mostrar em "Minha conta".
  static String get displayName {
    final u = _auth.currentUser;
    final n = u?.displayName ?? '';
    return n.isNotEmpty ? n : (u?.email ?? '');
  }

  static String get email => _auth.currentUser?.email ?? '';

  /// Muda quando a pessoa entra, sai ou confirma o e-mail.
  static Stream<User?> get changes => _auth.userChanges();

  // ---------------------------------------------------------- provedores

  /// Entrar com Google (abre a escolha de conta do Google).
  static Future<void> signInWithGoogle() =>
      _withProvider(GoogleAuthProvider()..addScope('email'));

  /// Entrar com Apple (só no iPhone; exige a conta Apple Developer).
  static Future<void> signInWithApple() => _withProvider(
      AppleAuthProvider()..addScope('email')..addScope('name'));

  /// Mostrar o botão da Apple? Só no iPhone (a Apple exige o botão quando há
  /// login com Google).
  static bool get appleAvailable => defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> _withProvider(AuthProvider provider) async {
    await ensureSignedIn();
    final current = _auth.currentUser!;
    try {
      if (current.isAnonymous) {
        // Vincula: mantém o mesmo uid e todos os dados.
        await current.linkWithProvider(provider);
        await _refreshToken();
        await onLinked?.call();
      } else {
        await _auth.signInWithProvider(provider);
        await onAccountChanged?.call();
      }
    } on FirebaseAuthException catch (e) {
      // A conta Google/Apple já existe (ex.: usada em outro celular): entra
      // nela. Os dados do anônimo deste aparelho ficam para trás.
      if (e.code == 'credential-already-in-use' && e.credential != null) {
        await _auth.signInWithCredential(e.credential!);
        await onAccountChanged?.call();
      } else {
        rethrow;
      }
    }
  }

  /// Renova o token de acesso logo após vincular a conta: as regras do
  /// Firestore leem dele se a conta ainda é anônima.
  static Future<void> _refreshToken() async {
    try {
      await _auth.currentUser?.getIdToken(true);
    } catch (_) {}
  }

  // ---------------------------------------------------------- e-mail

  /// Cria a conta com e-mail e senha (vinculada ao anônimo, mesmo uid) e
  /// envia o e-mail de confirmação.
  static Future<void> registerWithEmail(
      String name, String email, String password) async {
    await ensureSignedIn();
    final cred =
        EmailAuthProvider.credential(email: email.trim(), password: password);
    final current = _auth.currentUser!;
    final wasAnonymous = current.isAnonymous;
    final u = wasAnonymous
        ? (await current.linkWithCredential(cred)).user!
        : (await _auth.createUserWithEmailAndPassword(
                email: email.trim(), password: password))
            .user!;
    if (name.trim().isNotEmpty) await u.updateDisplayName(name.trim());
    await u.sendEmailVerification();
    await _refreshToken();
    if (wasAnonymous) {
      await onLinked?.call();
    } else {
      await onAccountChanged?.call();
    }
  }

  /// Entra numa conta de e-mail que já existe.
  static Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    await onAccountChanged?.call();
  }

  /// "Esqueci a senha": o Firebase envia o link para criar uma nova.
  static Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// Reenvia o e-mail de confirmação.
  static Future<void> resendVerification() async =>
      _auth.currentUser?.sendEmailVerification();

  /// Confere de novo no servidor se o e-mail já foi confirmado.
  static Future<void> reload() async => _auth.currentUser?.reload();

  /// Conta de e-mail ainda sem confirmação.
  static bool get needsVerification {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous || u.emailVerified) return false;
    return u.providerData.any((p) => p.providerId == 'password');
  }

  /// Sai da conta. O aparelho volta a ter uma conta anônima (o app continua
  /// funcionando para navegar sozinho).
  static Future<void> signOut() async {
    await _auth.signOut();
    await _auth.signInAnonymously();
    await onAccountChanged?.call();
  }

  /// Mensagem em português para os erros mais comuns do login.
  static String friendlyError(Object e) {
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'invalid-email' => 'E-mail inválido.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'E-mail ou senha incorretos.',
        'email-already-in-use' ||
        'credential-already-in-use' =>
          'Já existe uma conta com este e-mail. Use "Já tenho conta".',
        'weak-password' => 'Senha fraca: use pelo menos 8 caracteres.',
        'too-many-requests' =>
          'Muitas tentativas. Aguarde alguns minutos e tente de novo.',
        'network-request-failed' => 'Sem internet. Confira a conexão.',
        'operation-not-allowed' =>
          'Esta forma de login ainda não foi ativada no servidor.',
        'web-context-canceled' || 'canceled' => 'Login cancelado.',
        _ => 'Não foi possível entrar (${e.code}).',
      };
    }
    return 'Não foi possível entrar: $e';
  }
}
