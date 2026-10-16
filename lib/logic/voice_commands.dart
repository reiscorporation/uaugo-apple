// ============================================================================
// voice_commands.dart — Frases dos comandos de voz (regras puras)
//
// O que faz: A lista FECHADA de frases que o reconhecimento aceita
//   ("UauGo, radar", "UauGo, ir para", "sim", "não"...) e a conversão do
//   resultado do Vosk em comando. Frases fora da lista viram "[unk]" e são ignoradas, assim
//   conversa e barulho do motor não disparam nada.
// Quem usa: VoiceCommandService.
// Onde mexer: Para um comando novo, inclua em [voiceAlertWords] (a palavra
//   precisa existir no modelo de português do Vosk) e teste em
//   test/voice_commands_test.dart.
// ============================================================================

import 'dart:convert';

import '../models/hazard.dart';
import 'find_places.dart';

/// Palavra de ativação: o nome do app, "UauGo" ("UauGo, radar"). O modelo
/// de voz não conhece "uaugo" inteiro, então ele é reconhecido como duas
/// palavras que conhece: "uau" + "go". [voiceWakeDisplay] é como aparece
/// na tela.
const voiceWakeWord = 'uau go';
const voiceWakeDisplay = 'UauGo';

/// Palavra falada -> tipo de alerta.
const voiceAlertWords = <String, HazardType>{
  'radar': HazardType.radar,
  'polícia': HazardType.police,
  'óleo': HazardType.oil,
  'buraco': HazardType.pothole,
  'lombada': HazardType.bump,
  'acidente': HazardType.accident,
  'animal': HazardType.animal,
  'neblina': HazardType.fog,
  'pipa': HazardType.kite,
  'perigo': HazardType.danger,
  'área de risco': HazardType.risk,
};

/// Confiança mínima (0 a 1) para aceitar. "Sim"/"não" exigem mais, porque
/// são palavras curtas que o barulho imita mais fácil.
const voiceMinConfidence = 0.6;
const voiceMinConfidenceYesNo = 0.85;

/// Os comandos, sem a palavra de ativação ("radar", "procurar posto"...).
List<String> _commandPhrases() => [
      for (final w in voiceAlertWords.keys) w,
      'cancelar',
      // "ir para ...": o destino (frase livre) é ouvido depois do bipe
      // (opção "Pesquisa de trajeto por voz").
      'ir para',
      'ir para [unk]',
      // Locais salvos: "UauGo, ir para casa" / "... para o trabalho".
      'ir para casa',
      'ir para o trabalho',
      'ir para trabalho',
      // "procurar posto" / "... restaurante barato" / "procurar" + outra coisa.
      for (final v in findVerbs) ...[
        for (final e in findWords.entries) ...[
          '$v ${e.key}',
          if (e.value.hasPrice) '$v ${e.key} barato',
        ],
        v,
        '$v [unk]',
      ],
      // Depois de "UauGo" + pausa: só a categoria ("restaurante").
      for (final e in findWords.entries) ...[
        e.key,
        if (e.value.hasPrice) '${e.key} barato',
      ],
    ];

/// Lista de frases para o reconhecedor (formato JSON do Vosk). As frases com
/// "[unk]" dão um caminho para exclamações ("uau, que paisagem linda"):
/// sem elas, o motor forçava o resto da frase num comando ("uau neblina").
/// O Vosk separa a frase numa pausa: "UauGo" ... "procurar posto" chegam
/// separados. Por isso os comandos também valem SEM a palavra de ativação,
/// mas só nos segundos depois de um "UauGo" sozinho (VoiceCommandService).
/// Testado com voz sintética + ruído de motor: nenhum disparo falso.
String voiceGrammar() => jsonEncode([
      voiceWakeWord,
      for (final c in _commandPhrases()) ...['$voiceWakeWord $c', c],
      '$voiceWakeWord [unk]',
      'uau [unk]',
      'uau que [unk]',
      'uau olha [unk]',
      'sim',
      'não',
      '[unk]',
    ]);

/// Comando reconhecido.
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "UauGo, radar": marcar um alerta.
class ReportCommand extends VoiceCommand {
  final HazardType type;
  const ReportCommand(this.type);
}

/// "UauGo, cancelar": desfaz o último alerta marcado por voz.
class CancelCommand extends VoiceCommand {
  const CancelCommand();
}

/// "UauGo, ir para": pesquisar um destino falando (o nome do lugar é
/// ouvido em seguida pelo reconhecimento do Google).
class GoToCommand extends VoiceCommand {
  /// Local salvo pedido ("casa", "trabalho"); null = ouvir o destino.
  final String? saved;
  const GoToCommand({this.saved});
}

/// "UauGo, procurar posto": achar um lugar desse tipo no caminho (ou perto).
/// [category] null = pediu algo fora da lista (o app explica como pedir).
class FindCommand extends VoiceCommand {
  final FindCategory? category;
  final bool cheap;
  const FindCommand(this.category, {this.cheap = false});
}

/// "UauGo" sozinho (ou "UauGo, procurar"): o app bipa e espera o comando
/// por alguns segundos ([find]: já sabe que é uma busca).
class WakeCommand extends VoiceCommand {
  final bool find;
  const WakeCommand({this.find = false});
}

/// Depois de um "UauGo" sozinho: o que veio é o resto do comando.
enum VoiceContext { wake, find }

