import CarPlay
import CoreLocation
import Flutter
import GoogleMaps
import MapKit
import UIKit

class SceneDelegate: FlutterSceneDelegate {

}

// MARK: - Ponte com o Flutter (mesmo canal "uaugo/car" do Android Auto)

/// 24/11: o app manda para cá o mesmo estado que manda ao Android Auto
/// (lib/services/car_service.dart). Aqui ele vai para a tela do CarPlay.
final class CarBridgeIOS {
  static let shared = CarBridgeIOS()

  private var channel: FlutterMethodChannel?
  weak var carPlay: CarPlaySceneDelegate?
  private(set) var connected = false
  private(set) var last: [String: Any] = [:]
  private(set) var route: [CLLocationCoordinate2D] = []

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "uaugo/car", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    channel = ch
  }

  private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
    switch call.method {
    case "connected":
      result(connected)
    case "update":
      if let m = call.arguments as? [String: Any] {
        last = m
        carPlay?.apply(m)
      }
      result(nil)
    case "route":
      route = Self.coords(call.arguments)
      carPlay?.applyRoute(route)
      result(nil)
    case "clear":
      route = []
      last = [:]
      carPlay?.applyRoute([])
      carPlay?.endNav()
      result(nil)
    case "clearNav":
      carPlay?.endNav()
      result(nil)
    case "toast":
      if let t = call.arguments as? String { carPlay?.toast(t) }
      result(nil)
    default:
      // Coisas só do Android Auto (3D, busca no carro, pins...): ignora.
      result(nil)
    }
  }

  static func coords(_ a: Any?) -> [CLLocationCoordinate2D] {
    var v: [Double] = []
    if let d = a as? [Double] {
      v = d
    } else if let n = a as? [NSNumber] {
      v = n.map { $0.doubleValue }
    } else if let t = a as? FlutterStandardTypedData {
      v = t.data.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
    }
    var out: [CLLocationCoordinate2D] = []
    var i = 0
    while i + 1 < v.count {
      out.append(CLLocationCoordinate2D(latitude: v[i], longitude: v[i + 1]))
      i += 2
    }
    return out
  }

  func setConnected(_ on: Bool) {
    connected = on
    channel?.invokeMethod("connected", arguments: on)
  }

  func action(_ a: String) {
    channel?.invokeMethod("action", arguments: a)
  }
}

// MARK: - Tela do CarPlay

