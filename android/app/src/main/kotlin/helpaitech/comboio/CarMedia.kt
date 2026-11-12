// ============================================================================
// CarMedia.kt — Música na tela do carro (botão ♪, igual ao do celular)
//
// O que faz: lê a música que está tocando no celular (Spotify, YouTube Music...)
//   e manda anterior / tocar-pausar / próxima, pelo mesmo acesso de
//   notificações que o celular já usa (MediaListenerService).
// Quem usa: MusicScreen (UauGoCarAppService.kt).
// ============================================================================

package helpaitech.comboio

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import androidx.core.app.NotificationManagerCompat

object CarMedia {
    fun hasAccess(ctx: Context) =
        NotificationManagerCompat.getEnabledListenerPackages(ctx).contains(ctx.packageName)

    /** Sessão de mídia ativa agora (null = nada tocando ou sem acesso). */
    fun controller(ctx: Context): MediaController? = try {
        val msm = ctx.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        msm.getActiveSessions(ComponentName(ctx, MediaListenerService::class.java)).firstOrNull()
    } catch (_: Exception) { null }

    data class Now(val title: String, val artist: String, val app: String, val playing: Boolean)

    fun now(ctx: Context): Now? {
        val c = controller(ctx) ?: return null
        val m = c.metadata ?: return null
        val app = try {
            ctx.packageManager.getApplicationLabel(
                ctx.packageManager.getApplicationInfo(c.packageName, 0)).toString()
        } catch (_: Exception) { c.packageName }
        return Now(
            m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "",
            m.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: m.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: "",
            app,
            c.playbackState?.state == PlaybackState.STATE_PLAYING)
    }

    fun command(ctx: Context, cmd: String) {
        val c = controller(ctx) ?: return
        val t = c.transportControls
        when (cmd) {
            "previous" -> t.skipToPrevious()
            "next" -> t.skipToNext()
            "toggle" -> if (c.playbackState?.state == PlaybackState.STATE_PLAYING) t.pause() else t.play()
        }
    }
}
