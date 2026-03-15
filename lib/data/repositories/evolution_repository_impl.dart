import 'dart:math';

import '../../domain/repositories/evolution_repository.dart';
import '../datasources/evolution_api_service.dart';
import '../models/instance_connection_state.dart';
import '../models/message_job.dart';
import '../models/qr_code_response.dart';
import '../models/send_result.dart';

class EvolutionRepositoryImpl implements EvolutionRepository {
  EvolutionRepositoryImpl(this._service);

  final EvolutionApiService _service;
  final Random _random = Random();

  @override
  Future<void> ensureMoneyInstance() {
    return _service.createMoneyInstance();
  }

  @override
  Future<QrCodeResponse> getQrCode() {
    return _service.getQrCode();
  }

  @override
  Future<InstanceConnectionState> getConnectionState() {
    return _service.getConnectionState();
  }

  @override
  Future<List<SendResult>> sendBulkMessages({
    required List<MessageJob> jobs,
    required int minIntervalSeconds,
    required int maxIntervalSeconds,
  }) async {
    final results = <SendResult>[];
    final safeMin = minIntervalSeconds < 1 ? 1 : minIntervalSeconds;
    final safeMax = maxIntervalSeconds < safeMin ? safeMin : maxIntervalSeconds;

    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];

      try {
        for (int m = 0; m < job.renderedMessages.length; m++) {
          final msg = job.renderedMessages[m];
          
          // Anti-ban: Simular tempo de digitação real (media: ~50-100ms por caractere)
          final typingTimeMs = msg.length * (50 + _random.nextInt(50));
          final baseDelayMs = 1500 + _random.nextInt(1000); // tempo de "abrir o chat"
          final totalPresenceDelayMs = baseDelayMs + typingTimeMs;
          
          // Cap máximo de 12 segundos de digitando pra n ficar travado mt tempo
          final safePresenceDelay = totalPresenceDelayMs > 12000 ? 12000 : totalPresenceDelayMs;

          await _service.sendText(
            number: job.data.phone, 
            text: msg,
            delay: safePresenceDelay,
          );

          if (m < job.renderedMessages.length - 1) {
            // Anti-ban: Delay mais humano entre multiplos balões de texto (2 a 5 segs)
            final betweenMsgsDelay = 2 + _random.nextInt(4);
            await Future<void>.delayed(Duration(seconds: betweenMsgsDelay));
          }
        }

        results.add(
          SendResult(
            phone: job.data.phone,
            success: true,
            message: 'Enviado com sucesso',
          ),
        );
      } catch (e) {
        results.add(
          SendResult(
            phone: job.data.phone,
            success: false,
            message: e.toString(),
          ),
        );
      }

      final isLast = i == jobs.length - 1;
      if (!isLast) {
        // Anti-ban: Adicionado jitter em milissegundos pra o intervalo não ser um número redondo sempre
        final nextSeconds = safeMin + _random.nextInt((safeMax - safeMin) + 1);
        final nextMs = _random.nextInt(1000); 
        await Future<void>.delayed(Duration(seconds: nextSeconds, milliseconds: nextMs));
      }
    }

    return results;
  }
}
