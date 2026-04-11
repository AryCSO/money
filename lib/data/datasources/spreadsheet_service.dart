import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../models/server_data.dart';

class SpreadsheetService {
  /// Le o arquivo Excel a partir dos bytes e retorna a lista de servidores.
  List<ServerData> parseExcel(Uint8List bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);

    // Usa a primeira aba disponivel.
    final sheetName = decoder.tables.keys.first;
    final sheet = decoder.tables[sheetName]!;

    if (sheet.rows.isEmpty) {
      return [];
    }

    // ---- Mapear cabecalhos ----
    final headerRow = sheet.rows.first;
    final headers = <int, String>{};
    for (int col = 0; col < headerRow.length; col++) {
      final cell = headerRow[col];
      if (cell != null) {
        headers[col] = cell.toString().trim();
      }
    }

    // Encontrar indices das colunas relevantes.
    final nomeCol = _findColumn(headers, 'NOME SERVIDOR');
    final cargoCol = _findColumn(headers, 'CARGO PRINCIPAL') ??
        _findColumn(headers, 'VINCULO PRINCIPAL') ??
        _findColumn(headers, 'VÍNCULO PRINCIPAL');
    final tel2Col = _findColumn(headers, 'TELEFONE 2');
    final tel1Col = _findColumn(headers, 'TELEFONE');
    final dddCol = _findColumn(headers, 'DDD') ?? _findColumn(headers, 'ODD');
    final idadeCol = _findColumn(headers, 'IDADE');
    final dataNascCol = _findColumn(headers, 'DFT DATA NASCIMENTO') ??
        _findColumn(headers, 'DATA NASCIMENTO') ??
        _findColumn(headers, 'DATA DE NASCIMENTO');
    final sexoCol = _findColumn(headers, 'SEXO');
    final municipioCol = _findColumn(headers, 'MUNICIPIO LOTACAO') ??
        _findColumn(headers, 'MUNICÍPIO LOTAÇÃO') ??
        _findColumn(headers, 'MUNICIPIO LOTAÇÃO') ??
        _findColumn(headers, 'MUNICIPIO') ??
        _findColumn(headers, 'MUNICÍPIO');

    // Colunas de emprestimo:
    // toda coluna apos "Telefone 2" que contenha "emprestimo" no nome.
    final loanColIndices = _findLoanColumns(headers: headers, tel2Col: tel2Col);

    // ---- Processar linhas de dados ----
    final servers = <ServerData>[];

    for (int rowIdx = 1; rowIdx < sheet.rows.length; rowIdx++) {
      final row = sheet.rows[rowIdx];

      final rawNome = _cellText(row, nomeCol);
      if (rawNome.isEmpty) {
        continue;
      }

      final nome = _extractFirstName(rawNome);
      final cargo = _cellText(row, cargoCol);

      // Telefone: preferir TELEFONE 2, cair em TELEFONE se vazio.
      String telefone = _cellText(row, tel2Col);
      if (telefone.isEmpty) {
        telefone = _cellText(row, tel1Col);
      }

      // Ignorar telefones que comecam com "3".
      final cleanPhone = telefone.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.startsWith('3')) {
        continue;
      }

      final ddd = _cellText(row, dddCol);

      // Idade: preferir coluna IDADE, cair em DFT DATA NASCIMENTO.
      int idade = 0;
      final idadeRaw = _cellText(row, idadeCol);
      if (idadeRaw.isNotEmpty) {
        idade = int.tryParse(idadeRaw.replaceAll(RegExp(r'\D'), '')) ?? 0;
      } else {
        final dataNascRaw = _cellText(row, dataNascCol);
        if (dataNascRaw.isNotEmpty) {
          idade = _calcIdadeFromDate(dataNascRaw);
        }
      }

      // Municipio
      final municipio = _cellText(row, municipioCol);

      // Coletar todos os valores de emprestimo.
      final allLoanValues = <double>[];
      for (final colIdx in loanColIndices) {
        final value = _cellDouble(row, colIdx);
        if (value != null && value > 100.0) {
          allLoanValues.add(value);
        }
      }

      // Ordenar descendente e pegar top 5.
      allLoanValues.sort((a, b) => b.compareTo(a));
      final top5 = allLoanValues.take(5).toList();

      // Se nao tiver nenhum emprestimo valido, pular.
      if (top5.isEmpty) {
        continue;
      }

