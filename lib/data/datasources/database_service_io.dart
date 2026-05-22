import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fbdb/fbdb.dart';

import '../../core/utils/phone_utils.dart';

/// Servico de banco de dados Firebird 5.
/// Armazena clientes, tentativas de envio e conversas.
class DatabaseService {
  DatabaseService._();

  static final DatabaseService instance = DatabaseService._();

  static const String _dbFolderPath = r'C:\money';
  static const String _dbFileName = 'money.fdb';
  static const String _chatVisibleFromMetaKey = 'chat_visible_from';
  static const String _firebirdHost = '127.0.0.1';
  static const int _firebirdPort = 9255;
  static const String _firebirdPrimaryRoot = r'C:\money\firebird5';
  static const Map<String, String> _runtimeFirebirdFiles = <String, String>{
    'fbclient.dll': 'fbclient.dll',
    'msvcp140.dll': 'msvcp140.dll',
    'vcruntime140.dll': 'vcruntime140.dll',
  };
  static const String _dbUser = 'money';
  static const String _dbPassword = '101812Ar@';

  // Seed de autenticação (gravado em toda geração do banco).
  static const String _defaultAdminToken = '101812';
  static const String _defaultUserEmail = 'arycarvalho1969@gmail.com';
  static const String _defaultUserPassword = '101812Ar@';
  static const String _defaultUserNome = 'Ary Carvalho';
  static const String _defaultUserApelido = 'Ary';
  static const String _adminTokenMetaKey = 'admin_token';

  FbDb? _db;
  Future<FbDb>? _openingFuture;

  /// True quando há uma conexão Firebird ativa pronta para uso.
  bool get isReady => _db != null;

  String get _databasePath =>
      '$_dbFolderPath${Platform.pathSeparator}$_dbFileName';

  /// Retorna o banco pronto para uso. Chamadas concorrentes compartilham
  /// a mesma tentativa de conexão para evitar abrir o Firebird N vezes.
  Future<FbDb> get database {
    final existing = _db;
    if (existing != null) {
      return Future.value(existing);
    }
    return _openingFuture ??= _open()
        .then((db) {
          _db = db;
          _openingFuture = null;
          return db;
        })
        .catchError((Object e) {
          // Falha: limpa o future em cache para permitir nova tentativa.
          _openingFuture = null;
          throw e;
        });
  }

