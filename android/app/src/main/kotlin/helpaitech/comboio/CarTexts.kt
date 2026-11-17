// ============================================================================
// CarTexts.kt — Textos da tela do carro em português, inglês e espanhol
//
// O que faz: tx(en, pt) devolve o texto no idioma do app (vem do celular em
//   CarState.en / CarState.es). O espanhol sai de CAR_ES pela frase em
//   português; texto com parte variável passa o espanhol direto em [es].
// Quem usa: CarOverlay e UauGoCarAppService.
// Onde mexer: frase nova na tela do carro: tx("inglês", "português") e a
//   tradução em CAR_ES (sem ela, aparece em português no espanhol). 17/11.
// ============================================================================
package helpaitech.comboio

fun tx(en: String, pt: String, es: String? = null): String = when {
    CarState.en -> en
    CarState.es -> es ?: CAR_ES[pt] ?: pt
    else -> pt
}

val CAR_ES: Map<String, String> = mapOf(
    "Chegada" to "Llegada",
    "Libere o acesso à música no celular" to "Da acceso a la música en el celular",
    "Nada tocando" to "Nada sonando",
    "COMBOIO" to "CONVOY",
    "Toque novamente\npara enviar" to "Toca de nuevo\npara enviar",
    "Siga em frente" to "Sigue derecho",
    "Destino" to "Destino",
    "Só mapa" to "Solo mapa",
    "3D nas saídas" to "3D en las salidas",
    "3D sempre" to "3D siempre",
    "Norte para cima" to "Norte arriba",
    "Mapa na direção do carro" to "Mapa en la dirección del auto",
    "Abra o UauGo no celular" to "Abre UauGo en el celular",
    "Buscando…" to "Buscando…",
    "Nada encontrado" to "No se encontró nada",
    "Digite ou fale o lugar" to "Escribe o di el lugar",
    "Calculando a rota…" to "Calculando la ruta…",
    "Para onde?" to "¿A dónde?",
    "Buscar outro destino" to "Buscar otro destino",
    "📍 Parada no caminho" to "📍 Parada en el camino",
    "Posto, comida, café… o destino continua" to "Gasolinera, comida, café… el destino sigue",
    "Salve locais ou busque no celular antes" to "Guarda lugares o busca en el celular antes",
    "Destinos" to "Destinos",
    "🚫 Radar não existe" to "🚫 El radar no existe",
    "Corrigir para 20 a 60 km/h" to "Corregir a 20 a 60 km/h",
    "Corrigir para 70 a 120 km/h" to "Corregir a 70 a 120 km/h",
    "Corrigir velocidade" to "Corregir velocidad",
    "Ligar para " to "Llamar a ",
    "Contato de emergência" to "Contacto de emergencia",
    "Emergência · localização ao vivo ligada" to "Emergencia · ubicación en vivo activada",
    "Tela do carro" to "Pantalla del auto",
    "Configurações" to "Configuración",
    "Desligado: o mapa gira com o carro" to "Desactivado: el mapa gira con el auto",
    "Libere o acesso à música no UauGo do celular (Configurações)" to "Da acceso a la música en UauGo del celular (Configuración)",
    "Nada tocando. Abra seu app de música (Spotify, YouTube Music...)." to "Nada sonando. Abre tu app de música (Spotify, YouTube Music...).",
    "⏸  Pausar" to "⏸  Pausar",
    "▶  Tocar" to "▶  Reproducir",
    "⏭  Próxima" to "⏭  Siguiente",
    "⏮  Anterior" to "⏮  Anterior",
    "Música" to "Música",
    "Sim, continuar" to "Sí, continuar",
    "Não" to "No",
    "Parada no caminho" to "Parada en el camino",
    "Nada encontrado à frente" to "No se encontró nada adelante",
    "Incluindo a parada…" to "Incluyendo la parada…",
    "📍 Parar no caminho" to "📍 Parar en el camino",
    "O destino atual continua" to "El destino actual sigue",
    "🏁 Ir direto para lá" to "🏁 Ir directo allá",
    "Troca o destino" to "Cambia el destino",
    "Radar móvel" to "Radar móvil",
    "Polícia" to "Policía",
    "Acidente" to "Accidente",
    "Buraco" to "Bache",
    "Perigo na pista" to "Peligro en la vía",
    "Animal na pista" to "Animal en la vía",
    "Óleo / areia" to "Aceite / arena",
    "Neblina" to "Neblina",
    "🗑️  Remover meu alerta" to "🗑️  Quitar mi alerta",
    "O que tem na pista?" to "¿Qué hay en la vía?",
    "Remover meu alerta" to "Quitar mi alerta",
    "Preciso abastecer" to "Necesito cargar combustible",
    "Parada para banheiro" to "Parada para el baño",
    "Preciso descansar" to "Necesito descansar",
    "Problema no veículo" to "Problema en el vehículo",
    "Esperem, fiquei para trás" to "Espérenme, me quedé atrás",
    "Pedido ao grupo" to "Pedido al grupo",
    // Tipos de parada e telefones de emergência (listas com pt/en)
    "⛽ Posto" to "⛽ Gasolinera",
    "🍽️ Restaurante" to "🍽️ Restaurante",
    "☕ Café" to "☕ Café",
    "💊 Farmácia" to "💊 Farmacia",
    "🛞 Borracharia" to "🛞 Vulcanizadora",
    "🛏️ Hospedagem" to "🛏️ Hospedaje",
    "⚡ Eletroposto" to "⚡ Estación de carga",
    "SAMU (ambulância)" to "SAMU (ambulancia)",
    "Bombeiros (resgate)" to "Bomberos (rescate)",
    "PRF (rodovias federais)" to "PRF (carreteras federales)",
    "Polícia Militar" to "Policía Militar",
)
