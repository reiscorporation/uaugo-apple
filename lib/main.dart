// ============================================================================
// main.dart — Ponto de entrada do app
//
// O que faz: Inicializa o Firebase, o App Check, as configurações
//   (AppSettings) e as notificações, e define o tema visual (cores, modo
//   escuro).
// Quem usa: Primeira tela: StartupGate (autorizações no 1º uso, depois
//   HomeScreen).
// Onde mexer: Cores do app: appColorScheme (paleta da marca).
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/startup_gate.dart';
import 'screens/terms_screen.dart';
import 'services/voice_command_service.dart';
import 'services/app_settings.dart';
import 'services/auth_service.dart';
import 'services/user_service.dart';
import 'services/notification_service.dart';

/// Paleta da marca: azul-marinho (confiança, segurança, tecnologia) como base,
/// laranja só no que chama ação (iniciar, alertas, a marca) e verde-água para
/// "seguro". Vermelho fica reservado para SOS e perigo. O ícone usa as mesmas
/// cores (scripts/gerar-icone.py).
const appColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFF7A1A), // laranja da marca
  onPrimary: Color(0xFF1A0F05),
  primaryContainer: Color(0xFF1E3350), // azul aço ("Para onde?")
  onPrimaryContainer: Color(0xFFEAF1FA),
  secondary: Color(0xFF2EC4A0), // verde-água "seguro"
  onSecondary: Color(0xFF00261C),
  secondaryContainer: Color(0xFF173B44),
  onSecondaryContainer: Color(0xFFBFF2E3),
  tertiary: Color(0xFFFFB074),
  onTertiary: Color(0xFF3A1A00),
  tertiaryContainer: Color(0xFF4A2A10),
  onTertiaryContainer: Color(0xFFFFDCC2),
  error: Color(0xFFFF5A5F),
  onError: Color(0xFF3A0006),
  errorContainer: Color(0xFF5C1418),
  onErrorContainer: Color(0xFFFFDAD8),
  surface: Color(0xFF0F1B2D), // azul-marinho
  onSurface: Color(0xFFEAF1FA),
  onSurfaceVariant: Color(0xFFA9BBD1),
  surfaceContainerLowest: Color(0xFF0A1422),
  surfaceContainerLow: Color(0xFF12203A),
  surfaceContainer: Color(0xFF16253D),
  surfaceContainerHigh: Color(0xFF1B2D47),
  surfaceContainerHighest: Color(0xFF223756),
  outline: Color(0xFF3A5578),
  outlineVariant: Color(0xFF26405F),
  inverseSurface: Color(0xFFEAF1FA),
  onInverseSurface: Color(0xFF0F1B2D),
  inversePrimary: Color(0xFFB34A00),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// Ligado pelo scripts/testar-local.ps1: usa o Firebase Emulator Suite
/// rodando no computador em vez da nuvem.
const usarEmulador = bool.fromEnvironment('USE_EMULATOR');

/// Inicia o app: Firebase, App Check, configurações, notificações.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Barras do sistema claras sobre o azul-marinho (relógio, bateria e
  // botões de navegação legíveis).
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0F1B2D),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (usarEmulador) {
    await _conectarEmuladores();
  } else {
    // App Check: garante que só o app legítimo acessa o backend.
    // Em modo debug usa o provedor de depuração (veja o README).
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode
            ? AppleProvider.debug
            : AppleProvider.appAttestWithDeviceCheckFallback,
      );
    } catch (e) {
      debugPrint('App Check indisponível: $e');
    }
  }

  await AppSettings.instance.load();
  await VoiceCommandService.instance.load();
  // Trocou de conta (entrou numa conta que já existia ou saiu): regrava o
  // aceite dos Termos e as autorizações no uid novo, como registro.
  AuthService.onLinked = TermsService.attachAccount;
  AuthService.onAccountChanged = () async {
    if (await TermsService.accepted()) {
      await TermsService.accept(
          method: 'aceite já feito neste aparelho, regravado ao entrar na conta');
    }
    final c = await UserService.loadConsents();
    if (c != null) {
      await UserService.saveConsents(c,
          base: await UserService.loadBase(),
          phone: await UserService.loadPhone());
    }
  };
  await NotificationService.init();
  runApp(const ComboioApp());
  NotificationService.handleInitialMessage();
}

/// Em modo de teste local (scripts/testar-local.ps1), usa os emuladores do
/// Firebase no PC em vez do servidor de verdade.
Future<void> _conectarEmuladores() async {
  // No emulador do Android, 10.0.2.2 é o "localhost" do computador.
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instanceFor(region: 'southamerica-east1')
      .useFunctionsEmulator(host, 5001);
  await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  debugPrint('Usando o Firebase Emulator Suite em $host');
}

/// Raiz do app: tema (cores, modo escuro) e a primeira tela.
class ComboioApp extends StatelessWidget {
  const ComboioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UauGo',
      debugShowCheckedModeBanner: false,
      // Calendário, relógio e botões do sistema em português.
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorKey: NotificationService.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: appColorScheme,
        scaffoldBackgroundColor: appColorScheme.surface,
        appBarTheme: const AppBarTheme(systemOverlayStyle: SystemUiOverlayStyle.light),
      ),
      home: const StartupGate(),
    );
  }
}
