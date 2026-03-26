import '../../data/models/instance_connection_state.dart';
import '../../data/models/message_job.dart';
import '../../data/models/qr_code_response.dart';
import '../../data/models/send_result.dart';

abstract class EvolutionRepository {
  Future<void> ensureMoneyInstance();
  Future<void> disconnectInstance();
  Future<QrCodeResponse> getQrCode();
  Future<InstanceConnectionState> getConnectionState();
  Future<List<SendResult>> sendBulkMessages({
    required List<MessageJob> jobs,
    required int minIntervalSeconds,
    required int maxIntervalSeconds,
    bool enforceDuplicateGuard = true,
    bool Function()? isCancelled,
  });
}
