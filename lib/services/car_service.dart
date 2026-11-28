// ============================================================================
// car_service.dart — Modo carro (Android Auto)
//
// O que faz: Manda para a tela do carro (android/.../CarBridge.kt, canal
//   "uaugo/car") a próxima manobra, a chegada, a rota e a posição; recebe os
//   botões do carro (Radar, Perigo, Encerrar). Com o carro conectado e
//   navegando, o mapa mantém GPS, voz e avisos mesmo com o celular bloqueado.
//   Destinos (casa, salvos, recentes) vão para a lista do carro; com o carro
//   conectado e o celular apagado, as telas continuam sendo montadas
//   (quadros forçados): escolher destino no carro abre a rota sem desbloquear.
// Quem usa: MapScreen.
// ============================================================================

import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import '../widgets/bike_marker.dart';
import '../logic/route_window.dart';
import 'profile_service.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/hazard.dart';
import 'auth_service.dart';
import 'hazard_service.dart';
import '../l10n/i18n.dart';
import 'app_settings.dart';
import 'car_settings.dart';
import 'places_service.dart';
import 'recent_places_service.dart';
import 'saved_places_service.dart';
import 'shared_place_service.dart';

class CarService {
  CarService._();
  static final instance = CarService._();

  static const _ch = MethodChannel('uaugo/car');

  /// A tela do carro está aberta.
  final connected = ValueNotifier<bool>(false);

  /// Próximas manobras (tipo, texto, metros até ela), da mais perto à mais
  /// longe; as já passadas saem. Usada só na tela do celular do UauGo2 de
  /// testes com o carro conectado (na Play o celular fica só com o aviso:
  /// regra "Visual info on phone" do Android Auto, 13/11).
  final upcoming = ValueNotifier<List<(String, String, int)>>(const []);

  /// Botões do carro: "radar", "hazard", "stop".
  final _actions = StreamController<String>.broadcast();
  Stream<String> get actions => _actions.stream;

