import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Aqui (e não só quando o Flutter sobe): a tela do CarPlay também usa
    // o mapa do Google e pode abrir antes.
    GMSServices.provideAPIKey("AIzaSyCEQTDa31je6_x6S0u00q96jmEGsi4OxJ0")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Canal do modo carro (o mesmo do Android Auto): leva a navegação ao CarPlay.
    if let reg = engineBridge.pluginRegistry.registrar(forPlugin: "UauGoCar") {
      CarBridgeIOS.shared.attach(reg.messenger())
    }
  }
}
