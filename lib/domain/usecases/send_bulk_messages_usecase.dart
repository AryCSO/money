import '../../data/models/message_job.dart';
import '../../data/models/send_result.dart';
import '../repositories/evolution_repository.dart';

class SendBulkMessagesUseCase {
  SendBulkMessagesUseCase(this._repository);

  final EvolutionRepository _repository;

  Future<List<SendResult>> call({
    required List<MessageJob> jobs,
    required int minIntervalSeconds,
    required int maxIntervalSeconds,
    bool enforceDuplicateGuard = true,
    bool Function()? isCancelled,
  }) {
    return _repository.sendBulkMessages(
      jobs: jobs,
      minIntervalSeconds: minIntervalSeconds,
      maxIntervalSeconds: maxIntervalSeconds,
      enforceDuplicateGuard: enforceDuplicateGuard,
      isCancelled: isCancelled,
    );
  }
}
