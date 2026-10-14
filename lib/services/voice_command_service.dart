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
//   - Por enquanto só no Android (no iPhone a opção não aparece).
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

  /// Disponível neste aparelho? (por enquanto, só Android)
  static bool get supported => !kIsWeb && Platform.isAndroid;

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
    if (enabled.value && await _modelReady()) status.value = VoiceCmdStatus.ready;
  }

  Future<String> _modelDir() async =>
      '${(await getApplicationSupportDirectory()).path}/voz';

  Future<bool> _modelReady() async =>
      File('${await _modelDir()}/$_modelName/final.mdl').exists();

  /// Liga a função: pede o microfone e baixa o modelo (se ainda não tiver).
  /// Devolve uma mensagem de erro, ou null se deu certo.
  Future<String?> enable() async {
    if (!supported) return 'Disponível por enquanto só no Android.';
    final mic = await _method.invokeMethod<bool>('requestMic') ?? false;
    if (!mic) return 'Sem permissão do microfone, os comandos de voz não funcionam.';
    if (!await _modelReady()) {
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
        return 'Não foi possível baixar o reconhecimento de voz. '
            'Confira a internet e tente de novo.';
      }
    }
    status.value = VoiceCmdStatus.ready;
    enabled.value = true;
    (await SharedPreferences.getInstance()).setBool(_kEnabled, true);
    return null;
  }

  /// Desliga (o modelo baixado fica guardado para religar sem baixar de novo).
  Future<void> disable() async {
    await stop();
    enabled.value = false;
    status.value = VoiceCmdStatus.off;
    (await SharedPreferences.getInstance()).setBool(_kEnabled, false);
  }

  /// Liga/desliga a pesquisa de trajeto por voz.
  Future<void> setRouteByVoice(bool v) async {
    routeByVoice.value = v;
    (await SharedPreferences.getInstance()).setBool(_kRoute, v);
  }

  /// O que a faixa do mapa diz enquanto ouve a frase livre.
  final destPrompt = ValueNotifier<String>('Ouvindo destino… fale agora');

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
    try {
      return await _method.invokeMethod<String>('listenDestination', {
        'language': 'pt-BR',
      });
    } catch (e) {
      debugPrint('Frase livre por voz: $e');
      return null;
    } finally {
      destListening.value = false;
      if (wasListening) await start();
    }
  }

  /// Ouve o destino (frase livre) logo após um bipe, dentro do app. O Vosk
  /// solta o microfone durante a escuta e volta depois. Devolve o texto
  /// falado, ou null se nada foi entendido.
  Future<String?> recognizeDestination() async {
    destPrompt.value = 'Ouvindo destino… fale agora';
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
    try {
      final text = await _method.invokeMethod<String>('listenDestination', {
        'language': 'pt-BR',
      });
      return text == null ? null : cleanDestination(text);
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
    if (!await _modelReady()) return;
    if (!(await _method.invokeMethod<bool>('hasMic') ?? false)) return;
    _results ??= _events.receiveBroadcastStream().listen(_onResult,
        onError: (e) => debugPrint('Comandos de voz: $e'));
    try {
      await _method.invokeMethod('start', {
        'modelDir': '${await _modelDir()}/$_modelName',
        'grammar': voiceGrammar(),
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
