// ============================================================================
// offline_voice_service.dart — Vozes do UauGo (sem internet)
//
// O que faz: Vozes próprias em português (Piper, código aberto), diferentes
//   das que vêm no celular. O piloto baixa a que quiser (~21 MB, uma vez) e
//   ela fala sem internet. A síntese roda num isolate separado para não
//   travar o mapa; o áudio sai pelo canal de navegação (abaixa a música e vai
//   para o carro/capacete, como a voz do celular).
// Quem usa: VoiceService (fala), Configurações (baixar/escolher).
// Onde mexer: Lista de vozes: [OfflineVoice.catalog].
// Licenças: Faber, Cadu e Jeff (rhasspy/piper-voices, dados CC0). Não usar
//   Dii/Miro (OpenVoiceOS): licença não comercial.
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Uma voz do UauGo.
class OfflineVoice {
  const OfflineVoice(this.id, this.label, this.pkg, this.model);

  /// Guardado em Configurações como "uaugo:<id>".
  final String id;
  final String label;

  /// Pacote no sherpa-onnx (tts-models) e o arquivo do modelo dentro dele.
  final String pkg;
  final String model;

  String get url =>
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$pkg.tar.bz2';

  static const prefix = 'uaugo:';
  String get key => '$prefix$id';

  /// Vozes oferecidas (todas em português do Brasil, masculinas: não há voz
  /// feminina pt-BR do Piper com licença que permita uso comercial).
  static const catalog = [
    OfflineVoice('faber', 'Faber', 'vits-piper-pt_BR-faber-medium-int8', 'pt_BR-faber-medium.onnx'),
    OfflineVoice('cadu', 'Cadu', 'vits-piper-pt_BR-cadu-medium-int8', 'pt_BR-cadu-medium.onnx'),
    OfflineVoice('jeff', 'Jeff', 'vits-piper-pt_BR-jeff-medium-int8', 'pt_BR-jeff-medium.onnx'),
  ];

  static OfflineVoice? byKey(String? key) {
    for (final v in catalog) {
      if (v.key == key) return v;
    }
    return null;
  }
}

class OfflineVoiceService {
  OfflineVoiceService._();
  static final instance = OfflineVoiceService._();

  /// Baixando: id da voz -> progresso 0..1 (null = preparando/extraindo).
  final downloading = ValueNotifier<Map<String, double?>>({});

  /// Vozes já baixadas (atualiza a tela de Configurações).
  final installed = ValueNotifier<Set<String>>({});

  final _player = AudioPlayer();
  bool _playerReady = false;

  _Worker? _worker;
  String? _workerVoice;

