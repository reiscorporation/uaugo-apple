// ============================================================================
// voice_command_service.dart — Comandos de voz (acessibilidade, OPCIONAL)
//
// O que faz: Mãos livres para quem está de luva: "UauGo, radar",
//   "UauGo, polícia"... marcam o alerta; "sim"/"não" respondem à pergunta
//   "ainda está lá?". O reconhecimento é OFFLINE, no próprio celular (Vosk,
//   android/.../VoiceCommands.kt): o áudio não sai do aparelho.
//   - Desligado por padrão: o piloto liga em Configurações → Acessibilidade.
//   - Ao ligar, baixa o modelo de português (~31 MB) do Storage do app
//     (public/voz/) uma única vez.
//   - Ouve só com o mapa aberto, e pausa enquanto o app está falando.
//   - iPhone (26/11): o reconhecimento da Apple no próprio aparelho (sem
//     modelo para baixar; o áudio também não sai do celular). iPhone sem
//     reconhecimento no aparelho: a opção avisa que não dá.
//   - "UauGo, ir para" (opção à parte, desligada): logo depois de um bipe,
//     o destino é ouvido pelo reconhecimento do próprio Android, dentro do
//     app — no aparelho quando ele oferece (sem internet, o áudio não sai
//     do celular), senão o do Google (internet; o áudio dessa frase vai para
//     o Google).
// Quem usa: MapScreen (comandos), SettingsScreen (ligar/desligar).
// Onde mexer: Frases aceitas: lib/logic/voice_commands.dart.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/voice_commands.dart';
import 'voice_service.dart';
import '../l10n/i18n.dart';

/// Situação da função, para a tela de configurações.
enum VoiceCmdStatus { off, downloading, ready, error }

/// Comandos de voz offline (Vosk) — veja o cabeçalho do arquivo.
class VoiceCommandService {
  VoiceCommandService._();
  static final instance = VoiceCommandService._();

  static const _method = MethodChannel('rodajunto/voice');
  static const _events = EventChannel('rodajunto/voice/results');
  static const _modelName = 'vosk-model-small-pt-0.3';
  static const _modelPath = 'public/voz/$_modelName.zip';
  static const _kEnabled = 'voiceCommands';
  static const _kRoute = 'voiceRoute';
  static const _kHelmet = 'voiceHelmet';

  /// Ouvir pelo microfone do comunicador do capacete (Bluetooth), aberto o
  /// tempo todo. A música do comunicador fica com qualidade de ligação.
  final helmetMic = ValueNotifier<bool>(false);

  /// Disponível neste aparelho? Android (Vosk) e iPhone (Apple, 26/11).
  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// iPhone: não usa o modelo do Vosk (nada para baixar).
  static bool get _needsModel => !kIsWeb && Platform.isAndroid;

  /// Ouvir uma frase (alerta falado, destino): Android e iPhone (24/11).
  static bool get canListen => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Ligado pelo piloto (fica salvo no celular).
  final enabled = ValueNotifier<bool>(false);

  /// "Pesquisa de trajeto por voz" (opcional).
  final routeByVoice = ValueNotifier<bool>(false);

  /// Ouvindo o destino agora (o mapa mostra "Ouvindo destino…").
  final destListening = ValueNotifier<bool>(false);

  /// O que já foi entendido do destino (texto parcial, enquanto fala).
  final destHeard = ValueNotifier<String>('');
  final status = ValueNotifier<VoiceCmdStatus>(VoiceCmdStatus.off);

  /// Progresso do download do modelo (0 a 1).
  final progress = ValueNotifier<double>(0);

  final _commands = StreamController<VoiceCommand>.broadcast();

  /// Comandos reconhecidos (o MapScreen escuta).
  Stream<VoiceCommand> get commands => _commands.stream;

  StreamSubscription? _results;
  bool _listening = false;

  /// "UauGo" sozinho: os próximos segundos valem como o resto do comando.
  VoiceContext? _wakeCtx;
  DateTime _wakeUntil = DateTime(2000);
  static const _wakeWindow = Duration(seconds: 6);
  DateTime _quietUntil = DateTime(2000);

  /// Lê se o piloto ligou a função.
  Future<void> load() async {
    if (!supported) return;
    final p = await SharedPreferences.getInstance();
    enabled.value = p.getBool(_kEnabled) ?? false;
    routeByVoice.value = p.getBool(_kRoute) ?? false;
    helmetMic.value = p.getBool(_kHelmet) ?? false;
    if (enabled.value && (!_needsModel || await _modelReady())) {
      status.value = VoiceCmdStatus.ready;
    }
  }

  Future<String> _modelDir() async =>
      '${(await getApplicationSupportDirectory()).path}/voz';