  Future<FbDb> _open() async {
    final dir = Directory(_dbFolderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await _prepareFirebirdClientRuntime();

    final dbFile = File(_databasePath);
    final db = await _connectOrCreateDatabase(dbExists: await dbFile.exists());
    await _ensureSchema(db);
    return db;
  }

  Future<FbDb> _connectOrCreateDatabase({required bool dbExists}) async {
    try {
      if (dbExists) {
        return await FbDb.attach(
          host: _firebirdHost,
          port: _firebirdPort,
          database: _databasePath,
          user: _dbUser,
          password: _dbPassword,
        );
      }

      return await FbDb.createDatabase(
        host: _firebirdHost,
        port: _firebirdPort,
        database: _databasePath,
        user: _dbUser,
        password: _dbPassword,
      );
    } catch (error) {
      throw StateError(
        'Nao foi possivel conectar ao Firebird em '
        '$_firebirdHost:$_firebirdPort com o usuario $_dbUser. '
        'Execute a configuracao da instancia do Money antes de abrir o app. '
        'Erro original: $error',
      );
    }
  }

  Future<void> _prepareFirebirdClientRuntime() async {
    if (!Platform.isWindows) {
      return;
    }

    final sourceRoot = await _resolveFirebirdClientRoot();
    if (sourceRoot == null) {
      throw StateError(
        'Nenhuma instalacao do Firebird 5 do Money foi encontrada em '
        '$_firebirdPrimaryRoot.',
      );
    }

    final executableDirectory = _resolveRuntimeDirectory();
    for (final entry in _runtimeFirebirdFiles.entries) {
      final source = File(
        '${sourceRoot.path}${Platform.pathSeparator}${entry.key}',
      );
      if (!await source.exists()) {
        throw StateError(
          'Arquivo obrigatorio do Firebird ausente: ${source.path}',
        );
      }

      final destination = File(
        '${executableDirectory.path}${Platform.pathSeparator}${entry.value}',
      );
      final shouldCopy =
          !await destination.exists() ||
          await destination.length() != await source.length();
      if (shouldCopy) {
        await source.copy(destination.path);
      }
    }
  }

  Future<Directory?> _resolveFirebirdClientRoot() async {
    final dir = Directory(_firebirdPrimaryRoot);
    final client = File('${dir.path}${Platform.pathSeparator}fbclient.dll');
    if (await dir.exists() && await client.exists()) {
      return dir;
    }
    return null;
  }

  Directory _resolveRuntimeDirectory() {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final normalizedExecDir = executableDirectory.path
        .replaceAll('/', '\\')
        .toLowerCase();
    final sdkBinFragment = '\\flutter\\bin\\cache\\dart-sdk\\bin';
    if (normalizedExecDir.endsWith(sdkBinFragment)) {
      return Directory.current;
    }
    return executableDirectory;
  }

  Future<void> _ensureSchema(FbDb db) async {
    if (!await _tableExists(db, 'CLIENTES')) {
      await db.execute(
        sql: '''
          CREATE TABLE CLIENTES (
            ID BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            NOME VARCHAR(255) NOT NULL,
            CARGO VARCHAR(255) DEFAULT '',
            TELEFONE VARCHAR(32) NOT NULL,
            DDD VARCHAR(8) DEFAULT '',
            IDADE INTEGER DEFAULT 0,
            MUNICIPIO VARCHAR(255) DEFAULT '',
            GENERO VARCHAR(32) DEFAULT 'Indefinido',
            PARCELAS VARCHAR(255) DEFAULT '',
            CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''',
      );
    }

    if (!await _tableExists(db, 'ENVIOS')) {
      await db.execute(
        sql: '''
          CREATE TABLE ENVIOS (
            ID BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            CLIENTE_ID BIGINT,
            TELEFONE_COMPLETO VARCHAR(32) NOT NULL,
            NOME_CLIENTE VARCHAR(255) DEFAULT '',
            SUCESSO SMALLINT DEFAULT 0 NOT NULL,
            MENSAGEM_STATUS VARCHAR(512) DEFAULT '',
            MENSAGEM_ENVIADA VARCHAR(32765),
            TIPO VARCHAR(32) DEFAULT 'massa',
            ENVIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            CONSTRAINT FK_ENVIOS_CLIENTE FOREIGN KEY (CLIENTE_ID)
              REFERENCES CLIENTES(ID)
          )
        ''',
      );
    }

    if (!await _tableExists(db, 'CONVERSAS')) {
      await db.execute(
        sql: '''
          CREATE TABLE CONVERSAS (
            ID BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            TELEFONE VARCHAR(64) NOT NULL,
            NOME_CLIENTE VARCHAR(255) DEFAULT '',
            DESTINO_ENVIO VARCHAR(255) DEFAULT '',
            DIRECAO VARCHAR(32) DEFAULT 'recebida' NOT NULL,
            CONTEUDO VARCHAR(32765) NOT NULL,
            TIPO_MSG VARCHAR(32) DEFAULT 'texto',
            REGISTRADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''',
      );
    }

    if (!await _tableExists(db, 'CHAT_LEITURA')) {
      await db.execute(
        sql: '''
          CREATE TABLE CHAT_LEITURA (
            TELEFONE VARCHAR(64) PRIMARY KEY,
            LIDA_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
          )
        ''',
      );
    }

    if (!await _tableExists(db, 'APP_META')) {
      await db.execute(
        sql: '''
          CREATE TABLE APP_META (
            META_KEY VARCHAR(100) PRIMARY KEY,
            META_VALUE VARCHAR(255) NOT NULL
          )
        ''',
      );
    }

    if (!await _tableExists(db, 'USUARIOS')) {
      await db.execute(
        sql: '''
          CREATE TABLE USUARIOS (
            ID BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            EMAIL VARCHAR(255) NOT NULL UNIQUE,
            NOME_COMPLETO VARCHAR(255) DEFAULT '',
            NOME_PREFERIDO VARCHAR(120) DEFAULT '',
            SALT VARCHAR(64) NOT NULL,
            SENHA_HASH VARCHAR(128) NOT NULL,
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''',
      );
    }

    // Seed de login/admin — garantido em toda geração/abertura do banco.
    await _seedDefaultAuth(db);

    if (!await _tableExists(db, 'MODELOS_MENSAGEM')) {
      await db.execute(
        sql: '''
          CREATE TABLE MODELOS_MENSAGEM (
            ID BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
            NOME VARCHAR(255) NOT NULL,
            MSG1 BLOB SUB_TYPE TEXT,
            MSG2 BLOB SUB_TYPE TEXT,
            MSG3 BLOB SUB_TYPE TEXT,
            MSG4 BLOB SUB_TYPE TEXT,
            MSG5 BLOB SUB_TYPE TEXT,
            MSG6 BLOB SUB_TYPE TEXT,
            CRIADO_EM TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''',
      );
    }

    // Bancos antigos podem ter MODELOS_MENSAGEM com colunas faltando
    // (ex.: somente NOME/MSG1..MSG3). Garantimos que todas existam para
    // que INSERT/SELECT do recurso de "modelos salvos" funcione mesmo
    // em FDB pre-existente.
    for (var i = 1; i <= 6; i++) {
      await _ensureColumn(
        db,
        table: 'MODELOS_MENSAGEM',
        column: 'MSG$i',
        definition: 'BLOB SUB_TYPE TEXT',
      );
    }
    await _ensureColumn(
      db,
      table: 'MODELOS_MENSAGEM',
      column: 'CRIADO_EM',
      definition: 'TIMESTAMP DEFAULT CURRENT_TIMESTAMP',
    );

    if (!await _indexExists(db, 'IDX_ENVIOS_TELEFONE')) {
      await db.execute(
        sql: 'CREATE INDEX IDX_ENVIOS_TELEFONE ON ENVIOS(TELEFONE_COMPLETO)',
      );
    }
    if (!await _indexExists(db, 'IDX_CONVERSAS_TELEFONE')) {
      await db.execute(
        sql: 'CREATE INDEX IDX_CONVERSAS_TELEFONE ON CONVERSAS(TELEFONE)',
      );
    }
    if (!await _indexExists(db, 'IDX_CONVERSAS_TELEFONE_REG')) {
      await db.execute(
        sql: '''
          CREATE INDEX IDX_CONVERSAS_TELEFONE_REG
          ON CONVERSAS(TELEFONE, REGISTRADO_EM)
        ''',
      );
    }
    if (!await _indexExists(db, 'IDX_CLIENTES_TELEFONE')) {
      await db.execute(
        sql: 'CREATE INDEX IDX_CLIENTES_TELEFONE ON CLIENTES(TELEFONE)',
      );
    }

    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'DESTINO_ENVIO',
      definition: "VARCHAR(255) DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'MENSAGEM_ID',
      definition: "VARCHAR(128) DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'ARQUIVO_NOME',
      definition: "VARCHAR(255) DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'ARQUIVO_MIME',
      definition: "VARCHAR(255) DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'ARQUIVO_TAMANHO',
      definition: 'BIGINT DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'ARQUIVO_DADOS',
      definition: 'BLOB SUB_TYPE BINARY',
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'MEDIA_URL',
      definition: "VARCHAR(2048) DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'LATITUDE',
      definition: 'DOUBLE PRECISION',
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'LONGITUDE',
      definition: 'DOUBLE PRECISION',
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'LOCAL_NOME',
      definition: "VARCHAR(255) DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'CONVERSAS',
      column: 'LOCAL_ENDERECO',
      definition: "VARCHAR(512) DEFAULT ''",
    );
    if (!await _indexExists(db, 'IDX_CONVERSAS_MSG_ID')) {
      await db.execute(
        sql: 'CREATE INDEX IDX_CONVERSAS_MSG_ID ON CONVERSAS(MENSAGEM_ID)',
      );
    }
    if (!await _indexExists(db, 'IDX_CONVERSAS_TEL_DIR_MSG')) {
      await db.execute(
        sql: '''
          CREATE INDEX IDX_CONVERSAS_TEL_DIR_MSG
          ON CONVERSAS(TELEFONE, DIRECAO, MENSAGEM_ID)
        ''',
      );
    }
    if (!await _indexExists(db, 'IDX_CONVERSAS_DIR_REG_TEL')) {
      await db.execute(
        sql: '''
          CREATE INDEX IDX_CONVERSAS_DIR_REG_TEL
          ON CONVERSAS(DIRECAO, REGISTRADO_EM, TELEFONE)
        ''',
      );
    }
    if (!await _indexExists(db, 'IDX_ENVIOS_CHAT_TIMELINE')) {
      await db.execute(
        sql: '''
          CREATE INDEX IDX_ENVIOS_CHAT_TIMELINE
          ON ENVIOS(TELEFONE_COMPLETO, SUCESSO, TIPO, ENVIADO_EM)
        ''',
      );
    }
  }

  Future<bool> _tableExists(FbDb db, String tableName) async {
    final row = await _selectOneDb(
      db,
      '''
        SELECT 1 AS FOUND
        FROM RDB\$RELATIONS
        WHERE COALESCE(RDB\$SYSTEM_FLAG, 0) = 0
          AND TRIM(RDB\$RELATION_NAME) = ?
        ROWS 1
      ''',
      parameters: [tableName.toUpperCase()],
    );
    return row != null;
  }

  Future<bool> _indexExists(FbDb db, String indexName) async {
    final row = await _selectOneDb(
      db,
      '''
        SELECT 1 AS FOUND
        FROM RDB\$INDICES
        WHERE TRIM(RDB\$INDEX_NAME) = ?
        ROWS 1
      ''',
      parameters: [indexName.toUpperCase()],
    );
    return row != null;
  }

  Future<bool> _columnExists(
    FbDb db, {
    required String table,
    required String column,
  }) async {
    final row = await _selectOneDb(
      db,
      '''
        SELECT 1 AS FOUND
        FROM RDB\$RELATION_FIELDS
        WHERE TRIM(RDB\$RELATION_NAME) = ?
          AND TRIM(RDB\$FIELD_NAME) = ?
        ROWS 1
      ''',
      parameters: [table.toUpperCase(), column.toUpperCase()],
    );
    return row != null;
  }

  Future<void> _ensureColumn(
    FbDb db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    if (await _columnExists(db, table: table, column: column)) {
      return;
    }

    await db.execute(sql: 'ALTER TABLE $table ADD $column $definition');
  }

  Future<Map<String, dynamic>?> _selectOneDb(
    FbDb db,
    String sql, {
    List<dynamic> parameters = const [],
  }) async {
    final row = await db.selectOne(sql: sql, parameters: parameters);
    if (row == null) {
      return null;
    }
    return _normalizeRow(row);
  }

  Future<List<Map<String, dynamic>>> _selectAllDb(
    FbDb db,
    String sql, {
    List<dynamic> parameters = const [],
  }) async {
    final rows = await db.selectAll(sql: sql, parameters: parameters);
    return rows.map(_normalizeRow).toList();
  }

