/// Heurística de gênero compartilhada por toda a aplicação.
///
/// Centraliza a lógica que antes estava duplicada em
/// `SpreadsheetService._resolveGenero` e `AutoReplyService._getPronoun`.
/// O resultado é sempre um destes valores: 'Masculino', 'Feminino' ou
/// 'Indefinido'. A inferência por nome é aproximada — por isso a UI sempre
/// permite ao usuário corrigir manualmente quem está marcado.
class GenderUtils {
  const GenderUtils._();

  static const String masculino = 'Masculino';
  static const String feminino = 'Feminino';
  static const String indefinido = 'Indefinido';

  /// Resolve o gênero a partir de um valor explícito de "sexo" (coluna da
  /// planilha) e/ou do primeiro nome. Prioriza o valor explícito.
  static String resolve({String? sexo, String? nome}) {
    final sexoRaw = (sexo ?? '').trim().toUpperCase();
    if (sexoRaw == 'M' || sexoRaw == 'MASCULINO') {
      return masculino;
    }
    if (sexoRaw == 'F' || sexoRaw == 'FEMININO') {
      return feminino;
    }
    return fromName(nome ?? '');
  }

  /// Infere o gênero apenas pela terminação do primeiro nome.
  static String fromName(String nome) {
    final trimmed = nome.trim();
    if (trimmed.isEmpty) {
      return indefinido;
    }

    final lower = trimmed.toLowerCase();
    final lastChar = lower[lower.length - 1];

    if (lastChar == 'a' || lastChar == 'e') {
      return feminino;
    }
    if (lastChar == 'o' ||
        lower.endsWith('son') ||
        lower.endsWith('som') ||
        lower.endsWith('el')) {
      return masculino;
    }

    return indefinido;
  }
}
