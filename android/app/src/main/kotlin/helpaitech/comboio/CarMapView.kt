// ============================================================================
// CarMapView.kt — Mapa do Google na tela do carro (Android Auto)
//
// O que faz: Desenha um mapa de verdade (Google Maps) na superfície da tela
//   do carro: uma "tela virtual" do Android recebe uma Presentation com um
//   MapView. O mapa segue o piloto (girado para a frente, inclinado), com a
//   rota em azul, a seta do piloto, a velocidade, a placa do limite e o aviso
//   de radar por cima. Os dados vêm do CarState (alimentado pelo celular).
//   Por cima do mapa pode entrar a estrada em 3D (Car3DView), conforme
//   CarState.mode3d: nas saídas vai de 400 m antes a 400 m depois da manobra.
// Quem usa: NavScreen (UauGoCarAppService.kt). Se o mapa falhar, a tela
//   volta para o desenho simples (MapRenderer).
// ============================================================================

package helpaitech.comboio

import android.app.Presentation
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.view.Gravity
import android.view.Surface
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.MapsInitializer
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions
import com.google.android.gms.maps.model.Polyline
import com.google.android.gms.maps.model.PolylineOptions
import kotlin.math.max

/** Estilo noturno do mapa (fundo escuro, ruas e nomes claros). */
/** Sem os nomes de lugares (opção "Nomes de lugares no mapa do carro"). */
private const val NO_PLACES = """{"featureType":"poi","elementType":"labels.text","stylers":[{"visibility":"off"}]},
{"featureType":"transit","elementType":"labels.text","stylers":[{"visibility":"off"}]},"""

/** Estilo do mapa: noite/dia e, se pedido, sem nomes de lugares. */
private fun styleFor(dark: Boolean, places: Boolean): String {
    val base = if (dark) NIGHT else DAY
    return if (places) base else "[" + NO_PLACES + base.trim().removePrefix("[")
}

/** 23/11 (comparando com o Waze no painel da moto): mapa limpo, sem nomes
 *  de bairro, comércio e ônibus; só as ruas.
 *  Dia: nomes em cinza, mais discretos (12/11: "bem sutil"). Dia e noite sem
 *  as plaquinhas de número de rodovia (15/11: dezenas de "SP-330"/"050"). */
private const val DAY = """[
{"featureType":"administrative.neighborhood","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"administrative.land_parcel","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"poi.business","stylers":[{"visibility":"off"}]},
{"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"simplified"}]},
{"elementType":"labels.text.fill","stylers":[{"color":"#6b7584"}]},
{"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]"""

private const val NIGHT = """[
{"featureType":"administrative.neighborhood","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"administrative.land_parcel","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"poi.business","stylers":[{"visibility":"off"}]},
{"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
{"featureType":"road.local","elementType":"labels","stylers":[{"visibility":"simplified"}]},
{"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
{"elementType":"labels.text.fill","stylers":[{"color":"#d0dcef"}]},
{"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
{"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#4b6878"}]},
{"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#162338"}]},
{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},
{"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},
{"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#a9bcd8"}]},
{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},
{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
{"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}
]"""

/** Mapa do Google desenhado na tela do carro. */
/** Escala das letras do mapa do carro (1 = padrão do Google). */
const val MAP_FONT_SCALE = 0.85f

/** Densidade do mapa do carro: o Google desenha nomes de rua pela densidade
 *  da tela (a escala de letra quase não muda de perto). 0,75 = letras ~3
 *  pontos menores; o zoom compensa para mostrar a mesma área (12/11). */
const val MAP_DENSITY_SCALE = 0.42f

/** Inclinação do mapa do carro seguindo a direção (17/11: 45 -> 60, como o
 *  Google Maps no Android Auto). */
const val CAR_TILT = 60f

/** Largura da linha da rota (e do trânsito por cima dela) no mapa do carro.
 *  23/11: 4 -> 1,5 ("tosca", grossa demais na tela do carro); 26/11: 1. */
const val ROUTE_WIDTH_PX = 1f

/** Tamanho do veículo no mapa do carro (px). 23/11: 56 -> 38 ("muito
 *  grande"); 26/11: 52 (pedido: maior, com a rota mais fina); 26/11
 *  noite: 72 ("ficou pequeno" no carro). */
const val CAR_VEHICLE_PX = 72
val MAP_ZOOM_FIX = (Math.log(1.0 / MAP_DENSITY_SCALE) / Math.log(2.0)).toFloat()

class CarMapView(private val context: Context) {
    private var display: VirtualDisplay? = null
    private var presentation: Presentation? = null
    private var mapView: MapView? = null
    private var map: GoogleMap? = null
    private var routeLine: Polyline? = null
    private val trafficLines = mutableListOf<Polyline>()
    private var trafficDrawn: Any? = null
    private var routeSig = 0
    private var trimIdx = 0
    private var poiSig = 0
    private val poiMarkers = mutableListOf<com.google.android.gms.maps.model.Marker>()
    private val poiIcons = HashMap<Int, com.google.android.gms.maps.model.BitmapDescriptor>()
    private var hazardSig = 0
    private val hazardMarkers = mutableListOf<Marker>()
    private val hazardIcons = HashMap<String, com.google.android.gms.maps.model.BitmapDescriptor>()
    private var poisShown = true

