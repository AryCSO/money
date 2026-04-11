import 'package:flutter_test/flutter_test.dart';

import 'package:money/core/utils/template_engine.dart';
import 'package:money/data/models/template_variable_data.dart';

void main() {
  group('TemplateEngine.render', () {
    TemplateVariableData data({
      String nome = 'Joao',
      String posi = 'Analista',
      String banco = 'Caixa',
      String parc1 = '500',
      String parc2 = '600',
      String parc3 = '700',
      String parc4 = '',
      String parc5 = '',
    }) {
      return TemplateVariableData(
        phone: '5562999999999',
        nome: nome,
        posi: posi,
        banco: banco,
        parc1: parc1,
        parc2: parc2,
        parc3: parc3,
        parc4: parc4,
        parc5: parc5,
      );
    }

    test('substitui todas as variaveis', () {
      final result = TemplateEngine.render(
        template: 'Ola {NOME}, cargo {POSI}, banco {BANCO}, parcelas {PARC1}/{PARC2}/{PARC3}',
        data: data(),
      );

      expect(result, 'Ola Joao, cargo Analista, banco Caixa, parcelas 500/600/700');
    });

    test('mantem texto sem variaveis inalterado', () {
      final result = TemplateEngine.render(
        template: 'Texto simples sem nenhuma variavel',
        data: data(),
      );

      expect(result, 'Texto simples sem nenhuma variavel');
    });

    test('substitui variaveis vazias por string vazia', () {
      final result = TemplateEngine.render(
        template: 'Parcela 4 = {PARC4} e 5 = {PARC5}',
        data: data(),
      );

      expect(result, 'Parcela 4 =  e 5 = ');
    });

    test('resolve spintax com pipe', () {
      final result = TemplateEngine.render(
        template: '{Ola|Oi|Bom dia} {NOME}',
        data: data(),
      );

      expect(result, matches(RegExp(r'^(Ola|Oi|Bom dia) Joao$')));
    });

    test('preserva chaves sem pipe como texto', () {
      final result = TemplateEngine.render(
        template: 'Token desconhecido: {XPTO}',
        data: data(),
      );

      expect(result, 'Token desconhecido: {XPTO}');
    });

    test('trata nomes com espacos e trim', () {
      final result = TemplateEngine.render(
        template: '{NOME}',
        data: data(nome: '  Maria  '),
      );

      expect(result, 'Maria');
    });

    test('template vazio retorna string vazia', () {
      final result = TemplateEngine.render(
        template: '',
        data: data(),
      );

      expect(result, '');
    });

    test('multiplas ocorrencias da mesma variavel', () {
      final result = TemplateEngine.render(
        template: '{NOME} disse: oi {NOME}',
        data: data(),
      );

      expect(result, 'Joao disse: oi Joao');
    });
  });
}