/// "Sim" / "não": resposta à pergunta "ainda está lá?".
class AnswerCommand extends VoiceCommand {
  final bool yes;
  const AnswerCommand(this.yes);
}

/// Converte o resultado do Vosk (`{"text": ..., "result": [{"conf": ...}]}`)
/// em comando, ou null se não for um comando claro. Com [context] (logo
/// depois de um "UauGo" sozinho), a frase vale sem a palavra de ativação.
VoiceCommand? parseVoiceResult(String json, {VoiceContext? context}) {
  final Map<String, dynamic> r;
  try {
    r = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final words = [
    for (final w in (r['result'] as List?) ?? const [])
      (
        word: ((w as Map)['word'] as String?) ?? '',
        conf: (w['conf'] as num?)?.toDouble() ?? 0.0,
      ),
  ];
  // Ignora o "[unk]" ANTES do comando (silêncio/respiração no começo).
  final hadUnk = words.any((w) => w.word == '[unk]');
  while (words.isNotEmpty && words.first.word == '[unk]') {
    words.removeAt(0);
  }
  // Depois de "UauGo, procurar" + pausa, uma palavra fora da lista: pergunta.
  if (words.isEmpty) {
    return context == VoiceContext.find && hadUnk ? const FindCommand(null) : null;
  }
  final sure = words.every((w) => w.conf >= voiceMinConfidence);
  final plain = words.map((w) => w.word).join(' ');
  // "UauGo" sozinho / "UauGo, procurar" (pausa no meio da frase).
  if (sure && plain == voiceWakeWord) return const WakeCommand();
  if (sure && findVerbs.any((v) => plain == '$voiceWakeWord $v')) {
    return const WakeCommand(find: true);
  }
  final isWake = words.length >= 2 && words[0].word == 'uau' && words[1].word == 'go';
  if (context != null && !isWake && plain != 'sim' && plain != 'não') {
    // Logo depois do "UauGo": completa a frase ("restaurante" ->
    // "uau go procurar restaurante"; "radar" -> "uau go radar").
    final verb = context == VoiceContext.find ||
            findWords.containsKey(plain.replaceAll(' barato', ''))
        ? (findVerbs.contains(words.first.word) ? <String>[] : ['procurar'])
        : <String>[];
    words.insertAll(0, [
      for (final w in ['uau', 'go', ...verb]) (word: w, conf: 1.0),
    ]);
  }
  // "UauGo, ir para" (com ou sem o destino logo depois, que o Vosk não
  // conhece e marca como [unk]): só as 4 palavras do comando contam.
  const goTo = ['uau', 'go', 'ir', 'para'];
  if (words.length >= goTo.length &&
      [for (var i = 0; i < goTo.length; i++) words[i].word].join(' ') ==
          goTo.join(' ') &&
      words.take(goTo.length).every((w) => w.conf >= voiceMinConfidence)) {
    final rest = words.skip(goTo.length).map((w) => w.word).join(' ');
    if (rest == 'casa') return const GoToCommand(saved: 'casa');
    if (rest == 'trabalho' || rest == 'o trabalho') {
      return const GoToCommand(saved: 'trabalho');
    }
    return const GoToCommand();
  }
  // "UauGo, procurar <algo fora da lista>": avisa como pedir.
  if (words.length >= 3 &&
      words[0].word == 'uau' &&
      words[1].word == 'go' &&
      findVerbs.contains(words[2].word) &&
      words.take(3).every((w) => w.conf >= voiceMinConfidence) &&
      words.skip(3).any((w) => w.word == '[unk]')) {
    return const FindCommand(null);
  }
  final text = words.map((w) => w.word).join(' ').trim();
  if (text.isEmpty || text.contains('[unk]')) return null;
  final conf = words.map((w) => w.conf).reduce((a, b) => a < b ? a : b);

  if (text == 'sim' || text == 'não') {
    return conf >= voiceMinConfidenceYesNo ? AnswerCommand(text == 'sim') : null;
  }
  if (conf < voiceMinConfidence || !text.startsWith('$voiceWakeWord ')) {
    return null;
  }
  final what = text.substring(voiceWakeWord.length + 1);
  if (what == 'cancelar') return const CancelCommand();
  for (final v in findVerbs) {
    if (!what.startsWith('$v ')) continue;
    var rest = what.substring(v.length + 1);
    final cheap = rest.endsWith(' barato');
    if (cheap) rest = rest.substring(0, rest.length - ' barato'.length);
    final cat = findWords[rest];
    return cat == null ? null : FindCommand(cat, cheap: cheap && cat.hasPrice);
  }
  final type = voiceAlertWords[what];
  return type == null ? null : ReportCommand(type);
}

/// Tira do começo do destino falado as palavras de comando que muita gente
/// repete depois do bipe ("ir para São João da Boa Vista" -> "São João da
/// Boa Vista"), para a busca de lugares receber só o lugar.
String cleanDestination(String spoken) {
  var t = spoken.trim();
  final lead = RegExp(
      r'^(uau ?go[,]?\s+)?((eu )?(quero|queria|vamos|vou|preciso)( ir)?\s+)?'
      r'((me )?(leva|levar|leve)\s+)?'
      r'((ir|navegar|rota|traçar rota|trajeto|caminho)\s+)?'
      r'(para o|para a|para|pro|pra|até o|até a|até|ao|à)\s+',
      caseSensitive: false);
  final m = lead.firstMatch(t);
  if (m != null && m.end < t.length) t = t.substring(m.end).trim();
  return t;
}