  Future<Map<String, dynamic>> _executeReturningOneDb(
    FbDb db,
    String sql, {
    List<dynamic> parameters = const [],
  }) async {
    final query = db.query();
    try {
      await query.execute(sql: sql, parameters: parameters);
      return _normalizeRow(await query.getOutputAsMap());
    } finally {
      await query.close();
    }
  }

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final normalized = <String, dynamic>{};
    row.forEach((key, value) {
      normalized[key.toString().trim().toLowerCase()] = _normalizeValue(value);
    });
    return normalized;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is DateTime) {
      return _formatDateTime(value);
    }
    if (value is ByteBuffer) {
      return value.asUint8List();
    }
    if (value is ByteData) {
      return value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
    }
    if (value is TypedData) {
      return value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    return value;
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  // CLIENTES

  /// Insere ou atualiza um cliente baseado no telefone + ddd.
  Future<int> upsertCliente({
    required String nome,
    required String cargo,
    required String telefone,
    required String ddd,
    required int idade,
    required String municipio,
    required String genero,
    required List<double> parcelas,
  }) async {
    final db = await database;
    final parcelasStr = parcelas.map((p) => p.toStringAsFixed(2)).join(';');

    final existing = await _selectOneDb(
      db,
      '''
        SELECT FIRST 1 ID
        FROM CLIENTES
        WHERE TELEFONE = ? AND DDD = ?
        ORDER BY ID DESC
      ''',
      parameters: [telefone, ddd],
    );

    if (existing != null) {
      final id = _asInt(existing['id']);
      await db.execute(
        sql: '''
          UPDATE CLIENTES
          SET NOME = ?,
              CARGO = ?,
              IDADE = ?,
              MUNICIPIO = ?,
              GENERO = ?,
              PARCELAS = ?
          WHERE ID = ?
        ''',
        parameters: [nome, cargo, idade, municipio, genero, parcelasStr, id],
      );
      return id;
    }

    final inserted = await _executeReturningOneDb(
      db,
      '''
        INSERT INTO CLIENTES (
          NOME, CARGO, TELEFONE, DDD, IDADE, MUNICIPIO, GENERO, PARCELAS
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        RETURNING ID
      ''',
      parameters: [
        nome,
        cargo,
        telefone,
        ddd,
        idade,
        municipio,
        genero,
        parcelasStr,
      ],
    );

    return _asInt(inserted['id']);
  }

  Future<String?> findClientPhoneByName(String name) async {
    final candidates = await findClientPhoneCandidatesByName(name);
    if (candidates.isEmpty) {
      return null;
    }
    return candidates.first;
  }

  Future<List<String>> findClientPhoneCandidatesByName(String name) async {
    final normalizedLookup = _normalizePersonName(name);
    if (normalizedLookup.isEmpty) {
      return const [];
    }

    final db = await database;
    final rows = await _selectAllDb(db, '''
        SELECT NOME, TELEFONE, DDD
        FROM CLIENTES
        WHERE TRIM(COALESCE(NOME, '')) <> ''
        ORDER BY ID DESC
        ROWS 500
      ''');

    final exactMatch = _pickClientPhoneMatch(
      rows: rows,
      normalizedLookup: normalizedLookup,
      allowPrefixMatch: false,
    );
    if (exactMatch.isNotEmpty) {
      return exactMatch;
    }

    return _pickClientPhoneMatch(
      rows: rows,
      normalizedLookup: normalizedLookup,
      allowPrefixMatch: true,
    );
  }

  List<String> _pickClientPhoneMatch({
    required List<Map<String, Object?>> rows,
    required String normalizedLookup,
    required bool allowPrefixMatch,
  }) {
    for (final row in rows) {
      final candidateName = _normalizePersonName(row['nome']?.toString() ?? '');
      if (candidateName.isEmpty) {
        continue;
      }

      final matches = allowPrefixMatch
          ? candidateName.startsWith(normalizedLookup) ||
                normalizedLookup.startsWith(candidateName)
          : candidateName == normalizedLookup;
      if (!matches) {
        continue;
      }

      final phone = row['telefone']?.toString() ?? '';
      final ddd = row['ddd']?.toString() ?? '';
      final candidates = _buildStoredClientPhoneCandidates(
        phone: phone,
        ddd: ddd,
      );

      if (candidates.isNotEmpty) {
        return candidates;
      }
    }

    return const [];
  }

  List<String> _buildStoredClientPhoneCandidates({
    required String phone,
    required String ddd,
  }) {
    final rawPhone = phone.replaceAll(RegExp(r'\D'), '');
    final rawDdd = ddd.replaceAll(RegExp(r'\D'), '');
    final candidates = <String>[];

    void addCandidate(String value) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) {
        return;
      }

      final normalized = PhoneUtils.normalize(digits);
      if (_looksLikeStoredClientPhone(normalized) &&
          !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    if (rawPhone.isEmpty) {
      return candidates;
    }

    if (rawDdd.isNotEmpty) {
      if (rawPhone.startsWith('55') || rawPhone.startsWith(rawDdd)) {
        addCandidate(rawPhone);
      } else {
        addCandidate('$rawDdd$rawPhone');
      }
    }

    addCandidate(rawPhone);
    return candidates;
  }

  bool _looksLikeStoredClientPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 12 && digits.length <= 13;
  }

  // ENVIOS

  /// Registra uma tentativa de envio.
  Future<int> registrarEnvio({
    int? clienteId,
    required String telefoneCompleto,
    required String nomeCliente,
    required bool sucesso,
    required String mensagemStatus,
    String mensagemEnviada = '',
    String tipo = 'massa',
  }) async {
    final db = await database;
    final inserted = await _executeReturningOneDb(
      db,
      '''
        INSERT INTO ENVIOS (
          CLIENTE_ID,
          TELEFONE_COMPLETO,
          NOME_CLIENTE,
          SUCESSO,
          MENSAGEM_STATUS,
          MENSAGEM_ENVIADA,
          TIPO
        )
        VALUES (?, ?, ?, ?, ?, ?, ?)
        RETURNING ID
      ''',
      parameters: [
        clienteId,
        telefoneCompleto,
        nomeCliente,
        sucesso ? 1 : 0,
        mensagemStatus,
        mensagemEnviada,
        tipo,
      ],
    );
    return _asInt(inserted['id']);
  }

  /// Retorna os envios de hoje com sucesso.
  Future<int> countEnviosHojeSucesso() async {
    final db = await database;
    final bounds = _dayBounds(DateTime.now());
    final result = await _selectOneDb(
      db,
      '''
        SELECT COUNT(*) AS TOTAL
        FROM ENVIOS
        WHERE SUCESSO = 1
          AND ENVIADO_EM >= ?
          AND ENVIADO_EM < ?
      ''',
      parameters: [bounds.start, bounds.end],
    );
    return _asInt(result?['total']);
  }

  /// Retorna os envios de hoje com falha.
  Future<int> countEnviosHojeFalha() async {
    final db = await database;
    final bounds = _dayBounds(DateTime.now());
    final result = await _selectOneDb(
      db,
      '''
        SELECT COUNT(*) AS TOTAL
        FROM ENVIOS
        WHERE SUCESSO = 0
          AND ENVIADO_EM >= ?
          AND ENVIADO_EM < ?
      ''',
      parameters: [bounds.start, bounds.end],
    );
    return _asInt(result?['total']);
  }

  // CONVERSAS

  Future<DateTime> ensureChatVisibleFrom() async {
    final db = await database;
    final existing = await _selectOneDb(
      db,
      '''
        SELECT FIRST 1 META_VALUE
        FROM APP_META
        WHERE META_KEY = ?
      ''',
      parameters: [_chatVisibleFromMetaKey],
    );

    final parsed = _parseStoredDateTime(existing?['meta_value']?.toString());
    if (parsed != null) {
      return parsed;
    }

    final now = DateTime.now();
    await db.execute(
      sql: '''
        UPDATE OR INSERT INTO APP_META (META_KEY, META_VALUE)
        VALUES (?, ?)
        MATCHING (META_KEY)
      ''',
      parameters: [_chatVisibleFromMetaKey, _formatDateTime(now)],
    );
    return now;
  }

  /// Registra uma mensagem na conversa.
  Future<int> registrarMensagem({
    required String telefone,
    String nomeCliente = '',
    String destinoEnvio = '',
    required String direcao,
    required String conteudo,
    String tipoMsg = 'texto',
    String mensagemId = '',
    String arquivoNome = '',
    String arquivoMime = '',
    int arquivoTamanho = 0,
    Uint8List? arquivoDados,
    String mediaUrl = '',
    double? latitude,
    double? longitude,
    String localNome = '',
    String localEndereco = '',
    DateTime? registradoEm,
  }) async {
    final db = await database;
    final normalizedContent = conteudo.trim();
    final normalizedTarget = destinoEnvio.trim();
    final normalizedName = nomeCliente.trim();
    final normalizedType = tipoMsg.trim().isEmpty ? 'texto' : tipoMsg.trim();
    final normalizedMessageId = mensagemId.trim();
    final normalizedFileName = arquivoNome.trim();
    final normalizedMime = arquivoMime.trim();
    final normalizedMediaUrl = mediaUrl.trim();
    final normalizedLocationName = localNome.trim();
    final normalizedLocationAddress = localEndereco.trim();
    final hasAttachmentBytes = arquivoDados != null && arquivoDados.isNotEmpty;
    final hasRichPayload =
        normalizedType != 'texto' ||
        normalizedFileName.isNotEmpty ||
        normalizedMediaUrl.isNotEmpty ||
        hasAttachmentBytes ||
        latitude != null ||
        longitude != null ||
        normalizedLocationName.isNotEmpty ||
        normalizedLocationAddress.isNotEmpty;

    if (normalizedContent.isEmpty && !hasRichPayload) {
      throw ArgumentError('A mensagem precisa ter texto ou conteudo anexo.');
    }

    if (normalizedMessageId.isNotEmpty) {
      final existingByMessageId = await _selectOneDb(
        db,
        '''
          SELECT FIRST 1 ID
          FROM CONVERSAS
          WHERE TELEFONE = ?
            AND DIRECAO = ?
            AND MENSAGEM_ID = ?
          ORDER BY ID DESC
        ''',
        parameters: [telefone, direcao, normalizedMessageId],
      );

      if (existingByMessageId != null) {
        return _asInt(existingByMessageId['id']);
      }
    }

    if (registradoEm != null &&
        (normalizedContent.isNotEmpty || hasRichPayload)) {
      final existing = await _selectOneDb(
        db,
        '''
          SELECT FIRST 1 ID
          FROM CONVERSAS
          WHERE TELEFONE = ?
            AND DIRECAO = ?
            AND CONTEUDO = ?
            AND TIPO_MSG = ?
            AND REGISTRADO_EM = ?
          ORDER BY ID DESC
        ''',
        parameters: [
          telefone,
          direcao,
          normalizedContent,
          normalizedType,
          registradoEm,
        ],
      );

      if (existing != null) {
        final id = _asInt(existing['id']);
        if (normalizedTarget.isNotEmpty) {
          await db.execute(
            sql: '''
              UPDATE CONVERSAS
              SET DESTINO_ENVIO = ?
              WHERE ID = ?
                AND TRIM(COALESCE(DESTINO_ENVIO, '')) = ''
            ''',
            parameters: [normalizedTarget, id],
          );
        }
        return id;
      }
    }

    final inserted = await _executeReturningOneDb(
      db,
      registradoEm == null
          ? '''
              INSERT INTO CONVERSAS (
                TELEFONE,
                NOME_CLIENTE,
                DESTINO_ENVIO,
                DIRECAO,
                CONTEUDO,
                TIPO_MSG,
                MENSAGEM_ID,
                ARQUIVO_NOME,
                ARQUIVO_MIME,
                ARQUIVO_TAMANHO,
                ARQUIVO_DADOS,
                MEDIA_URL,
                LATITUDE,
                LONGITUDE,
                LOCAL_NOME,
                LOCAL_ENDERECO
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              RETURNING ID
            '''
          : '''
              INSERT INTO CONVERSAS (
                TELEFONE,
                NOME_CLIENTE,
                DESTINO_ENVIO,
                DIRECAO,
                CONTEUDO,
                TIPO_MSG,
                MENSAGEM_ID,
                ARQUIVO_NOME,
                ARQUIVO_MIME,
                ARQUIVO_TAMANHO,
                ARQUIVO_DADOS,
                MEDIA_URL,
                LATITUDE,
                LONGITUDE,
                LOCAL_NOME,
                LOCAL_ENDERECO,
                REGISTRADO_EM
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              RETURNING ID
            ''',
      parameters: registradoEm == null
          ? [
              telefone,
              normalizedName,
              normalizedTarget,
              direcao,
              normalizedContent,
              normalizedType,
              normalizedMessageId,
              normalizedFileName,
              normalizedMime,
              arquivoTamanho,
              arquivoDados,
              normalizedMediaUrl,
              latitude,
              longitude,
              normalizedLocationName,
              normalizedLocationAddress,
            ]
          : [
              telefone,
              normalizedName,
              normalizedTarget,
              direcao,
              normalizedContent,
              normalizedType,
              normalizedMessageId,
              normalizedFileName,
              normalizedMime,
              arquivoTamanho,
              arquivoDados,
              normalizedMediaUrl,
              latitude,
              longitude,
              normalizedLocationName,
              normalizedLocationAddress,
              registradoEm,
            ],
    );

    return _asInt(inserted['id']);
  }

  /// Recupera conversas de um telefone.
  Future<List<Map<String, dynamic>>> getConversas(
    String telefone, {
    DateTime? visibleFrom,
  }) async {
    final db = await database;
    return await _selectAllDb(
      db,
      '''
        SELECT
          TELEFONE,
          NOME_CLIENTE,
          DESTINO_ENVIO,
          DIRECAO,
          CONTEUDO,
          TIPO_MSG,
          MENSAGEM_ID,
          ARQUIVO_NOME,
          ARQUIVO_MIME,
          ARQUIVO_TAMANHO,
          ARQUIVO_DADOS,
          MEDIA_URL,
          LATITUDE,
          LONGITUDE,
          LOCAL_NOME,
          LOCAL_ENDERECO,
          REGISTRADO_EM
        FROM CONVERSAS
        WHERE TELEFONE = ?
        ${visibleFrom == null ? '' : 'AND REGISTRADO_EM >= ?'}
        ORDER BY REGISTRADO_EM ASC
      ''',
      parameters: visibleFrom == null ? [telefone] : [telefone, visibleFrom],
    );
  }

  /// Lista contatos que possuem ao menos uma mensagem (recebida OU enviada),
  /// para que o chat mostre tambem conversas iniciadas por nos. O nome exibido
  /// prioriza o nome completo importado da planilha (ENVIOS/CLIENTES) sobre o
  /// pushName do WhatsApp. Tambem retorna a contagem de mensagens recebidas
  /// ainda nao lidas (NAO_LIDAS) para o selo verde estilo WhatsApp.
  Future<List<Map<String, dynamic>>> getChatContacts({
    DateTime? visibleFrom,
  }) async {
    final db = await database;
    final args = <dynamic>[];
    final visibleFilter = visibleFrom == null ? '' : 'AND C.REGISTRADO_EM >= ?';
    final previewFilter = visibleFrom == null
        ? ''
        : 'AND C2.REGISTRADO_EM >= ?';
    final targetFilter = visibleFrom == null ? '' : 'AND C4.REGISTRADO_EM >= ?';
    final nameFilter = visibleFrom == null ? '' : 'AND C3.REGISTRADO_EM >= ?';
    final unreadFilter = visibleFrom == null ? '' : 'AND CU.REGISTRADO_EM >= ?';

    // Ordem dos placeholders segue a ordem em que aparecem no SQL.
    if (visibleFrom != null) {
      args.add(visibleFrom); // NOME_CLIENTE (C3)
      args.add(visibleFrom); // ULTIMA_MENSAGEM (C2)
      args.add(visibleFrom); // ULTIMO_TIPO_MSG (C2)
      args.add(visibleFrom); // ULTIMO_ARQUIVO_NOME (C2)
      args.add(visibleFrom); // ULTIMO_LOCAL_NOME (C2)
      args.add(visibleFrom); // DESTINO_ENVIO (C4)
      args.add(visibleFrom); // NAO_LIDAS (CU)
      args.add(visibleFrom); // ULTIMA_INTERACAO (C2)
      args.add(visibleFrom); // outer WHERE (C)
    }

    final rows = await _selectAllDb(db, '''
        SELECT
          C.TELEFONE AS TELEFONE,
          NULLIF(
            (
              SELECT FIRST 1 C3.NOME_CLIENTE
              FROM CONVERSAS C3
              WHERE C3.TELEFONE = C.TELEFONE
                AND TRIM(COALESCE(C3.NOME_CLIENTE, '')) <> ''
                $nameFilter
              ORDER BY C3.REGISTRADO_EM DESC
            ),
            ''
          ) AS NOME_CLIENTE,
          (
            SELECT FIRST 1 NULLIF(E.NOME_CLIENTE, '')
            FROM ENVIOS E
            WHERE E.TELEFONE_COMPLETO = C.TELEFONE
              AND TRIM(COALESCE(E.NOME_CLIENTE, '')) <> ''
            ORDER BY E.ENVIADO_EM DESC
          ) AS NOME_ENVIO,
          (
            SELECT FIRST 1 CL.NOME
            FROM CLIENTES CL
            WHERE TRIM(COALESCE(CL.NOME, '')) <> ''
              AND (
                CL.TELEFONE = C.TELEFONE
                OR (CL.DDD || CL.TELEFONE) = C.TELEFONE
                OR ('55' || CL.DDD || CL.TELEFONE) = C.TELEFONE
              )
            ORDER BY CL.ID DESC
          ) AS NOME_CLIENTE_PLANILHA,
          (
            SELECT FIRST 1 C2.CONTEUDO
            FROM CONVERSAS C2
            WHERE C2.TELEFONE = C.TELEFONE
              $previewFilter
            ORDER BY C2.REGISTRADO_EM DESC
          ) AS ULTIMA_MENSAGEM,
          (
            SELECT FIRST 1 C2.TIPO_MSG
            FROM CONVERSAS C2
            WHERE C2.TELEFONE = C.TELEFONE
              $previewFilter
            ORDER BY C2.REGISTRADO_EM DESC
          ) AS ULTIMO_TIPO_MSG,
          (
            SELECT FIRST 1 C2.ARQUIVO_NOME
            FROM CONVERSAS C2
            WHERE C2.TELEFONE = C.TELEFONE
              $previewFilter
            ORDER BY C2.REGISTRADO_EM DESC
          ) AS ULTIMO_ARQUIVO_NOME,
          (
            SELECT FIRST 1 C2.LOCAL_NOME
            FROM CONVERSAS C2
            WHERE C2.TELEFONE = C.TELEFONE
              $previewFilter
            ORDER BY C2.REGISTRADO_EM DESC
          ) AS ULTIMO_LOCAL_NOME,
          (
            SELECT FIRST 1 C4.DESTINO_ENVIO
            FROM CONVERSAS C4
            WHERE C4.TELEFONE = C.TELEFONE
              AND TRIM(COALESCE(C4.DESTINO_ENVIO, '')) <> ''
              $targetFilter
            ORDER BY C4.REGISTRADO_EM DESC
          ) AS DESTINO_ENVIO,
          (
            SELECT COUNT(*)
            FROM CONVERSAS CU
            WHERE CU.TELEFONE = C.TELEFONE
              AND CU.DIRECAO = 'recebida'
              AND CU.REGISTRADO_EM > COALESCE(
                (
                  SELECT FIRST 1 L.LIDA_EM
                  FROM CHAT_LEITURA L
                  WHERE L.TELEFONE = C.TELEFONE
                ),
                TIMESTAMP '1900-01-01 00:00:00'
              )
              $unreadFilter
          ) AS NAO_LIDAS,
          (
            SELECT FIRST 1 C2.REGISTRADO_EM
            FROM CONVERSAS C2
            WHERE C2.TELEFONE = C.TELEFONE
              $previewFilter
            ORDER BY C2.REGISTRADO_EM DESC
          ) AS ULTIMA_INTERACAO
        FROM CONVERSAS C
        WHERE 1 = 1
          $visibleFilter
        GROUP BY C.TELEFONE
        ORDER BY ULTIMA_INTERACAO DESC
      ''', parameters: args);

    // Escolhe o nome mais completo (planilha > envio > pushName) sem perder o
    // fallback para o proprio telefone quando nenhum nome esta disponivel.
    for (final row in rows) {
      final nomeConversa = row['nome_cliente']?.toString().trim() ?? '';
      final nomeEnvio = row['nome_envio']?.toString().trim() ?? '';
      final nomePlanilha = row['nome_cliente_planilha']?.toString().trim() ?? '';
      final telefone = row['telefone']?.toString().trim() ?? '';

      var resolved = _pickFullerName(nomeConversa, nomeEnvio);
      resolved = _pickFullerName(resolved, nomePlanilha);
      row['nome_cliente'] = resolved.isEmpty ? telefone : resolved;
    }

    return rows;
  }

  /// Marca a conversa de [telefone] como lida ate agora (zera o selo verde).
  ///
  /// LIDA_EM e definido como o MAIOR entre o REGISTRADO_EM mais recente da
  /// conversa e o CURRENT_TIMESTAMP do servidor Firebird. Isso garante:
  /// - Comparacoes futuras (`REGISTRADO_EM > LIDA_EM`) ficam no mesmo "frame"
  ///   de timestamp do banco, eliminando deriva de fuso entre o relogio do
  ///   app (DateTime local) e o relogio do servidor.
  /// - Se uma mensagem antiga for re-persistida pelo polling (duplicata cuja
  ///   deduplicacao falhou), LIDA_EM continuara >= ao REGISTRADO_EM dela,
  ///   entao o selo de nao-lidas NAO reaparece de forma falsa.
  Future<void> markChatRead(String telefone) async {
    final normalized = telefone.trim();
    if (normalized.isEmpty) {
      return;
    }
    final db = await database;
    await db.execute(
      sql: '''
        UPDATE OR INSERT INTO CHAT_LEITURA (TELEFONE, LIDA_EM)
        VALUES (
          ?,
          (
            SELECT
              CASE
                WHEN MAX(C.REGISTRADO_EM) IS NULL THEN CURRENT_TIMESTAMP
                WHEN MAX(C.REGISTRADO_EM) > CURRENT_TIMESTAMP
                  THEN MAX(C.REGISTRADO_EM)
                ELSE CURRENT_TIMESTAMP
              END
            FROM CONVERSAS C
            WHERE C.TELEFONE = ?
          )
        )
        MATCHING (TELEFONE)
      ''',
      parameters: [normalized, normalized],
    );
  }

  /// Persiste os bytes decifrados de uma midia em uma conversa ja registrada.
  ///
  /// Usado quando a primeira sincronizacao salvou apenas a `MEDIA_URL` (URL
  /// criptografada do WhatsApp, impossivel de baixar via GET) e a UI agora
  /// conseguiu obter o conteudo decifrado via `getBase64FromMediaMessage`.
  /// Casamos pela tupla (TELEFONE, MENSAGEM_ID) que ja e unica por design.
  Future<void> updateConversaMediaBytes({
    required String telefone,
    required String mensagemId,
    required Uint8List fileBytes,
    int fileSize = 0,
  }) async {
    final normalizedTelefone = telefone.trim();
    final normalizedMessageId = mensagemId.trim();
    if (normalizedTelefone.isEmpty ||
        normalizedMessageId.isEmpty ||
        fileBytes.isEmpty) {
      return;
    }

    final effectiveSize = fileSize > 0 ? fileSize : fileBytes.length;
    final db = await database;
    await db.execute(
      sql: '''
        UPDATE CONVERSAS
        SET ARQUIVO_DADOS = ?,
            ARQUIVO_TAMANHO = CASE
              WHEN COALESCE(ARQUIVO_TAMANHO, 0) > 0 THEN ARQUIVO_TAMANHO
              ELSE ?
            END
        WHERE TELEFONE = ?
          AND MENSAGEM_ID = ?
      ''',
      parameters: [fileBytes, effectiveSize, normalizedTelefone, normalizedMessageId],
    );
  }

  /// Monta a linha do tempo do chat com os disparos em massa e as conversas.
  Future<List<Map<String, dynamic>>> getConversationTimeline(
    String telefone, {
    DateTime? visibleFrom,
  }) async {
    final db = await database;
    final conversasFilter = visibleFrom == null ? '' : 'AND REGISTRADO_EM >= ?';
    final args = <dynamic>[telefone];
    if (visibleFrom != null) {
      args.add(visibleFrom);
    }
    args.add(telefone);
    final enviosFilter = visibleFrom == null ? '' : 'AND ENVIADO_EM >= ?';
    if (visibleFrom != null) {
      args.add(visibleFrom);
    }

    return await _selectAllDb(db, '''
        SELECT *
        FROM (
          SELECT
            TELEFONE,
            NOME_CLIENTE,
            DESTINO_ENVIO,
            DIRECAO,
            CONTEUDO,
            TIPO_MSG,
            MENSAGEM_ID,
            ARQUIVO_NOME,
            ARQUIVO_MIME,
            ARQUIVO_TAMANHO,
            ARQUIVO_DADOS,
            MEDIA_URL,
            LATITUDE,
            LONGITUDE,
            LOCAL_NOME,
            LOCAL_ENDERECO,
            REGISTRADO_EM
          FROM CONVERSAS
          WHERE TELEFONE = ?
            $conversasFilter

          UNION ALL

          SELECT
            TELEFONE_COMPLETO AS TELEFONE,
            NOME_CLIENTE,
            '' AS DESTINO_ENVIO,
            'enviada' AS DIRECAO,
            MENSAGEM_ENVIADA AS CONTEUDO,
            TIPO AS TIPO_MSG,
            '' AS MENSAGEM_ID,
            '' AS ARQUIVO_NOME,
            '' AS ARQUIVO_MIME,
            0 AS ARQUIVO_TAMANHO,
            NULL AS ARQUIVO_DADOS,
            '' AS MEDIA_URL,
            NULL AS LATITUDE,
            NULL AS LONGITUDE,
            '' AS LOCAL_NOME,
            '' AS LOCAL_ENDERECO,
            ENVIADO_EM AS REGISTRADO_EM
          FROM ENVIOS
          WHERE TELEFONE_COMPLETO = ?
            AND SUCESSO = 1
            AND TIPO = 'massa'
            AND TRIM(COALESCE(MENSAGEM_ENVIADA, '')) <> ''
            $enviosFilter
        ) TIMELINE
        ORDER BY REGISTRADO_EM ASC
      ''', parameters: args);
  }

  /// Lista os clientes que responderam a um disparo e ainda aguardam retorno.
  ///
  /// Critério de "pendente": o contato possui ao menos uma mensagem recebida
  /// (`recebida`) cujo horário é mais recente que o último envio nosso
  /// (massa/auto via ENVIOS, ou manual/auto via CONVERSAS). Ou seja, a bola
  /// está com a gente. Assim que respondemos, ele sai da lista naturalmente.
  Future<List<Map<String, dynamic>>> getPendingResponseClients({
    DateTime? visibleFrom,
  }) async {
    final db = await database;
    final args = <dynamic>[];
    final visibleFilter = visibleFrom == null ? '' : 'WHERE C.REGISTRADO_EM >= ?';
    if (visibleFrom != null) {
      args.add(visibleFrom);
    }

    final rows = await _selectAllDb(db, '''
        SELECT
          C.TELEFONE AS TELEFONE,
          MAX(CASE WHEN C.DIRECAO = 'recebida' THEN C.REGISTRADO_EM END)
            AS LAST_IN,
          MAX(CASE WHEN C.DIRECAO IN ('enviada_manual', 'enviada_auto')
            THEN C.REGISTRADO_EM END) AS LAST_OUT_CONV,
          (
            SELECT MAX(E.ENVIADO_EM)
            FROM ENVIOS E
            WHERE E.SUCESSO = 1
              AND (
                E.TELEFONE_COMPLETO = C.TELEFONE
                OR (
                  -- Tolera divergencia do "9" extra em celulares antigos vs novos,
                  -- mas exige DDI+DDD iguais para nao colidir entre cidades.
                  SUBSTRING(E.TELEFONE_COMPLETO FROM 1 FOR 4)
                    = SUBSTRING(C.TELEFONE FROM 1 FOR 4)
                  AND RIGHT(E.TELEFONE_COMPLETO, 8) = RIGHT(C.TELEFONE, 8)
                )
              )
          ) AS LAST_OUT_ENVIO,
          (
            SELECT FIRST 1 C3.NOME_CLIENTE
            FROM CONVERSAS C3
            WHERE C3.TELEFONE = C.TELEFONE
              AND TRIM(COALESCE(C3.NOME_CLIENTE, '')) <> ''
            ORDER BY C3.REGISTRADO_EM DESC
          ) AS NOME_CLIENTE,
          (
            SELECT FIRST 1 C2.CONTEUDO
            FROM CONVERSAS C2
            WHERE C2.TELEFONE = C.TELEFONE
              AND C2.DIRECAO = 'recebida'
            ORDER BY C2.REGISTRADO_EM DESC
          ) AS ULTIMA_MENSAGEM,
          (
            SELECT FIRST 1 C4.DESTINO_ENVIO
            FROM CONVERSAS C4
            WHERE C4.TELEFONE = C.TELEFONE
              AND TRIM(COALESCE(C4.DESTINO_ENVIO, '')) <> ''
            ORDER BY C4.REGISTRADO_EM DESC
          ) AS DESTINO_ENVIO,
          (
            SELECT FIRST 1 E2.NOME_CLIENTE
            FROM ENVIOS E2
            WHERE TRIM(COALESCE(E2.NOME_CLIENTE, '')) <> ''
              AND (
                E2.TELEFONE_COMPLETO = C.TELEFONE
                OR (
                  SUBSTRING(E2.TELEFONE_COMPLETO FROM 1 FOR 4)
                    = SUBSTRING(C.TELEFONE FROM 1 FOR 4)
                  AND RIGHT(E2.TELEFONE_COMPLETO, 8) = RIGHT(C.TELEFONE, 8)
                )
              )
            ORDER BY E2.ENVIADO_EM DESC
          ) AS NOME_ENVIO
        FROM CONVERSAS C
        $visibleFilter
        GROUP BY C.TELEFONE
        HAVING MAX(CASE WHEN C.DIRECAO = 'recebida'
          THEN C.REGISTRADO_EM END) IS NOT NULL
        ORDER BY LAST_IN DESC
      ''', parameters: args);

    final pending = <Map<String, dynamic>>[];
    for (final row in rows) {
      final lastIn = _parseStoredDateTime(row['last_in']?.toString());
      if (lastIn == null) {
        continue;
      }

      final lastOutConv = _parseStoredDateTime(row['last_out_conv']?.toString());
      final lastOutEnvio = _parseStoredDateTime(
        row['last_out_envio']?.toString(),
      );

      // Só consideramos quem já recebeu um envio nosso — caso contrário não é
      // resposta a campanha, e sim um contato espontâneo.
      DateTime? lastOut;
      if (lastOutConv != null) {
        lastOut = lastOutConv;
      }
      if (lastOutEnvio != null &&
          (lastOut == null || lastOutEnvio.isAfter(lastOut))) {
        lastOut = lastOutEnvio;
      }
      if (lastOut == null) {
        continue;
      }

      // Pendente apenas se a resposta do cliente é mais recente que o nosso
      // último envio (ainda não respondemos depois que ele falou).
      if (!lastIn.isAfter(lastOut)) {
        continue;
      }

      // Preferimos o nome mais completo entre o pushName salvo nas conversas
      // e o NOME_CLIENTE do envio (que guarda o nome completo da planilha),
      // para melhor gestao. O envio em si continua usando so o primeiro nome.
      final nomeConversa = row['nome_cliente']?.toString().trim() ?? '';
      final nomeEnvio = row['nome_envio']?.toString().trim() ?? '';
      final nome = _pickFullerName(nomeConversa, nomeEnvio);

      pending.add({
        'telefone': row['telefone']?.toString() ?? '',
        'nome': nome,
        'ultima_mensagem': row['ultima_mensagem']?.toString() ?? '',
        'destino_envio': row['destino_envio']?.toString() ?? '',
        'last_in': row['last_in'],
      });
    }

    return pending;
  }

  /// Recupera todos os envios de hoje.
  Future<List<Map<String, dynamic>>> getEnviosHoje() async {
    final db = await database;
    final bounds = _dayBounds(DateTime.now());
    return await _selectAllDb(
      db,
      '''
        SELECT
          ID,
          CLIENTE_ID,
          TELEFONE_COMPLETO,
          NOME_CLIENTE,
          SUCESSO,
          MENSAGEM_STATUS,
          MENSAGEM_ENVIADA,
          TIPO,
          ENVIADO_EM
        FROM ENVIOS
        WHERE ENVIADO_EM >= ?
          AND ENVIADO_EM < ?
        ORDER BY ENVIADO_EM DESC
      ''',
      parameters: [bounds.start, bounds.end],
    );
  }

  _DayBounds _dayBounds(DateTime reference) {
    final start = DateTime(reference.year, reference.month, reference.day);
    return _DayBounds(start: start, end: start.add(const Duration(days: 1)));
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  DateTime? _parseStoredDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return DateTime.tryParse(value.replaceFirst(' ', 'T'))?.toLocal();
  }

  /// Escolhe o nome mais "completo" (com mais palavras) entre dois candidatos.
  /// Em empate, prioriza o primeiro nao-vazio.
  String _pickFullerName(String a, String b) {
    final wordsA = a.trim().isEmpty ? 0 : a.trim().split(RegExp(r'\s+')).length;
    final wordsB = b.trim().isEmpty ? 0 : b.trim().split(RegExp(r'\s+')).length;
    if (wordsB > wordsA) {
      return b.trim();
    }
    if (wordsA > 0) {
      return a.trim();
    }
    return b.trim();
  }

  String _normalizePersonName(String value) {
    var normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return '';
    }

    final replacements = <String, String>{
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };

    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });

    final parts = normalized
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '';
    }

    return parts.first;
  }

  Future<void> close() async {
    if (_db == null) {
      return;
    }
    await _db!.detach();
    _db = null;
  }

  // USUARIOS / AUTENTICACAO

  /// Garante o usuário padrão e o token de administrador em toda geração do
  /// banco. Não sobrescreve valores existentes (não reseta senha do admin se
  /// já tiver sido alterada manualmente).
  Future<void> _seedDefaultAuth(FbDb db) async {
    try {
      // Token de administrador (APP_META).
      final tokenRow = await _selectOneDb(
        db,
        'SELECT FIRST 1 META_VALUE FROM APP_META WHERE META_KEY = ?',
        parameters: [_adminTokenMetaKey],
      );
      if (tokenRow == null) {
        await db.execute(
          sql: '''
            UPDATE OR INSERT INTO APP_META (META_KEY, META_VALUE)
            VALUES (?, ?)
            MATCHING (META_KEY)
          ''',
          parameters: [_adminTokenMetaKey, _defaultAdminToken],
        );
      }

      // Usuário padrão.
      final userRow = await _selectOneDb(
        db,
        'SELECT FIRST 1 ID FROM USUARIOS WHERE LOWER(EMAIL) = ?',
        parameters: [_defaultUserEmail.toLowerCase()],
      );
      if (userRow == null) {
        final salt = _generateSalt();
        await db.execute(
          sql: '''
            INSERT INTO USUARIOS
              (EMAIL, NOME_COMPLETO, NOME_PREFERIDO, SALT, SENHA_HASH)
            VALUES (?, ?, ?, ?, ?)
          ''',
          parameters: [
            _defaultUserEmail.toLowerCase(),
            _defaultUserNome,
            _defaultUserApelido,
            salt,
            _hashPassword(_defaultUserPassword, salt),
          ],
        );
      }
    } catch (e) {
      // Falha de seed não deve impedir a abertura do banco.
    }
  }

  /// Verifica e-mail + senha. Retorna os dados do usuário (sem hash) ou null.
  Future<Map<String, dynamic>?> autenticarUsuario({
    required String email,
    required String senha,
  }) async {
    final db = await database;
    final normalizedEmail = email.trim().toLowerCase();
    final row = await _selectOneDb(
      db,
      '''
        SELECT FIRST 1 ID, EMAIL, NOME_COMPLETO, NOME_PREFERIDO, SALT, SENHA_HASH
        FROM USUARIOS
        WHERE LOWER(EMAIL) = ?
      ''',
      parameters: [normalizedEmail],
    );

    if (row == null) {
      return null;
    }

    final salt = row['salt']?.toString() ?? '';
    final expectedHash = row['senha_hash']?.toString() ?? '';
    if (_hashPassword(senha, salt) != expectedHash) {
      return null;
    }

    return {
      'id': _asInt(row['id']),
      'email': row['email']?.toString() ?? '',
      'nome_completo': row['nome_completo']?.toString() ?? '',
      'nome_preferido': row['nome_preferido']?.toString() ?? '',
    };
  }

  /// Recarrega os dados de um usuário pelo ID, sem revalidar senha.
  /// Usado pela restauração de sessão persistida (1x/dia).
  Future<Map<String, dynamic>?> carregarUsuarioPorId(int id) async {
    if (id <= 0) return null;
    final db = await database;
    final row = await _selectOneDb(
      db,
      '''
        SELECT FIRST 1 ID, EMAIL, NOME_COMPLETO, NOME_PREFERIDO
        FROM USUARIOS
        WHERE ID = ?
      ''',
      parameters: [id],
    );
    if (row == null) return null;
    return {
      'id': _asInt(row['id']),
      'email': row['email']?.toString() ?? '',
      'nome_completo': row['nome_completo']?.toString() ?? '',
      'nome_preferido': row['nome_preferido']?.toString() ?? '',
    };
  }

  Future<bool> emailJaCadastrado(String email) async {
    final db = await database;
    final row = await _selectOneDb(
      db,
      'SELECT FIRST 1 ID FROM USUARIOS WHERE LOWER(EMAIL) = ?',
      parameters: [email.trim().toLowerCase()],
    );
    return row != null;
  }

  /// Valida o token de administrador exigido no cadastro.
  Future<bool> validarTokenAdmin(String token) async {
    final db = await database;
    final row = await _selectOneDb(
      db,
      'SELECT FIRST 1 META_VALUE FROM APP_META WHERE META_KEY = ?',
      parameters: [_adminTokenMetaKey],
    );
    final expected = row?['meta_value']?.toString() ?? _defaultAdminToken;
    return token.trim() == expected;
  }

  /// Cadastra um novo usuário. Lança [StateError] se o e-mail já existe.
  Future<int> registrarUsuario({
    required String email,
    required String senha,
    required String nomeCompleto,
    required String nomePreferido,
  }) async {
    final db = await database;
    final normalizedEmail = email.trim().toLowerCase();

    if (await emailJaCadastrado(normalizedEmail)) {
      throw StateError('E-mail já cadastrado.');
    }

    final salt = _generateSalt();
    final inserted = await _executeReturningOneDb(
      db,
      '''
        INSERT INTO USUARIOS
          (EMAIL, NOME_COMPLETO, NOME_PREFERIDO, SALT, SENHA_HASH)
        VALUES (?, ?, ?, ?, ?)
        RETURNING ID
      ''',
      parameters: [
        normalizedEmail,
        nomeCompleto.trim(),
        nomePreferido.trim(),
        salt,
        _hashPassword(senha, salt),
      ],
    );
    return _asInt(inserted['id']);
  }

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashPassword(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  // MODELOS DE MENSAGEM

  /// Salva um modelo de mensagem no banco de dados.
  Future<int> salvarModelo({
    required String nome,
    required List<String> mensagens,
  }) async {
    final db = await database;
    final msgs = List<String>.generate(
      6,
      (i) => i < mensagens.length ? mensagens[i] : '',
    );
    final inserted = await _executeReturningOneDb(
      db,
      '''
        INSERT INTO MODELOS_MENSAGEM (NOME, MSG1, MSG2, MSG3, MSG4, MSG5, MSG6)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        RETURNING ID
      ''',
      parameters: [nome, msgs[0], msgs[1], msgs[2], msgs[3], msgs[4], msgs[5]],
    );
    return _asInt(inserted['id']);
  }

  /// Retorna todos os modelos salvos, mais recentes primeiro.
  Future<List<Map<String, dynamic>>> listarModelos() async {
    final db = await database;
    final rows = await _selectAllDb(db, '''
      SELECT ID, NOME, MSG1, MSG2, MSG3, MSG4, MSG5, MSG6, CRIADO_EM
      FROM MODELOS_MENSAGEM
      ORDER BY CRIADO_EM DESC
    ''');
    return rows.map(_normalizeModeloMensagemRow).toList(growable: false);
  }

  Map<String, dynamic> _normalizeModeloMensagemRow(Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    for (var i = 1; i <= 6; i++) {
      normalized['msg$i'] = _decodeTextBlob(normalized['msg$i']);
    }
    return normalized;
  }

  String _decodeTextBlob(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return value;
    }

    Uint8List? bytes;
    var sourceWasBytes = false;
    if (value is Uint8List) {
      bytes = value;
      sourceWasBytes = true;
    } else if (value is ByteBuffer) {
      bytes = value.asUint8List();
      sourceWasBytes = true;
    } else if (value is ByteData) {
      bytes = value.buffer.asUint8List(
        value.offsetInBytes,
        value.lengthInBytes,
      );
      sourceWasBytes = true;
    } else if (value is TypedData) {
      bytes = value.buffer.asUint8List(
        value.offsetInBytes,
        value.lengthInBytes,
      );
      sourceWasBytes = true;
    } else if (value is List<int>) {
      bytes = Uint8List.fromList(value);
      sourceWasBytes = true;
    }

    // BLOB vazio (null/empty bytes/lista vazia) representa string vazia,
    // não "[]" — toString() de uma List vazia retorna "[]".
    if (sourceWasBytes && (bytes == null || bytes.isEmpty)) {
      return '';
    }

    if (bytes == null) {
      return value.toString();
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  /// Remove um modelo pelo ID.
  Future<void> excluirModelo(int id) async {
    final db = await database;
    await db.execute(
      sql: 'DELETE FROM MODELOS_MENSAGEM WHERE ID = ?',
      parameters: [id],
    );
  }

  // ESTATÍSTICAS PARA GRÁFICOS

  /// Retorna contagem de envios com sucesso por dia nos últimos [days] dias.
  Future<List<Map<String, dynamic>>> getEnviosPorDia({int days = 7}) async {
    final db = await database;
    final start = DateTime.now().subtract(Duration(days: days));
    final startDate = DateTime(start.year, start.month, start.day);
    return await _selectAllDb(
      db,
      '''
        SELECT
          CAST(ENVIADO_EM AS DATE) AS DIA,
          SUM(CASE WHEN SUCESSO = 1 THEN 1 ELSE 0 END) AS SUCESSO_COUNT,
          SUM(CASE WHEN SUCESSO = 0 THEN 1 ELSE 0 END) AS FALHA_COUNT,
          COUNT(*) AS TOTAL
        FROM ENVIOS
        WHERE ENVIADO_EM >= ?
        GROUP BY CAST(ENVIADO_EM AS DATE)
        ORDER BY DIA ASC
      ''',
      parameters: [startDate],
    );
  }

  /// Retorna contagem de mensagens recebidas por dia nos últimos [days] dias.
  Future<List<Map<String, dynamic>>> getMensagensRecebidasPorDia({
    int days = 7,
  }) async {
    final db = await database;
    final start = DateTime.now().subtract(Duration(days: days));
    final startDate = DateTime(start.year, start.month, start.day);
    return await _selectAllDb(
      db,
      '''
        SELECT
          CAST(REGISTRADO_EM AS DATE) AS DIA,
          COUNT(*) AS TOTAL
        FROM CONVERSAS
        WHERE DIRECAO = 'recebida'
          AND REGISTRADO_EM >= ?
        GROUP BY CAST(REGISTRADO_EM AS DATE)
        ORDER BY DIA ASC
      ''',
      parameters: [startDate],
    );
  }

  /// Retorna total de envios com sucesso e total de respostas recebidas (para taxa de retorno).
  Future<Map<String, int>> getEstatisticasGerais() async {
    final db = await database;
    final enviosTotal = await _selectOneDb(db, '''
      SELECT COUNT(*) AS TOTAL FROM ENVIOS WHERE SUCESSO = 1
    ''');
    final respostasTotal = await _selectOneDb(db, '''
      SELECT COUNT(*) AS TOTAL FROM CONVERSAS WHERE DIRECAO = 'recebida'
    ''');
    final enviosHoje = await countEnviosHojeSucesso();
    final falhasHoje = await countEnviosHojeFalha();
    final respostasHoje = await _selectOneDb(
      db,
      '''
      SELECT COUNT(*) AS TOTAL FROM CONVERSAS
      WHERE DIRECAO = 'recebida'
        AND REGISTRADO_EM >= ?
        AND REGISTRADO_EM < ?
    ''',
      parameters: [
        _dayBounds(DateTime.now()).start,
        _dayBounds(DateTime.now()).end,
      ],
    );

    return {
      'envios_total': _asInt(enviosTotal?['total']),
      'respostas_total': _asInt(respostasTotal?['total']),
      'envios_hoje': enviosHoje,
      'falhas_hoje': falhasHoje,
      'respostas_hoje': _asInt(respostasHoje?['total']),
    };
  }
}

class _DayBounds {
  const _DayBounds({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
