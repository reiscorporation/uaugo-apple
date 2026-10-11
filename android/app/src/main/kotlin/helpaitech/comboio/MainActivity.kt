package helpaitech.comboio

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Comandos de voz offline (Configurações → Acessibilidade). VoiceCommands.kt
    private var voice: VoiceCommands? = null
    // Endereço recebido de outro app (WhatsApp, Google Maps...). SharedPlace.kt
    private var shared: SharedPlace? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voice = VoiceCommands(this, flutterEngine.dartExecutor.binaryMessenger)
        shared = SharedPlace(flutterEngine.dartExecutor.binaryMessenger)
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
