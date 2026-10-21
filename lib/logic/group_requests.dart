// ============================================================================
// group_requests.dart — Pedidos ao grupo (só dentro da expedição)
//
// O que faz: Os atalhos que um piloto manda só para os pilotos da expedição
//   ("Preciso abastecer", "Parada para banheiro"...), as frases faladas e as
//   palavras do comando de voz ("UauGo, preciso abastecer").
// Quem usa: MapScreen (botão acima do SOS), ExpeditionService (envio),
//   voice_commands.dart (voz), functions/index.js (notificação, mesmos nomes).
// ============================================================================

/// Um pedido ao grupo. O [name] é gravado no servidor (não renomear).
enum GroupRequest {
  fuel('⛽', 'Preciso abastecer', 'precisa abastecer'),
  restroom('🚻', 'Parada para banheiro', 'pediu parada para banheiro'),
  rest('☕', 'Preciso descansar', 'precisa descansar'),
  problem('🔧', 'Problema no veículo', 'está com problema no veículo'),
  behind('🐢', 'Esperem, fiquei para trás', 'ficou para trás. Esperem'),
  ;

  const GroupRequest(this.emoji, this.label, this.spokenAction);
  final String emoji;
  final String label;

  /// Completa a frase depois do nome: "Ricardo precisa abastecer".
  final String spokenAction;

  static GroupRequest? fromName(String? n) =>
      GroupRequest.values.where((r) => r.name == n).firstOrNull;
}

/// Um pedido recebido ([ackName]: quem confirmou com "OK", se alguém).
typedef GroupRequestItem = ({
  String id,
  String uid,
  String name,
  GroupRequest kind,
  DateTime at,
  String? ackName,
});

/// Frase falada para o grupo: "Ricardo precisa abastecer".
String groupRequestSpeech(String who, GroupRequest r) {
  final name = who.trim().isEmpty ? 'Um piloto' : who.trim();
  return '$name ${r.spokenAction}';
}

/// Palavras do comando de voz (sem o "UauGo").
const groupRequestWords = <String, GroupRequest>{
  'preciso abastecer': GroupRequest.fuel,
  'abastecer': GroupRequest.fuel,
  'banheiro': GroupRequest.restroom,
  'parada banheiro': GroupRequest.restroom,
  'parada para banheiro': GroupRequest.restroom,
  'preciso descansar': GroupRequest.rest,
  'descansar': GroupRequest.rest,
  'problema na moto': GroupRequest.problem,
  'problema no carro': GroupRequest.problem,
  'problema no veículo': GroupRequest.problem,
  'fiquei para trás': GroupRequest.behind,
  'esperem': GroupRequest.behind,
};
