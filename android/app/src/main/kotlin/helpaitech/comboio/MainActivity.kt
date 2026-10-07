package helpaitech.comboio

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Comandos de voz offline (Configurações → Acessibilidade). VoiceCommands.kt
    private var voice: VoiceCommands? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voice = VoiceCommands(this, flutterEngine.dartExecutor.binaryMessenger)
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
