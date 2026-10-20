// ============================================================================
// CarMapView.kt — Mapa do Google na tela do carro (Android Auto)
//
// O que faz: Desenha um mapa de verdade (Google Maps) na superfície da tela
//   do carro: uma "tela virtual" do Android recebe uma Presentation com um
//   MapView. O mapa segue o piloto (girado para a frente, inclinado), com a
//   rota em azul, a seta do piloto, a velocidade, a placa do limite e o aviso
//   de radar por cima. Os dados vêm do CarState (alimentado pelo celular).
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
    private var me: Marker? = null
    private var speedText: TextView? = null
    private var limitText: TextView? = null
    private var alertText: TextView? = null
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
        val mv = MapView(context)
        mv.onCreate(null)
        val root = FrameLayout(context)
        root.addView(mv, FrameLayout.LayoutParams(-1, -1))
        root.addView(overlay(), FrameLayout.LayoutParams(-1, -1))
        p.setContentView(root)
        p.show()
        mv.onStart()
        mv.onResume()
        mv.getMapAsync { g ->
            map = g
            g.uiSettings.setAllGesturesEnabled(false)
            g.uiSettings.isMapToolbarEnabled = false
            g.uiSettings.isCompassEnabled = false
            g.isTrafficEnabled = true
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
        me = null
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
            routeLine = if (pts.size >= 2) g.addPolyline(
                PolylineOptions()
                    .addAll(pts.map { LatLng(it[0], it[1]) })
                    .color(Color.rgb(26, 115, 232))
                    .width(16f)
                    .zIndex(2f)) else null
        }
        speedText?.text = "${CarState.speedKmh} km/h"
        limitText?.let {
            it.text = if (CarState.limitKmh > 0) "${CarState.limitKmh}" else ""
            it.visibility = if (CarState.limitKmh > 0) TextView.VISIBLE else TextView.GONE
        }
        alertText?.let {
            val a = CarState.nav?.alert
            it.text = a ?: ""
            it.visibility = if (a.isNullOrBlank()) TextView.GONE else TextView.VISIBLE
        }
        if (!CarState.hasPosition) return
        val pos = LatLng(CarState.lat, CarState.lng)
        val m = me ?: g.addMarker(
            MarkerOptions().position(pos).flat(true).anchor(0.5f, 0.5f)
                .icon(BitmapDescriptorFactory.fromBitmap(arrowBitmap())).zIndex(5f)
        )?.also { me = it }
        m?.position = pos
        // Seta "deitada" no mapa, na direção do piloto; como o mapa gira
        // junto, ela aparece sempre para cima.
        m?.rotation = CarState.bearing.toFloat()
        // Mais longe na rodovia, mais perto na cidade.
        val zoom = when {
            CarState.speedKmh >= 90 -> 15.5f
            CarState.speedKmh >= 50 -> 16.3f
            else -> 17.2f
        }
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

    /** Velocidade, placa do limite e aviso de radar por cima do mapa. */
    private fun overlay(): FrameLayout {
        val f = FrameLayout(context)
        val col = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.START or Gravity.BOTTOM
            setPadding(28, 28, 28, 28)
        }
        limitText = TextView(context).apply {
            textSize = 22f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.BLACK)
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke(10, Color.RED)
            }
            visibility = TextView.GONE
        }
        col.addView(limitText, LinearLayout.LayoutParams(110, 110).apply { bottomMargin = 12 })
        speedText = TextView(context).apply {
            textSize = 26f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(22, 10, 22, 10)
            background = GradientDrawable().apply {
                cornerRadius = 24f
                setColor(Color.argb(220, 15, 27, 45))
            }
        }
        col.addView(speedText)
        f.addView(col, FrameLayout.LayoutParams(-2, -2, Gravity.START or Gravity.BOTTOM))
        alertText = TextView(context).apply {
            textSize = 24f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setPadding(26, 14, 26, 14)
            background = GradientDrawable().apply {
                cornerRadius = 24f
                setColor(Color.rgb(198, 40, 40))
            }
            visibility = TextView.GONE
        }
        f.addView(alertText, FrameLayout.LayoutParams(-2, -2, Gravity.END or Gravity.BOTTOM).apply {
            setMargins(28, 28, 28, 28)
        })
        return f
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
}
