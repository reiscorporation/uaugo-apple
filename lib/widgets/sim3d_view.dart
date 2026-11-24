// ============================================================================
// sim3d_view.dart — Visão 3D da navegação (UauGo v2, só no Galaxy de teste)
//
// O que faz: Mostra a estrada da rota em 3D, em primeira pessoa, com o
//   "tapete" azul na faixa, setas nas conversões, placas nas saídas,
//   radares/lombadas/polícia/alertas na pista e o destino (página em
//   assets/sim3d/index.html, desenhada com three.js, sem internet). Só ruas,
//   sem prédios: leve e prático.
// Quem usa: MapScreen (navegação). Pinça para afastar na visão 3D volta ao
//   mapa de cima; zoom para perto no mapa volta para o 3D.
// Onde mexer: o desenho fica na página; aqui só a ponte com o app
//   (Sim3DController.route / update / dark / active).
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/i18n.dart';
import '../logic/navigation.dart';
import '../services/car_service.dart';

/// Ponte do app com a página 3D. Guarda o último estado e reenvia quando a
/// página termina de carregar.
class Sim3DController {
  WebViewController? _web;
  bool _ready = false;
  String? _routeJson;
  String? _lastUpdate;
  String? _alertsJson;
  String? _ridersJson;
  bool _dark = false;
  bool _active = true;
  bool _mini = true;

  /// Minimapa no canto (tocar nele esconde/mostra; escolha guardada).
  void mini(bool on) {
    _mini = on;
    if (_ready) _web?.runJavaScript('sim3d.setMini($on)').catchError((_) {});
  }

  /// O piloto tocou no minimapa: guardar a escolha.
  void Function(bool on)? onMini;
  bool _visible = true;

  /// A página já desenhou a estrada (true) ou está carregando/escondida.
  final shown = ValueNotifier<bool>(false);

  /// Montada e escondida (transparente e parada) ou aparecendo.
  void visible(bool on) {
    if (on == _visible) return;
    _visible = on;
    if (!on) shown.value = false;
    if (_ready) _web?.runJavaScript('sim3d.setVisible($on)').catchError((_) {});
  }

  /// Rota (lat, lng), manobras e nome do destino.
  /// [partialEnd]: o trecho termina antes do destino (rota longa): a página
  /// não põe o pin de chegada no fim.
  void route(List<(double, double)> pts, List<NavStep> steps, String dest,
      {bool partialEnd = false}) {
    _routeJson = jsonEncode({
      if (partialEnd) 'partial': true,
      'pts': [for (final p in pts) [p.$1, p.$2]],
      'steps': [
        for (final s in steps) {'la': s.lat, 'lo': s.lng, 'm': s.maneuver, 't': s.text}
      ],
      'dest': dest,
    });
    _run('sim3d.setRoute($_routeJson)');
    if (_alertsJson != null) _run('sim3d.setAlerts($_alertsJson)');
  }

  /// Radares, lombadas, polícia, pedágios, semáforos e alertas dos usuários
  /// perto do piloto: viram objetos na pista (veja setAlerts na página).
  void alerts(List<Map<String, Object?>> list) {
    final j = jsonEncode(list);
    if (j == _alertsJson) return;
    _alertsJson = j;
    _run('sim3d.setAlerts($j)');
  }

  /// Outros pilotos do comboio: [{id, n (nome), c (cor RGB), la, lo}].
  /// Viram uma moto com o nome na pista quando estão na rota, à frente.
  void riders(List<Map<String, Object?>> list) {
    final j = jsonEncode(list);
    if (j == _ridersJson) return;
    _ridersJson = j;
    _run('sim3d.setRiders($j)');
  }

  /// Posição na rota (metros desde o início), velocidade (m/s), se saiu
  /// da rota e a posição real do GPS com o rumo (graus): fora da rota a
  /// cena segue o GPS e desenha a rua por onde o piloto está passando.
  void update(double along, double speedMs, bool offRoute,
      {double? lat, double? lng, double? heading}) {
    final j = jsonEncode({
      'along': along, 'v': speedMs, 'off': offRoute,
      if (lat != null) 'la': lat,
      if (lng != null) 'lo': lng,
      if (heading != null) 'hd': heading,
    });
    if (j == _lastUpdate) return;
    _lastUpdate = j;
    _run('sim3d.update($j)');
  }

