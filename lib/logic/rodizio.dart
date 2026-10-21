// ============================================================================
// rodizio.dart — Rodízio municipal de São Paulo (placa x dia/horário)
//
// O que faz: Diz se a placa está no rodízio agora (ou num horário), se um
//   ponto está no Centro Expandido (área do rodízio) e se a rota passa por
//   ele. Fontes (out/2026): CET-SP e imprensa — seg a sex, 7h–10h e
//   17h–20h; final 1-2 seg, 3-4 ter, 5-6 qua, 7-8 qui, 9-0 sex; não vale
//   sábado, domingo e feriado; motos e similares não participam.
// Quem usa: TripPreviewSheet (aviso antes de sair), MapScreen (voz ao
//   entrar na área), ProfileScreen (placa).
// Onde mexer: área [centroExpandido] (APROXIMADA, pelo Minianel Viário);
//   feriados fixos em [_feriados]. Só São Paulo tem rodízio por placa.
// ============================================================================

import '../models/bike.dart';

/// Contorno APROXIMADO do Centro Expandido (Minianel Viário): marginais
/// Tietê e Pinheiros, Av. dos Bandeirantes, Complexo Maria Maluf, Av.
/// Tancredo Neves/Juntas Provisórias, Viaduto Grande São Paulo, Av. Anhaia
/// Melo e Av. Salim Farah Maluf. (lat, lng)
const centroExpandido = <(double, double)>[
  (-23.5280, -46.7450), // Cebolão (marginais Tietê x Pinheiros)
  (-23.5120, -46.7000),
  (-23.5080, -46.6500),
  (-23.5150, -46.6150),
  (-23.5250, -46.5850), // Marginal Tietê x Av. Salim Farah Maluf
  (-23.5450, -46.5700),
  (-23.5650, -46.5650),
  (-23.5850, -46.5650), // Av. Anhaia Melo
  (-23.5950, -46.5900), // Viaduto Grande São Paulo
  (-23.6000, -46.6100), // Juntas Provisórias / Tancredo Neves
  (-23.6080, -46.6300), // Complexo Maria Maluf
  (-23.6050, -46.6600), // Av. dos Bandeirantes
  (-23.6000, -46.6950), // Bandeirantes x Marginal Pinheiros
  (-23.5700, -46.7050),
  (-23.5450, -46.7300),
];

/// Feriados de data fixa (dd/mm) em que o rodízio não vale (nacionais e o
/// aniversário de São Paulo). Feriados móveis (Carnaval, Sexta Santa,
/// Corpus Christi) e a suspensão de fim de ano não estão aqui.
const _feriados = {
  '1/1', '25/1', '21/4', '1/5', '9/7', '7/9', '12/10', '2/11', '15/11',
  '20/11', '25/12',
};

/// Último dígito da placa (null se não houver dígito).
int? plateDigit(String plate) {
  final d = plate.replaceAll(RegExp(r'[^0-9]'), '');
  return d.isEmpty ? null : int.parse(d[d.length - 1]);
}

/// Dia da semana do rodízio para o final [digit] (1 = segunda ... 5 = sexta).
int rodizioWeekday(int digit) => switch (digit) {
      1 || 2 => DateTime.monday,
      3 || 4 => DateTime.tuesday,
      5 || 6 => DateTime.wednesday,
      7 || 8 => DateTime.thursday,
      _ => DateTime.friday, // 9 e 0
    };

/// Nome do dia ("segunda-feira"...).
String rodizioDayName(int weekday) => const {
      DateTime.monday: 'segunda-feira',
      DateTime.tuesday: 'terça-feira',
      DateTime.wednesday: 'quarta-feira',
      DateTime.thursday: 'quinta-feira',
      DateTime.friday: 'sexta-feira',
    }[weekday]!;

/// O veículo participa do rodízio? (motos e similares não).
bool subjectToRodizio(BikeStyle style) => !style.isMoto;

/// Hoje é dia de rodízio para o final [digit]? (dia útil, não feriado fixo)
bool rodizioDay(int digit, DateTime t) =>
    t.weekday == rodizioWeekday(digit) && !_feriados.contains('${t.day}/${t.month}');

/// Dentro do horário (7h–10h ou 17h–20h)?
bool rodizioHour(DateTime t) {
  final m = t.hour * 60 + t.minute;
  return (m >= 7 * 60 && m < 10 * 60) || (m >= 17 * 60 && m < 20 * 60);
}

/// Restrição valendo agora para o final [digit].
bool rodizioNow(int digit, DateTime t) => rodizioDay(digit, t) && rodizioHour(t);

/// O ponto está no Centro Expandido? (área aproximada)
bool insideCentroExpandido(double lat, double lng) {
  var inside = false;
  final pts = centroExpandido;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final (yi, xi) = pts[i];
    final (yj, xj) = pts[j];
    if ((yi > lat) != (yj > lat) &&
        lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// A rota passa pelo Centro Expandido?
bool routeCrossesCentro(List<(double, double)> route) {
  // Caixa da área: descarta rápido rotas longe de São Paulo.
  for (var i = 0; i < route.length; i++) {
    final (la, lo) = route[i];
    if (la < -23.62 || la > -23.50 || lo < -46.76 || lo > -46.55) continue;
    if (insideCentroExpandido(la, lo)) return true;
  }
  return false;
}

/// Aviso para a prévia da rota, ou null se não há problema. [when] = hora
/// da viagem (saída).
String? rodizioWarning({
  required String plate,
  required BikeStyle style,
  required List<(double, double)> route,
  required DateTime when,
}) {
  final d = plateDigit(plate);
  if (d == null || !subjectToRodizio(style) || !rodizioDay(d, when)) return null;
  if (!routeCrossesCentro(route)) return null;
  return 'Rodízio em São Paulo: placa final $d não pode circular no centro '
      'expandido ${rodizioDayName(rodizioWeekday(d))} das 7h às 10h e das '
      '17h às 20h, e esta rota passa por lá.';
}
