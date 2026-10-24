// ============================================================================
// CarOverlay.kt — Informações por cima do mapa do carro (igual ao celular)
//
// O que faz: Faixa verde da próxima manobra, linha "Chegada · tempo · km",
//   faixa amarela de aviso (radar, polícia...), velocímetro com a placa do
//   limite e a contagem do radar. Os botões ficam na barra do Android Auto.
// Quem usa: CarMapView.kt.
// ============================================================================

package helpaitech.comboio

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CarOverlay(private val ctx: Context) {
    private val d = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()
    private fun box(color: Int, r: Int) = GradientDrawable().apply { setColor(color); cornerRadius = dp(r).toFloat() }
    private fun tv(size: Float, color: Int, bold: Boolean = true) = TextView(ctx).apply {
        textSize = size; setTextColor(color); if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    val root = FrameLayout(ctx)
    private val turnIcon = ImageView(ctx)
    private val turnDist = tv(26f, Color.WHITE)
    private val turnText = tv(16f, Color.WHITE).apply { maxLines = 2 }
    private val turn = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        background = box(Color.rgb(46, 125, 50), 16); setPadding(dp(12), dp(10), dp(14), dp(10))
        addView(turnIcon, LinearLayout.LayoutParams(dp(40), dp(40)))
        addView(LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(10), 0, 0, 0)
            addView(turnDist); addView(turnText)
        })
    }
    private val info = tv(15f, Color.WHITE).apply {
        background = box(Color.argb(238, 15, 27, 45), 12); setPadding(dp(12), dp(6), dp(12), dp(6))
    }
    private val banner = tv(16f, Color.BLACK).apply {
        background = box(Color.rgb(255, 193, 7), 12); setPadding(dp(12), dp(8), dp(12), dp(8)); maxLines = 2
    }
    private val speed = tv(36f, Color.WHITE).apply { gravity = Gravity.CENTER }
    private val limit = tv(18f, Color.BLACK).apply {
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(Color.WHITE); setStroke(dp(4), Color.RED)
        }
    }
    private val pill = tv(15f, Color.WHITE).apply {
        background = box(Color.rgb(198, 40, 40), 18); setPadding(dp(12), dp(6), dp(12), dp(6))
    }

    init {
        // Coluna de cima (esquerda): manobra, chegada, aviso amarelo.
        val top = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        fun gap() = LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(6) }
        top.addView(turn, LinearLayout.LayoutParams(-1, -2))
        top.addView(info, gap())
        top.addView(banner, gap().apply { width = -1 })
        root.addView(top, FrameLayout.LayoutParams(dp(330), -2, Gravity.TOP or Gravity.START).apply {
            setMargins(dp(10), dp(10), 0, 0)
        })
        // Velocímetro (embaixo, à esquerda), placa do limite no canto e a
        // contagem do radar ao lado, como no celular.
        val speedBox = FrameLayout(ctx)
        val sp = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            background = box(Color.argb(238, 15, 27, 45), 18)
            addView(speed); addView(tv(13f, Color.WHITE, false).apply { text = "km/h"; gravity = Gravity.CENTER })
        }
        speedBox.addView(sp, FrameLayout.LayoutParams(dp(96), dp(96), Gravity.BOTTOM or Gravity.START))
        speedBox.addView(limit, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END))
        val bottom = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
        bottom.addView(speedBox, LinearLayout.LayoutParams(dp(118), dp(116)))
        bottom.addView(pill, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(8); bottomMargin = dp(6) })
        root.addView(bottom, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.START).apply {
            setMargins(dp(10), 0, 0, dp(10))
        })
    }

    private fun icon(m: String) = when {
        m.startsWith("uturn") -> R.drawable.car_uturn
        m.contains("left") -> R.drawable.car_turn_left
        m.contains("right") -> R.drawable.car_turn_right
        else -> R.drawable.car_straight
    }

    private fun dist(m: Double) = if (m >= 1000) String.format(Locale("pt", "BR"), "%.1f km", m / 1000)
        else "${(m / 10).toInt() * 10} m"

    /** Atualiza com o estado mandado pelo celular. */
    fun update() {
        val n = CarState.nav
        turn.visibility = if (n == null) View.GONE else View.VISIBLE
        info.visibility = turn.visibility
        if (n != null) {
            turnIcon.setImageResource(icon(n.maneuver))
            turnIcon.setColorFilter(Color.WHITE)
            turnDist.text = dist(n.meters)
            turnText.text = n.text
            val secs = ((n.etaMillis - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
            val h = secs / 3600; val min = (secs % 3600) / 60
            val time = if (h > 0) "${h}h${"%02d".format(min)}" else "$min min"
            val eta = if (n.etaMillis > 0) SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date(n.etaMillis)) else ""
            info.text = "${if (CarState.en) "Arrival" else "Chegada"} $eta · $time · ${dist(n.remainingM)}"
        }
        val b = CarState.banner
        banner.visibility = if (b.isNullOrBlank()) View.GONE else View.VISIBLE
        banner.text = b ?: ""
        speed.text = "${CarState.speedKmh}"
        limit.visibility = if (CarState.limitKmh > 0) View.VISIBLE else View.GONE
        limit.text = "${CarState.limitKmh}"
        val a = CarState.alert
        pill.visibility = if (a.isNullOrBlank()) View.GONE else View.VISIBLE
        pill.text = a ?: ""
    }
}
