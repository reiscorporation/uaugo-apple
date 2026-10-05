// Frases faladas pelo app (funções puras, para facilitar os testes).
// Escritas por extenso onde a voz do celular costuma ler mal ("km", "1,5").

/// "400 metros", "1 quilômetro", "1 quilômetro e meio", "3 quilômetros".
String spokenDistance(double meters) {
  if (meters < 950) {
    final step = meters < 300 ? 50 : 100;
    final m = ((meters / step).round() * step).clamp(50, 900);
    return '$m metros';
  }
  final halves = (meters / 500).round(); // arredonda para 0,5 km
  final whole = halves ~/ 2;
  final half = halves.isOdd;
  final unit = whole == 1 && !half ? 'quilômetro' : 'quilômetros';
  if (!half) return '$whole $unit';
  return whole == 1 ? '1 quilômetro e meio' : '$whole quilômetros e meio';
}

/// Distâncias em que o aviso é falado: [meters] dividido igualmente pelo
/// número de [repeats]. Ex.: 1000 m e 2 vezes -> [1000, 500];
/// 3 vezes -> [1000, 667, 333].
List<double> alertThresholds(double meters, int repeats) {
  final n = repeats.clamp(1, 5);
  return [for (var k = 0; k < n; k++) meters * (n - k) / n];
}

/// Já foram feitos [done] avisos; na distância [d], é hora do próximo?
/// Se o piloto pular mais de um ponto de uma vez, fala só o mais próximo.
/// Retorna quantos avisos ficam "feitos" depois de falar (ou null se não
/// é hora).
int? nextAlert(double d, int done, List<double> thresholds) {
  var k = done;
  while (k < thresholds.length && d <= thresholds[k]) {
    k++;
  }
  return k > done ? k : null;
}

/// "Atenção: buraco a 400 metros".
String hazardSpeech(String spokenName, double meters) =>
    'Atenção: $spokenName a ${spokenDistance(meters)}';

/// Frase do SOS de um membro do grupo (com a distância, se souber).
String sosSpeech(String name, double? meters) => meters == null
    ? 'S O S: $name pediu ajuda'
    : 'S O S: $name pediu ajuda, a ${spokenDistance(meters)}';

/// Aviso de que a próxima parada está chegando.
String nextStopSpeech(String name, double meters) =>
    'Próxima parada: $name, a ${spokenDistance(meters)}';

/// Chegou numa parada (ou no destino final).
String arrivalSpeech(String name, {required bool isDestination}) =>
    isDestination ? 'Você chegou ao destino: $name' : 'Chegando em $name';
