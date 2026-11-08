package helpaitech.comboio

import android.app.ActivityManager
import android.content.Context
import android.provider.CalendarContract
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // App que o carro já ligou (UauGoEngine): a tela usa o mesmo, sem reiniciar.
    override fun provideFlutterEngine(context: Context): FlutterEngine? = UauGoEngine.cached()

    override fun shouldDestroyEngineWithHost(): Boolean = UauGoEngine.cached() == null

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
        // Controles da música que está tocando (mini player no mapa).
        MediaBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // Memória do aparelho (modo leve automático em celulares mais simples).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uaugo/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "totalMemMb") {
                    val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                    val mi = ActivityManager.MemoryInfo()
                    am.getMemoryInfo(mi)
                    result.success((mi.totalMem / (1024 * 1024)).toInt())
                } else if (call.method == "minimize") {
                    // "Minimizar": o app vai para trás e a rota continua.
                    moveTaskToBack(true)
                    result.success(null)
                } else if (call.method == "addToCalendar") {
                    // Abre o app de agenda já preenchido: quem salva é a
                    // agenda (o UauGo não pede permissão nem lê a agenda).
                    val i = Intent(Intent.ACTION_INSERT)
                        .setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.Events.TITLE, call.argument<String>("title"))
                        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, call.argument<Number>("begin")?.toLong())
                        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, call.argument<Number>("end")?.toLong())
                        .putExtra(CalendarContract.Events.EVENT_LOCATION, call.argument<String>("location"))
                        .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
                        .putExtra(CalendarContract.Events.HAS_ALARM, 1)
                    try {
                        startActivity(i)
                        result.success(true)
                    } catch (e: android.content.ActivityNotFoundException) {
                        result.success(false)
                    }
                } else if (call.method == "openTtsSettings") {
                    // Voz: tela do Android para baixar vozes do Google/Samsung.
                    // Primeiro a do mecanismo ("Instalar dados de voz"); se não
                    // houver, a de Conversão de texto em voz.
                    val tries = listOf(
                        Intent("android.speech.tts.engine.INSTALL_TTS_DATA"),
                        Intent("com.android.settings.TTS_SETTINGS"),
                    )
                    var ok = false
                    for (i in tries) {
                        try {
                            startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); ok = true; break
                        } catch (_: Exception) {}
                    }
                    result.success(ok)
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
        // App fechado (sem o motor do carro): o carro liga outro quando precisar.
        if (UauGoEngine.cached() == null) {
            CarState.actionSink = null
            CarState.dartReady = false
        }
        super.onDestroy()
    }
}
