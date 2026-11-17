# Política de Privacidad de UauGo

Versión 1.16, del 30/10/2026. Esta es una traducción al español ofrecida por conveniencia; en caso de divergencia, prevalece la versión en portugués.

Esta Política explica qué datos personales trata la aplicación **UauGo** ("App"), para qué, con quién los comparte, por cuánto tiempo los guarda y cómo ejerces tus derechos, conforme a la **Ley General de Protección de Datos de Brasil (Ley 13.709/2018, "LGPD")**.

## 1. Quién es el responsable

- **Controlador:** Ricardo Reis, persona física, bajo la marca HelpAITech.
- **Encargado (contacto de privacidad):** Ricardo Reis — **helpaitech.ricardo@gmail.com**.

## 2. Principio de la App: lo mínimo posible en el servidor

Lo que puede quedar en tu celular queda en tu celular: **historial de viajes, configuración, teléfono, gastos y los datos de radares y límites**. En el servidor queda solo lo que necesita compartirse en vivo con otras personas (expedición en curso, alertas de la comunidad y club).

## 3. Datos tratados y finalidades

**Identificación de la cuenta**
- Identificador generado por Firebase (inicio de sesión anónimo) y, si entras con Google o correo, tu **nombre y correo**. Finalidad: identificar tu cuenta, impedir abusos y permitir recuperar el acceso. Base legal: ejecución del contrato (art. 7, V).
- Registro de la **aceptación de los Términos** y de las **autorizaciones** (versión, fecha y hora). Finalidad: comprobar la aceptación. Base legal: cumplimiento de obligación legal y ejercicio regular de derechos (art. 7, II y VI).

**Ubicación (GPS)**
- **Navegando solo o en "Solo manejar":** la ubicación se usa **solo en el celular** (ruta, avisos, velocímetro). **No se envía a nuestro servidor**. Para calcular la ruta y buscar lugares, los puntos necesarios (origen, destino, paradas y el texto de la búsqueda) pasan por nuestro servidor, que los envía a Google **sin guardarlos**; para el pronóstico del tiempo, los puntos de adelante se envían a Open-Meteo.
- **En una expedición:** tu posición, velocidad y hora se envían a los **participantes de la expedición** mientras esté abierta en la App. Con la App minimizada o la pantalla apagada, la posición solo se sigue enviando si activas la opción **"Compartir posición en segundo plano"** (Configuración → Pantalla), y entonces aparece la notificación fija "UauGo activo". Fuera de una expedición, tu posición no se envía al grupo ni se guarda en el servidor. Base legal: consentimiento (art. 7, I), dado en la pantalla de autorizaciones y al entrar a la expedición.
- **SOS:** tu posición se envía a los participantes de la expedición.
- **Alerta reportada:** la posición de la alerta, el sentido en que circulabas (en las alertas que valen para un solo sentido de la vía) y el identificador de quien la reportó quedan visibles para los usuarios durante la validez de la alerta.
- **Estadísticas de contribución (programa Usuario Oro):** cuántas alertas reportaste, cuántas fueron confirmadas por otros usuarios y cuántas fueron quitadas por la comunidad como inexistentes, además de la fecha de creación de tu cuenta. Finalidad: conceder o retirar automáticamente la condición de Usuario Oro (Términos de Uso, punto 7) y combatir alertas falsas. Solo tú ves tus números. Base legal: interés legítimo (art. 7, IX).

**Perfil mostrado al grupo**
- Nombre de piloto, marca, modelo, tipo y color del vehículo y la **foto del vehículo** (si la envías). Finalidad: mostrar quién es quién en el mapa de la expedición.

**Club (opcional, solo con tu autorización)**
- Cada club tiene **administradores**, habilitados con códigos de activación proporcionados por HelpAITech. Para entrar, cada miembro usa una **invitación de un solo uso** generada por un administrador. Guardamos quiénes son los administradores y **quién invitó a cada miembro**, para garantizar que solo participen miembros oficiales. Los administradores pueden quitar miembros. HelpAITech puede registrar previamente el **nombre** de clubes conocidos; solo aparecen en la App después de que un administrador del propio club activa el acceso.
- **Ciudad base** redondeada a ~1 km, nombre y club. Los demás miembros ven solo el nombre, la ciudad y la distancia aproximada, **nunca tu posición exacta**.
- **Teléfono:** queda **solo en tu celular** y se envía solo cuando pides ayuda o avisas a alguien y marcas esa opción.

