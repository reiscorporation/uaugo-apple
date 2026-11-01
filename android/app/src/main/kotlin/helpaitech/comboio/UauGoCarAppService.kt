// ============================================================================
// UauGoCarAppService.kt — Modo carro (Android Auto)
//
// O que faz: Tela de navegação na central do carro: próxima manobra (seta e
//   distância), chegada e distância que falta, botões (Radar, Perigo,
//   Encerrar) e o desenho do trajeto com a posição do piloto. Os dados vêm do
//   celular (CarState, alimentado pelo Dart). A rota é escolhida no celular
//   (ou por voz: "UauGo, ir para").
// Quem usa: o Android Auto (serviço declarado no AndroidManifest.xml).
// Onde mexer: Mapa: CarMapView.kt (Google Maps; MapRenderer é o desenho
//   simples de reserva). Ícones das manobras:
//   res/drawable/car_*.xml.
// ============================================================================

package helpaitech.comboio

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.view.Surface
import androidx.car.app.AppManager
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.CarIcon
import androidx.car.app.model.DateTimeWithZone
import androidx.car.app.model.Distance
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.Maneuver
import androidx.car.app.navigation.model.MessageInfo
import androidx.car.app.navigation.model.NavigationTemplate
import androidx.car.app.navigation.model.RoutingInfo
import androidx.car.app.navigation.model.Step
import androidx.car.app.navigation.model.TravelEstimate
import androidx.car.app.validation.HostValidator
import androidx.core.graphics.drawable.IconCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.util.TimeZone
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class UauGoCarAppService : CarAppService() {
    // Teste (versão de depuração): aceita qualquer central. Na loja, só as
    // centrais conhecidas (lista do Google).
    override fun createHostValidator(): HostValidator =
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
        } else {
            HostValidator.Builder(applicationContext)
                .addAllowedHosts(androidx.car.app.R.array.hosts_allowlist_sample)
                .build()
        }

    override fun onCreateSession(): Session = UauGoSession()
}

class UauGoSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        CarState.updateConnected(true)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) = CarState.updateConnected(false)
        })
        handleNavigate(intent)
        return NavScreen(carContext)
    }

    // Já aberto no carro e o motorista pede outro destino ao Assistente.
    override fun onNewIntent(intent: Intent) = handleNavigate(intent)

    /** "Navegue até X" (Assistente/Gemini): manda o destino para o celular,
     *  que traça a rota e inicia sozinho (como o "UauGo, ir para"). */
    private fun handleNavigate(intent: Intent) {
        if (intent.action != CarContext.ACTION_NAVIGATE) return
        val geo = intent.dataString ?: return
        val sink = CarState.actionSink
        if (sink != null) {
            sink("navigate:$geo")
        } else {
            CarToast.makeText(carContext,
                if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular",
                CarToast.LENGTH_LONG).show()
        }
    }
}

/** Tela de navegação do carro. */
class NavScreen(ctx: CarContext) : Screen(ctx), SurfaceCallback {
    private val renderer = MapRenderer()
    // Mapa do Google na tela do carro; se não abrir, fica o desenho simples.
    private val carMap = CarMapView(ctx)
    private var navigating = false
    private val nav: NavigationManager = ctx.getCarService(NavigationManager::class.java)
    private val onChange: () -> Unit = {
        if (carMap.running) carMap.update() else renderer.draw()
        updateNavigationState()
        invalidate()
    }

    // GPS direto do celular: o mapa do carro abre onde o piloto está, com a
    // velocidade, mesmo sem o mapa aberto no celular. Quando o celular
    // (Dart) está mandando a posição, ela tem prioridade.
    private val gps = LocationListener { loc: Location ->
        if (System.currentTimeMillis() - CarState.lastDartUpdate < 3000) return@LocationListener
        CarState.lat = loc.latitude
        CarState.lng = loc.longitude
        if (loc.hasBearing() && loc.speed > 1.5f) CarState.bearing = loc.bearing.toDouble()
        CarState.speedKmh = (loc.speed * 3.6f).toInt()
        CarState.hasPosition = true
        CarState.changed()
    }

