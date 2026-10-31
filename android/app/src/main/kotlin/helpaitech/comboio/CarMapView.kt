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

/** Mapa do Google desenhado na tela do carro. */
class CarMapView(private val context: Context) {
    private var display: VirtualDisplay? = null
    private var presentation: Presentation? = null
    private var mapView: MapView? = null
    private var map: GoogleMap? = null
    private var routeLine: Polyline? = null
    private var routeSig = 0
    private var trimIdx = 0
    private var poiSig = 0
    private val poiMarkers = mutableListOf<com.google.android.gms.maps.model.Marker>()
    private val poiIcons = HashMap<Int, com.google.android.gms.maps.model.BitmapDescriptor>()

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
                    else -> "🚔" to Color.rgb(21, 101, 192)
                }
                BitmapDescriptorFactory.fromBitmap(pinBitmap(emoji, color))
            }
            g.addMarker(MarkerOptions().position(LatLng(p[0], p[1])).anchor(0.5f, 0.5f)
                .icon(icon).zIndex(4f))?.let { poiMarkers.add(it) }
        }
    }

    private fun pinBitmap(emoji: String, ring: Int): Bitmap {
        val px = 64
        val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawCircle(px / 2f, px / 2f, px / 2f - 3, Paint().apply { color = Color.WHITE; isAntiAlias = true })
        c.drawCircle(px / 2f, px / 2f, px / 2f - 3, Paint().apply {
            color = ring; style = Paint.Style.STROKE; strokeWidth = 5f; isAntiAlias = true
        })
        c.drawText(emoji, px / 2f, px / 2f + 12f, Paint().apply { textSize = 34f; textAlign = Paint.Align.CENTER; isAntiAlias = true })
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
        val end = minOf(pts.size - 1, trimIdx + 300)
        for (i in trimIdx until end) {
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
        if (best < 0 || bestD > 60.0 * 60.0) return
        trimIdx = best
        line.points = listOf(pos) + pts.subList(best + 1, pts.size).map { LatLng(it[0], it[1]) }
    }

    private var me: Marker? = null
    private var overlay: CarOverlay? = null
    private var view3d: Car3DView? = null

    /** Modo "nas saídas": fica em 3D até faltar menos que isso para o destino. */
    private var exit3dUntil = -1.0

    /** Mostra ou esconde a estrada em 3D. */
    private fun apply3d() {
        val v = view3d ?: return
        val n = CarState.nav
        val on = when (CarState.mode3d) {
            0 -> false
            2 -> n != null && CarState.route.size >= 2
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
        v.show(on)
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
        val mv = MapView(p.context)
        mv.onCreate(null)
        val root = FrameLayout(p.context)
        root.addView(mv, FrameLayout.LayoutParams(-1, -1))
        val v3 = Car3DView(p.context)
        v3.area = visible
        view3d = v3
        root.addView(v3.view, FrameLayout.LayoutParams(-1, -1))
        val ov = CarOverlay(p.context)
        overlay = ov
        root.addView(ov.root, FrameLayout.LayoutParams(-1, -1))
        p.setContentView(root)
        p.show()
        mv.onStart()
        mv.onResume()
        mv.getMapAsync { g ->
            map = g
            g.uiSettings.setAllGesturesEnabled(false)
            g.uiSettings.isMapToolbarEnabled = false
            g.uiSettings.isCompassEnabled = false
            g.isTrafficEnabled = true // como no celular
            g.isBuildingsEnabled = false // mais leve
            applyPadding()
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

    /** Área livre da tela (fora dos cartões do Android Auto). */
    fun setVisibleArea(r: Rect) {
        visible = r
        view3d?.area = r
        applyPadding()
        update()
    }

    /** A superfície foi embora (carro desligou, outra tela...). */
    fun stop() {
        runCatching { mapView?.onPause(); mapView?.onStop(); mapView?.onDestroy() }
        runCatching { presentation?.dismiss() }
        runCatching { display?.release() }
        mapView = null
        presentation = null
        display = null
        map = null
        routeLine = null
        poiMarkers.clear()
        poiSig = 0
        me = null
        overlay = null
        runCatching { view3d?.destroy() }
        view3d = null
        exit3dUntil = -1.0
        meIcon = ""
        routeSig = 0
    }

    val running get() = map != null || presentation != null

    /** Novo estado do celular: rota, posição, velocidade, limite, aviso. */
    fun update() {
        val g = map ?: return
        // Rota (só redesenha quando muda).
        val pts = CarState.route
        val sig = pts.size * 31 + (pts.firstOrNull()?.contentHashCode() ?: 0) +
            (pts.lastOrNull()?.contentHashCode() ?: 0)
        if (sig != routeSig) {
            routeSig = sig
            routeLine?.remove()
            trimIdx = 0
            routeLine = if (pts.size >= 2) g.addPolyline(
                PolylineOptions()
                    .addAll(pts.map { LatLng(it[0], it[1]) })
                    .color(Color.rgb(26, 115, 232)) // azul da rota do celular
                    .width(11f)
                    .zIndex(2f)) else null
        }
        overlay?.update()
        apply3d()
        drawPois(g)
        if (!CarState.hasPosition) return
        val pos = LatLng(CarState.lat, CarState.lng)
        trimPassed(pts, pos)
        if (meIcon != CarState.vehicle) {
            me?.remove()
            me = null
            meIcon = CarState.vehicle
        }
        val m = me ?: g.addMarker(
            MarkerOptions().position(pos).anchor(0.5f, 0.5f)
                .icon(BitmapDescriptorFactory.fromBitmap(vehicleBitmap(meIcon))).zIndex(5f)
        )?.also { me = it }
        m?.position = pos
        // Ícone em pé (o mapa gira com o piloto).
        // Mais longe na rodovia, mais perto na cidade.
        // Mais afastado que antes (pedido do Ricardo); +/− do motorista somam.
        // Perto de uma saída/conversão (até 400 m), aproxima sozinho.
        val n = CarState.nav
        val nearTurn = n != null && n.meters < 400 && n.maneuver.isNotEmpty() && n.maneuver != "straight"
        val zoom = (when {
            CarState.speedKmh >= 90 -> 13.4f
            CarState.speedKmh >= 50 -> 14.2f
            else -> 15.0f
        } + CarState.zoomOffset + (if (nearTurn) 1.2f else 0f)).coerceIn(10f, 19f)
        g.animateCamera(
            CameraUpdateFactory.newCameraPosition(
                CameraPosition.Builder().target(pos).zoom(zoom)
                    .bearing(CarState.bearing.toFloat()).tilt(45f).build()),
            900, null)
    }

    /** O centro do mapa fica na área livre, mais para baixo (vê à frente). */
    private fun applyPadding() {
        val g = map ?: return
        val r = visible ?: Rect(0, 0, width, height)
        val extraTop = (r.height() * 0.35f).toInt()
        g.setPadding(r.left, r.top + extraTop, max(0, width - r.right), max(0, height - r.bottom))
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

    private fun vehicleBitmap(emoji: String): Bitmap {
        val px = 96
        val b = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        c.drawCircle(px / 2f, px / 2f, px / 2f - 4, Paint().apply { color = Color.WHITE; isAntiAlias = true })
        c.drawCircle(px / 2f, px / 2f, px / 2f - 4, Paint().apply {
            color = Color.rgb(255, 122, 26); style = Paint.Style.STROKE; strokeWidth = 7f; isAntiAlias = true
        })
        val t = Paint().apply { textSize = 52f; textAlign = Paint.Align.CENTER; isAntiAlias = true }
        c.drawText(emoji, px / 2f, px / 2f + 18f, t)
        return b
    }
}
