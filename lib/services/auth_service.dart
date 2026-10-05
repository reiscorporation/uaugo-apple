// ============================================================================
// auth_service.dart — Login
//
// O que faz: Login anônimo no Firebase (o usuário não precisa criar conta).
// Quem usa: Todas as telas que usam o Firebase.
// ============================================================================

import 'package:firebase_auth/firebase_auth.dart';

/// Login anônimo: o Firebase cria um usuário sem e-mail nem senha. O uid
/// identifica o piloto nas expedições e nos alertas.
class AuthService {
  /// Login anônimo: cada aparelho recebe um ID único sem precisar de cadastro.
  static Future<String> ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
    return user.uid;
  }
}
