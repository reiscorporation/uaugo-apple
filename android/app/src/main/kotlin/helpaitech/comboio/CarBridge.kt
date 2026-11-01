// ============================================================================
// CarBridge.kt — Ponte entre a navegação (Flutter) e a tela do carro
//
// O que faz: O celular continua sendo o "cérebro" (rota, alertas, voz). O
//   Dart manda para cá, pelo canal "uaugo/car", a próxima manobra, a chegada,
//   a rota e a posição; a tela do Android Auto (UauGoCarAppService.kt) lê
//   daqui. Os botões do carro (radar, perigo, encerrar) voltam para o Dart.
// Quem usa: MainActivity; lib/services/car_service.dart.
// ============================================================================

package helpaitech.comboio

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Estado da navegação mostrado no carro (lido pela tela do Android Auto). */
object CarState {
    data class Nav(
        val text: String,       // "Vire à direita na Rua X"
        val maneuver: String,   // "turn-right", "roundabout-left"... ("" = seguir)
        val meters: Double,     // até a manobra
        val remainingM: Double, // até o destino
        val etaMillis: Long,    // hora de chegada
        val alert: String?,     // "📸 80 em 450 m"
    )

    @Volatile var nav: Nav? = null
    @Volatile var route: List<DoubleArray> = emptyList() // [lat, lng]
    /** Radares (1–3) e postos policiais (4) perto: [lat, lng, tipo]. */
    @Volatile var pois: List<DoubleArray> = emptyList()
    @Volatile var lat = 0.0
    @Volatile var lng = 0.0
    @Volatile var bearing = 0.0
    @Volatile var hasPosition = false
    @Volatile var speedKmh = 0
    @Volatile var limitKmh = 0
    /** Contagem do radar ("📸 80 em 450 m") e faixa amarela de aviso. */
    @Volatile var alert: String? = null
    @Volatile var banner: String? = null
    /** Emoji do veículo do piloto (🏍️ / 🚗 / 🚚). */
    @Volatile var vehicle = "🏍️"
    /** Textos da tela do carro em inglês (idioma do app, vem do celular). */
    @Volatile var en = java.util.Locale.getDefault().language != "pt"
    /** Zoom escolhido pelo motorista nos botões +/− do carro (passos). */
    @Volatile var zoomOffset = 0f
    /** Estrada em 3D no carro: 0 = só mapa, 1 = nas saídas, 2 = sempre. */
    @Volatile var mode3d = 1
    /** Imagem do veículo (PNG), a mesma do mapa do celular. */
    @Volatile var vehicleImage: ByteArray? = null
    /** Cena 3D: último comando de cada tipo ("sim3d.update" -> js) e quem executa. */
    val sim3dLast = java.util.concurrent.ConcurrentHashMap<String, String>()
    @Volatile var sim3dSink: ((String) -> Unit)? = null

    /** A tela do carro está aberta (o Dart mantém o GPS e a voz). */
    @Volatile var connected = false

    /** Hora do último envio do celular (Dart). Sem envio recente, a tela do
     *  carro usa o GPS direto (CarLocation) para o mapa e a velocidade. */
    @Volatile var lastDartUpdate = 0L

    /** Aviso curto na tela do carro ("Alerta de radar enviado"). */
    var toastSink: ((String) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<() -> Unit>()

    /** Botão do carro -> Dart ("radar", "hazard", "stop"). */
    var actionSink: ((String) -> Unit)? = null
    var connectedSink: ((Boolean) -> Unit)? = null

    fun listen(l: () -> Unit) = synchronized(listeners) { listeners.add(l) }
    fun unlisten(l: () -> Unit) = synchronized(listeners) { listeners.remove(l) }

    fun changed() = main.post {
        val copy = synchronized(listeners) { listeners.toList() }
        copy.forEach { it() }
    }

    fun updateConnected(on: Boolean) {
        connected = on
        main.post { connectedSink?.invoke(on) }
    }
}

class CarBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "uaugo/car")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val a = call.arguments as? Map<*, *>
                    if (a != null) {
                        CarState.lat = (a["lat"] as? Number)?.toDouble() ?: CarState.lat
                        CarState.lng = (a["lng"] as? Number)?.toDouble() ?: CarState.lng
                        CarState.bearing = (a["bearing"] as? Number)?.toDouble() ?: CarState.bearing
                        CarState.speedKmh = (a["speedKmh"] as? Number)?.toInt() ?: 0
                        CarState.limitKmh = (a["limitKmh"] as? Number)?.toInt() ?: 0
                        CarState.hasPosition = true
                        CarState.lastDartUpdate = System.currentTimeMillis()
                        CarState.alert = a["alert"] as? String
                        CarState.banner = a["banner"] as? String
                        (a["vehicle"] as? String)?.let { CarState.vehicle = it }
                        (a["lang"] as? String)?.let { CarState.en = it == "en" }
                        val text = a["text"] as? String
                        CarState.nav = if (text == null) null else CarState.Nav(
                            text = text,
                            maneuver = a["maneuver"] as? String ?: "",
                            meters = (a["meters"] as? Number)?.toDouble() ?: 0.0,
                            remainingM = (a["remainingM"] as? Number)?.toDouble() ?: 0.0,
                            etaMillis = (a["eta"] as? Number)?.toLong() ?: 0L,
                            alert = a["alert"] as? String,
                        )
                        CarState.changed()
                    }
                    result.success(null)
                }
                "route" -> {
                    val flat = (call.arguments as? List<*>)?.mapNotNull { (it as? Number)?.toDouble() }
                        ?: emptyList()
                    CarState.route = flat.chunked(2).filter { it.size == 2 }
                        .map { doubleArrayOf(it[0], it[1]) }
                    CarState.changed()
                    result.success(null)
                }
                "clear" -> {
                    CarState.nav = null
                    CarState.route = emptyList()
                    CarState.changed()
                    result.success(null)
                }
                "connected" -> result.success(CarState.connected)
                "mode3d" -> {
                    (call.arguments as? Int)?.let { CarState.mode3d = it }
                    CarState.changed()
                    result.success(null)
                }
                "vehicleImage" -> {
                    CarState.vehicleImage = call.arguments as? ByteArray
                    CarState.changed()
                    result.success(null)
                }
                "sim3d" -> {
                    // Comando da cena 3D (a mesma do celular).
                    val js = call.arguments as? String
                    if (js != null) {
                        CarState.sim3dLast[js.substringBefore('(')] = js
                        CarState.sim3dSink?.invoke(js)
                    }
                    result.success(null)
                }
                "pois" -> {
                    // Pins de radares e postos policiais: [lat, lng, tipo, ...].
                    val flat = (call.arguments as? List<*>)?.mapNotNull { (it as? Number)?.toDouble() }
                        ?: emptyList()
                    CarState.pois = flat.chunked(3).filter { it.size == 3 }
                        .map { doubleArrayOf(it[0], it[1], it[2]) }
                    CarState.changed()
                    result.success(null)
                }
                "clearNav" -> {
                    // Navegação encerrada: some a manobra e a rota da tela do carro.
                    CarState.nav = null
                    CarState.route = emptyList()
                    CarState.changed()
                    result.success(null)
                }
                "toast" -> {
                    val t = call.arguments as? String
                    if (t != null) CarState.toastSink?.let { s -> Handler(Looper.getMainLooper()).post { s(t) } }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        CarState.actionSink = { a -> channel.invokeMethod("action", a) }
        CarState.connectedSink = { on -> channel.invokeMethod("connected", on) }
    }
}