    private fun startGps() {
        val lm = carContext.getSystemService(android.content.Context.LOCATION_SERVICE) as LocationManager
        try {
            lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)?.let { gps.onLocationChanged(it) }
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, gps, Looper.getMainLooper())
        } catch (_: SecurityException) {
            // Sem permissão de localização: o mapa espera o celular.
        } catch (_: Exception) {}
    }

    private fun toast(t: String) = runCatching {
        CarToast.makeText(carContext, t, CarToast.LENGTH_LONG).show()
    }

    init {
        ctx.getCarService(AppManager::class.java).setSurfaceCallback(this)
        startGps()
        CarState.toastSink = { t -> toast(t) }
        nav.setNavigationManagerCallback(object : NavigationManagerCallback {
            // O carro pediu para parar (ex.: outro app de navegação começou).
            override fun onStopNavigation() {
                navigating = false
                CarState.actionSink?.invoke("stop")
            }
        })
        CarState.listen(onChange)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                CarState.unlisten(onChange)
                runCatching {
                    (carContext.getSystemService(android.content.Context.LOCATION_SERVICE) as LocationManager)
                        .removeUpdates(gps)
                }
                CarState.toastSink = null
                carMap.stop()
                if (navigating) runCatching { nav.navigationEnded() }
            }
        })
    }

    /** Avisa o carro quando a navegação começa/termina (painel, foco). */
    private fun updateNavigationState() {
        val active = CarState.nav != null
        if (active == navigating) return
        navigating = active
        runCatching { if (active) nav.navigationStarted() else nav.navigationEnded() }
    }

    private fun icon(res: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, res)).build()

    private fun maneuverOf(m: String): Maneuver {
        val (type, res) = when {
            m.startsWith("uturn") -> Maneuver.TYPE_U_TURN_LEFT to R.drawable.car_uturn
            m.startsWith("roundabout-left") -> Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW to R.drawable.car_turn_left
            m.startsWith("roundabout") -> Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CW to R.drawable.car_turn_right
            m == "turn-sharp-left" -> Maneuver.TYPE_TURN_SHARP_LEFT to R.drawable.car_turn_left
            m == "turn-sharp-right" -> Maneuver.TYPE_TURN_SHARP_RIGHT to R.drawable.car_turn_right
            m == "turn-slight-left" -> Maneuver.TYPE_TURN_SLIGHT_LEFT to R.drawable.car_slight_left
            m == "turn-slight-right" -> Maneuver.TYPE_TURN_SLIGHT_RIGHT to R.drawable.car_slight_right
            m == "ramp-left" -> Maneuver.TYPE_ON_RAMP_SLIGHT_LEFT to R.drawable.car_slight_left
            m == "ramp-right" -> Maneuver.TYPE_ON_RAMP_SLIGHT_RIGHT to R.drawable.car_slight_right
            m == "fork-left" -> Maneuver.TYPE_FORK_LEFT to R.drawable.car_slight_left
            m == "fork-right" -> Maneuver.TYPE_FORK_RIGHT to R.drawable.car_slight_right
            m == "keep-left" -> Maneuver.TYPE_KEEP_LEFT to R.drawable.car_slight_left
            m == "keep-right" -> Maneuver.TYPE_KEEP_RIGHT to R.drawable.car_slight_right
            m == "merge" -> Maneuver.TYPE_MERGE_SIDE_UNSPECIFIED to R.drawable.car_straight
            m.contains("left") -> Maneuver.TYPE_TURN_NORMAL_LEFT to R.drawable.car_turn_left
            m.contains("right") -> Maneuver.TYPE_TURN_NORMAL_RIGHT to R.drawable.car_turn_right
            else -> Maneuver.TYPE_STRAIGHT to R.drawable.car_straight
        }
        val b = Maneuver.Builder(type).setIcon(icon(res))
        if (type == Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CW ||
            type == Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CCW) {
            b.setRoundaboutExitNumber(1)
        }
        return b.build()
    }

    private fun distance(m: Double): Distance =
        if (m >= 1000) Distance.create(m / 1000.0, Distance.UNIT_KILOMETERS)
        else Distance.create((m / 10).toInt() * 10.0, Distance.UNIT_METERS)

    override fun onGetTemplate(): Template {
        fun action(title: String, code: String) = Action.Builder()
            .setTitle(title)
            .setOnClickListener {
                // Sem o app rodando no celular, avisa em vez de ficar mudo.
                val sink = CarState.actionSink
                if (sink == null) toast(if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular") else sink(code)
            }
            .build()
        fun icon(res: Int) = CarIcon.Builder(IconCompat.createWithResource(carContext, res)).build()
        // Alerta e radar móvel ficam desenhados no mapa, iguais aos do celular
        // (a barra do Android Auto pinta os ícones de uma cor só). Carro sem
        // toque no mapa (API < 5): continuam aqui.
        val sb = ActionStrip.Builder()
        if (carContext.carAppApiLevel < 5) {
            sb.addAction(Action.Builder()
                .setIcon(icon(R.drawable.car_alert))
                .setOnClickListener { openAlerts() }
                .build())
            sb.addAction(action("Radar", "radar"))
        }
        val strip = sb
            .addAction(action(if (CarState.en) "End" else "Encerrar", "stop"))
            .build()
        // Zoom do mapa do carro: o motorista escolhe (+/−).
        fun zoom(res: Int, step: Float) = Action.Builder()
            .setIcon(icon(res))
            .setOnClickListener {
                CarState.zoomOffset = (CarState.zoomOffset + step).coerceIn(-4f, 3f)
                if (carMap.running) carMap.update()
            }
            .build()
        // Estrada em 3D: mapa -> 3D nas saídas -> 3D sempre.
        val view3d = Action.Builder()
            .setIcon(icon(R.drawable.car_3d))
            .setOnClickListener {
                CarState.mode3d = (CarState.mode3d + 1) % 3
                toast(when (CarState.mode3d) {
                    0 -> if (CarState.en) "Map view" else "Só mapa"
                    1 -> if (CarState.en) "3D at exits" else "3D nas saídas"
                    else -> if (CarState.en) "3D always" else "3D sempre"
                })
                if (carMap.running) carMap.update()
            }
            .build()
        val mapStrip = ActionStrip.Builder()
            .addAction(zoom(R.drawable.car_zoom_in, 1f))
            .addAction(zoom(R.drawable.car_zoom_out, -1f))
            .addAction(view3d)
            .build()
        val b = NavigationTemplate.Builder().setActionStrip(strip).setMapActionStrip(mapStrip)
        // A manobra, a chegada e os avisos são desenhados no mapa (CarOverlay),
        // com o visual do celular; o Android Auto mostra só os botões.
        return b.build()
    }

    // ---- SurfaceCallback: o desenho do trajeto na tela do carro
    override fun onSurfaceAvailable(c: SurfaceContainer) {
        val s = c.surface ?: return
        if (carMap.start(s, c.width, c.height, c.dpi)) return
        renderer.surface = s
        renderer.width = c.width
        renderer.height = c.height
        renderer.draw()
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        if (carMap.running) {
            carMap.setVisibleArea(visibleArea)
        } else {
            renderer.visible = visibleArea
            renderer.draw()
        }
    }

    private fun openAlerts() = screenManager.push(AlertListScreen(carContext))

    private val sosTimer = android.os.Handler(android.os.Looper.getMainLooper())
    private val sosDisarm = Runnable {
        CarState.sosArmed = false
        CarState.changed()
    }

    /** No carro não existe "segurar": 1º toque pede confirmação, o 2º envia. */
    private fun sosTap() {
        sosTimer.removeCallbacks(sosDisarm)
        if (CarState.sosArmed) {
            CarState.sosArmed = false
            val sink = CarState.actionSink
            if (sink == null) toast(if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular") else sink("sos")
        } else {
            CarState.sosArmed = true
            sosTimer.postDelayed(sosDisarm, 3000)
        }
        CarState.changed()
    }

    /** Toque no mapa: os botões de alerta e radar, iguais aos do celular. */
    override fun onClick(x: Float, y: Float) {
        val hit = carMap.tap(x, y)
        when {
            hit == "alert" -> openAlerts()
            hit == "radar" -> {
                val sink = CarState.actionSink
                if (sink == null) toast(if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular") else sink("radar")
            }
            hit == "requests" -> screenManager.push(GroupRequestScreen(carContext))
            hit == "sos" -> sosTap()
            hit?.startsWith("do:") == true -> CarState.actionSink?.invoke(hit.removePrefix("do:"))
            hit != null -> screenManager.push(RemoveAlertScreen(carContext, hit.removePrefix("hazard:")))
        }
    }

    override fun onSurfaceDestroyed(c: SurfaceContainer) {
        carMap.stop()
        renderer.surface = null
    }
}

/**
 * Desenho simples do trajeto (sem mapa de fundo): a rota em laranja girada
 * na direção do piloto, a seta dele, a velocidade e o limite. A escala abre
 * com a velocidade (vê mais longe na rodovia).
 */
class MapRenderer {
    @Volatile var surface: Surface? = null
    @Volatile var width = 0
    @Volatile var height = 0
    @Volatile var visible: Rect? = null

    private val route = Paint().apply {
        color = Color.rgb(255, 122, 26); strokeWidth = 14f; style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; isAntiAlias = true
    }
    private val arrow = Paint().apply { color = Color.WHITE; isAntiAlias = true }
    private val text = Paint().apply { color = Color.WHITE; textSize = 34f; isAntiAlias = true; isFakeBoldText = true }
    private val sign = Paint().apply { color = Color.RED; style = Paint.Style.STROKE; strokeWidth = 8f; isAntiAlias = true }
    private val signFill = Paint().apply { color = Color.WHITE; isAntiAlias = true }
    private val signText = Paint().apply {
        color = Color.BLACK; textSize = 34f; isAntiAlias = true; isFakeBoldText = true; textAlign = Paint.Align.CENTER
    }

    @Synchronized
    fun draw() {
        val s = surface ?: return
        if (width <= 0 || height <= 0 || !s.isValid) return
        val canvas: Canvas = try { s.lockCanvas(null) } catch (_: Exception) { return }
        try {
            canvas.drawColor(Color.rgb(15, 27, 45))
            val area = visible ?: Rect(0, 0, width, height)
            val cx = area.centerX().toFloat()
            val cy = area.top + area.height() * 0.70f
            if (CarState.hasPosition) {
                // Metros por pixel: ~700 m de altura parado, até ~3 km na rodovia.
                val span = min(3000.0, max(700.0, CarState.speedKmh * 25.0))
                val mpp = span / max(1, area.height())
                val lat0 = CarState.lat
                val lng0 = CarState.lng
                val kx = 111320.0 * cos(Math.toRadians(lat0))
                val rot = Math.toRadians(-CarState.bearing)
                val path = Path()
                var first = true
                for (p in CarState.route) {
                    val x = (p[1] - lng0) * kx
                    val y = (p[0] - lat0) * 110540.0
                    // Gira para "frente = para cima" e passa para pixels.
                    val rx = x * cos(rot) - y * sin(rot)
                    val ry = x * sin(rot) + y * cos(rot)
                    val px = (cx + rx / mpp).toFloat()
                    val py = (cy - ry / mpp).toFloat()
                    if (first) { path.moveTo(px, py); first = false } else path.lineTo(px, py)
                }
                if (!first) canvas.drawPath(path, route)
            }
            // Seta do piloto.
            val a = Path().apply {
                moveTo(cx, cy - 34f); lineTo(cx + 24f, cy + 24f); lineTo(cx, cy + 12f); lineTo(cx - 24f, cy + 24f); close()
            }
            canvas.drawPath(a, arrow)
            // Velocidade e placa do limite (canto de baixo à esquerda).
            val bx = area.left + 40f
            val by = area.bottom - 40f
            canvas.drawText("${CarState.speedKmh} km/h", bx, by, text)
            if (CarState.limitKmh > 0) {
                val r = 38f
                val sx = bx + r
                val sy = by - 90f
                canvas.drawCircle(sx, sy, r, signFill)
                canvas.drawCircle(sx, sy, r, sign)
                canvas.drawText("${CarState.limitKmh}", sx, sy + 12f, signText)
            }
            CarState.nav?.alert?.let { canvas.drawText(it, area.left + 40f, area.top + 60f, text) }
        } finally {
            s.unlockCanvasAndPost(canvas)
        }
    }
}

/** Lista de alertas na tela do carro (aberta pelo botão ⚠). */
class AlertListScreen(ctx: CarContext) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        // Mesmo nome dos tipos do app (HazardType no Dart).
        val types = listOf(
            Triple("radar", "📷", if (en) "Mobile speed camera" else "Radar móvel"),
            Triple("police", "🚓", if (en) "Police" else "Polícia"),
            Triple("accident", "💥", if (en) "Accident" else "Acidente"),
            Triple("pothole", "🕳️", if (en) "Pothole" else "Buraco"),
            Triple("danger", "⚠️", if (en) "Road hazard" else "Perigo na pista"),
            Triple("animal", "🐄", if (en) "Animal on the road" else "Animal na pista"),
            Triple("oil", "🛢️", if (en) "Oil / sand" else "Óleo / areia"),
            Triple("fog", "🌫️", if (en) "Fog" else "Neblina"),
        )
        val list = ItemList.Builder()
        if (CarState.hazards.any { it.mine }) {
            list.addItem(Row.Builder()
                .setTitle(if (en) "🗑️  Remove my alert" else "🗑️  Remover meu alerta")
                .setBrowsable(true)
                .setOnClickListener { screenManager.push(RemoveAlertScreen(carContext)) }
                .build())
        }
        for ((code, emoji, label) in types) {
            list.addItem(Row.Builder()
                .setTitle("$emoji  $label")
                .setOnClickListener {
                    val sink = CarState.actionSink
                    if (sink == null) {
                        CarToast.makeText(carContext,
                            if (en) "Open UauGo on the phone" else "Abra o UauGo no celular",
                            CarToast.LENGTH_SHORT).show()
                    } else {
                        sink("hazard:$code")
                    }
                    screenManager.pop()
                }
                .build())
        }
        return ListTemplate.Builder()
            .setTitle(if (en) "Report on the road" else "O que tem na pista?")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Alertas marcados pelo próprio piloto, do mais perto ao mais longe. */
class RemoveAlertScreen(ctx: CarContext, private val only: String? = null) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        val k = cos(Math.toRadians(CarState.lat))
        fun meters(h: CarState.Hazard): Double {
            val x = (h.lng - CarState.lng) * 111320.0 * k
            val y = (h.lat - CarState.lat) * 110540.0
            return Math.hypot(x, y)
        }
        val list = ItemList.Builder()
        for (h in CarState.hazards.filter { it.mine && (only == null || it.id == only) }.sortedBy { meters(it) }.take(6)) {
            val m = meters(h)
            list.addItem(Row.Builder()
                .setTitle("${h.emoji}  ${h.label}")
                .addText(if (m < 1000) "${m.toInt()} m" else "${"%.1f".format(m / 1000)} km")
                .setOnClickListener {
                    val sink = CarState.actionSink
                    if (sink == null) {
                        CarToast.makeText(carContext,
                            if (en) "Open UauGo on the phone" else "Abra o UauGo no celular",
                            CarToast.LENGTH_SHORT).show()
                    } else {
                        sink("unhazard:${h.id}")
                    }
                    screenManager.popToRoot()
                }
                .build())
        }
        return ListTemplate.Builder()
            .setTitle(if (en) "Remove my alert" else "Remover meu alerta")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Pedidos ao grupo (os mesmos do celular, GroupRequest no Dart). */
class GroupRequestScreen(ctx: CarContext) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        val kinds = listOf(
            Triple("fuel", "⛽", if (en) "I need to refuel" else "Preciso abastecer"),
            Triple("restroom", "🚻", if (en) "Restroom stop" else "Parada para banheiro"),
            Triple("rest", "☕", if (en) "I need a rest" else "Preciso descansar"),
            Triple("problem", "🔧", if (en) "Vehicle problem" else "Problema no veículo"),
            Triple("behind", "🐢", if (en) "Wait, I fell behind" else "Esperem, fiquei para trás"),
        )
        val list = ItemList.Builder()
        for ((code, emoji, label) in kinds) {
            list.addItem(Row.Builder()
                .setTitle("$emoji  $label")
                .setOnClickListener {
                    val sink = CarState.actionSink
                    if (sink == null) {
                        CarToast.makeText(carContext,
                            if (en) "Open UauGo on the phone" else "Abra o UauGo no celular",
                            CarToast.LENGTH_SHORT).show()
                    } else {
                        sink("group:$code")
                    }
                    screenManager.pop()
                }
                .build())
        }
        return ListTemplate.Builder()
            .setTitle(if (en) "Request to the group" else "Pedido ao grupo")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}
