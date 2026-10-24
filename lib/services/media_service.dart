// ============================================================================
// media_service.dart — Música tocando (Spotify e outros) para o mini player
//
// O que faz: Recebe do Android (MediaBridge.kt) o título, o artista, a capa e
//   se está tocando, e manda os comandos anterior / tocar-pausar / próxima.
//   Só com "Acesso a notificações" liberado pelo usuário e com o mapa na
//   tela. Nada sai do celular.
// Quem usa: MapScreen (mini player) e SettingsScreen (opção e acesso).
// Onde mexer: lado Android em MediaBridge.kt.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// O que está tocando agora.
class MediaState {
  final String title;
  final String artist;
  final bool playing;
  final Uint8List? art;

  /// Ícone do app que está tocando (Spotify, YouTube Music...).
  final Uint8List? appIcon;
  const MediaState(this.title, this.artist, this.playing, this.art, [this.appIcon]);
}

class MediaService {
  MediaService._() {
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'state') return;
      final a = call.arguments as Map?;
      if (a == null) {
        state.value = null;
        return;
      }
      // A capa só vem quando a música muda; senão, mantém a anterior.
      final art = a.containsKey('art')
          ? a['art'] as Uint8List?
          : state.value?.art;
      final icon = a.containsKey('appIcon')
          ? a['appIcon'] as Uint8List?
          : state.value?.appIcon;
      state.value = MediaState((a['title'] ?? '') as String,
          (a['artist'] ?? '') as String, a['playing'] == true, art, icon);
    });
  }
  static final instance = MediaService._();

  static const _ch = MethodChannel('uaugo/media');

  /// null = nada tocando (ou sem acesso).
  final state = ValueNotifier<MediaState?>(null);

  bool get _android => defaultTargetPlatform == TargetPlatform.android;

  /// O usuário já liberou "Acesso a notificações" para o UauGo?
  Future<bool> hasAccess() async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre a tela do Android onde se libera o acesso.
  Future<void> openSettings() async {
    if (_android) await _ch.invokeMethod('openSettings');
  }

  /// Abre o app de música do celular. false = não há nenhum.
  Future<bool> openMusicApp() async {
    if (!_android) return false;
    try {
      return await _ch.invokeMethod<bool>('openMusicApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Começa / para de acompanhar a música (com o mapa na tela).
  Future<void> start() async {
    if (_android) await _ch.invokeMethod('start').catchError((_) => null);
  }

  Future<void> stop() async {
    if (!_android) return;
    await _ch.invokeMethod('stop').catchError((_) => null);
    state.value = null;
  }

  /// 'previous', 'toggle' ou 'next'.
  Future<void> command(String c) async {
    if (_android) await _ch.invokeMethod('command', c).catchError((_) => null);
  }
}
