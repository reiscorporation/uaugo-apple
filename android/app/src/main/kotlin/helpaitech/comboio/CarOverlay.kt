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
    // 23/11: manobra e chegada em branco com letra preta, como no celular.
    private val turnDist = tv(20f, Color.BLACK)
    private val turnText = tv(13f, Color.BLACK).apply {
        maxLines = 1; ellipsize = android.text.TextUtils.TruncateAt.END
    }
    private val turn = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        background = box(Color.WHITE, 14); setPadding(dp(10), dp(5), dp(12), dp(5))
        addView(turnIcon, LinearLayout.LayoutParams(dp(32), dp(32)))
        addView(LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; setPadding(dp(10), 0, 0, 0)
            addView(turnDist); addView(turnText)
        })
    }
    private val info = tv(16f, Color.BLACK).apply {
        gravity = Gravity.CENTER_VERTICAL; maxLines = 2
        background = box(Color.WHITE, 14); setPadding(dp(12), dp(5), dp(12), dp(5))
    }
    // Aviso amarelo igual ao do celular (12/11): faixa de lado a lado logo
    // abaixo da manobra, emoji grande à esquerda e texto em negrito.
    // 16/11: menor (letra 13, só a largura do texto), pedido do Ricardo.
    private val banner = tv(13f, Color.BLACK).apply {
        background = box(Color.rgb(255, 193, 7), 10); setPadding(dp(10), dp(3), dp(10), dp(3)); maxLines = 2
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
    // Música (♪), como no celular: sempre à mão.
    private val musicBtn = tv(26f, Color.WHITE).apply {
        text = "♪"; gravity = Gravity.CENTER
        background = box(Color.argb(238, 15, 27, 45), 14)
    }
    // Mini player (como no celular): abre ao lado do ♪, sem trocar de tela.
    var musicOpen = false
    private val musicTitle = tv(14f, Color.WHITE).apply {
        maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
        setPadding(dp(12), 0, dp(6), 0); gravity = Gravity.CENTER_VERTICAL
    }
    private fun mBtn(t: String) = tv(22f, Color.WHITE).apply { text = t; gravity = Gravity.CENTER }
    private val mPrev = mBtn("⏮︎")
    private val mPlay = mBtn("▶︎")
    private val mNext = mBtn("⏭︎")
    private val musicBar = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        background = box(Color.argb(238, 15, 27, 45), 14)
        addView(musicTitle, LinearLayout.LayoutParams(dp(170), -1))
        addView(mPrev, LinearLayout.LayoutParams(dp(48), -1))
        addView(mPlay, LinearLayout.LayoutParams(dp(52), -1))
        addView(mNext, LinearLayout.LayoutParams(dp(48), -1))
        visibility = View.GONE
    }
    // Configurações (⚙), como no celular.
    private val settingsBtn = tv(26f, Color.WHITE).apply {
        text = "⚙︎"; gravity = Gravity.CENTER
        background = box(Color.argb(238, 15, 27, 45), 14)
    }
    private val requestBtn = tv(25f, Color.WHITE).apply {
        text = "\uD83D\uDCE2"; gravity = Gravity.CENTER
        background = box(Color.rgb(245, 124, 0), 14)
    }
    // SOS redondo, vermelho com borda branca, como no celular (23/11).
    private val sosBtn = tv(17f, Color.WHITE).apply {
        text = "SOS"; gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL; setColor(Color.rgb(229, 57, 53)); setStroke(dp(3), Color.WHITE)
        }
    }
    // Próximos passos (23/11): painel branco com 40% da largura à direita,
    // a 1ª manobra em laranja, igual ao celular deitado.
    private val stepsTitle = tv(15f, Color.rgb(33, 33, 33)).apply {
        setPadding(dp(12), dp(10), dp(12), dp(6))
    }
    private val stepRows = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL; setPadding(dp(8), 0, dp(8), dp(8))
    }
    private val stepsPanel = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL; setBackgroundColor(Color.WHITE)
        visibility = View.GONE
        addView(stepsTitle); addView(stepRows)
    }
    /** Largura do painel dos passos (px); 0 = sem painel. */
    var panelW = 0
        private set
    private var panelPadR = 0
    /** Coluna de botões da direita (música, ⚙, bússola, visão, pedidos). */
    private var sideColumn: LinearLayout? = null
    private val groupBar = tv(15f, Color.WHITE).apply {
        setPadding(dp(12), dp(8), dp(12), dp(8)); maxLines = 2
    }
    private val radarBtn = tv(25f, Color.WHITE).apply {
        text = "\uD83D\uDCF7"; gravity = Gravity.CENTER
        background = box(Color.rgb(211, 47, 47), 14)
    }

    /** Bússola sempre à vista, como no celular: a coluna de botões do
     *  Android Auto some sozinha alguns segundos depois de navegar (16/11). */
    private val compassBtn = tv(24f, Color.WHITE).apply {
        text = "🧭"; gravity = Gravity.CENTER
        background = box(Color.argb(238, 15, 27, 45), 14)
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
            // Velocímetro: confirmar/corrigir o limite da via (23/11), como
            // segurar o velocímetro no celular.
            inside(speedArea) -> "roadspeed"
            inside(viewBtn) -> "toggleview"
            inside(mPrev) -> "mprev"
            inside(mPlay) -> "mtoggle"
            inside(mNext) -> "mnext"
            inside(musicBtn) -> "music"
            inside(settingsBtn) -> "settings"
            inside(requestBtn) -> "requests"
            inside(sosBtn) -> "sos"
            inside(compassBtn) -> "compass"
            inside(alertBtn) -> "alert"
            inside(radarBtn) -> "radar"
            inside(view3dBtn) -> if (hud3d) "tomap" else "to3d"
            else -> null
        }
    }

    private var topBox: View? = null
    private var lastArea: android.graphics.Rect? = null
    private var lastWidth = 0

    /** Estrada em 3D na tela: o minimapa da página fica no canto de cima à
     *  esquerda, então o aviso amarelo começa à direita dele (17/11: o aviso
     *  "Lombada à frente" cobria o minimapa). */
    var in3d = false
        set(v) {
            if (field == v) return
            field = v
            lastArea?.let { setArea(it, lastWidth) }
        }

    /** Largura do minimapa da página 3D (sim3d: 32% da altura, de 80 a 120
     *  px da página) + as margens dele, em px da tela. */
    private fun miniSpace(): Int {
        val hDp = root.height / d
        return dp((hDp * 0.32f).coerceIn(80f, 120f).toInt() + 10 + 8)
    }

    /** Área livre (fora dos botões do Android Auto): a faixa de cima cabe nela. */
    fun setArea(r: android.graphics.Rect, width: Int) {
        lastArea = android.graphics.Rect(r)
        lastWidth = width
        val v = topBox ?: return
        val lp = v.layoutParams as FrameLayout.LayoutParams
        // 12/11: a faixa sobe até o topo da tela (antes começava abaixo da
        // linha dos botões do Android Auto); à direita deixa o espaço da
        // lupa e da porta, que ficam no canto de cima.
        val rightGap = if (panelW > 0) panelW else maxOf((width - r.right).coerceAtLeast(0), dp(170))
        lp.setMargins(r.left + dp(10) + (if (in3d) miniSpace() else 0), dp(10), rightGap + dp(10), 0)
        v.layoutParams = lp
        placeBottom(r, width)
    }

    private val pill = tv(15f, Color.WHITE).apply {
        background = box(Color.rgb(198, 40, 40), 18); setPadding(dp(12), dp(6), dp(12), dp(6))
    }

    /** Folga dos botões até a borda (direita e embaixo). */
    private val EDGE_R get() = dp(6)
    private val EDGE_B get() = dp(10)

    private var speedColumn: View? = null
    private var buttonRow: View? = null

    /** Linha de botões na tela (null antes do 1º desenho). */
    fun buttonsRect(): android.graphics.Rect? = buttonRow?.takeIf { it.width > 0 && it.visibility == View.VISIBLE }
        ?.let { android.graphics.Rect(it.left, it.top, it.right, it.bottom) }

    /** Coluna do velocímetro na tela (null antes do 1º desenho). */
    fun speedRect(): android.graphics.Rect? = speedColumn?.takeIf { it.width > 0 }
        ?.let { android.graphics.Rect(it.left, it.top, it.right, it.bottom) }

    init {
        // Faixa de cima, de lado a lado da área livre: manobra e chegada; o
        // aviso amarelo fica logo abaixo.
        val top = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        val row = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(turn, LinearLayout.LayoutParams(0, -2, 1f))
        row.addView(info, LinearLayout.LayoutParams(-2, -1).apply { leftMargin = dp(6) })
        top.addView(row, LinearLayout.LayoutParams(-1, -2))
        top.addView(banner, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(6) })
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
            // Hexágono escuro com borda clara: o velocímetro do 3D do
            // celular, oficial em todos os modos (23/11).
            background = HexDrawable(Color.argb(225, 14, 24, 36), Color.argb(200, 244, 251, 255), dp(2).toFloat())
            addView(speed); addView(tv(13f, Color.WHITE, false).apply { text = "km/h"; gravity = Gravity.CENTER })
        }
        speedBox.addView(sp, FrameLayout.LayoutParams(dp(96), dp(96), Gravity.BOTTOM or Gravity.START))
        speedBox.addView(limit, FrameLayout.LayoutParams(dp(44), dp(44), Gravity.TOP or Gravity.END))
        val bottom = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.BOTTOM }
        // Embaixo de tudo: alerta e radar móvel, iguais aos do celular.
        val column = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        // Sem alinhar pela base do texto: o "SOS" (texto) descia uns pixels em
        // relação aos ícones e o fundo era cortado embaixo (17/11).
        val buttons = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            isBaselineAligned = false
            gravity = Gravity.CENTER_VERTICAL
        }
        // Como no celular deitado (23/11): embaixo 3D/mapa, radar móvel,
        // alerta e o SOS redondo; a coluna da direita fica acima do SOS.
        buttons.addView(view3dBtn, LinearLayout.LayoutParams(dp(56), dp(56)))
        buttons.addView(radarBtn, LinearLayout.LayoutParams(dp(56), dp(56)).apply { leftMargin = dp(8) })
        buttons.addView(alertBtn, LinearLayout.LayoutParams(dp(56), dp(56)).apply { leftMargin = dp(8) })
        buttons.addView(sosBtn, LinearLayout.LayoutParams(dp(68), dp(68)).apply { leftMargin = dp(8) })
        val side = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.END
        }
        fun sideAdd(v: View, w: Int = 52) = side.addView(v, LinearLayout.LayoutParams(dp(w), dp(52)).apply { topMargin = dp(8) })
        side.addView(musicBar, LinearLayout.LayoutParams(-2, dp(52)))
        sideAdd(musicBtn); sideAdd(settingsBtn); sideAdd(compassBtn); sideAdd(viewBtn, 72); sideAdd(requestBtn)
        sideColumn = side
        bottom.addView(speedBox, LinearLayout.LayoutParams(dp(118), dp(108)))
        bottom.addView(pill, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(8); bottomMargin = dp(6) })
        column.addView(bottom)
        speedColumn = column
        buttonRow = buttons
        root.addView(column, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.START).apply {
            setMargins(dp(10), 0, 0, dp(6))
        })
        root.addView(buttons, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.END).apply {
            setMargins(0, 0, dp(84) + EDGE_R, EDGE_B)
        })
        root.addView(side, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.END).apply {
            setMargins(0, 0, dp(84) + EDGE_R, EDGE_B + dp(68 + 4))
        })
        root.addView(stepsPanel, FrameLayout.LayoutParams(0, -1, Gravity.END))
    }

    /** Botões embaixo à direita, ao lado da coluna do Android Auto (+/−);
     *  velocímetro no canto de baixo à esquerda (16/11). Tela estreita
     *  (dividida): não cabem lado a lado, os botões ficam embaixo e o
     *  velocímetro logo acima deles, como antes. */
    private fun placeBottom(r: android.graphics.Rect, width: Int) {
        val b = buttonRow ?: return
        val c = speedColumn ?: return
        val narrow = r.width() < 560 // mesmo critério do extraLeft do mapa
        val blp = b.layoutParams as FrameLayout.LayoutParams
        val clp = c.layoutParams as FrameLayout.LayoutParams
        if (narrow) {
            blp.gravity = Gravity.BOTTOM or Gravity.START
            blp.setMargins(r.left + dp(10), 0, 0, EDGE_B)
            clp.setMargins(r.left + dp(10), 0, 0, EDGE_B + dp(56 + 8))
        } else {
            blp.gravity = Gravity.BOTTOM or Gravity.END
            blp.setMargins(0, 0, rightEdge(r, width) + EDGE_R, EDGE_B)
            clp.setMargins(r.left + dp(10), 0, 0, dp(6))
        }
        b.layoutParams = blp
        c.layoutParams = clp
        sideColumn?.let { sc ->
            val slp = sc.layoutParams as FrameLayout.LayoutParams
            slp.gravity = Gravity.BOTTOM or Gravity.END
            slp.setMargins(0, 0, rightEdge(r, width) + EDGE_R + dp(8), EDGE_B + dp(68 + 4))
            sc.layoutParams = slp
            sc.visibility = if (narrow) View.GONE else View.VISIBLE
        }
    }

    /** Distância da borda direita da tela até a borda do mapa: o painel dos
     *  passos (se houver) ou a coluna de botões do Android Auto. */
    private fun rightEdge(r: android.graphics.Rect, width: Int) =
        if (panelW > 0) panelW else maxOf((width - r.right).coerceAtLeast(0), dp(84))

    /** Liga/desliga o painel dos próximos passos (40% da largura). [padR]:
     *  espaço da coluna do Android Auto, que fica por cima do painel. */
    fun setPanel(w: Int, padR: Int) {
        if (w == panelW && padR == panelPadR) return
        panelW = w
        panelPadR = padR
        val lp = stepsPanel.layoutParams as FrameLayout.LayoutParams
        lp.width = w
        stepsPanel.layoutParams = lp
        // A coluna do Android Auto (lupa, sair, zoom) fica por cima da borda
        // direita: o conteúdo do painel para antes dela.
        stepsPanel.setPadding(0, 0, maxOf(padR, dp(96)), 0)
        stepsPanel.visibility = if (w > 0) View.VISIBLE else View.GONE
        lastArea?.let { setArea(it, lastWidth) }
        update()
    }

    private fun stepRow(i: Int, m: String, text: String, meters: Int): View {
        val first = i == 0
        val fg = if (first) Color.WHITE else Color.BLACK
        return LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            background = box(if (first) Color.rgb(255, 122, 26) else Color.rgb(241, 243, 245), 10)
            setPadding(dp(8), dp(6), dp(8), dp(6))
            addView(ImageView(ctx).apply { setImageResource(icon(m)); setColorFilter(fg) },
                LinearLayout.LayoutParams(dp(if (first) 30 else 24), dp(if (first) 30 else 24)))
            // Distância em cima e a rua embaixo (2 linhas): cabe no painel.
            addView(LinearLayout(ctx).apply {
                orientation = LinearLayout.VERTICAL
                addView(tv(if (first) 16f else 14f, fg).apply { this.text = dist(meters.toDouble()) })
                addView(tv(if (first) 13f else 12f, fg, first).apply {
                    this.text = text; maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END
                })
            }, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(8) })
        }
    }

    private var stepsSig = ""

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
        // Com o painel dos passos (deitado, como no celular), a manobra vai
        // na 1ª linha do painel e o topo mostra só a Chegada (23/11).
        turn.visibility = if (n == null || panelW > 0) View.GONE else View.VISIBLE
        // Velocímetro sempre no canto, também com o 3D (08/11).
        speedArea.visibility = View.VISIBLE
        // 3D/mapa ao lado do radar, no mapa E no 3D, como no celular (23/11).
        view3dBtn.visibility = View.VISIBLE
        view3dBtn.text = if (hud3d) "🗺" else "3D"
        stepsTitle.text = tx("Next steps", "Próximos passos", "Próximos pasos")
        if (panelW > 0) {
            val st = CarState.steps
            val sig = st.joinToString("|") { "${it.first}${it.second}${it.third / 10}" }
            if (sig != stepsSig) {
                stepsSig = sig
                stepRows.removeAllViews()
                val h = root.height
                val max = if (h > 0) ((h / d - 50) / 62).toInt().coerceIn(2, 8) else 5
                for ((i, x) in st.take(max).withIndex()) {
                    stepRows.addView(stepRow(i, x.first, x.second, x.third),
                        LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
                }
            }
        }
        if (n != null) {
            turnIcon.setImageResource(icon(n.maneuver))
            turnIcon.setColorFilter(Color.BLACK)
            turnDist.text = dist(n.meters)
            turnText.text = n.text
            val secs = ((n.etaMillis - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
            val h = secs / 3600; val min = (secs % 3600) / 60
            val time = if (h > 0) "${h}h${"%02d".format(min)}" else "$min min"
            val eta = if (n.etaMillis > 0) SimpleDateFormat("HH:mm", Locale("pt", "BR")).format(Date(n.etaMillis)) else ""
            info.text = "${tx("Arrival", "Chegada")} $eta\n$time · ${dist(n.remainingM)}"
        }
        val b = CarState.banner
        banner.visibility = if (b.isNullOrBlank()) View.GONE else View.VISIBLE
        info.visibility = if (n == null) View.GONE else View.VISIBLE
        (info.layoutParams as? LinearLayout.LayoutParams)?.let { lp ->
            val full = panelW > 0
            val w = if (full) 0 else -2
            if (lp.width != w) {
                lp.width = w; lp.weight = if (full) 1f else 0f
                lp.leftMargin = if (full) 0 else dp(6)
                info.layoutParams = lp
            }
        }
        banner.text = bannerText(b ?: "")
        musicBar.visibility = if (musicOpen) View.VISIBLE else View.GONE
        if (musicOpen) {
            val now = CarMedia.now(ctx)
            musicTitle.text = when {
                !CarMedia.hasAccess(ctx) -> tx("Allow music access on the phone", "Libere o acesso à música no celular")
                now == null -> tx("Nothing playing", "Nada tocando")
                else -> listOf(now.title, now.artist).filter { it.isNotEmpty() }.joinToString(" · ")
            }
            mPlay.text = if (now?.playing == true) "⏸︎" else "▶︎"
        }
        val group = if (CarState.groupOn) View.VISIBLE else View.GONE
        requestBtn.visibility = group
        // No 3D não há Solo/Comboio (sempre primeira pessoa), 23/11.
        viewBtn.visibility = if (hud3d) View.GONE else group
        // 23/11: Solo = uma pessoa, Comboio = três pessoas (como no celular).
        viewBtn.text = if (CarState.convoyView) "👥\n" + tx("CONVOY", "COMBOIO") else "👤\nSOLO"
        // SOS e bússola sempre, em todas as telas, como no celular (16/11).
        // Sozinho, o SOS abre os telefones de emergência no carro.
        sosBtn.visibility = View.VISIBLE
        // Bússola só no mapa, como no celular (no 3D não faz sentido).
        compassBtn.visibility = if (hud3d) View.GONE else View.VISIBLE
        val armed = CarState.sosArmed
        sosBtn.textSize = if (armed) 12f else 17f
        sosBtn.text = when {
            !armed -> "SOS"
            else -> tx("Tap again\nto send", "Toque novamente\npara enviar")
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
        ss.setSpan(android.text.style.RelativeSizeSpan(1.4f), 0, sp, 0)
        return ss
    }
}

/** Fundo em hexágono (velocímetro, como o do 3D do celular). */
class HexDrawable(private val fill: Int, private val stroke: Int, private val sw: Float) :
    android.graphics.drawable.Drawable() {
    private val pf = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = fill }
    private val ps = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        color = stroke; style = android.graphics.Paint.Style.STROKE; strokeWidth = sw
    }
    override fun draw(c: android.graphics.Canvas) {
        val b = bounds
        val w = b.width().toFloat(); val h = b.height().toFloat()
        val x0 = b.left + sw; val y0 = b.top + sw; val x1 = b.right - sw; val y1 = b.bottom - sw
        val k = w * 0.2f
        val p = android.graphics.Path().apply {
            moveTo(x0 + k, y0); lineTo(x1 - k, y0); lineTo(x1, b.top + h / 2)
            lineTo(x1 - k, y1); lineTo(x0 + k, y1); lineTo(x0, b.top + h / 2); close()
        }
        c.drawPath(p, pf); c.drawPath(p, ps)
    }
    override fun setAlpha(a: Int) {}
    override fun setColorFilter(f: android.graphics.ColorFilter?) {}
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
}
