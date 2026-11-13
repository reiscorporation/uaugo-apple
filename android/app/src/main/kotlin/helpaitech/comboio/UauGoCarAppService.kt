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
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.SearchTemplate
import androidx.car.app.model.Template
import androidx.car.app.navigation.NavigationManager
import androidx.car.app.navigation.NavigationManagerCallback
import androidx.car.app.navigation.model.Destination
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
        // Celular bloqueado e app fechado: liga o app sem tela para atender.
        UauGoEngine.ensureForCar(carContext)
        CarState.updateConnected(true)
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) = CarState.updateConnected(false)
        })
        handleNavigate(intent)
        return NavScreen(carContext)
    }

    // Já aberto no carro e o motorista pede outro destino ao Assistente.
    override fun onNewIntent(intent: Intent) = handleNavigate(intent)

    // Dia/noite do carro mudou: a tela refaz o modelo e troca o estilo do mapa.
    override fun onCarConfigurationChanged(newConfiguration: android.content.res.Configuration) {
        runCatching { carContext.getCarService(androidx.car.app.ScreenManager::class.java).top.invalidate() }
    }

    /** "Navegue até X" (Assistente/Gemini): manda o destino para o celular,
     *  que traça a rota e inicia sozinho (como o "UauGo, ir para"). */
    private fun handleNavigate(intent: Intent) {
        if (intent.action != CarContext.ACTION_NAVIGATE) return
        val geo = intent.dataString ?: return
        UauGoEngine.send(carContext, "navigate:$geo")
    }
}

/** Tela de navegação do carro. */
class NavScreen(ctx: CarContext) : Screen(ctx), SurfaceCallback {
    private val renderer = MapRenderer()
    // Mapa do Google na tela do carro; se não abrir, fica o desenho simples.
    private val carMap = CarMapView(ctx)

