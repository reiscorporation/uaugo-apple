// ============================================================================
// itinerary.dart — Agenda do roteiro da expedição
//
// O que faz: Calcula horários de chegada/saída de cada parada, divide a viagem
//   em dias e formata distâncias, tempos e horas ("1h20", "85 km", "10:43").
// Quem usa: PlanScreen (lista de paradas) e várias telas
//   (formatDistance/formatTime).
// Onde mexer: Regras de pausa e dias: classe Schedule.
// ============================================================================

import '../models/expedition.dart';
import '../l10n/i18n.dart';

/// Funções puras do roteiro (sem Firebase), para facilitar os testes.

/// Um ponto do roteiro com o dia e os horários previstos.
class ScheduledStop {
  final Stop stop;
  final int index; // posição no roteiro (0 = saída)
  final int day; // 1, 2, 3...
  final DateTime? arrival; // null na saída
  final DateTime departure; // no destino final, igual à chegada
  final int distanceFromStartM;

  ScheduledStop({
    required this.stop,
    required this.index,
    required this.day,
    required this.arrival,
    required this.departure,
    required this.distanceFromStartM,
  });

  bool get isStart => index == 0;
}

/// Resumo de um dia do roteiro: data, distância e tempo pilotando.
class DaySummary {
  final int day;
  final DateTime date;
  int distanceM = 0;
  int rideS = 0; // só tempo rodando, sem as paradas
  DaySummary(this.day, this.date);
}

/// Agenda completa do roteiro: cada parada com horários e os dias da
/// viagem. Montada por [buildSchedule].
class Schedule {
  final List<ScheduledStop> stops;
  final List<DaySummary> days;

  /// false quando a data de saída não foi definida: mostramos só os horários.
  final bool hasDate;
  Schedule(this.stops, this.days, this.hasDate);

  int get totalDistanceM => days.fold(0, (a, d) => a + d.distanceM);
  int get totalRideS => days.fold(0, (a, d) => a + d.rideS);
}

/// "HH:mm" -> (hora, minuto). Valor inválido vira 08:00.
(int, int) parseHm(String hm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hm.trim());
  if (m == null) return (8, 0);
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return (8, 0);
  return (h, min);
}

/// Lê "2026-10-05" (formato salvo no Firestore); null se vazio/inválido.
DateTime? parseDate(String ymd) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd.trim());
  if (m == null) return null;
  return DateTime(
      int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// Data no formato salvo no Firestore: "2026-10-05".
String formatYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_pad2(d.month)}-${_pad2(d.day)}';

/// Combina o dia com um horário "HH:MM".
DateTime _at(DateTime day, String hm) {
  final (h, m) = parseHm(hm);
  return DateTime(day.year, day.month, day.day, h, m);
}

/// Monta o cronograma: soma o tempo de cada trecho e das paradas; cada
/// pernoite encerra o dia e o dia seguinte começa na hora definida nele.
Schedule buildSchedule(TripPlan plan, List<Stop> stops) {
  final date = parseDate(plan.startDate);
  final base = date ?? DateTime(2000, 1, 1);
  final out = <ScheduledStop>[];
  final days = <DaySummary>[];
  if (stops.isEmpty) return Schedule(out, days, date != null);

  var day = 1;
  var cursor = _at(base, plan.startTime);
  var dist = 0;
  days.add(DaySummary(1, DateTime(cursor.year, cursor.month, cursor.day)));

  for (var i = 0; i < stops.length; i++) {
    final s = stops[i];
    DateTime? arrival;
    if (i > 0) {
      arrival = cursor.add(Duration(seconds: s.legDurationS));
      dist += s.legDistanceM;
      days.last
        ..distanceM += s.legDistanceM
        ..rideS += s.legDurationS;
      cursor = arrival;
    }
    final isLast = i == stops.length - 1;
    var departure = isLast ? cursor : cursor.add(Duration(minutes: s.stayMin));
    final stopDay = day;
    if (i > 0 && !isLast && s.type == StopType.overnight) {
      day++;
      final next = DateTime(cursor.year, cursor.month, cursor.day + 1);
      departure = _at(next, s.nextDayStart);
      days.add(DaySummary(day, next));
    }
    out.add(ScheduledStop(
      stop: s,
      index: i,
      day: stopDay,
      arrival: arrival,
      departure: departure,
      distanceFromStartM: dist,
    ));
    cursor = departure;
  }
  return Schedule(out, days, date != null);
}

/// Onde entra um ponto novo: antes do destino final (como no Google Maps),
/// ou no fim se ainda não houver destino.
int insertIndexFor(List<Stop> stops) =>
    stops.length >= 2 && stops.last.type == StopType.destination
        ? stops.length - 1
        : stops.length;

/// Tipo sugerido para um ponto novo: o 1º é o encontro, o 2º o destino.
StopType defaultTypeFor(List<Stop> stops) => switch (stops.length) {
      0 => StopType.meet,
      1 => StopType.destination,
      _ => StopType.waypoint,
    };

// ------------------------------------------------------------ formatação

