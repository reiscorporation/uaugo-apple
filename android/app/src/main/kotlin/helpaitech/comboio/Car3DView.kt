// ============================================================================
// Car3DView.kt — Estrada em 3D na tela do carro (Android Auto)
//
// O que faz: Desenha, por cima do mapa do carro, a estrada da rota em
//   perspectiva (primeira pessoa), com o tapete azul na faixa da direita e
//   setas antes da próxima conversão. É desenho 2D em perspectiva no Canvas
//   (sem WebView nem OpenGL): leve, para não pesar no celular, que já cuida do
//   GPS e de projetar a tela do carro. Entre as leituras do GPS o carro anda
//   sozinho na velocidade atual (fica suave).
// Quem usa: CarMapView (mostra/esconde conforme CarState.mode3d).
// Onde mexer: Cores no início da classe; câmera em onDraw.
// ============================================================================

package helpaitech.comboio

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.Shader
import android.view.View
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class Car3DView(context: Context) : View(context) {
    private companion object {
        const val STEP = 5.0        // amostra da rota à frente (m)
        const val AHEAD = 300.0     // até onde desenha (m)
        const val ROAD_HW = 3.7     // meia largura da rua (m)
        const val LANE = 1.75       // carro à direita do eixo (m)
        const val CAM_H = 1.6       // altura da câmera (m)
        const val NEAR = 2.2        // nada mais perto que isso (m)
        const val FRAME_MS = 50L    // 20 quadros por segundo bastam
    }

    private val ground = Paint().apply { color = Color.rgb(29, 36, 51) }
    private val road = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(46, 52, 62) }
    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(217, 222, 230) }
    private val axis = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(215, 169, 42) }
    private val carpet = Paint(Paint.ANTI_ALIAS_FLAG)
    private val arrow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(63, 198, 255) }
    private val sky = Paint()
    private var skyH = -1

    /** Área livre (fora dos cartões do Android Auto). */
    var area: Rect? = null

    // Posição: última leitura e a hora dela (para andar entre as leituras).
    private var lastLat = 0.0
    private var lastLng = 0.0
    private var lastAt = 0L
    private var hint = 0
    private var routeRef: List<DoubleArray>? = null
    private var viewBearing = Double.NaN
    private var odometer = 0.0 // faz as faixas pintadas passarem pelo carro
    private var lastDraw = 0L

    // Pontos à frente, em metros (leste, norte) a partir do carro.
    private val px = DoubleArray((AHEAD / STEP).toInt() + 3)
    private val py = DoubleArray(px.size)
    private var count = 0
    private var onRoute = false

    private val tick = object : Runnable {
        override fun run() {
            if (visibility == VISIBLE && isAttachedToWindow) {
                invalidate()
                postDelayed(this, FRAME_MS)
            }
        }
    }

    /** Liga/desliga a cena (desligada, não gasta nada). */
    fun show(on: Boolean) {
        val v = if (on) VISIBLE else GONE
        if (v == visibility) return
        visibility = v
        removeCallbacks(tick)
        if (on) {
            viewBearing = Double.NaN
            post(tick)
        }
    }

    /** Monta os pontos da rota à frente do carro; false = fora da rota. */
    private fun sampleRoute(lat: Double, lng: Double, moved: Double): Boolean {
        val r = CarState.route
        if (r !== routeRef) {
            routeRef = r
            hint = 0
        }
        if (r.size < 2) return false
        val k = cos(Math.toRadians(lat)) * 111320.0
        val ky = 110540.0
        var best = -1
        var bestD = Double.MAX_VALUE
        var bestT = 0.0
        for (i in max(0, hint - 3) until min(r.size - 1, hint + 300)) {
            val ax = (r[i][1] - lng) * k
            val ay = (r[i][0] - lat) * ky
            val dx = (r[i + 1][1] - lng) * k - ax
            val dy = (r[i + 1][0] - lat) * ky - ay
            val l2 = dx * dx + dy * dy
            val t = if (l2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / l2).coerceIn(0.0, 1.0)
            val d = hypot(ax + t * dx, ay + t * dy)
            if (d < bestD) { bestD = d; best = i; bestT = t }
        }
        if (best < 0 || bestD > 40.0) return false
        hint = best
        // Anda pela rota, amostrando a cada STEP metros.
        var i = best
        var ax = (r[i][1] - lng) * k
        var ay = (r[i][0] - lat) * ky
        var bx = (r[i + 1][1] - lng) * k
        var by = (r[i + 1][0] - lat) * ky
        var seg = hypot(bx - ax, by - ay)
        var done = bestT * seg + moved
        count = 0
        while (count < px.size) {
            while (done > seg) {
                done -= seg
                i++
                if (i >= r.size - 1) return count >= 2
                ax = bx; ay = by
                bx = (r[i + 1][1] - lng) * k
                by = (r[i + 1][0] - lat) * ky
                seg = hypot(bx - ax, by - ay)
            }
            val u = if (seg == 0.0) 0.0 else done / seg
            px[count] = ax + (bx - ax) * u
            py[count] = ay + (by - ay) * u
            count++
            done += STEP
        }
        return true
    }

    /** Fora da rota: estrada reta na direção do carro. */
    private fun sampleStraight(b: Double, moved: Double) {
        count = px.size
        for (i in 0 until count) {
            val d = moved + i * STEP
            px[i] = sin(b) * d
            py[i] = cos(b) * d
        }
    }

    /** Arredonda as curvas (a rota do carro vem com pontos espaçados). */
    private fun smooth() {
        for (pass in 0 until 2) {
            var x0 = px[0]
            var y0 = py[0]
            for (i in 1 until count - 1) {
                val x1 = px[i]
                val y1 = py[i]
                px[i] = (x0 + x1 * 2 + px[i + 1]) / 4
                py[i] = (y0 + y1 * 2 + py[i + 1]) / 4
                x0 = x1
                y0 = y1
            }
        }
    }

    // Câmera: leste/norte -> direita (x) e frente (z) do carro.
    private var cs = 1.0
    private var sn = 0.0
    private var cx = 0f
    private var hy = 0f
    private var f = 0f
    private fun rx(e: Double, n: Double) = e * cs - n * sn
    private fun rz(e: Double, n: Double) = e * sn + n * cs
    private fun sx(x: Double, z: Double) = (cx + f * x / z).toFloat()
    private fun sy(z: Double) = (hy + f * CAM_H / z).toFloat()

    // Lado do ponto i: posição (x, z) deslocada [off] metros para a direita.
    private fun sideX(i: Int, off: Double): Double {
        val a = max(0, i - 1)
        val b = min(count - 1, i + 1)
        val dx = px[b] - px[a]
        val dy = py[b] - py[a]
        val l = hypot(dx, dy).takeIf { it > 0 } ?: 1.0
        return px[i] + dy / l * off
    }

    private fun sideY(i: Int, off: Double): Double {
        val a = max(0, i - 1)
        val b = min(count - 1, i + 1)
        val dx = px[b] - px[a]
        val dy = py[b] - py[a]
        val l = hypot(dx, dy).takeIf { it > 0 } ?: 1.0
        return py[i] - dx / l * off
    }

    private val quad = Path()

    /** Quadrilátero da faixa [a, b] (m a partir do eixo) entre i e j. */
    private fun band(c: Canvas, i: Int, j: Int, a: Double, b: Double, p: Paint) {
        val a0x = sideX(i, a); val a0y = sideY(i, a)
        val b0x = sideX(i, b); val b0y = sideY(i, b)
        val a1x = sideX(j, a); val a1y = sideY(j, a)
        val b1x = sideX(j, b); val b1y = sideY(j, b)
        val za0 = rz(a0x, a0y); val zb0 = rz(b0x, b0y)
        val za1 = rz(a1x, a1y); val zb1 = rz(b1x, b1y)
        if (za0 < NEAR || zb0 < NEAR || za1 < NEAR || zb1 < NEAR) return
        quad.reset()
        quad.moveTo(sx(rx(a0x, a0y), za0), sy(za0))
        quad.lineTo(sx(rx(b0x, b0y), zb0), sy(zb0))
        quad.lineTo(sx(rx(b1x, b1y), zb1), sy(zb1))
        quad.lineTo(sx(rx(a1x, a1y), za1), sy(za1))
        quad.close()
        c.drawPath(quad, p)
    }

    override fun onDraw(c: Canvas) {
        val a = area ?: Rect(0, 0, width, height)
        val h = max(1, a.height())
        cx = a.exactCenterX()
        hy = a.top + h * 0.34f
        f = h * 1.05f
        if (skyH != height) {
            skyH = height
            sky.shader = LinearGradient(0f, 0f, 0f, hy, Color.rgb(5, 8, 15), Color.rgb(22, 34, 58), Shader.TileMode.CLAMP)
        }
        c.drawRect(0f, 0f, width.toFloat(), hy, sky)
        c.drawRect(0f, hy, width.toFloat(), height.toFloat(), ground)
        if (!CarState.hasPosition) return

        // Nova leitura do GPS: recomeça a contar; entre elas, anda sozinho.
        val now = System.currentTimeMillis()
        if (CarState.lat != lastLat || CarState.lng != lastLng) {
            lastLat = CarState.lat
            lastLng = CarState.lng
            lastAt = now
        }
        val moved = min(2.0, (now - lastAt) / 1000.0) * CarState.speedKmh / 3.6
        if (lastDraw > 0) odometer += min(500L, now - lastDraw) / 1000.0 * CarState.speedKmh / 3.6
        lastDraw = now
        val gps = Math.toRadians(CarState.bearing)
        onRoute = sampleRoute(lastLat, lastLng, moved)
        if (!onRoute) sampleStraight(gps, moved)
        if (count < 3) return
        smooth()

        // Olha para onde a rota vai (uns 25 m à frente), com suavidade.
        val look = min(5, count - 1)
        val want = atan2(px[look] - px[0], py[look] - py[0])
        if (viewBearing.isNaN()) viewBearing = want
        var diff = want - viewBearing
        while (diff > Math.PI) diff -= 2 * Math.PI
        while (diff < -Math.PI) diff += 2 * Math.PI
        viewBearing += diff * 0.15
        cs = cos(viewBearing)
        sn = sin(viewBearing)
        // A câmera anda na faixa da direita; a rota é o eixo da rua.
        val ox = px[0] + cs * LANE
        val oy = py[0] - sn * LANE
        for (i in 0 until count) {
            px[i] -= ox
            py[i] -= oy
        }

        for (i in count - 2 downTo 0) band(c, i, i + 1, -ROAD_HW, ROAD_HW, road)
        for (i in count - 2 downTo 0) {
            band(c, i, i + 1, ROAD_HW - 0.45, ROAD_HW - 0.25, line)
            band(c, i, i + 1, -ROAD_HW + 0.25, -ROAD_HW + 0.45, line)
            if ((i + (odometer / STEP).toLong()) % 2 == 0L) band(c, i, i + 1, -0.1, 0.1, axis)
        }

        // Tapete azul com faixas andando para a frente (some ao longe).
        if (onRoute) {
            val phase = ((now % 1000L) / 1000.0 * 2).toInt() % 2
            val last = min(count - 2, 28)
            for (i in last downTo 1) {
                val strong = (i + phase) % 2 == 0
                val fade = 1.0 - i.toDouble() / (last + 1)
                carpet.color = Color.argb(((if (strong) 190 else 120) * fade).toInt() + 25, 70, 220, 255)
                band(c, i, i + 1, LANE - 1.5, LANE + 1.5, carpet)
            }
            drawTurnArrows(c)
        }
    }

    /** Três setas flutuando no ponto da próxima conversão (até 200 m). */
    private fun drawTurnArrows(c: Canvas) {
        val n = CarState.nav ?: return
        val m = n.maneuver
        val side = when {
            m.contains("left") -> -1
            m.contains("right") -> 1
            else -> return
        }
        if (n.meters > 200 || n.meters < 8) return
        val i = min(count - 1, (n.meters / STEP).toInt())
        val z = rz(px[i], py[i])
        if (z < 6) return
        val x = rx(px[i], py[i])
        val s = f / z * 1.5 // tamanho na tela de uma seta de 1,5 m
        val y = sy(z) - (f * 3.0 / z).toFloat()
        for (k in 0..2) {
            val ax = sx(x, z) + (side * (k * 2.4 - 1.2) * s).toFloat()
            quad.reset()
            quad.moveTo(ax - side * 0.4f * s.toFloat(), y - s.toFloat())
            quad.lineTo(ax, y - s.toFloat())
            quad.lineTo(ax + side * 0.7f * s.toFloat(), y)
            quad.lineTo(ax, y + s.toFloat())
            quad.lineTo(ax - side * 0.4f * s.toFloat(), y + s.toFloat())
            quad.lineTo(ax + side * 0.3f * s.toFloat(), y)
            quad.close()
            c.drawPath(quad, arrow)
        }
    }
}
