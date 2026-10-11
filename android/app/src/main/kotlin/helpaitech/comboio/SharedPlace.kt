// ============================================================================
// SharedPlace.kt — Endereço recebido de outro app
//
// O que faz: Quando o usuário toca num endereço/localização (WhatsApp, agenda,
//   e-mail...), abre um link do Google Maps ou usa "Compartilhar → UauGo", o
//   Android entrega o texto/link aqui. Ele vai cru para o Dart, que entende o
//   formato (lib/logic/shared_place.dart).
// Quem usa: MainActivity; lib/services/shared_place_service.dart (canal
//   "uaugo/shared_place").
// Onde mexer: Quais links o app aceita: intent-filters no AndroidManifest.xml.
// ============================================================================

package helpaitech.comboio

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class SharedPlace(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "uaugo/shared_place")

    /// Recebido ao abrir o app (o Dart ainda não estava pronto): o Dart busca.
    private var pending: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "initial") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
    }

    /// [initial]: intent que abriu o app; senão, chegou com o app aberto.
    fun handle(intent: Intent?, initial: Boolean) {
        val text = extract(intent) ?: return
        if (initial) pending = text else channel.invokeMethod("shared", text)
    }

    private fun extract(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.dataString
        Intent.ACTION_SEND -> listOfNotNull(
            intent.getStringExtra(Intent.EXTRA_SUBJECT),
            intent.getStringExtra(Intent.EXTRA_TEXT),
        ).joinToString("\n").ifBlank { null }
        else -> null
    }
}