/// Cena do CarPlay: mapa do Google com a rota e o veículo, manobras no
/// cartão do próprio CarPlay e botões de alerta e radar.
/// Só aparece no carro depois que a Apple liberar o recurso de navegação
/// (com.apple.developer.carplay-maps) para o UauGo.
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPMapTemplateDelegate {
  private var ic: CPInterfaceController?
  private var carWindow: CPWindow?
  private let mapVC = CarPlayMapViewController()
  private let mapTemplate = CPMapTemplate()
  private var session: CPNavigationSession?
  private var trip: CPTrip?
  private var maneuver: CPManeuver?
  private var maneuverKey = ""

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController,
    to window: CPWindow
  ) {
    ic = interfaceController
    carWindow = window
    window.rootViewController = mapVC
    mapTemplate.mapDelegate = self
    setupButtons()
    interfaceController.setRootTemplate(mapTemplate, animated: false, completion: nil)
    let b = CarBridgeIOS.shared
    b.carPlay = self
    b.setConnected(true)
    applyRoute(b.route)
    if !b.last.isEmpty { apply(b.last) }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController,
    from window: CPWindow
  ) {
    endNav()
    CarBridgeIOS.shared.carPlay = nil
    CarBridgeIOS.shared.setConnected(false)
    ic = nil
    carWindow = nil
  }

  private func tx(_ en: String, _ pt: String, _ es: String) -> String {
    switch CarBridgeIOS.shared.last["lang"] as? String {
    case "en": return en
    case "es": return es
    default: return pt
    }
  }

  private func setupButtons() {
    let alert = CPBarButton(title: tx("Alert", "Alerta", "Alerta")) { [weak self] _ in
      self?.showAlerts()
    }
    let radar = CPBarButton(title: tx("Radar", "Radar", "Radar")) { _ in
      CarBridgeIOS.shared.action("radar")
    }
    mapTemplate.leadingNavigationBarButtons = [alert]
    mapTemplate.trailingNavigationBarButtons = [radar]
    let zoomIn = CPMapButton { [weak self] _ in self?.mapVC.zoom(by: 1) }
    zoomIn.image = UIImage(systemName: "plus.magnifyingglass")
    let zoomOut = CPMapButton { [weak self] _ in self?.mapVC.zoom(by: -1) }
    zoomOut.image = UIImage(systemName: "minus.magnifyingglass")
    mapTemplate.mapButtons = [zoomIn, zoomOut]
  }

  /// Lista de alertas (mesmos nomes do app: hazard:police...).
  private func showAlerts() {
    let types: [(String, String)] = [
      ("police", tx("Police", "Polícia", "Policía")),
      ("radar", tx("Mobile speed camera", "Radar móvel", "Radar móvil")),
      ("oil", tx("Oil / sand", "Óleo / areia", "Aceite / arena")),
      ("animal", tx("Animal on road", "Animal na pista", "Animal en la vía")),
      ("kite", tx("Kites", "Pipas / cerol", "Cometas")),
      ("pothole", tx("Pothole", "Buraco", "Bache")),
      ("danger", tx("Road hazard", "Risco na pista", "Peligro en la vía")),
      ("accident", tx("Accident", "Acidente", "Accidente")),
      ("risk", tx("Risk area", "Área de risco", "Zona de riesgo")),
    ]
    let items: [CPListItem] = types.map { (name, label) in
      let it = CPListItem(text: label, detailText: nil)
      it.handler = { [weak self] _, done in
        CarBridgeIOS.shared.action("hazard:\(name)")
        self?.ic?.popTemplate(animated: true, completion: nil)
        done()
      }
      return it
    }
    let list = CPListTemplate(title: tx("Alert", "Alerta", "Alerta"),
                              sections: [CPListSection(items: items)])
    ic?.pushTemplate(list, animated: true, completion: nil)
  }

  func toast(_ text: String) {
    let ok = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
      self?.mapTemplate.dismissNavigationAlert(animated: true, completion: { _ in })
    }
    let a = CPNavigationAlert(titleVariants: [text], subtitleVariants: [], image: nil,
                              primaryAction: ok, secondaryAction: nil, duration: 4)
    mapTemplate.present(navigationAlert: a, animated: true)
  }

  func applyRoute(_ pts: [CLLocationCoordinate2D]) {
    mapVC.setRoute(pts)
  }

  /// Estado vindo do celular (no máximo 1 vez por segundo).
  func apply(_ m: [String: Any]) {
    let lat = (m["lat"] as? NSNumber)?.doubleValue ?? 0
    let lng = (m["lng"] as? NSNumber)?.doubleValue ?? 0
    let bearing = (m["bearing"] as? NSNumber)?.doubleValue ?? 0
    mapVC.setVehicle(CLLocationCoordinate2D(latitude: lat, longitude: lng), bearing: bearing)
    mapVC.setSpeed((m["speedKmh"] as? NSNumber)?.intValue ?? 0,
                   limit: (m["limitKmh"] as? NSNumber)?.intValue ?? 0)
    mapVC.setBanner(m["banner"] as? String, alert: m["alert"] as? String)
    // Mesmas regras do celular: velocímetro vermelho acima do limite e faixa
    // do radar piscando acima do limite dele (calculado no app).
    mapVC.setOver(speed: m["speedOver"] as? Bool ?? false, radar: m["radarOver"] as? Bool ?? false)
    mapVC.setHint(nil)

    guard let text = m["text"] as? String, !text.isEmpty else {
      endNav()
      return
    }
    let meters = (m["meters"] as? NSNumber)?.doubleValue ?? 0
    let remaining = (m["remainingM"] as? NSNumber)?.doubleValue ?? 0
    let etaMs = (m["eta"] as? NSNumber)?.doubleValue ?? 0
    let left = etaMs > 0 ? max(0, etaMs / 1000 - Date().timeIntervalSince1970) : 0
    let kind = m["maneuver"] as? String ?? ""

    if session == nil {
      let here = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)))
      let end = CarBridgeIOS.shared.route.last ?? CLLocationCoordinate2D(latitude: lat, longitude: lng)
      let dest = MKMapItem(placemark: MKPlacemark(coordinate: end))
      let choice = CPRouteChoice(summaryVariants: ["UauGo"], additionalInformationVariants: [],
                                 selectionSummaryVariants: [])
      let t = CPTrip(origin: here, destination: dest, routeChoices: [choice])
      trip = t
      session = mapTemplate.startNavigationSession(for: t)
      maneuverKey = ""
    }
    guard let s = session, let t = trip else { return }

    let est = CPTravelEstimates(distanceRemaining: Measurement(value: meters, unit: UnitLength.meters),
                                timeRemaining: 0)
    if text + kind != maneuverKey {
      maneuverKey = text + kind
      let mv = CPManeuver()
      mv.instructionVariants = [text]
      mv.symbolImage = Self.symbol(kind)
      mv.initialTravelEstimates = est
      maneuver = mv
      s.upcomingManeuvers = [mv]
    } else if let mv = maneuver {
      s.updateEstimates(est, for: mv)
    }
    mapTemplate.updateEstimates(
      CPTravelEstimates(distanceRemaining: Measurement(value: remaining, unit: UnitLength.meters),
                        timeRemaining: left),
      for: t)
  }

  func endNav() {
    session?.finishTrip()
    session = nil
    trip = nil
    maneuver = nil
    maneuverKey = ""
  }

  /// Seta da manobra (tipos do Google Directions, como no Android Auto).
  static func symbol(_ m: String) -> UIImage? {
    let name: String
    if m.hasPrefix("uturn") {
      name = m.contains("right") ? "arrow.uturn.right" : "arrow.uturn.left"
    } else if m.hasPrefix("roundabout") {
      name = "arrow.triangle.turn.up.right.circle"
    } else if m == "turn-slight-left" || m == "ramp-left" || m == "keep-left" || m == "fork-left" {
      name = "arrow.up.left"
    } else if m == "turn-slight-right" || m == "ramp-right" || m == "keep-right" || m == "fork-right" {
      name = "arrow.up.right"
    } else if m.contains("left") {
      name = "arrow.turn.up.left"
    } else if m.contains("right") {
      name = "arrow.turn.up.right"
    } else {
      name = "arrow.up"
    }
    let cfg = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
    return UIImage(systemName: name, withConfiguration: cfg)
  }
}