    /** Alertas da comunidade, com o emoji do tipo (como no celular). */
    private fun drawHazards(g: GoogleMap) {
        val list = CarState.hazards
        val sig = list.hashCode()
        if (sig == hazardSig) return
        hazardSig = sig
        hazardMarkers.forEach { it.remove() }
        hazardMarkers.clear()
        for (h in list) {
            val icon = hazardIcons.getOrPut(h.emoji) {
                BitmapDescriptorFactory.fromBitmap(pinBitmap(h.emoji, Color.rgb(245, 166, 35)))
            }
            g.addMarker(MarkerOptions().position(LatLng(h.lat, h.lng)).anchor(0.5f, 0.5f)
                // Acima do veículo: quem marca está em cima do próprio alerta.
                .icon(icon).zIndex(6f))?.let { hazardMarkers.add(it) }
        }
    }

    private val memberMarkers = mutableListOf<com.google.android.gms.maps.model.Marker>()
    private val memberIcons = HashMap<String, com.google.android.gms.maps.model.BitmapDescriptor>()

    /** Colegas do comboio (bolinha laranja com o nome), como no celular. */
    private fun drawMembers(g: GoogleMap) {
        val list = if (CarState.groupOn) CarState.members else emptyList()
        while (memberMarkers.size > list.size) memberMarkers.removeAt(memberMarkers.size - 1).remove()
        for ((i, m) in list.withIndex()) {
            val icon = memberIcons.getOrPut(m.name) { BitmapDescriptorFactory.fromBitmap(memberBitmap(m.name)) }
            if (i < memberMarkers.size) {
                memberMarkers[i].position = LatLng(m.lat, m.lng)
                memberMarkers[i].setIcon(icon)
            } else {
                g.addMarker(MarkerOptions().position(LatLng(m.lat, m.lng)).anchor(0.5f, 0.85f)
                    .icon(icon).zIndex(4.5f))?.let { memberMarkers.add(it) }
            }
        }
    }

    private fun memberBitmap(name: String): Bitmap {
        val t = Paint().apply { textSize = 22f; isAntiAlias = true; color = Color.WHITE; isFakeBoldText = true }
        val label = name.take(14)
        val tw = t.measureText(label)
        val w = (tw + 24).toInt().coerceAtLeast(52)
        val h = 74
        val b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawRoundRect(android.graphics.RectF(0f, 0f, w.toFloat(), 30f), 10f, 10f,
            Paint().apply { color = Color.argb(220, 15, 27, 45); isAntiAlias = true })
        c.drawText(label, (w - tw) / 2f, 22f, t)
        c.drawCircle(w / 2f, 54f, 17f, Paint().apply { color = Color.WHITE; isAntiAlias = true })
        c.drawCircle(w / 2f, 54f, 13f, Paint().apply { color = Color.rgb(255, 122, 26); isAntiAlias = true })
        return b
    }

    /** Pins de radares e postos policiais (só redesenha quando mudam). */
    private fun drawPois(g: com.google.android.gms.maps.GoogleMap) {
        val list = CarState.pois
        val sig = list.size * 31 + (list.firstOrNull()?.contentHashCode() ?: 0)
        if (sig == poiSig) return
        poiSig = sig
        poiMarkers.forEach { it.remove() }
        poiMarkers.clear()
        for (p in list) {
            val kind = p[2].toInt()
            val icon = poiIcons.getOrPut(kind) {
                val (emoji, color) = when (kind) {
                    1 -> "📸" to Color.rgb(211, 47, 47)
                    2 -> "⏱️" to Color.rgb(211, 47, 47)
                    3 -> "🚦" to Color.rgb(211, 47, 47)
                    5 -> "⚡" to Color.rgb(46, 125, 50)
                    else -> "🚔" to Color.rgb(21, 101, 192)
                }
                BitmapDescriptorFactory.fromBitmap(pinBitmap(emoji, color))
            }
            g.addMarker(MarkerOptions().position(LatLng(p[0], p[1])).anchor(0.5f, 0.5f)
                .icon(icon).zIndex(4f).visible(poisShown))?.let { poiMarkers.add(it) }
        }
    }

    private fun pinBitmap(emoji: String, ring: Int): Bitmap {
        val px = 44
        val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawCircle(px / 2f, px / 2f, px / 2f - 2, Paint().apply { color = Color.WHITE; isAntiAlias = true })
        c.drawCircle(px / 2f, px / 2f, px / 2f - 2, Paint().apply {
            color = ring; style = Paint.Style.STROKE; strokeWidth = 4f; isAntiAlias = true
        })
        c.drawText(emoji, px / 2f, px / 2f + 8f, Paint().apply { textSize = 23f; textAlign = Paint.Align.CENTER; isAntiAlias = true })
        return b
    }

