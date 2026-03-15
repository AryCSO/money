import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/server_data.dart';

/// Colunas de empréstimo que devem ser buscadas na planilha.
const _loanColumns = <String>[
  'D900012BANCO SANTANDER BRASIL (ABN AMRO) - EMPRESTIMO',
  'D900017OLE - SANTANDER - EMPRESTIMO 01',
  'D900107BANCO SANTANDER BRASIL - EMPRESTIMO 01',
  'D900402OLE - SANTANDER - EMPRESTIMO 02',
  'D900408OLE - SANTANDER - EMPRESTIMO 03',
  'D900411OLE - SANTANDER - EMPRESTIMO 04',
  'D900507BANCO SANTANDER BRASIL - EMPRESTIMO 02',
  'D900508BANCO SANTANDER BRASIL - EMPRESTIMO 03',
  'D900598BANCO SANTANDER (BRASIL) - EMPRESTIMO 01 - Lei 22.449',
  'D900599BANCO SANTANDER (BRASIL) - EMPRESTIMO 02 - Lei 22.449',
  'D900604BANCO SANTANDER (BRASIL) - EMPRESTIMO 03 - Lei 22.449',
  'D900605BANCO SANTANDER (BRASIL) - EMPRESTIMO 04 - Lei 22.449',
  'D900677BANCO SANTANDER BRASIL - EMPRESTIMO 01 - LEI 22.449',
  'D900678BANCO SANTANDER BRASIL - EMPRESTIMO 02 - LEI 22.449',
  'D900679BANCO SANTANDER BRASIL - EMPRESTIMO 03 - LEI 22.449',
  'D900680BANCO SANTANDER BRASIL - EMPRESTIMO 04 - LEI 22.449',
  'D900704BANCO SANTANDER (BRASIL) - CARTAO BENEFICIO - LEI 22.449',
  'D1000156ADIANT. BANCO SANTANDER (ABN AMRO) - EMPRESTIMO',
  'D1000985ADIANT. OLE-SANTANDER - EMPRESTIMO 02',
  'D1001058ADIANT. OLE-SANTANDER - EMPRESTIMO 04',
  'D1001274ADIANT. BANCO SANTANDER BRASIL - EMPRESTIMO 02',
  'D1001275ADIANT. BANCO SANTANDER BRASIL - EMPRESTIMO 03',
  'D1001545ADIANT. BANCO SANTANDER (BRASIL) - EMPRESTIMO 01 - Lei 22.449',
  'D1001549ADIANT. BANCO SANTANDER (BRASIL) - EMPRESTIMO 02 - Lei 22.449',
];

class SpreadsheetService {
  /// Lê o arquivo Excel a partir dos bytes e retorna a lista de servidores.
  List<ServerData> parseExcel(Uint8List bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);

    // Usa a primeira aba disponivel
    final sheetName = decoder.tables.keys.first;
    final sheet = decoder.tables[sheetName]!;

    if (sheet.rows.isEmpty) return [];

    // ---- Mapear cabeçalhos ----
    final headerRow = sheet.rows.first;
    final headers = <int, String>{};
    for (int col = 0; col < headerRow.length; col++) {
      final cell = headerRow[col];
      if (cell != null) {
        headers[col] = cell.toString().trim();
      }
    }

    // Encontrar indices das colunas relevantes
    final nomeCol = _findColumn(headers, 'NOME SERVIDOR');
    final cargoCol = _findColumn(headers, 'CARGO PRINCIPAL');
    final tel2Col = _findColumn(headers, 'TELEFONE 2');
    final dddCol = _findColumn(headers, 'DDD');
    final idadeCol = _findColumn(headers, 'IDADE');
    final municipioCol = _findColumn(headers, 'MUNICÍPIO LOTAÇÃO') ??
        _findColumn(headers, 'MUNICIPIO LOTAÇÃO') ??
        _findColumn(headers, 'MUNICIPIO LOTACAO');

    // Encontrar todos os indices de colunas de empréstimo existentes
    final loanColIndices = <int>[];
    for (final entry in headers.entries) {
      final headerNormalized = entry.value.toUpperCase().trim();
      for (final loan in _loanColumns) {
        if (headerNormalized == loan.toUpperCase().trim()) {
          loanColIndices.add(entry.key);
          break;
        }
      }
    }

    // ---- Processar linhas de dados ----
    final servers = <ServerData>[];

    for (int rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];

      final rawNome = _cellText(row, nomeCol);
      if (rawNome.isEmpty) continue; // Linha vazia
      final nome = _extractFirstName(rawNome);

      final cargo = _cellText(row, cargoCol);
      final telefone = _cellText(row, tel2Col);
      
      // Ignorar telefones que começam com "3"
      final cleanPhone = telefone.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('3')) continue;

      final ddd = _cellText(row, dddCol);

      // Idade
      final idadeRaw = _cellText(row, idadeCol);
      final idade = int.tryParse(idadeRaw.replaceAll(RegExp(r'\D'), '')) ?? 0;

      // Município
      final municipio = _cellText(row, municipioCol);

      // Coletar todos os valores de empréstimo
      final allLoanValues = <double>[];
      for (final colIdx in loanColIndices) {
        final value = _cellDouble(row, colIdx);
        if (value != null && value > 100.0) {
          allLoanValues.add(value);
        }
      }

      // Ordenar descendente e pegar top 5
      allLoanValues.sort((a, b) => b.compareTo(a));
      final top5 = allLoanValues.take(5).toList();

      // Se não tiver nenhum empréstimo válido, pular
      if (top5.isEmpty) continue;

      String genero = 'Indefinido';
      if (nome.isNotEmpty) {
        final lowerNome = nome.toLowerCase();
        final lastChar = lowerNome[lowerNome.length - 1];
        if (lastChar == 'a' || lastChar == 'e') genero = 'Feminino';
        if (lastChar == 'o' ||
            lowerNome.endsWith('son') ||
            lowerNome.endsWith('som') ||
            lowerNome.endsWith('el')) {
          genero = 'Masculino';
        }
      }

      servers.add(ServerData(
        nome: nome,
        cargo: cargo,
        telefone: telefone,
        ddd: ddd,
        idade: idade,
        municipio: municipio,
        parcelas: top5,
        hasColor: false,
        genero: genero,
      ));
    }

    return servers;
  }

  // ---- Helpers ----

  int? _findColumn(Map<int, String> headers, String name) {
    final normalized = name.toUpperCase().trim();
    for (final entry in headers.entries) {
      if (entry.value.toUpperCase().trim() == normalized) {
        return entry.key;
      }
    }
    return null;
  }

  String _cellText(List<dynamic> row, int? col) {
    if (col == null || col >= row.length) return '';
    final cell = row[col];
    if (cell == null) return '';
    return cell.toString().trim();
  }

  double? _cellDouble(List<dynamic> row, int? col) {
    if (col == null || col >= row.length) return null;
    final cell = row[col];
    if (cell == null) return null;

    if (cell is double) return cell;
    if (cell is int) return cell.toDouble();
    if (cell is num) return cell.toDouble();

    // Tentar parse de string
    final text = cell.toString().trim().replaceAll('R\$', '').trim();
    // Formato brasileiro: 1.234,56
    final normalized =
        text.replaceAll('.', '').replaceAll(',', '.').replaceAll(' ', '');
    return double.tryParse(normalized);
  }

  String _extractFirstName(String fullName) {
    if (fullName.isEmpty) return '';
    final parts = fullName.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';

    final first = parts.first;
    if (first.length <= 1) return first.toUpperCase();
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }
}
