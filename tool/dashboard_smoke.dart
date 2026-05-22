import 'dart:io';

import 'package:money/data/datasources/database_service.dart';

Future<void> main() async {
  final service = DatabaseService.instance;
  final db = await service.database;

  final tag = '__dashboard_smoke_${DateTime.now().microsecondsSinceEpoch}__';
  final phone = '5599999999999';

  int? envioId;
  int? conversaId;

  try {
    final before = await service.getEstatisticasGerais();

    envioId = await service.registrarEnvio(
      telefoneCompleto: phone,
      nomeCliente: 'Dashboard Smoke',
      sucesso: true,
      mensagemStatus: 'Smoke OK',
      mensagemEnviada: tag,
      tipo: 'smoke',
    );
    conversaId = await service.registrarMensagem(
      telefone: phone,
      nomeCliente: 'Dashboard Smoke',
      direcao: 'recebida',
      conteudo: tag,
      tipoMsg: 'texto',
      mensagemId: tag,
    );

    final enviosPorDia = await service.getEnviosPorDia(days: 7);
    final respostasPorDia = await service.getMensagensRecebidasPorDia(days: 7);
    final stats = await service.getEstatisticasGerais();
    final enviosHoje = await service.getEnviosHoje();

    final expectedEnviosHoje = _asInt(before['envios_hoje']) + 1;
    final expectedRespostasHoje = _asInt(before['respostas_hoje']) + 1;
    final expectedEnviosTotal = _asInt(before['envios_total']) + 1;
    final expectedRespostasTotal = _asInt(before['respostas_total']) + 1;

    _expectAtLeast(
      _asInt(stats['envios_hoje']),
      expectedEnviosHoje,
      'envios_hoje',
    );
    _expectAtLeast(
      _asInt(stats['respostas_hoje']),
      expectedRespostasHoje,
      'respostas_hoje',
    );
    _expectAtLeast(
      _asInt(stats['envios_total']),
      expectedEnviosTotal,
      'envios_total',
    );
    _expectAtLeast(
      _asInt(stats['respostas_total']),
      expectedRespostasTotal,
      'respostas_total',
    );

    final recentFound = enviosHoje.any(
      (row) => _asInt(row['id']) == envioId || row['mensagem_enviada'] == tag,
    );
    if (!recentFound) {
      throw StateError('Envio temporario nao apareceu em getEnviosHoje().');
    }

    if (!_hasTodayValue(enviosPorDia, 'sucesso_count')) {
      throw StateError('getEnviosPorDia() nao retornou valor para hoje.');
    }
    if (!_hasTodayValue(respostasPorDia, 'total')) {
      throw StateError(
        'getMensagensRecebidasPorDia() nao retornou valor para hoje.',
      );
    }
    _validateChartNumericMapping(enviosPorDia, respostasPorDia);

    stdout.writeln('dashboard_smoke_ok');
    stdout.writeln('dbReady=${service.isReady}');
    stdout.writeln('enviosHoje=${stats['envios_hoje']}');
    stdout.writeln('respostasHoje=${stats['respostas_hoje']}');
    stdout.writeln('enviosTotal=${stats['envios_total']}');
    stdout.writeln('respostasTotal=${stats['respostas_total']}');
    stdout.writeln('recentRowFound=$recentFound');
    stdout.writeln('enviosPorDiaRows=${enviosPorDia.length}');
    stdout.writeln('respostasPorDiaRows=${respostasPorDia.length}');
  } finally {
    if (conversaId != null) {
      await db.execute(
        sql: 'DELETE FROM CONVERSAS WHERE ID = ?',
        parameters: [conversaId],
      );
    }
    if (envioId != null) {
      await db.execute(
        sql: 'DELETE FROM ENVIOS WHERE ID = ?',
        parameters: [envioId],
      );
    }
    await service.close();
  }
}

void _expectAtLeast(int actual, int expected, String label) {
  if (actual < expected) {
    throw StateError('$label esperado >= $expected, recebido $actual.');
  }
}

bool _hasTodayValue(List<Map<String, dynamic>> rows, String valueKey) {
  final now = DateTime.now();
  return rows.any((row) {
    final date = _parseDate(row['dia']);
    return date != null &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day &&
        _asInt(row[valueKey]) > 0;
  });
}

void _validateChartNumericMapping(
  List<Map<String, dynamic>> enviosPorDia,
  List<Map<String, dynamic>> respostasPorDia,
) {
  for (final row in enviosPorDia) {
    (row['sucesso_count'] ?? row['total'] ?? 0).toDouble();
  }
  for (final row in respostasPorDia) {
    (row['total'] ?? 0).toDouble();
  }
}

DateTime? _parseDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  return null;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
