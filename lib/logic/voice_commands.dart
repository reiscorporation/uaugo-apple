// ============================================================================
// voice_commands.dart — Frases dos comandos de voz (regras puras)
//
// O que faz: A lista FECHADA de frases que o reconhecimento aceita
//   ("roda junto radar", "sim", "não"...) e a conversão do resultado do Vosk
//   em comando. Frases fora da lista viram "[unk]" e são ignoradas, assim
//   conversa e barulho do motor não disparam nada.
// Quem usa: VoiceCommandService.
// Onde mexer: Para um comando novo, inclua em [voiceAlertWords] (a palavra
//   precisa existir no modelo de português do Vosk) e teste em
//   test/voice_commands_test.dart.
// ============================================================================

import 'dart:convert';

import '../models/hazard.dart';

/// Palavra de ativação: todo comando começa com ela ("roda junto radar").
const voiceWakeWord = 'roda junto';

/// Palavra falada -> tipo de alerta.
const voiceAlertWords = <String, HazardType>{
  'radar': HazardType.radar,
  'polícia': HazardType.police,
  'óleo': HazardType.oil,
  'buraco': HazardType.pothole,
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

/// Lista de frases para o reconhecedor (formato JSON do Vosk).
String voiceGrammar() => jsonEncode([
      for (final w in voiceAlertWords.keys) '$voiceWakeWord $w',
      '$voiceWakeWord cancelar',
      'sim',
      'não',
      '[unk]',
    ]);

/// Comando reconhecido.
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "Roda junto radar": marcar um alerta.
class ReportCommand extends VoiceCommand {
  final HazardType type;
  const ReportCommand(this.type);
}

/// "Roda junto cancelar": desfaz o último alerta marcado por voz.
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
  final text = ((r['text'] as String?) ?? '').trim();
  if (text.isEmpty || text.contains('[unk]')) return null;
  final words = (r['result'] as List?) ?? const [];
  final conf = words.isEmpty
      ? 0.0
      : words
          .map((w) => ((w as Map)['conf'] as num?)?.toDouble() ?? 0)
          .reduce((a, b) => a < b ? a : b);

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
