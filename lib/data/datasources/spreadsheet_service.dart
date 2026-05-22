import 'dart:typed_data';

import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../../core/utils/gender_utils.dart';
import '../models/server_data.dart';

class SpreadsheetService {
  /// Le o arquivo Excel a partir dos bytes e retorna a lista de servidores.
  List<ServerData> parseExcel(Uint8List bytes) {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes);

    // Usa a primeira aba disponivel.
    final sheetName = decoder.tables.keys.first;
    final sheet = decoder.tables[sheetName]!;

    return parseRows(
      sheet.rows
          .map((row) => row.toList(growable: false))
          .toList(growable: false),
    );
  }

  /// Processa linhas ja decodificadas de uma planilha.
  /// Mantido separado para facilitar testes e futuros imports CSV.
  List<ServerData> parseRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) {
      return [];
    }

    // ---- Mapear cabecalhos ----
    final headerRow = rows.first;
    final headers = <int, String>{};
    for (int col = 0; col < headerRow.length; col++) {
      final cell = headerRow[col];
      if (cell != null) {
        headers[col] = cell.toString().trim();
      }
    }

    // Encontrar indices das colunas relevantes. Existem dois layouts
    // suportados: o antigo (colunas largas de EMPRESTIMO) e o novo
    // (uma linha por produto, com CPF/Total/Produto).
    final cpfCol = _findColumn(headers, 'CPF');
    final nomeCol = _findColumn(headers, 'NOME SERVIDOR');
    final cargoCol = _findFirstColumn(headers, const [
      'CARGO PRINCIPAL',
      'VINCULO PRINCIPAL',
      'VÍNCULO PRINCIPAL',
    ]);
    final phoneColumns = _findPhoneColumns(headers);
    final dddCol = _findColumn(headers, 'DDD') ?? _findColumn(headers, 'ODD');
    final idadeCol = _findColumn(headers, 'IDADE');
    final dataNascCol =
        _findColumn(headers, 'DFT DATA NASCIMENTO') ??
        _findColumn(headers, 'DATA NASCIMENTO') ??
        _findColumn(headers, 'DATA DE NASCIMENTO');
    final sexoCol = _findColumn(headers, 'SEXO');
    final municipioCol =
        _findColumn(headers, 'MUNICIPIO LOTACAO') ??
        _findColumn(headers, 'MUNICÍPIO LOTAÇÃO') ??
        _findColumn(headers, 'MUNICIPIO LOTAÇÃO') ??
        _findColumn(headers, 'MUNICIPIO') ??
        _findColumn(headers, 'MUNICÍPIO');

    final productCol = _findFirstColumn(headers, const [
      'PRODUTO',
      'TIPO PRODUTO',
      'DESCRICAO PRODUTO',
      'DESCRIÇÃO PRODUTO',
    ]);

    // Layout "largo": cada coluna de produto/contrato guarda um valor.
    // A deteccao e independente da ordem das colunas e reconhece tanto
    // emprestimos consignados quanto produtos de beneficio (ex.: cabecalhos
    // como "D900685VEMCARD - CARTAO BENEFICIO - SAQUE - LEI 22.449").
    final wideLoanColIndices = _findWideLoanColumns(headers: headers);

    // Layout "linha": cada linha traz um produto e o valor vem em colunas
    // genericas como Total/Valor/Parcela. As linhas repetidas do mesmo
    // CPF/telefone sao agrupadas para manter ate 5 parcelas por servidor.
    // Removemos colunas ja contadas como "largas" para evitar valor duplicado.
    final rowLoanValueColIndices = _findRowLoanValueColumns(headers)
        .where((col) => !wideLoanColIndices.contains(col))
        .toList();

    // ---- Processar linhas de dados ----
    final serversByKey = <String, _ServerAccumulator>{};

    for (int rowIdx = 1; rowIdx < rows.length; rowIdx++) {
      final row = rows[rowIdx];

      final rawNome = _cellText(row, nomeCol);
      if (rawNome.isEmpty) {
        continue;
      }

      final nome = _extractFirstName(rawNome);
      final nomeCompleto = _formatFullName(rawNome);
      final cargo = _cellText(row, cargoCol);

      // Telefone: preferir celular/telefone 2 quando existir, mas aceitar
      // variacoes como TELEFON/TELEFONE no novo layout.
      final telefone = _pickPhone(row, phoneColumns);
      if (telefone == null) {
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

      final allLoanValues = <double>[
        ..._extractLoanValues(row, wideLoanColIndices),
        if (_isLoanProductRow(row, productCol))
          ..._extractLoanValues(row, rowLoanValueColIndices),
      ];

      // Ordenar descendente e pegar top 5.
      allLoanValues.sort((a, b) => b.compareTo(a));
      final top5 = allLoanValues.take(5).toList();

      // Se nao tiver nenhum emprestimo valido, pular.
      if (top5.isEmpty) {
        continue;
      }

      final key = _buildServerKey(
        row: row,
        rowIdx: rowIdx,
        cpfCol: cpfCol,
        ddd: ddd,
        telefone: telefone,
        rawNome: rawNome,
        municipio: municipio,
      );

      final accumulator = serversByKey.putIfAbsent(
        key,
        () => _ServerAccumulator(
          nome: nome,
          nomeCompleto: nomeCompleto,
          cargo: cargo,
          telefone: telefone,
          ddd: ddd,
          idade: idade,
          municipio: municipio,
          genero: _resolveGenero(row: row, sexoCol: sexoCol, nome: nome),
        ),
      );
      accumulator.merge(
        cargo: cargo,
        telefone: telefone,
        ddd: ddd,
        idade: idade,
        municipio: municipio,
        genero: _resolveGenero(row: row, sexoCol: sexoCol, nome: nome),
        parcelas: top5,
      );
    }

    return serversByKey.values.map((server) => server.toServerData()).toList();
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

  int? _findFirstColumn(Map<int, String> headers, List<String> names) {
    for (final name in names) {
      final col = _findColumn(headers, name);
      if (col != null) {
        return col;
      }
    }
    return null;
  }

  List<int> _findPhoneColumns(Map<int, String> headers) {
    final columns = <_HeaderColumn>[];
    for (final entry in headers.entries) {
      final normalized = _normalizeHeader(entry.value);
      final compact = normalized.replaceAll(' ', '');

      if (compact == 'DDD' || compact == 'ODD') {
        continue;
      }

      final isPhoneColumn =
          compact == 'TELEFONE' ||
          compact == 'TELEFON' ||
          compact == 'TELEFONE1' ||
          compact == 'TELEFONE2' ||
          compact.startsWith('TELEFONE') ||
          compact.startsWith('TELEFON') ||
          compact.contains('CELULAR') ||
          compact.contains('WHATSAPP') ||
          compact == 'FONE' ||
          compact == 'TEL';

      if (!isPhoneColumn) {
        continue;
      }

      columns.add(
        _HeaderColumn(
          index: entry.key,
          priority: _phoneColumnPriority(compact),
        ),
      );
    }

    columns.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      if (priority != 0) return priority;
      return a.index.compareTo(b.index);
    });

    return columns.map((column) => column.index).toList(growable: false);
  }

  int _phoneColumnPriority(String compactHeader) {
    if (compactHeader.contains('2') ||
        compactHeader.contains('CELULAR') ||
        compactHeader.contains('WHATSAPP')) {
      return 0;
    }
    if (compactHeader.startsWith('TELEFON')) {
      return 1;
    }
    return 2;
  }

  /// Localiza as colunas cujo cabecalho representa um produto/contrato com
  /// valor (uma coluna por produto). Independente da posicao das colunas.
  List<int> _findWideLoanColumns({required Map<int, String> headers}) {
    final loanCols = <int>[];

    for (final entry in headers.entries) {
      final normalized = _normalizeHeader(entry.value);
      final compact = normalized.replaceAll(' ', '');
      if (_isLoanProductHeader(compact)) {
        loanCols.add(entry.key);
      }
    }

    return loanCols;
  }

  /// Decide se um cabecalho identifica uma coluna de valor de produto.
  ///
  /// Reconhece, de forma especifica para evitar falsos positivos:
  /// - codigo de produto seguido do nome (ex.: "D900685VEMCARD..."),
  /// - palavras-chave de produtos financeiros/beneficio.
  ///
  /// Por ser especifico, NAO aplica a exclusao generica de
  /// [_isNeverLoanValueHeader] (que descartaria "CARTAO BENEFICIO").
  bool _isLoanProductHeader(String compactHeader) {
    if (compactHeader.isEmpty) {
      return false;
    }

    // Codigo de produto no inicio: letra opcional + digitos + letra.
    // Ex.: "D900685VEMCARD...", "900769VEMCARD...". Exige letra final para
    // nao capturar colunas puramente numericas (ex.: um ano "2024").
    if (RegExp(r'^[A-Z]?\d{3,}[A-Z]').hasMatch(compactHeader)) {
      return true;
    }

    const productKeywords = <String>[
      'EMPRESTIMO',
      'EMPREST',
      'CONSIGN',
      'REFIN',
      'PORTABIL',
      'VEMCARD',
    ];
    return productKeywords.any(compactHeader.contains);
  }

  List<int> _findRowLoanValueColumns(Map<int, String> headers) {
    final valueCols = <int>[];

    for (final entry in headers.entries) {
      final normalized = _normalizeHeader(entry.value);
      final compact = normalized.replaceAll(' ', '');

      if (_isNeverLoanValueHeader(compact)) {
        continue;
      }

      final isValueColumn =
          compact == 'TOTAL' ||
          compact.startsWith('TOTAL') ||
          compact.contains('VALOR') ||
          compact.startsWith('VLR') ||
          compact.contains('PARCELA');

      if (isValueColumn) {
        valueCols.add(entry.key);
      }
    }

    return valueCols;
  }

  bool _isNeverLoanValueHeader(String compactHeader) {
    if (compactHeader == 'CPF' ||
        compactHeader == 'DDD' ||
        compactHeader == 'ODD' ||
        compactHeader == 'IDADE' ||
        compactHeader == 'OS') {
      return true;
    }
    if (compactHeader.startsWith('TELEFON') ||
        compactHeader.contains('CELULAR') ||
        compactHeader.contains('WHATSAPP') ||
        compactHeader.contains('BENEFICIO')) {
      return true;
    }
    return false;
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
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    return value;
  }

  String? _pickPhone(List<dynamic> row, List<int> phoneColumns) {
    for (final col in phoneColumns) {
      final phone = _cellText(row, col);
      if (phone.isEmpty) {
        continue;
      }

      final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
      if (cleanPhone.isEmpty) {
        continue;
      }

      if (cleanPhone.startsWith('3')) {
        continue;
      }

      return phone;
    }

    return null;
  }

  List<double> _extractLoanValues(List<dynamic> row, List<int> columns) {
    final values = <double>[];
    for (final colIdx in columns) {
      final value = _cellDouble(row, colIdx);
      if (value != null && value > 100.0) {
        values.add(value);
      }
    }
    return values;
  }

  bool _isLoanProductRow(List<dynamic> row, int? productCol) {
    if (productCol == null) {
      return true;
    }

    final product = _normalizeHeader(_cellText(row, productCol));
    if (product.isEmpty) {
      return false;
    }

    // Whitelist explícita: empréstimos tradicionais + cartão benefício
    // (VEMCARD, CARTAO BENEFICIO, SAQUE, PRODUTO OU SERVICO).
    final knownProductKeywords = [
      'EMPREST',
      'CONSIGN',
      'REFIN',
      'PORTABIL',
      'CARTAO',
      'BENEFICIO',
      'VEMCARD',
      'SAQUE',
      'PRODUTO',
      'SERVICO',
    ];

    return knownProductKeywords.any(product.contains);
  }

  String _buildServerKey({
    required List<dynamic> row,
    required int rowIdx,
    required int? cpfCol,
    required String ddd,
    required String telefone,
    required String rawNome,
    required String municipio,
  }) {
    final cpf = _cellText(row, cpfCol).replaceAll(RegExp(r'\D'), '');
    if (cpf.isNotEmpty) {
      return 'cpf:$cpf';
    }

    final phone = '$ddd$telefone'.replaceAll(RegExp(r'\D'), '');
    if (phone.length >= 10) {
      return 'phone:$phone';
    }

    final nameKey = _normalizeHeader('$rawNome|$municipio');
    if (nameKey.trim().isNotEmpty) {
      return 'name:$nameKey:$rowIdx';
    }

    return 'row:$rowIdx';
  }

  String _resolveGenero({
    required List<dynamic> row,
    required int? sexoCol,
    required String nome,
  }) {
    return GenderUtils.resolve(sexo: _cellText(row, sexoCol), nome: nome);
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
    final normalized = text
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(' ', '');
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
    final parts = fullName
        .trim()
        .split(' ')
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '';
    }

    final first = parts.first;
    if (first.length <= 1) {
      return first.toUpperCase();
    }
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  /// Formata o nome completo para exibicao (cada palavra capitalizada).
  /// Usado apenas na interface — o envio continua usando [_extractFirstName].
  String _formatFullName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((part) {
          if (part.length <= 1) {
            return part.toUpperCase();
          }
          return part[0].toUpperCase() + part.substring(1).toLowerCase();
        })
        .toList();
    return parts.join(' ');
  }
}

