import 'dart:io';

import 'package:money/data/datasources/database_service.dart';

Future<void> main() async {
  final service = DatabaseService.instance;
  final db = await service.database;
  final visibleFrom = await service.ensureChatVisibleFrom();
  final tag = '__chat_smoke_${DateTime.now().microsecondsSinceEpoch}__';
  final phone = '55988887777';
  final inboundAt = DateTime.now().add(const Duration(seconds: 1));
  final manualAt = inboundAt.add(const Duration(seconds: 1));

  int? inboundId;
  int? duplicateInboundId;
  int? manualId;
  int? envioId;

  try {
    inboundId = await service.registrarMensagem(
      telefone: phone,
      nomeCliente: 'Chat Smoke',
      destinoEnvio: phone,
      direcao: 'recebida',
      conteudo: '$tag recebida',
      tipoMsg: 'texto',
      mensagemId: '${tag}_in',
      registradoEm: inboundAt,
    );
    duplicateInboundId = await service.registrarMensagem(
      telefone: phone,
      nomeCliente: 'Chat Smoke',
      destinoEnvio: phone,
      direcao: 'recebida',
      conteudo: '$tag recebida duplicada',
      tipoMsg: 'texto',
      mensagemId: '${tag}_in',
      registradoEm: inboundAt.add(const Duration(seconds: 10)),
    );
    manualId = await service.registrarMensagem(
      telefone: phone,
      nomeCliente: 'Chat Smoke',
      destinoEnvio: phone,
      direcao: 'enviada_manual',
      conteudo: '$tag manual',
      tipoMsg: 'texto',
      mensagemId: '${tag}_manual',
      registradoEm: manualAt,
    );
    envioId = await service.registrarEnvio(
      telefoneCompleto: phone,
      nomeCliente: 'Chat Smoke',
      sucesso: true,
      mensagemStatus: 'Smoke massa OK',
      mensagemEnviada: '$tag massa',
      tipo: 'massa',
    );

    if (duplicateInboundId != inboundId) {
      throw StateError('Deduplicacao por mensagemId falhou.');
    }

    final contacts = await service.getChatContacts(visibleFrom: visibleFrom);
    Map<String, dynamic>? contact;
    for (final row in contacts) {
      if (row['telefone'] == phone) {
        contact = row;
        break;
      }
    }
    if (contact == null) {
      throw StateError('Contato temporario nao apareceu em getChatContacts().');
    }
    if ((contact['nome_cliente'] ?? '').toString() != 'Chat Smoke') {
      throw StateError(
        'Nome do contato veio incorreto: ${contact['nome_cliente']}',
      );
    }
    if ((contact['ultima_mensagem'] ?? '').toString() != '$tag manual') {
      throw StateError(
        'Preview deveria usar a ultima mensagem manual, veio: '
        '${contact['ultima_mensagem']}',
      );
    }
    final lastInteraction = _parseDate(contact['ultima_interacao']);
    if (lastInteraction == null ||
        lastInteraction.isBefore(
          manualAt.subtract(const Duration(seconds: 1)),
        )) {
      throw StateError(
        'Ultima interacao nao refletiu a mensagem manual recente: '
        '${contact['ultima_interacao']}',
      );
    }

    final timeline = await service.getConversationTimeline(
      phone,
      visibleFrom: visibleFrom,
    );
    final directions = timeline
        .map((row) => row['direcao'].toString())
        .toList();
    if (!directions.contains('recebida') ||
        !directions.contains('enviada_manual') ||
        !directions.contains('enviada')) {
      throw StateError('Timeline incompleta: $directions');
    }

    stdout.writeln('chat_smoke_ok');
    stdout.writeln('dbReady=${service.isReady}');
    stdout.writeln('contacts=${contacts.length}');
    stdout.writeln('timeline=${timeline.length}');
    stdout.writeln('directions=${directions.join(',')}');
  } finally {
    if (manualId != null) {
      await db.execute(
        sql: 'DELETE FROM CONVERSAS WHERE ID = ?',
        parameters: [manualId],
      );
    }
    if (duplicateInboundId != null && duplicateInboundId != inboundId) {
      await db.execute(
        sql: 'DELETE FROM CONVERSAS WHERE ID = ?',
        parameters: [duplicateInboundId],
      );
    }
    if (inboundId != null) {
      await db.execute(
        sql: 'DELETE FROM CONVERSAS WHERE ID = ?',
        parameters: [inboundId],
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

DateTime? _parseDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  return null;
}
