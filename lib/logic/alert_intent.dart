// ============================================================================
// alert_intent.dart — Que alerta o piloto falou? (regras puras)
//
// O que faz: Recebe a frase livre dita na tela de alertas ("tem óleo na
//   pista", "cachorro na pista", "polícia à frente") e devolve o tipo de
//   alerta. Entende sinônimos e frases inteiras, não só a palavra exata:
//   procura a expressão MAIS LONGA que aparece na frase (assim "radar móvel"
//   vence "radar" e "pista perigosa" vence "pista").
//   Também define a ORDEM das categorias na tela de alertas.
// Quem usa: MapScreen (tela "O que tem na pista?").
// Onde mexer: sinônimo novo → [_phrases]; teste em
//   test/alert_intent_test.dart.
// ============================================================================

import '../models/hazard.dart';

/// Ordem da tela de alertas (pedido de 23/11): polícia, radar fixo, óleo,
/// animal, pipas/cerol, buraco, risco na pista, área de risco e depois os
/// demais, na ordem em que já apareciam.
List<HazardType> get alertSheetOrder {
  const first = [
    HazardType.police,
    HazardType.fixedRadar,
    HazardType.oil,
    HazardType.animal,
    HazardType.kite,
    HazardType.pothole,
    HazardType.danger,
    HazardType.roadworks,
    HazardType.risk,
  ];
  return [
    ...first,
    for (final t in HazardType.values)
      if (!first.contains(t)) t,
  ];
}