// MARK: - Mapa da tela do CarPlay

final class CarPlayMapViewController: UIViewController {
  private var map: GMSMapView!
  private let line = GMSPolyline()
  private let me = GMSMarker()
  private var zoom: Float = 17
  private var lastPos: CLLocationCoordinate2D?
  private var lastBearing: Double = 0
  private let speedBox = UIView()
  private let speedLabel = UILabel()
  private let limitLabel = UILabel()
  private let bannerLabel = PaddedLabel()
  private let hintLabel = PaddedLabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    let opts = GMSMapViewOptions()
    opts.camera = GMSCameraPosition(latitude: -15.78, longitude: -47.93, zoom: 4)
    map = GMSMapView(options: opts)
    map.settings.setAllGesturesEnabled(false)
    map.isBuildingsEnabled = false
    map.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(map)
    NSLayoutConstraint.activate([
      map.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      map.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      map.topAnchor.constraint(equalTo: view.topAnchor),
      map.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    line.strokeWidth = 8
    line.strokeColor = UIColor(red: 0.12, green: 0.53, blue: 0.9, alpha: 1)
    line.map = map

    let cfg = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)
    me.icon = UIImage(systemName: "location.north.fill", withConfiguration: cfg)?
      .withTintColor(UIColor(red: 1, green: 0.48, blue: 0.1, alpha: 1), renderingMode: .alwaysOriginal)
    me.isFlat = true
    me.groundAnchor = CGPoint(x: 0.5, y: 0.5)

    // Velocímetro e limite no canto de baixo à esquerda.
    speedBox.translatesAutoresizingMaskIntoConstraints = false
    speedBox.backgroundColor = UIColor(red: 0.06, green: 0.11, blue: 0.18, alpha: 0.92)
    speedBox.layer.cornerRadius = 14
    view.addSubview(speedBox)
    speedLabel.translatesAutoresizingMaskIntoConstraints = false
    speedLabel.textColor = .white
    speedLabel.font = .systemFont(ofSize: 22, weight: .heavy)
    speedLabel.textAlignment = .center
    speedLabel.numberOfLines = 2
    speedBox.addSubview(speedLabel)
    limitLabel.translatesAutoresizingMaskIntoConstraints = false
    limitLabel.textColor = .black
    limitLabel.backgroundColor = .white
    limitLabel.font = .systemFont(ofSize: 18, weight: .heavy)
    limitLabel.textAlignment = .center
    limitLabel.layer.cornerRadius = 22
    limitLabel.layer.borderWidth = 4
    limitLabel.layer.borderColor = UIColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1).cgColor
    limitLabel.clipsToBounds = true
    limitLabel.isHidden = true
    view.addSubview(limitLabel)