/// Dois dígitos: 7 -> "07".
String _pad2(int n) => n.toString().padLeft(2, '0');

/// Hora para exibir: "07:30".
String formatTime(DateTime t) => '${_pad2(t.hour)}:${_pad2(t.minute)}';

const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysEs = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "sáb 12/10" (em inglês, "Sat 12/10")
String formatDay(DateTime d) =>
    '${(I18n.isEn ? _weekdaysEn : (I18n.isEs ? _weekdaysEs : _weekdays))[d.weekday - 1]} ${_pad2(d.day)}/${_pad2(d.month)}';

/// "850 m", "12,3 km", "245 km"
String formatDistance(int meters) {
  if (meters < 1000) return '$meters m';
  final km = meters / 1000;
  return km < 100
      ? '${I18n.isEn ? km.toStringAsFixed(1) : km.toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${km.round()} km';
}

/// "45 min", "2h", "3h15"
String formatDuration(int seconds) {
  final min = (seconds / 60).round();
  if (min < 60) return '$min min';
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '${h}h' : '${h}h${_pad2(m)}';
}

// ------------------------------------------------------------ exportação

/// O link do Google Maps aceita até 9 paradas intermediárias no celular.
const maxMapsWaypoints = 9;

/// Links que abrem a rota no Google Maps, um por dia (e divididos se o dia
/// tiver paradas demais). Cada link termina onde o próximo começa.
List<String> googleMapsLinks(Schedule s) {
  final links = <String>[];
  for (final d in s.days) {
    // O dia vai do pernoite anterior (ou da saída) até o último ponto dele.
    final from =
        d.day == 1 ? 0 : s.stops.lastIndexWhere((x) => x.day == d.day - 1);
    final to = s.stops.lastIndexWhere((x) => x.day == d.day);
    if (from < 0 || to <= from) continue;
    final pts = s.stops.sublist(from, to + 1).map((x) => x.stop).toList();
    for (var i = 0; i < pts.length - 1; i += maxMapsWaypoints + 1) {
      final end = (i + maxMapsWaypoints + 1).clamp(0, pts.length - 1);
      links.add(_mapsUrl(pts.sublist(i, end + 1)));
    }
  }
  return links;
}

/// Coordenada como texto para o link do Google Maps.
String _ll(Stop s) => '${s.lat.toStringAsFixed(6)},${s.lng.toStringAsFixed(6)}';

/// Link do Google Maps com a rota passando pelos pontos (para abrir no
/// app do Google, se o piloto preferir).
String _mapsUrl(List<Stop> pts) {
  final params = <String, String>{
    'api': '1',
    'origin': _ll(pts.first),
    'destination': _ll(pts.last),
    'travelmode': 'driving',
    if (pts.length > 2)
      'waypoints': pts.sublist(1, pts.length - 1).map(_ll).join('|'),
  };
  return Uri.https('www.google.com', '/maps/dir/', params).toString();
}

/// Mensagem pronta para o WhatsApp (negrito com *asteriscos*).
String buildShareText({
  required String expeditionName,
  required String code,
  required Schedule schedule,
}) {
  final b = StringBuffer()
    ..writeln('🏍️ *$expeditionName*')
    ..writeln();
  final s = schedule;
  if (s.stops.isNotEmpty) {
    b.writeln(tr('📏 {0} · ⏱️ {1} rodando{2}', [formatDistance(s.totalDistanceM), formatDuration(s.totalRideS), s.days.length > 1 ? tr(' · {0} dias', [s.days.length]) : '']));
  }
  for (final d in s.days) {
    b.writeln();
    final title = s.days.length > 1 ? tr('Dia {0}', [d.day]) : tr('Roteiro');
    b.writeln(s.hasDate
        ? '*$title – ${formatDay(d.date)}* (${formatDistance(d.distanceM)})'
        : '*$title* (${formatDistance(d.distanceM)})');
    for (final x in s.stops.where((x) => x.day == d.day)) {
      final when = x.isStart
          ? tr('saída {0}', [formatTime(x.departure)])
          : x.arrival != null
              ? formatTime(x.arrival!)
              : '';
      b.write('${x.stop.type.emoji} $when – ${x.stop.name}');
      if (!x.isStart && x.stop.stayMin > 0 && x.index < s.stops.length - 1 &&
          x.stop.type != StopType.overnight) {
        b.write(' (${formatDuration(x.stop.stayMin * 60)})');
      }
      b.writeln();
      if (x.stop.notes.trim().isNotEmpty) b.writeln('   _${x.stop.notes.trim()}_');
    }
  }
  final links = googleMapsLinks(s);
  if (links.isNotEmpty) {
    b
      ..writeln()
      ..writeln(links.length == 1 ? tr('🗺️ Rota no Google Maps:') : tr('🗺️ Rota no Google Maps (por trecho):'));
    for (final l in links) {
      b.writeln(l);
    }
  }
  b
    ..writeln()
    ..writeln(tr('👉 Para entrar no comboio, abra o app *UauGo* e use o código *{0}*', [code]));
  return b.toString().trimRight();
}