    init {
        CarState.northUp = ctx.getSharedPreferences("car", android.content.Context.MODE_PRIVATE)
            .getBoolean("northUp", false)
        carMap.onMode = { setMode3d(it) }
        // Pergunta do celular (ex.: "Continuar a rota?") na tela do carro.
        CarState.askSink = { q -> showAsk(q) }
        CarState.speedEditSink = { q -> screenManager.push(SpeedEditScreen(carContext, q)) }
        // Depois de a tela do mapa entrar (no init ela ainda não está na pilha).
        CarState.pendingAsk?.let { q ->
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ showAsk(q) }, 800)
        }
    }

    private fun showAsk(q: Pair<String, String>) {
        CarState.pendingAsk = null
        if (screenManager.top is AskScreen) screenManager.pop()
        screenManager.push(AskScreen(carContext, q.first, q.second))
    }

    /** 0 = mapa, 2 = 3D sempre. Vale também no celular (11/11). */
    private fun setMode3d(m: Int) {
        CarState.mode3d = m
        CarState.actionSink?.invoke(if (m == 2) "view:3d" else "view:map")
        if (carMap.running) carMap.update()
        invalidate()
    }
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
            // Não é o motorista tocando em "Encerrar": o carro desligou ou outro
            // app pediu. A rota fica guardada e o celular pergunta ao voltar
            // (testador perdeu a rota ao descer no posto, 12/11).
            override fun onStopNavigation() {
                navigating = false
                CarState.actionSink?.invoke("carstop")
            }

            // "Test drive" do Android Auto (exigência da Play, 11/11): o
            // carro pede para simular a direção; o celular anda sozinho pela
            // rota (simulação), sem GPS de verdade.
            override fun onAutoDriveEnabled() {
                UauGoEngine.send(carContext, "autodrive")
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
                CarState.askSink = null
                CarState.speedEditSink = null
                carMap.stop()
                if (navigating) runCatching { nav.navigationEnded() }
            }
        })
    }

    /** Avisa o carro quando a navegação começa/termina (painel, foco). */
    private fun updateNavigationState() {
        val active = CarState.nav != null
        if (active != navigating) {
            navigating = active
            runCatching { if (active) nav.navigationStarted() else nav.navigationEnded() }
        }
        updateTripInfo()
    }

    private var lastTripAt = 0L

    /** Próxima manobra e chegada para o painel do carro (cluster) e o
     *  Android Auto (exigência da Play, 11/11). No máximo 1 vez por segundo. */
    private fun updateTripInfo() {
        val n = CarState.nav ?: return
        if (!navigating) return
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastTripAt < 1000) return
        lastTripAt = now
        runCatching {
            val tz = TimeZone.getDefault()
            val etaMs = if (n.etaMillis > 0) n.etaMillis else System.currentTimeMillis()
            val eta = DateTimeWithZone.create(etaMs, tz)
            val left = ((etaMs - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
            val step = Step.Builder(n.text.ifBlank { if (CarState.en) "Continue" else "Siga em frente" })
                .setManeuver(maneuverOf(n.maneuver))
                .build()
            val stepEst = TravelEstimate.Builder(distance(n.meters), eta).build()
            val destEst = TravelEstimate.Builder(distance(n.remainingM), eta)
                .setRemainingTimeSeconds(left).build()
            val dest = Destination.Builder()
                .setName(if (CarState.en) "Destination" else "Destino").build()
            nav.updateTrip(androidx.car.app.navigation.model.Trip.Builder()
                .addStep(step, stepEst)
                .addDestination(dest, destEst)
                .build())
        }.onFailure { android.util.Log.w("UauGoCar", "updateTrip: $it") }
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
        // Modo noturno do carro: mapa escuro (exigência da Play, 11/11).
        carMap.setDark(carContext.isDarkMode)
        fun action(title: String, code: String) = Action.Builder()
            .setTitle(title)
            .setOnClickListener {
                // Sem o app rodando no celular, liga o app (sem tela) e entrega.
                UauGoEngine.send(carContext, code)
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
        // Destinos: casa, salvos e recentes, sem tocar no celular.
        // 12/11: lupa ("Para onde?") e porta vermelha (sair), iguais aos do celular.
        sb.addAction(Action.Builder()
            .setIcon(icon(R.drawable.car_search))
            .setOnClickListener { screenManager.push(DestinationsScreen(carContext)) }
            .build())
        val strip = sb
            .addAction(Action.Builder()
                .setIcon(CarIcon.Builder(IconCompat.createWithResource(carContext, R.drawable.car_exit))
                    .setTint(androidx.car.app.model.CarColor.RED).build())
                .setOnClickListener { UauGoEngine.send(carContext, "stop") }
                .build())
            .build()
        // Zoom do mapa do carro: o motorista escolhe (+/−).
        fun zoom(res: Int, step: Float) = Action.Builder()
            .setIcon(icon(res))
            .setOnClickListener {
                CarState.zoomOffset = (CarState.zoomOffset + step).coerceIn(-4f, 3f)
                if (carMap.running) carMap.update()
            }
            .build()
        // Estrada em 3D: mapa <-> 3D sempre ("nas saídas" oculto por enquanto).
        val view3d = Action.Builder()
            .setIcon(icon(if (CarState.mode3d == 2) R.drawable.car_map else R.drawable.car_3d_text))
            .setOnClickListener {
                setMode3d(if (CarState.mode3d == 2) 0 else 2)
                toast(when (CarState.mode3d) {
                    0 -> if (CarState.en) "Map view" else "Só mapa"
                    1 -> if (CarState.en) "3D at exits" else "3D nas saídas"
                    else -> if (CarState.en) "3D always" else "3D sempre"
                })
            }
            .build()
        // Bússola: o motorista escolhe norte para cima ou o mapa girando com o carro.
        val compass = Action.Builder()
            .setIcon(icon(R.drawable.car_compass))
            .setOnClickListener {
                CarState.northUp = !CarState.northUp
                carContext.getSharedPreferences("car", android.content.Context.MODE_PRIVATE)
                    .edit().putBoolean("northUp", CarState.northUp).apply()
                toast(if (CarState.northUp) {
                    if (CarState.en) "North up" else "Norte para cima"
                } else {
                    if (CarState.en) "Map follows the car" else "Mapa na direção do carro"
                })
                if (carMap.running) carMap.update()
            }
            .build()
        // 3D primeiro: em tela baixa o último botão ficava escondido embaixo.
        val mapStrip = ActionStrip.Builder()
            .addAction(view3d)
            .addAction(compass)
            .addAction(zoom(R.drawable.car_zoom_in, 1f))
            .addAction(zoom(R.drawable.car_zoom_out, -1f))
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
            hit == "to3d" -> setMode3d(2)
            hit == "requests" -> screenManager.push(GroupRequestScreen(carContext))
            hit == "sos" -> sosTap()
            hit?.startsWith("do:") == true -> CarState.actionSink?.invoke(hit.removePrefix("do:"))
            hit == "toggleview" -> CarState.actionSink?.invoke("toggleview")
            // ♪ abre/fecha o mini player no próprio mapa (como no celular).
            hit == "music" -> carMap.toggleMusic()
            hit == "mprev" || hit == "mtoggle" || hit == "mnext" -> {
                CarMedia.command(carContext, when (hit) { "mprev" -> "previous"; "mnext" -> "next"; else -> "toggle" })
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ carMap.update() }, 500)
            }
            hit == "settings" -> screenManager.push(CarSettingsScreen(carContext))
            hit == "bannertap" -> {
                val sink = CarState.actionSink
                if (sink == null) toast(if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular") else sink("bannertap")
            }
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
                val rot = if (CarState.northUp) 0.0 else Math.toRadians(-CarState.bearing)
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
/** Busca de destino novo no carro: o app (Dart) procura e devolve a lista. */
class SearchPlaceScreen(ctx: CarContext) : Screen(ctx) {
    private var query = ""

    init {
        CarState.searchResults = emptyList()
        CarState.onSearchResults = { invalidate() }
    }

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        val res = CarState.searchResults
        if (res.isEmpty()) {
            list.setNoItemsMessage(when {
                CarState.searching -> if (CarState.en) "Searching…" else "Buscando…"
                query.isNotEmpty() -> if (CarState.en) "Nothing found" else "Nada encontrado"
                else -> if (CarState.en) "Type or say the place" else "Digite ou fale o lugar"
            })
        }
        for ((id, name, addr) in res.take(6)) {
            val row = Row.Builder().setTitle(name)
            if (addr.isNotEmpty()) row.addText(addr)
            row.setOnClickListener {
                val sink = CarState.actionSink
                if (sink == null) {
                    CarToast.makeText(carContext,
                        if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular",
                        CarToast.LENGTH_LONG).show()
                } else {
                    sink("place:$id|$name")
                    CarToast.makeText(carContext,
                        if (CarState.en) "Calculating route…" else "Calculando a rota…",
                        CarToast.LENGTH_SHORT).show()
                }
                CarState.onSearchResults = null
                screenManager.popToRoot()
            }
            list.addItem(row.build())
        }
        return SearchTemplate.Builder(object : SearchTemplate.SearchCallback {
            override fun onSearchTextChanged(searchText: String) {}
            override fun onSearchSubmitted(searchText: String) {
                val t = searchText.trim()
                if (t.length < 3) return
                query = t
                CarState.searching = true
                CarState.searchResults = emptyList()
                invalidate()
                val sink = CarState.actionSink
                if (sink == null) {
                    CarState.searching = false
                    CarToast.makeText(carContext,
                        if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular",
                        CarToast.LENGTH_LONG).show()
                } else {
                    sink("search:$t")
                }
            }
        })
            .setHeaderAction(Action.BACK)
            .setSearchHint(if (CarState.en) "Where to?" else "Para onde?")
            .setShowKeyboardByDefault(true)
            .setItemList(list.build())
            .setLoading(false)
            .build()
    }
}

/** Destinos para escolher no carro (casa, salvos, recentes). */
class DestinationsScreen(ctx: CarContext) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        // Destino novo: busca pelo nome (teclado ou voz do carro).
        list.addItem(Row.Builder()
            .setTitle(if (CarState.en) "Search a new place" else "Buscar outro destino")
            .setOnClickListener { screenManager.push(SearchPlaceScreen(carContext)) }
            .build())
        // Navegando: paradas no caminho (o destino continua o mesmo, 12/11).
        val navigating = CarState.nav != null
        if (navigating) {
            list.addItem(Row.Builder()
                .setTitle(if (CarState.en) "📍 Add a stop on the way" else "📍 Parada no caminho")
                .addText(if (CarState.en) "Gas, food, coffee… keeps the destination"
                    else "Posto, comida, café… o destino continua")
                .setOnClickListener { screenManager.push(StopKindsScreen(carContext)) }
                .build())
        }
        val all = CarState.destinations
        if (all.isEmpty()) {
            list.setNoItemsMessage(if (CarState.en) "Save places or search on the phone first"
                else "Salve locais ou busque no celular antes")
        }
        for ((name, lat, lng) in all.take(if (navigating) 4 else 5)) {
            list.addItem(Row.Builder()
                .setTitle(name)
                .setOnClickListener {
                    // Navegando: perguntar se é parada no caminho ou destino novo.
                    if (navigating) {
                        screenManager.push(StopOrGoScreen(carContext, name, lat, lng))
                        return@setOnClickListener
                    }
                    val geo = "geo:$lat,$lng?q=" + android.net.Uri.encode(name.replace("(", " ").replace(")", " "))
                    UauGoEngine.send(carContext, "navigate:$geo")
                    CarToast.makeText(carContext,
                        if (CarState.en) "Calculating route…" else "Calculando a rota…",
                        CarToast.LENGTH_SHORT).show()
                    screenManager.pop()
                }
                .build())
        }
        return ListTemplate.Builder()
            .setTitle(if (CarState.en) "Go to" else "Destinos")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Confirmar/corrigir velocidade ou radar (toque na faixa amarela), como no
 *  celular. O carro limita listas a ~6 linhas: velocidades em duas páginas. */
class SpeedEditScreen(ctx: CarContext, private val q: SpeedEdit,
                      private val page: Int = 0) : Screen(ctx) {
    private fun pick(v: Int) {
        CarState.actionSink?.invoke("speedpick:$v")
        screenManager.popToRoot()
    }

    override fun onGetTemplate(): Template {
        val en = CarState.en
        val list = ItemList.Builder()
        fun row(t: String, sub: String? = null, click: () -> Unit) {
            val r = Row.Builder().setTitle(t)
            if (sub != null) r.addText(sub)
            list.addItem(r.setOnClickListener(click).build())
        }
        when (page) {
            0 -> {
                if (q.current != null) row(if (en) "✅ Confirm ${q.current} km/h" else "✅ Confirmar ${q.current} km/h") { pick(q.current) }
                if (q.radar) row(if (en) "🚫 Radar does not exist" else "🚫 Radar não existe") { pick(0) }
                row(if (en) "Correct to 20 – 60 km/h" else "Corrigir para 20 a 60 km/h") {
                    screenManager.push(SpeedEditScreen(carContext, q, 1))
                }
                row(if (en) "Correct to 70 – 120 km/h" else "Corrigir para 70 a 120 km/h") {
                    screenManager.push(SpeedEditScreen(carContext, q, 2))
                }
            }
            else -> {
                val vs = if (page == 1) listOf(20, 30, 40, 50, 60) else listOf(70, 80, 90, 100, 110, 120)
                for (v in vs) row("$v km/h") { pick(v) }
            }
        }
        return ListTemplate.Builder()
            .setTitle(if (page == 0) q.title else (if (en) "Correct speed" else "Corrigir velocidade"))
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Configurações no carro (⚙): as mesmas do celular, em seções. */
class CarSettingsScreen(ctx: CarContext) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        val list = ItemList.Builder()
        for ((idx, sec) in CarState.cfg.withIndex()) {
            list.addItem(Row.Builder().setTitle(sec.title)
                .setBrowsable(true)
                .setOnClickListener { screenManager.push(CarSettingsSection(carContext, idx)) }
                .build())
        }
        list.addItem(Row.Builder().setTitle(if (en) "Car screen" else "Tela do carro")
            .setBrowsable(true)
            .setOnClickListener { screenManager.push(CarSettingsSection(carContext, -1)) }
            .build())
        if (CarState.cfg.isEmpty()) list.setNoItemsMessage(if (en) "Open UauGo on the phone" else "Abra o UauGo no celular")
        return ListTemplate.Builder()
            .setTitle(if (en) "Settings" else "Configurações")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Uma seção das configurações; -1 = só do carro (norte para cima). */
class CarSettingsSection(ctx: CarContext, private val idx: Int) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        val list = ItemList.Builder()
        fun refresh() = android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ invalidate() }, 1200)
        val title: String
        if (idx < 0) {
            title = if (en) "Car screen" else "Tela do carro"
            list.addItem(Row.Builder().setTitle(if (en) "North up" else "Norte para cima")
                .addText(if (en) "Off: map turns with the car" else "Desligado: o mapa gira com o carro")
                .setToggle(androidx.car.app.model.Toggle.Builder { v ->
                    CarState.northUp = v
                    carContext.getSharedPreferences("car", android.content.Context.MODE_PRIVATE)
                        .edit().putBoolean("northUp", v).apply()
                }.setChecked(CarState.northUp).build()).build())
        } else {
            val sec = CarState.cfg.getOrNull(idx)
            title = sec?.title ?: ""
            for (it in sec?.items.orEmpty()) {
                val choice = it.key.contains('=')
                val r = Row.Builder().setTitle(it.title)
                if (it.sub.isNotEmpty()) r.addText(it.sub)
                if (choice) {
                    // Escolha entre várias: tocar marca esta (✓ na marcada).
                    r.setTitle((if (it.on) "✓  " else "     ") + it.title)
                    r.setOnClickListener {
                        CarState.actionSink?.invoke("cfg:${it.key}:1")
                        refresh()
                    }
                } else {
                    r.setToggle(androidx.car.app.model.Toggle.Builder { v ->
                        CarState.actionSink?.invoke("cfg:${it.key}:${if (v) 1 else 0}")
                        refresh()
                    }.setChecked(it.on).build())
                }
                list.addItem(r.build())
            }
        }
        return ListTemplate.Builder()
            .setTitle(title)
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Música (botão ♪ do carro): o que toca no celular e os comandos. */
class MusicScreen(ctx: CarContext) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        val list = ItemList.Builder()
        val now = CarMedia.now(carContext)
        when {
            !CarMedia.hasAccess(carContext) -> list.setNoItemsMessage(
                if (en) "Allow music access in UauGo on the phone (Settings)"
                else "Libere o acesso à música no UauGo do celular (Configurações)")
            now == null -> list.setNoItemsMessage(
                if (en) "Nothing playing. Start music in your music app."
                else "Nada tocando. Abra seu app de música (Spotify, YouTube Music...).")
            else -> {
                fun row(t: String, cmd: String) = list.addItem(Row.Builder().setTitle(t)
                    .setOnClickListener {
                        CarMedia.command(carContext, cmd)
                        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ invalidate() }, 600)
                    }.build())
                list.addItem(Row.Builder()
                    .setTitle(now.title.ifEmpty { now.app })
                    .addText(listOf(now.artist, now.app).filter { it.isNotEmpty() }.joinToString(" · "))
                    .build())
                row(if (now.playing) (if (en) "⏸  Pause" else "⏸  Pausar") else (if (en) "▶  Play" else "▶  Tocar"), "toggle")
                row(if (en) "⏭  Next" else "⏭  Próxima", "next")
                row(if (en) "⏮  Previous" else "⏮  Anterior", "previous")
            }
        }
        return ListTemplate.Builder()
            .setTitle(if (en) "Music" else "Música")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Pergunta Sim/Não vinda do celular (ex.: continuar a rota ao voltar ao carro). */
