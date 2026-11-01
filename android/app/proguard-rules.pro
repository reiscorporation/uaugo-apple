# Regras extras da versão de loja (o R8 enxuga o código e não pode remover
# o que é criado por reflexão).

# Firebase: os "registrars" são criados pelo nome (sem eles, o App Check não
# inicia e o servidor recusa as gravações: PERMISSION_DENIED).
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.firebase.appcheck.** { *; }
-keep class com.google.android.play.core.integrity.** { *; }
-keep class com.google.android.play.integrity.** { *; }

# Voz offline (Vosk usa JNA, que acha as classes pelo nome).
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class org.vosk.** { *; }
-dontwarn java.awt.**

# Cena 3D do carro: a página chama o app por este método (Car3DView).
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface
