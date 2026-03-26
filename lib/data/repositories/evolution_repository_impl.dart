import 'dart:math';

import '../../domain/repositories/evolution_repository.dart';
import '../datasources/evolution_api_service.dart';
import '../datasources/send_history_service.dart';
import '../models/instance_connection_state.dart';
import '../models/message_job.dart';
import '../models/qr_code_response.dart';
import '../models/send_result.dart';

class EvolutionRepositoryImpl implements EvolutionRepository {
  EvolutionRepositoryImpl(this._service, this._sendHistoryService);

  final EvolutionApiService _service;
  final SendHistoryService _sendHistoryService;
  final Random _random = Random();

  @override
  Future<void> ensureMoneyInstance() {
    return _service.createMoneyInstance();
  }

  @override
  Future<void> disconnectInstance() {
    return _service.disconnectInstance();
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
    bool enforceDuplicateGuard = true,
    bool Function()? isCancelled,
  }) async {
    final results = <SendResult>[];
    final safeMin = minIntervalSeconds < 1 ? 1 : minIntervalSeconds;
    final safeMax = maxIntervalSeconds < safeMin ? safeMin : maxIntervalSeconds;

    if (enforceDuplicateGuard) {
      await _sendHistoryService.warmUpRemoteHistory();
    }

    for (var i = 0; i < jobs.length; i++) {
      // ── Verificar cancelamento antes de processar cada job ──
      if (isCancelled?.call() == true) break;

      final job = jobs[i];
      var shouldSkipNumber = false;
      var skipReason = '';

      if (enforceDuplicateGuard) {
        final sentRecently = await _sendHistoryService.wasSentInLastDays(
          job.data.phone,
          days: SendHistoryService.defaultLookbackDays,
        );

        if (sentRecently) {
          shouldSkipNumber = true;
          skipReason = 'Pulado: numero ja recebeu mensagem nos ultimos 30 dias.';
        } else {
          final sentByEvolution = await _sendHistoryService
              .wasSentByEvolutionHistory(
                job.data.phone,
                days: SendHistoryService.defaultLookbackDays,
              );
          if (sentByEvolution) {
            shouldSkipNumber = true;
            skipReason =
                'Pulado: numero ja possui envio registrado na instancia.';
          }
        }
      }

      if (shouldSkipNumber) {
        results.add(
          SendResult(
            phone: job.data.phone,
            success: false,
            message: skipReason,
          ),
        );
        continue;
      }

      try {
        for (int m = 0; m < job.renderedMessages.length; m++) {
          // ── Verificar cancelamento antes de cada mensagem ──
          if (isCancelled?.call() == true) break;

          final msg = job.renderedMessages[m];

          // ── 1. Disparar "Digitando..." via presença ──
          await _service.sendPresence(
            number: job.data.phone,
            presence: 'composing',
          );

          // ── 2. Simular tempo de digitação real ──
          final typingTimeMs = msg.length * (50 + _random.nextInt(50));
          final baseDelayMs = 1500 + _random.nextInt(1000);
          final totalPresenceDelayMs = baseDelayMs + typingTimeMs;
          final safePresenceDelay =
              totalPresenceDelayMs > 12000 ? 12000 : totalPresenceDelayMs;

          // Delay cancelável — verifica cancelamento a cada ~200ms
          final wasCancelled = await _cancellableDelay(
            Duration(milliseconds: safePresenceDelay),
            isCancelled,
          );
          if (wasCancelled) break;

          // ── 3. Enviar a mensagem de fato ──
          await _service.sendText(
            number: job.data.phone,
            text: msg,
            delay: 0,
          );

          // ── 4. Encerrar indicador de digitando ──
          await _service.sendPresence(
            number: job.data.phone,
            presence: 'paused',
          );

          if (m < job.renderedMessages.length - 1) {
            // Anti-ban: Delay cancelável entre múltiplos balões
            final betweenMsgsDelay = 2 + _random.nextInt(4);
            final cancelled = await _cancellableDelay(
              Duration(seconds: betweenMsgsDelay),
              isCancelled,
            );
            if (cancelled) break;
          }
        }

        // Se foi cancelado no meio das mensagens, não marca como sucesso
        if (isCancelled?.call() == true) break;

        results.add(
          SendResult(
            phone: job.data.phone,
            success: true,
            message: 'Enviado com sucesso',
          ),
        );
        await _sendHistoryService.saveSuccessfulSend(job.data.phone);
      } catch (e) {
        results.add(
          SendResult(
            phone: job.data.phone,
            success: false,
            message: e.toString(),
          ),
        );
      }

      // ── Verificar cancelamento antes do delay entre clientes ──
      if (isCancelled?.call() == true) break;

      final isLast = i == jobs.length - 1;
      if (!isLast) {
        final nextSeconds = safeMin + _random.nextInt((safeMax - safeMin) + 1);
        final nextMs = _random.nextInt(1000);
        final cancelled = await _cancellableDelay(
          Duration(seconds: nextSeconds, milliseconds: nextMs),
          isCancelled,
        );
        if (cancelled) break;
      }
    }

    return results;
  }

  /// Delay que verifica cancelamento a cada ~200ms.
  /// Retorna `true` se foi cancelado antes do tempo total acabar.
  Future<bool> _cancellableDelay(
    Duration total,
    bool Function()? isCancelled,
  ) async {
    const tick = Duration(milliseconds: 200);
    var remaining = total;

    while (remaining > Duration.zero) {
      if (isCancelled?.call() == true) return true;

      final wait = remaining < tick ? remaining : tick;
      await Future<void>.delayed(wait);
      remaining -= wait;
    }

    return isCancelled?.call() == true;
  }
}