class AskScreen(ctx: CarContext, private val title: String, private val text: String) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        fun answer(code: String) {
            CarState.actionSink?.invoke(code)
            screenManager.pop()
        }
        return MessageTemplate.Builder(text)
            .setTitle(title)
            .setHeaderAction(Action.APP_ICON)
            .addAction(Action.Builder()
                .setTitle(if (en) "Yes, continue" else "Sim, continuar")
                .setFlags(Action.FLAG_PRIMARY)
                .setOnClickListener { answer("resume:yes") }
                .build())
            .addAction(Action.Builder()
                .setTitle(if (en) "No" else "Não")
                .setOnClickListener { answer("resume:no") }
                .build())
            .build()
    }
}

/** Tipos de parada oferecidos no carro: (categoria do app, nome pt, nome en). */
val STOP_KINDS = listOf(
    Triple("fuel", "⛽ Posto", "⛽ Gas station"),
    Triple("food", "🍽️ Restaurante", "🍽️ Restaurant"),
    Triple("cafe", "☕ Café", "☕ Coffee"),
    Triple("pharmacy", "💊 Farmácia", "💊 Pharmacy"),
    Triple("tire", "🛞 Borracharia", "🛞 Tire repair"),
    Triple("lodging", "🛏️ Hospedagem", "🛏️ Lodging"),
)

