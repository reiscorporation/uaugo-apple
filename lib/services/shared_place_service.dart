// ============================================================================
// shared_place_service.dart — Endereço recebido de outro app
//
// O que faz: Recebe do Android (SharedPlace.kt, canal "uaugo/shared_place") o
//   texto/link de "Abrir com UauGo" ou "Compartilhar → UauGo", guarda até a
//   tela inicial usar e o transforma em lugar: abre links curtos do Google
//   Maps e dá nome a coordenadas soltas.
// Quem usa: main.dart (init) e HomeScreen (leva ao "Para onde?").
// Onde mexer: Formatos aceitos: lib/logic/shared_place.dart.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../logic/shared_place.dart';

class SharedPlaceService {
  SharedPlaceService._();
  static final instance = SharedPlaceService._();

  static const _channel = MethodChannel('uaugo/shared_place');

  /// Texto recebido e ainda não usado (a tela inicial escuta).
  final pending = ValueNotifier<String?>(null);

  /// Liga o canal e pega o que abriu o app, se for o caso.
  Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') pending.value = call.arguments as String?;
    });
    try {
      final first = await _channel.invokeMethod<String>('initial');
      if (first != null) pending.value = first;
    } catch (_) {} // outras plataformas: sem canal
  }

  /// Pega o texto pendente (uma vez só).
  String? take() {
    final v = pending.value;
    pending.value = null;
    return v;
  }

  /// Texto recebido → lugar (abre link curto; nomeia coordenadas soltas).
  Future<SharedPlace?> resolve(String raw) async {
    var place = parseSharedPlace(raw);
    if (place?.shortLink != null) {
      final full = await _expand(place!.shortLink!);
      final r = full == null ? null : parseMapsUrl(full);
      place = r == null
          ? (place.label == null ? null : SharedPlace(query: place.label))
          : (r.label == null && place.label != null
              ? SharedPlace(lat: r.lat, lng: r.lng, query: r.query, label: place.label)
              : r);
    }
    if (place == null || !place.hasCoords || place.label != null) return place;
    return SharedPlace(lat: place.lat, lng: place.lng, label: await _nameOf(place));
  }

  /// Segue os redirecionamentos do link curto até o link completo do mapa.
  Future<Uri?> _expand(Uri u) async {
    final client = http.Client();
    try {
      var cur = u;
      for (var i = 0; i < 6; i++) {
        final req = http.Request('GET', cur)..followRedirects = false;
        final res = await client.send(req).timeout(const Duration(seconds: 8));
        await res.stream.drain<void>();
        final loc = res.headers['location'];
        if (res.statusCode < 300 || res.statusCode >= 400 || loc == null) {
          return i == 0 ? null : cur;
        }
        cur = cur.resolve(loc);
        if (cur.host.contains('google.') && cur.path.startsWith('/maps')) {
          return cur;
        }
      }
      return cur;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Nome para uma coordenada solta (rua, cidade); feito no próprio celular.
  Future<String> _nameOf(SharedPlace p) async {
    try {
      final pm = (await placemarkFromCoordinates(p.lat!, p.lng!)).firstOrNull;
      if (pm != null) {
        final name = [pm.street, pm.subAdministrativeArea ?? pm.locality]
            .where((x) => x != null && x.trim().isNotEmpty)
            .join(', ');
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}
    return 'Local recebido';
  }
}
