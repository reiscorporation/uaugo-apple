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

/// Modelos de previsão consultados (Open-Meteo). Avisar só quando a
/// maioria concorda corta os alarmes falsos de um modelo só.
const rainModels = ['gfs_seamless', 'icon_seamless', 'ecmwf_ifs025'];

/// Chuva em que pelo menos 2 modelos concordam ([mmPer15minByModel]: maior
/// chuva prevista por modelo nos próximos 15–30 min). O nível é o do 2º mais
/// forte: aquele em que dois modelos concordam.
RainLevel rainConsensus(int weatherCode, List<double> mmPer15minByModel) {
  final levels = [
    for (final mm in mmPer15minByModel)
      // O código do tempo (WMO) só decide a trovoada; a quantidade decide o resto.
      rainLevel(weatherCode >= 95 ? weatherCode : 0, mm),
  ]..sort((a, b) => b.index.compareTo(a.index));
  if (levels.length < 2 || levels[1] == RainLevel.none) return RainLevel.none;
  return levels[1];
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