/** Que tipo de parada procurar à frente na rota. */
class StopKindsScreen(ctx: CarContext) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        // Elétrico/plug-in: eletroposto em primeiro (12/11).
        val kinds = if (CarState.ev) listOf(Triple("charger", "⚡ Eletroposto", "⚡ EV charger")) + STOP_KINDS.take(5) else STOP_KINDS
        for ((cat, pt, en) in kinds) {
            val t = if (CarState.en) en else pt
            list.addItem(Row.Builder()
                .setTitle(t)
                .setOnClickListener { screenManager.push(FindStopScreen(carContext, cat, t)) }
                .build())
        }
        return ListTemplate.Builder()
            .setTitle(if (CarState.en) "Stop on the way" else "Parada no caminho")
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

/** Envia ao app (celular) ou avisa para abrir o UauGo. */
private fun sendToApp(ctx: CarContext, code: String): Boolean {
    val sink = CarState.actionSink
    if (sink == null) {
        CarToast.makeText(ctx,
            if (CarState.en) "Open UauGo on the phone" else "Abra o UauGo no celular",
            CarToast.LENGTH_LONG).show()
        return false
    }
    sink(code)
    return true
}

/** Lugares de um tipo à frente na rota; tocar inclui como próxima parada. */
class FindStopScreen(ctx: CarContext, private val cat: String, private val title: String) : Screen(ctx) {
    init {
        CarState.searchResults = emptyList()
        CarState.searching = true
        CarState.onSearchResults = { invalidate() }
        if (!sendToApp(ctx, "findstop:$cat")) CarState.searching = false
    }

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        val res = CarState.searchResults
        if (res.isEmpty() && !CarState.searching) {
            list.setNoItemsMessage(if (CarState.en) "Nothing found ahead" else "Nada encontrado à frente")
        }
        for ((id, name, info) in res.take(6)) {
            val row = Row.Builder().setTitle(name)
            if (info.isNotEmpty()) row.addText(info)
            row.setOnClickListener {
                if (sendToApp(carContext, "stopat:$id|$name")) {
                    CarToast.makeText(carContext,
                        if (CarState.en) "Adding stop…" else "Incluindo a parada…",
                        CarToast.LENGTH_SHORT).show()
                }
                CarState.onSearchResults = null
                screenManager.popToRoot()
            }
            list.addItem(row.build())
        }
        return ListTemplate.Builder()
            .setTitle(title)
            .setHeaderAction(Action.BACK)
            .apply { if (CarState.searching && res.isEmpty()) setLoading(true) else setSingleList(list.build()) }
            .build()
    }
}

