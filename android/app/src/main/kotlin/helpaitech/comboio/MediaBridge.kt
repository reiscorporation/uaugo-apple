// ============================================================================
// MediaBridge.kt — Controles da música que está tocando (Spotify e outros)
//
// O que faz: Lê a sessão de mídia ativa do Android (Spotify, YouTube Music,
//   Deezer, rádio...) e manda para o app: título, artista, capa e se está
//   tocando; recebe os comandos anterior / tocar-pausar / próxima. Só
//   funciona depois que o usuário libera "Acesso a notificações" para o
//   UauGo (exigência do Android para ver o que outros apps tocam). Nada sai
//   do celular.
// Quem usa: MainActivity (canal "uaugo/media") → lib/services/media_service.dart.
// Onde mexer: MediaListenerService (o serviço que o Android exige).
// ============================================================================

package helpaitech.comboio

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/** Serviço vazio: o Android só entrega as sessões de mídia a quem tem um. */
class MediaListenerService : NotificationListenerService()

class MediaBridge(private val ctx: Context, messenger: BinaryMessenger) {
    private val ch = MethodChannel(messenger, "uaugo/media")
    private val main = Handler(Looper.getMainLooper())
    private val component = ComponentName(ctx, MediaListenerService::class.java)
    private val msm = ctx.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
    private var controller: MediaController? = null
    private var listening = false
    private var lastArtKey = ""
    private var lastIconPkg = ""

    private val sessionsListener = MediaSessionManager.OnActiveSessionsChangedListener { list ->
        attach(list?.firstOrNull())
    }

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = push()
        override fun onPlaybackStateChanged(state: PlaybackState?) = push()
        override fun onSessionDestroyed() = attach(null)
    }

    init {
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasAccess())
                "openSettings" -> {
                    ctx.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "openMusicApp" -> {
                    // Abre o app de música do celular (o Android pergunta qual,
                    // se houver mais de um).
                    try {
                        ctx.startActivity(Intent.makeMainSelectorActivity(
                            Intent.ACTION_MAIN, Intent.CATEGORY_APP_MUSIC)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "start" -> { start(); result.success(null) }
                "stop" -> { stop(); result.success(null) }
                "command" -> {
                    val t = controller?.transportControls
                    when (call.arguments as? String) {
                        "previous" -> t?.skipToPrevious()
                        "next" -> t?.skipToNext()
                        "toggle" -> {
                            val playing = controller?.playbackState?.state == PlaybackState.STATE_PLAYING
                            if (playing) t?.pause() else t?.play()
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasAccess() =
        NotificationManagerCompat.getEnabledListenerPackages(ctx).contains(ctx.packageName)

    /** Passa a acompanhar a música (só com o mapa na tela). */
    private fun start() {
        if (listening || !hasAccess()) return
        try {
            msm.addOnActiveSessionsChangedListener(sessionsListener, component, main)
            listening = true
            attach(msm.getActiveSessions(component).firstOrNull())
        } catch (_: SecurityException) {
            // Acesso revogado nas configurações do Android.
        }
    }

    private fun stop() {
        if (!listening) return
        try { msm.removeOnActiveSessionsChangedListener(sessionsListener) } catch (_: Exception) {}
        attach(null)
        listening = false
    }

    private fun attach(c: MediaController?) {
        if (c?.sessionToken == controller?.sessionToken) { push(); return }
        controller?.unregisterCallback(callback)
        controller = c
        lastArtKey = ""
        lastIconPkg = ""
        c?.registerCallback(callback, main)
        push()
    }

    /** Estado atual para o app (null = nada tocando). */
    private fun push() {
        val c = controller
        val m = c?.metadata
        if (c == null || m == null) {
            ch.invokeMethod("state", null)
            return
        }
        val title = m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
        val artist = m.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
        val state = mutableMapOf<String, Any?>(
            "title" to title,
            "artist" to artist,
            "playing" to (c.playbackState?.state == PlaybackState.STATE_PLAYING),
            "app" to c.packageName,
        )
        // Ícone do app que está tocando (Spotify...), só quando muda o app.
        if (c.packageName != lastIconPkg) {
            lastIconPkg = c.packageName
            state["appIcon"] = try {
                val d = ctx.packageManager.getApplicationIcon(c.packageName)
                val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                val cv = android.graphics.Canvas(bmp)
                d.setBounds(0, 0, 96, 96)
                d.draw(cv)
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
                out.toByteArray()
            } catch (_: Exception) { null }
        }
        // Capa só quando muda a música (é o item mais pesado).
        val artKey = "$title|$artist"
        if (artKey != lastArtKey) {
            lastArtKey = artKey
            val art = m.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                ?: m.getBitmap(MediaMetadata.METADATA_KEY_ART)
            state["art"] = art?.let { small(it) }
        }
        ch.invokeMethod("state", state)
    }

    private fun small(b: Bitmap): ByteArray {
        val s = Bitmap.createScaledBitmap(b, 96, 96, true)
        val out = ByteArrayOutputStream()
        s.compress(Bitmap.CompressFormat.JPEG, 80, out)
        return out.toByteArray()
    }
}