class _HeaderColumn {
  const _HeaderColumn({required this.index, required this.priority});

  final int index;
  final int priority;
}

class _ServerAccumulator {
  _ServerAccumulator({
    required this.nome,
    required this.nomeCompleto,
    required String cargo,
    required String telefone,
    required String ddd,
    required int idade,
    required String municipio,
    required String genero,
  }) : _cargo = cargo,
       _telefone = telefone,
       _ddd = ddd,
       _idade = idade,
       _municipio = municipio,
       _genero = genero;

  final String nome;
  final String nomeCompleto;
  String _cargo;
  String _telefone;
  String _ddd;
  int _idade;
  String _municipio;
  String _genero;
  final List<double> _parcelas = <double>[];

  void merge({
    required String cargo,
    required String telefone,
    required String ddd,
    required int idade,
    required String municipio,
    required String genero,
    required List<double> parcelas,
  }) {
    if (_cargo.isEmpty && cargo.isNotEmpty) _cargo = cargo;
    if (_telefone.isEmpty && telefone.isNotEmpty) _telefone = telefone;
    if (_ddd.isEmpty && ddd.isNotEmpty) _ddd = ddd;
    if (_idade == 0 && idade > 0) _idade = idade;
    if (_municipio.isEmpty && municipio.isNotEmpty) _municipio = municipio;
    if (_genero == 'Indefinido' && genero != 'Indefinido') _genero = genero;
    _parcelas.addAll(parcelas);
  }

  ServerData toServerData() {
    _parcelas.sort((a, b) => b.compareTo(a));
    return ServerData(
      nome: nome,
      nomeCompleto: nomeCompleto,
      cargo: _cargo,
      telefone: _telefone,
      ddd: _ddd,
      idade: _idade,
      municipio: _municipio,
      parcelas: _parcelas.take(5).toList(),
      hasColor: false,
      genero: _genero,
    );
  }
}
