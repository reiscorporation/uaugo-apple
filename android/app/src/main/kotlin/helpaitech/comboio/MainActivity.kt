package helpaitech.comboio

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Comandos de voz offline (Configurações → Acessibilidade). VoiceCommands.kt
    private var voice: VoiceCommands? = null
    // Endereço recebido de outro app (WhatsApp, Google Maps...). SharedPlace.kt
    private var shared: SharedPlace? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voice = VoiceCommands(this, flutterEngine.dartExecutor.binaryMessenger)
        shared = SharedPlace(flutterEngine.dartExecutor.binaryMessenger)
        // Modo carro (Android Auto): estado da navegação para a tela do carro.
        CarBridge(flutterEngine.dartExecutor.binaryMessenger)
        // Memória do aparelho (modo leve automático em celulares mais simples).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uaugo/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "totalMemMb") {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val mi = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(mi)
                    result.success((mi.totalMem / (1024 * 1024)).toInt())
                } else {
                    result.notImplemented()
                }
            }
        shared?.handle(intent, initial = true)
    }

    // App já aberto (launchMode singleTop): o endereço chega por aqui.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shared?.handle(intent, initial = false)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == VoiceCommands.MIC_REQUEST) {
            voice?.onMicPermission(grantResults.isNotEmpty() && grantResults[0] == 0)
        }
    }

    override fun onDestroy() {
        voice?.shutdown()
        super.onDestroy()
    }
}
