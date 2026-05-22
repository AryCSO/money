import 'package:flutter_test/flutter_test.dart';
import 'package:money/data/datasources/spreadsheet_service.dart';

void main() {
  group('SpreadsheetService.parseRows', () {
    test('reconhece layout antigo com colunas de emprestimo', () {
      final servers = SpreadsheetService().parseRows([
        [
          'NOME SERVIDOR',
          'CARGO PRINCIPAL',
          'MUNICÍPIO LOTAÇÃO',
          'IDADE',
          'DDD',
          'TELEFONE',
          'TELEFONE 2',
          'D1001254ADIANT. BANCO SANTANDER BRASIL - EMPRESTIMO 02',
          'D1001275ADIANT. BANCO SANTANDER BRASIL - EMPRESTIMO 03',
          'D1001545ADIANT. BANCO SANTANDER (BRASIL) - EMPRESTIMO 01',
        ],
        [
          'MARIA DA SILVA',
          'PROFESSORA',
          'Goiânia',
          42,
          62,
          '3232-0000',
          '99999-8888',
          '1.200,50',
          90,
          3500,
        ],
      ]);

      expect(servers, hasLength(1));
      expect(servers.single.nome, 'Maria');
      expect(servers.single.cargo, 'PROFESSORA');
      expect(servers.single.municipio, 'Goiânia');
      expect(servers.single.ddd, '62');
      expect(servers.single.telefone, '99999-8888');
      expect(servers.single.idade, 42);
      expect(servers.single.parcelas, [3500, 1200.50]);
    });

    test('reconhece layout novo agrupando linhas por CPF', () {
      final servers = SpreadsheetService().parseRows([
        [
          'Total',
          'OS',
          'CPF',
          'NOME SERVIDOR',
          'CARGO PRINCIPAL',
          'MUNICÍPIO LOTAÇÃO',
          'IDADE',
          'DDD',
          'TELEFON',
          'TELEFONE',
          'PRODUTO',
          'U SERV',
        ],
        [
          'R\$ 1.234,56',
          '001',
          '123.456.789-00',
          'JOAO PEREIRA',
          'SERVIDOR',
          'Anápolis',
          51,
          62,
          '99999-1111',
          '',
          'BANCO SANTANDER BRASIL - EMPRESTIMO 01',
          'ATIVO',
        ],
        [
          1700.25,
          '002',
          '123.456.789-00',
          'JOAO PEREIRA',
          'SERVIDOR',
          'Anápolis',
          51,
          62,
          '99999-1111',
          '',
          'BANCO SANTANDER BRASIL - EMPRESTIMO 02',
          'ATIVO',
        ],
        [
          9000,
          '003',
          '123.456.789-00',
          'JOAO PEREIRA',
          'SERVIDOR',
          'Anápolis',
          51,
          62,
          '99999-1111',
          '',
          'CARTAO BENEFICIO',
          'ATIVO',
        ],
      ]);

      expect(servers, hasLength(1));
      expect(servers.single.nome, 'Joao');
      expect(servers.single.telefone, '99999-1111');
      // O produto "CARTAO BENEFICIO" (9000) tambem conta como parcela —
      // produtos de beneficio sao valores validos de campanha.
      expect(servers.single.parcelas, [9000, 1700.25, 1234.56]);
    });

    test('reconhece colunas de produto de beneficio (VEMCARD)', () {
      final servers = SpreadsheetService().parseRows([
        [
          'DDD',
          'TELEFONE 2',
          'CPF',
          'NOME SERVIDOR',
          'TELEFONE',
          'CARGO PRINCIPAL',
          'MUNICÍPIO LOTAÇÃO',
          'IDADE',
          'D900685VEMCARD - CARTAO BENEFICIO - SAQUE - LEI 22.449',
          'D900769VEMCARD - CARTAO BENEFICIO - PRODUTO OU SERVICO - LEI 22.449',
        ],
        [
          62,
          '98888-7777',
          '123.456.789-00',
          'CARLOS EDUARDO SOUZA',
          '3232-0000',
          'AGENTE',
          'Goiânia',
          47,
          '2.500,00',
          1800,
        ],
      ]);

      expect(servers, hasLength(1));
      expect(servers.single.nome, 'Carlos');
      expect(servers.single.nomeCompleto, 'Carlos Eduardo Souza');
      expect(servers.single.ddd, '62');
      expect(servers.single.telefone, '98888-7777');
      expect(servers.single.idade, 47);
      expect(servers.single.parcelas, [2500, 1800]);
    });

    test('reconhece colunas de beneficio independente da ordem', () {
      final servers = SpreadsheetService().parseRows([
        [
          'D900769VEMCARD - CARTAO BENEFICIO - PRODUTO OU SERVICO - LEI 22.449',
          'IDADE',
          'NOME SERVIDOR',
          'D900685VEMCARD - CARTAO BENEFICIO - SAQUE - LEI 22.449',
          'TELEFONE 2',
          'DDD',
          'CPF',
          'CARGO PRINCIPAL',
          'MUNICÍPIO LOTAÇÃO',
        ],
        [
          1800,
          47,
          'CARLOS EDUARDO SOUZA',
          '2.500,00',
          '98888-7777',
          62,
          '123.456.789-00',
          'AGENTE',
          'Goiânia',
        ],
      ]);

      expect(servers, hasLength(1));
      expect(servers.single.telefone, '98888-7777');
      expect(servers.single.parcelas, [2500, 1800]);
    });

    test('ignora linhas somente com telefone fixo iniciado por 3', () {
      final servers = SpreadsheetService().parseRows([
        [
          'NOME SERVIDOR',
          'CARGO PRINCIPAL',
          'DDD',
          'TELEFONE',
          'D1001254ADIANT. BANCO SANTANDER BRASIL - EMPRESTIMO 02',
        ],
        ['ANA COSTA', 'SERVIDORA', 62, '3232-0000', 500],
      ]);

      expect(servers, isEmpty);
    });
  });
}
