// ============================================================================
// voice_service.dart — Voz
//
// O que faz: Texto para fala em português: avisos (radar, perigos) e narração
//   das curvas, com fila, música abaixada durante a fala e modo rápido na
//   simulação.
// Quem usa: MapScreen, Configurações.
// Onde mexer: Velocidade da fala: setFastMode.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Voz do app (sintetizador do próprio celular: funciona sem internet).
///
/// - Abaixa a música enquanto fala e usa o canal de navegação, que vai para
///   o intercomunicador Bluetooth do capacete.
/// - Fila: uma frase por vez; SOS passa na frente e interrompe a atual.
class VoiceService {
  VoiceService._();
  static final instance = VoiceService._();

  final _tts = FlutterTts();
  final _queue = <String>[];
  bool _ready = false;
  bool _speaking = false;

  /// true enquanto o app está falando (os comandos de voz pausam para não
  /// ouvir o próprio app).
  final speaking = ValueNotifier<bool>(false);

  /// Avisos falados (perigos, radares, SOS, paradas). Ligado por padrão.
  final alertsOn = ValueNotifier<bool>(true);

  /// Narração do trajeto (curva a curva). Desligada por padrão.
  final narrationOn = ValueNotifier<bool>(false);

  static const _kAlerts = 'voiceAlerts';
  static const _kNarration = 'voiceNarration';

  /// Prepara a voz em português (uma vez).
  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    alertsOn.value = prefs.getBool(_kAlerts) ?? true;
    narrationOn.value = prefs.getBool(_kNarration) ?? false;
    try {
      await _tts.setLanguage('pt-BR');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1);
      await _tts.awaitSpeakCompletion(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions.interruptSpokenAudioAndMixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
      _ready = true;
    } catch (e) {
      debugPrint('Voz indisponível: $e');
    }
  }

  /// Liga/desliga os avisos falados (radar, perigos, SOS).
  Future<void> setAlerts(bool v) async {
    alertsOn.value = v;
    (await SharedPreferences.getInstance()).setBool(_kAlerts, v);
    if (!v) await stop();
  }

  /// Liga/desliga a narração das curvas.
  Future<void> setNarration(bool v) async {
    narrationOn.value = v;
    (await SharedPreferences.getInstance()).setBool(_kNarration, v);
  }

  /// Fala um aviso (respeita o botão de avisos).
  void alert(String text, {bool urgent = false}) {
    if (alertsOn.value) _say(text, urgent: urgent);
  }

  /// Fala uma instrução do trajeto (respeita o botão de narração, a menos
  /// que [force]: usado na simulação da viagem).
  void narrate(String text, {bool force = false}) {
    if (narrationOn.value || force) _say(text);
  }

  bool _fast = false;

  /// Simulação acelerada: fala mais rápido e descarta frases atrasadas
  /// (só a mais recente fica na fila). [multiplier] = 1, 5, 20...
  Future<void> setFastMode(int multiplier) async {
    _fast = multiplier > 1;
    if (!_ready) await init();
    try {
      await _tts.setSpeechRate(switch (multiplier) {
        >= 20 => 0.7,
        >= 5 => 0.6,
        _ => 0.5,
      });
    } catch (_) {}
  }

  /// Fala mesmo com tudo desligado (botão "Testar voz").
  void test(String text) => _say(text, urgent: true);

  /// Resposta a um comando de voz ("Radar marcado"): fala mesmo com os
  /// avisos desligados, porque foi o piloto que pediu.
  void reply(String text) => _say(text, urgent: true);

  /// Cala a voz e limpa a fila.
  Future<void> stop() async {
    _queue.clear();
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
    speaking.value = false;
  }

  /// Fala ou põe na fila. [urgent] passa na frente (ex.: SOS).
  Future<void> _say(String text, {bool urgent = false}) async {
    if (!_ready) await init();
    if (!_ready) return;
    if (urgent) {
      _queue.insert(0, text);
      // Interrompe a frase atual; o laço que já está falando pega esta a seguir.
      if (_speaking) {
        try {
          await _tts.stop();
        } catch (_) {}
        return;
      }
    } else {
      // Não acumula a mesma frase repetida na fila.
      if (_queue.contains(text)) return;
      // Modo rápido (simulação acelerada): o que estava esperando já ficou
      // velho; mantém só a frase mais recente.
      if (_fast) _queue.clear();
      _queue.add(text);
    }
    if (_speaking) return;
    _speaking = true;
    speaking.value = true;
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      debugPrint('Voz: $next');
      try {
        await _tts.speak(next, focus: true);
      } catch (e) {
        debugPrint('Falha ao falar: $e');
      }
    }
    _speaking = false;
    speaking.value = false;
  }
}
