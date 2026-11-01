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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
  bool _dark = false;
  bool _active = true;

  /// Rota (lat, lng), manobras e nome do destino.
  void route(List<(double, double)> pts, List<NavStep> steps, String dest) {
    _routeJson = jsonEncode({
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

  /// Rodovias reais perto do piloto (ViasService.near): faixas e saídas.
  void roads(String json) {
    _roadsJson = json;
    _run('sim3d.setRoads($_roadsJson)');
  }

  /// Espaço livre para o painel (px a partir das bordas da visão 3D),
  /// medido pelo app em volta dos botões.
  void layout({required double left, required double right, required double bottom}) {
    final j = jsonEncode({'l': left.round(), 'r': right.round(), 'b': bottom.round()});
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
    car.sim3d('sim3d.setDark($_dark)');
    if (_routeJson != null) car.sim3d('sim3d.setRoute($_routeJson)');
    if (_roadsJson != null) car.sim3d('sim3d.setRoads($_roadsJson)');
    if (_alertsJson != null) car.sim3d('sim3d.setAlerts($_alertsJson)');
    if (_lastUpdate != null) car.sim3d('sim3d.update($_lastUpdate)');
    if (_hudJson != null) car.sim3d('sim3d.hud($_hudJson)');
  }

  void _onReady() {
    _ready = true;
    _run('sim3d.setDark($_dark)');
    if (_routeJson != null) _run('sim3d.setRoute($_routeJson)');
    if (_alertsJson != null) _run('sim3d.setAlerts($_alertsJson)');
    if (_lastUpdate != null) _run('sim3d.update($_lastUpdate)');
    if (_layoutJson != null) _run('sim3d.layout($_layoutJson)');
    if (_roadsJson != null) _run('sim3d.setRoads($_roadsJson)');
    if (_hudJson != null) _run('sim3d.hud($_hudJson)');
    _run('sim3d.setActive($_active)');
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

class _Sim3DViewState extends State<Sim3DView> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFDBE7EE))
      ..addJavaScriptChannel('Sim3D', onMessageReceived: (m) {
        if (m.message == 'ready') widget.controller._onReady();
        if (m.message == 'map') widget.onBackToMap();
        if (m.message.startsWith('log:')) debugPrint('Sim3D ${m.message.substring(4)}');
      })
      ..loadFlutterAsset('assets/sim3d/index.html');
    widget.controller._web = _web;
  }

  @override
  void dispose() {
    widget.controller
      .._web = null
      .._ready = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
