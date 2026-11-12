// ============================================================================
// address_abbrev.dart — Abreviações de endereço na busca ("av" = Avenida)
//
// O que faz: Troca as abreviações comuns que o piloto digita pela palavra
//   inteira ("av. aparecido savegnago" -> "Avenida aparecido savegnago"),
//   para a busca achar o lugar mesmo quando o nome oficial vem por extenso.
//   Só troca palavras inteiras (com ou sem ponto) e só as conhecidas.
// Quem usa: PlacesService.search (busca a versão digitada e a expandida).
// Onde mexer: lista _abbrev.
// ============================================================================

/// Abreviação (sem ponto, minúscula) -> palavra inteira.
const _abbrev = <String, String>{
  'av': 'Avenida', 'avd': 'Avenida', 'avda': 'Avenida', 'aven': 'Avenida',
  'r': 'Rua',
  'rod': 'Rodovia', 'rdv': 'Rodovia',
  'al': 'Alameda',
  'pc': 'Praça', 'pca': 'Praça', 'pça': 'Praça', 'pç': 'Praça',
  'est': 'Estrada', 'estr': 'Estrada',
  'tv': 'Travessa', 'trav': 'Travessa',
  'lgo': 'Largo', 'lg': 'Largo',
  'vd': 'Viaduto',
  'jd': 'Jardim', 'jdm': 'Jardim', 'jardim': 'Jardim',
  'pq': 'Parque', 'pque': 'Parque',
  'vl': 'Vila',
  'cj': 'Conjunto', 'conj': 'Conjunto',
  'res': 'Residencial', 'resid': 'Residencial',
  'cond': 'Condomínio',
  'dr': 'Doutor', 'dra': 'Doutora',
  'prof': 'Professor', 'profa': 'Professora', 'profª': 'Professora',
  'eng': 'Engenheiro',
  'pres': 'Presidente',
  'gov': 'Governador',
  'cel': 'Coronel',
  'gal': 'General', 'gen': 'General',
  'mal': 'Marechal',
  'cap': 'Capitão',
  'ten': 'Tenente',
  'sgt': 'Sargento',
  'brig': 'Brigadeiro',
  'cmte': 'Comandante', 'com': 'Comendador',
  'dep': 'Deputado',
  'sen': 'Senador',
  'ver': 'Vereador',
  'pe': 'Padre',
  'fr': 'Frei',
  'd': 'Dom',
  'sta': 'Santa', 'sto': 'Santo',
  'n.s': 'Nossa Senhora', 'ns': 'Nossa Senhora', 'nsa': 'Nossa Senhora',
  'sr': 'Senhor', 'sra': 'Senhora',
};

/// Palavras que só são abreviação no começo do texto (no meio, "r" ou "d"
/// podem ser parte de um nome: "Bloco D", "Dom Pedro I").
const _onlyFirst = {'r', 'd', 'pe', 'com', 'ver', 'est', 'res', 'al', 'pc'};

/// Texto com as abreviações trocadas; igual ao original se não havia nenhuma.
String expandAddressAbbrev(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  var changed = false;
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    // "av." / "av" / "Av" / "R." (o ponto final é opcional).
    final key = w.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
    final full = _abbrev[key];
    final hadDot = w.endsWith('.');
    // Palavra comum que coincide com abreviação ("com", "ver", "pe") só
    // vale com ponto ou no começo.
    final ok = full != null &&
        full.toLowerCase() != key &&
        (hadDot || i == 0 || !_onlyFirst.contains(key)) &&
        // Número ou letra solta depois de "r" no meio é "Bloco r"? só no início.
        !(key.length == 1 && i > 0 && !hadDot);
    if (ok) {
      out.add(full);
      changed = true;
    } else {
      out.add(w);
    }
  }
  return changed ? out.join(' ') : text.trim();
}