/** Destino salvo escolhido navegando: parada no caminho ou novo destino. */
class StopOrGoScreen(ctx: CarContext, private val name: String,
                     private val lat: Double, private val lng: Double) : Screen(ctx) {
    override fun onGetTemplate(): Template {
        val en = CarState.en
        val list = ItemList.Builder()
        list.addItem(Row.Builder()
            .setTitle(if (en) "📍 Add as a stop on the way" else "📍 Parar no caminho")
            .addText(if (en) "Keeps the current destination" else "O destino atual continua")
            .setOnClickListener {
                if (sendToApp(carContext, "stopat:$lat,$lng|$name")) {
                    CarToast.makeText(carContext,
                        if (en) "Adding stop…" else "Incluindo a parada…",
                        CarToast.LENGTH_SHORT).show()
                }
                screenManager.popToRoot()
            }
            .build())
        list.addItem(Row.Builder()
            .setTitle(if (en) "🏁 Go there instead" else "🏁 Ir direto para lá")
            .addText(if (en) "Replaces the destination" else "Troca o destino")
            .setOnClickListener {
                val geo = "geo:$lat,$lng?q=" + android.net.Uri.encode(name.replace("(", " ").replace(")", " "))
                UauGoEngine.send(carContext, "navigate:$geo")
                CarToast.makeText(carContext,
                    if (en) "Calculating route…" else "Calculando a rota…",
                    CarToast.LENGTH_SHORT).show()
                screenManager.popToRoot()
            }
            .build())
        return ListTemplate.Builder()
            .setTitle(name)
            .setHeaderAction(Action.BACK)
            .setSingleList(list.build())
            .build()
    }
}

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