    for l in [bannerLabel, hintLabel] {
      l.translatesAutoresizingMaskIntoConstraints = false
      l.font = .systemFont(ofSize: 16, weight: .bold)
      l.numberOfLines = 2
      l.layer.cornerRadius = 10
      l.clipsToBounds = true
      l.isHidden = true
      view.addSubview(l)
    }
    bannerLabel.backgroundColor = UIColor(red: 1, green: 0.84, blue: 0.0, alpha: 0.95)
    bannerLabel.textColor = .black
    hintLabel.backgroundColor = UIColor(red: 0.06, green: 0.11, blue: 0.18, alpha: 0.92)
    hintLabel.textColor = .white

    let g = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      speedBox.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 10),
      speedBox.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -10),
      speedBox.widthAnchor.constraint(equalToConstant: 76),
      speedBox.heightAnchor.constraint(equalToConstant: 64),
      speedLabel.centerXAnchor.constraint(equalTo: speedBox.centerXAnchor),
      speedLabel.centerYAnchor.constraint(equalTo: speedBox.centerYAnchor),
      limitLabel.leadingAnchor.constraint(equalTo: speedBox.trailingAnchor, constant: 6),
      limitLabel.bottomAnchor.constraint(equalTo: speedBox.bottomAnchor),
      limitLabel.widthAnchor.constraint(equalToConstant: 44),
      limitLabel.heightAnchor.constraint(equalToConstant: 44),
      bannerLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 10),
      bannerLabel.trailingAnchor.constraint(lessThanOrEqualTo: g.trailingAnchor, constant: -10),
      bannerLabel.bottomAnchor.constraint(equalTo: speedBox.topAnchor, constant: -8),
      hintLabel.centerXAnchor.constraint(equalTo: g.centerXAnchor),
      hintLabel.centerYAnchor.constraint(equalTo: g.centerYAnchor),
      hintLabel.widthAnchor.constraint(lessThanOrEqualTo: g.widthAnchor, constant: -40),
    ])
    setHint("Abra o UauGo no iPhone")
    applyStyle()
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    applyStyle()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // O cartão das manobras do CarPlay fica por cima: o veículo vai para
    // a área livre (safe area).
    map?.padding = view.safeAreaInsets
  }

  /// Noite: mapa escuro (como no Android Auto).
  private func applyStyle() {
    guard let map = map else { return }
    if traitCollection.userInterfaceStyle == .dark {
      map.mapStyle = try? GMSMapStyle(jsonString: Self.night)
    } else {
      map.mapStyle = nil
    }
  }

  func setRoute(_ pts: [CLLocationCoordinate2D]) {
    let p = GMSMutablePath()
    for c in pts { p.add(c) }
    line.path = p
  }

  func setVehicle(_ c: CLLocationCoordinate2D, bearing: Double) {
    guard map != nil, c.latitude != 0 || c.longitude != 0 else { return }
    lastPos = c
    lastBearing = bearing
    me.position = c
    me.map = map
    move()
  }

  func zoom(by d: Float) {
    zoom = min(20, max(12, zoom + d))
    move()
  }

  private func move() {
    guard let c = lastPos, let map = map else { return }
    let cam = GMSCameraPosition(target: c, zoom: zoom, bearing: lastBearing, viewingAngle: 45)
    map.animate(to: cam)
  }

  func setSpeed(_ kmh: Int, limit: Int) {
    speedLabel.text = "\(kmh)\nkm/h"
    limitLabel.isHidden = limit <= 0
    limitLabel.text = "\(limit)"
  }

  func setBanner(_ banner: String?, alert: String?) {
    let t = [alert, banner].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    bannerLabel.text = t
    bannerLabel.isHidden = t.isEmpty
  }

  private var blink: Timer?
  private var blinkRed = false

  func setOver(speed: Bool, radar: Bool) {
    speedBox.backgroundColor = speed
      ? UIColor(red: 0.83, green: 0.18, blue: 0.18, alpha: 1)
      : UIColor(red: 0.06, green: 0.11, blue: 0.18, alpha: 0.92)
    if radar, blink == nil {
      blink = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        self.blinkRed.toggle()
        self.paintBanner()
      }
    } else if !radar, let t = blink {
      t.invalidate()
      blink = nil
      blinkRed = false
      paintBanner()
    }
  }

  private func paintBanner() {
    bannerLabel.backgroundColor = blinkRed
      ? UIColor(red: 0.9, green: 0.22, blue: 0.21, alpha: 1)
      : UIColor(red: 1, green: 0.84, blue: 0.0, alpha: 0.95)
    bannerLabel.textColor = blinkRed ? .white : .black
  }

  func setHint(_ t: String?) {
    hintLabel.text = t
    hintLabel.isHidden = t == nil
  }

  private static let night = """
  [{"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]}]
  """
}

