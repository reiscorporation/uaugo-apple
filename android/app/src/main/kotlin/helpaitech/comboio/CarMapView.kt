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
            v.area = visible
            view3d = v
            // Entre o mapa e os avisos do carro.
            root.addView(v.view, 1, FrameLayout.LayoutParams(-1, -1))
            runCatching { mapView?.onPause() }
        } else {
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
        val cfg = android.content.res.Configuration(p.context.resources.configuration)
        cfg.fontScale = 1f
        val mv = MapView(android.view.ContextThemeWrapper(p.context, 0).apply {
            applyOverrideConfiguration(cfg)
        })
        mv.onCreate(null)
        val root = FrameLayout(p.context)
        root.addView(mv, FrameLayout.LayoutParams(-1, -1))
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

    /** Toque na tela do carro: "alert", "radar" ou null. */
    fun tap(x: Float, y: Float) = overlay?.hit(x, y)

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
        hazardMarkers.clear()
        hazardSig = 0
        poisShown = true
        me = null
        overlay = null
        runCatching { view3d?.destroy() }
        view3d = null
        root3d = null
        ctx3d = null
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
                    .width(3f) // bem fina: o trânsito aparece em volta
                    .zIndex(2f)) else null
        }
        apply3d()
        overlay?.update()
        if (view3d != null) return // mapa pausado: a cena 3D cobre a tela
        drawPois(g)
        drawHazards(g)
        if (!CarState.hasPosition) return
        val pos = LatLng(CarState.lat, CarState.lng)
        trimPassed(pts, pos)
        // A imagem do veículo vem do celular (foto ou ícone configurado).
        val img = CarState.vehicleImage
        val iconKey = "${CarState.vehicle}|${img?.contentHashCode() ?: 0}"
        if (meIcon != iconKey) {
            me?.remove()
            me = null
            meIcon = iconKey
        }
        val m = me ?: g.addMarker(
            MarkerOptions().position(pos).anchor(0.5f, 0.5f)
                .icon(BitmapDescriptorFactory.fromBitmap(myVehicle(img))).zIndex(5f)
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
        // Mapa bem afastado: os radares viram um amontoado que cobre as ruas.
        val show = zoom >= 13f
        if (show != poisShown) {
            poisShown = show
            poiMarkers.forEach { it.isVisible = show }
        }
        // Anima no tempo entre as leituras: uma animação longa seria cancelada
        // pela leitura seguinte e o mapa ficaria para trás do veículo. Muito
        // atrasado (celular ocupado): pula direto para o lugar certo.
        val cam = CameraUpdateFactory.newCameraPosition(
            CameraPosition.Builder().target(pos).zoom(zoom)
                .bearing(CarState.bearing.toFloat()).tilt(45f).build())
        val now = android.os.SystemClock.uptimeMillis()
        val gap = now - lastCamAt
        lastCamAt = now
        if (gap > 2500) g.moveCamera(cam)
        else g.animateCamera(cam, gap.coerceIn(120L, 900L).toInt(), null)
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

    /** A imagem mandada pelo celular; sem ela, o emoji do tipo do veículo. */
    private fun myVehicle(png: ByteArray?): Bitmap {
        val b = png?.let { android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size) }
            ?: return vehicleBitmap(CarState.vehicle)
        return Bitmap.createScaledBitmap(b, 56, 56, true)
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