  Future<bool> _modelReady() async =>
      File('${await _modelDir()}/$_modelName/final.mdl').exists();

  /// Liga a função: pede o microfone e baixa o modelo (se ainda não tiver).
  /// Devolve uma mensagem de erro, ou null se deu certo.
  Future<String?> enable() async {
    if (!supported) return tr('Ainda não disponível neste sistema.');
    final mic = await _method.invokeMethod<bool>('requestMic') ?? false;
    if (!mic) return tr('Sem permissão do microfone, os comandos de voz não funcionam.');
    if (!_needsModel) {
      // iPhone: precisa do reconhecimento no próprio aparelho.
      final ok = await _method.invokeMethod<bool>('canListenAlways') ?? false;
      if (!ok) return tr('Este iPhone não reconhece a fala sem internet, então os comandos de voz não funcionam nele.');
    } else if (!await _modelReady()) {
      status.value = VoiceCmdStatus.downloading;
      progress.value = 0;
      try {
        final dir = await _modelDir();
        final zip = File('${(await getTemporaryDirectory()).path}/$_modelName.zip');
        final task = FirebaseStorage.instance.ref(_modelPath).writeToFile(zip);
        task.snapshotEvents.listen((s) {
          if (s.totalBytes > 0) progress.value = s.bytesTransferred / s.totalBytes;
        });
        await task;
        await _method.invokeMethod('unzip', {'zip': zip.path, 'dir': dir});
        await zip.delete();
      } catch (e) {
        status.value = VoiceCmdStatus.error;
        return tr('Não foi possível baixar o reconhecimento de voz. Confira a internet e tente de novo.');
      }
    }
    status.value = VoiceCmdStatus.ready;
    enabled.value = true;
    (await SharedPreferences.getInstance()).setBool(_kEnabled, true);
    // Ligou com o mapa aberto por baixo (Configurações abertas pelo mapa):
    // já começa a ouvir, sem precisar fechar e abrir o mapa (26/11).
    if (mapOpen) await start();
    return null;
  }

  /// O mapa está aberto (ele liga ao abrir e desliga ao fechar).
  bool mapOpen = false;

  /// Desliga (o modelo baixado fica guardado para religar sem baixar de novo).
  Future<void> disable() async {
    await stop();
    enabled.value = false;
    status.value = VoiceCmdStatus.off;
    (await SharedPreferences.getInstance()).setBool(_kEnabled, false);
  }

  /// Liga/desliga a pesquisa de trajeto por voz.
  /// Liga/desliga o microfone do comunicador e recomeça a ouvir.
  Future<void> setHelmetMic(bool v) async {
    helmetMic.value = v;
    (await SharedPreferences.getInstance()).setBool(_kHelmet, v);
    if (_listening) {
      await stop();
      await start();
    }
  }

  Future<void> setRouteByVoice(bool v) async {
    routeByVoice.value = v;
    (await SharedPreferences.getInstance()).setBool(_kRoute, v);
  }

  /// O que a faixa do mapa diz enquanto ouve a frase livre.
  final destPrompt = ValueNotifier<String>(tr('Ouvindo destino… fale agora'));

  /// A última escuta falhou por falta de permissão (iPhone: microfone ou
  /// Reconhecimento de Fala negados em Ajustes).
  bool lastDenied = false;

  /// Mensagem para quando [lastDenied].
  static String get deniedMessage => Platform.isIOS
      ? tr('Permita o Microfone e o Reconhecimento de Fala para o UauGo em Ajustes do iPhone.')
      : tr('Permita o microfone para o UauGo nas configurações do celular.');

  /// Ouve uma frase livre (destino ou "o que você procura?") logo após um
  /// bipe, dentro do app. O Vosk solta o microfone durante a escuta e volta
  /// depois. Devolve o texto falado, ou null se nada foi entendido.
  Future<String?> listenFree(String prompt) async {
    destPrompt.value = prompt;
    final wasListening = _listening;
    await stop();
    _method.setMethodCallHandler((call) async {
      if (call.method == 'destPartial') destHeard.value = call.arguments as String;
    });
    destHeard.value = '';
    destListening.value = true;
    lastDenied = false;
    try {
      return await _method.invokeMethod<String>('listenDestination', {
        'language': I18n.ttsLang,
        'helmet': helmetMic.value,
      });
    } on PlatformException catch (e) {
      debugPrint('Frase livre por voz: $e');
      lastDenied = e.code == 'no-permission';
      return null;
    } catch (e) {
      debugPrint('Frase livre por voz: $e');
      return null;
    } finally {
      destListening.value = false;
      if (wasListening) await start();
    }
  }

