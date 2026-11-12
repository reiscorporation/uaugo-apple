// ============================================================================
// Car3DView.kt — A mesma cena 3D do celular na tela do carro (Android Auto)
//
// O que faz: Abre a página assets/sim3d/index.html numa WebView por cima do
//   mapa do carro, com o mesmo painel (velocidade, placa piscando, manobra),
//   as placas de saída e as rodovias reais. O celular manda os comandos da
//   cena pelo canal do carro (CarState.sim3d); a página nova recebe o último
//   de cada tipo ao abrir. Só existe enquanto aparece: em celular simples a
//   memória não comporta tudo ao mesmo tempo (CarMapView cria e libera).
// Quem usa: CarMapView (mostra/esconde conforme CarState.mode3d).
// Onde mexer: o desenho é o da página; aqui só a ponte e o espaço do painel.
// ============================================================================

package helpaitech.comboio

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.WebView

@SuppressLint("SetJavaScriptEnabled")
class Car3DView(context: Context) {
    val view = WebView(context)
    private var ready = false

    /** Pedido de voltar ao mapa (toque no minimapa). */
    var onMap: (() -> Unit)? = null

    /** Cena pronta para aparecer (até lá o mapa continua visível). */
    var onShown: (() -> Unit)? = null

    /** Noite pelo carro, não pelo celular (exigência da Play, 11/11). */
    var dark = false
        set(v) {
            field = v
            if (ready) view.evaluateJavascript("sim3d.setDark($v)", null)
        }

    /** Toque na tela do carro repassado à página (o minimapa ouve toques). */
    fun tap(x: Float, y: Float) {
        val t = android.os.SystemClock.uptimeMillis()
        val down = android.view.MotionEvent.obtain(t, t, android.view.MotionEvent.ACTION_DOWN, x, y, 0)
        view.dispatchTouchEvent(down)
        down.recycle()
        view.postDelayed({
            val t2 = android.os.SystemClock.uptimeMillis()
            val up = android.view.MotionEvent.obtain(t, t2, android.view.MotionEvent.ACTION_UP, x, y, 0)
            view.dispatchTouchEvent(up)
            up.recycle()
        }, 60)
    }
    private val density = context.resources.displayMetrics.density

    /** Área livre (fora dos botões do Android Auto). */
    var area: Rect? = null
        set(v) {
            field = v
            sendLayout()
        }

    init {
        view.setBackgroundColor(Color.rgb(5, 8, 15))
        view.settings.javaScriptEnabled = true
        view.settings.allowFileAccess = true
        view.addJavascriptInterface(object {
            @JavascriptInterface
            fun postMessage(m: String) {
                if (m == "ready") view.post { onReady() }
                // Toque no minimapa: volta ao mapa (11/11).
                if (m == "map") view.post { onMap?.invoke() }
            }
        }, "Sim3D")
        // O dia/noite do celular não vale aqui: quem manda é o carro.
        CarState.sim3dSink = { js -> if (ready && !js.startsWith("sim3d.setDark")) view.evaluateJavascript(js, null) }
        // #car: resolução e quadros menores (o celular já projeta a tela do carro).
        view.loadUrl("file:///android_asset/flutter_assets/assets/sim3d/index.html#car")
    }

    private fun onReady() {
        ready = true
        // Rota antes das vias: a página posiciona as vias sobre a rota.
        view.evaluateJavascript("sim3d.setDark($dark)", null)
        for (k in listOf("sim3d.setRoute", "sim3d.setRoads", "sim3d.setAlerts", "sim3d.update", "sim3d.hud")) {
            CarState.sim3dLast[k]?.let { view.evaluateJavascript(it, null) }
        }
        sendLayout()
        view.evaluateJavascript("sim3d.setActive(true)", null)
        // Um instante para o primeiro quadro antes de cobrir o mapa.
        view.postDelayed({ onShown?.invoke() }, 300)
    }

    /** Painel entre as bordas da área livre (em px da página). */
    private fun sendLayout() {
        val r = area ?: return
        if (!ready || view.width == 0) return
        val d = density
        val left = (r.left / d).toInt() + 8
        val right = ((view.width - r.right) / d).toInt() + 8
        val bottom = ((view.height - r.bottom) / d).toInt() + 8
        // topo livre (abaixo do cartão de manobra do Android Auto): minimapa
        // 12/11: minimapa no alto da tela (antes abaixo da linha de botões do
        // Android Auto, que ficam só no canto direito).
        val top = 0
        view.evaluateJavascript("sim3d.layout({l:$left,r:$right,b:$bottom,t:$top})", null)
    }

    fun destroy() {
        CarState.sim3dSink = null
        view.destroy()
    }
}
