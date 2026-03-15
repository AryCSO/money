import 'dart:math';
import '../../data/models/template_variable_data.dart';

class TemplateEngine {
  static final _random = Random();
  static final _spintaxRegex = RegExp(r'\{([^}]+)\}');

  static String render({
    required String template,
    required TemplateVariableData data,
  }) {
    // 1. Resolver variáveis convencionais
    String rendered = template
        .replaceAll('{NOME}', data.nome.trim())
        .replaceAll('{POSI}', data.posi.trim())
        .replaceAll('{BANCO}', data.banco.trim())
        .replaceAll('{PARC1}', data.parc1.trim())
        .replaceAll('{PARC2}', data.parc2.trim())
        .replaceAll('{PARC3}', data.parc3.trim())
        .replaceAll('{PARC4}', data.parc4.trim())
        .replaceAll('{PARC5}', data.parc5.trim());

    // 2. Resolver Spintax, ex: {Olá|Oi|Bom dia}
    rendered = rendered.replaceAllMapped(_spintaxRegex, (match) {
      final content = match.group(1);
      if (content == null) return match.group(0)!;

      // Se não conter o pipe (|), provavelmente era uma variável não substituída ou texto comum entre chaves
      if (!content.contains('|')) {
        return '{$content}';
      }

      final options = content.split('|');
      final choice = options[_random.nextInt(options.length)];
      return choice;
    });

    return rendered;
  }
}
