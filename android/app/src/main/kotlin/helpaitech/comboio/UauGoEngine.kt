package helpaitech.comboio

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Motor do app (Dart) que o carro liga sozinho: com o Android Auto conectado
 * e o celular bloqueado, sem ninguém abrir o UauGo, o app sobe em segundo
 * plano e atende o carro. A tela do celular (MainActivity) usa o mesmo motor
 * quando ele já existe.
 */
object UauGoEngine {
    const val ID = "uaugo"

    fun cached(): FlutterEngine? = FlutterEngineCache.getInstance().get(ID)

    /** Pedido do carro: liga o app se preciso e entrega (ou guarda até ele subir). */
    fun send(ctx: Context, action: String) {
        ensureForCar(ctx)
        CarState.actionSink?.invoke(action)
    }

    /** Garante o app rodando (sem tela) para atender o carro. */
    fun ensureForCar(ctx: Context) {
        if (CarState.actionSink != null || cached() != null) return
        val e = FlutterEngine(ctx.applicationContext)
        CarBridge(e.dartExecutor.binaryMessenger)
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, e)
    }
}