  /// Visão em primeira pessoa conforme o veículo (23/11): 'moto', 'car',
  /// 'truck' ou 'bus' (guidão, capô ou cabine na base da tela).
  void vehicle(String kind) {
    if (kind == _vehicle) return;
    _vehicle = kind;
    _run('sim3d.setVehicle("$kind")'); // celular e tela do carro
  }

  String? _vehicle;

  void dark(bool on) {
    if (on == _dark) return;
    _dark = on;
    _run('sim3d.setDark($on)');
  }

  /// Escondida: para de desenhar (economiza bateria).
  void active(bool on) {
    if (on == _active) return;
    _active = on;
    _run('sim3d.setActive($on)');
  }

  /// Painel do para-brisa: velocidade, limite (pisca acima dele), próxima
  /// manobra com a distância e a chegada.
  void hud(Map<String, Object?> d) {
    final j = jsonEncode(d);
    if (j == _hudJson) return;
    _hudJson = j;
    _run('sim3d.hud($j)');
  }

  String? _hudJson;
  String? _layoutJson;
  String? _roadsJson;
  String? _streetsJson;

  /// Todas as ruas em volta (MiniStreetsService), só para o minimapa.
  void streets(String json) {
    _streetsJson = json;
    _run('sim3d.setStreets($_streetsJson)');
  }

  /// Rodovias reais perto do piloto (ViasService.near): faixas e saídas.
  void roads(String json) {
    _roadsJson = json;
    _run('sim3d.setRoads($_roadsJson)');
  }

  /// Espaço livre para o painel (px a partir das bordas da visão 3D),
  /// medido pelo app em volta dos botões.
  void layout({required double left, required double right, required double bottom, double top = 0,
      Map<String, int>? car, double inset = 0}) {
    final j = jsonEncode({
      'l': left.round(), 'r': right.round(), 'b': bottom.round(), 't': top.round(),
      'ib': inset.round(),
      if (car != null) 'car': car,
    });
    if (j == _layoutJson) return;
    _layoutJson = j;
    _run('sim3d.layout($j)');
  }

  void _run(String js) {
    if (_ready) _web?.runJavaScript(js).catchError((_) {});
    // A tela do carro usa a mesma cena (com o espaço do painel dela).
    if (!js.startsWith('sim3d.layout') && !js.startsWith('sim3d.setActive')) {
      CarService.instance.sim3d(js);
    }
  }

  /// Carro conectou agora: manda o estado atual da cena para ele.
  void resendToCar() {
    final car = CarService.instance;
    car.sim3d('sim3d.setLang("${I18n.code}")');
    car.sim3d('sim3d.setDark($_dark)');
    if (_vehicle != null) car.sim3d('sim3d.setVehicle("$_vehicle")');
    if (_routeJson != null) car.sim3d('sim3d.setRoute($_routeJson)');
    if (_roadsJson != null) car.sim3d('sim3d.setRoads($_roadsJson)');
    if (_streetsJson != null) car.sim3d('sim3d.setStreets($_streetsJson)');
    if (_alertsJson != null) car.sim3d('sim3d.setAlerts($_alertsJson)');
    if (_ridersJson != null) car.sim3d('sim3d.setRiders($_ridersJson)');
    if (_lastUpdate != null) car.sim3d('sim3d.update($_lastUpdate)');
    if (_hudJson != null) car.sim3d('sim3d.hud($_hudJson)');
  }