  /// Tela de alertas (23/11): ouve o alerta falado ("tem óleo na pista") assim
  /// que a tela abre, sem botão. Pede o microfone se ainda não tiver; com o
  /// comunicador ligado, ouve por ele. Os comandos "UauGo" pausam enquanto
  /// isso (um microfone por vez) e voltam depois. null = não ouviu nada,
  /// sem permissão ou aparelho sem reconhecimento (ex.: iPhone, por ora).
  Future<String?> listenAlert(String prompt) async {
    if (!canListen) return null;
    try {
      final mic = await _method.invokeMethod<bool>('requestMic') ?? false;
      if (!mic) return null;
    } catch (_) {
      return null;
    }
    return listenFree(prompt);
  }

  /// Ouve o destino (frase livre) logo após um bipe, dentro do app. O Vosk
  /// solta o microfone durante a escuta e volta depois. Devolve o texto
  /// falado, ou null se nada foi entendido.
  Future<String?> recognizeDestination() async {
    destPrompt.value = tr('Ouvindo destino… fale agora');
    final wasListening = _listening;
    await stop();
    _method.setMethodCallHandler((call) async {
      if (call.method == 'destPartial') destHeard.value = call.arguments as String;
      if (call.method == 'destListening') {
        debugPrint('Destino por voz: ouvindo (${call.arguments})');
      }
    });
    destHeard.value = '';
    destListening.value = true;
    lastDenied = false;
    try {
      final text = await _method.invokeMethod<String>('listenDestination', {
        'language': I18n.ttsLang,
        'helmet': helmetMic.value,
      });
      return text == null ? null : cleanDestination(text);
    } on PlatformException catch (e) {
      debugPrint('Pesquisa por voz: $e');
      lastDenied = e.code == 'no-permission';
      return null;
    } catch (e) {
      debugPrint('Pesquisa por voz: $e');
      return null;
    } finally {
      destListening.value = false;
      if (wasListening) await start();
    }
  }

  /// Cancela a escuta do destino (ex.: o piloto saiu do mapa).
  Future<void> cancelDestination() async {
    try {
      await _method.invokeMethod('cancelDestination');
    } catch (_) {}
  }

  /// Começa a ouvir (chamado pelo MapScreen ao abrir / voltar ao app).
  Future<void> start() async {
    debugPrint('Comandos de voz: start (ligado=${enabled.value}, ouvindo=$_listening)');
    if (!supported || !enabled.value || _listening) return;
    if (_needsModel && !await _modelReady()) return;
    if (!(await _method.invokeMethod<bool>('hasMic') ?? false)) return;
    _results ??= _events.receiveBroadcastStream().listen(_onResult,
        onError: (e) => debugPrint('Comandos de voz: $e'));
    try {
      await _method.invokeMethod('start', {
        'modelDir': '${await _modelDir()}/$_modelName',
        'grammar': voiceGrammar(),
        'helmet': helmetMic.value,
      });
      _listening = true;
      VoiceService.instance.speaking.addListener(_onSpeaking);
    } catch (e) {
      debugPrint('Comandos de voz não iniciaram: $e');
    }
  }

  /// Para de ouvir (mapa fechado, app minimizado ou função desligada).
  Future<void> stop() async {
    debugPrint('Comandos de voz: stop (ouvindo=$_listening)');
    if (!_listening) return;
    _listening = false;
    VoiceService.instance.speaking.removeListener(_onSpeaking);
    try {
      await _method.invokeMethod('stop');
    } catch (_) {}
  }

  /// Enquanto o app fala, o microfone pausa (para não ouvir a si mesmo); depois
  /// ainda ignora 0,7 s, o "rabo" da própria fala.
  void _onSpeaking() {
    final talking = VoiceService.instance.speaking.value;
    if (!talking) {
      _quietUntil = DateTime.now().add(const Duration(milliseconds: 700));
    }
    _method.invokeMethod('pause', {'paused': talking}).catchError((_) => null);
  }

  void _onResult(dynamic json) {
    if (json is! String) return;
    if (VoiceService.instance.speaking.value ||
        DateTime.now().isBefore(_quietUntil)) {
      return;
    }
    final ctx = DateTime.now().isBefore(_wakeUntil) ? _wakeCtx : null;
    final cmd = parseVoiceResult(json, context: ctx);
    if (kDebugMode) debugPrint('Voz ouviu: $json -> ${cmd?.runtimeType}');
    if (cmd is WakeCommand) {
      // Bipe: "pode falar o comando".
      _wakeCtx = cmd.find ? VoiceContext.find : VoiceContext.wake;
      _wakeUntil = DateTime.now().add(_wakeWindow);
      _method.invokeMethod('beep').catchError((_) => null);
      return;
    }
    if (cmd != null) {
      _wakeUntil = DateTime(2000);
      _commands.add(cmd);
    }
  }
}