    /** Apaga da linha o trecho já percorrido (como no celular). A rota do
     *  carro vem com pontos espaçados (até centenas de metros na estrada):
     *  mede a distância até cada TRECHO, não até os pontos. */
    private fun trimPassed(pts: List<DoubleArray>, pos: LatLng) {
        val line = routeLine ?: return
        if (pts.size < 2) return
        val k = Math.cos(Math.toRadians(pos.latitude))
        var best = -1
        var bestD = Double.MAX_VALUE
        // Longe do ponto guardado (a simulação voltou ou pulou): procura na
        // rota inteira, para redesenhar o trecho certo.
        val p0 = pts[minOf(trimIdx, pts.size - 1)]
        val far = Math.abs(p0[0] - pos.latitude) + Math.abs(p0[1] - pos.longitude) > 0.05
        val start = if (far) 0 else trimIdx
        val end = if (far) pts.size - 1 else minOf(pts.size - 1, trimIdx + 300)
        for (i in start until end) {
            // Trecho i -> i+1 em metros, com o piloto na origem.
            val ax = (pts[i][1] - pos.longitude) * 111320.0 * k
            val ay = (pts[i][0] - pos.latitude) * 111320.0
            val bx = (pts[i + 1][1] - pos.longitude) * 111320.0 * k
            val by = (pts[i + 1][0] - pos.latitude) * 111320.0
            val dx = bx - ax
            val dy = by - ay
            val len2 = dx * dx + dy * dy
            val t = if (len2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / len2).coerceIn(0.0, 1.0)
            val px = ax + t * dx
            val py = ay + t * dy
            val d = px * px + py * py
            if (d < bestD) { bestD = d; best = i }
        }
        // Só apaga com o piloto na rota (até 60 m do trecho).
        if (best < 0 || bestD > 60.0 * 60.0) {
            // Não achou à frente: pode ter voltado alguns km.
            if (trimIdx > 0 && !far) trimIdx = 0
            return
        }
        trimIdx = best
        line.points = listOf(pos) + pts.subList(best + 1, pts.size).map { LatLng(it[0], it[1]) }
    }

    private var me: Marker? = null
    private var overlay: CarOverlay? = null
    private var view3d: Car3DView? = null
    private var lastCamAt = 0L

    /** Modo "nas saídas": fica em 3D até faltar menos que isso para o destino. */
    private var exit3dUntil = -1.0

    private var root3d: FrameLayout? = null
    private var ctx3d: Context? = null

    /** Cria a cena ao entrar no 3D e libera ao sair; com ela na tela, o mapa
     *  do Google fica pausado (economia de memória no celular). */
    private fun set3d(on: Boolean) {
        if (on == (view3d != null)) return
        val root = root3d ?: return
        if (on) {
            val v = Car3DView(ctx3d ?: return)
            v.area = visible?.let { Rect(it.left, it.top, mapRight(it), it.bottom) }
            v.onMap = { onMode?.invoke(0) }
            v.dark = dark
            view3d = v
            // Entre o mapa e os avisos do carro. Invisível até a cena carregar
            // (antes ficava uns 8 s de tela preta); só então pausa o mapa.
            v.view.alpha = 0f
            v.onShown = {
                if (view3d === v) {
                    v.view.alpha = 1f
                    runCatching { mapView?.onPause() }
                }
            }
            val pw = panelW(visible ?: Rect(0, 0, width, height))
            root.addView(v.view, 1, FrameLayout.LayoutParams(if (pw > 0) width - pw else -1, -1,
                android.view.Gravity.START))
            overlay?.in3d = true
        } else {
            overlay?.in3d = false
            view3d?.let {
                root.removeView(it.view)
                runCatching { it.destroy() }
            }
            view3d = null
            runCatching { mapView?.onResume() }
        }
    }

    /** Mostra ou esconde a estrada em 3D. */
    private fun apply3d() {
        if (root3d == null) return
        val n = CarState.nav
        val on = when (CarState.mode3d) {
            0 -> false
            2 -> CarState.route.size >= 2
            else -> {
                if (n != null && n.meters <= 400 &&
                    Regex("ramp|fork|keep|roundabout").containsMatchIn(n.maneuver)) {
                    exit3dUntil = n.remainingM - n.meters - 400
                }
                val inside = n != null && exit3dUntil >= 0 && n.remainingM > exit3dUntil
                if (!inside) exit3dUntil = -1.0
                inside
            }
        }
        set3d(on)
        overlay?.hud3d = on
    }
    private var meIcon = ""
    private var visible: Rect? = null
    private var width = 0
    private var height = 0