  void _onReady() {
    _ready = true;
    // Idioma antes da rota e dos alertas (placas viram textura).
    _run('sim3d.setLang("${I18n.code}")');
    _run('sim3d.setDark($_dark)');
    if (_vehicle != null) {
      _web?.runJavaScript('sim3d.setVehicle("$_vehicle")').catchError((_) {});
    }
    if (_routeJson != null) _run('sim3d.setRoute($_routeJson)');
    if (_alertsJson != null) _run('sim3d.setAlerts($_alertsJson)');
    if (_ridersJson != null) _run('sim3d.setRiders($_ridersJson)');
    if (_lastUpdate != null) _run('sim3d.update($_lastUpdate)');
    if (_layoutJson != null) _run('sim3d.layout($_layoutJson)');
    if (_roadsJson != null) _run('sim3d.setRoads($_roadsJson)');
    if (_streetsJson != null) _run('sim3d.setStreets($_streetsJson)');
    if (_hudJson != null) _run('sim3d.hud($_hudJson)');
    _run('sim3d.setActive($_active)');
    _web?.runJavaScript('sim3d.setVisible($_visible)').catchError((_) {});
    _web?.runJavaScript('sim3d.setMini($_mini)').catchError((_) {});
  }
}

class Sim3DView extends StatefulWidget {
  const Sim3DView({super.key, required this.controller, required this.onBackToMap});

  final Sim3DController controller;

  /// Pinça para afastar: voltar ao mapa de cima.
  final VoidCallback onBackToMap;

  @override
  State<Sim3DView> createState() => _Sim3DViewState();
}

class _Sim3DViewState extends State<Sim3DView> with WidgetsBindingObserver {
  late WebViewController _web;
  int _gen = 0;

  /// Última mensagem da página (ela manda 'beat' a cada 2 s).
  DateTime _lastMsg = DateTime.now();
  bool _resumed = true;
  Timer? _watch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _create();
    // O Android mata o processo do WebView ao minimizar (log "Renderer
    // process crash detected"): a página fica morta, só a estrada escura,
    // sem a rota. Página calada com o app na tela = recria; o controle
    // reenvia rota, vias e alertas quando ela fica pronta (08/11).
    _watch = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_resumed) return;
      if (DateTime.now().difference(_lastMsg) > const Duration(seconds: 9)) {
        _recreate('parou de responder');
      }
    });
  }

  DateTime? _leftAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final was = _resumed;
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed && was) _leftAt = DateTime.now();
    if (_resumed && !was) {
      // De volta à tela depois de minimizar: o Android pode ter perdido o
      // desenho da página (contexto do WebGL; ela segue viva, mas mostra só
      // a estrada escura, sem a rota, teste de 08/11). Recarrega a página;
      // o controle reenvia rota, vias e alertas quando ela fica pronta.
      final away = _leftAt == null ? Duration.zero : DateTime.now().difference(_leftAt!);
      if (away > const Duration(seconds: 3)) {
        _recreate('voltou para a tela');
      } else {
        _lastMsg = DateTime.now();
      }
    }
  }

  void _recreate(String why) {
    if (!mounted) return;
    debugPrint('3D página recriada ($why)');
    widget.controller
      .._web = null
      .._ready = false
      ..shown.value = false;
    setState(() {
      _gen++;
      _create();
    });
  }

  void _create() {
    debugPrint('3D página criada');
    _lastMsg = DateTime.now().add(const Duration(seconds: 20)); // carregando
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Transparente até a estrada aparecer: enquanto a página carrega
      // (8 a 20 s num celular simples) o mapa continua visível por baixo, em
      // vez de uma tela vazia ou só o céu (bateria de testes em SP, 06/11).
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel('Sim3D', onMessageReceived: (m) {
        _lastMsg = DateTime.now();
        if (m.message == 'beat') return;
        if (m.message == 'ready') {
          debugPrint('3D página pronta');
          widget.controller._onReady();
        }
        if (m.message == 'map') widget.onBackToMap();
        if (m.message == 'shown') widget.controller.shown.value = true;
        if (m.message.startsWith('mini:')) {
          widget.controller._mini = m.message.endsWith('1');
          widget.controller.onMini?.call(widget.controller._mini);
        }
        if (m.message.startsWith('log:')) debugPrint('Sim3D ${m.message.substring(4)}');
      })
      ..loadFlutterAsset('assets/sim3d/index.html');
    widget.controller._web = _web;
  }

  @override
  void dispose() {
    _watch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller
      .._web = null
      .._ready = false
      ..shown.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WebViewWidget(key: ValueKey(_gen), controller: _web);
}
