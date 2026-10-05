/// Classificação da chuva (códigos WMO do Open-Meteo), função pura.
enum RainLevel { none, light, moderate, heavy, storm }

/// Nível de chuva pelo código do tempo (WMO) e pela quantidade em 15 min.
RainLevel rainLevel(int weatherCode, double mmPer15min) {
  if (weatherCode >= 95) return RainLevel.storm; // trovoada
  // Converte para mm/h (o Open-Meteo dá a soma em 15 min).
  final mmh = mmPer15min * 4;
  final rainyCode = (weatherCode >= 51 && weatherCode <= 67) ||
      (weatherCode >= 80 && weatherCode <= 82);
  if (!rainyCode && mmh < 0.4) return RainLevel.none;
  if (mmh >= 8) return RainLevel.heavy;
  if (mmh >= 2) return RainLevel.moderate;
  return RainLevel.light;
}

/// Nome do nível para mostrar e falar.
String rainWord(RainLevel l) => switch (l) {
      RainLevel.storm => 'Tempestade',
      RainLevel.heavy => 'Chuva forte',
      RainLevel.moderate => 'Chuva',
      RainLevel.light => 'Chuva fraca',
      RainLevel.none => '',
    };

/// "Chuva forte a aproximadamente 4 quilômetros à frente".
String rainSpeech(RainLevel l, double meters) {
  final km = (meters / 1000).round();
  return '${rainWord(l)} a aproximadamente '
      '${km <= 1 ? 'um quilômetro' : '$km quilômetros'} à frente';
}