/// Expressão (sem acento, minúscula) -> tipo. Português, inglês e espanhol.
const _phrases = <String, HazardType>{
  // Polícia
  'policia': HazardType.police,
  'policial': HazardType.police,
  'policiais': HazardType.police,
  'viatura': HazardType.police,
  'blitz': HazardType.police,
  'batida policial': HazardType.police,
  'operacao policial': HazardType.police,
  'prf': HazardType.police,
  'pm': HazardType.police,
  'guarda': HazardType.police,
  'rodoviaria': HazardType.police,
  'police': HazardType.police,
  'cop': HazardType.police,
  'cops': HazardType.police,
  'policia en la ruta': HazardType.police,
  // Radar fixo ("radar" sozinho = fixo; o móvel tem botão próprio)
  'radar': HazardType.fixedRadar,
  'radar fixo': HazardType.fixedRadar,
  'pardal': HazardType.fixedRadar,
  'lombada eletronica': HazardType.fixedRadar,
  'fotossensor': HazardType.fixedRadar,
  'controlador de velocidade': HazardType.fixedRadar,
  'speed camera': HazardType.fixedRadar,
  'radar fijo': HazardType.fixedRadar,
  'fotomulta': HazardType.fixedRadar,
  // Radar móvel
  'radar movel': HazardType.radar,
  'radar portatil': HazardType.radar,
  'radar de pistola': HazardType.radar,
  'mobile radar': HazardType.radar,
  'radar movil': HazardType.radar,
  // Óleo / areia
  'oleo': HazardType.oil,
  'areia': HazardType.oil,
  'cascalho': HazardType.oil,
  'brita': HazardType.oil,
  'graxa': HazardType.oil,
  'diesel': HazardType.oil,
  'lama': HazardType.oil,
  'barro': HazardType.oil,
  'escorregadia': HazardType.oil,
  'escorregadio': HazardType.oil,
  'pista lisa': HazardType.oil,
  'oil': HazardType.oil,
  'sand': HazardType.oil,
  'gravel': HazardType.oil,
  'slippery': HazardType.oil,
  'aceite': HazardType.oil,
  'arena': HazardType.oil,
  'grava': HazardType.oil,
  // Animal
  'animal': HazardType.animal,
  'animais': HazardType.animal,
  'bicho': HazardType.animal,
  'cachorro': HazardType.animal,
  'cao': HazardType.animal,
  'cavalo': HazardType.animal,
  'boi': HazardType.animal,
  'vaca': HazardType.animal,
  'gado': HazardType.animal,
  'capivara': HazardType.animal,
  'gato': HazardType.animal,
  'jumento': HazardType.animal,
  'burro': HazardType.animal,
  'porco': HazardType.animal,
  'cabrito': HazardType.animal,
  'anta': HazardType.animal,
  'dog': HazardType.animal,
  'horse': HazardType.animal,
  'cow': HazardType.animal,
  'perro': HazardType.animal,
  'caballo': HazardType.animal,
  // Pipas / cerol
  'pipa': HazardType.kite,
  'pipas': HazardType.kite,
  'papagaio': HazardType.kite,
  'cerol': HazardType.kite,
  'linha chilena': HazardType.kite,
  'linha de pipa': HazardType.kite,
  'kite': HazardType.kite,
  'kites': HazardType.kite,
  'cometa': HazardType.kite,
  'barrilete': HazardType.kite,
  // Buraco
  'buraco': HazardType.pothole,
  'buracos': HazardType.pothole,
  'cratera': HazardType.pothole,
  'panela': HazardType.pothole,
  'pothole': HazardType.pothole,
  'bache': HazardType.pothole,
  'pozo': HazardType.pothole,
  // Risco na pista (objeto/obstáculo)
  'risco na pista': HazardType.danger,
  'perigo': HazardType.danger,
  'perigo na pista': HazardType.danger,
  'objeto na pista': HazardType.danger,
  'pedra na pista': HazardType.danger,
  'pedra': HazardType.danger,
  'obstaculo': HazardType.danger,
  'galho': HazardType.danger,
  'arvore caida': HazardType.danger,
  'pneu na pista': HazardType.danger,
  'carga caida': HazardType.danger,
  'entulho': HazardType.danger,
  'hazard': HazardType.danger,
  'object on the road': HazardType.danger,
  'peligro': HazardType.danger,
  'objeto en la ruta': HazardType.danger,
  // Obras na pista
  'obra': HazardType.roadworks,
  'obras': HazardType.roadworks,
  'obras na pista': HazardType.roadworks,
  'obra na pista': HazardType.roadworks,
  'pista interditada': HazardType.roadworks,
  'faixa interditada': HazardType.roadworks,
  'interditado': HazardType.roadworks,
  'interditada': HazardType.roadworks,
  'maquinas na pista': HazardType.roadworks,
  'cones': HazardType.roadworks,
  'roadworks': HazardType.roadworks,
  'road works': HazardType.roadworks,
  'construction': HazardType.roadworks,
  'obras en la via': HazardType.roadworks,
  // Área de risco (assalto / lugar perigoso)
  'area de risco': HazardType.risk,
  'pista perigosa': HazardType.risk,
  'estrada perigosa': HazardType.risk,
  'rua perigosa': HazardType.risk,
  'lugar perigoso': HazardType.risk,
  'regiao perigosa': HazardType.risk,
  'perigoso': HazardType.risk,
  'perigosa': HazardType.risk,
  'assalto': HazardType.risk,
  'assaltante': HazardType.risk,
  'roubo': HazardType.risk,
  'arrastao': HazardType.risk,
  'risk area': HazardType.risk,
  'dangerous road': HazardType.risk,
  'robbery': HazardType.risk,
  'zona de riesgo': HazardType.risk,
  'asalto': HazardType.risk,
  'peligrosa': HazardType.risk,
  // Lombada
  'lombada': HazardType.bump,
  'quebra molas': HazardType.bump,
  'redutor': HazardType.bump,
  'speed bump': HazardType.bump,
  'tope': HazardType.bump,
  'lomo de burro': HazardType.bump,
  // Acidente
  'acidente': HazardType.accident,
  'batida': HazardType.accident,
  'colisao': HazardType.accident,
  'capotou': HazardType.accident,
  'tombou': HazardType.accident,
  'engavetamento': HazardType.accident,
  'accident': HazardType.accident,
  'crash': HazardType.accident,
  'accidente': HazardType.accident,
  'choque': HazardType.accident,
  // Neblina
  'neblina': HazardType.fog,
  'nevoeiro': HazardType.fog,
  'cerracao': HazardType.fog,
  'fog': HazardType.fog,
  'niebla': HazardType.fog,
  // Semáforo
  'semaforo': HazardType.signal,
  'farol': HazardType.signal,
  'sinaleiro': HazardType.signal,
  'traffic light': HazardType.signal,
  // Veículo parado
  'veiculo parado': HazardType.stoppedVehicle,
  'carro parado': HazardType.stoppedVehicle,
  'caminhao parado': HazardType.stoppedVehicle,
  'moto parada': HazardType.stoppedVehicle,
  'carro quebrado': HazardType.stoppedVehicle,
  'acostamento': HazardType.stoppedVehicle,
  'stopped vehicle': HazardType.stoppedVehicle,
  'vehiculo detenido': HazardType.stoppedVehicle,
};

/// Tira acentos e pontuação e deixa minúsculo ("Óleo, na PISTA!" → "oleo na pista").
String normalizeSpoken(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b
      .toString()
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Tipo de alerta da frase falada, ou null se não reconheceu nenhum.
/// Vale a expressão mais longa encontrada (palavra inteira).
HazardType? alertFromSpeech(String? said) {
  if (said == null) return null;
  final text = ' ${normalizeSpoken(said)} ';
  if (text.trim().isEmpty) return null;
  HazardType? best;
  var bestLen = 0;
  for (final e in _phrases.entries) {
    if (e.key.length <= bestLen) continue;
    if (text.contains(' ${e.key} ')) {
      best = e.value;
      bestLen = e.key.length;
    }
  }
  return best;
}