/// Rótulo com folga interna.
final class PaddedLabel: UILabel {
  override func drawText(in rect: CGRect) {
    super.drawText(in: rect.inset(by: UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)))
  }

  override var intrinsicContentSize: CGSize {
    let s = super.intrinsicContentSize
    return CGSize(width: s.width + 20, height: s.height + 12)
  }
}

// MARK: - Voz (alerta falado e frase livre) no iPhone

import AVFoundation
import Speech

/// 24/11: no Android o canal "rodajunto/voice" usa o Vosk + reconhecedor do
/// Google. No iPhone, o reconhecimento de fala da Apple faz a escuta de uma
/// frase (alerta falado, destino, "o que você procura?"). O "UauGo" ouvindo
/// o tempo todo continua só no Android.
final class VoiceBridgeIOS {
  static let shared = VoiceBridgeIOS()

  private var channel: FlutterMethodChannel?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var pending: FlutterResult?
  private var best = ""
  private var silence: Timer?
  private var maxTimer: Timer?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "rodajunto/voice", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    channel = ch
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "requestMic":
      requestPermissions { result($0) }
    case "hasMic":
      result(AVAudioSession.sharedInstance().recordPermission == .granted
        && SFSpeechRecognizer.authorizationStatus() == .authorized)
    case "listenDestination":
      let a = call.arguments as? [String: Any]
      listen(lang: a?["language"] as? String ?? "pt-BR",
             helmet: a?["helmet"] as? Bool ?? false, result: result)
    case "cancelDestination":
      finish(nil)
      result(nil)
    case "beep":
      AudioServicesPlaySystemSound(1113)
      result(nil)
    default:
      // start/stop/pause/unzip: escuta contínua (Vosk), só no Android.
      result(nil)
    }
  }

  /// Pede o microfone e o reconhecimento de fala (o iPhone pergunta 1 vez;
  /// depois o UauGo aparece em Ajustes > Privacidade > Microfone).
  private func requestPermissions(_ done: @escaping (Bool) -> Void) {
    AVAudioSession.sharedInstance().requestRecordPermission { ok in
      guard ok else {
        DispatchQueue.main.async { done(false) }
        return
      }
      SFSpeechRecognizer.requestAuthorization { st in
        DispatchQueue.main.async { done(st == .authorized) }
      }
    }
  }

  private func listen(lang: String, helmet: Bool, result: @escaping FlutterResult) {
    finish(nil)
    guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang)), rec.isAvailable else {
      result(nil)
      return
    }
    let s = AVAudioSession.sharedInstance()
    do {
      // Com o comunicador do capacete: microfone Bluetooth.
      var opts: AVAudioSession.CategoryOptions = [.duckOthers, .defaultToSpeaker]
      if helmet { opts.insert(.allowBluetooth) }
      try s.setCategory(.playAndRecord, mode: .measurement, options: opts)
      try s.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      result(nil)
      return
    }
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    request = req
    pending = result
    best = ""
    let input = engine.inputNode
    let fmt = input.outputFormat(forBus: 0)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
      req.append(buf)
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      finish(nil)
      return
    }
    channel?.invokeMethod("destListening", arguments: true)
    task = rec.recognitionTask(with: req) { [weak self] r, err in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if let r = r {
          self.best = r.bestTranscription.formattedString
          self.channel?.invokeMethod("destPartial", arguments: self.best)
          self.armSilence()
          if r.isFinal { self.finish(self.best) }
        } else if err != nil {
          self.finish(self.best.isEmpty ? nil : self.best)
        }
      }
    }
    // No máximo 8 s de escuta (como no Android).
    maxTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.finish(self.best.isEmpty ? nil : self.best)
    }
  }

  /// Parou de falar por 1,5 s: entrega o que ouviu.
  private func armSilence() {
    silence?.invalidate()
    silence = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      self.finish(self.best.isEmpty ? nil : self.best)
    }
  }

  private func finish(_ text: String?) {
    silence?.invalidate()
    silence = nil
    maxTimer?.invalidate()
    maxTimer = nil
    if engine.isRunning { engine.stop() }
    engine.inputNode.removeTap(onBus: 0)
    request?.endAudio()
    request = nil
    task?.cancel()
    task = nil
    if let p = pending {
      pending = nil
      p(text)
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
}