    /** A superfície do carro chegou: cria a tela virtual com o mapa. */
    fun start(surface: Surface, w: Int, h: Int, dpi: Int): Boolean = try {
        stop()
        width = w
        height = h
        MapsInitializer.initialize(context)
        val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val vd = dm.createVirtualDisplay(
            "UauGoCarMap", w, h, dpi, surface,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY)
        display = vd
        val p = Presentation(context, vd.display)
        // Letra grande do celular não vale aqui: o mapa do carro é outra tela.
        // 12/11: nomes de rua e bairro grandes demais na tela do carro:
        // ~3 pontos a menos que o padrão do Google (0,7).
        val cfg = android.content.res.Configuration(p.context.resources.configuration)
        cfg.fontScale = MAP_FONT_SCALE
        cfg.densityDpi = (dpi * MAP_DENSITY_SCALE).toInt()
        val mv = MapView(android.view.ContextThemeWrapper(p.context, 0).apply {
            applyOverrideConfiguration(cfg)
        })
        mv.onCreate(null)
        val root = FrameLayout(p.context)
        root.addView(mv, FrameLayout.LayoutParams(-1, -1))
        // Veículo desenhado por nós, fixo no centro da câmera (onde a linha
        // azul começa). O ícone do Google saía deslocado nesta tela virtual
        // com densidade reduzida: nas fotos do testador ficava sempre no mesmo
        // ponto ao lado da rota, longe do centro do mapa (15/11).
        val iv = android.widget.ImageView(p.context)
        iv.scaleType = android.widget.ImageView.ScaleType.FIT_XY
        iv.visibility = android.view.View.GONE
        root.addView(iv, FrameLayout.LayoutParams(CAR_VEHICLE_PX, CAR_VEHICLE_PX))
        meView = iv
        root3d = root
        ctx3d = p.context
        val ov = CarOverlay(p.context)
        overlay = ov
        root.addView(ov.root, FrameLayout.LayoutParams(-1, -1))
        p.setContentView(root)
        // A Presentation é um diálogo: sem isso a imagem sai escurecida.
        p.window?.apply {
            clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setDimAmount(0f)
            attributes = attributes.apply { alpha = 1f }
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.BLACK))
        }
        p.show()
        mv.onStart()
        mv.onResume()
        mv.getMapAsync { g ->
            map = g
            g.uiSettings.setAllGesturesEnabled(false)
            g.uiSettings.isMapToolbarEnabled = false
            g.uiSettings.isCompassEnabled = false
            g.isTrafficEnabled = false // o trânsito vai só na linha da rota
            g.isBuildingsEnabled = false // mais leve
            runCatching {
                g.setMapStyle(com.google.android.gms.maps.model.MapStyleOptions(styleFor(dark, CarState.placeNames)))
                stylePlaces = CarState.placeNames
            }
            applyPadding()
            // Sem posição ainda: Brasil inteiro, não o ponto 0,0 (Golfo da
            // Guiné aparecia na tela do carro nos primeiros segundos).
            if (!CarState.hasPosition) {
                g.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(-15.78, -47.93), 3.5f + MAP_ZOOM_FIX))
            }
            update()
        }
        presentation = p
        mapView = mv
        true
    } catch (e: Exception) {
        android.util.Log.w("UauGoCar", "Mapa do carro indisponível: $e")
        stop()
        false
    }

    private var dark = false
    /** Opção de nomes de lugares já aplicada ao estilo. */
    private var stylePlaces = true

    /** Noite no carro: mapa escuro com letras claras (exigência da Play). */
    fun setDark(on: Boolean) {
        view3d?.dark = on
        if (on == dark && map != null) return
        dark = on
        map?.let { g ->
            runCatching {
                g.setMapStyle(com.google.android.gms.maps.model.MapStyleOptions(styleFor(on, CarState.placeNames)))
                stylePlaces = CarState.placeNames
            }
        }
    }

    /** ♪ no carro: abre/fecha o mini player. */
    fun toggleMusic() {
        val ov = overlay ?: return
        ov.musicOpen = !ov.musicOpen
        ov.update()
    }

    /** Toque na tela do carro: "alert", "radar", "hazard:id" ou null. */
    fun tap(x: Float, y: Float): String? {
        overlay?.hit(x, y)?.let { return it }
        // No 3D o toque vai para a página (tocar no minimapa volta ao mapa).
        view3d?.let { it.tap(x, y); return null }
        return myHazardAt(x, y)
    }

    /** Troca pedida na tela do carro: 0 = mapa, 2 = 3D. */
    var onMode: ((Int) -> Unit)? = null

    /** Toque no ícone de um alerta do próprio piloto (como no celular). */
    private fun myHazardAt(x: Float, y: Float): String? {
        val g = map ?: return null
        if (view3d != null) return null
        val h = CarState.hazards.filter { it.mine }.minByOrNull {
            val p = g.projection.toScreenLocation(LatLng(it.lat, it.lng))
            Math.hypot((p.x - x).toDouble(), (p.y - y).toDouble())
        } ?: return null
        val p = g.projection.toScreenLocation(LatLng(h.lat, h.lng))
        return if (Math.hypot((p.x - x).toDouble(), (p.y - y).toDouble()) <= 36) "hazard:${h.id}" else null
    }

    /** Área livre da tela (fora dos cartões do Android Auto). */
    fun setVisibleArea(r: Rect) {
        visible = r
        lastPanel = -1
        view3d?.area = Rect(r.left, r.top, mapRight(r), r.bottom)
        overlay?.setArea(r, width)
        applyPadding()
        update()
    }

    /** A superfície foi embora (carro desligou, outra tela...). */
    fun stop() {
        ticker.removeCallbacks(glide)
        shownPos = null
        runCatching { mapView?.onPause(); mapView?.onStop(); mapView?.onDestroy() }
        runCatching { presentation?.dismiss() }
        runCatching { display?.release() }
        mapView = null
        presentation = null
        display = null
        map = null
        routeLine = null
        trafficLines.clear()
        trafficDrawn = null
        poiMarkers.clear()
        poiSig = 0
        hazardMarkers.clear()
        hazardSig = 0
        poisShown = true
        me = null
        overlay = null
        runCatching { view3d?.destroy() }
        view3d = null
        root3d = null
        ctx3d = null
        meView = null
        meViewIcon = ""
        exit3dUntil = -1.0
        meIcon = ""
        routeSig = 0
    }

    val running get() = map != null || presentation != null

    /** Novo estado do celular: rota, posição, velocidade, limite, aviso. */
    fun update() {
        syncPanel()
        val g = map ?: return
        // Opção "nomes de lugares" mudou no celular: refaz o estilo.
        if (stylePlaces != CarState.placeNames) runCatching {
            g.setMapStyle(com.google.android.gms.maps.model.MapStyleOptions(styleFor(dark, CarState.placeNames)))
            stylePlaces = CarState.placeNames
        }
        // Rota (só redesenha quando muda).
        val pts = CarState.route
        // O trecho detalhado perto do veículo muda o meio da lista (16/11):
        // o ponto do meio também entra na assinatura.
        val sig = pts.size * 31 + (pts.firstOrNull()?.contentHashCode() ?: 0) +
            (pts.lastOrNull()?.contentHashCode() ?: 0) +
            (pts.getOrNull(pts.size / 2)?.contentHashCode() ?: 0) * 7
        if (sig != routeSig) {
            routeSig = sig
            routeLine?.remove()
            trimIdx = 0
            routeLine = if (pts.size >= 2) g.addPolyline(
                PolylineOptions()
                    .addAll(pts.map { LatLng(it[0], it[1]) })
                    .color(Color.rgb(26, 115, 232)) // azul da rota do celular
                    // 17/11: 6 -> 4 px ("muito larga" no mapa do carro).
                    .width(ROUTE_WIDTH_PX)
                    .zIndex(2f)) else null
        }
        if (CarState.traffic !== trafficDrawn) {
            trafficDrawn = CarState.traffic
            trafficLines.forEach { it.remove() }
            trafficLines.clear()
            for ((level, line) in CarState.traffic) {
                trafficLines.add(g.addPolyline(PolylineOptions()
                    .addAll(line.map { LatLng(it[0], it[1]) })
                    .color(when (level) {
                        2 -> Color.rgb(211, 47, 47)
                        1 -> Color.rgb(249, 168, 37)
                        else -> Color.rgb(46, 160, 67)
                    })
                    .width(ROUTE_WIDTH_PX)
                    .zIndex(3f)))
            }
        }
        // Norte para cima liga/desliga: o veículo muda de altura na tela.
        if (CarState.northUp != paddedNorthUp) {
            paddedNorthUp = CarState.northUp
            applyPadding()
            placeMeView()
        }
        apply3d()
        overlay?.update()
        // 3D: a página encaixa Chegada e manobra no espaço real dos botões.
        view3d?.let { v ->
            overlay?.let { o -> v.setControls(o.speedRect(), o.buttonsRect()) }
        }
        if (view3d != null) { meView?.visibility = android.view.View.GONE; return } // mapa pausado: a cena 3D cobre a tela
        drawPois(g)
        drawHazards(g)
        drawMembers(g)
        if (!CarState.hasPosition) return
        // Última trava: navegando, o veículo vai SEMPRE para a linha azul que
        // está desenhada aqui (até 50 m dela), venha a posição do celular ou
        // do GPS do carro. Mesmo com as duas fontes encaixadas, o testador
        // ainda viu o ícone ao lado da rota na 1.2.10 (15/11).
        // Com rota desenhada (não só com manobra na tela: sem a próxima
        // manobra o "nav" fica vazio e a posição passava crua).
        // Celular seguindo a rota: encaixa até 150 m (o celular já decidiu
        // que está nela); senão só até 50 m.
        val snapMax = if (CarState.onRoute) 150.0 else 50.0
        val snap = if (pts.size >= 2) CarState.snapToRoute(CarState.lat, CarState.lng, snapMax) else null
        val pos = if (snap != null) LatLng(snap[0], snap[1]) else LatLng(CarState.lat, CarState.lng)
        logPos(pos, snap != null)
        // A linha começa onde o veículo ESTÁ na tela (não à frente dele).
        trimPassed(pts, shownPos ?: pos)
        // A imagem do veículo vem do celular (foto ou ícone configurado).
        val img = CarState.vehicleImage
        val iconKey = "${CarState.vehicle}|${img?.contentHashCode() ?: 0}"
        if (meIcon != iconKey) {
            me?.remove()
            me = null
            meIcon = iconKey
        }
        me = me ?: g.addMarker(
            MarkerOptions().position(shownPos ?: pos).anchor(0.5f, 0.5f)
                .icon(BitmapDescriptorFactory.fromBitmap(myVehicle(img))).zIndex(5f)
        )
        if (meViewIcon != iconKey) {
            meViewIcon = iconKey
            meView?.setImageBitmap(myVehicle(img))
        }
        // Ícone em pé (o mapa gira com o piloto).
        // Mais longe na rodovia, mais perto na cidade.
        // Mais afastado que antes (pedido do Ricardo); +/− do motorista somam.
        // Perto de uma saída/conversão (até 400 m), aproxima sozinho.
        val n = CarState.nav
        val nearTurn = n != null && n.meters < 400 && n.maneuver.isNotEmpty() && n.maneuver != "straight"
        // 23/11: 1,2 nível mais afastado (o mapa do carro ficava "grande",
        // pouca área à vista): 13,4/14,2/15,0 -> 12,2/13,0/13,8.
        val zoom = (when {
            CarState.speedKmh >= 90 -> 12.2f
            CarState.speedKmh >= 50 -> 13.0f
            else -> 13.8f
        } + CarState.zoomOffset + (if (nearTurn) 1.2f else 0f)).coerceIn(10f, 19f) + MAP_ZOOM_FIX
        // Mapa bem afastado: os radares viram um amontoado que cobre as ruas.
        val show = zoom >= 13f
        if (show != poisShown) {
            poisShown = show
            poiMarkers.forEach { it.isVisible = show }
        }
        // Veículo e câmera andam juntos, em passos pequenos, no tempo entre as
        // leituras (como no celular). Muito atrasado (celular ocupado): pula
        // direto para o lugar certo.
        // Visão COMBOIO: você e os colegas na tela, norte para cima.
        val mates = CarState.members
        if (CarState.convoyView && CarState.groupOn && mates.isNotEmpty()) {
            var s = pos.latitude; var n = pos.latitude; var w = pos.longitude; var e = pos.longitude
            for (m in mates) { s = minOf(s, m.lat); n = maxOf(n, m.lat); w = minOf(w, m.lng); e = maxOf(e, m.lng) }
            val c = LatLng((s + n) / 2, (w + e) / 2)
            val k = Math.cos(Math.toRadians(c.latitude))
            val spanM = maxOf((n - s) * 111320.0, (e - w) * 111320.0 * k, 300.0) * 1.6
            val dens = context.resources.displayMetrics.density
            val sizeDp = minOf(width, height) / dens
            val z = (Math.log(156543.03 * k * sizeDp / spanM) / Math.log(2.0)).toFloat()
                .coerceIn(8f, 16f) + MAP_ZOOM_FIX
            ticker.removeCallbacks(glide)
            shownPos = null
            me?.position = pos
            me?.isVisible = true
            meView?.visibility = android.view.View.GONE
            runCatching {
                g.animateCamera(CameraUpdateFactory.newCameraPosition(
                    CameraPosition.Builder().target(c).zoom(z).bearing(0f).tilt(0f).build()), 800, null)
            }
            return
        }
        me?.isVisible = false
        placeMeView()
        val now = android.os.SystemClock.uptimeMillis()
        val gap = now - lastCamAt
        lastCamAt = now
        glideFrom = shownPos ?: pos
        glideBearingFrom = shownBearing
        glideZoomFrom = shownZoom
        glideTo = pos
        glideBearingTo = if (CarState.northUp) 0f else CarState.bearing.toFloat()
        glideZoomTo = zoom
        glideStart = now
        glideMs = if (gap > 2500 || shownPos == null) 0L else gap.coerceIn(120L, 1100L)
        ticker.removeCallbacks(glide)
        glide.run()
    }

    private val ticker = android.os.Handler(android.os.Looper.getMainLooper())
    private var shownPos: LatLng? = null
    private var shownBearing = 0f
    private var shownZoom = 15f
    private var glideFrom: LatLng? = null
    private var glideTo: LatLng? = null
    private var glideBearingFrom = 0f
    private var glideBearingTo = 0f
    private var glideZoomFrom = 15f
    private var glideZoomTo = 15f
    private var glideStart = 0L
    private var glideMs = 0L

    /** Um passo do deslize (~20 por segundo: leve para celular simples). */
    private val glide = object : Runnable {
        override fun run() {
            val g = map ?: return
            val a = glideFrom ?: return
            val b = glideTo ?: return
            if (view3d != null) return
            val t = if (glideMs == 0L) 1f else
                ((android.os.SystemClock.uptimeMillis() - glideStart).toFloat() / glideMs).coerceAtMost(1f)
            val p0 = LatLng(a.latitude + (b.latitude - a.latitude) * t,
                a.longitude + (b.longitude - a.longitude) * t)
            // Na curva, a reta entre duas leituras corta a linha azul: o passo
            // vai para cima dela.
            val sp = if (t < 1f && CarState.route.size >= 2)
                CarState.snapToRoute(p0.latitude, p0.longitude, 30.0) else null
            val p = if (sp != null) LatLng(sp[0], sp[1]) else p0
            val turn = ((glideBearingTo - glideBearingFrom + 540f) % 360f) - 180f
            shownPos = p
            shownBearing = (glideBearingFrom + turn * t + 360f) % 360f
            shownZoom = glideZoomFrom + (glideZoomTo - glideZoomFrom) * t
            me?.position = p
            g.moveCamera(CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder().target(p).zoom(shownZoom)
                    .bearing(shownBearing).tilt(if (CarState.northUp) 0f else CAR_TILT).build()))
            if (t < 1f) ticker.postDelayed(this, 50)
        }
    }

    private var paddedNorthUp = false
    private var meView: android.widget.ImageView? = null
    private var meViewIcon = ""

    /** Veículo no centro da câmera: o mesmo ponto que [applyPadding] usa. */
    private fun placeMeView() {
        val iv = meView ?: return
        val r = visible ?: Rect(0, 0, width, height)
        val extraTop = extraTop(r)
        val cx = (r.left + extraLeft(r) + mapRight(r)) / 2f
        val cy = (r.top + extraTop + r.bottom) / 2f
        val lp = iv.layoutParams
        iv.translationX = cx - lp.width / 2f
        iv.translationY = cy - lp.height / 2f
        // Ícone "deitado" na estrada, acompanhando a inclinação do mapa
        // (17/11, como o carrinho do Google Maps no carro). Norte para cima:
        // mapa plano, ícone reto.
        iv.pivotX = lp.width / 2f
        iv.pivotY = lp.height / 2f
        iv.cameraDistance = 6000f * context.resources.displayMetrics.density
        iv.rotationX = if (CarState.northUp) 0f else CAR_TILT * 0.8f
        iv.visibility = android.view.View.VISIBLE
    }

    private val debuggable = (context.applicationInfo.flags and
        android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
    private var lastLogAt = 0L

    /** Só no UauGo2 (debug): de onde veio a posição e quanto foi encaixada. */
    private fun logPos(pos: LatLng, snapped: Boolean) {
        if (!debuggable) return
        val now = android.os.SystemClock.uptimeMillis()
        if (now - lastLogAt < 2000) return
        lastLogAt = now
        val k = Math.cos(Math.toRadians(pos.latitude))
        val dx = (CarState.lng - pos.longitude) * 111320.0 * k
        val dy = (CarState.lat - pos.latitude) * 111320.0
        val fromDart = System.currentTimeMillis() - CarState.lastDartUpdate < 3000
        // Diagnóstico B: onde o MAPA desenha a posição (centro da câmera)
        // e onde está o nosso ícone. Diferença = erro de desenho, não de GPS.
        val g = map
        val sp = shownPos ?: pos
        val onMap = g?.projection?.toScreenLocation(sp)
        val lineStart = routeLine?.points?.firstOrNull()?.let { g?.projection?.toScreenLocation(it) }
        val iv = meView
        val icon = if (iv != null) "${(iv.translationX + iv.width / 2f).toInt()},${(iv.translationY + iv.height / 2f).toInt()}" else "-"
        android.util.Log.d("UauGoCarPos", "src=${if (fromDart) "celular" else "gps-carro"} " +
            "onRoute=${CarState.onRoute} snapped=$snapped desvio=${Math.hypot(dx, dy).toInt()}m " +
            "rota=${CarState.route.size}pts area=$visible mapaDesenha=${onMap?.x},${onMap?.y} icone=$icon inicioLinha=${lineStart?.x},${lineStart?.y} " +
            "mapView=${mapView?.width}x${mapView?.height} sentido=${CarState.bearing.toInt()} camera=${shownBearing.toInt()}")
    }

    /** Área estreita (tela dividida do Android Auto): o velocímetro, o
     *  aviso de radar e os botões ocupam a coluna da esquerda e cobriam o
     *  veículo (painel, 16/11). Empurra o centro para a direita deles. */
    private fun extraLeft(r: Rect): Int =
        if (r.width() < 560) (r.width() * 0.30f).toInt() else 0

    /** Quanto o centro (e o veículo) desce na área livre. 17/11: como no
     *  Google Maps do carro, o veículo fica perto de baixo e a estrada à
     *  frente ocupa a tela (antes 0,35 = pouco abaixo do meio). Seguindo a
     *  direção; com o norte para cima, fica como antes. */
    private fun extraTop(r: Rect): Int {
        val h = r.height()
        if (CarState.northUp) return (h * 0.35f).toInt()
        // O veículo desce até logo acima da linha de botões do UauGo (56 dp
        // + margens): em tela baixa (800x480) a foto do piloto ficava atrás
        // dos botões (DHU, 17/11). Centro = (extraTop + h) / 2.
        val dens = context.resources.displayMetrics.density
        val lowest = h - 2 * ((CAR_BTN + 14 + 34) * dens).toInt()
        return maxOf((h * 0.35f).toInt(), minOf((h * 0.62f).toInt(), lowest))
    }

    /** Painel dos próximos passos (23/11): com rota, 40% da largura à
     *  direita, como no celular deitado. Tela dividida (estreita): sem painel. */
    private fun panelW(r: Rect): Int {
        if (CarState.route.size < 2 || CarState.nav == null || r.width() < 560) return 0
        // 24/11: minimizado = aba fina (coluna do Android Auto + 48 dp).
        val dens = context.resources.displayMetrics.density
        return if (CarState.stepsMin) maxOf(width - r.right, (96 * dens).toInt()) + (48 * dens).toInt()
        else (width * 0.4f).toInt()
    }

    /** Borda direita do mapa (antes do painel ou da coluna do Android Auto). */
    private fun mapRight(r: Rect): Int {
        val p = panelW(r)
        return if (p > 0) width - p else r.right
    }

    private var lastPanel = -1
    private var lastMin = false

    /** Liga/desliga o painel e ajusta mapa, veículo e 3D aos 60%. */
    private fun syncPanel() {
        val r = visible ?: Rect(0, 0, width, height)
        val p = panelW(r)
        if (p == lastPanel && CarState.stepsMin == lastMin) return
        lastPanel = p
        lastMin = CarState.stepsMin
        overlay?.setPanel(p, max(0, width - r.right), CarState.stepsMin)
        view3d?.let { v ->
            val lp = v.view.layoutParams as? FrameLayout.LayoutParams
            if (lp != null) {
                lp.width = if (p > 0) width - p else -1
                lp.gravity = android.view.Gravity.START
                v.view.layoutParams = lp
            }
            v.area = Rect(r.left, r.top, mapRight(r), r.bottom)
        }
        applyPadding()
        placeMeView()
    }

    /** O centro do mapa fica na área livre, mais para baixo (vê à frente). */
    private fun applyPadding() {
        val g = map ?: return
        val r = visible ?: Rect(0, 0, width, height)
        val extraTop = extraTop(r)
        g.setPadding(r.left + extraLeft(r), r.top + extraTop, max(0, width - mapRight(r)), max(0, height - r.bottom))
    }

    /** Seta do piloto (branca com borda azul), sempre apontando para cima. */
    private fun arrowBitmap(): Bitmap {
        val s = 72
        val b = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val path = Path().apply {
            moveTo(s / 2f, 4f); lineTo(s - 10f, s - 8f); lineTo(s / 2f, s * 0.70f); lineTo(10f, s - 8f); close()
        }
        c.drawPath(path, Paint().apply { color = Color.rgb(26, 115, 232); isAntiAlias = true })
        c.drawPath(path, Paint().apply {
            color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 6f; isAntiAlias = true
        })
        return b
    }

    /** A imagem mandada pelo celular; sem ela, o emoji do tipo do veículo. */
    private fun myVehicle(png: ByteArray?): Bitmap {
        val b = png?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size) }
            ?: return navArrowBitmap()
        // 26/11 noite: a imagem do celular tem muita margem transparente (a
        // moto ocupava ~40% do quadrado e ficava minúscula). Recorta a parte
        // desenhada e encaixa no quadrado, sem distorcer.
        val t = trimTransparent(b)
        val s = CAR_VEHICLE_PX
        val k = s.toFloat() / maxOf(t.width, t.height)
        val w = maxOf(1, (t.width * k).toInt()); val h = maxOf(1, (t.height * k).toInt())
        val out = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(Bitmap.createScaledBitmap(t, w, h, true),
            (s - w) / 2f, (s - h) / 2f, Paint(Paint.FILTER_BITMAP_FLAG))
        return out
    }

    /** Corta as bordas transparentes (alfa < 16). */
    private fun trimTransparent(b: Bitmap): Bitmap {
        val w = b.width; val h = b.height
        val px = IntArray(w * h); b.getPixels(px, 0, w, 0, 0, w, h)
        var l = w; var t = h; var r = -1; var bo = -1
        for (y in 0 until h) for (x in 0 until w) {
            if ((px[y * w + x] ushr 24) >= 16) {
                if (x < l) l = x; if (x > r) r = x; if (y < t) t = y; if (y > bo) bo = y
            }
        }
        if (r < l || bo < t) return b
        return Bitmap.createBitmap(b, l, t, r - l + 1, bo - t + 1)
    }

    /** Sem a imagem do celular (ainda não chegou): seta de navegação
     *  comum, laranja com borda branca (12/11: a moto emoji não deve aparecer). */
    private fun navArrowBitmap(): Bitmap {
        val px = 72
        val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        val path = android.graphics.Path().apply {
            moveTo(px / 2f, 8f)
            lineTo(px - 12f, px - 10f)
            lineTo(px / 2f, px - 24f)
            lineTo(12f, px - 10f)
            close()
        }
        c.drawPath(path, Paint().apply {
            color = Color.argb(70, 0, 0, 0); isAntiAlias = true
            maskFilter = android.graphics.BlurMaskFilter(5f, android.graphics.BlurMaskFilter.Blur.NORMAL)
        })
        c.drawPath(path, Paint().apply { color = Color.rgb(255, 122, 26); isAntiAlias = true })
        c.drawPath(path, Paint().apply {
            color = Color.WHITE; style = Paint.Style.STROKE; strokeWidth = 5f
            strokeJoin = Paint.Join.ROUND; isAntiAlias = true
        })
        return b
    }
}