**Comandos de voz (opcional, desactivado por defecto)**
- Si los activas en Configuración → Accesibilidad, la App usa el **micrófono** con el mapa abierto para reconocer comandos como "UauGo, radar" y las respuestas "sí"/"no". El reconocimiento se hace **en el propio celular** (sin internet): **el audio no se graba, no se guarda y no sale del aparato**. Solo los comandos reconocidos se convierten en acciones (por ejemplo, una alerta). Puedes desactivarlos en cualquier momento. Base legal: consentimiento (art. 7, I).
- **"Vehículo detenido en el acotamiento" (automático):** con la App en uso, cuando te quedes detenido más de 2 minutos en el acotamiento de una carretera, la App publica una alerta temporal de "vehículo detenido" en ese punto para quienes vienen atrás. La alerta **no muestra quién eres** (ni nombre, ni vehículo); queda solo el punto y la hora. Desaparece cuando vuelves a avanzar o en hasta 30 minutos, y puedes quitarla al instante tocando "No avisar" en el aviso que aparece en la pantalla. Base legal: protección de la vida y de la integridad física de terceros (art. 7, VII) e interés legítimo en la seguridad vial (art. 7, IX).
- **Pedidos hablados libres (IA):** cuando pides por voz algo fuera de la lista de comandos (ej.: "un restaurante bueno y barato"), el **texto** del pedido (no el audio) se envía a **Gemini, de Google**, a través del servidor de la App, solo para entender qué buscar. No se usa para otra finalidad y la App no lo guarda.
- **Búsqueda de trayecto por voz (opcional, desactivada):** si la activas, al decir "UauGo, ir a" la App escucha el destino con el **reconocimiento de voz de Android**. Cuando el celular ofrece reconocimiento en el propio aparato, el audio **no sale del celular**; si no lo ofrece, el audio de esa frase se envía a **Google**, que lo convierte en texto (sujeto a la política de privacidad de Google). La App usa el texto solo para buscar el lugar y no guarda el audio. Base legal: consentimiento (art. 7, I).

**Estadísticas de uso e informe de errores (puedes desactivarlos)**
- **Estadísticas anónimas de uso** (Google Analytics para Firebase): cuántas personas usan la App por día, semana y mes, en cuánto tiempo vuelven a usarla, qué funciones se usan (trazar ruta, Solo manejar, crear o entrar a una expedición, marcar alerta, comando de voz), modelo del celular, versión de Android y de la App, y región aproximada (ciudad/estado, estimada por la dirección de internet). **No incluye** tu ubicación exacta, nombre, correo, trayectos ni el contenido de las expediciones, y **no recolectamos el identificador de publicidad** ni usamos estos datos para publicidad.
- **Informe de errores** (Firebase Crashlytics): cuando la App se cierra o da error, envía lo que ocurrió (la parte del programa que falló), el modelo del celular y las versiones, para que lo corrijamos.
- Finalidad: entender el uso y mejorar la App. Base legal: interés legítimo (art. 7, IX). **Puedes desactivarlo** en cualquier momento en Configuración → "Compartir estadísticas de uso".

**Notificaciones**
- Token de notificaciones del celular (Firebase Cloud Messaging). Finalidad: avisar de SOS y paradas del grupo y de mensajes del club.

**Controles de música en el mapa (opcional, desactivado por defecto)**
- Si lo activas en Configuración y das el **"Acceso a notificaciones"** de Android, la App lee **solo la música que está sonando** (título, artista y portada, de apps como Spotify, YouTube Music o Deezer) para mostrar el mini reproductor y enviar los comandos anterior / reproducir-pausar / siguiente. Esto ocurre **solo en el celular**: nada se envía a nuestro servidor ni se guarda, y la App **no lee el contenido de tus notificaciones**. Puedes desactivar la opción o retirar el acceso en la configuración de Android en cualquier momento. Base legal: consentimiento (art. 7, I).

