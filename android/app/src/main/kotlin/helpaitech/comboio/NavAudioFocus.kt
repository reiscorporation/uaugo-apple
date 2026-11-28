package helpaitech.comboio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build

/**
 * Foco de áudio da voz do GPS (28/11, exigência do Android Auto na Play).
 * O flutter_tts pedia o foco sem os atributos (saía como mídia) enquanto a
 * fala tocava no canal de navegação. Aqui o pedido usa o mesmo canal:
 * USAGE_ASSISTANCE_NAVIGATION_GUIDANCE + AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
 * (abaixa a música durante a frase e devolve no fim).
 */
object NavAudioFocus {
    private var req: AudioFocusRequest? = null

    private val attrs: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    fun request(ctx: Context) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val r = req ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener { }
                .build().also { req = it }
            am.requestAudioFocus(r)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }

    fun abandon(ctx: Context) {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            req?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(null)
        }
    }
}