  bool _started = false;
  String _routeSig = '';
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void init() {
    if (_started) return;
    _started = true;
    _ch.setMethodCallHandler((c) async {
      if (c.method == 'action') {
        final a = c.arguments as String;
        // Busca de destino feita no carro: o app procura e responde (com o
        // mapa aberto ou não).
        if (a.startsWith('search:')) {
          _searchFromCar(a.substring(7));
          return;
        }
        if (a.startsWith('place:')) {
          _placeFromCar(a.substring(6));
          return;
        }
        debugPrint('Carro: $a (mapa aberto: ${_actions.hasListener}, '
            'app: ${WidgetsBinding.instance.lifecycleState})');
        // Mapa aberto no celular: ele cuida. Senão, os botões ainda valem.
        if (_actions.hasListener) {
          _actions.add(a);
        } else {
          _handleWithoutMap(a);
        }
      }
      if (c.method == 'connected') {
        // Carro (re)conectado: manda a rota e os pins de novo (a tela do
        // carro pode ter sido recriada e ficava sem o trajeto).
        if (c.arguments == true) {
          _routeSig = '';
          _poisSig = '';
          _hazardsSig = '';
          _membersSig = '';
          _groupSig = '';
        }
        connected.value = c.arguments == true;
        if (c.arguments == true) _sendVehicle();
      }
    });
    _ch.invokeMethod<bool>('connected').then((v) {
      connected.value = v == true;
      if (v == true) _sendVehicle();
    },
        onError: (_) {});
    connected.addListener(_onConnected);
    // Segurança (23/11): com a trava na tela, confere a cada 5 s se o carro
    // ainda está conectado (se o aviso de desconexão se perder, a tela do
    // celular volta sozinha).
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (!connected.value) return;
      _ch.invokeMethod<bool>('connected').then((v) {
        if (v != true && connected.value) connected.value = false;
      }, onError: (_) {});
    });
    SavedPlacesService.instance.places.addListener(sendDestinations);
  }

  Timer? _frames;

  /// Celular apagado ou bloqueado: o Android para de montar as telas, e a rota
  /// pedida no carro só começava ao desbloquear. Com o carro conectado,
  /// força um quadro a cada 0,5 s enquanto o app não está na frente.
  void _onConnected() {
    _frames?.cancel();
    _frames = null;
    if (!connected.value) return;
    sendDestinations();
    _frames = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        SchedulerBinding.instance.scheduleForcedFrame();
      }
    });
  }

  /// Casa, trabalho, locais salvos e os recentes, para escolher no carro.
  Future<void> sendDestinations() async {
    if (!connected.value) return;
    await SavedPlacesService.instance.load();
    final recent = await RecentPlacesService.instance.load();
    final seen = <String>{};
    final list = <Map<String, Object>>[];
    void add(String name, double lat, double lng) {
      final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
      if (name.isEmpty || !seen.add(key) || list.length >= 12) return;
      list.add({'n': name, 'la': lat, 'lo': lng});
    }
    for (final p in SavedPlacesService.instance.places.value) {
      add(p.name, p.lat, p.lng);
    }
    for (final p in recent) {
      add(p.name, p.lat, p.lng);
    }
    _ch.invokeMethod('destinations', list).catchError((_) => null);
  }

  /// Aviso curto na tela do carro.
  String _poisSig = '';
  String _hazardsSig = '';
  String _groupSig = '';

  /// Manda a imagem do veículo assim que o carro conecta (sem depender do
  /// mapa aberto no celular).
  Future<void> _sendVehicle() async {
    try {
      vehicleImage(await bikeBadgePng(await ProfileService.load()));
    } catch (_) {}
  }

  /// Visão escolhida no celular vale no carro: 0 mapa, 1 nas saídas, 2 sempre.
  String _emergencySig = '';

  /// Contato de emergência para o SOS da tela do carro (ligar pelo carro).
  void emergency(String? name, String? phone, {bool force = false}) {
    final sig = '$name|$phone';
    if (sig == _emergencySig && !force) return;
    _emergencySig = sig;
    _ch.invokeMethod('emergency', {'name': name, 'phone': phone})
        .catchError((_) => null);
  }

  bool? _offlineSent;

  /// Celular sem internet: o carro troca o mapa pela estrada da rota e avisa.
  void offline(bool v, {bool force = false}) {
    if (v == _offlineSent && !force) return;
    _offlineSent = v;
    _ch.invokeMethod('offline', v).catchError((_) => null);
  }

  void mode3d(int mode) {
    _ch.invokeMethod('mode3d', mode).catchError((_) => null);
  }

  /// Imagem do veículo (a mesma do mapa do celular) para a tela do carro.
  void vehicleImage(Uint8List png) {
    if (!connected.value) return;
    _ch.invokeMethod('vehicleImage', png).catchError((_) => null);
  }

  /// Comando da cena 3D (a mesma do celular) para a tela do carro.
  void sim3d(String js) {
    if (!connected.value) return;
    _ch.invokeMethod('sim3d', js).catchError((_) => null);
  }

  /// Pins de radares/postos policiais perto: (lat, lng, tipo).
  void pois(List<(double, double, int)> list) {
    final sig = list.map((e) => '${e.$1},${e.$2}').join(';');
    if (sig == _poisSig) return;
    _poisSig = sig;
    _ch.invokeMethod('pois', [
      for (final (la, lo, k) in list) ...[la, lo, k.toDouble()]
    ]).catchError((_) => null);
  }

  /// Expedição: botões do grupo e a faixa de SOS/pedidos. [action] volta
  /// para o app quando o motorista toca na faixa.
  void group({required bool on, String? text, String? action, bool urgent = false}) {
    final sig = '$on|$text|$action|$urgent';
    if (sig == _groupSig) return;
    _groupSig = sig;
    _ch.invokeMethod('group', {
      'on': on, 'text': text, 'action': action, 'urgent': urgent,
    }).catchError((_) => null);
  }

  /// Alertas da comunidade perto: (id, lat, lng, emoji, nome, é meu).
  String _membersSig = '';

  /// Colegas do comboio na tela do carro: (nome, lat, lng).
  void members(List<(String, double, double)> list) {
    final sig = list.map((m) => '${m.$1}${m.$2.toStringAsFixed(4)}${m.$3.toStringAsFixed(4)}').join(';');
    if (sig == _membersSig) return;
    _membersSig = sig;
    _ch.invokeMethod('members', [
      for (final m in list) ...[m.$1, m.$2, m.$3]
    ]).catchError((_) => null);
  }

  void hazards(List<(String, double, double, String, String, bool)> list) {
    final sig = list.map((e) => '${e.$1},${e.$6}').join(';');
    if (sig == _hazardsSig) return;
    _hazardsSig = sig;
    _ch.invokeMethod('hazards', [
      for (final h in list) ...[h.$1, h.$2, h.$3, h.$4, h.$5, h.$6]
    ]).catchError((_) => null);
  }

  /// Some a navegação da tela do carro (rota, manobra, chegada) na hora.
  void clearNavigation() {
    _routeSig = '';
    _ch.invokeMethod('clearNav').catchError((_) => null);
  }

  final _found = <String, PlaceSuggestion>{};
  final _places = PlacesService();

  /// Procura [text] perto da posição atual e manda até 6 lugares ao carro.
  Future<void> _searchFromCar(String text) async {
    Position? me;
    try {
      me = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    // Erro na busca: responde a lista vazia mesmo assim (senão a tela do
    // carro ficava em "Buscando…" para sempre).
    var res = <PlaceSuggestion>[];
    try {
      res = await _places
          .search(text, nearLat: me?.latitude, nearLng: me?.longitude)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      _places.lastFailed = true;
    }
    _found
      ..clear()
      ..addEntries(res.map((s) => MapEntry(s.placeId, s)));
    await _ch.invokeMethod('searchResults', [
      for (final s in res.take(6)) {'id': s.placeId, 'n': s.title, 's': s.subtitle},
    ]).catchError((_) => null);
    if (res.isEmpty && _places.lastFailed) {
      toast(tr('Não foi possível buscar agora (código: {0})', [_places.lastErrorCode ?? '?']));
    }
  }

  /// Lugar escolhido na busca do carro: pega a posição e abre a rota, igual
  /// aos destinos salvos ("navigate:geo:...").
  Future<void> _placeFromCar(String arg) async {
    final i = arg.indexOf('|');
    final id = i < 0 ? arg : arg.substring(0, i);
    final s = _found[id];
    if (s == null) return;
    final d = await _places.details(s);
    if (d == null) {
      toast(tr('Não foi possível abrir este lugar. Tente de novo.'));
      return;
    }
    final name = s.title.replaceAll('(', ' ').replaceAll(')', ' ');
    final a = 'navigate:geo:${d.lat},${d.lng}?q=${Uri.encodeComponent(name)}';
    if (_actions.hasListener) {
      _actions.add(a);
    } else {
      _handleWithoutMap(a);
    }
  }

  /// Lista para a tela do carro (busca de parada): id, nome e linha de baixo.
  Future<void> results(List<({String id, String name, String info})> list) =>
      _ch.invokeMethod('searchResults', [
        for (final r in list.take(6)) {'id': r.id, 'n': r.name, 's': r.info},
      ]).catchError((_) => null);

  /// Pergunta Sim/Não na tela do carro; a resposta volta como ação
  /// "resume:yes" / "resume:no".
  /// Pergunta sim/não na tela do carro. A resposta volta como [yes] ou [no]
  /// (padrão: "Continuar a rota?" -> resume:yes / resume:no).
  void ask(String title, String text,
          {String yes = 'resume:yes',
          String no = 'resume:no',
          String? yesLabel,
          String? noLabel}) =>
      _ch.invokeMethod('ask', {
        'title': title,
        'text': text,
        'yes': yes,
        'no': no,
        if (yesLabel != null) 'yesLabel': yesLabel,
        if (noLabel != null) 'noLabel': noLabel,
      }).catchError((_) => null);

  /// Fecha a pergunta/opções abertas na tela do carro (passou o tempo).
  void closeAsk() => _ch.invokeMethod('closeAsk').catchError((_) => null);

  /// Fecha a lista de alertas do carro (o alerta falado já foi marcado).
  void closeAlerts() => _ch.invokeMethod('closeAlerts').catchError((_) => null);

  /// Opções de velocidade na tela do carro (confirmar, radar não existe,
  /// corrigir). A escolha volta como "speedpick:N" (0 = radar não existe).
  /// Corrigir o pedágio na tela do carro (valor atual em centavos).
  void tollEdit(String title, int cents) => _ch
      .invokeMethod('tollEdit', {'title': title, 'cents': cents}).catchError((_) => null);

  void speedEdit(String title, int? current, bool radar) => _ch.invokeMethod(
      'speedEdit', {'title': title, 'current': current, 'radar': radar}).catchError((_) => null);

  void toast(String text) =>
      _ch.invokeMethod('toast', text).catchError((_) => null);

  /// Botão do carro com o UauGo fora do mapa (tela inicial, outra tela):
  /// Radar/Perigo marcam o alerta na posição atual; Encerrar não tem o que
  /// encerrar.
  Future<void> _handleWithoutMap(String a) async {
    // Destino pedido ao Assistente/Gemini no carro: a tela inicial traça a
    // rota e inicia sozinha.
    if (a.startsWith('navigate:')) {
      final geo = a.substring(9);
      SharedPlaceService.instance.fromVoice = true;
      SharedPlaceService.instance.pending.value = geo;
      toast(tr('Buscando o destino…'));
      // 28/11 (Play): primeira vez no celular (termos/autorizações ainda não
      // aceitos) a tela inicial não abre e o pedido ficava sem resposta.
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (SharedPlaceService.instance.pending.value == geo) {
          toast(tr('Abra o UauGo no celular para concluir a configuração e navegar até o destino'));
        }
      });
      return;
    }
    // Lista de alertas aberta sem o mapa: não ouve (os toques funcionam).
    if (a == 'hazard:voice:auto' || a == 'hazard:voicecancel' || a == 'findvoice:auto') return;
    if (a == 'hazard:voice') {
      toast(tr('Abra o mapa no celular para falar o alerta'));
      return;
    }
    if (a.startsWith('unhazard:')) {
      toast(tr('Abra o mapa no celular para remover o alerta'));
      return;
    }
    final type = switch (a) {
      'radar' => HazardType.radar,
      'hazard' => HazardType.danger,
      // Lista de alertas do carro: "hazard:police", "hazard:pothole"...
      final x when x.startsWith('hazard:') => HazardType.fromName(x.substring(7)),
      _ => null,
    };
    if (type == null) {
      toast(tr('Nenhuma navegação em andamento'));
      return;
    }
    if (AuthService.isAnonymous) {
      toast(tr('Entre na sua conta no celular para marcar alertas'));
      return;
    }
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition();
      final uid = AuthService.user?.uid;
      if (uid == null) return;
      await HazardService.instance.report(type, p.latitude, p.longitude, uid,
          heading: p.speed > 2 && p.heading >= 0 ? p.heading : null);
      toast(tr('Alerta enviado: {0}', [type.label]));
    } catch (_) {
      toast(tr('Não foi possível marcar o alerta'));
    }
  }

  /// Estado da navegação (no máximo 1 vez por segundo). [text] null = sem
  /// navegação (o carro mostra "Abra a navegação no UauGo").
  void update({
    required double lat,
    required double lng,
    required double bearing,
    required int speedKmh,
    int limitKmh = 0,
    bool speedOver = false,
    bool radarOver = false,
    bool dark = false,
    String? text,
    String maneuver = '',
    double meters = 0,
    double remainingM = 0,
    DateTime? eta,
    String? alert,
    String? banner,
    String vehicle = '🏍️',
    bool convoy = false,
    bool onRoute = false,
  }) {
    final now = DateTime.now();
    if (now.difference(_last) < const Duration(milliseconds: 900)) return;
    _last = now;
    _ch.invokeMethod('update', {
      'lat': lat,
      'lng': lng,
      'bearing': bearing,
      'speedKmh': speedKmh,
      'limitKmh': limitKmh,
      'speedOver': speedOver,
      'radarOver': radarOver,
      // Noite pela regra do celular (pôr do sol / opção do app): muitos carros
      // não informam o modo noturno (25/11).
      'dark': dark,
      'lang': I18n.lang.value, // textos da tela do carro
      'placeNames': AppSettings.instance.carPlaceNames.value,
      'convoy': convoy,
      // O celular está seguindo a rota: o carro põe o veículo na linha azul.
      'onRoute': onRoute,
      // Configurações mostradas na tela do carro (⚙).
      'cfg': CarSettings.toCar(),
      // Elétrico/plug-in: "Eletroposto" nas paradas do carro.
      'ev': AppSettings.instance.fuel.value.energy.plugs,
      // Valem com ou sem rota (Só dirigir): contagem do radar, faixa amarela
      // de aviso e o ícone do veículo.
      if (alert != null) 'alert': alert,
      if (banner != null) 'banner': banner,
      'vehicle': vehicle,
      // Próximos passos (painel da direita no carro, como no celular deitado).
      'steps': [
        for (final s in upcoming.value.take(8)) [s.$1, s.$2, s.$3],
      ],
      if (text != null) ...{
        'text': text,
        'maneuver': maneuver,
        'meters': meters,
        'remainingM': remainingM,
        'eta': eta?.millisecondsSinceEpoch ?? 0,
      },
    }).catchError((_) => null);
  }

  /// Rota (enviada só quando muda). Simplificada sem cortar esquinas
  /// (Douglas-Peucker): pegar 1 ponto a cada N deixava a linha do carro
  /// atravessando quarteirões, fora das ruas (11/11).
  /// [force]: manda de novo mesmo igual (o carro reconectou e o lado
  /// nativo pode ter perdido a rota: no teste do painel, 16/11, o carro
  /// ficou sem a linha azul depois de reconectar).
  ///
  /// Perto do veículo a linha vai com 1 m (como no celular); o resto da rota
  /// vai mais leve. Com a rota inteira simplificada em 4-16 m (rotas longas,
  /// limite de 4000 pontos), a linha do carro cortava as curvas e saía de
  /// cima da rua (16/11). O trecho detalhado anda junto com o veículo
  /// ([routeAt]).
  void route(List<(double, double)> pts, {bool force = false}) {
    final sig = pts.isEmpty ? '' : '${pts.length}:${pts.first}:${pts.last}';
    if (sig == _routeSig && !force) return;
    _routeSig = sig;
    _window = pts.length >= 2 ? RouteWindow(pts) : null;
    _sendRoute(_lastAlong);
  }

  RouteWindow? _window;
  double _lastAlong = 0;

  /// Veículo em [along] metros da rota: refaz o trecho detalhado quando ele
  /// chega perto do fim (a cada ~3 km).
  void routeAt(double along) {
    _lastAlong = along;
    final w = _window;
    if (w == null || !w.needsMove(along)) return;
    _sendRoute(along);
  }

  void _sendRoute(double along) {
    final w = _window;
    final s = w == null ? const <(double, double)>[] : w.build(along);
    final flat = <double>[for (final p in s) ...[p.$1, p.$2]];
    _ch.invokeMethod('route', flat).catchError((_) => null);
  }

  /// Trechos da rota com trânsito: [nível, nº de pontos, lat, lng, ...].
  void traffic(List<(int, List<(double, double)>)> runs) {
    final flat = <double>[
      for (final (level, pts) in runs) ...[
        level.toDouble(),
        pts.length.toDouble(),
        for (final p in pts) ...[p.$1, p.$2],
      ],
    ];
    _ch.invokeMethod('traffic', flat).catchError((_) => null);
  }

  void clear() {
    _routeSig = '';
    _ch.invokeMethod('clear').catchError((_) => null);
  }
}
