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
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
import 'services/shared_place_service.dart';
import 'services/car_service.dart';
import 'services/expedition_service.dart';
import 'services/analytics_service.dart';
import 'l10n/i18n.dart';
import 'services/usage_service.dart';

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

/// Paleta do app. Padrão: as cores originais (azul-marinho e laranja).
/// Clean: tudo claro (fundo branco, letra escura) com a cor dos botões
/// escolhida. As cores de segurança (alertas, SOS, radar) são fixas no mapa.
ColorScheme schemeFor(bool clean, AppAccent a) {
  if (!clean) return appColorScheme;
  final s = ColorScheme.fromSeed(seedColor: a.color, brightness: Brightness.light);
  return s.copyWith(
    primary: a.color,
    onPrimary: Colors.white,
    surface: const Color(0xFFF7F8FA),
    onSurface: const Color(0xFF16202C),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF2F4F7),
    surfaceContainer: const Color(0xFFECEFF3),
    surfaceContainerHigh: const Color(0xFFE6EAEF),
    surfaceContainerHighest: const Color(0xFFDFE4EA),
    error: const Color(0xFFD32F2F),
  );
}

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
  // Estatísticas anônimas e erros (o usuário pode desligar em Configurações).
  await AnalyticsService.setEnabled(AppSettings.instance.shareStats.value);
  AppSettings.instance.shareStats
      .addListener(() => AnalyticsService.setEnabled(AppSettings.instance.shareStats.value));
  if (!usarEmulador) {
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      if (AppSettings.instance.shareStats.value && !kDebugMode) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(d);
      }
    };
    PlatformDispatcher.instance.onError = (e, st) {
      AnalyticsService.error(e, st, reason: 'erro não tratado');
      return true;
    };
  }
  await VoiceCommandService.instance.load();
  // Trocou de conta (entrou numa conta que já existia ou saiu): regrava o
  // aceite dos Termos e as autorizações no uid novo, como registro.
  AuthService.onLinked = TermsService.attachAccount;
  // Trocou de conta: líder/capitão/ferrolho vão junto para a conta nova.
  AuthService.onSwitchedFrom = ExpeditionService.instance.transferRoles;
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
  await SharedPlaceService.instance.init();
  CarService.instance.init(); // modo carro (Android Auto)
  // Tempo de uso por piloto (prêmios no futuro, 16/11).
  UsageService.instance.start();
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

/// Tema do app com a paleta [c] (cor de destaque escolhida).
ThemeData _theme(ColorScheme c) => ThemeData(
      useMaterial3: true,
      colorScheme: c,
      scaffoldBackgroundColor: c.surface,
      // Relógio e bateria legíveis: claros no Padrão, escuros no Clean.
      appBarTheme: AppBarTheme(
          systemOverlayStyle: c.brightness == Brightness.light
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light),
    );

/// Raiz do app: tema (cores, modo escuro) e a primeira tela.
class ComboioApp extends StatelessWidget {
  const ComboioApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Troca de aparência (Configurações) vale na hora.
    final s = AppSettings.instance;
    return ListenableBuilder(
        listenable: Listenable.merge([s.cleanTheme, s.accent, I18n.lang]),
        builder: (_, __) => MaterialApp(
      // Trocar o idioma refaz as telas (volta ao início) já no novo idioma.
      key: ValueKey(I18n.lang.value),
      title: 'UauGo',
      debugShowCheckedModeBanner: false,
      // Calendário, relógio e botões do sistema no idioma do app.
      locale: I18n.isEn ? const Locale('en', 'US') : const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorKey: NotificationService.navigatorKey,
      theme: _theme(schemeFor(s.cleanTheme.value, s.accent.value)),
      home: const StartupGate(),
      // Android Auto conectado: o celular não oferece nada para tocar
      // (exigência da Play, "Visual info on phone", 11/11). Tudo segue
      // rodando por baixo e a navegação continua na tela do carro.
      builder: (ctx, child) => ValueListenableBuilder<bool>(
        valueListenable: CarService.instance.connected,
        builder: (_, car, __) => Stack(children: [
          if (child != null) child,
          if (car) const Positioned.fill(child: _CarLock()),
        ]),
      ),
    ));
  }
}

/// UauGo2 de testes: próximas manobras com a distância de cada uma.
class _CarSteps extends StatelessWidget {
  const _CarSteps();

  static IconData _icon(String m) => switch (m) {
        'turn-slight-left' || 'ramp-left' || 'keep-left' => Icons.turn_slight_left,
        'turn-slight-right' || 'ramp-right' || 'keep-right' => Icons.turn_slight_right,
        'turn-sharp-left' => Icons.turn_sharp_left,
        'turn-sharp-right' => Icons.turn_sharp_right,
        'fork-left' || 'fork-right' => Icons.fork_right,
        'uturn-left' => Icons.u_turn_left,
        'uturn-right' => Icons.u_turn_right,
        'roundabout-left' => Icons.roundabout_left,
        final x when x.startsWith('roundabout') => Icons.roundabout_right,
        'merge' => Icons.merge,
        final x when x.contains('left') => Icons.turn_left,
        final x when x.contains('right') => Icons.turn_right,
        _ => Icons.straight,
      };

  static String _dist(int m) => m >= 1000
      ? '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1).replaceAll('.', ',')} km'
      : '${(m / 10).round() * 10} m';

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<(String, String, int)>>(
        valueListenable: CarService.instance.upcoming,
        builder: (_, list, __) => list.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: ListView(shrinkWrap: true, children: [
                    for (final (i, (m, text, d)) in list.indexed)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: i == 0 ? const Color(0xFFFF7A1A) : Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Icon(_icon(m), color: Colors.white, size: i == 0 ? 34 : 26),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 74,
                            child: Text(_dist(d),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: i == 0 ? 20 : 16,
                                    fontWeight: FontWeight.w900)),
                          ),
                          Expanded(
                            child: Text(text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontSize: i == 0 ? 16 : 14)),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ),
      );
}

/// Tela do celular com o Android Auto conectado: só um aviso, sem botões.
class _CarLock extends StatelessWidget {
  const _CarLock();

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF0F1B2D),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.directions_car, size: 72, color: Color(0xFFFF7A1A)),
                const SizedBox(height: 20),
                Text(tr('UauGo está na tela do carro'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(tr('Por segurança, use a tela do carro enquanto dirige.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16)),
                // Só no UauGo2 de testes (13/11): lista das próximas
                // manobras, as passadas saem. Na Play não (regra do Android
                // Auto "Visual info on phone").
                if (kDebugMode) const _CarSteps(),
              ]),
            ),
          ),
        ),
      );
}
