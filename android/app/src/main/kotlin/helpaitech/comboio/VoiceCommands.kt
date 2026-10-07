// ============================================================================
// VoiceCommands.kt — Comandos de voz offline (acessibilidade, opcional)
//
// O que faz: Ouve o microfone com o Vosk (reconhecimento de voz no próprio
//   celular, sem internet, sem enviar áudio para lugar nenhum) restrito a uma
//   lista fechada de frases ("roda junto radar", "sim", "não"...). Cada frase
//   reconhecida vai para o Dart (VoiceCommandService) como JSON do Vosk.
// Quem usa: lib/services/voice_command_service.dart (canais "rodajunto/voice").
// Onde mexer: As frases aceitas são montadas no Dart (grammar).
// ============================================================================

package helpaitech.comboio

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

class VoiceCommands(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, RecognitionListener {

    companion object {
        const val MIC_REQUEST = 4711
        private const val SAMPLE_RATE = 16000f
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var model: Model? = null
    private var modelDir: String? = null
    private var service: SpeechService? = null
    private var micResult: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "rodajunto/voice").setMethodCallHandler(this)
        EventChannel(messenger, "rodajunto/voice/results").setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasMic" -> result.success(hasMic())
            "requestMic" -> requestMic(result)
            "unzip" -> worker.execute {
                try {
                    unzip(call.argument<String>("zip")!!, call.argument<String>("dir")!!)
                    main.post { result.success(true) }
                } catch (e: Exception) {
                    main.post { result.error("unzip", e.message, null) }
                }
            }
            "start" -> worker.execute {
                try {
                    start(call.argument<String>("modelDir")!!, call.argument<String>("grammar")!!)
                    main.post { result.success(true) }
                } catch (e: Exception) {
                    main.post { result.error("start", e.message, null) }
                }
            }
            "pause" -> {
                service?.setPause(call.argument<Boolean>("paused") ?: false)
                result.success(true)
            }
            "stop" -> {
                stop()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasMic() = ContextCompat.checkSelfPermission(
        activity, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun requestMic(result: MethodChannel.Result) {
        if (hasMic()) return result.success(true)
        micResult = result
        ActivityCompat.requestPermissions(
            activity, arrayOf(Manifest.permission.RECORD_AUDIO), MIC_REQUEST)
    }

    /** Resposta da janela de permissão (chamado pela MainActivity). */
    fun onMicPermission(granted: Boolean) {
        micResult?.success(granted)
        micResult = null
    }

    /** Descompacta o modelo baixado (zip do Vosk) na pasta do app. */
    private fun unzip(zipPath: String, destDir: String) {
        val dest = File(destDir).canonicalFile
        dest.mkdirs()
        ZipInputStream(File(zipPath).inputStream().buffered()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val out = File(dest, entry.name).canonicalFile
                // Proteção: nenhum arquivo do zip pode sair da pasta de destino.
                require(out.path.startsWith(dest.path + File.separator)) { "zip inválido" }
                if (entry.isDirectory) {
                    out.mkdirs()
                } else {
                    out.parentFile?.mkdirs()
                    FileOutputStream(out).use { zip.copyTo(it) }
                }
                entry = zip.nextEntry
            }
        }
    }

    /** Carrega o modelo (uma vez) e começa a ouvir só as frases da [grammar]. */
    private fun start(dir: String, grammar: String) {
        stop()
        if (model == null || modelDir != dir) {
            model?.close()
            model = Model(dir)
            modelDir = dir
        }
        val rec = Recognizer(model, SAMPLE_RATE, grammar)
        rec.setWords(true)
        service = SpeechService(rec, SAMPLE_RATE).also { it.startListening(this) }
    }

    private fun stop() {
        service?.stop()
        service?.shutdown()
        service = null
    }

    fun shutdown() {
        stop()
        model?.close()
        model = null
    }

    // ---- RecognitionListener (já roda na thread principal)
    override fun onResult(hypothesis: String) { events?.success(hypothesis) }
    override fun onFinalResult(hypothesis: String) { events?.success(hypothesis) }
    override fun onPartialResult(hypothesis: String) {}
    override fun onError(e: Exception) { events?.error("voice", e.message, null) }
    override fun onTimeout() {}

    // ---- EventChannel
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
    override fun onCancel(arguments: Any?) { events = null }
}
