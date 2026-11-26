// ============================================================================
// voice_service.dart — Voz
//
// O que faz: Texto para fala em português: avisos (radar, perigos) e narração
//   das curvas, com fila, música abaixada durante a fala e modo rápido na
//   simulação.
// Quem usa: MapScreen, Configurações.
// Onde mexer: Velocidade da fala: setFastMode.
// ============================================================================

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/i18n.dart';
import 'offline_voice_service.dart';
import '../logic/navigation.dart' show spokenText;

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

  /// Até quando cada frase da fila ainda vale (avisos com distância ficam
  /// velhos rápido: a 80 km/h, 6 s são ~130 m).
  final _expires = <String, DateTime>{};

  /// Validade dos avisos falados ([alert]).
  static const alertMaxAge = Duration(seconds: 6);
  bool _ready = false;
  bool _speaking = false;

  /// true enquanto o app está falando (os comandos de voz pausam para não
  /// ouvir o próprio app).
  final speaking = ValueNotifier<bool>(false);

  /// Avisos falados (perigos, radares, SOS, paradas). Ligado por padrão.
  final alertsOn = ValueNotifier<bool>(true);

  /// Narração do trajeto (curva a curva). Ligada por padrão; depois fica
  /// como o piloto deixou (não religa a cada rota, 16/11).
  final narrationOn = ValueNotifier<bool>(true);

  static const _kAlerts = 'voiceAlerts';
  static const _kNarration = 'voiceNarration';
  static const _kVoice = 'voiceName';

  /// Voz escolhida em Configurações: nome do Android, "uaugo:<id>" (voz do
  /// UauGo, [OfflineVoice]) ou null = automática.
  final voiceName = ValueNotifier<String?>(null);

  /// Prepara a voz em português (uma vez).
  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    alertsOn.value = prefs.getBool(_kAlerts) ?? true;
    narrationOn.value = prefs.getBool(_kNarration) ?? true;
    try {
      await _tts.setLanguage(I18n.ttsLang);
      // Trocou o idioma do app: a voz acompanha.
      I18n.lang.addListener(() async {
        await _tts.setLanguage(I18n.ttsLang);
        await _applyVoice();
      });
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1);
      // Canal de navegação: no Android Auto a voz vai pelo canal de guia do
      // carro (e abaixa a música), em vez de misturar com a mídia.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setAudioAttributesForNavigation();
      }
      voiceName.value = prefs.getString(_kVoice);
      await OfflineVoiceService.instance.refresh();
      await _applyVoice();
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

  /// Vozes do idioma do app que funcionam sem internet. A voz "de rede", sem
  /// sinal na estrada, era trocada na hora por uma reserva fina e distorcida.
  Future<List<Map<String, String>>> voices() async {
    try {
      final all = await _tts.getVoices;
      final lang = I18n.ttsLang.toLowerCase();
      final list = [
        for (final v in (all as List? ?? const []))
          if (v is Map) {for (final e in v.entries) '${e.key}': '${e.value}'}
      ].where((v) =>
          (v['locale'] ?? '').toLowerCase() == lang &&
          v['network_required'] != '1' &&
          !(v['features'] ?? '').contains('notInstalled')).toList();
      list.sort((a, b) => a['name']!.compareTo(b['name']!));
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Usa a voz escolhida; sem escolha, uma do celular (sem internet) parecida
  /// com a padrão.
  Future<void> _applyVoice() async {
    // Voz do UauGo: a do celular fica como reserva (automática).
    if (OfflineVoice.byKey(voiceName.value) != null) return;
    final list = await voices();
    if (list.isEmpty) return;
    Map<String, String>? v;
    for (final x in list) {
      if (x['name'] == voiceName.value) v = x;
    }
    if (v == null) {
      final def = await _tts.getDefaultVoice;
      final name = def is Map ? '${def['name']}' : '';
      final base = name.replaceAll(RegExp(r'-(local|network)$'), '');
      for (final x in list) {
        if (base.isNotEmpty && x['name']!.startsWith(base)) v = x;
      }
      if (v == null && def is Map && '${def['network_required']}' != '1') return;
      v ??= list.first;
    }
    debugPrint('Voz: ${v['name']} (${list.length} sem internet)');
    await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
  }

  /// Escolhe uma voz do UauGo (já baixada) e fala uma frase de exemplo.
  Future<void> setOfflineVoice(OfflineVoice v) async {
    voiceName.value = v.key;
    (await SharedPreferences.getInstance()).setString(_kVoice, v.key);
    test(tr('Em 300 metros, vire à direita.'));
  }

  /// Volta para a voz automática do celular.
  Future<void> clearVoice() async {
    voiceName.value = null;
    (await SharedPreferences.getInstance()).remove(_kVoice);
    await _applyVoice();
  }

  /// Escolhe a voz (Configurações) e fala uma frase de exemplo.
  Future<void> setVoice(Map<String, String> v) async {
    voiceName.value = v['name'];
    (await SharedPreferences.getInstance()).setString(_kVoice, v['name']!);
    try {
      await _tts.setVoice({'name': v['name']!, 'locale': v['locale']!});
    } catch (_) {}
    test(tr('Em 300 metros, vire à direita.'));
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
    if (!alertsOn.value) return;
    // Urgente (SOS do grupo): sempre fala. Os demais, se atrasarem na fila
    // (uma fala encavalada na outra), são descartados: fica só a faixa na tela.
    if (!urgent) _expires[text] = DateTime.now().add(alertMaxAge);
    _say(text, urgent: urgent);
  }

  /// Fala uma instrução do trajeto (respeita o botão de narração, a menos
  /// que [force]: usado na simulação da viagem). Instrução atrasada também é
  /// descartada ("vire à direita" depois de passar a esquina só confunde).
  void narrate(String text, {bool force = false}) {
    if (!(narrationOn.value || force)) return;
    // A mesma frase de novo em menos de 30 s (recálculo, GPS que volta para
    // trás) não é repetida (pedido de 08/11).
    final now = DateTime.now();
    _recent.removeWhere((_, t) => now.difference(t) > const Duration(seconds: 30));
    if (!force && _recent.containsKey(text)) return;
    _recent[text] = now;
    _expires[text] = DateTime.now().add(alertMaxAge);
    _say(text);
  }

  bool _fast = false;

  /// Frases da narração faladas há pouco (texto -> quando).
  final _recent = <String, DateTime>{};

  /// Velocidade para a voz do UauGo (1 = normal), igual à do celular.
  double _offlineSpeed = 1;

  /// Simulação acelerada: fala mais rápido e descarta frases atrasadas
  /// (só a mais recente fica na fila). [multiplier] = 1, 5, 20...
  Future<void> setFastMode(int multiplier) async {
    _fast = multiplier > 1;
    if (!_ready) await init();
    try {
      _offlineSpeed = switch (multiplier) { >= 20 => 1.4, >= 5 => 1.2, _ => 1.0 };
      await _tts.setSpeechRate(switch (multiplier) {
        >= 20 => 0.7,
        >= 5 => 0.6,
        _ => 0.5,
      });
    } catch (_) {}
  }

  AudioPlayer? _chime;

  /// "Glug" (duas bolhas) no lugar da frase "Recalculando a rota" (26/11).
  /// Respeita o botão de narração e não toca por cima de uma fala.
  Future<void> recalcChime() async {
    if (!narrationOn.value || _speaking) return;
    try {
      final p = _chime ??= AudioPlayer();
      await p.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceNavigationGuidance,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.duckOthers},
        ),
      ));
      await p.setReleaseMode(ReleaseMode.stop);
      await p.play(AssetSource('sounds/glug.wav'));
    } catch (e) {
      debugPrint('Glug: $e');
    }
  }

  /// Fala mesmo com tudo desligado (botão "Testar voz").
  void test(String text) => _say(text, urgent: true);

  /// Resposta a um comando de voz ("Radar marcado"): fala mesmo com os
  /// avisos desligados, porque foi o piloto que pediu.
  void reply(String text) => _say(text, urgent: true);

  /// Cala a voz e limpa a fila.
  Future<void> stop() async {
    _queue.clear();
    await OfflineVoiceService.instance.stop();
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
        await OfflineVoiceService.instance.stop();
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
      final exp = _expires.remove(next);
      if (exp != null && DateTime.now().isAfter(exp)) {
        debugPrint('Voz (descartada, ficou velha): $next');
        continue;
      }
      // Abreviações, cidades das placas e romanos por extenso (vale para
      // toda frase: Google, motor próprio, paradas, avisos).
      final say = spokenText(next);
      debugPrint('Voz: $say');
      try {
        // Voz do UauGo; se falhar (arquivo apagado etc.), a do celular.
        final ov = OfflineVoice.byKey(voiceName.value);
        if (ov == null ||
            !await OfflineVoiceService.instance.speak(ov, say, speed: _offlineSpeed)) {
          await _tts.speak(say, focus: true);
        }
      } catch (e) {
        debugPrint('Falha ao falar: $e');
      }
    }
    _speaking = false;
    speaking.value = false;
  }
}

/// Nome da voz para a lista: "Voz 2 · masculina" quando o nome do Android
/// indica o gênero (Samsung: ...SMTf00 / ...SMTm00); senão, "Voz 2" e o código.
String voiceLabel(String name, [int? n]) {
  final g = RegExp(r'SMT([fm])\d', caseSensitive: false).firstMatch(name);
  final head = n == null ? tr('Voz') : tr('Voz {0}', [n]);
  if (g != null) {
    return '$head · ${g[1]!.toLowerCase() == 'm' ? tr('masculina') : tr('feminina')}';
  }
  final code = RegExp(r'-x-([a-z]+)').firstMatch(name)?[1];
  return code == null ? head : '$head ($code)';
}