  Future<Directory> _root() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}/voices');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> _dir(OfflineVoice v) async => '${(await _root()).path}/${v.pkg}';

  /// Confere quais vozes já estão no celular.
  Future<void> refresh() async {
    final s = <String>{};
    for (final v in OfflineVoice.catalog) {
      if (await File('${await _dir(v)}/${v.model}').exists()) s.add(v.id);
    }
    installed.value = s;
  }

  bool isInstalled(OfflineVoice v) => installed.value.contains(v.id);

  /// Baixa e prepara a voz. Devolve false se falhar (sem internet etc.).
  Future<bool> download(OfflineVoice v) async {
    if (downloading.value.containsKey(v.id)) return false;
    void prog(double? p) => downloading.value = {...downloading.value, v.id: p};
    prog(0);
    final root = await _root();
    final tar = File('${root.path}/${v.pkg}.tar.bz2');
    try {
      final req = await http.Client().send(http.Request('GET', Uri.parse(v.url)));
      if (req.statusCode != 200) throw 'HTTP ${req.statusCode}';
      final total = req.contentLength ?? 0;
      var got = 0;
      final sink = tar.openWrite();
      await for (final chunk in req.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) prog(got / total);
      }
      await sink.close();
      prog(null); // extraindo
      final out = root.path;
      await Isolate.run(() => extractFileToDisk(tar.path, out));
      await refresh();
      return isInstalled(v);
    } catch (e) {
      debugPrint('Voz do UauGo: falha ao baixar ${v.id}: $e');
      return false;
    } finally {
      if (await tar.exists()) await tar.delete();
      downloading.value = {...downloading.value}..remove(v.id);
    }
  }

  /// Apaga a voz do celular (libera espaço).
  Future<void> remove(OfflineVoice v) async {
    if (_workerVoice == v.id) {
      _worker?.close();
      _worker = null;
      _workerVoice = null;
    }
    final d = Directory(await _dir(v));
    if (await d.exists()) await d.delete(recursive: true);
    await refresh();
  }

  Future<void> _preparePlayer() async {
    if (_playerReady) return;
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.speech,
        usageType: AndroidUsageType.assistanceNavigationGuidance,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));
    await _player.setReleaseMode(ReleaseMode.stop);
    _playerReady = true;
  }

  /// Fala [text] com a voz [v] e espera terminar. [speed] 1 = normal.
  /// Devolve false se não deu (a VoiceService usa a voz do celular).
  Future<bool> speak(OfflineVoice v, String text, {double speed = 1}) async {
    if (!isInstalled(v)) return false;
    final stopped = _stopped.future;
    try {
      if (_workerVoice != v.id) {
        _worker?.close();
        final dir = await _dir(v);
        _worker = await _Worker.start(
            model: '$dir/${v.model}',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data');
        _workerVoice = v.id;
      }
      final tmp = await getTemporaryDirectory();
      final t0 = DateTime.now();
      final wav = await _worker!.say(text, speed, '${tmp.path}/uaugo_voz.wav');
      // Tempo para montar a frase (10/11: testador achou a voz
      // desincronizada; frase longa em celular simples pode demorar).
      debugPrint('Voz do UauGo: ${DateTime.now().difference(t0).inMilliseconds} ms para ${text.length} letras');
      if (wav == null) return false;
      await _preparePlayer();
      final done = _player.onPlayerComplete.first;
      await _player.play(DeviceFileSource(wav));
      // Parada no meio (stop) também libera a espera.
      await Future.any([done, stopped]);
      return true;
    } catch (e) {
      debugPrint('Voz do UauGo: falha ao falar: $e');
      return false;
    }
  }

  Completer<void> _stopped = Completer<void>();

  Future<void> stop() async {
    if (!_stopped.isCompleted) _stopped.complete();
    _stopped = Completer<void>();
    try {
      await _player.stop();
    } catch (_) {}
  }
}

/// Isolate que guarda o sintetizador carregado (carregar leva ~1 s; gerar
/// uma frase, uma fração disso) e grava o .wav.
class _Worker {
  _Worker._(this._iso, this._send, this._replies);
  final Isolate _iso;
  final SendPort _send;
  final StreamQueue _replies;

  static Future<_Worker> start(
      {required String model, required String tokens, required String dataDir}) async {
    final rp = ReceivePort();
    final iso = await Isolate.spawn(_main, [rp.sendPort, model, tokens, dataDir]);
    final q = StreamQueue(rp);
    final send = await q.next as SendPort;
    final ok = await q.next;
    if (ok != true) {
      iso.kill();
      throw 'não carregou: $ok';
    }
    return _Worker._(iso, send, q);
  }

  Future<String?> say(String text, double speed, String path) async {
    _send.send([text, speed, path]);
    final r = await _replies.next;
    return r is String ? r : null;
  }

  void close() {
    _iso.kill(priority: Isolate.immediate);
    _replies.cancel();
  }

  static void _main(List args) {
    final out = args[0] as SendPort;
    final rp = ReceivePort();
    out.send(rp.sendPort);
    sherpa.OfflineTts? tts;
    try {
      sherpa.initBindings();
      tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: args[1] as String,
            tokens: args[2] as String,
            dataDir: args[3] as String,
          ),
          numThreads: 2,
          debug: false,
        ),
      ));
      out.send(true);
    } catch (e) {
      out.send('$e');
      return;
    }
    rp.listen((msg) {
      final m = msg as List;
      try {
        final a = tts!.generate(text: m[0] as String, speed: m[1] as double);
        final ok = sherpa.writeWave(
            filename: m[2] as String, samples: a.samples, sampleRate: a.sampleRate);
        out.send(ok ? m[2] : null);
      } catch (_) {
        out.send(null);
      }
    });
  }
}

/// Fila mínima sobre um Stream (respostas do isolate, na ordem).
class StreamQueue {
  StreamQueue(Stream s) {
    _sub = s.listen((e) {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete(e);
      } else {
        _buf.add(e);
      }
    });
  }
  late final StreamSubscription _sub;
  final _buf = <dynamic>[];
  final _waiting = <Completer<dynamic>>[];

  Future<dynamic> get next {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    final c = Completer<dynamic>();
    _waiting.add(c);
    return c.future;
  }

  void cancel() {
    _sub.cancel();
    for (final c in _waiting) {
      c.complete(null);
    }
    _waiting.clear();
  }
}