      // Genero: preferir coluna SEXO; fallback por heuristica do nome.
      String genero = 'Indefinido';
      final sexoRaw = _cellText(row, sexoCol).toUpperCase();
      if (sexoRaw == 'M' || sexoRaw == 'MASCULINO') {
        genero = 'Masculino';
      } else if (sexoRaw == 'F' || sexoRaw == 'FEMININO') {
        genero = 'Feminino';
      } else if (nome.isNotEmpty) {
        final lowerNome = nome.toLowerCase();
        final lastChar = lowerNome[lowerNome.length - 1];
        if (lastChar == 'a' || lastChar == 'e') {
          genero = 'Feminino';
        }
        if (lastChar == 'o' ||
            lowerNome.endsWith('son') ||
            lowerNome.endsWith('som') ||
            lowerNome.endsWith('el')) {
          genero = 'Masculino';
        }
      }

      servers.add(
        ServerData(
          nome: nome,
          cargo: cargo,
          telefone: telefone,
          ddd: ddd,
          idade: idade,
          municipio: municipio,
          parcelas: top5,
          hasColor: false,
          genero: genero,
        ),
      );
    }

    return servers;
  }

  // ---- Helpers ----

  int? _findColumn(Map<int, String> headers, String name) {
    final normalized = _normalizeHeader(name);
    for (final entry in headers.entries) {
      if (_normalizeHeader(entry.value) == normalized) {
        return entry.key;
      }
    }
    return null;
  }

  List<int> _findLoanColumns({
    required Map<int, String> headers,
    required int? tel2Col,
  }) {
    final startCol = tel2Col ?? -1;
    final loanCols = <int>[];

    for (final entry in headers.entries) {
      if (entry.key <= startCol) {
        continue;
      }

      final normalizedHeader = _normalizeHeader(entry.value);
      if (normalizedHeader.contains('EMPRESTIMO')) {
        loanCols.add(entry.key);
      }
    }

    return loanCols;
  }

  String _normalizeHeader(String input) {
    var value = input.toUpperCase().trim();
    value = value
        .replaceAll('Á', 'A')
        .replaceAll('À', 'A')
        .replaceAll('Â', 'A')
        .replaceAll('Ã', 'A')
        .replaceAll('Ä', 'A')
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Ë', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ì', 'I')
        .replaceAll('Î', 'I')
        .replaceAll('Ï', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ò', 'O')
        .replaceAll('Ô', 'O')
        .replaceAll('Õ', 'O')
        .replaceAll('Ö', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ù', 'U')
        .replaceAll('Û', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C');
    return value;
  }

  String _cellText(List<dynamic> row, int? col) {
    if (col == null || col >= row.length) {
      return '';
    }
    final cell = row[col];
    if (cell == null) {
      return '';
    }
    return cell.toString().trim();
  }

  double? _cellDouble(List<dynamic> row, int? col) {
    if (col == null || col >= row.length) {
      return null;
    }
    final cell = row[col];
    if (cell == null) {
      return null;
    }

    if (cell is double) {
      return cell;
    }
    if (cell is int) {
      return cell.toDouble();
    }
    if (cell is num) {
      return cell.toDouble();
    }

    // Tentar parse de string.
    final text = cell.toString().trim().replaceAll('R\$', '').trim();
    // Formato brasileiro: 1.234,56
    final normalized =
        text.replaceAll('.', '').replaceAll(',', '.').replaceAll(' ', '');
    return double.tryParse(normalized);
  }

  int _calcIdadeFromDate(String raw) {
    // Suporta formatos: dd/MM/yyyy, dd-MM-yyyy, yyyy-MM-dd, numero serial Excel.
    try {
      // Serial Excel (numero de dias desde 1900-01-01).
      final serial = double.tryParse(raw.replaceAll(',', '.'));
      if (serial != null && serial > 1000) {
        final excelEpoch = DateTime(1899, 12, 30);
        final date = excelEpoch.add(Duration(days: serial.toInt()));
        return _ageFromBirthDate(date);
      }
      // dd/MM/yyyy ou dd-MM-yyyy
      final parts = raw.split(RegExp(r'[/\-]'));
      if (parts.length == 3) {
        int? year, month, day;
        if (parts[0].length == 4) {
          // yyyy-MM-dd
          year = int.tryParse(parts[0]);
          month = int.tryParse(parts[1]);
          day = int.tryParse(parts[2]);
        } else {
          // dd/MM/yyyy
          day = int.tryParse(parts[0]);
          month = int.tryParse(parts[1]);
          year = int.tryParse(parts[2]);
        }
        if (year != null && month != null && day != null) {
          return _ageFromBirthDate(DateTime(year, month, day));
        }
      }
    } catch (_) {}
    return 0;
  }

  int _ageFromBirthDate(DateTime birth) {
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age < 0 ? 0 : age;
  }

  String _extractFirstName(String fullName) {
    if (fullName.isEmpty) {
      return '';
    }
    final parts = fullName.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '';
    }

    final first = parts.first;
    if (first.length <= 1) {
      return first.toUpperCase();
    }
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }
}