**Datos que quedan solo en el celular**
- Historial de viajes (camino, estadísticas, gastos), viajes planeados, configuración, consumo del vehículo, teléfono, **placa del vehículo** (usada solo para avisar del rodízio de São Paulo) y **contacto de emergencia** (nombre y WhatsApp, usado solo cuando tocas el SOS). **No tenemos acceso a ellos.** Desinstalar la App borra estos datos.

## 4. Con quién compartimos

- **Otros usuarios**, solo lo descrito arriba (participantes de tu expedición, miembros de tu club y alertas públicas).
- **Operadores (proveedores de servicios):** Google LLC (Firebase: base de datos, archivos, inicio de sesión, notificaciones, funciones, estadísticas de uso e informe de errores; Google Maps, Directions y Places) y Open-Meteo (pronóstico del tiempo, solo coordenadas, sin identificación).
- **Autoridades**, cuando haya obligación legal u orden judicial.
- **No vendemos** datos personales y no los usamos para publicidad.

## 5. Dónde quedan los datos

La base de datos, los archivos y las funciones del servidor quedan en la región **São Paulo (southamerica-east1)** de Google Cloud. Algunos servicios de Google (como mapas, rutas y notificaciones) pueden tratar datos en servidores fuera de Brasil, con las garantías previstas en los contratos de Google, conforme al art. 33 de la LGPD.

## 6. Por cuánto tiempo guardamos

- **Expedición** (participantes, posiciones, paradas, SOS): hasta que el líder la termine o después de **30 días sin actividad**.
- **Alertas de la comunidad:** durante la validez de cada tipo (de **1 hora a 7 días**), y después se borran automáticamente.
- **Avisos del club:** **180 días**.
- **Invitaciones del club:** hasta que vencen (**7 días**), y después se borran automáticamente.
- **Cuenta, autorizaciones y aceptación de los Términos:** mientras exista la cuenta.
- **Estadísticas de contribución y condición de Usuario Oro:** mientras exista la cuenta; se borran al borrar tus datos.
- **Estadísticas de uso:** el detalle por evento, durante **2 meses**; después quedan solo los totales (sin identificar a nadie).
- **Informes de error:** **90 días**.
- **Conteo diario de consultas de rutas y lugares** (solo el número, para limitar abusos): se reemplaza cada día.
- **Datos en el celular:** hasta que los borres o desinstales la App.

## 7. Tus derechos (art. 18 de la LGPD)

Puedes: confirmar si tratamos tus datos; acceder, corregir o actualizar tus datos; pedir anonimización, bloqueo o eliminación; pedir la portabilidad; saber con quién los compartimos; **revocar el consentimiento** en cualquier momento; y oponerte a tratamientos.

- **En la propia App:** "Privacidad y autorizaciones" permite cambiar las autorizaciones y **borrar todos tus datos** (servidor y celular) de inmediato.
- **Por correo:** helpaitech.ricardo@gmail.com. Respondemos en hasta **15 días**.
- También puedes reclamar ante la **Autoridad Nacional de Protección de Datos de Brasil (ANPD)**.

## 8. Seguridad

Usamos conexiones cifradas, reglas de acceso en la base de datos (cada persona solo lee lo que le está permitido), verificación de la aplicación (App Check) y borrado automático de datos antiguos. Ningún sistema es 100% seguro: en caso de un incidente relevante, lo comunicaremos a los afectados y a la ANPD, como manda la ley.

## 9. Cómo borrar tus datos

En la App: **Privacidad y autorizaciones → Borrar todos mis datos**. Esto borra tu cuenta, tus participaciones en expediciones, tu registro en el club, tus estadísticas de contribución y los datos del celular. Las alertas que reportaste dejan de estar asociadas a ti. Si ya no tienes la App, pídelo por correo a helpaitech.ricardo@gmail.com.

## 10. Edad mínima

La App está destinada a mayores de **18 años**. No tratamos intencionalmente datos de niños ni adolescentes.

## 11. Cambios

Podemos actualizar esta Política. Los cambios relevantes se informarán en la App y, cuando sea necesario, pediremos un nuevo consentimiento.

## 12. Contacto

**helpaitech.ricardo@gmail.com**
