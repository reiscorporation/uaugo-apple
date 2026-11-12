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
    private val turnDist = tv(20f, Color.WHITE)
    private val turnText = tv(13f, Color.WHITE).apply {
        maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
    }
    private val turn = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        background = box(Color.rgb(46, 125, 50), 14); setPadding(dp(10), dp(5), dp(12), dp(5))
        addView(turnIcon, LinearLayout.LayoutParams(dp(32), dp(32)))
        addView(LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(10), 0, 0, 0)
            addView(turnDist); addView(turnText)
        })
    }
    private val info = tv(16f, Color.WHITE).apply {
        gravity = Gravity.CENTER_VERTICAL; maxLines = 2
        background = box(Color.argb(238, 15, 27, 45), 14); setPadding(dp(12), dp(5), dp(12), dp(5))
    }
    // Aviso amarelo igual ao do celular (12/11): faixa de lado a lado logo
    // abaixo da manobra, emoji grande à esquerda e texto em negrito.
    private val banner = tv(16f, Color.BLACK).apply {
        background = box(Color.rgb(255, 193, 7), 12); setPadding(dp(12), dp(6), dp(12), dp(6)); maxLines = 2
        gravity = Gravity.CENTER_VERTICAL; elevation = dp(6).toFloat()
    }
    private val speed = tv(36f, Color.WHITE).apply { gravity = Gravity.CENTER }
    private val speedArea = FrameLayout(ctx)
    private val limit = tv(18f, Color.BLACK).apply {
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(Color.WHITE); setStroke(dp(4), Color.RED)
        }
    }
    private val alertBtn = tv(30f, Color.BLACK).apply {
        text = "\u26A0\uFE0E"; gravity = Gravity.CENTER
        background = box(Color.rgb(255, 193, 7), 14)
    }
    // SOLO/COMBOIO, igual ao botão do celular (só em grupo).
    private val viewBtn = tv(12f, Color.WHITE).apply {
        gravity = Gravity.CENTER
        background = box(Color.argb(238, 15, 27, 45), 14)
    }
    private val requestBtn = tv(25f, Color.WHITE).apply {
        text = "\uD83D\uDCE2"; gravity = Gravity.CENTER
        background = box(Color.rgb(245, 124, 0), 14)
    }
    private val sosBtn = tv(17f, Color.WHITE).apply {
        text = "SOS"; gravity = Gravity.CENTER; minWidth = dp(56)
        background = box(Color.rgb(211, 47, 47), 14); setPadding(dp(8), 0, dp(8), 0)
    }
    private val groupBar = tv(15f, Color.WHITE).apply {
        setPadding(dp(12), dp(8), dp(12), dp(8)); maxLines = 2
    }
    private val radarBtn = tv(25f, Color.WHITE).apply {
        text = "\uD83D\uDCF7"; gravity = Gravity.CENTER
        background = box(Color.rgb(211, 47, 47), 14)
    }

    /** No mapa: vai para a estrada em 3D (no 3D, tocar no minimapa volta). */
    private val view3dBtn = tv(19f, Color.WHITE).apply {
        text = "3D"; gravity = Gravity.CENTER
        background = box(Color.rgb(15, 27, 45), 14)
    }

    /** Qual botão do mapa foi tocado (com folga para o dedo). */
    fun hit(x: Float, y: Float): String? {
        fun inside(v: View): Boolean {
            if (v.visibility != View.VISIBLE) return false
            val o = IntArray(2)
            v.getLocationInWindow(o)
            val m = dp(6)
            return x >= o[0] - m && x <= o[0] + v.width + m && y >= o[1] - m && y <= o[1] + v.height + m
        }
        return when {
            inside(groupBar) && CarState.groupAction != null -> "do:${CarState.groupAction}"
            // Faixa amarela: confirmar/corrigir velocidade, radar não existe.
            inside(banner) -> "bannertap"
            inside(viewBtn) -> "toggleview"
            inside(requestBtn) -> "requests"
            inside(sosBtn) -> "sos"
            inside(alertBtn) -> "alert"
            inside(radarBtn) -> "radar"
            inside(view3dBtn) -> "to3d"
            else -> null
        }
    }

    private var topBox: View? = null

    /** Área livre (fora dos botões do Android Auto): a faixa de cima cabe nela. */
    fun setArea(r: android.graphics.Rect, width: Int) {
        val v = topBox ?: return
        val lp = v.layoutParams as FrameLayout.LayoutParams
        lp.setMargins(r.left + dp(10), r.top + dp(10), (width - r.right).coerceAtLeast(0) + dp(10), 0)
        v.layoutParams = lp
    }

    private val pill = tv(15f, Color.WHITE).apply {
        background = box(Color.rgb(198, 40, 40), 18); setPadding(dp(12), dp(6), dp(12), dp(6))
    }

    init {
        // Faixa de cima, de lado a lado da área livre: manobra e chegada; o
        // aviso amarelo fica logo abaixo.
        val top = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val row = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(turn, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(info, LinearLayout.LayoutParams(-2, -1).apply { leftMargin = dp(6) })
        top.addView(row, LinearLayout.LayoutParams(-1, -2))
        top.addView(banner, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
        top.addView(groupBar, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(6) })
        topBox = top
        root.addView(top, FrameLayout.LayoutParams(-1, -2, Gravity.TOP).apply {
            setMargins(dp(10), dp(10), dp(10), 0)
        })
        // Velocímetro (embaixo, à esquerda), placa do limite no canto e a
        // contagem do radar ao lado, como no celular.
        val speedBox = speedArea
        val sp = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            background = box(Color.argb(238, 15, 27, 45), 18)
            addView(speed); addView(tv(13f, Color.WHITE, false).apply { text = "km/h"; gravity = Gravity.CENTER })
        }
        speedBox.addView(sp, FrameLayout.LayoutParams(dp(96), dp(96), Gravity.BOTTOM or Gravity.START))
        speedBox.addView(limit, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END))
        val bottom = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
        // Embaixo de tudo: alerta e radar móvel, iguais aos do celular.
        val column = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val buttons = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        buttons.addView(alertBtn, LinearLayout.LayoutParams(dp(56), dp(56)))
        buttons.addView(radarBtn, LinearLayout.LayoutParams(dp(56), dp(56)).apply { leftMargin = dp(8) })
        buttons.addView(viewBtn, LinearLayout.LayoutParams(dp(78), dp(56)).apply { leftMargin = dp(8) })
        buttons.addView(requestBtn, LinearLayout.LayoutParams(dp(56), dp(56)).apply { leftMargin = dp(8) })
        buttons.addView(sosBtn, LinearLayout.LayoutParams(-2, dp(56)).apply { leftMargin = dp(8) })
        buttons.addView(view3dBtn, LinearLayout.LayoutParams(dp(56), dp(56)).apply { leftMargin = dp(8) })
        bottom.addView(speedBox, LinearLayout.LayoutParams(dp(118), dp(108)))
        bottom.addView(pill, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(8); bottomMargin = dp(6) })
        column.addView(bottom)
        column.addView(buttons, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(6) })
        root.addView(column, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.START).apply {
            setMargins(dp(10), 0, 0, dp(10))
        })
    }

    private fun icon(m: String) = when {
        m.startsWith("uturn") -> R.drawable.car_uturn
        // Curva suave, saída e "mantenha-se": seta menos curvada.
        m == "turn-slight-left" || m == "ramp-left" || m == "keep-left" || m == "fork-left" -> R.drawable.car_slight_left
        m == "turn-slight-right" || m == "ramp-right" || m == "keep-right" || m == "fork-right" -> R.drawable.car_slight_right
        m.contains("left") -> R.drawable.car_turn_left
        m.contains("right") -> R.drawable.car_turn_right
        else -> R.drawable.car_straight
    }

    private fun dist(m: Double) = if (m >= 1000) String.format(Locale("pt", "BR"), "%.1f km", m / 1000)
        else "${(m / 10).toInt() * 10} m"

    /** Cena 3D na tela: o painel dela mostra velocidade e manobra. */
    var hud3d = false

    /** Atualiza com o estado mandado pelo celular. */
    fun update() {
        val n = CarState.nav
        turn.visibility = if (n == null || hud3d) View.GONE else View.VISIBLE
        // Velocímetro sempre no canto, também com o 3D (08/11).
        speedArea.visibility = View.VISIBLE
        // 12/11: o "3D" fica só nos botões do Android Auto (à direita); este
        // de baixo repetia o mesmo botão.
        view3dBtn.visibility = View.GONE
        if (n != null) {
            turnIcon.setImageResource(icon(n.maneuver))
            turnIcon.setColorFilter(Color.WHITE)
            turnDist.text = dist(n.meters)
            turnText.text = n.text
            val secs = ((n.etaMillis - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
            val h = secs / 3600; val min = (secs % 3600) / 60
            val time = if (h > 0) "${h}h${"%02d".format(min)}" else "$min min"
            val eta = if (n.etaMillis > 0) SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date(n.etaMillis)) else ""
            info.text = "${if (CarState.en) "Arrival" else "Chegada"} $eta\n$time · ${dist(n.remainingM)}"
        }
        val b = CarState.banner
        banner.visibility = if (b.isNullOrBlank()) View.GONE else View.VISIBLE
        info.visibility = turn.visibility
        banner.text = bannerText(b ?: "")
        val group = if (CarState.groupOn) View.VISIBLE else View.GONE
        requestBtn.visibility = group
        viewBtn.visibility = group
        viewBtn.text = if (CarState.convoyView) (if (CarState.en) "CONVOY" else "COMBOIO") else "SOLO"
        sosBtn.visibility = group
        val armed = CarState.sosArmed
        sosBtn.textSize = if (armed) 12f else 17f
        sosBtn.text = when {
            !armed -> "SOS"
            CarState.en -> "Tap again\nto send"
            else -> "Toque novamente\npara enviar"
        }
        val g = CarState.groupText
        groupBar.visibility = if (g.isNullOrBlank()) View.GONE else View.VISIBLE
        groupBar.text = g ?: ""
        groupBar.background = box(
            if (CarState.groupUrgent) Color.rgb(198, 40, 40) else Color.rgb(46, 125, 50), 12)
        speed.text = "${CarState.speedKmh}"
        limit.visibility = if (CarState.limitKmh > 0) View.VISIBLE else View.GONE
        limit.text = "${CarState.limitKmh}"
        val a = CarState.alert
        pill.visibility = if (a.isNullOrBlank()) View.GONE else View.VISIBLE
        pill.text = a ?: ""
    }

    /** Emoji do começo maior que o texto, como no celular. */
    private fun bannerText(t: String): CharSequence {
        val sp = t.indexOf(' ')
        if (sp <= 0 || sp > 8) return t
        val ss = android.text.SpannableString(t.substring(0, sp) + "  " + t.substring(sp + 1))
        ss.setSpan(android.text.style.RelativeSizeSpan(1.7f), 0, sp, 0)
        return ss
    }
}
