// ============================================================================
// VoiceCommands.kt — Comandos de voz offline (acessibilidade, opcional)
//
// O que faz: Ouve o microfone com o Vosk (reconhecimento de voz no próprio
//   celular, sem internet, sem enviar áudio para lugar nenhum) restrito a uma
//   lista fechada de frases ("roda junto radar", "sim", "não"...). Cada frase
//   reconhecida vai para o Dart (VoiceCommandService) como JSON do Vosk.
//   "UauGo, ir para": em seguida ouve o destino (frase livre) com o
//   reconhecimento do próprio Android, sem abrir outra tela — no aparelho
//   quando ele oferece (sem internet), senão o do Google (internet).
// Quem usa: lib/services/voice_command_service.dart (canais "rodajunto/voice").
// Onde mexer: As frases aceitas são montadas no Dart (grammar).
// ============================================================================

package helpaitech.comboio

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
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
    private val channel = MethodChannel(messenger, "rodajunto/voice")
    private var dest: SpeechRecognizer? = null
    private var destResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
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
            "listenDestination" -> listenDestination(
                call.argument<String>("language") ?: "pt-BR", result)
            "cancelDestination" -> {
                finishDestination(null)
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
        finishDestination(null)
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

    // ---- "UauGo, ir para": o destino (frase livre)

    /**
     * Ouve o destino com o SpeechRecognizer do Android, dentro do app (sem
     * abrir a janela do Google): no próprio aparelho quando há (rápido, sem
     * internet, o áudio não sai do celular); se não houver ou faltar o
     * português, usa o do Google (internet). Bipe ao começar; o texto parcial
     * vai para o Dart ("destPartial") e o final volta em [result].
     */
    private fun listenDestination(language: String, result: MethodChannel.Result) {
        destResult?.success(null)
        destResult = result
        val onDevice = Build.VERSION.SDK_INT >= 31 &&
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        startDestination(language, onDevice)
    }

    private fun startDestination(language: String, onDevice: Boolean) {
        dest?.destroy()
        dest = null
        if (!onDevice && !SpeechRecognizer.isRecognitionAvailable(activity)) {
            finishDestination(null)
            return
        }
        val r = if (onDevice && Build.VERSION.SDK_INT >= 31) {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        } else {
            SpeechRecognizer.createSpeechRecognizer(activity)
        }
        dest = r
        r.setRecognitionListener(object : android.speech.RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                beep()
                channel.invokeMethod("destListening", if (onDevice) "device" else "cloud")
            }
            override fun onPartialResults(b: Bundle?) {
                first(b)?.let { channel.invokeMethod("destPartial", it) }
            }
            override fun onResults(b: Bundle?) = finishDestination(first(b))
            override fun onError(error: Int) {
                // Sem fala ou sem entender: termina. Outro erro no aparelho
                // (ex.: português não baixado): tenta o do Google uma vez.
                val noSpeech = error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                    error == SpeechRecognizer.ERROR_NO_MATCH
                if (onDevice && !noSpeech) startDestination(language, false)
                else finishDestination(null)
            }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        r.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
        })
    }

    private fun first(b: Bundle?): String? =
        b?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            ?.takeIf { it.isNotBlank() }

    private fun finishDestination(text: String?) {
        dest?.destroy()
        dest = null
        destResult?.success(text)
        destResult = null
    }

    /** Bipe curto: "pode falar o destino". */
    private fun beep() {
        try {
            val tone = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 150)
            main.postDelayed({ tone.release() }, 400)
        } catch (_: Exception) {}
    }
}
