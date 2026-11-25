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
    /** Próximas manobras (manobra, texto, metros), a 1ª é a atual (23/11). */
    @Volatile var steps: List<Triple<String, String, Int>> = emptyList()
    @Volatile var route: List<DoubleArray> = emptyList() // [lat, lng]
    /** Trechos da rota com trânsito: nível (0–2) e pontos [lat, lng]. */
    @Volatile var traffic: List<Pair<Int, List<DoubleArray>>> = emptyList()
    /** Radares (1–3) e postos policiais (4) perto: [lat, lng, tipo]. */
    @Volatile var pois: List<DoubleArray> = emptyList()
    /** Alertas da comunidade perto do piloto (mine = marcado por ele). */
    /** Colegas do comboio no mapa do carro (nome, posição). */
    data class Member(val name: String, val lat: Double, val lng: Double)
    @Volatile var members: List<Member> = emptyList()
    /** Visão COMBOIO (todos do grupo na tela) ou SOLO (segue o piloto). */
    @Volatile var convoyView = false

    data class Hazard(val id: String, val lat: Double, val lng: Double,
                      val emoji: String, val label: String, val mine: Boolean)
    @Volatile var hazards: List<Hazard> = emptyList()
    /** Em expedição: botões de SOS e pedidos, e a faixa do grupo (SOS, pedido). */
    @Volatile var groupOn = false
    @Volatile var groupText: String? = null
    @Volatile var groupAction: String? = null
    @Volatile var groupUrgent = false
    /** SOS tocado uma vez: o próximo toque em até 3 s envia. */
    @Volatile var sosArmed = false
    /** 24/11: próximos passos minimizados na tela do carro (só a aba fina). */
    @Volatile var stepsMin = false
    @Volatile var lat = 0.0
    @Volatile var lng = 0.0
    @Volatile var bearing = 0.0
    @Volatile var hasPosition = false
    /** O celular diz que está seguindo a rota (não saiu dela): o carro põe o
     *  veículo na linha azul mesmo com o GPS mais longe (15/11). */
    @Volatile var onRoute = false
    @Volatile var speedKmh = 0
    @Volatile var limitKmh = 0
    /** Contagem do radar ("📸 80 em 450 m") e faixa amarela de aviso. */
    @Volatile var alert: String? = null
    @Volatile var banner: String? = null
    /** Pergunta do celular para a tela do carro: (título, texto). A tela do
     *  carro abre quando houver uma ([askSink] ou ao montar). */
    @Volatile var pendingAsk: Ask? = null
    /** Pergunta sim/não: o código de cada resposta volta ao celular. */
    data class Ask(val title: String, val text: String, val yes: String, val no: String,
                   val yesLabel: String?, val noLabel: String?)
    /** Fechar a pergunta/opções abertas (o celular desistiu: passou o tempo). */
    @Volatile var closeAskSink: (() -> Unit)? = null
    /** Opções de velocidade pedidas pelo celular (toque na faixa amarela). */
    @Volatile var speedEditSink: ((SpeedEdit) -> Unit)? = null
    @Volatile var tollEditSink: ((TollEdit) -> Unit)? = null
    @Volatile var askSink: ((Ask) -> Unit)? = null
    /** Configurações do celular mostradas no ⚙ do carro (por seção). */
    data class CfgItem(val key: String, val title: String, val on: Boolean, val sub: String)
    data class CfgSection(val title: String, val items: List<CfgItem>)
    @Volatile var cfg: List<CfgSection> = emptyList()
    /** Veículo elétrico ou plug-in: eletropostos no carro. */
    @Volatile var ev = false
    /** Nomes de lugares no mapa do carro (opção do usuário). */
    @Volatile var placeNames = true
    /** Emoji do veículo do piloto (🏍️ / 🚗 / 🚚). */
    @Volatile var vehicle = "🏍️"
    /** Textos da tela do carro em inglês (idioma do app, vem do celular). */
    @Volatile var en = java.util.Locale.getDefault().language.let { it != "pt" && it != "es" }
    /** Textos da tela do carro em espanhol (17/11). */
    @Volatile var es = java.util.Locale.getDefault().language == "es"
    /** Zoom escolhido pelo motorista nos botões +/− do carro (passos). */
    @Volatile var zoomOffset = 0f
    /** Destinos para escolher no carro: (nome, lat, lng). */
    @Volatile var destinations: List<Triple<String, Double, Double>> = emptyList()
    /** Resultado da busca feita no carro: (id, nome, endereço). */
    @Volatile var searchResults: List<Triple<String, String, String>> = emptyList()
    @Volatile var searching = false
    /** Tela de busca aberta no carro (atualiza ao chegar o resultado). */
    @Volatile var onSearchResults: (() -> Unit)? = null
    /** Pedidos do carro que chegaram antes de o app (Dart) estar pronto. */
    val pending = java.util.concurrent.ConcurrentLinkedQueue<String>()
    @Volatile var dartReady = false
    /** Bússola do carro: norte sempre para cima (sem inclinar o mapa). */
    @Volatile var northUp = false

    /** Contato de emergência (Configurações do celular), para o SOS do carro. */
    @Volatile var emergencyName: String? = null
    @Volatile var emergencyPhone: String? = null
    /** Estrada em 3D no carro: 0 = só mapa, 1 = nas saídas, 2 = sempre. */
    @Volatile var mode3d = 0
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

    /** Ponto da rota mais perto de (lat, lng), se estiver a até [maxM]
     *  metros dela; senão null. O GPS nativo (quando o celular atrasa)
     *  usa isto para o veículo não sair da linha azul (14/11). */
    fun snapToRoute(lat: Double, lng: Double, maxM: Double = 100.0): DoubleArray? {
        val pts = route
        if (pts.size < 2) return null
        val k = Math.cos(Math.toRadians(lat))
        var best: DoubleArray? = null
        var bestD = maxM * maxM
        for (i in 0 until pts.size - 1) {
            val ax = (pts[i][1] - lng) * 111320.0 * k
            val ay = (pts[i][0] - lat) * 111320.0
            val bx = (pts[i + 1][1] - lng) * 111320.0 * k
            val by = (pts[i + 1][0] - lat) * 111320.0
            val dx = bx - ax
            val dy = by - ay
            val len2 = dx * dx + dy * dy
            val t = if (len2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / len2).coerceIn(0.0, 1.0)
            val px = ax + t * dx
            val py = ay + t * dy
            val d = px * px + py * py
            if (d < bestD) {
                bestD = d
                best = doubleArrayOf(pts[i][0] + t * (pts[i + 1][0] - pts[i][0]),
                    pts[i][1] + t * (pts[i + 1][1] - pts[i][1]))
            }
        }
        return best
    }

    /** Aviso curto na tela do carro ("Alerta de radar enviado"). */
    var toastSink: ((String) -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<() -> Unit>()

    /** Botão do carro -> Dart ("radar", "hazard", "stop"). */
    var actionSink: ((String) -> Unit)? = null
    // 23/11: uma lista, não um só: o app pode ter duas cópias do Flutter (a do
    // celular e a que atende o carro em segundo plano). Com um só, o aviso
    // "carro desligou" ia para a última e a tela do celular ficava presa em
    // "UauGo está na tela do carro".
    val connectedSinks = java.util.concurrent.CopyOnWriteArrayList<(Boolean) -> Unit>()

    fun listen(l: () -> Unit) = synchronized(listeners) { listeners.add(l) }
    fun unlisten(l: () -> Unit) = synchronized(listeners) { listeners.remove(l) }

    fun changed() = main.post {
        val copy = synchronized(listeners) { listeners.toList() }
        copy.forEach { it() }
    }

    fun updateConnected(on: Boolean) {
        connected = on
        main.post { connectedSinks.forEach { s -> runCatching { s(on) } } }
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
                        (a["lang"] as? String)?.let { CarState.en = it == "en"; CarState.es = it == "es" }
                        (a["placeNames"] as? Boolean)?.let { CarState.placeNames = it }
                        (a["convoy"] as? Boolean)?.let { CarState.convoyView = it }
                        CarState.onRoute = a["onRoute"] == true
                        (a["ev"] as? Boolean)?.let { CarState.ev = it }
                        (a["cfg"] as? List<*>)?.let { l ->
                            CarState.cfg = l.mapNotNull { sec ->
                                val m = sec as? Map<*, *> ?: return@mapNotNull null
                                CarState.CfgSection(m["t"] as? String ?: "",
                                    (m["i"] as? List<*>).orEmpty().mapNotNull { it2 ->
                                        val i = it2 as? Map<*, *> ?: return@mapNotNull null
                                        CarState.CfgItem(i["k"] as? String ?: return@mapNotNull null,
                                            i["t"] as? String ?: "", i["v"] == true, i["s"] as? String ?: "")
                                    })
                            }
                        }
                        CarState.steps = (a["steps"] as? List<*>).orEmpty().mapNotNull { st ->
                            val l = st as? List<*> ?: return@mapNotNull null
                            Triple(l.getOrNull(0) as? String ?: "", l.getOrNull(1) as? String ?: "",
                                (l.getOrNull(2) as? Number)?.toInt() ?: 0)
                        }
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
                "traffic" -> {
                    val f = (call.arguments as? List<*>)?.mapNotNull { (it as? Number)?.toDouble() }
                        ?: emptyList()
                    val runs = ArrayList<Pair<Int, List<DoubleArray>>>()
                    var i = 0
                    while (i + 1 < f.size) {
                        val n = f[i + 1].toInt()
                        val end = i + 2 + n * 2
                        if (end > f.size) break
                        runs.add(f[i].toInt() to (0 until n).map {
                            doubleArrayOf(f[i + 2 + it * 2], f[i + 3 + it * 2])
                        })
                        i = end
                    }
                    CarState.traffic = runs
                    CarState.changed()
                    result.success(null)
                }
                "clear" -> {
                    CarState.nav = null
                    CarState.route = emptyList()
                    CarState.traffic = emptyList()
                    CarState.changed()
                    result.success(null)
                }
                "connected" -> {
                    result.success(CarState.connected)
                    // O app acabou de subir: entrega o que o carro já pediu.
                    CarState.dartReady = true
                    Handler(Looper.getMainLooper()).post {
                        while (true) {
                            val a = CarState.pending.poll() ?: break
                            channel.invokeMethod("action", a)
                        }
                    }
                }
                "searchResults" -> {
                    val l = call.arguments as? List<*> ?: emptyList<Any>()
                    CarState.searchResults = l.mapNotNull { e ->
                        val m = e as? Map<*, *> ?: return@mapNotNull null
                        Triple(m["id"] as? String ?: return@mapNotNull null,
                            m["n"] as? String ?: "", m["s"] as? String ?: "")
                    }
                    CarState.searching = false
                    CarState.onSearchResults?.invoke()
                    result.success(null)
                }
                "destinations" -> {
                    val l = call.arguments as? List<*> ?: emptyList<Any>()
                    CarState.destinations = l.mapNotNull { e ->
                        val m = e as? Map<*, *> ?: return@mapNotNull null
                        val n = m["n"] as? String ?: return@mapNotNull null
                        val la = (m["la"] as? Number)?.toDouble() ?: return@mapNotNull null
                        val lo = (m["lo"] as? Number)?.toDouble() ?: return@mapNotNull null
                        Triple(n, la, lo)
                    }
                    result.success(null)
                }
                "emergency" -> {
                    val m = call.arguments as? Map<*, *>
                    CarState.emergencyName = m?.get("name") as? String
                    CarState.emergencyPhone = m?.get("phone") as? String
                    result.success(null)
                }
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
                "hazards" -> {
                    // Alertas: [id, lat, lng, emoji, nome, meu, ...].
                    CarState.hazards = (call.arguments as? List<*>).orEmpty().chunked(6)
                        .filter { it.size == 6 }
                        .map {
                            CarState.Hazard(it[0] as String, (it[1] as Number).toDouble(),
                                (it[2] as Number).toDouble(), it[3] as String,
                                it[4] as String, it[5] == true)
                        }
                    CarState.changed()
                    result.success(null)
                }
                "members" -> {
                    CarState.members = (call.arguments as? List<*>).orEmpty().chunked(3)
                        .filter { it.size == 3 }
                        .map { CarState.Member(it[0] as String, (it[1] as Number).toDouble(), (it[2] as Number).toDouble()) }
                    CarState.changed()
                    result.success(null)
                }
                "group" -> {
                    val a = call.arguments as? Map<*, *>
                    CarState.groupOn = a?.get("on") == true
                    CarState.groupText = a?.get("text") as? String
                    CarState.groupAction = a?.get("action") as? String
                    CarState.groupUrgent = a?.get("urgent") == true
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
                "tollEdit" -> {
                    val m = call.arguments as? Map<*, *>
                    val q = TollEdit(m?.get("title") as? String ?: "",
                        (m?.get("cents") as? Number)?.toInt() ?: 0)
                    CarState.tollEditSink?.let { s -> Handler(Looper.getMainLooper()).post { s(q) } }
                    result.success(null)
                }
                "speedEdit" -> {
                    val m = call.arguments as? Map<*, *>
                    val q = SpeedEdit(m?.get("title") as? String ?: "",
                        (m?.get("current") as? Number)?.toInt(), m?.get("radar") == true)
                    CarState.speedEditSink?.let { s -> Handler(Looper.getMainLooper()).post { s(q) } }
                    result.success(null)
                }
                "ask" -> {
                    val m = call.arguments as? Map<*, *>
                    val q = CarState.Ask(m?.get("title") as? String ?: "", m?.get("text") as? String ?: "",
                        m?.get("yes") as? String ?: "resume:yes", m?.get("no") as? String ?: "resume:no",
                        m?.get("yesLabel") as? String, m?.get("noLabel") as? String)
                    CarState.pendingAsk = q
                    CarState.askSink?.let { s -> Handler(Looper.getMainLooper()).post { s(q) } }
                    result.success(null)
                }
                "closeAsk" -> {
                    CarState.pendingAsk = null
                    CarState.closeAskSink?.let { s -> Handler(Looper.getMainLooper()).post { s() } }
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
        CarState.actionSink = { a ->
            if (CarState.dartReady) channel.invokeMethod("action", a) else CarState.pending.add(a)
        }
        CarState.connectedSinks.add { on -> channel.invokeMethod("connected", on) }
    }
}

/** Pedido de confirmar/corrigir velocidade na tela do carro. */
data class SpeedEdit(val title: String, val current: Int?, val radar: Boolean)
data class TollEdit(val title: String, val currentCents: Int)
