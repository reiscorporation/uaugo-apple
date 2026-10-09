// ============================================================================
// voice_commands.dart — Frases dos comandos de voz (regras puras)
//
// O que faz: A lista FECHADA de frases que o reconhecimento aceita
//   ("UauGo, radar", "sim", "não"...) e a conversão do resultado do Vosk
//   em comando. Frases fora da lista viram "[unk]" e são ignoradas, assim
//   conversa e barulho do motor não disparam nada.
// Quem usa: VoiceCommandService.
// Onde mexer: Para um comando novo, inclua em [voiceAlertWords] (a palavra
//   precisa existir no modelo de português do Vosk) e teste em
//   test/voice_commands_test.dart.
// ============================================================================

import 'dart:convert';

import '../models/hazard.dart';

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

/// Lista de frases para o reconhecedor (formato JSON do Vosk). As frases com
/// "[unk]" dão um caminho para exclamações ("uau, que paisagem linda"):
/// sem elas, o motor forçava o resto da frase num comando ("uau neblina").
/// Testado com voz sintética + ruído de motor: nenhum disparo falso.
String voiceGrammar() => jsonEncode([
      for (final w in voiceAlertWords.keys) '$voiceWakeWord $w',
      '$voiceWakeWord cancelar',
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

/// "Sim" / "não": resposta à pergunta "ainda está lá?".
class AnswerCommand extends VoiceCommand {
  final bool yes;
  const AnswerCommand(this.yes);
}

/// Converte o resultado do Vosk (`{"text": ..., "result": [{"conf": ...}]}`)
/// em comando, ou null se não for um comando claro.
VoiceCommand? parseVoiceResult(String json) {
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
  while (words.isNotEmpty && words.first.word == '[unk]') {
    words.removeAt(0);
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
  final type = voiceAlertWords[what];
  return type == null ? null : ReportCommand(type);
}
